import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_notice_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_system_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// v2 business sync for the three group-owned domains.
///
/// The existing group services remain the compatibility path.  This service
/// only reports `true` after a complete opaque-cursor snapshot/changes run;
/// callers can then skip their legacy offset/seq request for that run.
class GroupProtocolSyncService {
  GroupProtocolSyncService._();
  static final GroupProtocolSyncService instance = GroupProtocolSyncService._();

  static const _maxPages = 10000;
  static const _statePrefix = 'sync_v2_group_state_';
  static const _versionsPrefix = 'sync_v2_group_versions_';
  static const _eventsPrefix = 'sync_v2_group_events_';
  static const _maxRememberedEvents = 1000;
  final Map<String, Future<bool>> _inFlight = {};

  Future<bool> _coalescedSync(String domain,
      {String? groupId, required String reason}) {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return Future<bool>.value(false);
    final key =
        '${identity.ownerUserId}|${identity.generation}|$domain|${groupId ?? ''}';
    final active = _inFlight[key];
    if (active != null) return active;
    late final Future<bool> task;
    task =
        _syncDomain(domain, groupId: groupId, reason: reason).whenComplete(() {
      if (identical(_inFlight[key], task)) _inFlight.remove(key);
    });
    _inFlight[key] = task;
    return task;
  }

  Future<bool> syncGroups({String reason = 'manual'}) =>
      _coalescedSync('groups', reason: reason);

