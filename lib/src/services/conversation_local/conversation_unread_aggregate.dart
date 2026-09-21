import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_filter.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_id_canonical.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

/// Tab / 桌面角标用的会话未读聚合（不依赖 UI 窗口全表）。
class ConversationUnreadAggregate extends ChangeNotifier {
  ConversationUnreadAggregate._() {
    archivedConversationC2cIDsNotifier.addListener(_onArchivedChanged);
    archivedConversationGroupIDsNotifier.addListener(_onArchivedChanged);
  }

  static final ConversationUnreadAggregate instance =
      ConversationUnreadAggregate._();

  static const Duration _defaultDebounce = Duration(milliseconds: 220);
  static const Duration _bulkDebounce = Duration(milliseconds: 800);
  // Realtime commits are already serialized by ConversationSyncService. A
  // single frame is enough to coalesce a burst without making the bottom-tab
  // badge wait for the normal reload debounce window.
  static const Duration _realtimeDebounce = Duration.zero;

  static const Set<String> _bulkRefreshReasons = <String>{
    'drain_db_only',
    'paced_sync_no_full_reload',
    'dirty_retry',
    'apply_out_of_window',
    // archived_changed：归档后要尽快从底部导航扣掉未读，不用 bulk 长防抖。
  };

  static const String _uiApplyDeferredPrefix = 'ui_apply_deferred_';

  /// Refresh reasons allowed to publish a true `(0,0)` when previous sums
  /// were non-zero. All other reasons defer once via [zeroConfirmReason].
  static const Set<String> _allowZeroRefreshReasons = <String>{
    'zero_confirm',
    // Intentional local clears from the session projection.
    'zero_unread',
    'zero_unread_many',
    'zero_unread_many_empty',
    'realtime_commit',
  };

  /// Follow-up reason after deferring a surprising all-zero store refresh.
  static const String zeroConfirmReason = 'zero_confirm';

  int _c2cNotifiableUnreadSum = 0;
  int _groupNotifiableUnreadSum = 0;
  int? _sdkTotalUnreadCount;
  Timer? _debounce;
  String? _debounceReason;
  Timer? _idleDebounce;
  String? _idleReason;
  Future<void>? _refreshInFlight;
  bool _refreshDirty = false;
  int _deltaCommitCount = 0;
  int _storeCalibrationCount = 0;
  int _scheduledRefreshCount = 0;
  int _sessionClearGeneration = 0;
  bool _sdkSourceActive = false;
  bool _sdkUnreadSeeded = false;

  /// Folder badges consume raw SDK counts, including muted/archived rows.
  /// Their changes are independent of the notifiable tab sums.
  final ValueNotifier<int> sdkUnreadRevision = ValueNotifier<int>(0);
  int _sdkRevision = 0;
  final Map<String, V2TimConversation> _sdkRows = {};
  final Map<String, int> _sdkRowRevisions = {};
  final Map<String, ({bool group, int count})> _sdkContributions = {};
  int _sdkC2cSum = 0, _sdkGroupSum = 0;
  @visibleForTesting
  int sdkRowsEvaluatedForTest = 0;

  @visibleForTesting
  Future<V2TimConversationResult> Function(String nextSeq)? sdkPageForTest;

  V2TimConversation _unreadSnapshot(V2TimConversation row) => V2TimConversation(
        conversationID: row.conversationID,
        type: row.type,
        userID: row.userID,
        groupID: row.groupID,
        groupType: row.groupType,
        unreadCount: row.unreadCount,
        recvOpt: row.recvOpt,
      );

