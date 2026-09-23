import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/native_bootstrap_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_sync_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/friendShip/self_hosted_friendship_bridge.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

enum ImSdkRelationshipPhase { idle, scheduled, running, completed }

/// One-shot IM relationship calibration. Not SNS-ready; not a poller.
class ImSdkRelationshipReconcileService {
  ImSdkRelationshipReconcileService._()
      : _directory = ImSdkRelationshipDirectory.instance,
        _loadFriendsOverride = null,
        _loadGroupsOverride = null,
        _isSyncPendingOverride = null,
        _hasHandledFinishOverride = null,
        _canRunNowOverride = null,
        fallbackDelay = Duration.zero,
        handshakeTimeout = const Duration(seconds: 12),
        uiIdleTimeout = ImSdkRelationshipPerf.uiIdleTimeout;

  ImSdkRelationshipReconcileService.forTest({
    required ImSdkRelationshipDirectory directory,
    required Future<List<RelationshipFriendEntry>> Function() loadFriends,
    required Future<List<RelationshipGroupEntry>> Function() loadGroups,
    bool Function()? isSyncPending,
    bool Function()? hasHandledFinish,
    bool Function()? canRunNow,
    this.fallbackDelay = Duration.zero,
    this.handshakeTimeout = const Duration(seconds: 12),
    this.uiIdleTimeout = const Duration(seconds: 15),
  })  : _directory = directory,
        _loadFriendsOverride = loadFriends,
        _loadGroupsOverride = loadGroups,
        _isSyncPendingOverride = isSyncPending,
        _hasHandledFinishOverride = hasHandledFinish,
        _canRunNowOverride = canRunNow;

  static final ImSdkRelationshipReconcileService instance =
      ImSdkRelationshipReconcileService._();

  final ImSdkRelationshipDirectory _directory;
  final Future<List<RelationshipFriendEntry>> Function()? _loadFriendsOverride;
  final Future<List<RelationshipGroupEntry>> Function()? _loadGroupsOverride;
  final bool Function()? _isSyncPendingOverride;
  final bool Function()? _hasHandledFinishOverride;
  final bool Function()? _canRunNowOverride;

  final Duration fallbackDelay;
  final Duration handshakeTimeout;
  final Duration uiIdleTimeout;

  ImSdkRelationshipPhase friendFirstPhase = ImSdkRelationshipPhase.idle;
  ImSdkRelationshipPhase groupFirstPhase = ImSdkRelationshipPhase.idle;
  ImSdkRelationshipPhase friendReconcilePhase = ImSdkRelationshipPhase.idle;
  ImSdkRelationshipPhase groupReconcilePhase = ImSdkRelationshipPhase.idle;

  int debugFriendGetCount = 0;
  int debugGroupGetCount = 0;
  int reconnectEpoch = 0;

  int _sessionGeneration = -1;
  bool _connectBaseline = false;
  bool _needsReconnectReconcile = false;
  DateTime? _lastGroupSdkAt;
  Future<void>? _friendFlight;
  Future<void>? _groupFlight;
  Timer? _fallbackTimer;
  final Set<String> _viewportHydrating = <String>{};
  DateTime? _loginAt;
  Completer<void>? _idleHold;

  ImSdkRelationshipDirectory get directory => _directory;

  /// SDK callbacks are hints when the backend owns friendship membership.
  Future<void> refreshConfirmedFriends({required String reason}) =>
      ContactsProtocolSyncService.instance.sync(reason: reason);

  void onImLoginSuccess() {
    final generation = SessionIdentityService.instance.generation;
    if (generation != _sessionGeneration) {
      resetForSession(generation);
    }
    _loginAt = DateTime.now();
    unawaited(requestFirstSnapshot(reason: 'im_login'));
    _scheduleFallback();
  }

  void onSessionInvalidated() {
    resetForSession(-1);
  }

  void resetForSession(int generation) {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _idleHold?.complete();
    _idleHold = null;
    _sessionGeneration = generation;
    _connectBaseline = false;
    _needsReconnectReconcile = false;
    reconnectEpoch = 0;
    friendFirstPhase = ImSdkRelationshipPhase.idle;
    groupFirstPhase = ImSdkRelationshipPhase.idle;
    friendReconcilePhase = ImSdkRelationshipPhase.idle;
    groupReconcilePhase = ImSdkRelationshipPhase.idle;
    _directory.reset();
    _viewportHydrating.clear();
    debugFriendGetCount = 0;
    debugGroupGetCount = 0;
    _loginAt = null;
    ImSdkRelationshipSyncAnchor.reset();
  }