  Future<bool> syncGroupMembers(String groupId, {String reason = 'manual'}) {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isEmpty) return Future<bool>.value(false);
    return _coalescedSync('groupMembers', groupId: id, reason: reason);
  }

  Future<bool> syncGroupNotices({String reason = 'manual'}) =>
      _coalescedSync('groupNotices', reason: reason);

  Future<bool> _syncDomain(
    String domain, {
    String? groupId,
    required String reason,
    bool allowSnapshotRestart = true,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final owner = identity.ownerUserId;
    if (owner.isEmpty) return false;
    final scope = '$owner|$domain|${groupId ?? ''}';
    try {
      final prefs = await SharedPreferences.getInstance();
      var state = _readState(prefs, scope);
      final hasRevision = state.revision.isNotEmpty;
      if (!hasRevision || !state.snapshotDone) {
        await _runSnapshot(
          prefs,
          scope: scope,
          owner: owner,
          domain: domain,
          groupId: groupId,
          initialCursor: hasRevision ? state.cursor : '',
          initialRevision: hasRevision ? state.revision : null,
          identity: identity,
        );
        if (!SessionIdentityService.instance.isCurrent(identity)) return false;
        state = _readState(prefs, scope);
      }
      if (state.revision.isEmpty) return false;
      await _runChanges(
        prefs,
        scope: scope,
        owner: owner,
        domain: domain,
        groupId: groupId,
        revision: state.revision,
        cursor: state.cursor,
        identity: identity,
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) return false;
      if (kDebugMode) {
        debugPrint(
            'GroupProtocolSync: done domain=$domain groupId=${groupId ?? ''} reason=$reason');
      }
      return true;
    } on SyncProtocolException catch (error) {
      if (!SessionIdentityService.instance.isCurrent(identity)) return false;
      // A permission denial is not an unsupported protocol. Falling back
      // would repeat the same forbidden read through the REST member API.
      if (error.code == 'NOT_GROUP_MEMBER') rethrow;
      // A 410 means only this domain (or this group) lost its cursor. Clear
      // that scope and rebuild; do not fall back to a different domain or
      // reset unrelated account data.
      if (allowSnapshotRestart &&
          (error.snapshotExpired || _isCursorResetCode(error.code))) {
        final prefs = await SharedPreferences.getInstance();
        await _clearState(
          prefs,
          scope,
          owner: owner,
          domain: domain,
          groupId: groupId,
        );
        return _syncDomain(
          domain,
          groupId: groupId,
          reason: '${reason}_snapshot_restart',
          allowSnapshotRestart: false,
        );
      }
      // Missing rollout/route is intentionally left to the legacy service.
      if (kDebugMode) {
        debugPrint(
            'GroupProtocolSync: fallback domain=$domain code=${error.code}');
      }
      return false;
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint('GroupProtocolSync: invalid domain=$domain error=$error');
      }
      return false;
    }
  }

  Future<void> _clearState(
    SharedPreferences prefs,
    String scope, {
    required String owner,
    required String domain,
    String? groupId,
  }) async {
    await prefs.remove(_stateKey(scope));
    await prefs.remove(_versionsKey(scope));
    await prefs.remove(_eventsKey(scope));
    if (domain == 'groups') {
      await GroupLocalStore.instance.clearForOwner(owner);
    } else if (domain == 'groupMembers' && groupId != null) {
      await GroupMemberLocalStore.instance.clearGroup(
        ownerUserId: owner,
        groupId: groupId,
      );
    } else if (domain == 'groupNotices') {
      await GroupSystemNoticeService.instance.clearForOwner(owner);
      GroupSystemNoticeService.instance.clearSession();
    }
  }

  bool _isCursorResetCode(String code) {
    switch (code.trim().toUpperCase()) {
      case 'SNAPSHOT_REQUIRED':
      case 'INVALID_CURSOR':
      case 'CURSOR_INVALID':
      case 'CURSOR_EXPIRED':
      case 'REVISION_TOO_OLD':
        return true;
      default:
        return false;
    }
  }

  Future<void> _runSnapshot(
    SharedPreferences prefs, {
    required String scope,
    required String owner,
    required String domain,
    String? groupId,
    String initialCursor = '',
    String? initialRevision,
    required SessionIdentity identity,
  }) async {
    var cursor = initialCursor;
    String? revision = initialRevision;
    final pageVersions = _readVersions(prefs, _versionsKey(scope));
    for (var page = 0; page < _maxPages; page++) {
      if (!await RestoreWorkPacer.instance.beforePage(
        isCurrent: () => SessionIdentityService.instance.isCurrent(identity),
        firstPage: page == 0,
      )) {
        return;
      }
      final response = await SyncProtocolApi.instance.fetchSnapshot(
        accountId: owner,
        domain: domain,
        cursor: cursor,
        snapshotRevision: revision,
        groupId: groupId,
        limit: 200,
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      revision ??= response.snapshotRevision.trim();
      if (revision.isEmpty || response.snapshotRevision.trim() != revision) {
        throw const FormatException('group snapshot revision changed');
      }
      for (final item in response.items) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        await _applyItem(
          prefs: prefs,
          scope: scope,
          owner: owner,
          domain: domain,
          groupId: groupId,
          item: item,
          sharedVersions: pageVersions,
          persistVersion: false,
        );
      }
      await prefs.setString(_versionsKey(scope), jsonEncode(pageVersions));
      if (!response.hasMore) {
        // Some v2 servers echo the last opaque cursor on the terminal page.
        // v2 requires persisting that cursor as the next changes watermark.
        await _saveState(
          prefs,
          scope,
          _SyncState(
            revision: revision,
            cursor: response.nextCursor,
            snapshotDone: true,
          ),
        );
        break;
      }
      if (response.nextCursor.isEmpty || response.nextCursor == cursor) {
        throw const FormatException('group snapshot cursor did not advance');
      }
      cursor = response.nextCursor;
      await _saveState(
        prefs,
        scope,
        _SyncState(
          revision: revision,
          cursor: cursor,
          snapshotDone: false,
        ),
      );
      if (page == _maxPages - 1) throw StateError('group snapshot page budget');
    }
    if (revision == null || revision.isEmpty) {
      throw const FormatException('group snapshot revision required');
    }
  }

  Future<void> _runChanges(
    SharedPreferences prefs, {
    required String scope,
    required String owner,
    required String domain,
    String? groupId,
    required String revision,
    required String cursor,
    required SessionIdentity identity,
  }) async {
    var nextCursor = cursor;
    var currentRevision = revision;
    final pageVersions = _readVersions(prefs, _versionsKey(scope));
    final pageEvents = _readSet(prefs, _eventsKey(scope));
    for (var page = 0; page < _maxPages; page++) {
      if (!await RestoreWorkPacer.instance.beforePage(
        isCurrent: () => SessionIdentityService.instance.isCurrent(identity),
      )) {
        return;
      }
      final response = await SyncProtocolApi.instance.fetchChanges(
        accountId: owner,
        domain: domain,
        afterRevision: currentRevision,
        cursor: nextCursor,
        groupId: groupId,
        limit: 200,
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      for (final event in response.events) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        await _applyEvent(
          prefs,
          scope: scope,
          owner: owner,
          domain: domain,
          groupId: groupId,
          event: event,
          sharedVersions: pageVersions,
          sharedSeen: pageEvents,
          persistState: false,
        );
      }
      await prefs.setString(_versionsKey(scope), jsonEncode(pageVersions));
      await prefs.setStringList(
        _eventsKey(scope),
        pageEvents.toList(growable: false),
      );
      if (response.hasMore) {
        if (response.nextCursor.isEmpty || response.nextCursor == nextCursor) {
          throw const FormatException('group changes cursor did not advance');
        }
        nextCursor = response.nextCursor;
        await _saveState(
          prefs,
          scope,
          _SyncState(
            revision: currentRevision,
            cursor: nextCursor,
            snapshotDone: true,
          ),
        );
      } else {
        // A terminal changes page may also echo an opaque cursor.  Persist
        // only the revision and clear the cursor for the next poll.
        currentRevision = response.toRevision.trim();
        if (currentRevision.isEmpty) {
          throw const FormatException('group changes toRevision required');
        }
        await _saveState(
          prefs,
          scope,
          _SyncState(
            revision: currentRevision,
            cursor: response.nextCursor,
            snapshotDone: true,
          ),
        );
        return;
      }
      if (page == _maxPages - 1) throw StateError('group changes page budget');
    }
  }

  Future<void> _applyItem({
    required SharedPreferences prefs,
    required String scope,
    required String owner,
    required String domain,
    String? groupId,
    required SyncProtocolItem item,
    Map<String, int>? sharedVersions,
    bool persistVersion = true,
  }) async {
    final payload = Map<String, dynamic>.from(item.data);
    if (item.updatedAt > 0) {
      payload.putIfAbsent('updatedAt', () => item.updatedAt);
    }
    final entityKey = _entityKey(domain, item, payload, groupId);
    if (entityKey.isEmpty) return;
    final versions =
        sharedVersions ?? _readVersions(prefs, _versionsKey(scope));
    if (item.itemVersion > 0 &&
        (versions[entityKey] ?? -1) >= item.itemVersion) {
      return;
    }
    if (domain == 'groups') {
      final id =
          (payload['groupId'] ?? payload['group_id'] ?? item.id).toString();
      if (item.deleted) {
        await GroupLocalStore.instance.delete(ownerUserId: owner, groupId: id);
      } else if (id.trim().isNotEmpty) {
        // The v2 groups stream may contain display-only change events for
        // groups outside the account's current membership snapshot.  Those
        // events must never create a new local group; /me/groups is the
        // membership authority and will add legitimate new groups.
        if (GroupLocalStore.instance
                .readCached(groupId: id, ownerUserId: owner) ==
            null) {
          await _rememberVersion(
            prefs,
            scope,
            versions,
            entityKey,
            item.itemVersion,
            persist: persistVersion,
          );
          return;
        }
        final map = <String, dynamic>{
          ...payload,
          'groupId': id,
          'updatedAt': item.updatedAt,
        };
        map.remove('memberCount');
        map.remove('member_count');
        await GroupLocalStore.instance.upsert(
          ownerUserId: owner,
          record: MeGroupRecord.fromJson(map),
        );
      }
      await _rememberVersion(
          prefs, scope, versions, entityKey, item.itemVersion,
          persist: persistVersion);
      return;
    }
    if (domain == 'groupMembers') {
      final gid = groupId ?? payload['groupId']?.toString() ?? '';
      final uid =
          (payload['userId'] ?? payload['user_id'] ?? item.id).toString();
      if (gid.trim().isEmpty || uid.trim().isEmpty) return;
      if (item.deleted) {
        await GroupMemberLocalStore.instance
            .deleteUsers(ownerUserId: owner, groupId: gid, userIds: [uid]);
        GroupMemberStore.instance.removeMembers(gid, [uid], notify: true);
      } else {
        await GroupMemberLocalStore.instance.upsertMany(
          ownerUserId: owner,
          groupId: gid,
          records: [
            GroupMemberRecord.fromJson({...payload, 'userId': uid})
          ],
        );
      }
      await _rememberVersion(
          prefs, scope, versions, entityKey, item.itemVersion,
          persist: persistVersion);
      return;
    }
    if (domain == 'groupNotices') {
      final noticeType = (payload['type'] ??
              payload['noticeType'] ??
              payload['notice_type'] ??
              '')
          .toString()
          .trim()
          .toUpperCase();
      if (noticeType == 'READ_WATERMARK') {
        final rawRead = payload['lastReadAtMs'] ??
            payload['last_read_at_ms'] ??
            payload['readAtMs'] ??
            payload['read_at_ms'];
        final readAt = rawRead is num
            ? rawRead.toInt()
            : int.tryParse(rawRead?.toString() ?? '') ?? 0;
        GroupSystemNoticeService.instance.applyRemoteReadWatermark(readAt);
        await _rememberVersion(
            prefs, scope, versions, entityKey, item.itemVersion,
            persist: persistVersion);
        return;
      }
      final id =
          (payload['noticeId'] ?? payload['notice_id'] ?? item.id).toString();
      if (item.deleted) {
        await GroupSystemNoticeService.instance.removeNoticeById(id);
      } else {
        final record = GroupNoticeRecord.fromJson({...payload, 'noticeId': id});
        if (record.noticeId.isNotEmpty && record.groupId.isNotEmpty) {
          GroupSystemNoticeService.instance
              .upsertNotice(record.toUIKitNotice());
        }
      }
    }
    await _rememberVersion(prefs, scope, versions, entityKey, item.itemVersion,
        persist: persistVersion);
  }

  Future<void> _applyEvent(
    SharedPreferences prefs, {
    required String scope,
    required String owner,
    required String domain,
    String? groupId,
    required SyncChangeEvent event,
    Map<String, int>? sharedVersions,
    Set<String>? sharedSeen,
    bool persistState = true,
  }) async {
    final seen = sharedSeen ?? _readSet(prefs, _eventsKey(scope));
    if (seen.contains(event.eventId)) return;
    if (domain == 'groupNotices' && _isReadWatermark(event)) {
      final value = event.data['lastReadAtMs'] ??
          event.data['last_read_at_ms'] ??
          event.occurredAt;
      final watermark = int.tryParse(value?.toString() ?? '') ?? 0;
      if (watermark > 0) {
        GroupSystemNoticeService.instance.applyRemoteReadWatermark(watermark);
      }
      seen.add(event.eventId);
      if (persistState) {
        await prefs.setStringList(
            _eventsKey(scope), seen.toList(growable: false));
      }
      return;
    }
    final versions =
        sharedVersions ?? _readVersions(prefs, _versionsKey(scope));
    final versionKey = _entityKey(
      domain,
      SyncProtocolItem(
        id: event.id,
        itemVersion: event.itemVersion,
        updatedAt: event.occurredAt,
        data: event.data,
        deleted: event.isDelete,
      ),
      event.data,
      groupId,
    );
    if (versionKey.isEmpty ||
        (versions[versionKey] ?? -1) >= event.itemVersion) {
      seen.add(event.eventId);
      if (persistState) {
        await prefs.setStringList(
            _eventsKey(scope), seen.toList(growable: false));
      }
      return;
    }
    await _applyItem(
      prefs: prefs,
      scope: scope,
      owner: owner,
      domain: domain,
      groupId: groupId,
      item: SyncProtocolItem(
        id: event.id,
        itemVersion: event.itemVersion,
        updatedAt: event.occurredAt,
        data: event.data,
        deleted: event.isDelete,
      ),
      sharedVersions: versions,
      persistVersion: false,
    );
    versions[versionKey] = event.itemVersion;
    seen.add(event.eventId);
    while (seen.length > _maxRememberedEvents) {
      seen.remove(seen.first);
    }
    if (persistState) {
      await prefs.setString(_versionsKey(scope), jsonEncode(versions));
      await prefs.setStringList(
          _eventsKey(scope), seen.toList(growable: false));
    }
  }

  bool _isReadWatermark(SyncChangeEvent event) {
    final type = (event.data['type'] ?? event.data['noticeType'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return type == 'READ_WATERMARK' || type == 'READ_WATERMARK_UPDATED';
  }

  String _stateKey(String scope) => '$_statePrefix$scope';
  String _versionsKey(String scope) => '$_versionsPrefix$scope';
  String _eventsKey(String scope) => '$_eventsPrefix$scope';

  _SyncState _readState(SharedPreferences prefs, String scope) {
    final raw = prefs.getString(_stateKey(scope));
    if (raw == null) return const _SyncState();
    try {
      final map = jsonDecode(raw);
      return _SyncState(
        revision: map['revision']?.toString() ?? '',
        cursor: map['cursor']?.toString() ?? '',
        snapshotDone: map['snapshotDone'] != false,
      );
    } catch (_) {
      return const _SyncState();
    }
  }

  Future<void> _saveState(
      SharedPreferences prefs, String scope, _SyncState state) {
    return prefs.setString(
        _stateKey(scope),
        jsonEncode({
          'revision': state.revision,
          'cursor': state.cursor,
          'snapshotDone': state.snapshotDone,
        }));
  }

  Set<String> _readSet(SharedPreferences prefs, String key) =>
      (prefs.getStringList(key) ?? const <String>[])
          .where((e) => e.isNotEmpty)
          .toSet();

  Map<String, int> _readVersions(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return <String, int>{};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in map.entries)
          entry.key.toString(): int.tryParse(entry.value.toString()) ?? 0,
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  String _entityKey(
    String domain,
    SyncProtocolItem item,
    Map<String, dynamic> payload,
    String? groupId,
  ) {
    if (domain == 'groups') {
      return (payload['groupId'] ?? payload['group_id'] ?? item.id)
          .toString()
          .trim();
    }
    if (domain == 'groupMembers') {
      final gid = (groupId ?? payload['groupId'] ?? payload['group_id'] ?? '')
          .toString()
          .trim();
      final uid = (payload['userId'] ?? payload['user_id'] ?? item.id)
          .toString()
          .trim();
      return gid.isEmpty || uid.isEmpty ? '' : '$gid|$uid';
    }
    return (payload['noticeId'] ?? payload['notice_id'] ?? item.id)
        .toString()
        .trim();
  }

  Future<void> _rememberVersion(
    SharedPreferences prefs,
    String scope,
    Map<String, int> versions,
    String entityKey,
    int itemVersion, {
    bool persist = true,
  }) async {
    if (entityKey.isEmpty || itemVersion <= 0) return;
    versions[entityKey] = itemVersion;
    if (persist) {
      await prefs.setString(_versionsKey(scope), jsonEncode(versions));
    }
  }
}

class _SyncState {
  const _SyncState({
    this.revision = '',
    this.cursor = '',
    this.snapshotDone = true,
  });
  final String revision;
  final String cursor;
  final bool snapshotDone;
}