  /// SDK-primary lists bypass SQLite. Keep absolute per-conversation values
  /// from that same SDK stream, including rows outside the visible window.
  void applySdkConversations(Iterable<V2TimConversation> rows) {
    final first = !_sdkSourceActive;
    _sdkSourceActive = true;
    final changedKeys = <String>{};
    for (final row in rows) {
      final key = ConversationIdCanonical.forStorage(row.conversationID);
      if (key.isEmpty) continue;
      _sdkRows[key] = _unreadSnapshot(row);
      _sdkRowRevisions[key] = ++_sdkRevision;
      changedKeys.add(key);
    }
    _publishSdkSums(changedKeys: changedKeys);
    // Seed conversations not yet loaded by the UI. Do not restart this timer
    // for every message in an incoming burst.
    if (first) scheduleRefresh(reason: 'realtime_commit');
  }

  void removeSdkConversations(Iterable<String> ids) {
    if (!_sdkSourceActive) return;
    final changedKeys = <String>{};
    for (final id in ids) {
      final key = ConversationIdCanonical.forStorage(id);
      _sdkRows.remove(key);
      _sdkRowRevisions[key] = ++_sdkRevision;
      changedKeys.add(key);
    }
    _publishSdkSums(changedKeys: changedKeys);
  }

  /// An explicit read action clears raw counts, including rows outside the
  /// visible window. Notification eligibility deltas must not do this.
  void zeroSdkUnreadCounts(Iterable<String> ids) {
    if (!_sdkSourceActive) return;
    final changed = <String>{};
    for (final id in ids) {
      final key = ConversationIdCanonical.forStorage(id);
      final row = _sdkRows[key];
      if (row != null) row.unreadCount = 0;
      _sdkRowRevisions[key] = ++_sdkRevision;
      changed.add(key);
    }
    if (changed.isNotEmpty) _publishSdkSums(changedKeys: changed);
  }

  void updateSdkProjectionIfActive(Iterable<V2TimConversation> rows) {
    if (!_sdkSourceActive) return;
    final changed = rows.where((row) {
      final previous =
          _sdkRows[ConversationIdCanonical.forStorage(row.conversationID)];
      return previous == null ||
          previous.unreadCount != row.unreadCount ||
          previous.recvOpt != row.recvOpt ||
          previous.groupType != row.groupType ||
          previous.type != row.type ||
          previous.userID != row.userID ||
          previous.groupID != row.groupID;
    }).toList(growable: false);
    if (changed.isNotEmpty) applySdkConversations(changed);
  }

  int get sdkPageRevision => _sdkRevision;

  void applySdkPage(Iterable<V2TimConversation> rows,
      {required int startedAtRevision}) {
    applySdkConversations(rows.where((row) =>
        (_sdkRowRevisions[
                ConversationIdCanonical.forStorage(row.conversationID)] ??
            0) <=
        startedAtRevision));
  }

  void _publishSdkSums({Set<String>? changedKeys}) {
    sdkUnreadRevision.value++;
    if (changedKeys == null) {
      _sdkContributions.clear();
      _sdkC2cSum = 0;
      _sdkGroupSum = 0;
    }
    for (final key in changedKeys ?? _sdkRows.keys) {
      final old = _sdkContributions.remove(key);
      if (old != null) {
        if (old.group) {
          _sdkGroupSum -= old.count;
        } else {
          _sdkC2cSum -= old.count;
        }
      }
      final row = _sdkRows[key];
      if (row == null) continue;
      sdkRowsEvaluatedForTest++;
      final count = GroupMembershipSyncService.instance
              .isExplicitlyRemovedConversation(row)
          ? 0
          : ConversationUnreadUtils.notifiableUnreadForAggregate(
              row,
              archivedC2c: archivedConversationC2cIDsNotifier.value,
              archivedGroup: archivedConversationGroupIDsNotifier.value,
            );
      final group = ConversationUnreadUtils.isGroupConversation(row);
      _sdkContributions[key] = (group: group, count: count);
      if (group) {
        _sdkGroupSum += count;
      } else {
        _sdkC2cSum += count;
      }
    }
    final c2c = _sdkC2cSum, group = _sdkGroupSum;
    if (c2c == _c2cNotifiableUnreadSum && group == _groupNotifiableUnreadSum) {
      return;
    }
    _c2cNotifiableUnreadSum = c2c;
    _groupNotifiableUnreadSum = group;
    notifyListeners();
  }

