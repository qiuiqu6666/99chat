import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// Fetches and patches the group live index for the conversation list.
class GroupLiveIndexSyncService {
  GroupLiveIndexSyncService._() : _fetch = GroupLiveApi.instance.liveIndex;

  @visibleForTesting
  GroupLiveIndexSyncService.forTest({
    required Future<GroupLiveIndexFetchResult> Function({String? ifNoneMatch})
        fetch,
  }) : _fetch = fetch;

  static final GroupLiveIndexSyncService instance =
      GroupLiveIndexSyncService._();

  static const Duration _pollInterval = Duration(seconds: 45);

  final GroupLiveIndexStore _store = GroupLiveIndexStore.instance;
  final Future<GroupLiveIndexFetchResult> Function({String? ifNoneMatch})
      _fetch;

  Timer? _pollTimer;
  bool _tabVisible = false;
  Future<void>? _fetchTask;
  String? _pendingReason;
  int _generation = 0;
  int _fetchGeneration = 0;
  int _patchRevision = 0;

  GroupLiveIndexStore get store => _store;

  Future<void> fetchIndex({String reason = 'manual', bool invalidate = false}) {
    final existing = _fetchTask;
    if (existing != null) {
      if (invalidate || _fetchGeneration != _generation) {
        _pendingReason = reason;
      }
      return existing;
    }
    _fetchGeneration = _generation;
    final requestedGeneration = _generation;
    late final Future<void> task;
    task = Future<void>.microtask(() async {
      if (requestedGeneration != _generation && _pendingReason == null) return;
      var nextReason = reason;
      do {
        _pendingReason = null;
        _fetchGeneration = _generation;
        await _fetchIndexOnce(reason: nextReason);
        nextReason = _pendingReason ?? reason;
      } while (_pendingReason != null);
    }).whenComplete(() {
      if (identical(_fetchTask, task)) _fetchTask = null;
    });
    _fetchTask = task;
    return task;
  }

  void onGroupTabVisible() {
    _tabVisible = true;
    _startPolling();
    unawaited(fetchIndex(reason: 'group_tab_visible'));
  }

  void onGroupTabHidden() {
    _tabVisible = false;
    _stopPolling();
  }

  void onAppResumed() {
    if (_tabVisible) {
      unawaited(fetchIndex(reason: 'app_resumed'));
      _startPolling();
      return;
    }
    unawaited(fetchIndex(reason: 'app_resumed_cold'));
  }

  void reset() {
    _stopPolling();
    _tabVisible = false;
    _generation++;
    _pendingReason = null;
    _store.clear();
  }

  Future<void> applyGroupLiveChanged(FriendRealtimeEvent event) async {
    if (event.event.trim() != 'group_changed') {
      return;
    }
    if (event.action?.trim().toLowerCase() != 'group_live_changed') {
      return;
    }
    final groupId = ChatIdFormat.normalizeGroupId(event.groupId);
    if (groupId.isEmpty) {
      return;
    }
    final detail = event.detail;
    if (detail == null || detail.isEmpty) {
      _patchRevision++;
      unawaited(fetchIndex(
        reason: 'tcp_group_live_changed_empty_detail',
        invalidate: true,
      ));
      return;
    }
    _onPatch();
    _store.applyTcpPatch(
      groupId: groupId,
      detail: Map<String, dynamic>.from(detail),
    );
  }

  void patchLocalSession(GroupLiveSession session, {int version = 0}) {
    _onPatch();
    _store.applyLocalSession(session, version: version);
  }

  void _onPatch() {
    _patchRevision++;
    if (_fetchTask != null) {
      unawaited(fetchIndex(reason: 'patch_during_fetch', invalidate: true));
    }
  }

  Future<void> _fetchIndexOnce({required String reason}) async {
    final generation = _generation;
    final patchRevision = _patchRevision;
    try {
      final result = await _fetch(
        ifNoneMatch: _store.etag,
      );
      // A late account response or pre-patch snapshot cannot replace new state.
      if (generation != _generation || patchRevision != _patchRevision) return;
      switch (result.status) {
        case GroupLiveIndexFetchStatus.notModified:
          if (kDebugMode) {
            // ignore: avoid_print
            print('[GroupLiveIndex] 304 reason=$reason');
          }
          return;
        case GroupLiveIndexFetchStatus.updated:
          final snapshot = result.snapshot;
          if (snapshot == null) {
            return;
          }
          _store.applySnapshot(snapshot, etag: result.etag);
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[GroupLiveIndex] updated reason=$reason '
              'revision=${snapshot.revision} items=${snapshot.items.length}',
            );
          }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GroupLiveIndex] fetch failed reason=$reason error=$e');
      }
    }
  }

  void _startPolling() {
    if (!_tabVisible) {
      return;
    }
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(fetchIndex(reason: 'poll'));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