  void onSocketConnectSuccess() {
    if (!_connectBaseline) {
      _connectBaseline = true;
      return;
    }
    if (!_needsReconnectReconcile) {
      return;
    }
    _needsReconnectReconcile = false;
    reconnectEpoch++;
    friendReconcilePhase = ImSdkRelationshipPhase.idle;
    groupReconcilePhase = ImSdkRelationshipPhase.idle;
    unawaited(requestRelationshipReconcile(reason: 'im_reconnect'));
  }

  void onSocketDisconnectedAfterConnected() {
    if (_connectBaseline) {
      _needsReconnectReconcile = true;
    }
  }

  Future<void> requestFirstSnapshot({required String reason}) {
    return Future.wait<void>([
      _request(
        isReconcile: false,
        isFriends: true,
        reason: reason,
      ),
      _request(
        isReconcile: false,
        isFriends: false,
        reason: reason,
      ),
    ]);
  }

  Future<void> requestRelationshipReconcile({required String reason}) {
    return Future.wait<void>([
      _request(
        isReconcile: true,
        isFriends: true,
        reason: reason,
      ),
      _request(
        isReconcile: true,
        isFriends: false,
        reason: reason,
      ),
    ]);
  }

  @visibleForTesting
  void releaseIdleHold() {
    _idleHold?.complete();
    _idleHold = null;
  }

  @visibleForTesting
  void holdNextRun() {
    _idleHold = Completer<void>();
  }

  Future<void> _request({
    required bool isReconcile,
    required bool isFriends,
    required String reason,
  }) async {
    var phase = _phase(isReconcile: isReconcile, isFriends: isFriends);
    if (phase == ImSdkRelationshipPhase.completed ||
        phase == ImSdkRelationshipPhase.running) {
      _logSkip(reason, 'once_or_inflight');
      return;
    }
    if (phase == ImSdkRelationshipPhase.scheduled) {
      return;
    }
    _setPhase(
      isReconcile: isReconcile,
      isFriends: isFriends,
      phase: ImSdkRelationshipPhase.scheduled,
    );
    try {
      await _waitUntilRunnable();
      phase = _phase(isReconcile: isReconcile, isFriends: isFriends);
      if (phase != ImSdkRelationshipPhase.scheduled) {
        return;
      }
      _setPhase(
        isReconcile: isReconcile,
        isFriends: isFriends,
        phase: ImSdkRelationshipPhase.running,
      );
      if (isFriends) {
        await _runFriends(reason: reason, isReconcile: isReconcile);
      } else {
        await _runGroups(reason: reason, isReconcile: isReconcile);
      }
      _setPhase(
        isReconcile: isReconcile,
        isFriends: isFriends,
        phase: ImSdkRelationshipPhase.completed,
      );
    } catch (_) {
      _setPhase(
        isReconcile: isReconcile,
        isFriends: isFriends,
        phase: ImSdkRelationshipPhase.idle,
      );
      ConversationPerfGateLog.log(
        'im_rel.${isFriends ? 'friends' : 'groups'}.reconcile',
        extras: <String, Object?>{
          'reason': reason,
          'outcome': 'fail',
        },
      );
    }
  }

  Future<void> _runFriends({
    required String reason,
    required bool isReconcile,
  }) async {
    while (_friendFlight != null) {
      await _friendFlight;
    }
    if (!isReconcile && _directory.hasCompleteFriendSnapshot) {
      return;
    }
    late final Future<void> task;
    task = _fetchFriends(reason: reason).whenComplete(() {
      if (identical(_friendFlight, task)) {
        _friendFlight = null;
      }
    });
    _friendFlight = task;
    await task;
  }

  Future<void> _runGroups({
    required String reason,
    required bool isReconcile,
  }) async {
    while (_groupFlight != null) {
      await _groupFlight;
    }
    if (!isReconcile && _directory.hasCompleteGroupSnapshot) {
      return;
    }
    late final Future<void> task;
    task = _fetchGroups(reason: reason).whenComplete(() {
      if (identical(_groupFlight, task)) {
        _groupFlight = null;
      }
    });
    _groupFlight = task;
    await task;
  }