  Future<void> _refreshFromSdk() async {
    final generation = _sessionClearGeneration;
    final revision = _sdkRevision;
    final snapshot = <String, V2TimConversation>{};
    var cursor = '0';
    final seen = <String>{};
    try {
      while (seen.add(cursor)) {
        final V2TimConversationResult page;
        if (sdkPageForTest != null) {
          page = await sdkPageForTest!(cursor);
        } else {
          final manager =
              TencentImSDKPlugin.v2TIMManager.getConversationManager();
          // Only unread rows are needed to apply the app's mute/archive/group
          // visibility rules. Do not enumerate every read conversation.
          final result = kIsWeb
              ? await manager.getConversationList(nextSeq: cursor, count: 100)
              : await manager.getConversationListByFilter(
                  filter: V2TimConversationFilter(hasUnreadCount: true),
                  nextSeq: int.parse(cursor),
                  count: 100,
                );
          if (result.code != 0 || result.data == null) return;
          page = result.data!;
        }
        if (generation != _sessionClearGeneration) return;
        for (final row in page.conversationList ?? <V2TimConversation>[]) {
          snapshot[ConversationIdCanonical.forStorage(row.conversationID)] =
              _unreadSnapshot(row);
        }
        if (page.isFinished == true) break;
        cursor = page.nextSeq?.trim() ?? '';
        if (cursor.isEmpty || seen.contains(cursor)) return;
      }
      // New messages/read/deletion callbacks during pagination take precedence
      // over older page snapshots, including tombstones for deleted rows.
      for (final entry in _sdkRowRevisions.entries) {
        if (entry.value <= revision) continue;
        final row = _sdkRows[entry.key];
        if (row == null) {
          snapshot.remove(entry.key);
        } else {
          snapshot[entry.key] = row;
        }
      }
      _sdkRows
        ..clear()
        ..addAll(snapshot);
      _sdkUnreadSeeded = true;
      _publishSdkSums();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ConversationUnreadAggregate: SDK refresh failed: $error');
      }
    }
  }

  /// Reuse the account's SDK unread snapshot for business folders. The backend
  /// owns folder membership; SQLite conversation mirrors are not a count source.
  Future<Map<String, int>> readSdkUnreadCountsForIds(
      Iterable<String> ids) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return const <String, int>{};
    final generation = _sessionClearGeneration;
    _sdkSourceActive = true;
    if (!_sdkUnreadSeeded) {
      await refreshFromStore(reason: 'folder_sdk_seed');
    }
    if (generation != _sessionClearGeneration || !_sdkUnreadSeeded) {
      throw StateError('SDK unread snapshot is not ready for this account');
    }
    return <String, int>{
      for (final id in requested)
        id: (_sdkRows[ConversationIdCanonical.forStorage(id)] ??
                    (!id.startsWith('c2c_') && !id.startsWith('group_')
                        ? _sdkRows[
                            ConversationIdCanonical.forStorage('c2c_$id')]
                        : null))
                ?.unreadCount ??
            0,
    };
  }

  /// R1: zero-confirm 连续 defer 次数上限。超过后强制应用 Store 结果，
  /// 避免新消息到达时 Store 写入延迟导致 defer 循环吞掉非零未读。
  int _zeroConfirmDeferrals = 0;
  static const int _maxZeroConfirmDeferrals = 2;

  int get c2cNotifiableUnreadSum => _c2cNotifiableUnreadSum;

  int get groupNotifiableUnreadSum => _groupNotifiableUnreadSum;

  int? get sdkTotalUnreadCount => _sdkTotalUnreadCount;

  void applySdkTotalUnreadCount(int unreadCount) {
    final next = math.max(0, unreadCount);
    final changed = _sdkTotalUnreadCount != next;
    _sdkTotalUnreadCount = next;
    // SDK totals arrive independently of row commits. They must not clear
    // the store-backed tab sums while the conversation rows remain unread.
    if (changed) notifyListeners();
  }

  /// Lets an explicit local read projection win for the current frame. The
  /// next Tencent total callback restores the provider value.
  void clearSdkTotalForLocalProjection() {
    if (_sdkTotalUnreadCount == null) return;
    _sdkTotalUnreadCount = null;
    // The badge service listens to this aggregate. Notify immediately so an
    // explicit local read is visible even when the conversation row is not in
    // the current UI window and no per-row delta is emitted.
    notifyListeners();
  }

  void _onArchivedChanged() {
    if (_sdkSourceActive) {
      _publishSdkSums();
      return;
    }
    scheduleRefresh(reason: 'archived_changed');
  }

  static bool isBulkRefreshReason(String reason) {
    if (_bulkRefreshReasons.contains(reason)) {
      return true;
    }
    return reason.startsWith(_uiApplyDeferredPrefix);
  }

  static bool isRealtimeRefreshReason(String reason) {
    return reason == 'realtime_commit';
  }

  void scheduleRefresh({String reason = 'manual'}) {
    _scheduledRefreshCount++;
    _idleDebounce?.cancel();
    _idleDebounce = null;
    _idleReason = null;
    _debounce?.cancel();
    _debounceReason = reason;
    final delay = isRealtimeRefreshReason(reason)
        ? _realtimeDebounce
        : (isBulkRefreshReason(reason) ? _bulkDebounce : _defaultDebounce);
    final generation = _sessionClearGeneration;
    _debounce = Timer(delay, () {
      _debounce = null;
      if (generation != _sessionClearGeneration) {
        return;
      }
      final r = _debounceReason ?? reason;
      _debounceReason = null;
      unawaited(refreshFromStore(reason: r));
    });
  }

  /// Schedules a store calibration outside the interaction/startup window.
  ///
  /// Realtime and local mutations update the aggregate with deltas. A full
  /// SQLite SUM is only needed as a reconciliation pass for rows outside the
  /// current UI window, so it must never compete with first paint or a burst
  /// of incoming messages.
  void scheduleIdleRefresh({
    String reason = 'idle',
    Duration delay = const Duration(seconds: 2),
  }) {
    _scheduledRefreshCount++;
    _idleDebounce?.cancel();
    _idleReason = reason;
    final generation = _sessionClearGeneration;
    _idleDebounce = Timer(delay, () {
      _idleDebounce = null;
      if (generation != _sessionClearGeneration) return;
      final r = _idleReason ?? reason;
      _idleReason = null;
      unawaited(refreshFromStore(reason: r));
    });
  }

  /// Last committed absolute unread value per conversation. This makes
  /// duplicate delivery idempotent without confusing a later legitimate
  /// 0 -> 1 transition with an earlier 0 -> 1 transition for the same chat.
  final Map<String, int> _lastNotifiableByConversation = <String, int>{};

  String _deltaConversationKey(ConversationUnreadDelta sample) {
    var id = sample.conversationKey.trim();
    if (id.isEmpty) return '';
    if (sample.isGroup && id.startsWith('group_')) id = id.substring(6);
    if (!sample.isGroup && id.startsWith('c2c_')) id = id.substring(4);
    return '${sample.isGroup ? 'g' : 'c'}|$id';
  }

  /// Legacy fallback for callers that do not provide a conversation key.
  static const int _deltaDedupeWindow = 32;

  /// 窗内 apply 增量；不触发全表扫描。
  ///
  /// P0-2 idempotency: the same `ConversationUnreadDelta` (same isGroup +
  /// old/new pair) can be re-submitted by callers (e.g. tab_store +
  /// chat_session_controller both firing on the same commit). Without dedup the
  /// aggregate doubles (observed: store=1357, ui=2714). We remember the last
  /// 32 (old→new) signatures per scope and skip duplicates on next calls.
  void applyNotifiableDeltas(List<ConversationUnreadDelta> deltas) {
    if (_sdkSourceActive) {
      // A notifiable count can reach zero because of mute/archive. It says
      // nothing about raw unread. Explicit reads and SDK rows update raw counts.
      _publishSdkSums();
      return;
    }
    if (deltas.isEmpty) {
      return;
    }
    _deltaCommitCount++;
    var c2c = _c2cNotifiableUnreadSum;
    var group = _groupNotifiableUnreadSum;
    var touched = false;
    for (final sample in deltas) {
      if (sample.delta == 0) {
        continue;
      }
      final conversationKey = _deltaConversationKey(sample);
      if (conversationKey.isNotEmpty) {
        final previous = _lastNotifiableByConversation[conversationKey];
        if (previous == sample.newNotifiable) continue;
        _lastNotifiableByConversation[conversationKey] = sample.newNotifiable;
      } else {
        final key = sample.deltaKey;
        if (_recentDeltaKeys.contains(key)) continue;
        _recordRecentDeltaKey(key);
      }
      touched = true;
      if (sample.isGroup) {
        group = math.max(0, group + sample.delta);
      } else {
        c2c = math.max(0, c2c + sample.delta);
      }
    }
    if (!touched) {
      return;
    }
    if (c2c == _c2cNotifiableUnreadSum && group == _groupNotifiableUnreadSum) {
      return;
    }
    _c2cNotifiableUnreadSum = c2c;
    _groupNotifiableUnreadSum = group;
    notifyListeners();
  }

  /// FIFO sliding window of recently applied delta signatures.
  final ListQueue<String> _recentDeltaKeys = ListQueue<String>();
  final Set<String> _recentDeltaKeySet = <String>{};

  void _recordRecentDeltaKey(String key) {
    _recentDeltaKeys.addLast(key);
    _recentDeltaKeySet.add(key);
    while (_recentDeltaKeys.length > _deltaDedupeWindow) {
      final evicted = _recentDeltaKeys.removeFirst();
      _recentDeltaKeySet.remove(evicted);
    }
  }

  /// 编辑态按 scope 全部已读时立即隐藏 Tab 角标；随后仍由本地库刷新校准。
  void clearScopeOptimistically({required bool isGroup}) {
    clearSdkTotalForLocalProjection();
    if (_sdkSourceActive) {
      for (final entry in _sdkRows.entries) {
        if (ConversationUnreadUtils.isGroupConversation(entry.value) !=
            isGroup) {
          continue;
        }
        entry.value.unreadCount = 0;
        _sdkRowRevisions[entry.key] = ++_sdkRevision;
      }
      _publishSdkSums();
      return;
    }
    var changed = false;
    if (isGroup) {
      _lastNotifiableByConversation
          .removeWhere((key, _) => key.startsWith('g|'));
      changed = _groupNotifiableUnreadSum != 0;
      _groupNotifiableUnreadSum = 0;
    } else {
      _lastNotifiableByConversation
          .removeWhere((key, _) => key.startsWith('c|'));
      changed = _c2cNotifiableUnreadSum != 0;
      _c2cNotifiableUnreadSum = 0;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> refreshFromStore({String reason = 'manual'}) async {
    // An explicit refresh supersedes any queued debounce for the same state.
    // This also prevents a manually confirmed zero from running again after
    // the account boundary or test teardown has already cleared its owner.
    _debounce?.cancel();
    _debounce = null;
    _debounceReason = null;
    _idleDebounce?.cancel();
    _idleDebounce = null;
    _idleReason = null;
    if (_refreshInFlight != null) {
      _refreshDirty = true;
      return _refreshInFlight!;
    }
    final generation = _sessionClearGeneration;
    final task = _sdkSourceActive
        ? _refreshFromSdk()
        : _refreshFromStoreOnce(reason: reason);
    _refreshInFlight = task;
    try {
      await task;
    } finally {
      if (generation == _sessionClearGeneration &&
          identical(_refreshInFlight, task)) {
        _refreshInFlight = null;
        if (_refreshDirty) {
          _refreshDirty = false;
          unawaited(refreshFromStore(reason: 'dirty_retry'));
        }
      }
    }
  }

  /// Same resolution order as [ConversationLocalStore] `_resolveOwner(null)`:
  /// debug override (tests) then login user id.
  String _resolvedOwnerForRefresh() {
    return ConversationLocalStore.instance.resolvedOwnerUserId().trim();
  }

  Future<void> _refreshFromStoreOnce({required String reason}) async {
    final owner = _resolvedOwnerForRefresh();
    if (owner.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'ConversationUnreadAggregate: skip refresh reason=$reason '
          '(empty owner; keep c2c=$_c2cNotifiableUnreadSum '
          'group=$_groupNotifiableUnreadSum)',
        );
      }
      return;
    }
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: owner,
    );
    final clearGeneration = _sessionClearGeneration;
    final deltaRevision = _deltaCommitCount;
    _storeCalibrationCount++;

    final archivedC2c = archivedConversationC2cIDsNotifier.value;
    final archivedGroup = archivedConversationGroupIDsNotifier.value;
    final excludedUserIds = <String>{
      ...PlatformOfficialAccountService.officialAccountIds.where(
        PlatformOfficialAccountService.shouldHideInConversationList,
      ),
    };
    final sums =
        await ConversationLocalStore.instance.sumNotifiableUnreadByScope(
      archivedC2c: archivedC2c,
      archivedGroup: archivedGroup,
      excludedUserIds: excludedUserIds,
      ownerUserId: owner,
    );
    if (_sdkSourceActive ||
        clearGeneration != _sessionClearGeneration ||
        !SessionIdentityService.instance.isCurrent(
          identity,
          currentOwnerUserId: _resolvedOwnerForRefresh(),
        )) {
      return;
    }

    if (deltaRevision != _deltaCommitCount) {
      // A row changed during the SQL read. Retry instead of overwriting its
      // newer delta with a potentially older snapshot.
      _refreshDirty = true;
      return;
    }

    final goingToAllZero = sums.c2c == 0 && sums.group == 0;
    final hadUnread =
        _c2cNotifiableUnreadSum > 0 || _groupNotifiableUnreadSum > 0;
    if (goingToAllZero &&
        hadUnread &&
        !_allowZeroRefreshReasons.contains(reason)) {
      // R1: 连续 defer 超过上限后强制清零。避免 Store 写入延迟时
      // 新消息的 scheduleRefresh 反复取消 zero_confirm debounce，
      // 导致聚合永远不更新（Tab 角标不显示但会话行有红点）。
      if (_zeroConfirmDeferrals >= _maxZeroConfirmDeferrals) {
        _zeroConfirmDeferrals = 0;
      } else {
        _zeroConfirmDeferrals++;
        scheduleRefresh(reason: zeroConfirmReason);
        return;
      }
    } else {
      // 非零结果或确认清零成功——重置计数器。
      _zeroConfirmDeferrals = 0;
    }

    // The absolute store snapshot establishes a new delta baseline.
    _lastNotifiableByConversation.clear();
    _recentDeltaKeys.clear();
    _recentDeltaKeySet.clear();
    if (sums.c2c == _c2cNotifiableUnreadSum &&
        sums.group == _groupNotifiableUnreadSum) {
      // The app badge prefers sdkTotalUnreadCount when it is available.
      // A local read/zero reconciliation can legitimately reach zero before
      // Tencent emits its next total-unread callback; keeping the old SDK
      // snapshot here leaves a stale bottom-tab badge even though every
      // conversation row is already read.  Once the local store confirms
      // both scopes are zero, the SDK snapshot is no longer authoritative.
      if (sums.c2c == 0 && sums.group == 0 && _sdkTotalUnreadCount != null) {
        _sdkTotalUnreadCount = null;
        notifyListeners();
      }
      return;
    }
    // A stable store snapshot must also reconcile decreases (read, mute,
    // archive). Clamping to the previous total leaves phantom unread counts.
    final effectiveC2c = sums.c2c;
    final effectiveGroup = sums.group;
    _c2cNotifiableUnreadSum = effectiveC2c;
    _groupNotifiableUnreadSum = effectiveGroup;
    // Do not let a stale SDK aggregate override a confirmed local zero in
    // AppBadgeUnreadUtils.totalAppBadgeUnreadCount().  This is intentionally
    // done only after the existing zero-confirm/decrease rules have accepted
    // the store result, so the anti-regression protection remains intact.
    if (effectiveC2c == 0 &&
        effectiveGroup == 0 &&
        _sdkTotalUnreadCount != null) {
      _sdkTotalUnreadCount = null;
    }
    notifyListeners();
  }

  @visibleForTesting
  void setSumsForTest({required int c2c, required int group}) {
    _c2cNotifiableUnreadSum = c2c;
    _groupNotifiableUnreadSum = group;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _sdkUnreadSeeded = false;
    _sdkContributions.clear();
    _sdkC2cSum = 0;
    _sdkGroupSum = 0;
    sdkRowsEvaluatedForTest = 0;
    _sdkSourceActive = false;
    _sdkRows.clear();
    _sdkRowRevisions.clear();
    _sdkRevision = 0;
    sdkPageForTest = null;
    _debounce?.cancel();
    _debounce = null;
    _debounceReason = null;
    _idleDebounce?.cancel();
    _idleDebounce = null;
    _idleReason = null;
    _refreshInFlight = null;
    _refreshDirty = false;
    _zeroConfirmDeferrals = 0;
    _c2cNotifiableUnreadSum = 0;
    _groupNotifiableUnreadSum = 0;
    _sdkTotalUnreadCount = null;
    _deltaCommitCount = 0;
    _storeCalibrationCount = 0;
    _scheduledRefreshCount = 0;
    _recentDeltaKeys.clear();
    _recentDeltaKeySet.clear();
    _lastNotifiableByConversation.clear();
    _sessionClearGeneration++;
  }

  @visibleForTesting
  int get deltaCommitCountForTest => _deltaCommitCount;

  @visibleForTesting
  int get storeCalibrationCountForTest => _storeCalibrationCount;

  @visibleForTesting
  int get scheduledRefreshCountForTest => _scheduledRefreshCount;

  @visibleForTesting
  Duration debounceForReasonForTest(String reason) {
    if (isRealtimeRefreshReason(reason)) {
      return _realtimeDebounce;
    }
    return isBulkRefreshReason(reason) ? _bulkDebounce : _defaultDebounce;
  }

  void clearSession() {
    _sdkUnreadSeeded = false;
    _sdkContributions.clear();
    _sdkC2cSum = 0;
    _sdkGroupSum = 0;
    _sdkSourceActive = false;
    _sdkRows.clear();
    _sdkRowRevisions.clear();
    _sdkRevision = 0;
    _sessionClearGeneration++;
    _debounce?.cancel();
    _debounce = null;
    _debounceReason = null;
    _idleDebounce?.cancel();
    _idleDebounce = null;
    _idleReason = null;
    _refreshInFlight = null;
    _refreshDirty = false;
    _zeroConfirmDeferrals = 0;
    _sdkTotalUnreadCount = null;
    _recentDeltaKeys.clear();
    _recentDeltaKeySet.clear();
    _lastNotifiableByConversation.clear();
    if (_c2cNotifiableUnreadSum == 0 && _groupNotifiableUnreadSum == 0) {
      return;
    }
    _c2cNotifiableUnreadSum = 0;
    _groupNotifiableUnreadSum = 0;
    notifyListeners();
  }
}
