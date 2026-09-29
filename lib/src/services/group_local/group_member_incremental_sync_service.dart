import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_member_change.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_realtime_cursor_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

typedef GroupMemberChangesFetcher = Future<GroupMemberChangesPage> Function(
  String groupId,
  int sinceSeq,
  int limit,
);
typedef GroupMembersSnapshotFetcher = Future<GroupMembersPage> Function(
  String groupId,
  int limit,
  int offset,
);
typedef GroupMemberEventApplier = Future<void> Function(
  String ownerUserId,
  String groupId,
  GroupMemberChangeEvent event,
);
typedef GroupMembersSnapshotReplacer = Future<void> Function(
  String ownerUserId,
  String groupId,
  List<GroupMemberRecord> records,
);
typedef GroupMemberCursorReader = Future<int> Function(
  String ownerUserId,
  String groupId,
);
typedef GroupMemberCursorWriter = Future<void> Function(
  int seq,
  String ownerUserId,
  String groupId,
);
typedef GroupMemberCursorClearer = Future<void> Function(
  String ownerUserId,
  String groupId,
);

/// Applies member-stream cursors and repairs gaps from the server change log.
/// A cursor only advances across contiguous events; expired cursors fall back
/// to a complete paginated member snapshot before establishing a new baseline.
class GroupMemberIncrementalSyncService {
  GroupMemberIncrementalSyncService._() {
    _ownerResolver = _readCurrentOwner;
    _readCursorImpl =
        (owner, group) => GroupMemberLocalStore.instance.readIncrementalCursor(
              ownerUserId: owner,
              groupId: group,
            );
    _writeCursorImpl = (seq, owner, group) =>
        GroupMemberLocalStore.instance.advanceIncrementalCursor(
          ownerUserId: owner,
          groupId: group,
          memberSeq: seq,
        );
    _clearCursorImpl =
        (owner, group) => GroupMemberLocalStore.instance.clearIncrementalCursor(
              ownerUserId: owner,
              groupId: group,
            );
    _fetchChangesImpl =
        (group, since, limit) => MeGroupApi.instance.fetchGroupMemberChanges(
              groupId: group,
              sinceSeq: since,
              limit: limit,
            );
    _fetchSnapshotImpl =
        (group, limit, offset) => MeGroupApi.instance.fetchGroupMembersPage(
              groupId: group,
              limit: limit,
              offset: offset,
            );
    _applyEventImpl = (owner, group, event) {
      if (event.isUpserted) {
        final record = event.toMemberRecord(ownerUserId: owner);
        if (record == null) {
          throw const FormatException('invalid member upsert');
        }
        return GroupMemberLocalStore.instance.applyIncrementalEvent(
          ownerUserId: owner,
          groupId: group,
          memberSeq: event.seq,
          upsert: record,
        );
      }
      if (event.isRemoved && event.userId.trim().isNotEmpty) {
        return GroupMemberLocalStore.instance.applyIncrementalEvent(
          ownerUserId: owner,
          groupId: group,
          memberSeq: event.seq,
          removeUserId: event.userId,
        );
      }
      throw const FormatException('unsupported member change event');
    };
    _replaceSnapshotImpl = (owner, group, records) =>
        GroupMemberLocalStore.instance.replaceSnapshot(
          ownerUserId: owner,
          groupId: group,
          records: records,
        );
    _identitylessForTesting = false;
  }

  @visibleForTesting
  GroupMemberIncrementalSyncService.forTesting({
    required String ownerUserId,
    required GroupMemberCursorReader readCursor,
    required GroupMemberCursorWriter writeCursor,
    required GroupMemberCursorClearer clearCursor,
    required GroupMemberChangesFetcher fetchChanges,
    required GroupMembersSnapshotFetcher fetchSnapshot,
    required GroupMemberEventApplier applyEvent,
    required GroupMembersSnapshotReplacer replaceSnapshot,
  }) {
    _ownerResolver = () => ownerUserId;
    _readCursorImpl = readCursor;
    _writeCursorImpl = writeCursor;
    _clearCursorImpl = clearCursor;
    _fetchChangesImpl = fetchChanges;
    _fetchSnapshotImpl = fetchSnapshot;
    _applyEventImpl = applyEvent;
    _replaceSnapshotImpl = replaceSnapshot;
    _identitylessForTesting = true;
  }

  static final GroupMemberIncrementalSyncService instance =
      GroupMemberIncrementalSyncService._();

  static const int _changePageLimit = 100;
  static const int _maxChangePagesPerRepair = 20;
  static const int _snapshotPageLimit = 100;
  static const int _maxSnapshotPages = 1000;

