import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_mapper.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

typedef ContactsSnapshotFetch = Future<SyncSnapshotPage> Function({
  required String domain,
  String cursor,
  String? snapshotRevision,
  int limit,
});

typedef ContactsChangesFetch = Future<SyncChangesPage> Function({
  required String domain,
  String afterRevision,
  String cursor,
  int limit,
});

class ContactsProtocolSyncService with WidgetsBindingObserver {
  ContactsProtocolSyncService._()
      : _fetchSnapshot = null,
        _fetchChanges = null,
        _pacer = RestoreWorkPacer.instance,
        _captureIdentity = null;

  ContactsProtocolSyncService.forTest({
    required ContactsSnapshotFetch fetchSnapshot,
    required ContactsChangesFetch fetchChanges,
    RestoreWorkPacer? pacer,
    SessionIdentity Function()? captureIdentity,
  })  : _fetchSnapshot = fetchSnapshot,
        _fetchChanges = fetchChanges,
        _pacer = pacer ?? RestoreWorkPacer.instance,
        _captureIdentity = captureIdentity;

  static final ContactsProtocolSyncService instance =
      ContactsProtocolSyncService._();

  static const _maxPages = 10000;
  static const _domain = 'contacts';

  final ContactsSnapshotFetch? _fetchSnapshot;
  final ContactsChangesFetch? _fetchChanges;
  final RestoreWorkPacer _pacer;
  final SessionIdentity Function()? _captureIdentity;

  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Set<String> _pending = <String>{};
  final Set<String> _projectedSessions = <String>{};
  Timer? _catchUpTimer;
  bool _attached = false;