  Future<void> _fetchFriends({required String reason}) async {
    if (_loadFriendsOverride == null && SelfHostedFriendshipBridge.enabled) {
      // The protocol coordinator serializes hydration and remote changes. A
      // second SQLite/SDK snapshot writer could replay an older captured list.
      await ContactsProtocolSyncService.instance.sync(reason: reason);
      return;
    }
    final identity = _loadFriendsOverride == null
        ? SessionIdentityService.instance.capture()
        : null;
    final captureId = _directory.beginFriendCapture();
    final started = DateTime.now();
    try {
      final rawEntries = await _loadFriends();
      debugFriendGetCount++;
      final sdkMs = DateTime.now().difference(started).inMilliseconds;
      ConversationPerfGateLog.log(
        'im_rel.friends.sdk_get_ms',
        extras: <String, Object?>{'ms': sdkMs, 'reason': reason},
      );
      final entries = await _overlayEntries(rawEntries);
      final extractStarted = DateTime.now();
      final ordered = await _orderedIds(entries);
      if (identity != null &&
          !SessionIdentityService.instance.isCurrent(identity)) {
        _directory.dropFriendCapture(captureId);
        return;
      }
      ConversationPerfGateLog.log(
        'im_rel.friends.extract_ms',
        extras: <String, Object?>{
          'ms': DateTime.now().difference(extractStarted).inMilliseconds,
          'count': entries.length,
          'isolate':
              ImSdkRelationshipPerf.shouldIsolateSort(entries.length) ? 1 : 0,
        },
      );
      _directory.applyFriendSnapshot(
        captureId: captureId,
        entries: entries,
        orderedIds: ordered,
      );
    } catch (error) {
      _directory.dropFriendCapture(captureId);
      rethrow;
    }
  }

  Future<void> _fetchGroups({required String reason}) async {
    final captureId = _directory.beginGroupCapture();
    final started = DateTime.now();
    try {
      await _waitGroupRateLimit();
      final entries = await _loadGroups();
      debugGroupGetCount++;
      _lastGroupSdkAt = DateTime.now();
      ConversationPerfGateLog.log(
        'im_rel.groups.sdk_get_ms',
        extras: <String, Object?>{
          'ms': DateTime.now().difference(started).inMilliseconds,
          'reason': reason,
        },
      );
      final ordered = await _orderedGroupIds(entries);
      _directory.applyGroupSnapshot(
        captureId: captureId,
        entries: entries,
        orderedIds: ordered,
      );
    } catch (error) {
      _directory.dropGroupCapture(captureId);
      rethrow;
    }
  }

  Future<void> _waitGroupRateLimit() async {
    final last = _lastGroupSdkAt;
    if (last == null) {
      return;
    }
    final elapsed = DateTime.now().difference(last);
    final wait = ImSdkRelationshipPerf.groupSdkMinInterval - elapsed;
    if (wait > Duration.zero) {
      ConversationPerfGateLog.log(
        'im_rel.groups.sdk_skipped_rate_limit',
        extras: <String, Object?>{'waitMs': wait.inMilliseconds},
      );
      await Future<void>.delayed(wait);
    }
  }

  Future<List<String>> _orderedIds(
      List<RelationshipFriendEntry> entries) async {
    if (entries.isEmpty) {
      return const <String>[];
    }
    final rows = <List<String>>[
      for (final entry in entries) <String>[entry.userId, entry.sortKey],
    ];
    if (ImSdkRelationshipPerf.shouldIsolateSort(entries.length)) {
      return compute(imSdkRelationshipSortIds, rows);
    }
    return imSdkRelationshipSortIds(rows);
  }