  late final String Function() _ownerResolver;
  late final GroupMemberCursorReader _readCursorImpl;
  late final GroupMemberCursorWriter _writeCursorImpl;
  late final GroupMemberCursorClearer _clearCursorImpl;
  late final GroupMemberChangesFetcher _fetchChangesImpl;
  late final GroupMembersSnapshotFetcher _fetchSnapshotImpl;
  late final GroupMemberEventApplier _applyEventImpl;
  late final GroupMembersSnapshotReplacer _replaceSnapshotImpl;
  late final bool _identitylessForTesting;
  final Map<String, Future<void>> _repairsInFlight = <String, Future<void>>{};
  final Map<String, int> _repairTargetSeq = <String, int>{};
  final Map<String, Timer> _repairRetryTimers = <String, Timer>{};
  final Map<String, int> _repairRetryAttempts = <String, int>{};
  static const int _maxRepairRetries = 3;

  static String _readCurrentOwner() =>
      ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());

  /// Only explicit membership denial is terminal; generic 403/transport
  /// failures must not remove a group or discard its pending repair.
  static bool isMembershipDenied(Object error) =>
      (error is DioError &&
          MeGroupApi.readDioCode(error).trim().toUpperCase() ==
              'NOT_GROUP_MEMBER') ||
      (error is SyncProtocolException && error.code == 'NOT_GROUP_MEMBER') ||
      error is ImSdkGroupMembershipDenied;

  Future<int> readCursor({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner =
        ChatIdFormat.rawUserUid((ownerUserId ?? _ownerResolver()).trim());
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return 0;
    return _readCursorImpl(owner, gid);
  }

  Future<void> writeCursor(
    int seq, {
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner =
        ChatIdFormat.rawUserUid((ownerUserId ?? _ownerResolver()).trim());
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || seq < 0) return;
    await _writeCursorImpl(seq, owner, gid);
  }

  Future<void> clearCursor({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner =
        ChatIdFormat.rawUserUid((ownerUserId ?? _ownerResolver()).trim());
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return;
    await _clearCursorImpl(owner, gid);
  }

  Future<void> clearSession() async {
    // Cursors live with their member rows in SQLite and are cleared by the
    // account lifecycle's GroupMemberLocalStore.clearForOwner call.
  }

  Future<bool> shouldApplyRealtimeSeq({
    required String groupId,
    required int seq,
  }) async {
    if (seq <= 0) return true;
    final current = await readCursor(groupId: groupId);
    return GroupMemberRealtimeCursorPolicy.shouldApply(
      cursor: current,
      seq: seq,
    );
  }

  /// Advances a contiguous event directly. If a sequence is missing, replay
  /// the server change log; an expired cursor is repaired from a full snapshot.
  Future<void> noteRealtimeSeq({
    required String groupId,
    required int seq,
  }) async {
    if (seq <= 0) return;
    final owner = ChatIdFormat.rawUserUid(_ownerResolver());
    final gid = ChatIdFormat.normalizeGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return;

    final identity = _identitylessForTesting
        ? null
        : SessionIdentityService.instance.capture(ownerUserId: owner);
    bool isCurrent() =>
        identity == null || SessionIdentityService.instance.isCurrent(identity);
    final key = '${identity?.generation ?? 0}|$owner|$gid';

    try {
      final active = _repairsInFlight[key];
      if (active != null) {
        _repairTargetSeq.update(
          key,
          (current) => current > seq ? current : seq,
          ifAbsent: () => seq,
        );
        await active;
        if (isCurrent() && seq > await _readCursorImpl(owner, gid)) {
          // The active repair may have completed just before this higher
          // target was observed. Re-enter once after coalescing to avoid
          // losing that final notification at the completion boundary.
          await noteRealtimeSeq(groupId: gid, seq: seq);
        } else {
          _clearRepairRetry(key);
        }
        return;
      }

      final current = await _readCursorImpl(owner, gid);
      if (!isCurrent()) return;
      if (seq <= current) {
        _clearRepairRetry(key);
        return;
      }
      if (GroupMemberRealtimeCursorPolicy.shouldAdvance(
        cursor: current,
        seq: seq,
      )) {
        await _writeCursorImpl(seq, owner, gid);
        _clearRepairRetry(key);
        return;
      }

      _repairTargetSeq[key] = seq;
      late final Future<void> repair;
      repair = _drainGapRepair(
        key: key,
        owner: owner,
        groupId: gid,
        isCurrent: isCurrent,
      ).whenComplete(() {
        if (identical(_repairsInFlight[key], repair)) {
          _repairsInFlight.remove(key);
        }
        _repairTargetSeq.remove(key);
      });
      _repairsInFlight[key] = repair;
      await repair;
      if (isCurrent() && seq <= await _readCursorImpl(owner, gid)) {
        _clearRepairRetry(key);
      }
    } catch (error) {
      // The realtime callback is fire-and-forget. Preserve the committed
      // cursor and let the next event or foreground repair retry the gap.
      if (kDebugMode) {
        debugPrint('GroupMemberIncrementalSync: gap repair failed '
            'groupId=$gid seq=$seq error=$error');
      }
      if (isCurrent() && !isMembershipDenied(error)) {
        _scheduleRepairRetry(
          key: key,
          groupId: gid,
          seq: seq,
          isCurrent: isCurrent,
        );
      }
    }
  }

  Future<void> _drainGapRepair({
    required String key,
    required String owner,
    required String groupId,
    required bool Function() isCurrent,
  }) async {
    var pageBudget = _maxChangePagesPerRepair;
    while (isCurrent() && pageBudget-- > 0) {
      final target = _repairTargetSeq[key] ?? 0;
      var cursor = await _readCursorImpl(owner, groupId);
      if (cursor >= target) return;

      var caughtUp = false;
      try {
        caughtUp = await _replayChanges(
          owner: owner,
          groupId: groupId,
          fromCursor: cursor,
          targetSeq: target,
          isCurrent: isCurrent,
        );
      } on GroupMemberCursorExpiredException {
        caughtUp = false;
      }
      if (!isCurrent()) return;
      cursor = await _readCursorImpl(owner, groupId);
      if (caughtUp && cursor >= target) continue;

      final snapshotApplied = await _replaceWithSnapshot(
        owner: owner,
        groupId: groupId,
        baselineSeq: target,
        isCurrent: isCurrent,
      );
      if (!snapshotApplied || !isCurrent()) return;
      // A newer event may have arrived during the snapshot; loop and replay
      // from this committed baseline instead of silently skipping it.
    }
  }

  Future<bool> _replayChanges({
    required String owner,
    required String groupId,
    required int fromCursor,
    required int targetSeq,
    required bool Function() isCurrent,
  }) async {
    var cursor = fromCursor;
    for (var pageNumber = 0;
        pageNumber < _maxChangePagesPerRepair && cursor < targetSeq;
        pageNumber++) {
      final page = await _fetchChangesImpl(
        groupId,
        cursor,
        _changePageLimit,
      );
      if (!isCurrent()) return false;
      final events = List<GroupMemberChangeEvent>.of(page.events)
        ..sort((a, b) => a.seq.compareTo(b.seq));
      if (events.isEmpty) return false;

      for (final event in events) {
        if (event.seq <= cursor) continue;
        final eventGroupId = ChatIdFormat.normalizeGroupId(event.groupId);
        if (event.seq != cursor + 1 ||
            (eventGroupId.isNotEmpty && eventGroupId != groupId) ||
            (!event.isUpserted &&
                !(event.isRemoved && event.userId.trim().isNotEmpty))) {
          return false;
        }
        await _applyEventImpl(owner, groupId, event);
        if (!isCurrent()) return false;
        cursor = event.seq;
        if (cursor >= targetSeq) return true;
      }

      if (!page.hasMore || page.nextSeq <= cursor) return false;
    }
    return cursor >= targetSeq;
  }

  Future<bool> _replaceWithSnapshot({
    required String owner,
    required String groupId,
    required int baselineSeq,
    required bool Function() isCurrent,
  }) async {
    final records = <GroupMemberRecord>[];
    var offset = 0;
    for (var pageNumber = 0; pageNumber < _maxSnapshotPages; pageNumber++) {
      final page = await _fetchSnapshotImpl(
        groupId,
        _snapshotPageLimit,
        offset,
      );
      if (!isCurrent()) return false;
      records.addAll(page.items);
      final nextOffset = offset + page.items.length;
      final hasMore = page.hasMore ??
          (page.total > 0
              ? nextOffset < page.total
              : page.items.length == _snapshotPageLimit);
      if (!hasMore) {
        await _replaceSnapshotImpl(owner, groupId, records);
        if (!isCurrent()) return false;
        await _writeCursorImpl(baselineSeq, owner, groupId);
        return true;
      }
      if (page.items.isEmpty || nextOffset <= offset) return false;
      offset = nextOffset;
    }
    return false;
  }

  void _scheduleRepairRetry({
    required String key,
    required String groupId,
    required int seq,
    required bool Function() isCurrent,
  }) {
    if (_repairRetryTimers.containsKey(key)) return;
    final attempts = _repairRetryAttempts[key] ?? 0;
    if (attempts >= _maxRepairRetries) return;
    _repairRetryAttempts[key] = attempts + 1;
    final delay = Duration(seconds: 1 << attempts);
    _repairRetryTimers[key] = Timer(delay, () {
      _repairRetryTimers.remove(key);
      if (!isCurrent()) {
        _repairRetryAttempts.remove(key);
        _repairTargetSeq.remove(key);
        return;
      }
      final target = _repairTargetSeq[key] ?? seq;
      unawaited(noteRealtimeSeq(groupId: groupId, seq: target));
    });
  }

  void _clearRepairRetry(String key) {
    _repairRetryTimers.remove(key)?.cancel();
    _repairRetryAttempts.remove(key);
    _repairTargetSeq.remove(key);
  }
}