  Future<void> attach() async {
    if (!_attached) {
      _attached = true;
      FriendRealtimeService.instance.addAuthOkListener(_onAuthOk);
      WidgetsBinding.instance.addObserver(this);
      _catchUpTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(sync(reason: 'foreground_catch_up'));
        }
      });
    }
    await sync(reason: 'home_bind');
  }

  void detach() {
    FriendRealtimeService.instance.removeAuthOkListener(_onAuthOk);
    WidgetsBinding.instance.removeObserver(this);
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _attached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_attached && state == AppLifecycleState.resumed) {
      unawaited(sync(reason: 'foreground_resume'));
    }
  }

  void _onAuthOk() {
    unawaited(sync(reason: 'tcp_auth_ok'));
  }

  Future<void> clearSession({String? ownerUserId}) async {
    detach();
    _inFlight.clear();
    _pending.clear();
    _projectedSessions.clear();
  }

  Future<void> sync({required String reason}) {
    final identity = _identity();
    if (identity.ownerUserId.isEmpty) {
      return Future<void>.value();
    }
    final key = '${identity.ownerUserId}|${identity.generation}';
    final active = _inFlight[key];
    if (active != null) {
      // The running request may have been captured before this mutation.
      _pending.add(key);
      return active;
    }
    late final Future<void> task;
    task = (() async {
      do {
        _pending.remove(key);
        await _syncOnce(
          identity: identity,
          reason: reason,
          allowSnapshotRestart: true,
        );
      } while (_isCurrent(identity) && _pending.remove(key));
    })()
        .whenComplete(() {
      if (identical(_inFlight[key], task)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = task;
    return task;
  }

  SessionIdentity _identity() {
    return _captureIdentity?.call() ??
        SessionIdentityService.instance.capture();
  }

  bool _isCurrent(SessionIdentity identity) {
    if (_captureIdentity != null) {
      return identity.ownerUserId.isNotEmpty &&
          identity == _captureIdentity!.call();
    }
    return SessionIdentityService.instance.isCurrent(identity);
  }

  Future<SyncSnapshotPage> _snapshot({
    required String cursor,
    String? snapshotRevision,
  }) {
    final fetch = _fetchSnapshot;
    if (fetch != null) {
      return fetch(
        domain: _domain,
        cursor: cursor,
        snapshotRevision: snapshotRevision,
        limit: 200,
      );
    }
    return SyncProtocolApi.instance.fetchSnapshot(
      domain: _domain,
      cursor: cursor,
      snapshotRevision: snapshotRevision,
      limit: 200,
    );
  }

  Future<SyncChangesPage> _changes({
    required String afterRevision,
    required String cursor,
  }) {
    final fetch = _fetchChanges;
    if (fetch != null) {
      return fetch(
        domain: _domain,
        afterRevision: afterRevision,
        cursor: cursor,
        limit: 200,
      );
    }
    return SyncProtocolApi.instance.fetchChanges(
      domain: _domain,
      afterRevision: afterRevision,
      cursor: cursor,
      limit: 200,
    );
  }

  Future<void> _syncOnce({
    required SessionIdentity identity,
    required String reason,
    required bool allowSnapshotRestart,
  }) async {
    final owner = identity.ownerUserId;
    final sessionKey = '$owner|${identity.generation}';
    try {
      if (!_projectedSessions.contains(sessionKey)) {
        final cached =
            await FriendLocalStore.instance.readAll(ownerUserId: owner);
        if (!_isCurrent(identity)) return;
        await _projectSnapshot(
            identity: identity, before: cached, after: cached);
        _projectedSessions.add(sessionKey);
      }
      final job = await FriendLocalStore.instance.readSyncJob(
        ownerUserId: owner,
      );
      final revision = job?['snapshot_revision']?.toString().trim() ?? '';
      final state = job?['state']?.toString() ?? '';
      if (revision.isEmpty || state != 'completed') {
        await _runSnapshot(
          identity: identity,
          owner: owner,
          job: job,
        );
      }
      if (!_isCurrent(identity)) {
        return;
      }
      await _runChanges(identity: identity, owner: owner);
    } on SyncProtocolException catch (error) {
      if (!_isCurrent(identity)) {
        return;
      }
      if (_isTerminalAuth(error)) {
        return;
      }
      if (allowSnapshotRestart &&
          (error.snapshotExpired ||
              error.revisionTooOld ||
              _isCursorResetCode(error.code))) {
        await FriendLocalStore.instance.clearSyncJob(ownerUserId: owner);
        await FriendLocalStore.instance.clearProtocolStaging(
          ownerUserId: owner,
        );
        await FriendLocalStore.instance.clearProtocolEvents(
          ownerUserId: owner,
        );
        await _syncOnce(
          identity: identity,
          reason: '${reason}_snapshot_restart',
          allowSnapshotRestart: false,
        );
        return;
      }
      if (kDebugMode) {
        debugPrint(
          'ContactsProtocolSync: failed reason=$reason code=${error.code}',
        );
      }
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint('ContactsProtocolSync: invalid reason=$reason error=$error');
      }
    } catch (error) {
      _projectedSessions.remove(sessionKey);
      // A successful mutation must not become a failed operation because its
      // catch-up request failed. Reconnect/resume/foreground timer retries it.
      if (kDebugMode) {
        debugPrint(
            'ContactsProtocolSync: retry pending reason=$reason error=$error');
      }
    }
  }

  bool _isTerminalAuth(SyncProtocolException error) {
    final code = error.code.trim().toUpperCase();
    return code == 'UNAUTHORIZED' ||
        code == 'AUTH_EXPIRED' ||
        code.contains('401');
  }

  bool _isCursorResetCode(String code) {
    switch (code.trim().toUpperCase()) {
      case 'SNAPSHOT_REQUIRED':
      case 'SNAPSHOT_EXPIRED':
      case 'INVALID_CURSOR':
      case 'CURSOR_INVALID':
      case 'CURSOR_EXPIRED':
      case 'REVISION_TOO_OLD':
      case 'SEQ_EXPIRED':
        return true;
      default:
        return false;
    }
  }

  Future<void> _runSnapshot({
    required SessionIdentity identity,
    required String owner,
    required Map<String, Object?>? job,
  }) async {
    var cursor = '';
    String? revision;
    final jobState = job?['state']?.toString() ?? '';
    if (jobState == 'snapshot') {
      cursor = job?['next_cursor']?.toString() ?? '';
      final existing = job?['snapshot_revision']?.toString().trim() ?? '';
      if (existing.isNotEmpty) {
        revision = existing;
      }
    }
    for (var page = 0; page < _maxPages; page++) {
      if (!await _pacer.beforePage(
        isCurrent: () => _isCurrent(identity),
        firstPage: page == 0,
      )) {
        return;
      }
      final response = await _snapshot(
        cursor: cursor,
        snapshotRevision: revision,
      );
      if (!_isCurrent(identity)) {
        return;
      }
      revision ??= response.snapshotRevision.trim();
      if (revision.isEmpty || response.snapshotRevision.trim() != revision) {
        throw const FormatException('contacts snapshot revision changed');
      }
      if (response.items.isNotEmpty) {
        await FriendLocalStore.instance.stageProtocolItems(
          ownerUserId: owner,
          snapshotRevision: revision,
          items: response.items,
        );
      }
      if (response.hasMore) {
        if (response.nextCursor.isEmpty || response.nextCursor == cursor) {
          throw const FormatException(
              'contacts snapshot cursor did not advance');
        }
        cursor = response.nextCursor;
        await FriendLocalStore.instance.saveSyncJob(
          ownerUserId: owner,
          snapshotRevision: revision,
          nextCursor: cursor,
          hasMore: true,
          persistedCount: 0,
          state: 'snapshot',
        );
      } else {
        final records = await FriendLocalStore.instance.readProtocolStaging(
          ownerUserId: owner,
          snapshotRevision: revision,
        );
        if (response.estimatedTotal != null &&
            records.length != response.estimatedTotal) {
          throw const FormatException('contacts snapshot total mismatch');
        }
        final before = await FriendLocalStore.instance.readAll(
          ownerUserId: owner,
        );
        await FriendLocalStore.instance.publishProtocolSnapshot(
          ownerUserId: owner,
          snapshotRevision: revision,
          records: records,
          replaceAbsent: true,
        );
        await FriendLocalStore.instance.saveSyncJob(
          ownerUserId: owner,
          snapshotRevision: revision,
          nextCursor: '',
          hasMore: false,
          persistedCount: records.length,
          state: 'completed',
        );
        final after = await FriendLocalStore.instance.readAll(
          ownerUserId: owner,
        );
        await _projectSnapshot(
            identity: identity, before: before, after: after);
        return;
      }
      if (page == _maxPages - 1) {
        throw StateError('contacts snapshot page budget');
      }
    }
    if (revision == null || revision.isEmpty) {
      throw const FormatException('contacts snapshot revision required');
    }
  }

  Future<void> _runChanges({
    required SessionIdentity identity,
    required String owner,
  }) async {
    final job = await FriendLocalStore.instance.readSyncJob(
      ownerUserId: owner,
    );
    var revision = job?['snapshot_revision']?.toString().trim() ?? '';
    if (revision.isEmpty) {
      return;
    }
    var cursor = job?['next_cursor']?.toString() ?? '';
    for (var page = 0; page < _maxPages; page++) {
      if (!await _pacer.beforePage(
        isCurrent: () => _isCurrent(identity),
      )) {
        return;
      }
      final response = await _changes(
        afterRevision: revision,
        cursor: cursor,
      );
      if (!_isCurrent(identity)) {
        return;
      }
      for (final event in response.events) {
        if (!_isCurrent(identity)) {
          return;
        }
        await _applyAndProject(identity: identity, owner: owner, event: event);
      }
      if (response.hasMore) {
        if (response.nextCursor.isEmpty || response.nextCursor == cursor) {
          throw const FormatException(
              'contacts changes cursor did not advance');
        }
        cursor = response.nextCursor;
        await FriendLocalStore.instance.saveSyncJob(
          ownerUserId: owner,
          snapshotRevision: revision,
          nextCursor: cursor,
          hasMore: true,
          persistedCount: 0,
          state: 'completed',
        );
      } else {
        final nextRevision = response.toRevision.trim();
        if (nextRevision.isEmpty) {
          throw const FormatException('contacts changes toRevision required');
        }
        await FriendLocalStore.instance.saveSyncJob(
          ownerUserId: owner,
          snapshotRevision: nextRevision,
          nextCursor: '',
          hasMore: false,
          persistedCount: 0,
          state: 'completed',
        );
        return;
      }
      if (page == _maxPages - 1) {
        throw StateError('contacts changes page budget');
      }
    }
  }

  Future<void> _applyAndProject({
    required SessionIdentity identity,
    required String owner,
    required SyncChangeEvent event,
  }) async {
    final id = ChatIdFormat.rawUserUid(event.id);
    if (id.isEmpty) {
      return;
    }
    final beforeRows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[id],
    );
    final before = beforeRows.isEmpty ? null : beforeRows.first;
    final record = meFriendRecordFromSyncChangeEvent(event);
    final applied = await FriendLocalStore.instance.applyProtocolChange(
      ownerUserId: owner,
      event: event,
      record: record,
    );
    if (!_isCurrent(identity) || !applied) {
      return;
    }
    MeFriendApi.instance.invalidateRelation(id);
    C2cFriendMessageGuard.invalidate(id, clearTrusted: true);
    if (event.isDelete) {
      ImSdkRelationshipDirectory.instance.applyFriendRemoves([id]);
      PeerProfileRefreshBus.instance.notify(id);
      return;
    }
    final afterRows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[id],
    );
    if (afterRows.isEmpty) {
      return;
    }
    if (!_isCurrent(identity)) return;
    final after = afterRows.first;
    ImSdkRelationshipDirectory.instance.applyFriendAdds([
      ImSdkRelationshipReconcileService.friendEntryFromSdk(
          after.toV2TimFriendInfo()),
    ]);
    PeerProfileRefreshBus.instance.notify(id);
    final remarkChanged = (before?.remark ?? '') != after.remark;
    final nicknameChanged =
        (before?.friendNickname ?? '') != after.friendNickname;
    final avatarChanged =
        (before?.friendAvatarUrl ?? '') != after.friendAvatarUrl;
    await FriendSyncService.instance.publishProtocolFriendProjection(
      after: after,
      remarkChanged: remarkChanged,
      nicknameChanged: nicknameChanged,
      avatarChanged: avatarChanged,
    );
  }

  Future<void> _projectSnapshot({
    required SessionIdentity identity,
    required List<MeFriendRecord> before,
    required List<MeFriendRecord> after,
  }) async {
    if (!_isCurrent(identity)) return;
    final directory = ImSdkRelationshipDirectory.instance;
    final entries = [
      for (final record in after)
        ImSdkRelationshipReconcileService.friendEntryFromSdk(
            record.toV2TimFriendInfo()),
    ];
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: entries,
    );
    for (final id in {
      ...before.map((r) => r.friendUserId),
      ...after.map((r) => r.friendUserId)
    }) {
      MeFriendApi.instance.invalidateRelation(id);
      C2cFriendMessageGuard.invalidate(id, clearTrusted: true);
      PeerProfileRefreshBus.instance.notify(id);
    }
    final beforeById = <String, MeFriendRecord>{
      for (final record in before)
        ChatIdFormat.rawUserUid(record.friendUserId): record,
    };
    for (final record in after) {
      if (!_isCurrent(identity)) return;
      final id = ChatIdFormat.rawUserUid(record.friendUserId);
      if (id.isEmpty) {
        continue;
      }
      final previous = beforeById[id];
      final remarkChanged = (previous?.remark ?? '') != record.remark;
      final nicknameChanged =
          (previous?.friendNickname ?? '') != record.friendNickname;
      final avatarChanged =
          (previous?.friendAvatarUrl ?? '') != record.friendAvatarUrl;
      await FriendSyncService.instance.publishProtocolFriendProjection(
        after: record,
        remarkChanged: remarkChanged,
        nicknameChanged: nicknameChanged,
        avatarChanged: avatarChanged,
      );
    }
  }
}