  Future<List<String>> _orderedGroupIds(
    List<RelationshipGroupEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return const <String>[];
    }
    final rows = <List<String>>[
      for (final entry in entries) <String>[entry.groupId, entry.sortKey],
    ];
    if (ImSdkRelationshipPerf.shouldIsolateSort(entries.length)) {
      return compute(imSdkRelationshipSortIds, rows);
    }
    return imSdkRelationshipSortIds(rows);
  }

  Future<void> overlayLocalFriendDisplay({required String reason}) async {
    if (_loadFriendsOverride == null && SelfHostedFriendshipBridge.enabled) {
      return;
    }
    if (!_directory.hasCompleteFriendSnapshot) {
      return;
    }
    final ids = _directory.friendOrderedIds;
    if (ids.isEmpty) {
      return;
    }
    final current = <RelationshipFriendEntry>[
      for (final id in ids)
        if (_directory.friend(id) != null) _directory.friend(id)!,
    ];
    final overlaid = await _overlayEntries(current);
    final changed = <RelationshipFriendEntry>[];
    for (var i = 0; i < current.length; i++) {
      if (overlaid[i].fingerprint != current[i].fingerprint) {
        changed.add(overlaid[i]);
      }
    }
    if (changed.isEmpty) {
      return;
    }
    _directory.applyFriendChanges(changed);
    ConversationPerfGateLog.log(
      'im_rel.friends.local_overlay',
      extras: <String, Object?>{
        'reason': reason,
        'changed': changed.length,
      },
    );
  }

  Future<void> hydrateViewportFriendDisplay(List<String> userIds) async {
    if (_loadFriendsOverride == null && SelfHostedFriendshipBridge.enabled) {
      return;
    }
    final ids = <String>[
      for (final id in userIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (ids.isEmpty) {
      return;
    }
    final pending = <String>[];
    for (final id in ids) {
      if (_viewportHydrating.contains(id)) {
        continue;
      }
      final entry = _directory.friend(id);
      if (entry == null) {
        continue;
      }
      if (entry.faceUrl.isNotEmpty &&
          (entry.remark.isNotEmpty || entry.nickname.isNotEmpty)) {
        continue;
      }
      _viewportHydrating.add(id);
      pending.add(id);
    }
    if (pending.isEmpty) {
      return;
    }
    try {
      var entries = <RelationshipFriendEntry>[
        for (final id in pending)
          if (_directory.friend(id) != null) _directory.friend(id)!,
      ];
      entries = await _overlayEntries(entries, alsoUserProfileStore: true);
      final stillMissing = <String>[
        for (final entry in entries)
          if (entry.faceUrl.isEmpty &&
              entry.nickname.isEmpty &&
              entry.remark.isEmpty)
            entry.userId,
      ];
      if (stillMissing.isNotEmpty && _loadFriendsOverride == null) {
        entries = await _overlayUsersInfo(entries, stillMissing);
      }
      final changed = <RelationshipFriendEntry>[];
      for (final entry in entries) {
        final prev = _directory.friend(entry.userId);
        if (prev == null || prev.fingerprint != entry.fingerprint) {
          changed.add(entry);
        }
      }
      if (changed.isNotEmpty) {
        _directory.applyFriendChanges(changed);
      }
    } finally {
      _viewportHydrating.removeAll(pending);
    }
  }

  Future<List<RelationshipFriendEntry>> _overlayEntries(
    List<RelationshipFriendEntry> entries, {
    bool alsoUserProfileStore = false,
  }) async {
    if (entries.isEmpty) {
      return entries;
    }
    if (_loadFriendsOverride != null) {
      return entries;
    }
    final ids = <String>[for (final entry in entries) entry.userId];
    Map<String, String> remarks = const {};
    Map<String, String> nicks = const {};
    Map<String, String> faces = const {};
    try {
      final records = ids.length > 400
          ? await FriendLocalStore.instance.readAll()
          : await FriendLocalStore.instance.readByIds(friendUserIds: ids);
      remarks = <String, String>{
        for (final record in records)
          if (record.friendUserId.trim().isNotEmpty)
            record.friendUserId.trim(): record.remark,
      };
      nicks = <String, String>{
        for (final record in records)
          if (record.friendUserId.trim().isNotEmpty)
            record.friendUserId.trim(): record.friendNickname,
      };
      faces = <String, String>{
        for (final record in records)
          if (record.friendUserId.trim().isNotEmpty)
            record.friendUserId.trim(): record.friendAvatarUrl,
      };
    } catch (_) {}
    if (alsoUserProfileStore) {
      try {
        final stored = await UserProfileLocalStore.instance.readByIds(
          userIds: ids,
        );
        for (final record in stored) {
          final id = record.userId.trim();
          if (id.isEmpty) {
            continue;
          }
          if ((remarks[id] ?? '').isEmpty && record.friendRemark.isNotEmpty) {
            remarks = Map<String, String>.from(remarks)
              ..[id] = record.friendRemark;
          }
          if ((nicks[id] ?? '').isEmpty && record.nickname.isNotEmpty) {
            nicks = Map<String, String>.from(nicks)..[id] = record.nickname;
          }
          if ((faces[id] ?? '').isEmpty && record.avatarUrl.isNotEmpty) {
            faces = Map<String, String>.from(faces)..[id] = record.avatarUrl;
          }
        }
      } catch (_) {}
    }
    return <RelationshipFriendEntry>[
      for (final entry in entries)
        overlayFriendDisplay(
          entry: entry,
          localRemark: UserProfileLocalService.instance
                  .readCached(entry.userId)
                  ?.friendRemark ??
              remarks[entry.userId],
          localNickname: UserProfileLocalService.instance
                  .readCached(entry.userId)
                  ?.nickname ??
              nicks[entry.userId],
          localFaceUrl: UserProfileLocalService.instance
                  .readCached(entry.userId)
                  ?.avatarUrl ??
              faces[entry.userId],
        ),
    ];
  }

  Future<List<RelationshipFriendEntry>> _overlayUsersInfo(
    List<RelationshipFriendEntry> entries,
    List<String> missingIds,
  ) async {
    if (missingIds.isEmpty) {
      return entries;
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager.getUsersInfo(
        userIDList: missingIds.take(100).toList(growable: false),
      );
      if (res.code != 0 || res.data == null) {
        return entries;
      }
      final byId = <String, String>{
        for (final info in res.data!)
          if ((info.userID ?? '').trim().isNotEmpty)
            info.userID!.trim(): info.nickName?.trim() ?? '',
      };
      final faceById = <String, String>{
        for (final info in res.data!)
          if ((info.userID ?? '').trim().isNotEmpty)
            info.userID!.trim(): info.faceUrl?.trim() ?? '',
      };
      return <RelationshipFriendEntry>[
        for (final entry in entries)
          overlayFriendDisplay(
            entry: entry,
            localNickname: byId[entry.userId],
            localFaceUrl: faceById[entry.userId],
          ),
      ];
    } catch (_) {
      return entries;
    }
  }

  Future<List<RelationshipFriendEntry>> _loadFriends() async {
    final override = _loadFriendsOverride;
    if (override != null) {
      return override();
    }
    if (SelfHostedFriendshipBridge.enabled) {
      final records = await FriendLocalStore.instance.readAll();
      return [
        for (final record in records)
          friendEntryFromSdk(record.toV2TimFriendInfo()),
      ];
    }
    final res = await TencentImSDKPlugin.v2TIMManager
        .getFriendshipManager()
        .getFriendList();
    if (res.code != 0) {
      throw StateError('getFriendList code=${res.code}');
    }
    return <RelationshipFriendEntry>[
      for (final info in res.data ?? const <V2TimFriendInfo>[])
        friendEntryFromSdk(info),
    ];
  }

  Future<List<RelationshipGroupEntry>> _loadGroups() async {
    final override = _loadGroupsOverride;
    if (override != null) {
      return override();
    }
    final res = await TencentImSDKPlugin.v2TIMManager
        .getGroupManager()
        .getJoinedGroupList();
    if (res.code != 0) {
      throw StateError('getJoinedGroupList code=${res.code}');
    }
    return <RelationshipGroupEntry>[
      for (final info in res.data ?? const <V2TimGroupInfo>[])
        groupEntryFromSdk(info),
    ];
  }

  void _scheduleFallback() {
    _fallbackTimer?.cancel();
    final delay = _loadFriendsOverride != null
        ? fallbackDelay
        : NativeBootstrapPerfFlags.postHomeStartDelay +
            ConversationPerfFlags.resumeQuietDuration;
    _fallbackTimer = Timer(delay, () {
      unawaited(_onFallbackFired());
    });
  }

  Future<void> _onFallbackFired() async {
    if (_isSyncPending) {
      final loginAt = _loginAt ?? DateTime.now();
      final left = handshakeTimeout - DateTime.now().difference(loginAt);
      if (left <= Duration.zero) {
        await requestRelationshipReconcile(reason: 'sync_finish_missing');
        return;
      }
      _fallbackTimer = Timer(left, () {
        unawaited(_onFallbackFired());
      });
      return;
    }
    if (_hasHandledFinish) {
      return;
    }
    await requestRelationshipReconcile(reason: 'login_delay_fallback');
  }

  Future<void> _waitUntilRunnable() async {
    final hold = _idleHold;
    if (hold != null) {
      await hold.future;
    }
    final override = _canRunNowOverride;
    if (override != null) {
      if (!override()) {
        throw StateError('idle_cancelled');
      }
      return;
    }
    final deadline = DateTime.now().add(uiIdleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_productionCanRun()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  bool _productionCanRun() {
    try {
      if ((ActiveChatRegistry.instance.activeConversationId ?? '').isNotEmpty) {
        return false;
      }
    } catch (_) {}
    return true;
  }

  bool get _isSyncPending {
    final override = _isSyncPendingOverride;
    if (override != null) {
      return override();
    }
    return ImSdkRelationshipSyncAnchor.serverSyncPending;
  }

  bool get _hasHandledFinish {
    final override = _hasHandledFinishOverride;
    if (override != null) {
      return override();
    }
    return ImSdkRelationshipSyncAnchor.hasHandledFinish;
  }

  ImSdkRelationshipPhase _phase({
    required bool isReconcile,
    required bool isFriends,
  }) {
    if (isReconcile) {
      return isFriends ? friendReconcilePhase : groupReconcilePhase;
    }
    return isFriends ? friendFirstPhase : groupFirstPhase;
  }

  void _setPhase({
    required bool isReconcile,
    required bool isFriends,
    required ImSdkRelationshipPhase phase,
  }) {
    if (isReconcile) {
      if (isFriends) {
        friendReconcilePhase = phase;
      } else {
        groupReconcilePhase = phase;
      }
    } else if (isFriends) {
      friendFirstPhase = phase;
    } else {
      groupFirstPhase = phase;
    }
  }

  void _logSkip(String reason, String why) {
    ConversationPerfGateLog.log(
      'im_rel.reconcile.skipped_once',
      extras: <String, Object?>{'reason': reason, 'why': why},
    );
  }

  static RelationshipFriendEntry friendEntryFromSdk(V2TimFriendInfo info) {
    final userId = info.userID.trim();
    final remark = info.friendRemark?.trim() ?? '';
    final rawNick = info.userProfile?.nickName?.trim() ?? '';
    final nick =
        DisplayNameStore.isRawUserIdDisplayName(userId, rawNick) ? '' : rawNick;
    final displayName =
        remark.isNotEmpty ? remark : (nick.isNotEmpty ? nick : userId);
    final faceUrl = info.userProfile?.faceUrl?.trim() ?? '';
    final azTag = memberSuspensionIndexTag(displayName);
    return RelationshipFriendEntry(
      userId: userId,
      displayName: displayName,
      faceUrl: faceUrl,
      remark: remark,
      nickname: nick,
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: userId,
        displayName: displayName,
        azTag: azTag,
      ),
    );
  }

  static RelationshipFriendEntry overlayFriendDisplay({
    required RelationshipFriendEntry entry,
    String? localRemark,
    String? localNickname,
    String? localFaceUrl,
  }) {
    final remark =
        entry.remark.isNotEmpty ? entry.remark : (localRemark?.trim() ?? '');
    final nickname = entry.nickname.isNotEmpty
        ? entry.nickname
        : (localNickname?.trim() ?? '');
    final faceUrl =
        entry.faceUrl.isNotEmpty ? entry.faceUrl : (localFaceUrl?.trim() ?? '');
    final displayName = remark.isNotEmpty
        ? remark
        : (nickname.isNotEmpty ? nickname : entry.userId);
    if (remark == entry.remark &&
        nickname == entry.nickname &&
        faceUrl == entry.faceUrl &&
        displayName == entry.displayName) {
      return entry;
    }
    return entry.copyWith(
      remark: remark,
      nickname: nickname,
      faceUrl: faceUrl,
      displayName: displayName,
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: entry.userId,
        displayName: displayName,
        azTag: memberSuspensionIndexTag(displayName),
      ),
    );
  }

  static RelationshipGroupEntry groupEntryFromSdk(V2TimGroupInfo info) {
    final groupId = info.groupID.trim();
    final groupName = (info.groupName ?? '').trim();
    final display = groupName.isNotEmpty ? groupName : groupId;
    final azTag = memberSuspensionIndexTag(display);
    return RelationshipGroupEntry(
      groupId: groupId,
      groupName: display,
      faceUrl: (info.faceUrl ?? '').trim(),
      groupType: (info.groupType ?? '').trim(),
      memberCount: info.memberCount ?? 0,
      role: info.role ?? 0,
      sortKey: ImSdkRelationshipDirectory.sortKeyFor(
        id: groupId,
        displayName: display,
        azTag: azTag,
      ),
    );
  }
}
