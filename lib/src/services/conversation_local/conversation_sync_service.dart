import 'package:tencent_cloud_chat_demo/src/services/im/message_core_owner.dart';
import 'dart:async';
import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/services/coalesced_async_flush.dart';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_deleted_bus.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_patch_hydrator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_pending_sdk_sync.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_pin_hydrate_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/c2c_history_backfill.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_sync_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_snapshot_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/resume_foreground_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_signaling.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_conversation_visibility.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_last_message_prefer.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/src/utils/archive_conversation_lookup.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/typing_status_message.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_display_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_conversation_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/mobile_async_commit_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/runtime_ingress_processor.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_recovery_worker.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/heartbeat_tick.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

class _PendingConversationEvent {
  const _PendingConversationEvent({
    required this.ownerUserId,
    required this.ownerGeneration,
    required this.canonicalConversationId,
    required this.sequence,
    required this.source,
    required this.allowRecreate,
    required this.reason,
    required this.snapshot,
    required this.fingerprint,
    this.identity,
  });

  final String ownerUserId;
  final int ownerGeneration;
  final String canonicalConversationId;
  final int sequence;
  final ConversationMutationSource source;
  final bool allowRecreate;
  final String reason;
  final V2TimConversation snapshot;
  final String fingerprint;
  final SessionIdentity? identity;
}

enum ConversationBootstrapResult {
  success,

  /// The business conversation projection is already usable. No SDK first
  /// page was pulled; realtime deltas and user-driven pagination remain active.
  localReady,
  provisional,
  failed,
  deferred,
  stale,
}

extension ConversationBootstrapResultX on ConversationBootstrapResult {
  bool get isSuccess =>
      this == ConversationBootstrapResult.success ||
      this == ConversationBootstrapResult.localReady;

  bool get isUsable =>
      this == ConversationBootstrapResult.success ||
      this == ConversationBootstrapResult.localReady ||
      this == ConversationBootstrapResult.provisional;
}

/// SDK 监听与恢复的会话边界。主列表使用 [ConversationTabStore]；
/// 仅业务归档索引、未完成命令等必要状态继续使用应用持久化。
class ConversationSyncService {
  ConversationSyncService._();

  static final ConversationSyncService instance = ConversationSyncService._();

  final _archivedSdkChanges =
      StreamController<List<V2TimConversation>>.broadcast();
  Stream<List<V2TimConversation>> get archivedSdkChanges =>
      _archivedSdkChanges.stream;

  List<V2TimConversation> _archivedRows(List<V2TimConversation> rows) {
    final c2c =
        cachedArchiveLookupTokenSet(archivedConversationC2cIDsNotifier.value);
    final groups =
        cachedArchiveLookupTokenSet(archivedConversationGroupIDsNotifier.value);
    return rows
        .where((row) => conversationIdInArchivedLookup(
              row.type == ConversationType.V2TIM_GROUP ? groups : c2c,
              row.conversationID,
            ))
        .toList(growable: false);
  }

  void _queueArchivedSdkChanges(
      List<V2TimConversation> rows, SessionIdentity identity,
      {bool allowRecreate = false}) {
    final archived = _archivedRows(rows);
    if (archived.isEmpty) return;
    _enqueuePersistChanged(archived,
        reason: 'archived_sdk_projection',
        prepare: false,
        source: ConversationMutationSource.sdkRealtime,
        allowRecreate: allowRecreate,
        identity: identity);
  }

  static const int _defaultPageSize = 40;
  static const Duration _c2cBackfillProbeTimeout = Duration(seconds: 8);

  bool _installed = false;
  bool _pageSyncInFlight = false;
  int _syncGeneration = 0;
  int _messageDomainGeneration = 0;
  final MobileAsyncCommitGuard _lifecycleGuard = MobileAsyncCommitGuard();
  V2TimConversationListener? _listener;
  TencentAdvancedMessageAdapter? _messageAdapter;
  bool _messageListenerAttached = false;
  Future<void>? _messageListenerAttachInFlight;
  Future<void> _realtimeLifecycleTail = Future<void>.value();
  Timer? _messageListenerRetryTimer;
  Timer? _conversationListenerRetryTimer;
  Future<void>? _conversationListenerAttachInFlight;
  bool _conversationListenerAttached = false;
  final ConversationPatchHydrator _conversationPatchHydrator =
      ConversationPatchHydrator();
  SessionIdentity? _realtimeIdentity;
  bool _realtimeTeardownInFlight = false;
  Future<void>? _realtimeActivationInFlight;
  SessionIdentity? _realtimeActivationIdentity;
  ImRecoveryWorker? _messageRecoveryWorker;
  static const Duration _messageRecoveryInterval = Duration(seconds: 30);
  late final ImIngressStore _messageIngressStore =
      createPlatformImIngressStore();
  late final DurableIngressGateway _messageIngress = DurableIngressGateway(
    store: _messageIngressStore,
  );
  late final ImWriterLeaseService _messageWriterLeaseService =
      ImWriterLeaseService(
    store: _messageIngressStore,
    prepareOwner: MessageCoreOwner.instance.prepareLeaseOwner,
    isOwnerAbandoned: MessageCoreOwner.instance.isAbandoned,
  );
  late final ImMailboxRouter _messageMailbox = ImMailboxRouter(
    handler: _handleMessageIngress,
  );
  String get _messageCoreLeaseOwnerId => MessageCoreOwner.instance.id;
  ImWriterLease? _messageCoreLease;
  Timer? _messageCoreHeartbeatTimer;
  Timer? _messageCoreAcquireRetryTimer;
  Future<void>? _messageCoreHeartbeatInFlight;
  Future<bool>? _messageCoreAcquireInFlight;
  SessionIdentity? _messageCoreAcquireIdentity;
  SessionIdentity? _messageCoreBlockedIdentity;
  int _messageCoreBlockedUntilMs = 0;
  // Message-core transactions are serialized with ingress writes. During a
  // large-member/history burst a single SQLite turn can exceed 15 seconds;
  // keep the lease alive across that scheduling jitter while retaining the
  // 5-second heartbeat and fencing checks.
  static const int _messageCoreLeaseTtlMs = 60000;
  static const Duration _messageCoreHeartbeatInterval = Duration(seconds: 5);
  static const Duration _messageCoreAcquireRetryDelay = Duration(seconds: 5);
  DateTime? _lastSyncServerFinishAt;
  Timer? _syncServerFinishTimer;
  bool _sdkServerSyncPending = false;
  Future<ConversationBootstrapResult>? _sdkBootstrapTask;
  String _sdkBootstrapOwner = '';
  int _sdkBootstrapGeneration = -1;
  bool _sdkBootstrapResets = false;
  static const Duration _syncServerFinishDelay = Duration(milliseconds: 350);

  void invalidateLifecycle() {
    _lifecycleGuard.advancePage();
  }

  void setInboxRecoveryForeground(bool foreground) {
    InboxRecoveryCoordinator.instance.setForeground(foreground);
    if (!foreground) return;
    final identity = _realtimeIdentity;
    if (identity == null) return;
    InboxRecoveryCoordinator.instance.request(
      trigger: InboxRecoveryTrigger.resume,
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
    );
  }

  /// 冷启动 bootstrap 可能在 SDK 离线消息入库前完成；需等 [onSyncServerFinish] 后再拉一次。
  Future<void>? _c2cHistoryBackfillInFlight;
  bool _c2cHistoryBackfillScheduled = false;

  /// 本登录已对「已有本地单聊壳」做过预览/置顶/免打扰富化，避免每次 syncFinish 重扫。
  bool _c2cMetadataEnrichDone = false;

  /// 本登录已做过（或尝试过）好友/置顶补壳扫描。
  bool _c2cFriendScanDone = false;
  ConversationPendingSdkSync? _pendingSdkSync;
  bool _backgroundDrainInFlight = false;
  Timer? _idleDrainTimer;

  /// 本登录会话内 idle/background drain 已拉页数（防误开 flag 时无限 resume）。
  int _idleDrainSessionPages = 0;

  /// 本登录会话内 idle/background drain 已触发的次数（cycle 数）。
  /// 与 [_idleDrainSessionPages] 不同：cycle 数包含 cancel / paused 等没有
  /// 实际拉页的触发；用于在到达上限后停止自动 scheduleIdleBackgroundDrain。
  int _idleDrainCycleCount = 0;
  DateTime? _resumeQuietUntil;
  Future<void>? _scopeHydrationTask;
  bool _scopeHydrationDone = false;
  final Map<String, V2TimMessage> _pendingPatches = <String, V2TimMessage>{};
  int _patchesQueuedDuringSync = 0;
  Timer? _pendingPatchesForceTimer;
  DateTime? _pendingPatchesFirstQueuedAt;

  String? _lastMarkReadId;
  DateTime? _lastMarkReadAt;
  static const Duration _markReadDebounce = Duration(milliseconds: 400);

  Timer? _reloadUiCoalesceTimer;
  int _chatTransitionDepth = 0;
  static const Duration _globalReloadDebounce = Duration(milliseconds: 80);

  /// 返回列表后先让用户手势（左右滑）稳定，再合并落盘刷新，避免与 Slidable 抢主线程。
  static const Duration _postPopCoalesceWindow = Duration(milliseconds: 1400);
  static const Duration _postPopMinFlushDelay = Duration(milliseconds: 700);
  static const Duration _postPopTrailingDebounce = Duration(milliseconds: 200);
  DateTime? _postPopCoalesceUntil;
  DateTime? _postPopCoalesceWindowStart;
  bool _postPopCoalesceScheduled = false;

  /// 合并队列里是否有人要求整窗快照 reload（冷启等白名单）。
  bool _pendingCoalesceForceFull = false;
  Future<void>? _sdkProjectionRestoreInFlight;
  bool _sdkProjectionRestoreDirty = false;
  bool _sdkProjectionRestoreDirtyForceFull = false;

  final List<_PendingConversationEvent> _pendingPersistEvents =
      <_PendingConversationEvent>[];
  static const int _pendingPersistEventCap = 512;
  String _pendingPersistOwner = '';
  int _pendingPersistOwnerGeneration = 0;
  Future<void> _persistFlushTail = Future<void>.value();
  final Map<String, String> _viewModelPersistFingerprints = <String, String>{};
  final Map<String, String> _persistInFlightFingerprints = <String, String>{};
  Timer? _persistDedupTimer;
  int _persistCommitSequence = 0;
  final Map<String, int> _latestPersistSequenceById = <String, int>{};
  String? _recentlyLeftConversationId;

  /// 群成员库尚未含本人时到达的群会话：先挂起，入群后再落库上屏（避免杀进程才看见）。
  final LinkedHashMap<String, V2TimConversation>
      _pendingNonMemberGroupConversations =
      LinkedHashMap<String, V2TimConversation>();
  static const int _pendingNonMemberGroupCap = 256;
  Timer? _membershipExpandReloadTimer;
  final Set<String> _pendingGroupRecoveryScheduled = <String>{};

  @visibleForTesting
  int projectionRestoreInvocationCount = 0;

  @visibleForTesting
  int persistFlushInvocationCount = 0;

  @visibleForTesting
  bool get projectionRestoreInFlightForTest =>
      _sdkProjectionRestoreInFlight != null;

  @visibleForTesting
  bool get projectionRestoreDirtyForTest => _sdkProjectionRestoreDirty;

  @visibleForTesting
  Future<void> Function()? projectionRestoreImplOverride;

  @visibleForTesting
  Future<void> Function(String conversationID)? markReadStoreOverride;

  @visibleForTesting
  Future<List<V2TimConversation>> Function(List<V2TimConversation>)?
      upsertBatchOverride;

  @visibleForTesting
  Future<V2TimConversation?> Function(String conversationID)?
      debugGetConversationOverride;

  @visibleForTesting
  String? debugOwnerUserId;

  /// 单测注入 ByFilter 拉页。
  @visibleForTesting
  static Future<
          ({
            List<V2TimConversation> conversationList,
            String nextSeq,
            bool isFinished,
            int code,
            String desc,
          })>
      Function({
    required int convType,
    required String nextSeq,
    required int count,
  })? debugGetConversationListByFilterOverride;

  bool get hasActiveChatTransition => _chatTransitionDepth > 0;

  bool get _isFeedScrollingNow =>
      ChatSessionController.instance.isFeedScrollingNow;

  bool get _isUiBusyForPersist =>
      _isFeedScrollingNow ||
      hasActiveChatTransition ||
      isInPostPopCoalesceWindow ||
      ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat;

  Duration get _effectivePersistDedupDelay => _isUiBusyForPersist
      ? ConversationPerfFlags.persistDedupDelayBusy
      : ConversationPerfFlags.persistDedupDelay;

  bool _isConversationListenerPersistReason(String reason) {
    final r = reason.trim();
    return r == 'changed' ||
        r == 'new' ||
        r == 'coalesced:changed' ||
        r == 'coalesced:new' ||
        r.startsWith('coalesced:changed') ||
        r.startsWith('coalesced:new');
  }

  Duration _persistDedupDelayForReason(String reason) {
    if (_isConversationListenerPersistReason(reason)) {
      return _isUiBusyForPersist
          ? ConversationPerfFlags.persistDedupDelayConversationListenerBusy
          : ConversationPerfFlags.persistDedupDelayConversationListener;
    }
    return _effectivePersistDedupDelay;
  }

  @visibleForTesting
  bool shouldMarkReadReloadImmediately() {
    return _chatTransitionDepth > 0 && !isInPostPopCoalesceWindow;
  }

  @visibleForTesting
  void resetChatTransitionStateForTesting() {
    _reloadUiCoalesceTimer?.cancel();
    _reloadUiCoalesceTimer = null;
    _chatTransitionDepth = 0;
    _postPopCoalesceUntil = null;
    _postPopCoalesceWindowStart = null;
    _postPopCoalesceScheduled = false;
    projectionRestoreInvocationCount = 0;
    projectionRestoreImplOverride = null;
    markReadStoreOverride = null;
    upsertBatchOverride = null;
    debugGetConversationOverride = null;
    debugOwnerUserId = null;
    _sdkProjectionRestoreInFlight = null;
    _sdkProjectionRestoreDirty = false;
    _sdkProjectionRestoreDirtyForceFull = false;
    _pendingCoalesceForceFull = false;
    _persistDedupTimer?.cancel();
    _persistDedupTimer = null;
    _persistCommitSequence = 0;
    _latestPersistSequenceById.clear();
    _pendingPersistEvents.clear();
    _pendingPersistOwner = '';
    _pendingPersistOwnerGeneration++;
    _persistFlushTail = Future<void>.value();
    _viewModelPersistFingerprints.clear();
    _persistInFlightFingerprints.clear();
    persistFlushInvocationCount = 0;
    _recentlyLeftConversationId = null;
    _pendingSdkSync = null;
    _backgroundDrainInFlight = false;
    _idleDrainTimer?.cancel();
    _idleDrainTimer = null;
    _idleDrainSessionPages = 0;
    _idleDrainCycleCount = 0;
    _resumeQuietExitTimer?.cancel();
    _resumeQuietExitTimer = null;
    _resumeQuietUntil = null;
    _uiApplyPendingAfterQuietOrScroll = false;
    _pendingUiApplyById.clear();
    _deferredViewModelPersistById.clear();
    _sdkSyncResumeAfterScroll = false;
    _reloadUiDeferredWhileScrolling = false;
    _scrollEndFlushTimer?.cancel();
    _scrollEndFlushTimer = null;
    _pendingPatchesForceTimer?.cancel();
    _pendingPatchesForceTimer = null;
    _pendingPatchesFirstQueuedAt = null;
    _pendingPatches.clear();
    _patchesQueuedDuringSync = 0;
    ConversationListSyncNotifier.instance.setDraining(false);
  }

  @visibleForTesting
  Future<void> notifyUiAfterLocalWriteForTest({
    List<V2TimConversation> upserted = const [],
    V2TimConversation? updated,
  }) {
    return _notifyUiAfterLocalWrite(upserted: upserted, updated: updated);
  }

  @visibleForTesting
  Future<void> applyPacedSyncPageToUiForTest(
    List<V2TimConversation> merged, {
    String reason = 'test',
  }) {
    return _applyPacedSyncPageToUi(merged, reason: reason, allowDefer: false);
  }

  @visibleForTesting
  void notePendingUiApplyForTest(
    List<V2TimConversation> conversations, {
    String via = 'test',
    String cause = 'test',
  }) {
    _notePendingUiApply(conversations, via: via, cause: cause);
  }

  @visibleForTesting
  Future<void> forceFlushPendingPatchesForTest() {
    return _forceFlushPendingPatches(reason: 'test');
  }

  @visibleForTesting
  int get pendingPreviewPatchCountForTest => _pendingPatches.length;

  @visibleForTesting
  void queuePendingPreviewPatchForTest({
    required String conversationId,
    required V2TimMessage message,
  }) {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    _pendingPatches[id] = message;
    _patchesQueuedDuringSync++;
    _pendingPatchesFirstQueuedAt ??= DateTime.now();
  }

  @visibleForTesting
  int get pendingUiApplyCountForTest => _pendingUiApplyById.length;

  @visibleForTesting
  Future<void> flushPendingUiApplyForTest({required String reason}) {
    return _flushPendingUiApply(reason: reason);
  }

  @visibleForTesting
  static bool shouldScheduleIdleDrainResume({
    required bool idleBackgroundDrainEnabled,
    required bool haveMore,
    required int sessionDrainPages,
    required int sessionDrainPageBudget,
  }) {
    if (!idleBackgroundDrainEnabled) {
      return false;
    }
    if (!haveMore) {
      return false;
    }
    if (sessionDrainPageBudget > 0 &&
        sessionDrainPages >= sessionDrainPageBudget) {
      return false;
    }
    return true;
  }

  @visibleForTesting
  static bool shouldQueueSyncServerFinishDuringPageSync({
    required bool needsFullReset,
    required bool awaitingPostServerSync,
  }) {
    return needsFullReset || awaitingPostServerSync;
  }

  @visibleForTesting
  static bool shouldUsePostPopLightReload({
    required bool inPostPopWindow,
    required bool postPopLightReloadEnabled,
  }) {
    return postPopLightReloadEnabled && inPostPopWindow;
  }

  @visibleForTesting
  bool shouldSuppressStaleUnreadForTest(String conversationID) {
    return shouldSuppressStaleUnread(conversationID);
  }

  bool shouldSuppressStaleUnread(String conversationID) {
    if (!isInPostPopCoalesceWindow) {
      return false;
    }
    final left = _recentlyLeftConversationId?.trim() ?? '';
    if (left.isEmpty) {
      return false;
    }
    return MessageConversationId.sameConversation(conversationID, left);
  }

  bool get isInPostPopCoalesceWindow {
    final until = _postPopCoalesceUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void beginChatTransition() {
    _chatTransitionDepth++;
    _reloadUiCoalesceTimer?.cancel();
    _reloadUiCoalesceTimer = null;
    _postPopCoalesceScheduled = false;
  }

  void cancelChatTransition() {
    if (_chatTransitionDepth > 0) {
      _chatTransitionDepth--;
    }
    _reloadUiCoalesceTimer?.cancel();
    _reloadUiCoalesceTimer = null;
  }

  void schedulePostPopCoalesceWindow({String? conversationID}) {
    if (_postPopCoalesceScheduled) {
      return;
    }
    if (_chatTransitionDepth <= 0 && _postPopCoalesceUntil == null) {
      return;
    }
    _postPopCoalesceScheduled = true;
    if (_chatTransitionDepth > 0) {
      _chatTransitionDepth--;
    }
    final explicit = conversationID?.trim() ?? '';
    _recentlyLeftConversationId = explicit.isNotEmpty
        ? explicit
        : ActiveChatRegistry.instance.activeConversationId;
    ConversationUnreadTrace.log(
      'post_pop_window_start',
      conversationID: _recentlyLeftConversationId,
      extras: <String, Object?>{
        'depth': _chatTransitionDepth,
        'windowMs': _postPopCoalesceWindow.inMilliseconds,
      },
    );
    _postPopCoalesceUntil = DateTime.now().add(_postPopCoalesceWindow);
    _postPopCoalesceWindowStart = DateTime.now();
    _scheduleCoalescedReloadUi(postPop: true);
  }

  Future<void> flushPendingProjectionRestore() async {
    _reloadUiCoalesceTimer?.cancel();
    _reloadUiCoalesceTimer = null;
    _postPopCoalesceUntil = null;
    _postPopCoalesceWindowStart = null;
    _postPopCoalesceScheduled = false;
    final forceFull = _pendingCoalesceForceFull;
    _pendingCoalesceForceFull = false;
    // 默认 soft：保留滑动窗；仅队列里曾要求 forceFull 时整窗快照。
    await _restoreSdkProjectionImpl(forceFull: forceFull);
    _recentlyLeftConversationId = null;
  }

  ConversationService get _conversationService =>
      serviceLocator<ConversationService>();

  /// 用 `/me/groups` 的真实群名回填会话列表，避免标题显示 `@TGS#_@TGS#…`。
  Future<void> applyGroupDisplayNames(Iterable<MeGroupRecord> records) async {
    final byToken = <String, String>{};
    final avatarByToken = <String, String>{};
    for (final record in records) {
      final groupId = record.groupId.trim();
      if (groupId.isEmpty) {
        continue;
      }
      final name = record.groupName.trim();
      final token = ChatIdFormat.groupEquivalenceToken(groupId) ?? groupId;
      if (name.isNotEmpty &&
          !GroupDisplayResolver.looksLikeGroupIdLabel(name, groupId: groupId)) {
        byToken[token] = name;
        DisplayNameStore.instance.setGroup(groupId, name, notify: false);
        final canonical = ChatIdFormat.canonicalGroupStorageId(groupId);
        if (canonical.isNotEmpty) {
          DisplayNameStore.instance.setGroup(canonical, name, notify: false);
        }
      }
      final avatar = record.avatarUrl.trim();
      if (avatar.isNotEmpty) {
        avatarByToken[token] = avatar;
      }
    }
    if (byToken.isEmpty && avatarByToken.isEmpty) {
      return;
    }

    final committed = <V2TimConversation>[];
    for (final conversation in ChatSessionController.instance.conversations) {
      final groupId = conversation.groupID?.trim() ?? '';
      if (groupId.isEmpty) {
        continue;
      }
      final token = ChatIdFormat.groupEquivalenceToken(groupId) ?? groupId;
      final name = byToken[token];
      final avatar = avatarByToken[token];
      String? patchedName;
      String? patchedAvatar;
      if (name != null && name.isNotEmpty) {
        final current = conversation.showName?.trim() ?? '';
        if (current != name) {
          patchedName = name;
        }
      }
      if (avatar != null && avatar.isNotEmpty) {
        final currentFace = conversation.faceUrl?.trim() ?? '';
        if (currentFace != avatar) {
          patchedAvatar = avatar;
        }
      }
      if (patchedName != null || patchedAvatar != null) {
        final updated = await applyConversationMetadataPatch(
          conversationID: conversation.conversationID,
          showName: patchedName,
          faceUrl: patchedAvatar,
          snapshot: conversation,
          remoteAuthority: true,
        );
        if (updated != null) {
          committed.add(updated);
        }
      }
    }
    if (committed.isNotEmpty) {
      await _notifyUiAfterLocalWrite(upserted: committed);
    }
  }

  /// 会话同步明细日志。默认关闭：冷启/删除风暴时 print 极密，debug/release 均会刷屏。
  static const bool _logEnabled = false;

  static void _log(String message) {
    if (!_logEnabled) return;
    debugPrint('ConversationSync: $message');
  }

  void install() {
    if (_installed) {
      return;
    }
    _installed = true;
  }

  /// AuthBootstrapService owns the SDK-session generation. Conversation
  /// pagination keeps its separate request lock generation in [_syncGeneration].
  /// Keeping these values distinct prevents a page reset from invalidating
  /// otherwise valid realtime message events.
  void setMessageDomainGeneration(int generation) {
    if (generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'must not be negative',
      );
    }
    if (generation < _messageDomainGeneration) {
      throw StateError(
        'message domain generation cannot move backwards: '
        'current=$_messageDomainGeneration next=$generation',
      );
    }
    _messageDomainGeneration = generation;
  }

  V2TimConversationListener _createConversationListener(
    SessionIdentity identity,
  ) {
    _listener = V2TimConversationListener(
      onConversationChanged: (list) {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        // SDK callbacks own conversation fields. Only the backend-managed
        // archive subset also needs a business index for archive pagination.
        if (list.isNotEmpty) {
          ChatSessionController.instance.applyPendingRealtimeProjection(
            list,
            reason: 'sdk_realtime_authoritative',
            preserveOrder: false,
          );
          unawaited(_hydrateIncompleteConversationPatches(list, identity));
          _queueArchivedSdkChanges(list, identity);
          // D2 v15/v16 改造：可观测性埋点，验证 long-connection push 到达率。
          StartupPerfLog.markTagged(
            'conv_push_changed',
            category: 'realtime',
            details: <String, Object>{
              'count': list.length,
              'ids': list.take(10).map((c) => c.conversationID).toList(),
              'owner': identity.ownerUserId,
            },
          );
        }
      },
      onNewConversation: (list) {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        if (list.isNotEmpty) {
          ChatSessionController.instance.applyPendingRealtimeProjection(
            list,
            reason: 'sdk_realtime_authoritative_new',
          );
          unawaited(_hydrateIncompleteConversationPatches(list, identity));
          _queueArchivedSdkChanges(list, identity, allowRecreate: true);
          // D1 v15/v16 改造：可观测性埋点，验证 long-connection 新会话到达率。
          StartupPerfLog.markTagged(
            'conv_push_new',
            category: 'realtime',
            details: <String, Object>{
              'count': list.length,
              'ids': list.take(10).map((c) => c.conversationID).toList(),
              'owner': identity.ownerUserId,
            },
          );
        }
      },
      onConversationDeleted: (ids) {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        ChatSessionController.instance.applyPendingRealtimeDeletion(ids);
        unawaited(_persistSdkDeleted(ids, identity: identity));
      },
      onTotalUnreadMessageCountChanged: (totalUnread) {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        ConversationUnreadAggregate.instance.applySdkTotalUnreadCount(
          totalUnread,
        );
      },
      onSyncServerStart: () {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        _sdkServerSyncPending = true;
        ImSdkRelationshipSyncAnchor.serverSyncPending = true;
        ConversationListSyncNotifier.instance.setAwaitingServerSync(true);
        NotificationSettingsService.instance.markOfflineMessageSyncStarted();
        StartupPerfLog.markTagged(
          'conv_sync_start',
          category: 'realtime',
          details: <String, Object>{
            'owner': identity.ownerUserId,
            'generation': identity.generation,
          },
        );
      },
      onSyncServerFailed: () {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        _sdkServerSyncPending = false;
        ImSdkRelationshipSyncAnchor.serverSyncPending = false;
        ConversationListSyncNotifier.instance.setAwaitingServerSync(false);
        ConversationListSyncNotifier.instance.setRetryableFailure(true);
        NotificationSettingsService.instance.markOfflineMessageSyncFinished();
        StartupPerfLog.markTagged(
          'conv_sync_failed',
          category: 'realtime',
          details: <String, Object>{
            'owner': identity.ownerUserId,
            'generation': identity.generation,
          },
        );
      },
      onSyncServerFinish: () {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        // D3 v15/v16 改造：可观测性埋点，用于审计「同步对齐完成」锚点.
        // 这个事件是 SDK 登录成功 / 上线 / 重连后同步完成的关键事件，
        // 改造工程应以该事件作为「补齐锚点」，触发 UI 同步状态反馈。
        StartupPerfLog.markTagged(
          'conv_sync_finish',
          category: 'realtime',
          details: <String, Object>{
            'owner': identity.ownerUserId,
            'generation': identity.generation,
          },
        );
        _scheduleSyncServerFinish(identity);
      },
    );
    return _listener!;
  }

  TencentAdvancedMessageAdapter _createMessageAdapter(
    SessionIdentity identity,
  ) {
    late TencentAdvancedMessageAdapter adapterForProgress;
    final adapter = TencentAdvancedMessageAdapter(
      messageService: serviceLocator<MessageService>(),
      ingress: _messageIngress,
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
      domainGeneration: _messageDomainGeneration,
      onEvent: (event) =>
          _messageMailbox.dispatch(event, lane: _laneForMessageEvent(event)),
      onSdkRealtimeEvent: (event) =>
          _messageMailbox.dispatch(event, lane: ImIngressLane.realtime),
      sdkRealtimeClearEpoch: (scope) => serviceLocator<TUIChatGlobalModel>()
          .messageDeltaClearEpochFor(scope.canonicalConversationId),
      ingressDiagnostics: () => ImAdvancedIngressDiagnostics(
        queueLength: _messageMailbox.pendingEventCount,
        queueCapacity: _messageMailbox.maxConcurrentWorkers,
        activeMailboxCount: _messageMailbox.activeMailboxCount,
        inFlightCount: _messageMailbox.inFlightEventCount,
        readyMailboxCount: _messageMailbox.readyMailboxCount,
        idleMailboxCount: _messageMailbox.idleMailboxCount,
        oldestInflightMs: _messageMailbox.oldestInflightMs,
        mailboxEvictionCount: _messageMailbox.evictionCount,
        mailboxLimitHitCount: _messageMailbox.limitHitCount,
        isClosed: !_messageListenerAttached,
        isDisposed: _realtimeTeardownInFlight ||
            !identical(_messageAdapter, adapterForProgress),
        currentAccountGeneration: _realtimeIdentity?.generation ?? -1,
        currentDomainGeneration: _messageDomainGeneration,
      ),
      isUiProgressLifecycleCurrent: () =>
          _isCurrentRealtimeIdentity(identity) &&
          identical(_messageAdapter, adapterForProgress) &&
          adapterForProgress.domainGeneration == _messageDomainGeneration,
      onUiProgress: (progress) async {
        if (!adapterForProgress.isCurrentUiProgress(progress)) return;
        final model = serviceLocator<TUIChatGlobalModel>();
        if (progress is ImMessageProgressEvent) {
          model.applyAppSendMessageProgress(
              progress.message, progress.progress);
        } else if (progress is ImMessageDownloadProgressEvent) {
          await model.applyAppMessageDownloadProgress(progress.progress,
              isCurrent: () =>
                  adapterForProgress.isCurrentUiProgress(progress));
        }
      },
      onIngestFailure: (
        draft,
        error,
        stackTrace, {
        required int attempt,
        required bool dropped,
      }) {
        if (!_isCurrentRealtimeIdentity(identity)) return;
        _log(
          'message ingress failure kind=${draft.kind.name} '
          'attempt=$attempt dropped=$dropped '
          'conversationId=${draft.scope?.canonicalConversationId ?? ''} '
          'errorType=${error.runtimeType}',
        );
        if (attempt != 1 && !dropped) return;
        final conversationId = draft.scope?.canonicalConversationId ?? '';
        if (conversationId.isNotEmpty) {
          ChatHistoryRefreshBus.instance.requestRefresh(
            conversationId: conversationId,
            reason: 'message_ingress_failure',
            delay: Duration.zero,
          );
        }
        InboxRecoveryCoordinator.instance.request(
          trigger: InboxRecoveryTrigger.pendingWrite,
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
        );
      },
    );
    adapterForProgress = adapter;
    _messageAdapter = adapter;
    return adapter;
  }

  Future<ImRecoveryPayload> _loadMessageRecoveryPayload(
    ImInboxRecord record,
  ) async {
    final identity = _realtimeIdentity;
    if (identity == null ||
        !record.event.belongsToDomain(
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
          domainGeneration: _messageDomainGeneration,
        )) {
      return const ImRecoveryPayload.unavailable();
    }
    if (record.recoveryMode == ImRecoveryMode.ephemeralUi) {
      return const ImRecoveryPayload.recovered(null);
    }

    final recoveryRef = record.recoveryRef.trim();
    const messagePrefix = 'msgID:';
    if (recoveryRef.startsWith(messagePrefix)) {
      final msgID = recoveryRef.substring(messagePrefix.length).trim();
      if (msgID.isEmpty) return const ImRecoveryPayload.unavailable();
      final messages = await serviceLocator<MessageService>().findMessages(
        messageIDList: <String>[msgID],
      );
      for (final message in messages ?? const <V2TimMessage>[]) {
        if (message.msgID?.trim() == msgID) {
          return ImRecoveryPayload.recovered(message);
        }
      }
      return const ImRecoveryPayload.unavailable();
    }

    const receiptBatchPrefix = 'receipt-batch-json:';
    if (recoveryRef.startsWith(receiptBatchPrefix)) {
      try {
        final json =
            jsonDecode(recoveryRef.substring(receiptBatchPrefix.length));
        if (json is Map &&
            json['watermark'] is bool &&
            json['receipts'] is List) {
          final rows = json['receipts'] as List;
          if (rows.isNotEmpty && rows.every((row) => row is Map)) {
            return ImRecoveryPayload.recovered(ImReadReceiptBatch(
              rows.map((row) => V2TimMessageReceipt.fromJson(row as Map)),
              applyC2CWatermark: json['watermark'] as bool,
            ));
          }
        }
      } catch (_) {}
      return const ImRecoveryPayload.unavailable();
    }

    const receiptPrefix = 'receipt-json:';
    if (recoveryRef.startsWith(receiptPrefix)) {
      try {
        final json = jsonDecode(recoveryRef.substring(receiptPrefix.length));
        if (json is Map) {
          return ImRecoveryPayload.recovered(
              V2TimMessageReceipt.fromJson(json));
        }
      } catch (_) {}
      return const ImRecoveryPayload.unavailable();
    }

    const revokePrefix = 'revoke:';
    if (recoveryRef.startsWith(revokePrefix)) {
      final msgID = recoveryRef.substring(revokePrefix.length).trim();
      if (msgID.isEmpty) return const ImRecoveryPayload.unavailable();
      return ImRecoveryPayload.recovered(ImMessageRevokedEvent(msgID: msgID));
    }
    return const ImRecoveryPayload.unavailable();
  }

  void _startMessageRecovery(SessionIdentity identity) {
    InboxRecoveryCoordinator.instance.bind(
      runner: (request) => _executeInboxRecovery(identity, request),
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
    );
    InboxRecoveryCoordinator.instance.markRealtimeLinkReady();
    InboxRecoveryCoordinator.instance.request(
      trigger: InboxRecoveryTrigger.reconnect,
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
    );
  }

  Future<InboxRecoveryBatchResult> _executeInboxRecovery(
    SessionIdentity identity,
    InboxRecoveryRunRequest request,
  ) async {
    if (!_isCurrentRealtimeIdentity(identity) ||
        identity.ownerUserId != request.ownerUserId ||
        identity.generation != request.accountGeneration) {
      return const InboxRecoveryBatchResult();
    }
    final lease = _messageCoreLease;
    if (lease == null) return const InboxRecoveryBatchResult();
    final persist = MessagePersistCoordinator.instance;
    final worker = ImRecoveryWorker(
      gateway: _messageIngress,
      router: _messageMailbox,
      lease: lease,
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
      domainGeneration: _messageDomainGeneration,
      loadPayload: _loadMessageRecoveryPayload,
      processingTimeoutMs: _messageRecoveryInterval.inMilliseconds,
    );
    _messageRecoveryWorker = worker;
    try {
      final result = await worker.run(
        nowMs: request.nowMs,
        limit: request.batchSize,
        phase: request.phase,
        activeConversationId: request.activeConversationId,
        allowBackground: persist.shouldProduceBackground &&
            (request.phase == ReconnectRecoveryPhase.backgroundHistory ||
                request.trigger == InboxRecoveryTrigger.timerFallback),
        persistPriority: persist.hasRealtimeBacklog
            ? MessagePersistPriority.backgroundRepair
            : MessagePersistPriority.userHistory,
      );
      if (result.scanned > 0) {
        _log(
          'message recovery scanned=${result.scanned} '
          'dispatched=${result.dispatched} deferred=${result.deferred} '
          'due=${result.dueCount} pending=${result.pendingCount}',
        );
      }
      return result.toBatchResult();
    } catch (error) {
      _log('message recovery failed: $error');
      return const InboxRecoveryBatchResult();
    }
  }

  Future<void> _handleMessageIngress(EventEnvelope<dynamic> event) async {
    final identity = _realtimeIdentity;
    if (identity == null ||
        !event.belongsToDomain(
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
          domainGeneration: _messageDomainGeneration,
        )) {
      return;
    }
    if (event.eventNamespace ==
        TencentAdvancedMessageAdapter.sdkRealtimeNamespace) {
      await _handleSdkRealtimeMessage(event, identity);
      return;
    }
    if (!await _hasCurrentMessageCoreLease(identity)) {
      return;
    }
    final lease = _messageCoreLease;
    if (lease == null) return;
    final claimed = await _messageIngress.claimForWriter(
      event: event,
      lease: lease,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      allowStaleProcessing: true,
      processingTimeoutMs: _messageRecoveryInterval.inMilliseconds,
    );
    if (claimed == null || claimed.status == ImInboxStatus.completed) {
      return;
    }
    try {
      await const RuntimeIngressProcessor().run(
        status: claimed.status,
        // Heartbeats renew the lease object without replacing its ownership.
        // Fence by owner/token so healthy renewals do not reject a valid turn.
        isCurrent: () =>
            _isCurrentRealtimeIdentity(identity) &&
            event.domainGeneration == _messageDomainGeneration &&
            _messageCoreLease?.leaseOwnerId == lease.leaseOwnerId &&
            _messageCoreLease?.fencingToken == lease.fencingToken,
        applyMetadata: () =>
            _applyMessageIngressMetadata(event, identity: identity),
        flushMetadata: () => _ingressPersistFlush.request(),
        advance: (from, to) => _advanceMessageInboxStatus(
          event: event,
          identity: identity,
          expectedStatus: from,
          nextStatus: to,
        ),
        adoptOutgoing: () => _adoptProviderOutgoingMessage(
          event, identity: identity, lease: lease),
        publish: () =>
            _publishMessageIngressProjection(event, identity: identity),
        completeOutgoing: () async {
          final outgoing = _providerOutgoingIdentity(event, identity: identity);
          if (outgoing == null) return;
          final completed = await Im05Persistence(store: _messageIngressStore)
              .completeOutboxProjection(
            ownerUserId: identity.ownerUserId,
            operationId: outgoing.operationId,
            leaseOwnerId: lease.leaseOwnerId,
            fencingToken: lease.fencingToken,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (!completed) {
            throw StateError(
              'provider Outbox projection completion was rejected',
            );
          }
        },
      );
    } catch (error, stack) {
      // Leave PROCESSING durable. Recovery must replay the event rather than
      // treating a failed compatibility projection as completed.
      debugPrint(
        'CHAT_INGRESS_HANDLER_FAILURE kind=${event.kind.name} '
        'eventId=${event.eventId} errorType=${error.runtimeType} '
        'error=$error\n$stack',
      );
      if (claimed.status != ImInboxStatus.completed) {
        try {
          await _messageIngress.scheduleRetry(
            record: claimed,
            errorClass: InboxRecoveryPolicy.classify(error),
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {}
        InboxRecoveryCoordinator.instance.request(
          trigger: InboxRecoveryTrigger.retryDue,
          ownerUserId: identity.ownerUserId,
          accountGeneration: identity.generation,
          nextRetryAtMs: InboxRecoveryPolicy.nextRetryAtMs(
            nowMs: DateTime.now().millisecondsSinceEpoch,
            retryCount: claimed.retryCount,
            jitterMs: 0,
          ),
        );
      }
    }
  }

  Future<void> _handleSdkRealtimeMessage(
      EventEnvelope<dynamic> event, SessionIdentity identity) async {
    final message = event.payload;
    final conversationID = event.scope?.canonicalConversationId;
    if (message is! V2TimMessage || conversationID == null) return;
    final model = serviceLocator<TUIChatGlobalModel>();
    if (!_isCurrentRealtimeIdentity(identity) ||
        model.messageDeltaClearEpochFor(conversationID) != event.clearEpoch)
      return;
    // The adapter sequence is process-local mailbox order, not an Inbox fence.
    // SDK history supplies recovery; reading-away delivery keeps its existing
    // stable message identity and durable UI watermark without a formal sequence.
    await model.applyAppRealtimeMessage(
      message,
      ingressEventID: event.eventId,
      projectMessageList:
          ActiveChatRegistry.instance.matchesOpenConversation(conversationID),
    );
    if (!_isCurrentRealtimeIdentity(identity) ||
        model.messageDeltaClearEpochFor(conversationID) != event.clearEpoch)
      return;
    // Notification work must not hold the next message behind an app database
    // or platform call. SDK conversation callbacks own preview and unread state.
    unawaited(_publishSdkRealtimeSideEffects(message, identity));
  }

  Future<void> _publishSdkRealtimeSideEffects(
      V2TimMessage message, SessionIdentity identity) async {
    if (!_isCurrentRealtimeIdentity(identity)) return;
    try {
      await NotificationSettingsService.instance
          .handleAppRealtimeMessage(message);
    } catch (error) {
      _log('SDK realtime notification failed: $error');
    }
    if (!_isCurrentRealtimeIdentity(identity)) return;
    try {
      await LiveKitCallSignaling.instance.handleAppMessage(message);
    } catch (error) {
      _log('SDK realtime signaling projection failed: $error');
    }
    if (_isCurrentRealtimeIdentity(identity) &&
        (message.groupID?.trim() ?? '').isEmpty) {
      ChatImageMessagePrefetch.prefetchThumbnailForMessage(message);
    }
  }

  OutgoingIdentityContract? _providerOutgoingIdentity(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
  }) {
    if (event.kind != ImEventKind.realtimeMessage &&
        event.kind != ImEventKind.messageMutation) {
      return null;
    }
    final payload = event.payload;
    final scope = event.scope;
    if (payload is! V2TimMessage ||
        payload.isSelf != true ||
        scope == null ||
        scope.ownerUserId != identity.ownerUserId) {
      return null;
    }
    return OutgoingIdentityContract.fromCloudCustomData(
      payload.cloudCustomData,
      scope: scope,
    );
  }

  Future<bool> _adoptProviderOutgoingMessage(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
    required ImWriterLease lease,
  }) async {
    final outgoing = _providerOutgoingIdentity(event, identity: identity);
    if (outgoing == null) return false;
    final payload = event.payload as V2TimMessage;
    return Im05Persistence(
      store: _messageIngressStore,
    ).adoptOutboxProviderSucceeded(
      ownerUserId: identity.ownerUserId,
      operationId: outgoing.operationId,
      clientCorrelationId: outgoing.clientCorrelationId,
      conversationId: outgoing.scope.storageKey,
      payloadHash: outgoing.payloadFingerprint,
      leaseOwnerId: lease.leaseOwnerId,
      fencingToken: lease.fencingToken,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      sdkLocalId: payload.id,
      serverMsgId: payload.msgID,
    );
  }

  Future<void> _applyMessageIngressMetadata(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
  }) async {
    final payload = event.payload;
    if (event.kind == ImEventKind.realtimeMessage) {
      if (payload is! V2TimMessage) {
        throw StateError('formal realtime message payload is unavailable');
      }
      await _patchInboundConversationPreview(payload, identity: identity);
      await _onRecvNewMessageForMembershipBridge(payload, identity: identity);
      return;
    }
    if (event.kind == ImEventKind.messageMutation) {
      if (payload is! V2TimMessage) {
        throw StateError('formal message mutation payload is unavailable');
      }
      await _patchInboundConversationPreview(payload, identity: identity);
      return;
    }
    if (payload is ImMessageRevokedEvent) {
      await markConversationLastMessageRevoked(
        msgID: payload.msgID,
        isAdmin: payload.isAdmin,
        revoker: payload.revoker,
        identity: identity,
      );
      return;
    }
    // The SDK adapter uses notification when a message/receipt has no
    // resolvable conversation scope. Route by payload so these durable events
    // do not become poison Inbox rows that recovery retries forever.
    if (payload is V2TimMessage) {
      await _patchInboundConversationPreview(payload, identity: identity);
      if (event.eventId.startsWith('received:')) {
        await _onRecvNewMessageForMembershipBridge(payload, identity: identity);
      }
      return;
    }
    if (payload is V2TimMessageReceipt ||
        payload is ImReadReceiptBatch ||
        payload is ImMessageProgressEvent ||
        payload is ImMessageDownloadProgressEvent ||
        payload is ImRecoveredEphemeralUiEvent) {
      return;
    }
    if (event.kind == ImEventKind.notification) {
      // Extensions/reactions currently have no app projection consumer. They
      // are intentionally acknowledged instead of left in PROCESSING.
      return;
    }
    throw StateError(
      'unsupported IM metadata payload: ${event.kind.name}/${event.eventId}',
    );
  }

  Future<void> _publishMessageIngressProjection(
    EventEnvelope<dynamic> event, {
    required SessionIdentity identity,
  }) async {
    if (!_isCurrentRealtimeIdentity(identity) ||
        !event.belongsToDomain(
            ownerUserId: identity.ownerUserId,
            accountGeneration: identity.generation,
            domainGeneration: _messageDomainGeneration)) return;
    final payload = event.payload;
    if (event.kind == ImEventKind.realtimeMessage) {
      if (payload is! V2TimMessage) {
        throw StateError('formal realtime message payload is unavailable');
      }
      await serviceLocator<TUIChatGlobalModel>().applyAppRealtimeMessage(
        payload,
        ingressEventID: event.eventId,
        ingressSequence: event.accountIngressSequence,
        projectMessageList: ActiveChatRegistry.instance
            .matchesOpenConversation(event.scope?.canonicalConversationId),
      );
      await NotificationSettingsService.instance.handleAppRealtimeMessage(
        payload,
      );
      await LiveKitCallSignaling.instance.handleAppMessage(payload);
      if ((payload.groupID?.trim() ?? '').isEmpty) {
        ChatImageMessagePrefetch.prefetchThumbnailForMessage(payload);
      }
      return;
    }
    if (event.kind == ImEventKind.messageMutation) {
      if (payload is! V2TimMessage) {
        throw StateError('formal message mutation payload is unavailable');
      }
      await serviceLocator<TUIChatGlobalModel>().applyAppMessageModified(
        payload,
        conversationID: event.scope?.canonicalConversationId,
        ingressEventID: event.eventId,
        ingressSequence: event.accountIngressSequence,
      );
      return;
    }
    if (payload is ImMessageRevokedEvent) {
      // Revoke-only fix: when the SDK listener adapter failed to attach a
      // scope (e.g. early lifecycle, empty memory window, vendor patch
      // rolled back), fall back to a best-effort in-memory reverse lookup so
      // the chat model still receives a usable conversationID.
      final resolvedConvId = event.scope?.canonicalConversationId ??
          _reverseLookupRevokeConversationId(payload.msgID);
      await serviceLocator<TUIChatGlobalModel>().applyAppMessageRevoked(
        payload.msgID,
        resolvedConvId,
      );
      return;
    }
    if (payload is V2TimMessage && event.kind == ImEventKind.notification) {
      if (event.eventId.startsWith('modified:')) {
        await serviceLocator<TUIChatGlobalModel>().applyAppMessageModified(
          payload,
          conversationID: event.scope?.canonicalConversationId,
        );
      } else {
        await serviceLocator<TUIChatGlobalModel>().applyAppRealtimeMessage(
          payload,
          ingressEventID: event.eventId,
          ingressSequence: event.accountIngressSequence,
          projectMessageList: ActiveChatRegistry.instance
              .matchesOpenConversation(event.scope?.canonicalConversationId),
        );
        await NotificationSettingsService.instance.handleAppRealtimeMessage(
          payload,
        );
        await LiveKitCallSignaling.instance.handleAppMessage(payload);
      }
      return;
    }
    if (payload is ImReadReceiptBatch) {
      payload.applyTo(serviceLocator<TUIChatGlobalModel>());
      return;
    }
    if (payload is V2TimMessageReceipt) {
      final model = serviceLocator<TUIChatGlobalModel>();
      final canonical = event.eventId.startsWith('read-receipt:');
      if (event.eventId.startsWith('c2c-read:') ||
          (canonical && (payload.groupID?.trim() ?? '').isEmpty)) {
        model.applyAppC2CReadReceipts(<V2TimMessageReceipt>[payload]);
      }
      if (!event.eventId.startsWith('c2c-read:')) {
        model.applyAppMessageReadReceipts(<V2TimMessageReceipt>[payload]);
      }
      return;
    }
    if (payload is ImRecoveredEphemeralUiEvent) return;
    if ((payload is ImMessageProgressEvent ||
            payload is ImMessageDownloadProgressEvent) &&
        _messageAdapter?.isCurrentUiProgress(payload as Object) == false)
      return;
    if (payload is ImMessageProgressEvent) {
      serviceLocator<TUIChatGlobalModel>().applyAppSendMessageProgress(
        payload.message,
        payload.progress,
      );
      return;
    }
    if (payload is ImMessageDownloadProgressEvent) {
      final adapter = _messageAdapter;
      await serviceLocator<TUIChatGlobalModel>()
          .applyAppMessageDownloadProgress(
        payload.progress,
        isCurrent: () =>
            _isCurrentRealtimeIdentity(identity) &&
            event.domainGeneration == _messageDomainGeneration &&
            identical(adapter, _messageAdapter) &&
            adapter?.isCurrentUiProgress(payload) != false,
      );
      return;
    }
    if (event.kind == ImEventKind.notification) {
      // Extension/reaction notifications have no compatibility projection.
      return;
    }
    throw StateError(
      'unsupported IM projection payload: ${event.kind.name}/${event.eventId}',
    );
  }

  /// Best-effort reverse lookup of the conversation key that owns [msgID].
  ///
  /// Used only when a revoke ingress event arrives without an attached scope.
  /// Returns null when no match is found in the in-memory chat model or the
  /// model cannot be reached; in that case the vendor's own fallback inside
  /// [TUIChatGlobalModel.markMessageRevokedNow] still scans every known
  /// message list.
  String? _reverseLookupRevokeConversationId(String msgID) {
    final normalized = msgID.trim();
    if (normalized.isEmpty) return null;
    final TUIChatGlobalModel model;
    try {
      model = serviceLocator<TUIChatGlobalModel>();
    } catch (_) {
      return null;
    }
    final Map<String, List<V2TimMessage>?> snapshot;
    try {
      snapshot = model.messageListMap;
    } catch (_) {
      return null;
    }
    final selected = model.currentSelectedConv.trim();
    if (selected.isNotEmpty && snapshot[selected] != null) {
      for (final message in snapshot[selected]!) {
        if (message.msgID?.trim() == normalized) {
          return selected;
        }
      }
    }
    String? fallback;
    snapshot.forEach((key, messages) {
      if (fallback != null || messages == null || messages.isEmpty) return;
      for (final message in messages) {
        if (message.msgID?.trim() == normalized) {
          fallback = key;
          return;
        }
      }
    });
    return fallback;
  }

  Future<bool> _advanceMessageInboxStatus({
    required EventEnvelope<dynamic> event,
    required SessionIdentity identity,
    required ImInboxStatus expectedStatus,
    required ImInboxStatus nextStatus,
  }) async {
    if (!_isCurrentRealtimeIdentity(identity) ||
        !event.belongsToDomain(
            ownerUserId: identity.ownerUserId,
            accountGeneration: identity.generation,
            domainGeneration: _messageDomainGeneration)) return false;
    final lease = _messageCoreLease;
    if (lease == null) return false;
    return _messageIngress.advanceForWriter(
      event: event,
      expectedStatus: expectedStatus,
      nextStatus: nextStatus,
      lease: lease,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      completeRecoveryCopies: event.payload is ImReadReceiptBatch &&
          nextStatus == ImInboxStatus.completed,
      committedAtMs: nextStatus == ImInboxStatus.metadataCommitted
          ? DateTime.now().millisecondsSinceEpoch
          : null,
    );
  }

  ImIngressLane _laneForMessageEvent(EventEnvelope<dynamic> event) {
    if (event.kind == ImEventKind.messageMutation ||
        event.payload is ImMessageRevokedEvent) {
      return ImIngressLane.urgent;
    }
    if (event.kind == ImEventKind.historyPage) {
      return ImIngressLane.history;
    }
    return ImIngressLane.realtime;
  }

  /// Binds realtime callbacks to the account that has just completed IM login.
  /// Kept as a compatibility entry point; activation itself is idempotent.
  Future<void> activateRealtimeSession() {
    return ensureRealtimeActive(SessionIdentityService.instance.capture());
  }

  /// Ensures one realtime owner for [identity]. Repeated calls for the same
  /// account reuse the active/starting operation and never detach listeners.
  Future<void> ensureRealtimeActive(SessionIdentity identity) {
    if (identity.ownerUserId.isEmpty ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return Future<void>.value();
    }
    if (isRealtimeActiveFor(identity)) {
      _log(
        'event=realtime_start_reused generation=${identity.generation} '
        'state=active',
      );
      return Future<void>.value();
    }
    final pending = _realtimeActivationInFlight;
    if (pending != null && _realtimeActivationIdentity == identity) {
      _log(
        'event=realtime_start_reused generation=${identity.generation} '
        'state=starting',
      );
      return pending;
    }
    _log('event=realtime_start_requested generation=${identity.generation}');
    late final Future<void> task;
    task = _enqueueRealtimeLifecycle(() => _ensureRealtimeActive(identity));
    _realtimeActivationInFlight = task;
    _realtimeActivationIdentity = identity;
    unawaited(task.then<void>(
      (_) {
        if (identical(_realtimeActivationInFlight, task)) {
          _realtimeActivationInFlight = null;
          _realtimeActivationIdentity = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_realtimeActivationInFlight, task)) {
          _realtimeActivationInFlight = null;
          _realtimeActivationIdentity = null;
        }
      },
    ));
    return task;
  }

  bool isRealtimeActiveFor(SessionIdentity identity) {
    return _realtimeIdentity == identity &&
        _messageCoreLease != null &&
        _conversationListenerAttached &&
        _messageListenerAttached &&
        _isCurrentSessionIdentity(identity);
  }

  Future<void> _ensureRealtimeActive(SessionIdentity identity) async {
    if (!_isCurrentSessionIdentity(identity)) return;
    {
      ChatSessionController.instance.ensureTabStoreBridgeAttached();
    }
    final current = _realtimeIdentity;
    if (current != null && current != identity) {
      _log(
        'event=realtime_switch generation=${identity.generation} '
        'previousGeneration=${current.generation}',
      );
      await _detachRealtimeListeners(reason: 'account_switch');
    }
    // Keep the original identity object while the listeners are alive:
    // callbacks use identity-token matching in [_isCurrentRealtimeIdentity].
    final activeIdentity = _realtimeIdentity ?? identity;
    _realtimeIdentity = activeIdentity;
    if (!await _hasCurrentMessageCoreLease(activeIdentity) &&
        !await _acquireMessageCoreLeaseSingleFlight(activeIdentity)) {
      _scheduleMessageCoreAcquireRetry(activeIdentity);
      return;
    }
    await _attachRealtimeSdkListeners(activeIdentity);
  }

  Future<void> _hydrateIncompleteConversationPatches(
    List<V2TimConversation> patches,
    SessionIdentity identity,
  ) =>
      _conversationPatchHydrator.hydrate(
        patches,
        isCurrent: () => _isCurrentRealtimeIdentity(identity),
        apply: (full) {
          ChatSessionController.instance.applyPendingRealtimeProjection(
            [full],
            reason: 'sdk_realtime_hydrated',
            preserveOrder: false,
          );
        },
      );

  /// Null draft text means "no draft" in normal SDK rows and must not cause
  /// a per-callback getConversation request. Hydration is needed only when the
  /// unread authority is absent, or when unread proves a last message exists
  /// but the callback omitted it.
  @visibleForTesting
  static bool conversationPatchNeedsHydration(V2TimConversation patch) =>
      ConversationPatchHydrator.needsHydration(patch);

  Future<void> _attachRealtimeSdkListeners(SessionIdentity identity) async {
    if (!await _hasCurrentMessageCoreLease(identity)) {
      _scheduleMessageCoreAcquireRetry(identity);
      return;
    }
    if (_messageAdapter == null) {
      _createMessageAdapter(identity);
    }
    await _ensureConversationListenerAttached(identity);
    await _ensureRealtimeMessageListenerAttached();
    if (!_isCurrentRealtimeIdentity(identity)) return;
    unawaited(_primeRealtimeConversationTabs(identity));
  }

  Future<void> _primeRealtimeConversationTabs(SessionIdentity identity) async {
    // Visible-tab first page is owned by restoreProjection. Attaching
    // listeners must not Future.wait both C2C and group pages.
    return;
  }

  Future<void> _ensureConversationListenerAttached(
    SessionIdentity identity,
  ) async {
    if (_conversationListenerAttached ||
        !(await _hasCurrentMessageCoreLease(identity))) {
      return;
    }
    final pending = _conversationListenerAttachInFlight;
    if (pending != null) {
      await pending;
      return;
    }
    final conversationListener = _createConversationListener(identity);
    try {
      if (!await _hasCurrentMessageCoreLease(identity)) {
        if (identical(_listener, conversationListener)) _listener = null;
        _scheduleMessageCoreAcquireRetry(identity);
        return;
      }
      final task = TencentImSDKPlugin.v2TIMManager
          .getConversationManager()
          .addConversationListener(listener: conversationListener);
      _conversationListenerAttachInFlight = task;
      try {
        await task;
      } finally {
        if (identical(_conversationListenerAttachInFlight, task)) {
          _conversationListenerAttachInFlight = null;
        }
      }
      if (!_isCurrentRealtimeIdentity(identity)) {
        await _detachRealtimeListeners();
        return;
      }
      _conversationListenerAttached = true;
      _log(
        'event=realtime_listener_attached type=conversation '
        'generation=${identity.generation}',
      );
      _conversationListenerRetryTimer?.cancel();
      _conversationListenerRetryTimer = null;
    } catch (error) {
      if (identical(_listener, conversationListener)) _listener = null;
      _conversationListenerAttached = false;
      _log(
        'conversation listener attach failed '
        'errorType=${error.runtimeType}',
      );
      _scheduleConversationListenerRetry(identity);
    }
  }

  void _scheduleConversationListenerRetry(SessionIdentity identity) {
    if (!_isCurrentRealtimeIdentity(identity) ||
        _conversationListenerRetryTimer?.isActive == true) {
      return;
    }
    _conversationListenerRetryTimer = Timer(_messageCoreAcquireRetryDelay, () {
      _conversationListenerRetryTimer = null;
      unawaited(
        _enqueueRealtimeLifecycle(
          () => _ensureConversationListenerAttached(identity),
        ),
      );
    });
  }

  bool _isCurrentRealtimeIdentity(SessionIdentity? identity) {
    return identity != null &&
        identical(_realtimeIdentity, identity) &&
        _isCurrentSessionIdentity(identity);
  }

  bool _isCurrentSessionIdentity(SessionIdentity? identity) {
    return identity != null &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  Future<bool> _acquireMessageCoreLease(SessionIdentity identity) async {
    if (!_isCurrentSessionIdentity(identity)) return false;
    final lease = await _messageWriterLeaseService.acquire(
      ownerUserId: identity.ownerUserId,
      leaseOwnerId: _messageCoreLeaseOwnerId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      ttlMs: _messageCoreLeaseTtlMs,
      onBlocked: (current, reason) {
        if (reason == 'other_owner_active' && current != null) {
          _messageCoreBlockedIdentity = identity;
          final now = DateTime.now().millisecondsSinceEpoch;
          final retryAt = now + _messageCoreAcquireRetryDelay.inMilliseconds;
          _messageCoreBlockedUntilMs =
              current.expiresAtMs < retryAt ? current.expiresAtMs : retryAt;
        }
        _log('event=message_core_lease_blocked reason=$reason '
            'requester=$_messageCoreLeaseOwnerId holder=${current?.leaseOwnerId} '
            'heldSince=${current?.acquiredAtMs} expiresAt=${current?.expiresAtMs} '
            'generation=${identity.generation}');
        if (!const bool.fromEnvironment('SQLITE_QUERY_DIAGNOSTICS')) return;
        debugPrintSynchronously(
          '[LeaseDiagnostic] reason=$reason requester=$_messageCoreLeaseOwnerId '
          'leaseOwner=${current?.leaseOwnerId} '
          'leaseExpiresAt=${current?.expiresAtMs} '
          'heartbeatAt=${current?.heartbeatAtMs} '
          'heldSince=${current?.acquiredAtMs} '
          'nowMs=${DateTime.now().millisecondsSinceEpoch} '
          'generation=${identity.generation} '
          'localHeartbeatActive=${_messageCoreHeartbeatTimer?.isActive ?? false} '
          'recoveryWorkerPresent=${_messageRecoveryWorker != null} '
          'retryScheduled=${_messageCoreAcquireRetryTimer?.isActive ?? false} '
          'pendingPersistQueueSize=${_pendingPersistEvents.length} '
          'remoteWorkerActive=unknown',
        );
      },
    );
    if (!_isCurrentSessionIdentity(identity)) {
      if (lease != null) await _messageWriterLeaseService.release(lease);
      return false;
    }
    if (lease == null) return false;
    _messageCoreBlockedIdentity = null;
    _messageCoreBlockedUntilMs = 0;
    _realtimeIdentity = identity;
    _messageCoreLease = lease;
    _startMessageCoreHeartbeat(identity);
    return true;
  }

  Future<bool> _hasCurrentMessageCoreLease(SessionIdentity identity) async {
    final lease = _messageCoreLease;
    if (lease == null || !_isCurrentRealtimeIdentity(identity)) return false;
    final isCurrent = await _messageWriterLeaseService.isCurrent(
      lease: lease,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    return isCurrent &&
        identical(_messageCoreLease, lease) &&
        _isCurrentRealtimeIdentity(identity);
  }

  /// Sending is P0 and must not wait behind listener teardown/startup work.
  Future<ImMessageCoreLeaseContext?> messageCoreLeaseForOutgoingSend() {
    return _messageCoreLeaseForOutgoingSend();
  }

  Future<ImMessageCoreLeaseContext?> _messageCoreLeaseForOutgoingSend() async {
    if (_realtimeTeardownInFlight) {
      _log('event=outgoing_send_lease_blocked reason=realtime_teardown');
      return null;
    }
    final existing = _realtimeIdentity;
    final identity = existing != null && _isCurrentSessionIdentity(existing)
        ? existing
        : SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty || !_isCurrentSessionIdentity(identity)) {
      _log('event=outgoing_send_lease_blocked reason=stale_session');
      return null;
    }
    if (_messageCoreLease == null || !_isCurrentRealtimeIdentity(identity)) {
      if (!await _acquireMessageCoreLeaseSingleFlight(identity)) {
        _scheduleMessageCoreAcquireRetry(identity);
        return null;
      }
    }
    if (!await _hasCurrentMessageCoreLease(identity)) {
      _log(
          'event=outgoing_send_lease_stale action=reacquire generation=${identity.generation}');
      // A queued SQLite transaction can make a still-valid in-memory lease
      // look stale. Re-elect the same owner before tearing down listeners;
      // this keeps P0 send/receive alive without bypassing fencing.
      if (!await _acquireMessageCoreLeaseSingleFlight(identity) ||
          !await _hasCurrentMessageCoreLease(identity)) {
        _log(
            'event=outgoing_send_lease_blocked reason=lease_not_current generation=${identity.generation}');
        return null;
      }
    }
    if (_realtimeTeardownInFlight) {
      _log('event=outgoing_send_lease_blocked reason=teardown_after_acquire');
      return null;
    }
    final lease = _messageCoreLease;
    if (lease == null) return null;
    return ImMessageCoreLeaseContext(
      store: _messageIngressStore,
      lease: lease,
      ownerUserId: identity.ownerUserId,
      accountGeneration: identity.generation,
      domainGeneration: _messageDomainGeneration,
    );
  }

  Future<bool> _acquireMessageCoreLeaseSingleFlight(
    SessionIdentity identity,
  ) {
    final pending = _messageCoreAcquireInFlight;
    if (pending != null && _messageCoreAcquireIdentity == identity) {
      return pending;
    }
    if (_messageCoreBlockedIdentity == identity &&
        DateTime.now().millisecondsSinceEpoch < _messageCoreBlockedUntilMs) {
      return Future<bool>.value(false);
    }
    late final Future<bool> task;
    task = _acquireMessageCoreLease(identity);
    _messageCoreAcquireInFlight = task;
    _messageCoreAcquireIdentity = identity;
    unawaited(task.then<void>(
      (_) {
        if (identical(_messageCoreAcquireInFlight, task)) {
          _messageCoreAcquireInFlight = null;
          _messageCoreAcquireIdentity = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_messageCoreAcquireInFlight, task)) {
          _messageCoreAcquireInFlight = null;
          _messageCoreAcquireIdentity = null;
        }
      },
    ));
    return task;
  }

  void _startMessageCoreHeartbeat(SessionIdentity identity) {
    _messageCoreHeartbeatTimer?.cancel();
    _messageCoreHeartbeatTimer = Timer.periodic(
      _messageCoreHeartbeatInterval,
      (_) => unawaited(_renewMessageCoreLease(identity)),
    );
  }

  Future<void> _renewMessageCoreLease(SessionIdentity identity) async {
    if (_messageCoreHeartbeatInFlight != null) return;
    late final Future<void> task;
    task = () async {
      final cpu = Stopwatch()..start();
      final lease = _messageCoreLease;
      if (lease == null || !_isCurrentRealtimeIdentity(identity)) {
        HeartbeatTickRecorder.instance.record(
          cpuUs: cpu.elapsedMicroseconds,
          dbQueryCount: 0,
          uiNotifyCount: 0,
          triggeredTaskCount: 0,
        );
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (!HeartbeatTickPolicy.shouldRenewLease(
        expiresAtMs: lease.expiresAtMs,
        nowMs: nowMs,
      )) {
        HeartbeatTickRecorder.instance.record(
          cpuUs: cpu.elapsedMicroseconds,
          dbQueryCount: 0,
          uiNotifyCount: 0,
          triggeredTaskCount: 0,
        );
        return;
      }
      final renewed = await _messageWriterLeaseService.renew(
        lease: lease,
        nowMs: nowMs,
        ttlMs: _messageCoreLeaseTtlMs,
      );
      if (!_isCurrentRealtimeIdentity(identity) ||
          !identical(_messageCoreLease, lease)) {
        if (renewed != null) await _messageWriterLeaseService.release(renewed);
        HeartbeatTickRecorder.instance.record(
          cpuUs: cpu.elapsedMicroseconds,
          dbQueryCount: 1,
          uiNotifyCount: 0,
          triggeredTaskCount: 0,
        );
        return;
      }
      if (renewed == null) {
        // Give the same owner one immediate re-election chance. A transient
        // database queue must not detach both SDK listeners; teardown remains
        // the fallback when fencing really changed or the lease expired.
        if (await _acquireMessageCoreLeaseSingleFlight(identity)) {
          HeartbeatTickRecorder.instance.record(
            cpuUs: cpu.elapsedMicroseconds,
            dbQueryCount: 1,
            uiNotifyCount: 0,
            triggeredTaskCount: 1,
          );
          return;
        }
        // Queue the teardown, but let the heartbeat finish first. The
        // lifecycle queue may itself be waiting for this in-flight heartbeat
        // during logout or account switching.
        unawaited(_onMessageCoreLeaseLost(identity, lease));
        HeartbeatTickRecorder.instance.record(
          cpuUs: cpu.elapsedMicroseconds,
          dbQueryCount: 1,
          uiNotifyCount: 0,
          triggeredTaskCount: 1,
        );
        return;
      }
      _messageCoreLease = renewed;
      HeartbeatTickRecorder.instance.record(
        cpuUs: cpu.elapsedMicroseconds,
        dbQueryCount: 1,
        uiNotifyCount: 0,
        triggeredTaskCount: 0,
      );
    }();
    _messageCoreHeartbeatInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_messageCoreHeartbeatInFlight, task)) {
        _messageCoreHeartbeatInFlight = null;
      }
    }
  }

  Future<void> _onMessageCoreLeaseLost(
    SessionIdentity identity,
    ImWriterLease lease,
  ) {
    return _enqueueRealtimeLifecycle(
      () => _handleMessageCoreLeaseLost(identity, lease),
    );
  }

  Future<void> _handleMessageCoreLeaseLost(
    SessionIdentity identity,
    ImWriterLease lease,
  ) async {
    if (!identical(_messageCoreLease, lease)) return;
    _messageCoreLease = null;
    _realtimeIdentity = null;
    _messageCoreHeartbeatTimer?.cancel();
    _messageCoreHeartbeatTimer = null;
    await _messageMailbox.drain();
    await _detachRealtimeSdkListeners();
    await _messageMailbox.drain();
    if (_isCurrentSessionIdentity(identity)) {
      _scheduleMessageCoreAcquireRetry(identity);
    }
  }

  void _scheduleMessageCoreAcquireRetry(SessionIdentity identity) {
    if (!_isCurrentSessionIdentity(identity) ||
        _messageCoreAcquireRetryTimer?.isActive == true) {
      return;
    }
    _messageCoreAcquireRetryTimer = Timer(_messageCoreAcquireRetryDelay, () {
      _messageCoreAcquireRetryTimer = null;
      unawaited(_retryMessageCoreAcquire(identity));
    });
  }

  Future<void> _retryMessageCoreAcquire(SessionIdentity identity) {
    return _enqueueRealtimeLifecycle(
      () => _handleMessageCoreAcquireRetry(identity),
    );
  }

  Future<void> _handleMessageCoreAcquireRetry(SessionIdentity identity) async {
    if (!_isCurrentSessionIdentity(identity) || _messageCoreLease != null) {
      return;
    }
    if (!await _acquireMessageCoreLeaseSingleFlight(identity)) {
      _scheduleMessageCoreAcquireRetry(identity);
      return;
    }
    await _attachRealtimeSdkListeners(identity);
  }

  Future<void> detachRealtimeListeners() {
    return _enqueueRealtimeLifecycle(
      () => _detachRealtimeListeners(reason: 'explicit'),
    );
  }

  Future<T> _enqueueRealtimeLifecycle<T>(Future<T> Function() action) {
    final previous = _realtimeLifecycleTail;
    late final Future<T> task;
    task = () async {
      try {
        await previous;
      } catch (_) {
        // A failed teardown must not prevent the next login from retrying.
      }
      return action();
    }();
    _realtimeLifecycleTail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return task;
  }

  Future<void> _detachRealtimeListeners({String reason = 'lifecycle'}) async {
    final previousIdentity = _realtimeIdentity;
    _log(
      'event=realtime_listener_detached reason=$reason '
      'generation=${previousIdentity?.generation}',
    );
    _realtimeTeardownInFlight = true;
    try {
      _realtimeIdentity = null;
      _conversationPatchHydrator.reset();
      _messageCoreBlockedIdentity = null;
      _messageCoreBlockedUntilMs = 0;
      _messageCoreAcquireRetryTimer?.cancel();
      _messageCoreAcquireRetryTimer = null;
      _messageCoreHeartbeatTimer?.cancel();
      _messageCoreHeartbeatTimer = null;
      final heartbeat = _messageCoreHeartbeatInFlight;
      if (heartbeat != null) {
        try {
          await heartbeat;
        } catch (_) {}
      }
      await _messageMailbox.drain();
      await _detachRealtimeSdkListeners();
      await _messageMailbox.drain();
      final lease = _messageCoreLease;
      _messageCoreLease = null;
      if (lease != null) {
        try {
          await _messageWriterLeaseService.release(lease);
        } catch (_) {}
      }
    } finally {
      _realtimeTeardownInFlight = false;
    }
  }

  Future<void> _detachRealtimeSdkListeners() async {
    _messageListenerRetryTimer?.cancel();
    _messageListenerRetryTimer = null;
    _conversationListenerRetryTimer?.cancel();
    _conversationListenerRetryTimer = null;
    InboxRecoveryCoordinator.instance.unbind();
    _messageRecoveryWorker = null;
    final conversationListener = _listener;
    _listener = null;
    _conversationListenerAttached = false;
    final conversationAttach = _conversationListenerAttachInFlight;
    if (conversationAttach != null) {
      try {
        await conversationAttach;
      } catch (_) {}
    }
    if (conversationListener != null) {
      try {
        await TencentImSDKPlugin.v2TIMManager
            .getConversationManager()
            .removeConversationListener(listener: conversationListener);
      } catch (_) {}
    }
    final pending = _messageListenerAttachInFlight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final messageAdapter = _messageAdapter;
    _messageAdapter = null;
    if (messageAdapter != null) {
      try {
        await messageAdapter.unregister();
      } catch (_) {}
    }
    _messageListenerAttached = false;
  }

  /// The service is installed before login, while the SDK may still be
  /// initializing. Recheck the advanced listener after login/reconnect so the
  /// inbound preview fallback is not lost because its first registration was
  /// attempted too early.
  Future<void> ensureRealtimeMessageListenerAttached({bool force = false}) {
    return _enqueueRealtimeLifecycle(
      () => _ensureRealtimeMessageListenerAttached(force: force),
    );
  }

  Future<void> _ensureRealtimeMessageListenerAttached({
    bool force = false,
  }) async {
    final adapter = _messageAdapter;
    final identity = _realtimeIdentity;
    if (adapter == null ||
        identity == null ||
        !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    final pending = _messageListenerAttachInFlight;
    if (pending != null) {
      await pending;
    }
    if (force && _messageListenerAttached) {
      try {
        await adapter.unregister();
      } catch (_) {}
      _messageListenerAttached = false;
    }
    if (_messageListenerAttached) {
      if (InboxRecoveryCoordinator.instance.state == InboxRecoveryState.idle) {
        _startMessageRecovery(identity);
      }
      return;
    }
    late final Future<void> task;
    task = () async {
      if (!await _hasCurrentMessageCoreLease(identity)) {
        return;
      }
      try {
        await adapter.register();
        _messageListenerAttached = identical(_messageAdapter, adapter) &&
            adapter.isRegistered &&
            await _hasCurrentMessageCoreLease(identity) &&
            _isCurrentRealtimeIdentity(identity);
        if (_messageListenerAttached) {
          _log(
            'event=realtime_listener_attached type=message '
            'generation=${identity.generation}',
          );
        }
      } catch (e) {
        _log('message listener attach failed: $e');
        _scheduleMessageListenerRetry(identity);
      }
    }();
    _messageListenerAttachInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_messageListenerAttachInFlight, task)) {
        _messageListenerAttachInFlight = null;
      }
    }
    if (_messageListenerAttached) {
      _messageListenerRetryTimer?.cancel();
      _messageListenerRetryTimer = null;
      _startMessageRecovery(identity);
    }
  }

  void _scheduleMessageListenerRetry(SessionIdentity identity) {
    if (!_isCurrentRealtimeIdentity(identity) ||
        _messageListenerRetryTimer?.isActive == true) {
      return;
    }
    _messageListenerRetryTimer = Timer(_messageCoreAcquireRetryDelay, () {
      _messageListenerRetryTimer = null;
      unawaited(ensureRealtimeMessageListenerAttached());
    });
  }

  /// 将本地会话预览中的最后一条消息标记为已撤回。
  Future<void> markConversationLastMessageRevoked({
    required String msgID,
    String? conversationID,
    bool isAdmin = false,
    V2TimUserFullInfo? revoker,
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    final targetMsgID = msgID.trim();
    if (targetMsgID.isEmpty) {
      return;
    }
    final normalizedConversationID = conversationID?.trim() ?? '';
    V2TimConversation? conversation;
    if (normalizedConversationID.isNotEmpty) {
      conversation = await ConversationLocalStore.instance.conversationById(
        normalizedConversationID,
      );
      if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
        return;
      }
    }
    conversation ??= ChatSessionController.instance
        .findConversationByLastMessageId(targetMsgID);
    conversation ??= await ConversationLocalStore.instance.findByLastMsgId(
      targetMsgID,
    );
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }

    final source = conversation?.lastMessage;
    if (conversation == null ||
        source == null ||
        !lastMessageMatchesRevokeTarget(source, targetMsgID)) {
      return;
    }

    // 必须换对象：列表行 StatefulWidget 对同一 lastMessage 引用不重算摘要。
    final lastMessage = V2TimMessage.fromJson(source.toJson());
    applyRemoteRevokedStateToMessage(
      lastMessage,
      isAdmin: isAdmin,
      revoker: revoker,
    );
    conversation.lastMessage = lastMessage;

    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: identity?.ownerUserId ?? _ownerUserId(),
      conversations: <V2TimConversation>[conversation],
      source: ConversationMutationSource.sdkRealtime,
      onCommittedBatch: (result) => committedBatch = result,
    );
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    await _notifyUiAfterLocalWrite(
      upserted: merged,
      committedBatch: committedBatch,
    );
  }

  String _ownerUserId() => ChatIdFormat.rawUserUid(
        debugOwnerUserId ?? ContactSocialCacheStore.safeLoginUserId(),
      );

  Future<void> _restoreDurableMutationState({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final durable =
        await ConversationLocalStore.instance.coordinatorDurableState(
      ownerUserId: ownerUserId,
      conversationId: conversationId,
    );
    ConversationMutationShadowBridge.instance.restoreDurableConversationState(
      ownerUserId: ownerUserId,
      conversationId: conversationId,
      generation: durable.generation,
      tombstoned: durable.tombstoned,
    );
  }

  void _notifyChatRoamingSyncFinished() {
    try {
      serviceLocator<TUIChatGlobalModel>().notifyRoamingSyncFinished();
    } catch (_) {}
  }

  void _scheduleSyncServerFinish(SessionIdentity identity) {
    _syncServerFinishTimer?.cancel();
    _syncServerFinishTimer = Timer(_syncServerFinishDelay, () {
      _syncServerFinishTimer = null;
      if (!_isCurrentRealtimeIdentity(identity)) {
        return;
      }
      unawaited(_handleSyncServerFinish(identity));
    });
  }

  Future<void> _handleSyncServerFinish(SessionIdentity identity) async {
    if (!_isCurrentRealtimeIdentity(identity)) return;
    final serverCycle = _sdkServerSyncPending;
    // SDK page queries may emit finish again. Only an actual sync-start cycle
    // (or the first unsolicited finish) can request a fresh first page.
    // The start callback can predate listener registration on first login.
    // Preserve that first finish even during a page request, then suppress its
    // query feedback. An observed later start authorizes the next refresh.
    if (!serverCycle && _lastSyncServerFinishAt != null) return;
    _sdkServerSyncPending = false;
    ImSdkRelationshipSyncAnchor.serverSyncPending = false;
    ImSdkRelationshipSyncAnchor.hasHandledFinish = true;
    _lastSyncServerFinishAt = DateTime.now();
    NotificationSettingsService.instance.markOfflineMessageSyncFinished();
    _notifyChatRoamingSyncFinished();
    final result = await bootstrapTypedFirstScreen(
        reason: 'sync_server_finish', reset: true);
    if (!_isCurrentRealtimeIdentity(identity)) return;
    if (result.isSuccess) {
      _completeServerSyncAwaitingUi();
      AuthBootstrapService.instance.markConversationListBootstrapReady();
    }
    unawaited(GroupMembershipSyncService.instance
        .pruneStaleGroupConversations(reason: 'sync_server_finish'));
    unawaited(ImRecoveryService.instance
        .refreshForegroundChatIfNeeded(reason: 'sync_server_finish'));
    // 会话同步完成后，再校准一次关系名单。不是好友/群已同步完成。
    unawaited(() async {
      await waitUntilResumeQuietEnds();
      await ImSdkRelationshipReconcileService.instance
          .requestRelationshipReconcile(reason: 'conversation_sync_finished');
    }());
  }

  Future<void> ensureInitialSync({String reason = 'initial'}) async {
    await bootstrapTypedFirstScreen(reason: reason, reset: false);
  }

  Future<void> ensureVisibleConversations({
    required bool Function() hasVisibleConversations,
    int? visibleConvType,
    String reason = 'scope_empty',
  }) async {
    if (_scopeHydrationDone && hasVisibleConversations()) {
      return;
    }
    final inFlight = _scopeHydrationTask;
    if (inFlight != null) {
      await inFlight;
      if (hasVisibleConversations()) {
        return;
      }
    }
    late final Future<void> task;
    task = _ensureVisibleConversationsImpl(
      hasVisibleConversations: hasVisibleConversations,
      visibleConvType: visibleConvType,
      reason: reason,
    ).whenComplete(() {
      if (identical(_scopeHydrationTask, task)) {
        _scopeHydrationTask = null;
      }
    });
    _scopeHydrationTask = task;
    await task;
  }

  Future<void> _ensureVisibleConversationsImpl({
    required bool Function() hasVisibleConversations,
    int? visibleConvType,
    required String reason,
  }) async {
    if (_ownerUserId().isEmpty) return;
    final owner = _ownerUserId();
    final generation = _syncGeneration;
    await ConversationTabStore.instance
        .ensurePrimed(convType: visibleConvType, coldStart: true);
    if (!_isCurrentSync(owner, generation)) return;
    await restoreSdkProjection(immediate: true);
    // A successful empty SDK page is a valid loaded result; filtered folders
    // fetch their own explicit IDs rather than scanning all conversation pages.
    _scopeHydrationDone = hasVisibleConversations();
  }

  /// [forceFull]=true：整窗快照 reload（冷启/空窗 hydration 等白名单）。
  /// 默认 false：soft 保留当前滑动窗，只 patch 刚离开的会话。
  Future<void> restoreSdkProjection({
    bool immediate = false,
    bool forceFull = false,
  }) async {
    if (forceFull) {
      _pendingCoalesceForceFull = true;
    }
    if (immediate) {
      _reloadUiCoalesceTimer?.cancel();
      _reloadUiCoalesceTimer = null;
      final full = _pendingCoalesceForceFull;
      _pendingCoalesceForceFull = false;
      await _restoreSdkProjectionImpl(forceFull: full);
      return;
    }
    if (isInPostPopCoalesceWindow) {
      _scheduleCoalescedReloadUi(postPop: true);
      return;
    }
    _scheduleCoalescedReloadUi(postPop: false);
  }

  Future<void> _notifyUiAfterLocalWrite({
    List<V2TimConversation> upserted = const [],
    List<String> deletedIds = const [],
    List<String> exactDeletedIds = const [],
    V2TimConversation? updated,
    ConversationSdkCommittedBatch? committedBatch,
    bool fullReload = false,
    bool immediate = false,
  }) async {
    if (fullReload) {
      {
        // Phase2：整窗刷新走 TabStore，不读自建库。
        await ChatSessionController.instance.restoreProjection(
          reason: ConversationStoreProjectionReason.sdkProjectionRestore,
        );
        return;
      }
    }
    // Apply data once to TabStore. The controller alone owns scroll/route
    // notification deferral; the retired SQLite queue must not swallow patches.
    if (updated != null) {
      final updatedId = updated.conversationID.trim();
      await ChatSessionController.instance.applySdkProjectionPatch(
        reason: ConversationStoreProjectionReason.sdkProjectionRestore,
        upserted: [updated],
        forceAdmitIds: updatedId.isEmpty
            ? const <String>{}
            : <String>{updatedId},
      );
      return;
    }
    final mergedDeleted = <String>{
      ...deletedIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
      ...exactDeletedIds.map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.toList(growable: false);
    if (upserted.isNotEmpty || mergedDeleted.isNotEmpty) {
      if (committedBatch != null) {
        await ChatSessionController.instance.applyCommittedProjection(
          ConversationUiSnapshotBatch<V2TimConversation>(
            upsertedSnapshots: committedBatch.upserted.isNotEmpty
                ? committedBatch.upserted
                : upserted,
            deletedCanonicalIds: mergedDeleted,
            structureChanged:
                committedBatch.structureChanged || mergedDeleted.isNotEmpty,
            changedFieldMasks: committedBatch.changedFieldMasks,
            commitGeneration: 0,
            unreadDeltas: committedBatch.unreadDeltas,
            unreadProjectionComplete: committedBatch.unreadProjectionComplete,
          ),
          forceAdmitIds: upserted
              .map((conversation) => conversation.conversationID.trim())
              .where((id) => id.isNotEmpty)
              .toSet(),
        );
        return;
      }
      await ChatSessionController.instance.applySdkProjectionPatch(
        reason: ConversationStoreProjectionReason.sdkProjectionRestore,
        upserted: upserted,
        deletedIds: mergedDeleted,
        // A just-persisted outbound preview must be visible even when the
        // virtual list window is empty or has not hydrated this conversation.
        // Otherwise the database contains the new preview while the UI
        // projection silently drops it.
        forceAdmitIds: upserted
            .map((conversation) => conversation.conversationID.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
      );
    }
  }

  void _scheduleCoalescedReloadUi({bool postPop = false}) {
    final now = DateTime.now();
    final inPostPop = postPop || isInPostPopCoalesceWindow;
    late Duration delay;
    if (inPostPop) {
      final until = _postPopCoalesceUntil ?? now.add(_postPopCoalesceWindow);
      final windowStart = _postPopCoalesceWindowStart ?? now;
      final minFlushAt = windowStart.add(_postPopMinFlushDelay);
      var target = now.add(_postPopTrailingDebounce);
      if (target.isBefore(minFlushAt)) {
        target = minFlushAt;
      }
      if (target.isAfter(until)) {
        target = until;
      }
      delay = target.difference(now);
      if (delay.isNegative) {
        delay = Duration.zero;
      }
      _reloadUiCoalesceTimer?.cancel();
    } else {
      delay = _globalReloadDebounce;
      _reloadUiCoalesceTimer?.cancel();
    }

    _reloadUiCoalesceTimer = Timer(delay, _onCoalescedReloadTimerFired);
  }

  bool _reloadUiDeferredWhileScrolling = false;

  /// 滚动/quiet 期间挂起的 UI apply（停滑或 quiet 结束 flush）。
  bool _uiApplyPendingAfterQuietOrScroll = false;
  final Map<String, V2TimConversation> _pendingUiApplyById =
      <String, V2TimConversation>{};

  /// legacy quiet/scroll 挂起帽；sdkPrimary 下 [_notePendingUiApply] 直接 no-op。
  Timer? _resumeQuietExitTimer;

  /// 滚动中暂缓的 ViewModel 分页写库。
  final Map<String, V2TimConversation> _deferredViewModelPersistById =
      <String, V2TimConversation>{};

  bool get isInResumeQuietWindow {
    final until = _resumeQuietUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// 等到 resume quiet 结束（或已不在 quiet）；供 PostHome / 群 sync 错峰。
  Future<void> waitUntilResumeQuietEnds() async {
    final until = _resumeQuietUntil;
    if (until == null) {
      return;
    }
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) {
      return;
    }
    ConversationPerfGateLog.log(
      'resume_quiet_wait',
      extras: <String, Object?>{'waitMs': left.inMilliseconds},
    );
    await Future<void>.delayed(left);
  }

  void _notePendingUiApply(
    List<V2TimConversation> conversations, {
    required String via,
    required String cause,
  }) {
    // Phase4：sdkPrimary 列表不走 DB pending 帽；Listener/TabStore 已即时灌 UI。
    {
      ConversationPerfGateLog.log(
        'mirror_skip_ui',
        extras: <String, Object?>{
          'via': 'pending_ui_apply',
          'cause': cause,
          'count': conversations.length,
        },
      );
      return;
    }
  }

  bool _sdkSyncResumeAfterScroll = false;
  Timer? _scrollEndFlushTimer;
  Future<void>? _scrollEndFlushInFlight;
  bool _scrollEndFlushDirty = false;

  /// 列表开始滚动时取消 settle 中的 scroll_end flush，避免滑到一半又灌窗。
  void onFeedScrollStarted() {
    _scrollEndFlushTimer?.cancel();
    _scrollEndFlushTimer = null;
  }

  /// quiet 结束且热窗未扩展：soft 热快照（保类型地板）。
  /// scroll_end / 已扩展：只 patch「已在 UI 窗内」的会话，禁止未读群批量灌窗。
  Future<void> _flushPendingUiApply({required String reason}) async {
    {
      _uiApplyPendingAfterQuietOrScroll = false;
      _pendingUiApplyById.clear();
      ConversationPerfGateLog.log(
        'mirror_skip_ui',
        extras: <String, Object?>{'via': 'pending_ui_flush', 'reason': reason},
      );
      return;
    }
  }

  void _onCoalescedReloadTimerFired() {
    _reloadUiCoalesceTimer = null;
    final until = _postPopCoalesceUntil;
    if (until != null && DateTime.now().isAfter(until)) {
      _postPopCoalesceUntil = null;
      _postPopCoalesceWindowStart = null;
      _postPopCoalesceScheduled = false;
    }
    if (ConversationPerfFlags.deferUiNotifyWhileFeedScrolling &&
        _isFeedScrollingNow) {
      _reloadUiDeferredWhileScrolling = true;
      _scheduleCoalescedReloadUi(postPop: isInPostPopCoalesceWindow);
      return;
    }
    final forceFull = _pendingCoalesceForceFull;
    _pendingCoalesceForceFull = false;
    unawaited(_restoreSdkProjectionImpl(forceFull: forceFull));
  }

  /// 停滑后落地因滚动挂起的 soft reload（带 settle，防抖动连 flush）。
  void flushDeferredProjectionRestoreAfterScroll() {
    if (!_reloadUiDeferredWhileScrolling &&
        !_uiApplyPendingAfterQuietOrScroll &&
        _pendingUiApplyById.isEmpty &&
        !_sdkSyncResumeAfterScroll &&
        _deferredViewModelPersistById.isEmpty) {
      return;
    }
    _scrollEndFlushTimer?.cancel();
    final settle = ConversationPerfFlags.uiApplyFlushSettleDelay;
    if (settle <= Duration.zero) {
      _runScrollEndFlush();
      return;
    }
    _scrollEndFlushTimer = Timer(settle, () {
      _scrollEndFlushTimer = null;
      if (_isFeedScrollingNow) {
        return;
      }
      _runScrollEndFlush();
    });
  }

  void _runScrollEndFlush() {
    if (!_reloadUiDeferredWhileScrolling &&
        !_uiApplyPendingAfterQuietOrScroll &&
        _pendingUiApplyById.isEmpty &&
        !_sdkSyncResumeAfterScroll &&
        _deferredViewModelPersistById.isEmpty) {
      return;
    }
    if (_scrollEndFlushInFlight != null) {
      _scrollEndFlushDirty = true;
      return;
    }
    final task = () async {
      try {
        do {
          _scrollEndFlushDirty = false;
          _reloadUiDeferredWhileScrolling = false;
          _reloadUiCoalesceTimer?.cancel();
          _reloadUiCoalesceTimer = null;
          final forceFull = _pendingCoalesceForceFull;
          _pendingCoalesceForceFull = false;
          final resumeSdk = _sdkSyncResumeAfterScroll;
          _sdkSyncResumeAfterScroll = false;
          await _flushDeferredViewModelPersist(reason: 'scroll_end');
          await _flushPendingUiApply(reason: 'scroll_end');
          if (forceFull) {
            await _restoreSdkProjectionImpl(forceFull: true);
          }
          if (resumeSdk) {
            unawaited(
              syncFromSdk(
                reason: 'resume_after_scroll',
                drainMode: ConversationSdkDrainMode.singlePage,
              ),
            );
          }
        } while (_scrollEndFlushDirty);
      } finally {
        _scrollEndFlushInFlight = null;
        // 收尾瞬间又脏：再开一轮。
        if (_scrollEndFlushDirty) {
          _scrollEndFlushDirty = false;
          _runScrollEndFlush();
        }
      }
    }();
    _scrollEndFlushInFlight = task;
    unawaited(task);
  }

  Future<void> _flushDeferredViewModelPersist({required String reason}) async {
    if (_deferredViewModelPersistById.isEmpty) {
      return;
    }
    final batch = _deferredViewModelPersistById.values.toList(growable: false);
    _deferredViewModelPersistById.clear();
    ConversationPerfGateLog.log(
      'view_model_persist_flush',
      extras: <String, Object?>{'reason': reason, 'count': batch.length},
    );
    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: batch,
      source: ConversationMutationSource.sdkPage,
      onCommittedBatch: (result) => committedBatch = result,
    );
    if (merged.isEmpty) {
      return;
    }
    await _applyPacedSyncPageToUi(
      merged,
      reason: 'view_model_flush_$reason',
      allowDefer: false,
      committedBatch: committedBatch,
    );
    // 写库后同样尝试 append，避免只 defer 不进窗。
    await ChatSessionController.instance.appendOlderFromLocal(
      convType: 2,
      protectVirtualViewport: true,
    );
    await ChatSessionController.instance.appendOlderFromLocal(
      convType: 1,
      protectVirtualViewport: true,
    );
  }

  Future<void> _restoreSdkProjectionImpl({bool forceFull = false}) async {
    if (_sdkProjectionRestoreInFlight != null) {
      _sdkProjectionRestoreDirty = true;
      _sdkProjectionRestoreDirtyForceFull =
          _sdkProjectionRestoreDirtyForceFull || forceFull;
      return _sdkProjectionRestoreInFlight!;
    }
    final task = ChatMainThreadPerf.isEnabled
        ? ChatMainThreadPerf.measureAsync(
            ChatMainThreadPerf.conversationReloadMs,
            () => _restoreSdkProjectionImplInner(forceFull: forceFull),
            source: forceFull ? 'full' : 'soft',
            conversationType: 'mixed',
          )
        : _restoreSdkProjectionImplInner(forceFull: forceFull);
    _sdkProjectionRestoreInFlight = task;
    try {
      await task;
    } finally {
      _sdkProjectionRestoreInFlight = null;
      if (_sdkProjectionRestoreDirty) {
        final full = _sdkProjectionRestoreDirtyForceFull;
        _sdkProjectionRestoreDirty = false;
        _sdkProjectionRestoreDirtyForceFull = false;
        unawaited(_restoreSdkProjectionImpl(forceFull: full));
      }
    }
  }

  Future<void> _restoreSdkProjectionImplInner({bool forceFull = false}) async {
    projectionRestoreInvocationCount++;
    final override = projectionRestoreImplOverride;
    if (override != null) {
      await override();
      return;
    }
    {
      ConversationPerfGateLog.log(
        'ui_source',
        extras: <String, Object?>{
          'source': 'sdk_store',
          'via': 'reload_ui_impl',
          'forceFull': forceFull,
        },
      );
      await ChatSessionController.instance.restoreProjection(
        reason: ConversationStoreProjectionReason.sdkProjectionRestore,
      );
      return;
    }
  }

  Future<void> _applyPacedSyncPageToUi(
    List<V2TimConversation> merged, {
    required String reason,
    bool allowDefer = true,
    ConversationSdkCommittedBatch? committedBatch,
  }) async {
    if (merged.isEmpty) {
      return;
    }
    {
      // Phase2：paced Sync 只 mirror，不驱动列表 UI。
      ConversationPerfGateLog.log(
        'mirror_skip_ui',
        extras: <String, Object?>{
          'via': 'paced',
          'reason': reason,
          'count': merged.length,
        },
      );
      return;
    }
  }

  Future<V2TimConversation?> applyConversationPinLocally({
    required String conversationID,
    required bool isPinned,
    V2TimConversation? snapshot,
    double? listScrollOffset,
  }) async {
    final owner = _ownerUserId();
    await _restoreDurableMutationState(
      ownerUserId: owner,
      conversationId: conversationID,
    );
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: conversationID,
      fieldPatch: <ConversationMutationField, Object?>{
        ConversationMutationField.pin: isPinned,
      },
      fullSnapshot: snapshot,
    );
    final commit = plan == null
        ? null
        : await ConversationLocalStore.instance.commitCoordinatorPlan(
            plan: plan,
          );
    var updated = commit == null || commit.upsertedSnapshots.isEmpty
        ? null
        : commit.upsertedSnapshots.first;
    if (updated == null) {
      // SDK realtime 可能先把 coordinator 的 pin 字段推进到目标值，随后本地
      // confirmed intent 会变成 no-plan/noop。此时仍要修复 SQLite is_pinned，
      // 否则虚拟列表重水合后会重新按时间序显示带图钉的会话。
      await ConversationLocalStore.instance.replaceAllPinnedFlags(
        pinnedConversationIds:
            ConversationPinSyncService.instance.pinnedConversationIds,
        ownerUserId: owner,
      );
      updated = await ConversationLocalStore.instance.conversationById(
        conversationID,
        ownerUserId: owner,
      );
    }
    ConversationPinFlickerLog.log(
      'sync_pin_local_write',
      conversationID: conversationID,
      extras: <String, Object?>{
        'isPinned': isPinned,
        'updated': updated != null,
        'localPinned': updated?.isPinned,
        'listScroll': listScrollOffset?.toStringAsFixed(1) ?? 'na',
      },
    );
    if (updated != null) {
      final session = ChatSessionController.instance;
      // 先就地改底色，短停顿后重排；视口保持，不主动滚顶。
      // 若乐观阶段已对齐 pin+序，notifier 内会短路跳过二次 deferred。
      if (commit != null && commit.shouldNotifyUi) {
        await ChatSessionController.instance.applyCommittedPinProjection(
          commit.uiBatch,
          conversationID: conversationID,
          isPinned: isPinned,
          listScrollOffset: listScrollOffset,
        );
      } else {
        // The SDK callback may already have advanced the Coordinator, leaving
        // this confirmed local intent with no plan. The repaired SQLite row is
        // still a committed Store snapshot; publish it with the durable
        // generation instead of bypassing the commit projection API.
        final durable =
            await ConversationLocalStore.instance.coordinatorDurableState(
          ownerUserId: owner,
          conversationId: conversationID,
        );
        await ChatSessionController.instance.applyCommittedPinProjection(
          ConversationUiSnapshotBatch<V2TimConversation>(
            upsertedSnapshots: <V2TimConversation>[updated],
            deletedCanonicalIds: const <String>[],
            structureChanged: true,
            changedFieldMasks: <String, Set<ConversationMutationField>>{
              conversationID: const <ConversationMutationField>{
                ConversationMutationField.pin,
              },
            },
            commitGeneration: durable.generation,
          ),
          conversationID: conversationID,
          isPinned: isPinned,
          listScrollOffset: listScrollOffset,
        );
      }
      // 写库后按需校正类型窗：center 跟视口，勿跟掉队会话；窗外才 forceReload。
      final convType =
          (updated.type == 2 || (updated.groupID?.trim().isNotEmpty == true))
              ? 2
              : 1;
      final hydrateStart = session.hydratedStartOffsetForType(convType);
      final hydrateLength = session.hydratedLengthForType(convType);
      final movedTypeIndex = session.typeIndexOfConversationId(
        convType,
        conversationID,
      );
      final anchorId = (session.viewportAnchorConversationId ?? '').trim();
      final viewportAnchorTypeIndex = anchorId.isEmpty
          ? null
          : session.typeIndexOfConversationId(convType, anchorId);
      final hydrateMidTypeIndex =
          hydrateLength > 0 ? hydrateStart + (hydrateLength ~/ 2) : null;
      final center = resolvePinHydrateCenterIndex(
        viewportAnchorTypeIndex: viewportAnchorTypeIndex,
        hydrateMidTypeIndex: hydrateMidTypeIndex,
        fallback: 0,
      );
      final forceReload = shouldForceReloadTypeHydrateAfterPin(
        movedTypeIndex: movedTypeIndex,
        hydrateStart: hydrateStart,
        hydrateLength: hydrateLength,
      );
      ConversationPinFlickerLog.log(
        'sync_pin_hydrate_plan',
        conversationID: conversationID,
        extras: <String, Object?>{
          'convType': convType,
          'center': center,
          'forceReload': forceReload,
          'movedTypeIndex': movedTypeIndex,
          'hydrateStart': hydrateStart,
          'hydrateLength': hydrateLength,
          'viewportAnchor': anchorId.isEmpty ? null : anchorId,
        },
      );
      unawaited(
        session.ensureTypeIndexHydrated(
          convType: convType,
          centerIndex: center,
          forceReload: forceReload,
        ),
      );
    }
    return updated;
  }

  Future<void> reconcileConversationPinSetLocally({
    required Set<String> previousPinnedConversationIds,
    required Set<String> pinnedConversationIds,
  }) async {
    final changed = <String>{
      ...previousPinnedConversationIds,
      ...pinnedConversationIds,
    }.where((id) {
      final wasPinned = previousPinnedConversationIds.any(
        (item) => MessageConversationId.sameConversation(item, id),
      );
      final isPinned = pinnedConversationIds.any(
        (item) => MessageConversationId.sameConversation(item, id),
      );
      return wasPinned != isPinned;
    });
    final owner = _ownerUserId();
    if (changed.isEmpty) {
      // Coordinator 无字段变化不等于 SQLite 镜像一定一致。SDK callback
      // 可能先把 shadow pin 更新为目标值，导致后续本地全量对账没有 plan；
      // 仍需用已确认的完整置顶集合修复 is_pinned，供虚拟列表索引排序。
      // skipIfUnchanged: 让 ConversationLocalStore 在指纹一致时跳过全表
      // SELECT（cold start 961 行 conversations 表 ~2.8s）。
      await ConversationLocalStore.instance.replaceAllPinnedFlags(
        pinnedConversationIds: pinnedConversationIds,
        ownerUserId: owner,
        skipIfUnchanged: true,
      );
      return;
    }
    final plans = <ConversationDatabaseCommitPlan<V2TimConversation>>[];
    for (final id in changed) {
      final pinned = pinnedConversationIds.any(
        (item) => MessageConversationId.sameConversation(item, id),
      );
      await _restoreDurableMutationState(
        ownerUserId: owner,
        conversationId: id,
      );
      final plan = await ConversationMutationShadowBridge.instance
          .prepareLocalIntentCommit(
        ownerUserId: owner,
        conversationId: id,
        fieldPatch: <ConversationMutationField, Object?>{
          ConversationMutationField.pin: pinned,
        },
      );
      if (plan != null) {
        plans.add(plan);
      }
    }
    await ConversationLocalStore.instance.commitCoordinatorPinSetPlans(
      plans: plans,
      pinnedConversationIds: pinnedConversationIds,
    );
    // 即使某个 plan 因 shadow 已经是相同值而被忽略，也必须校准镜像列。
    // 该方法只写实际变化行，正常路径不会造成重复更新。
    // skipIfUnchanged: 上面的 commitCoordinatorPinSetPlans 已经执行了
    // replaceAllPinnedFlags（同 owner 内 fingerprint 必变化），所以此处
    // 用 skipIfUnchanged=true 避免重复 SELECT。
    await ConversationLocalStore.instance.replaceAllPinnedFlags(
      pinnedConversationIds: pinnedConversationIds,
      ownerUserId: owner,
      skipIfUnchanged: true,
    );
  }

  Future<V2TimConversation?> applyConversationMuteLocally({
    required String conversationID,
    required int recvOpt,
    V2TimConversation? snapshot,
  }) async {
    final owner = _ownerUserId();
    await _restoreDurableMutationState(
      ownerUserId: owner,
      conversationId: conversationID,
    );
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: conversationID,
      fieldPatch: <ConversationMutationField, Object?>{
        ConversationMutationField.mute: recvOpt,
      },
      fullSnapshot: snapshot,
    );
    final commit = plan == null
        ? null
        : await ConversationLocalStore.instance.commitCoordinatorPlan(
            plan: plan,
          );
    if (commit != null && commit.shouldNotifyUi) {
      await ChatSessionController.instance.applyCommittedProjection(
        commit.uiBatch,
      );
    }
    return commit == null || commit.upsertedSnapshots.isEmpty
        ? null
        : commit.upsertedSnapshots.first;
  }

  Future<V2TimConversation?> applyConversationUnreadLocally({
    required String conversationID,
    required int unreadCount,
    V2TimConversation? snapshot,
  }) async {
    final owner = _ownerUserId();
    await _restoreDurableMutationState(
      ownerUserId: owner,
      conversationId: conversationID,
    );
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: conversationID,
      fieldPatch: <ConversationMutationField, Object?>{
        ConversationMutationField.unread: unreadCount,
      },
      fullSnapshot: snapshot,
    );
    final commit = plan == null
        ? null
        : await ConversationLocalStore.instance.commitCoordinatorPlan(
            plan: plan,
          );
    final updated = commit == null || commit.upsertedSnapshots.isEmpty
        ? null
        : commit.upsertedSnapshots.first;
    if (commit != null && commit.shouldNotifyUi) {
      await ChatSessionController.instance.applyCommittedProjection(
        commit.uiBatch,
      );
    }
    return updated;
  }

  Future<V2TimConversation?> applyConversationMetadataPatch({
    required String conversationID,
    String? showName,
    String? faceUrl,
    V2TimConversation? snapshot,
    bool remoteAuthority = false,
    bool explicitAuthority = false,
  }) async {
    final patch = <ConversationMutationField, Object?>{
      if (showName != null) ConversationMutationField.name: showName,
      if (faceUrl != null) ConversationMutationField.avatar: faceUrl,
    };
    final owner = _ownerUserId();
    await _restoreDurableMutationState(
      ownerUserId: owner,
      conversationId: conversationID,
    );
    final plan =
        await ConversationMutationShadowBridge.instance.prepareFieldPatchCommit(
      ownerUserId: owner,
      conversationId: conversationID,
      source: explicitAuthority
          ? ConversationMutationSource.userExplicitMetadata
          : remoteAuthority
              ? ConversationMutationSource.remoteMetadata
              : ConversationMutationSource.localCache,
      fieldPatch: patch,
      fullSnapshot: snapshot,
    );
    final commit = plan == null
        ? null
        : await ConversationLocalStore.instance.commitCoordinatorPlan(
            plan: plan,
          );
    if (commit != null && commit.shouldNotifyUi) {
      await ChatSessionController.instance.applyCommittedProjection(
        commit.uiBatch,
      );
    }
    return commit == null || commit.upsertedSnapshots.isEmpty
        ? null
        : commit.upsertedSnapshots.first;
  }

  Future<bool> get haveMoreData async {
    final tabs = ConversationTabStore.instance;
    return !tabs.finishedForType(1) || !tabs.finishedForType(2);
  }

  Future<bool> haveMoreDataForType(int convType) async {
    return !ConversationTabStore.instance.finishedForType(convType);
  }

  void _completeServerSyncAwaitingUi() {
    ConversationListSyncNotifier.instance.setAwaitingServerSync(false);
    ConversationListSyncNotifier.instance.setRetryableFailure(false);
  }

  void _enqueuePendingSync({
    required String reason,
    bool reset = false,
    bool force = false,
    bool loadAllPages = false,
    bool reloadUiEachPage = true,
    ConversationSdkDrainMode? drainMode,
    int? conversationType,
  }) {
    final incoming = ConversationPendingSdkSync(
      reason: reason,
      reset: reset,
      force: force,
      loadAllPages: loadAllPages,
      reloadUiEachPage: reloadUiEachPage,
      drainMode: drainMode,
      conversationTypes:
          conversationType == null ? null : <int>{conversationType},
    );
    final existing = _pendingSdkSync;
    _pendingSdkSync =
        existing == null ? incoming : existing.mergePreferStronger(incoming);
    _log(
      'syncFromSdk queued reason=$reason reset=$reset '
      'loadAllPages=$loadAllPages drainMode=${drainMode?.name}',
    );
  }

  /// 解析写库节奏；供单测断言 `reset` 不再隐含全量。
  @visibleForTesting
  static ConversationSdkDrainMode resolveDrainMode({
    required bool pacedSdkPersist,
    required bool reset,
    required bool force,
    required bool loadAllPages,
    ConversationSdkDrainMode? drainMode,
  }) {
    if (drainMode != null) {
      return drainMode;
    }
    if (!pacedSdkPersist) {
      // 旧行为：reset/force/loadAllPages 都视为可持续拉多页。
      if (loadAllPages || reset || force) {
        return ConversationSdkDrainMode.backgroundContinue;
      }
      return ConversationSdkDrainMode.singlePage;
    }
    if (loadAllPages) {
      return ConversationSdkDrainMode.backgroundContinue;
    }
    if (reset || force) {
      return ConversationSdkDrainMode.foregroundLimited;
    }
    return ConversationSdkDrainMode.singlePage;
  }

  /// 脏 meta：单聊游标已判死但本地 C2C 行数仍低于首屏地板 → 应重开 C2C。
  @visibleForTesting
  static bool shouldHealC2cCursor({
    required bool healEnabled,
    required bool c2cHaveMore,
    required int c2cRowCount,
    required int healFloor,
  }) {
    if (!healEnabled) {
      return false;
    }
    if (c2cHaveMore) {
      return false;
    }
    final floor = healFloor > 0 ? healFloor : 40;
    return c2cRowCount < floor;
  }

  /// 若需自愈：重开 C2C 游标并至少 ByFilter 拉一页。返回是否执行了自愈拉页。
  Future<bool> healC2cCursorIfNeeded({String reason = 'heal'}) async {
    if (_ownerUserId().isEmpty) return false;
    final tabs = ConversationTabStore.instance;
    if (tabs.primedForType(ConversationType.V2TIM_C2C)) return false;
    await tabs.ensurePrimed(
        convType: ConversationType.V2TIM_C2C, coldStart: true);
    return tabs.primedForType(ConversationType.V2TIM_C2C);
  }

  void scheduleBackgroundDrain({required String reason}) {
    scheduleIdleBackgroundDrain(reason: reason);
  }

  void scheduleIdleBackgroundDrain({required String reason, Duration? delay}) {
    if (!ConversationPerfFlags.pacedSdkPersist) {
      return;
    }
    if (!ConversationPerfFlags.idleBackgroundDrainEnabled) {
      _idleDrainTimer?.cancel();
      _idleDrainTimer = null;
      ConversationListSyncNotifier.instance.setDraining(false);
      _log('idle_drain skipped (disabled) reason=$reason');
      return;
    }
    final cycleCap = ConversationPerfFlags.idleDrainMaxCyclesPerSession;
    if (cycleCap > 0 && _idleDrainCycleCount >= cycleCap) {
      _idleDrainTimer?.cancel();
      _idleDrainTimer = null;
      ConversationListSyncNotifier.instance.setDraining(false);
      _log(
        'idle_drain skipped (cycle_cap=$cycleCap reached) '
        'reason=$reason',
      );
      return;
    }
    _idleDrainTimer?.cancel();
    ConversationListSyncNotifier.instance.setDraining(true);
    final wait = delay ?? ConversationPerfFlags.idleDrainStartDelay;
    _log(
      'idle_drain scheduled reason=$reason '
      'cycle=${_idleDrainCycleCount + 1}/$cycleCap '
      'delayMs=${wait.inMilliseconds}',
    );
    StartupPerfLog.markTagged(
      'idle_drain_schedule',
      category: 'post_home',
      details: <String, Object>{
        'reason': reason,
        'cycle': _idleDrainCycleCount + 1,
        'cap': cycleCap,
        'delayMs': wait.inMilliseconds,
      },
    );
    _idleDrainTimer = Timer(wait, () {
      _idleDrainTimer = null;
      unawaited(_runIdleBackgroundDrain(reason: reason));
    });
  }

  void beginResumeQuietWindow({Duration? duration}) {
    final flagHold = ConversationPerfFlags.resumeQuietDuration;
    final hold = duration ??
        (flagHold > Duration.zero
            ? flagHold
            : ResumeForegroundPolicy.conversationHoldDuration);
    if (hold <= Duration.zero) {
      return;
    }
    final until = DateTime.now().add(hold);
    final current = _resumeQuietUntil;
    if (current == null || until.isAfter(current)) {
      _resumeQuietUntil = until;
    }
    ConversationPerfGateLog.log(
      'resume_quiet_enter',
      extras: <String, Object?>{'durationMs': hold.inMilliseconds},
    );
    _resumeQuietExitTimer?.cancel();
    final exitAt = _resumeQuietUntil!;
    _resumeQuietExitTimer = Timer(exitAt.difference(DateTime.now()), () {
      _resumeQuietExitTimer = null;
      ConversationPerfGateLog.log('resume_quiet_exit');
      if (!_isFeedScrollingNow) {
        unawaited(_flushPendingUiApply(reason: 'quiet_end'));
      }
    });
  }

  @visibleForTesting
  static bool shouldFullResetOnServerFinish({
    required bool hasSyncedOnce,
    required int rowCount,
  }) {
    return !hasSyncedOnce || rowCount == 0;
  }

  /// 登录冷启是否尝试 IM Snapshot（方案 B：有库也暖；失败再降级腾讯分页）。
  /// [rowCount] 保留参数兼容旧调用，不再作为门闩。
  static bool shouldUseImSnapshotBootstrap({required int rowCount}) {
    return shouldAttemptImSnapshotOnLoginBootstrap();
  }

  /// 登录会话 bootstrap 是否尝试 Snapshot。
  /// 由 [ConversationPerfFlags.attemptImSnapshotOnLoginBootstrap] 控制；
  /// 关闭后首屏只依赖本地库 + SDK paced sync。
  static bool shouldAttemptImSnapshotOnLoginBootstrap() =>
      ConversationPerfFlags.attemptImSnapshotOnLoginBootstrap;

  @visibleForTesting
  static bool shouldPauseIdleDrain({
    required bool isScrolling,
    required bool inChatTransition,
  }) {
    return isScrolling || inChatTransition;
  }

  static bool shouldSkipPostHomeConversationReset({
    required bool conversationListBootstrapDone,
  }) {
    return conversationListBootstrapDone;
  }

  /// 治愈脏 meta：游标显示还有下一页，但 haveMore 被误写成 false。
  @visibleForTesting
  static bool shouldHealHaveMoreFromNextSeq({
    required bool haveMore,
    required String nextSeq,
  }) {
    if (haveMore) {
      return false;
    }
    final seq = nextSeq.trim();
    return seq.isNotEmpty && seq != '0';
  }

  /// 单页拉取后重算 haveMore（防 IM 未就绪空页把 flag 永久毒死）。
  @visibleForTesting
  static bool resolveHaveMoreAfterPage({
    required bool haveMoreBeforePage,
    required int pageLength,
    required int pagesLoadedBeforeThisPage,
    required String nextSeq,
    String requestedNextSeq = '0',
    bool? isFinished,
    bool allowTerminal = true,
  }) {
    // Tencent SDK 的 isFinished 是分页是否结束的权威标记。部分版本在
    // isFinished=true 时仍会回传上一页 nextSeq，不能再据此继续翻页。
    if (isFinished == true) {
      return allowTerminal ? false : haveMoreBeforePage;
    }
    final normalizedNextSeq = nextSeq.trim();
    if (normalizedNextSeq.isNotEmpty && normalizedNextSeq != '0') {
      return true;
    }
    if (pageLength > 0) {
      return false;
    }
    if (pagesLoadedBeforeThisPage > 0) {
      return false;
    }
    final requested = requestedNextSeq.trim();
    if (requested.isNotEmpty && requested != '0') {
      return false;
    }
    return haveMoreBeforePage;
  }

  bool _shouldPauseIdleWork() {
    final scrolling = ChatSessionController.instance.isFeedScrolling;
    return shouldPauseIdleDrain(
      isScrolling: scrolling != null && scrolling(),
      inChatTransition: hasActiveChatTransition,
    );
  }

  Future<void> _runIdleBackgroundDrain({required String reason}) async {
    if (!ConversationPerfFlags.pacedSdkPersist ||
        !ConversationPerfFlags.idleBackgroundDrainEnabled) {
      ConversationListSyncNotifier.instance.setDraining(false);
      return;
    }
    if (_backgroundDrainInFlight) {
      return;
    }
    _idleDrainCycleCount++;
    StartupPerfLog.markTagged(
      'idle_drain_start',
      category: 'post_home',
      details: <String, Object>{
        'reason': reason,
        'cycle': _idleDrainCycleCount
      },
    );
    if (_shouldPauseIdleWork()) {
      _log('idle_drain pause reason=$reason');
      scheduleIdleBackgroundDrain(reason: '${reason}_paused');
      return;
    }
    _backgroundDrainInFlight = true;
    ConversationListSyncNotifier.instance.setDraining(true);
    _log('idle_drain start reason=$reason');
    // 最近一次 sync meta：循环内的 pre-check 和 post-check 复用同一变量，
    // 避免每次循环 + finally 再读 3 次 SQLite。循环未进入时保持 null，
    // finally 才做兜底 readSyncMeta。
    ConversationSyncMeta? latestMeta;
    try {
      while (true) {
        if (_shouldPauseIdleWork()) {
          _log('idle_drain pause mid reason=$reason');
          break;
        }
        if (!shouldScheduleIdleDrainResume(
          idleBackgroundDrainEnabled:
              ConversationPerfFlags.idleBackgroundDrainEnabled,
          haveMore: true,
          sessionDrainPages: _idleDrainSessionPages,
          sessionDrainPageBudget:
              ConversationPerfFlags.idleDrainSessionPageBudget,
        )) {
          _log('idle_drain budget exhausted pages=$_idleDrainSessionPages');
          break;
        }
        final meta = await ConversationLocalStore.instance.readSyncMeta();
        latestMeta = meta;
        if (!meta.c2cHaveMore && !meta.groupHaveMore) {
          break;
        }
        if (_pageSyncInFlight) {
          _enqueuePendingSync(
            reason: '${reason}_drain',
            drainMode: ConversationSdkDrainMode.backgroundContinue,
            reloadUiEachPage:
                ConversationPerfFlags.backgroundUiRefreshEveryPages > 0,
          );
          _log('idle_drain yielded to in-flight sync');
          return;
        }
        await syncFromSdk(
          reason: '${reason}_drain',
          // 外层负责预算、yield 与 resume；内层严格只拉一页，否则一次调用
          // 会绕过 idleDrainSessionPageBudget 直接排空整个账号。
          drainMode: ConversationSdkDrainMode.singlePage,
          reloadUiEachPage: false,
        );
        _idleDrainSessionPages++;
        final refreshEvery =
            ConversationPerfFlags.backgroundUiRefreshEveryPages;
        if (refreshEvery > 0 && _idleDrainSessionPages % refreshEvery == 0) {
          await ChatSessionController.instance.restoreProjection(
            reason: ConversationStoreProjectionReason.backgroundDrain,
          );
        }
        final after = await ConversationLocalStore.instance.readSyncMeta();
        latestMeta = after;
        if (!after.c2cHaveMore && !after.groupHaveMore) {
          break;
        }
        break;
      }
    } finally {
      _backgroundDrainInFlight = false;
      final meta =
          latestMeta ?? await ConversationLocalStore.instance.readSyncMeta();
      final stillHaveMore = meta.c2cHaveMore || meta.groupHaveMore;
      final canResume = stillHaveMore &&
          _pendingSdkSync == null &&
          !_pageSyncInFlight &&
          shouldScheduleIdleDrainResume(
            idleBackgroundDrainEnabled:
                ConversationPerfFlags.idleBackgroundDrainEnabled,
            haveMore: stillHaveMore,
            sessionDrainPages: _idleDrainSessionPages,
            sessionDrainPageBudget:
                ConversationPerfFlags.idleDrainSessionPageBudget,
          );
      ConversationListSyncNotifier.instance.setDraining(canResume);
      if (canResume) {
        scheduleIdleBackgroundDrain(reason: '${reason}_resume');
      }
      _log(
        'idle_drain done haveMore=$stillHaveMore canResume=$canResume '
        'reason=$reason',
      );
      StartupPerfLog.markTagged(
        'idle_drain_done',
        category: 'post_home',
        details: <String, Object>{
          'reason': reason,
          'haveMore': stillHaveMore,
          'canResume': canResume,
          'pages': _idleDrainSessionPages,
        },
      );
    }
  }

  int _typedPageCount(int convType) {
    const coldStartFallback = ConversationTabStore.coldStartFirstPageSize;
    if (convType == ConversationType.V2TIM_GROUP) {
      final n = ConversationPerfFlags.uiSnapshotGroupLimit;
      return n > 0 ? n : coldStartFallback;
    }
    final n = ConversationPerfFlags.uiSnapshotC2cLimit;
    return n > 0 ? n : coldStartFallback;
  }

  /// SDK first-page ownership is shared with the mounted conversation tabs.
  /// Explicit reset refreshes those pages; ordinary entry reuses their cursor.
  Future<ConversationBootstrapResult> bootstrapTypedFirstScreen({
    String reason = 'typed_bootstrap',
    bool reset = false,
  }) {
    final owner = _ownerUserId();
    final generation = _syncGeneration;
    final pending = _sdkBootstrapTask;
    if (pending != null &&
        _sdkBootstrapOwner == owner &&
        _sdkBootstrapGeneration == generation) {
      if (!reset || _sdkBootstrapResets) return pending;
      return pending.then<ConversationBootstrapResult>((_) async {
        if (!_isCurrentSync(owner, generation)) {
          return ConversationBootstrapResult.stale;
        }
        return bootstrapTypedFirstScreen(reason: reason, reset: true);
      });
    }
    _sdkBootstrapOwner = owner;
    _sdkBootstrapGeneration = generation;
    _sdkBootstrapResets = reset;
    late final Future<ConversationBootstrapResult> task;
    task =
        _bootstrapSdkFirstScreen(reason: reason, reset: reset).whenComplete(() {
      if (identical(_sdkBootstrapTask, task)) _sdkBootstrapTask = null;
    });
    _sdkBootstrapTask = task;
    return task;
  }

  Future<ConversationBootstrapResult> _bootstrapSdkFirstScreen({
    required String reason,
    required bool reset,
  }) async {
    final owner = _ownerUserId();
    final generation = _syncGeneration;
    if (owner.isEmpty) return ConversationBootstrapResult.stale;
    final tabs = ConversationTabStore.instance;
    // Publish successful types even when another first page fails. Calling
    // projection recovery after a failure would immediately prime that failed
    // type again while this attempt still reports its earlier failed result.
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    final sync = ConversationListSyncNotifier.instance;
    sync.setSyncing(true);
    try {
      await Future.wait<void>([
        for (final type in const [1, 2])
          reset
              ? tabs.loadFirstPage(convType: type, count: _typedPageCount(type))
              : tabs.ensurePrimed(
                  convType: type,
                  coldStart: true,
                  caller: 'bootstrapTypedFirstScreen',
                ),
      ]);
      if (!_isCurrentSync(owner, generation))
        return ConversationBootstrapResult.stale;
      final success = tabs.primedForType(1) &&
          tabs.primedForType(2) &&
          !tabs.lastLoadFailedForType(1) &&
          !tabs.lastLoadFailedForType(2);
      sync.setHasSyncedOnce(tabs.primedForType(1) && tabs.primedForType(2));
      sync.setRetryableFailure(!success);
      if (success) await restoreSdkProjection(immediate: true);
      if (!_isCurrentSync(owner, generation))
        return ConversationBootstrapResult.stale;
      return success
          ? ConversationBootstrapResult.success
          : ConversationBootstrapResult.failed;
    } catch (error) {
      if (_isCurrentSync(owner, generation)) sync.setRetryableFailure(true);
      _log('SDK first page failed reason=$reason: $error');
      return ConversationBootstrapResult.failed;
    } finally {
      if (_isCurrentSync(owner, generation)) sync.setSyncing(tabs.isLoading);
    }
  }

  /// Compatibility entry point; user pagination uses the SDK tab cursor only.
  Future<void> syncFromSdkByType({
    required int convType,
    String reason = 'typed_page',
    bool reset = false,
    bool force = false,
    int? count,
    ConversationSdkDrainMode drainMode = ConversationSdkDrainMode.singlePage,
  }) async {
    if (_ownerUserId().isEmpty) return;
    final tabs = ConversationTabStore.instance;
    final type = convType == 2 ? 2 : 1;
    final pageCount = count ?? _typedPageCount(type);
    if (reset || force) {
      await tabs.loadFirstPage(convType: type, count: pageCount);
    } else if (!tabs.primedForType(type)) {
      await tabs.ensurePrimed(convType: type, count: pageCount);
    } else {
      await tabs.loadMore(convType: type, count: pageCount);
    }
  }

  bool _isCurrentSync(String owner, int generation) {
    return generation == _syncGeneration && _ownerUserId() == owner;
  }

  @visibleForTesting
  static bool isSyncResultCurrent({
    required String startedOwner,
    required int startedGeneration,
    required String currentOwner,
    required int currentGeneration,
  }) {
    return startedOwner.isNotEmpty &&
        startedOwner == currentOwner &&
        startedGeneration == currentGeneration;
  }

  /// User refresh reloads the two SDK first pages, without an account-wide scan.
  Future<void> userInitiatedFullRefresh(
      {String reason = 'user_refresh'}) async {
    await bootstrapTypedFirstScreen(reason: reason, reset: true);
  }

  Future<void> syncFromSdk({
    String reason = 'manual',
    bool reset = false,
    bool force = false,
    int count = _defaultPageSize,
    bool loadAllPages = false,
    bool reloadUiEachPage = false,
    ConversationSdkDrainMode? drainMode,
    int? conversationType,
  }) async {
    final token = _lifecycleGuard.begin('conversation-sync');
    if (!_lifecycleGuard.canCommit(token) || _ownerUserId().isEmpty) return;
    if (conversationType != null) {
      final tabs = ConversationTabStore.instance;
      if (reset || force) {
        await tabs.loadFirstPage(convType: conversationType, count: count);
      } else {
        await tabs.ensurePrimed(convType: conversationType, count: count);
      }
      return;
    }
    await bootstrapTypedFirstScreen(reason: reason, reset: reset || force);
  }

  Future<void> syncNextPage(
      {int count = _defaultPageSize, int? convType}) async {
    await syncFromSdkByType(
        convType: convType ?? 1, count: count, reason: 'sync_next_page');
  }

  /// ByFilter 单聊空 / 同步完成后：把「有过记录」的 C2C 补进本地库。
  Future<C2cHistoryBackfillStats> maybeBackfillC2cFromHistoryPeers({
    String reason = 'manual',
  }) async {
    if (!ConversationPerfFlags.c2cHistoryBackfillEnabled) {
      return const C2cHistoryBackfillStats();
    }
    final inFlight = _c2cHistoryBackfillInFlight;
    if (inFlight != null) {
      await inFlight;
      return const C2cHistoryBackfillStats(skipped: 1);
    }
    final task = _runC2cHistoryBackfill(reason: reason);
    _c2cHistoryBackfillInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_c2cHistoryBackfillInFlight, task)) {
        _c2cHistoryBackfillInFlight = null;
      }
    }
  }

  Future<void> _persistSdkDeleted(
    List<String> ids, {
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) return;
    if (identity != null && !await _hasCurrentMessageCoreLease(identity)) {
      return;
    }
    final deleted = await _commitConversationDeletes(
      ids,
      ownerUserId: identity?.ownerUserId,
    );
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) return;
    if (deleted.isEmpty) {
      return;
    }
    await _notifyUiAfterLocalWrite(deletedIds: deleted);
    _notifyActiveChatClosed(deleted);
  }

  Future<List<String>> _commitConversationDeletes(
    List<String> ids, {
    String? ownerUserId,
  }) async {
    final owner = ownerUserId?.trim().isNotEmpty == true
        ? ownerUserId!.trim()
        : _ownerUserId();
    for (final id in ids) {
      await _restoreDurableMutationState(
        ownerUserId: owner,
        conversationId: id,
      );
    }
    if (!ConversationMutationShadowBridge.authoritativeSdkCommitEnabled) {
      // 072 rollback allowlist: the kill switch restores the complete legacy
      // writer; authoritative and legacy writes are never active together.
      final admitted = await ConversationMutationShadowBridge.instance
          .admitSdkDeletedForCommit(ownerUserId: owner, conversationIds: ids);
      return ConversationLocalStore.instance.deleteBatch(
        conversationIds: admitted,
        ownerUserId: owner,
      );
    }
    final plans = await ConversationMutationShadowBridge.instance
        .prepareSdkDeleteCommits(ownerUserId: owner, conversationIds: ids);
    final deleted = <String>[];
    for (final plan in plans) {
      final result = await ConversationLocalStore.instance
          .commitCoordinatorPlan(plan: plan);
      if (result.shouldNotifyUi) {
        deleted.addAll(result.deletedConversationIds);
      }
    }
    return deleted;
  }

  Future<C2cHistoryBackfillStats> _runC2cHistoryBackfill({
    required String reason,
  }) async {
    final owner = _ownerUserId();
    if (owner.isEmpty) {
      return const C2cHistoryBackfillStats();
    }
    final localC2c = await ConversationLocalStore.instance.countByConvType(
      convType: 1,
      ownerUserId: owner,
    );
    final floor = ConversationPerfFlags.c2cHistoryBackfillFriendScanBelow;

    // 已有壳：本登录先富化一次元数据（不替代好友扫）。
    if (localC2c > 0 && !_c2cMetadataEnrichDone) {
      final localRows = await ConversationLocalStore.instance.loadConvTypePage(
        convType: 1,
        offset: 0,
        limit: ConversationPerfFlags.c2cHistoryBackfillMaxPeers,
        ownerUserId: owner,
      );
      final enrichCandidates = <String>[
        for (final row in localRows)
          if (row.conversationID.trim().startsWith('c2c_'))
            row.conversationID.trim(),
      ];
      if (enrichCandidates.isNotEmpty) {
        await _admitC2cBackfillCandidates(
          owner: owner,
          reason: '$reason:enrich_existing',
          candidates: enrichCandidates,
        );
      }
      _c2cMetadataEnrichDone = true;
    }

    final officialConversationIds = PlatformOfficialAccountService
        .officialAccountIds
        .map((id) => 'c2c_${id.trim()}')
        .where((id) => id != 'c2c_')
        .toList(growable: false);
    final existingOfficialRows = officialConversationIds.isEmpty
        ? const <V2TimConversation>[]
        : await ConversationLocalStore.instance.conversationsByIds(
            officialConversationIds,
            ownerUserId: owner,
            caller: 'official_account_history_backfill_probe',
          );
    final existingOfficialIds =
        existingOfficialRows.map((row) => row.conversationID.trim()).toSet();
    final missingOfficialAccount = officialConversationIds.any(
      (id) => !existingOfficialIds.contains(id),
    );
    final needFriendScan = C2cHistoryBackfill.shouldRunFriendScan(
          localC2c: localC2c,
          floor: floor,
          friendScanDone: _c2cFriendScanDone,
        ) ||
        missingOfficialAccount;
    if (!needFriendScan) {
      ConversationPerfGateLog.log(
        'c2c_history_backfill',
        extras: <String, Object?>{
          'reason': reason,
          'skipped': _c2cFriendScanDone
              ? 'friend_scan_done'
              : 'friend_scan_not_needed',
          'c2c': localC2c,
          'floor': floor,
          'friendScan': false,
        },
      );
      return const C2cHistoryBackfillStats(skipped: 1);
    }

    final friendUserIds = await _collectFriendUserIdsForBackfill(owner);
    final pinned = ConversationPinSyncService.instance.pinnedConversationIds;
    final existingIds = <String>{};
    if (localC2c > 0) {
      final loadLimit =
          localC2c > ConversationPerfFlags.c2cHistoryBackfillMaxPeers
              ? localC2c
              : ConversationPerfFlags.c2cHistoryBackfillMaxPeers;
      final existingRows =
          await ConversationLocalStore.instance.loadConvTypePage(
        convType: 1,
        offset: 0,
        limit: loadLimit,
        ownerUserId: owner,
      );
      for (final row in existingRows) {
        final id = row.conversationID.trim();
        if (id.startsWith('c2c_')) {
          existingIds.add(id);
        }
      }
    }

    final candidates = C2cHistoryBackfill.selectCandidateConversationIds(
      // Official accounts are not ordinary friends and therefore are absent
      // from the friend scan. Add them to the same C2C history backfill lane
      // so their last message, preview and ordering are hydrated identically.
      friendUserIds: <String>[
        ...PlatformOfficialAccountService.officialAccountIds,
        ...friendUserIds,
      ],
      pinnedConversationIds: pinned,
      existingLocalIds: existingIds,
      maxPeers: ConversationPerfFlags.c2cHistoryBackfillMaxPeers,
      includeFriends: ConversationPerfFlags.c2cHistoryBackfillIncludeFriends,
      includePinned: ConversationPerfFlags.c2cHistoryBackfillIncludePinned,
    );

    if (candidates.isEmpty) {
      ConversationPerfGateLog.log(
        'c2c_history_backfill',
        extras: <String, Object?>{
          'reason': reason,
          'candidates': 0,
          'applied': 0,
          'friends': friendUserIds.length,
          'c2c': localC2c,
          'floor': floor,
          'friendScan': true,
          'existing': existingIds.length,
        },
      );
      // 好友尚未就绪：本登录只再排一次延迟补拉（不立刻标 done，以便 retry）。
      if (!_c2cHistoryBackfillScheduled && friendUserIds.isEmpty) {
        _c2cHistoryBackfillScheduled = true;
        Future<void>.delayed(const Duration(seconds: 2), () {
          unawaited(
            maybeBackfillC2cFromHistoryPeers(reason: '$reason:friends_retry'),
          );
        });
        return const C2cHistoryBackfillStats();
      }
      _c2cFriendScanDone = true;
      return const C2cHistoryBackfillStats();
    }

    final stats = await _admitC2cBackfillCandidates(
      owner: owner,
      reason: '$reason:friend_scan',
      candidates: candidates,
    );
    _c2cFriendScanDone = true;
    ConversationPerfGateLog.log(
      'c2c_history_backfill',
      extras: <String, Object?>{
        'reason': '$reason:friend_scan_summary',
        'candidates': stats.candidates,
        'applied': stats.applied,
        'friends': friendUserIds.length,
        'c2c': localC2c,
        'floor': floor,
        'friendScan': true,
        'existing': existingIds.length,
        'sdkHit': stats.sdkHit,
        'historyHit': stats.historyHit,
      },
    );
    return stats;
  }

  Future<C2cHistoryBackfillStats> _admitC2cBackfillCandidates({
    required String owner,
    required String reason,
    required List<String> candidates,
  }) async {
    var sdkHit = 0;
    var historyHit = 0;
    var previewEnriched = 0;
    var skipped = 0;
    var droppedNoHistory = 0;
    final admit = <V2TimConversation>[];
    MessageService? messageService;
    try {
      messageService = serviceLocator<MessageService>();
    } catch (_) {
      messageService = null;
    }
    final resolvedMessageService = messageService;

    Future<List<V2TimMessage>> peekHistory(String peer) async {
      if (resolvedMessageService == null || peer.isEmpty) {
        return const [];
      }
      var history = await resolvedMessageService
          .getHistoryMessageList(
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
            userID: peer,
            count: 1,
          )
          .timeout(_c2cBackfillProbeTimeout);
      if (history.isEmpty) {
        history = await resolvedMessageService
            .getHistoryMessageList(
              getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
              userID: peer,
              count: 1,
            )
            .timeout(_c2cBackfillProbeTimeout);
      }
      return history;
    }

    for (final conversationId in candidates) {
      try {
        // The open chat owns its history cursor. Background preview probes must
        // never compete with the user's scroll/send lane for that conversation.
        if (ActiveChatRegistry.instance
            .matchesOpenConversation(conversationId)) {
          skipped++;
          continue;
        }
        final peer = ChatIdFormat.rawUserUid(
          conversationId.startsWith('c2c_')
              ? conversationId.substring(4)
              : conversationId,
        );
        final sdk = await _conversationService
            .getConversation(conversationID: conversationId)
            .timeout(_c2cBackfillProbeTimeout);
        V2TimConversation? row;
        if (C2cHistoryBackfill.shouldAdmitSdkConversation(sdk)) {
          sdkHit++;
          row = sdk;
          if (C2cHistoryBackfill.needsLastMessageEnrichment(row)) {
            final history = await peekHistory(peer);
            if (history.isNotEmpty) {
              row!.lastMessage = history.first;
              final ts = history.first.timestamp ?? 0;
              if (ts > 0) {
                row.orderkey = ts;
              }
              previewEnriched++;
              historyHit++;
            }
          }
        } else if (!ConversationPerfFlags.c2cHistoryBackfillRequireHistory) {
          row = C2cHistoryBackfill.buildShellFromHistory(
            conversationId: conversationId,
            lastMessage: null,
            hasHistory: false,
            requireHistory: false,
          );
          if (row != null) {
            historyHit++;
          }
        } else {
          final history = await peekHistory(peer);
          row = C2cHistoryBackfill.buildShellFromHistory(
            conversationId: conversationId,
            lastMessage: history.isEmpty ? null : history.first,
            hasHistory: history.isNotEmpty,
            requireHistory: true,
          );
          if (row != null) {
            historyHit++;
            previewEnriched++;
          }
        }
        if (row == null) {
          skipped++;
          continue;
        }
        final isPinned = ConversationPinSyncService.instance
            .isPinnedConversationId(conversationId);
        if (!C2cHistoryBackfill.shouldPersistBackfillRow(
          row: row,
          requireHistory:
              ConversationPerfFlags.c2cHistoryBackfillRequireHistory,
          isPinned: isPinned,
        )) {
          droppedNoHistory++;
          skipped++;
          continue;
        }
        C2cHistoryBackfill.applyPinnedFlag(row, isPinned: isPinned);
        admit.add(row);
      } catch (e) {
        skipped++;
        _log('c2c_history_backfill peer failed id=$conversationId err=$e');
      }
    }

    // 批量拉免打扰，避免 SDK 空壳 recvOpt=0 盖掉真实免打扰。
    if (admit.isNotEmpty) {
      final userIds = <String>[
        for (final c in admit)
          if ((c.userID?.trim().isNotEmpty ?? false)) c.userID!.trim(),
      ];
      final recvByUser = await _fetchC2cRecvOptsForBackfill(userIds);
      for (final c in admit) {
        final uid = c.userID?.trim() ?? '';
        if (uid.isEmpty) {
          continue;
        }
        C2cHistoryBackfill.applyRecvOpt(c, recvOpt: recvByUser[uid]);
      }
    }

    if (admit.isNotEmpty) {
      final merged = await _commitSdkConversationBatch(
        ownerUserId: owner,
        conversations: admit,
        source: ConversationMutationSource.sdkPage,
      );
      await _notifyUiAfterLocalWrite(upserted: merged);
      await ChatSessionController.instance.refreshTypeTotals();
    }

    final stats = C2cHistoryBackfillStats(
      candidates: candidates.length,
      sdkHit: sdkHit,
      historyHit: historyHit,
      applied: admit.length,
      skipped: skipped,
    );
    ConversationPerfGateLog.log(
      'c2c_history_backfill',
      extras: <String, Object?>{
        'reason': reason,
        'candidates': stats.candidates,
        'sdkHit': stats.sdkHit,
        'historyHit': stats.historyHit,
        'previewEnriched': previewEnriched,
        'droppedNoHistory': droppedNoHistory,
        'applied': stats.applied,
        'skipped': stats.skipped,
      },
    );
    _log(
      'c2c_history_backfill reason=$reason candidates=${stats.candidates} '
      'sdk=${stats.sdkHit} hist=${stats.historyHit} '
      'preview=$previewEnriched dropped=$droppedNoHistory '
      'applied=${stats.applied}',
    );
    return stats;
  }

  Future<Map<String, int?>> _fetchC2cRecvOptsForBackfill(
    List<String> userIds,
  ) async {
    final out = <String, int?>{};
    if (userIds.isEmpty) {
      return out;
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .getC2CReceiveMessageOpt(userIDList: userIds);
      if (res.code != 0) {
        _log('c2c_history_backfill recvOpt fail code=${res.code}');
        return out;
      }
      for (final info in res.data ?? const []) {
        final userId = info.userID?.trim() ?? '';
        if (userId.isEmpty) {
          continue;
        }
        out[userId] = info.c2CReceiveMessageOpt;
      }
    } catch (e) {
      _log('c2c_history_backfill recvOpt error: $e');
    }
    return out;
  }

  Future<List<String>> _collectFriendUserIdsForBackfill(String owner) async {
    final ids = <String>{};
    try {
      final records = await FriendLocalStore.instance.readAll(
        ownerUserId: owner,
      );
      for (final r in records) {
        final id = ChatIdFormat.rawUserUid(r.friendUserId);
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    } catch (_) {}
    try {
      final friends =
          serviceLocator<TUIFriendShipViewModel>().friendList ?? const [];
      for (final f in friends) {
        final id = ChatIdFormat.rawUserUid(f.userID);
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    } catch (_) {}
    return ids.toList(growable: false);
  }

  /// 通过好友后立刻在会话列表露出 C2C 行（不依赖 IM 已建会话 / 已发 tip）。
  Future<void> ensureC2cConversationVisible({
    required String userId,
    String? nickname,
    String? avatarUrl,
  }) async {
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) {
      return;
    }
    final convId = 'c2c_$id';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    V2TimConversation? conversation;
    try {
      conversation = await _conversationService.getConversation(
        conversationID: convId,
      );
    } catch (_) {}
    conversation ??= await ConversationLocalStore.instance.conversationById(
      convId,
    );

    final storeName = DisplayNameStore.instance.c2c(id)?.trim() ?? '';
    final showName = (nickname?.trim().isNotEmpty == true)
        ? nickname!.trim()
        : (storeName.isNotEmpty ? storeName : id);
    final face = avatarUrl?.trim() ?? '';

    if (conversation == null) {
      conversation = V2TimConversation(
        conversationID: convId,
        type: 1,
        userID: id,
        showName: showName,
        faceUrl: face.isEmpty ? null : face,
        unreadCount: 0,
        recvOpt: 0,
        orderkey: nowMs,
      );
    } else {
      if ((conversation.showName ?? '').trim().isEmpty) {
        conversation.showName = showName;
      }
      if ((conversation.faceUrl ?? '').trim().isEmpty && face.isNotEmpty) {
        conversation.faceUrl = face;
      }
      final existingActive = ConversationLocalStore.activeTimeMs(conversation);
      if (nowMs >= existingActive) {
        conversation.orderkey = nowMs;
      }
    }

    if (!_shouldPersistConversation(conversation)) {
      return;
    }

    final merged = await commitCreatedConversation(
      conversation,
      notifyUi: false,
    );
    final toShow =
        merged.isNotEmpty ? merged : <V2TimConversation>[conversation];
    final session = ChatSessionController.instance;
    await ChatSessionController.instance.applySdkProjectionPatch(
      reason: ConversationStoreProjectionReason.sdkProjectionRestore,
      upserted: toShow,
      forceAdmitIds: <String>{convId},
    );
    await ChatSessionController.instance.refreshTypeTotals();
    final inHead = session.conversations.any(
      (c) => MessageConversationId.sameConversation(c.conversationID, convId),
    );
    final inHydrate =
        ChatSessionController.instance.typeIndexOfConversationId(1, convId) !=
            null;
    if (!inHead || !inHydrate) {
      await ChatSessionController.instance.ensureTypeIndexHydrated(
        convType: 1,
        centerIndex: 0,
        forceReload: true,
      );
    }
  }

  Future<void> refreshConversationItem(
    String conversationID, {
    bool allowRecreate = false,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    final lookupOverride = debugGetConversationOverride;
    V2TimConversation? conversation;
    try {
      conversation = lookupOverride != null
          ? await lookupOverride(id)
          : await _conversationService.getConversation(
              conversationID: id,
            );
    } catch (_) {}
    if (conversation == null) {
      if (MessageConversationId.looksLikeC2cConversationId(id)) {
        final userId = ChatIdFormat.rawUserUid(id);
        if (userId.isNotEmpty) {
          await ensureC2cConversationVisible(userId: userId);
        }
      }
      return;
    }
    if (!_shouldPersistConversation(conversation)) {
      _stashPendingNonMemberGroupConversations([conversation]);
      return;
    }
    _pendingNonMemberGroupConversations.remove(id);
    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: <V2TimConversation>[conversation],
      source: ConversationMutationSource.sdkPage,
      allowRecreate: allowRecreate,
      onCommittedBatch: (result) => committedBatch = result,
    );
    await _notifyUiAfterLocalWrite(
      upserted: merged,
      committedBatch: committedBatch,
    );
  }

  /// 用户已经从列表成功打开会话：立即保留 UI 行，并排队落入本地库。
  ///
  /// 群：成员快照可能因缓存/分页暂时缺项；若只做 membership 过滤放行，虚拟列表
  /// 返回时从 SQLite 重建仍会丢行。
  /// 单聊：下滑到中间打开的冷会话往往只在 `_typeHydrate`、不在 `_conversations`；
  /// 返回后 snapshot/post-pop 不 forceAdmit 就会从视口消失。
  Future<void> retainOpenedGroupConversation(
    V2TimConversation conversation,
  ) async {
    final convId = conversation.conversationID.trim();
    if (convId.isEmpty) {
      return;
    }
    GroupMembershipSyncService.instance.noteActiveGroupConversation(
      conversation,
    );
    if (!_shouldPersistConversation(conversation)) {
      return;
    }

    // 先把写请求放入 coalesce 队列，再补 UI；这样即使用户立刻返回，
    // 返回水合门禁也能等到该写入完成。
    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: <V2TimConversation>[conversation],
      source: ConversationMutationSource.sdkPage,
      onCommittedBatch: (result) => committedBatch = result,
    );
    if (merged.isNotEmpty) {
      if (committedBatch != null) {
        await ChatSessionController.instance.applyCommittedProjection(
          ConversationUiSnapshotBatch<V2TimConversation>(
            upsertedSnapshots: merged,
            deletedCanonicalIds: const <String>[],
            structureChanged: committedBatch!.structureChanged,
            changedFieldMasks: committedBatch!.changedFieldMasks,
            commitGeneration: 0,
            unreadDeltas: committedBatch!.unreadDeltas.map(
              (delta) => ConversationUiUnreadDelta(
                conversationKey: delta.conversationKey,
                isGroup: delta.isGroup,
                oldNotifiable: delta.oldNotifiable,
                newNotifiable: delta.newNotifiable,
              ),
            ),
            unreadProjectionComplete: committedBatch!.unreadProjectionComplete,
          ),
          forceAdmitIds: <String>{convId},
        );
      } else {
        await ChatSessionController.instance.applySdkProjectionPatch(
          reason: ConversationStoreProjectionReason.sdkProjectionRestore,
          upserted: merged,
          forceAdmitIds: <String>{convId},
        );
      }
    }
    await ChatSessionController.instance.refreshTypeTotals();
  }

  /// 本人新入群后：拉 SDK 会话 + 冲刷挂起项 + 热窗 reload（对齐杀进程重开路径）。
  Future<void> onLocalGroupMembershipExpanded({String? groupId}) async {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isNotEmpty) {
      final convId = id.startsWith('group_') ? id : 'group_$id';
      await refreshConversationItem(convId, allowRecreate: true);
    }
    await flushPendingGroupConversationsAfterMembershipChange();
    _scheduleMembershipExpandHotWindowReload();
  }

  /// 成员库已更新：把此前因「非成员」挂起的群会话落库并上屏。
  Future<void> flushPendingGroupConversationsAfterMembershipChange() async {
    if (_pendingNonMemberGroupConversations.isEmpty) {
      return;
    }
    final pending = _pendingNonMemberGroupConversations.values.toList(
      growable: false,
    );
    final ready = <V2TimConversation>[];
    for (final conversation in pending) {
      final convId = conversation.conversationID.trim();
      if (convId.isEmpty) {
        continue;
      }
      if (_shouldPersistConversation(conversation)) {
        ready.add(conversation);
        _pendingNonMemberGroupConversations.remove(convId);
        continue;
      }
      // 再拉一次 SDK，避免挂起快照过旧。
      try {
        final latest = await _conversationService.getConversation(
          conversationID: convId,
        );
        if (latest != null && _shouldPersistConversation(latest)) {
          ready.add(latest);
          _pendingNonMemberGroupConversations.remove(convId);
        }
      } catch (e, st) {
        _log(
          'flushPendingGroupConversations refreshFailed id=$convId error=$e',
        );
        assert(() {
          debugPrint('flushPendingGroupConversations refresh failed: $e\n$st');
          return true;
        }());
      }
    }
    if (ready.isEmpty) {
      return;
    }
    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: ready,
      source: ConversationMutationSource.sdkPage,
      onCommittedBatch: (result) => committedBatch = result,
    );
    await _notifyUiAfterLocalWrite(
      upserted: merged,
      committedBatch: committedBatch,
    );
    _log(
      'flushPendingGroupConversations count=${ready.length} '
      'stillPending=${_pendingNonMemberGroupConversations.length}',
    );
  }

  void _stashPendingNonMemberGroupConversations(
    List<V2TimConversation> conversations,
  ) {
    for (final conversation in conversations) {
      if (!isGroupConversation(conversation)) {
        continue;
      }
      if (_shouldPersistConversation(conversation)) {
        continue;
      }
      final id = conversation.conversationID.trim();
      if (id.isEmpty) {
        continue;
      }
      _pendingNonMemberGroupConversations.remove(id);
      _pendingNonMemberGroupConversations[id] = conversation;
      while (_pendingNonMemberGroupConversations.length >
          _pendingNonMemberGroupCap) {
        _pendingNonMemberGroupConversations.remove(
          _pendingNonMemberGroupConversations.keys.first,
        );
      }
      _schedulePendingGroupMembershipRecovery(conversation);
    }
  }

  Future<void> _onRecvNewMessageForMembershipBridge(
    V2TimMessage message, {
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    final loginUser = identity?.ownerUserId ?? _ownerUserId();
    if (!GroupTipsMessageHelper.isSelfInvitedOrJoined(message, loginUser)) {
      return;
    }
    final groupId = ChatIdFormat.normalizeGroupId(
      message.groupID ?? message.groupTipsElem?.groupID,
    );
    if (groupId.isEmpty) {
      return;
    }
    final convId = groupId.startsWith('group_') ? groupId : 'group_$groupId';
    final pending = _pendingNonMemberGroupConversations[convId];
    await GroupMembershipSyncService.instance.admitGroupMembershipFromImHint(
      groupId: groupId,
      groupName: pending?.showName?.trim() ?? '',
      avatarUrl: pending?.faceUrl?.trim() ?? '',
      confirmedMembership: true,
    );
  }

  /// Advanced message callbacks are the earliest reliable source for an
  /// inbound message. Keep the conversation preview independent from the
  /// notification/banner listener: notification settings may be disabled,
  /// attached late, or need to be reattached after an IM reconnect.
  ///
  /// The conversation listener remains the authoritative SDK snapshot path;
  /// this patch only fills the gap where that snapshot is delayed or still
  /// contains the previous lastMessage.
  Future<void> _patchInboundConversationPreview(
    V2TimMessage message, {
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    if (message.isSelf == true || TypingStatusMessage.isTypingStatus(message)) {
      return;
    }
    final conversationID = MessageConversationId.fromMessage(message);
    if (conversationID == null || conversationID.trim().isEmpty) {
      return;
    }
    await patchConversationLastMessage(
      conversationID: conversationID,
      message: message,
      identity: identity,
    );
  }

  void _schedulePendingGroupMembershipRecovery(V2TimConversation conversation) {
    final groupId = resolveGroupIdFromConversation(
      conversationId: conversation.conversationID,
      groupId: conversation.groupID,
    );
    if (groupId.isEmpty) {
      return;
    }
    if (!_pendingGroupRecoveryScheduled.add(groupId)) {
      return;
    }
    unawaited(
      _runPendingGroupMembershipRecovery(
        groupId: groupId,
        groupName: conversation.showName?.trim() ?? '',
        avatarUrl: conversation.faceUrl?.trim() ?? '',
      ),
    );
  }

  Future<void> _runPendingGroupMembershipRecovery({
    required String groupId,
    required String groupName,
    required String avatarUrl,
  }) async {
    try {
      await GroupMembershipSyncService.instance.admitGroupMembershipFromImHint(
        groupId: groupId,
        groupName: groupName,
        avatarUrl: avatarUrl,
      );
    } finally {
      _pendingGroupRecoveryScheduled.remove(groupId);
    }
  }

  /// TCP `member_added` 未点名本人时：仅当该群已在挂起队列才触发入群恢复。
  Future<void> recoverPendingGroupMembershipIfNeeded({
    required String groupId,
  }) async {
    final id = ChatIdFormat.normalizeGroupId(groupId);
    if (id.isEmpty) {
      return;
    }
    final convId = id.startsWith('group_') ? id : 'group_$id';
    final pending = _pendingNonMemberGroupConversations[convId];
    if (pending == null) {
      return;
    }
    await GroupMembershipSyncService.instance.admitGroupMembershipFromImHint(
      groupId: id,
      groupName: pending.showName?.trim() ?? '',
      avatarUrl: pending.faceUrl?.trim() ?? '',
    );
  }

  void _scheduleMembershipExpandHotWindowReload() {
    _membershipExpandReloadTimer?.cancel();
    _membershipExpandReloadTimer = Timer(const Duration(milliseconds: 120), () {
      _membershipExpandReloadTimer = null;
      unawaited(restoreSdkProjection(immediate: true, forceFull: true));
    });
  }

  @visibleForTesting
  int get pendingNonMemberGroupConversationCount =>
      _pendingNonMemberGroupConversations.length;

  @visibleForTesting
  void stashPendingNonMemberGroupConversationsForTest(
    List<V2TimConversation> conversations,
  ) {
    _stashPendingNonMemberGroupConversations(conversations);
  }

  @visibleForTesting
  void clearPendingNonMemberGroupConversationsForTest() {
    _pendingNonMemberGroupConversations.clear();
    _pendingGroupRecoveryScheduled.clear();
  }

  /// IM 与后端归档清空成功后：从消息列表移出该会话（不留空壳）。
  Future<void> onConversationHistoryCleared({
    required String conversationID,
    V2TimConversation? snapshot,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    ChatHistoryRefreshBus.instance.requestRefresh(
      conversationId: id,
      reason: 'conversation_clear_history',
    );
    // 产品：清空 = 列表移出。force 清水位并删本地行，避免空壳回钉。
    await _persistDeleted([id], force: true);
    try {
      await _conversationService.deleteConversation(conversationID: id);
    } catch (_) {}
  }

  /// 聊天页删除消息后修正本地会话预览：被删的正是预览所指那条时，
  /// 回退到会话剩余的最新一条；一条不剩则按清空历史处理。
  /// SDK 删除最后一条消息不会更新会话 lastMessage、也不触发
  /// onConversationChanged，必须本地补偿（与撤回的
  /// markConversationLastMessageRevoked 对应）。
  Future<void> onConversationMessagesDeleted({
    required String conversationID,
    required List<String> deletedMsgIDs,
    V2TimMessage? fallbackLastMessage,
  }) async {
    final id = conversationID.trim();
    final targets = deletedMsgIDs
        .map((msgID) => msgID.trim())
        .where((msgID) => msgID.isNotEmpty)
        .toSet();
    if (id.isEmpty || targets.isEmpty) {
      return;
    }
    final optimisticApplied =
        ChatSessionController.instance.replaceLastMessageAfterDeleteLocally(
      conversationID: id,
      deletedMessageIds: targets,
      replacement: fallbackLastMessage,
    );
    if (kDebugMode) {
      debugPrint(
        '[ConversationDeletePreview] sync-start conv=$id '
        'deleted=${targets.join(',')} '
        'fallback=${fallbackLastMessage?.msgID ?? fallbackLastMessage?.id ?? '<empty>'} '
        'optimistic=$optimisticApplied',
      );
    }
    // 传入的是裸 userID/groupID；先解析成 store 里存的完整会话 id。
    var storedId = id;
    final matched = await ConversationLocalStore.instance.conversationById(id);
    if (matched != null) {
      storedId = matched.conversationID;
    }
    final updated = await ConversationLocalStore.instance
        .replaceConversationLastMessageAfterDelete(
      storedId,
      deletedMsgIDs: targets,
      replacement: fallbackLastMessage,
    );
    if (updated == null) {
      if (kDebugMode) {
        debugPrint(
          '[ConversationDeletePreview] store-miss conv=$storedId '
          'optimistic=$optimisticApplied',
        );
      }
      return;
    }
    if (updated.lastMessage == null) {
      ChatSessionController.instance.clearLastMessageLocally(storedId);
    }
    await ChatSessionController.instance.applySdkProjectionPatch(
      reason: ConversationStoreProjectionReason.sdkProjectionRestore,
      upserted: [updated],
      changedFieldMasks: <String, Set<ConversationMutationField>>{
        storedId: <ConversationMutationField>{
          ConversationMutationField.lastMessage,
        },
      },
    );
    if (kDebugMode) {
      debugPrint(
        '[ConversationDeletePreview] projected conv=$storedId '
        'last=${updated.lastMessage?.msgID ?? updated.lastMessage?.id ?? '<empty>'}',
      );
    }
  }

  /// 对方已读回执：若预览即为对应己方消息，写回 lastMessage.isPeerRead。
  Future<void> markLastMessagePeerRead({
    required String conversationID,
    String? msgID,
    int? peerReadAtSec,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    final existing = await ConversationLocalStore.instance.conversationById(id);
    if (existing == null) {
      return;
    }
    final last = existing.lastMessage;
    if (last == null) {
      return;
    }
    if (last.isSelf != true) {
      return;
    }
    if (last.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      return;
    }
    if (last.isPeerRead == true) {
      return;
    }
    final targetMsgId = msgID?.trim() ?? '';
    final lastMsgId = last.msgID?.trim() ?? '';
    var matched = false;
    if (targetMsgId.isNotEmpty &&
        lastMsgId.isNotEmpty &&
        targetMsgId == lastMsgId) {
      matched = true;
    } else if ((peerReadAtSec ?? 0) > 0) {
      final ts = last.timestamp ?? 0;
      if (ts > 0 && ts <= peerReadAtSec!) {
        matched = true;
      }
    }
    if (!matched) {
      return;
    }
    last.isPeerRead = true;
    ConversationSdkCommittedBatch? committedBatch;
    final merged = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: <V2TimConversation>[existing],
      source: ConversationMutationSource.sdkRealtime,
      onCommittedBatch: (result) => committedBatch = result,
    );
    await _notifyUiAfterLocalWrite(
      upserted: merged,
      committedBatch: committedBatch,
    );
  }

  /// 用当前消息乐观更新本地会话预览，避免横幅先于列表刷新。
  Future<void> patchConversationLastMessage({
    required String conversationID,
    required V2TimMessage message,
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return;
    }
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    if (_pageSyncInFlight) {
      if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
        return;
      }
      _pendingPatches[id] = message;
      _patchesQueuedDuringSync++;
      _pendingPatchesFirstQueuedAt ??= DateTime.now();
      _armPendingPatchesForceFlush();
      if (_patchesQueuedDuringSync == 1 || _patchesQueuedDuringSync % 50 == 0) {
        _log(
          'patch queued during sync count=$_patchesQueuedDuringSync last=$id',
        );
      }
      return;
    }
    await _applyPatchConversationLastMessage(
      conversationID: id,
      message: message,
      identity: identity,
    );
  }

  void _armPendingPatchesForceFlush() {
    if (_pendingPatchesForceTimer?.isActive == true) {
      return;
    }
    final maxWait = ConversationPerfFlags.pendingPreviewPatchMaxWait;
    if (maxWait <= Duration.zero) {
      return;
    }
    final firstAt = _pendingPatchesFirstQueuedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(firstAt);
    final remain = maxWait - elapsed;
    _pendingPatchesForceTimer = Timer(
      remain.isNegative ? Duration.zero : remain,
      () {
        _pendingPatchesForceTimer = null;
        unawaited(_forceFlushPendingPatches(reason: 'pending_patch_max_wait'));
      },
    );
  }

  Future<void> _forceFlushPendingPatches({required String reason}) async {
    if (_pendingPatches.isEmpty) {
      _pendingPatchesFirstQueuedAt = null;
      _patchesQueuedDuringSync = 0;
      return;
    }
    ConversationPerfGateLog.log(
      'pending_preview_patch_force_flush',
      extras: <String, Object?>{
        'reason': reason,
        'count': _pendingPatches.length,
        'syncInFlight': _pageSyncInFlight ? 1 : 0,
      },
    );
    await _replayPendingPatches();
  }

  Future<void> _replayPendingPatches() async {
    _pendingPatchesForceTimer?.cancel();
    _pendingPatchesForceTimer = null;
    _pendingPatchesFirstQueuedAt = null;
    if (_pendingPatches.isEmpty) {
      _patchesQueuedDuringSync = 0;
      return;
    }
    final patches = Map<String, V2TimMessage>.from(_pendingPatches);
    _pendingPatches.clear();
    final queued = _patchesQueuedDuringSync;
    _patchesQueuedDuringSync = 0;
    if (queued > 0) {
      _log(
        'replay pending patches unique=${patches.length} queuedLogs=$queued',
      );
    }
    final mergedAll = <V2TimConversation>[];
    for (final entry in patches.entries) {
      final merged = await _applyPatchConversationLastMessage(
        conversationID: entry.key,
        message: entry.value,
        notifyUi: false,
      );
      if (merged != null && merged.isNotEmpty) {
        mergedAll.addAll(merged);
      }
    }
    if (mergedAll.isNotEmpty) {
      await _notifyUiAfterLocalWrite(upserted: mergedAll, immediate: true);
    }
  }

  Future<List<V2TimConversation>?> _applyPatchConversationLastMessage({
    required String conversationID,
    required V2TimMessage message,
    bool notifyUi = true,
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return null;
    }
    final id = conversationID.trim();
    if (id.isEmpty) {
      return null;
    }
    // 禁止跨类型把单聊正文写进群预览（或反过来）。
    final messageConvId = MessageConversationId.fromMessage(message);
    if (messageConvId != null && messageConvId.isNotEmpty) {
      final targetC2c = MessageConversationId.looksLikeC2cConversationId(id);
      final targetGroup =
          MessageConversationId.looksLikeGroupConversationId(id) ||
              ChatIdFormat.isIMGroupOrCommunityId(id) ||
              id.toUpperCase().contains('TGS#');
      final msgC2c = MessageConversationId.looksLikeC2cConversationId(
        messageConvId,
      );
      final msgGroup = MessageConversationId.looksLikeGroupConversationId(
        messageConvId,
      );
      if ((targetGroup && msgC2c) || (targetC2c && msgGroup)) {
        _log(
          'skip lastMessage patch type mismatch target=$id '
          'messageConv=$messageConvId msgId=${message.msgID ?? ''}',
        );
        OutgoingVisibleProbe.log(
          'lastmsg_skip_type_mismatch',
          conversationID: id,
          message: message,
          extras: <String, Object?>{'messageConv': messageConvId},
        );
        return null;
      }
    }
    // 社群 ID 多形态：`group_@TGS#_mc…` / 裸 ID；逐个试 getConversation。
    final idCandidates = <String>{id};
    if (id.toLowerCase().startsWith('group_')) {
      final bare = id.substring(6);
      idCandidates.add(bare);
      final normalized = ChatIdFormat.normalizeGroupId(bare);
      if (normalized.isNotEmpty) {
        idCandidates.add(normalized);
        idCandidates.add('group_$normalized');
      }
    } else if (ChatIdFormat.isIMGroupOrCommunityId(id) ||
        id.toUpperCase().contains('TGS#')) {
      final normalized = ChatIdFormat.normalizeGroupId(id);
      if (normalized.isNotEmpty) {
        idCandidates.add(normalized);
        idCandidates.add('group_$normalized');
      }
    }
    V2TimConversation? conversation;
    for (final candidate in idCandidates) {
      final lookupOverride = debugGetConversationOverride;
      conversation = lookupOverride != null
          ? await lookupOverride(candidate)
          : await _conversationService.getConversation(
              conversationID: candidate,
            );
      if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
        return null;
      }
      if (conversation != null) {
        break;
      }
    }
    final msgId = message.msgID?.trim() ?? '';
    if (conversation == null) {
      final isGroup = id.toLowerCase().startsWith('group_') ||
          ChatIdFormat.isIMGroupOrCommunityId(id) ||
          id.toUpperCase().contains('TGS#');
      final groupId = isGroup
          ? ChatIdFormat.normalizeGroupId(
              id.toLowerCase().startsWith('group_') ? id.substring(6) : id,
            )
          : null;
      final convId = isGroup
          ? (groupId != null && groupId.isNotEmpty ? 'group_$groupId' : id)
          : (id.startsWith('c2c_') ? id : 'c2c_$id');
      // 项 6-2：创建空会话时 orderkey 也统一毫秒。
      final createdTs = message.timestamp ?? 0;
      final createdOrderkey = createdTs <= 0
          ? 0
          : (createdTs >= 1000000000000 ? createdTs : createdTs * 1000);
      conversation = V2TimConversation(
        conversationID: convId,
        type: isGroup ? 2 : 1,
        userID: isGroup ? null : id.replaceFirst('c2c_', ''),
        groupID: groupId,
        lastMessage: message,
        orderkey: createdOrderkey,
      );
    }
    if (!_shouldPersistConversation(conversation)) {
      OutgoingVisibleProbe.log(
        'lastmsg_persist_reject',
        conversationID: id,
        message: message,
        extras: <String, Object?>{'convId': conversation.conversationID},
      );
      // 入群竞态：先挂起并触发成员恢复，勿立刻 prune（否则永远等杀进程）。
      _stashPendingNonMemberGroupConversations([conversation]);
      // 072 phase-6 allowlist: membership is not authoritative yet, so this
      // row cannot be committed. Keep only a transient pending preview until
      // membership recovery admits it through the Coordinator.
      ChatSessionController.instance.applyLastMessageLocally(
        conversationID: conversation.conversationID,
        message: message,
      );
      return null;
    }
    if (conversation.lastMessage?.msgID?.trim() == msgId && msgId.isNotEmpty) {
      final shouldUpgrade =
          GroupTipsMessageHelper.shouldUpgradeSameIdLastMessage(
        existing: conversation.lastMessage,
        incoming: message,
      );
      if (shouldUpgrade) {
        conversation.lastMessage = message;
      }
      final unreadBeforePatch = conversation.unreadCount;
      _applySdkUnreadForPatch(conversation);
      // SDKs can replay the same changed-conversation callback while a chat
      // page is open.  If the payload did not advance the last message and
      // no unread transition was produced, do not send the patch through the
      // persistence/projection pipeline again.
      if (!shouldUpgrade &&
          unreadBeforePatch == conversation.unreadCount &&
          _sameLastMessageSnapshot(conversation.lastMessage, message)) {
        OutgoingVisibleProbe.log(
          'lastmsg_patch_duplicate_skip',
          conversationID: id,
          message: message,
        );
        return null;
      }
      OutgoingVisibleProbe.log(
        'lastmsg_patch_same_id',
        conversationID: id,
        message: message,
      );
      return _persistPatchedConversation(
        conversation,
        message: message,
        notifyUi: notifyUi,
        identity: identity,
      );
    }
    final last = conversation.lastMessage;
    final lastId = last?.msgID?.trim() ?? '';
    final incomingTs = message.timestamp ?? 0;
    final currentTs = last?.timestamp ?? 0;
    if (incomingTs > 0 &&
        currentTs > 0 &&
        incomingTs < currentTs &&
        msgId.isNotEmpty &&
        lastId.isNotEmpty &&
        msgId != lastId) {
      OutgoingVisibleProbe.log(
        'lastmsg_skip_ts_rollback',
        conversationID: id,
        message: message,
        extras: <String, Object?>{
          'incomingTs': incomingTs,
          'currentTs': currentTs,
          'lastMsgID': lastId,
        },
      );
      return null;
    }
    conversation.lastMessage = message;
    if (incomingTs > 0) {
      // 项 6-1：orderkey 统一为毫秒，与 activeTimeMs() 对齐，避免 tie-break 抖动。
      // SDK 给的 message.timestamp 单位不确定（秒或毫秒），
      // 通过阈值 1e12 启发式判断并补齐到毫秒。
      conversation.orderkey =
          incomingTs >= 1000000000000 ? incomingTs : incomingTs * 1000;
    }
    _applySdkUnreadForPatch(conversation);
    OutgoingVisibleProbe.log(
      'lastmsg_patch_ok',
      conversationID: id,
      message: message,
      extras: <String, Object?>{'notifyUi': notifyUi},
    );
    return _persistPatchedConversation(
      conversation,
      message: message,
      notifyUi: notifyUi,
      identity: identity,
    );
  }

  bool _sameLastMessageSnapshot(
    V2TimMessage? existing,
    V2TimMessage incoming,
  ) {
    if (existing == null) {
      return false;
    }
    final existingId = existing.msgID?.trim() ?? '';
    final incomingId = incoming.msgID?.trim() ?? '';
    if (existingId.isEmpty || incomingId.isEmpty || existingId != incomingId) {
      return false;
    }
    return existing.timestamp == incoming.timestamp &&
        existing.status == incoming.status &&
        existing.isSelf == incoming.isSelf;
  }

  /// 发送预览 patch：并入 persist dedup，与 SDK changed 同窗合并，避免双写 SQLite。
  Future<List<V2TimConversation>?> _persistPatchedConversation(
    V2TimConversation conversation, {
    required V2TimMessage message,
    required bool notifyUi,
    SessionIdentity? identity,
  }) async {
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) {
      return null;
    }
    if (!notifyUi) {
      // sync replay / 批量路径：直接落库。
      return _commitSdkConversationBatch(
        ownerUserId: identity?.ownerUserId ?? _ownerUserId(),
        conversations: <V2TimConversation>[conversation],
        source: ConversationMutationSource.sdkRealtime,
      );
    }
    final shouldBumpUnread = ConversationUnreadGuard.shouldOptimisticBumpUnread(
      conversationId: conversation.conversationID,
      message: message,
    );
    // 072 phase-6 allowlist: outgoing preview is a transient pending state.
    // Apply the row immediately, but defer unread aggregation to the durable
    // SDK commit below. The old ordering let both paths add +1.
    ChatSessionController.instance.applyLastMessageLocally(
      conversationID: conversation.conversationID,
      message: message,
      bumpUnread: shouldBumpUnread,
      updateUnreadAggregate: false,
    );
    final convId = conversation.conversationID.trim();
    V2TimConversation? projected;
    for (final row in ChatSessionController.instance.conversations) {
      if (MessageConversationId.sameConversation(row.conversationID, convId)) {
        projected = row;
        break;
      }
    }
    // SDK-primary mode can keep the visible row only in ConversationTabStore
    // while the session window is empty. Reuse that same projected
    // row so the durable commit carries the already-applied single unread
    // increment instead of adding another one (or dropping the first one).
    if (projected == null) {
      for (final type in const [1, 2]) {
        for (final row in ConversationTabStore.instance.itemsForType(type)) {
          if (MessageConversationId.sameConversation(
            row.conversationID,
            convId,
          )) {
            projected = row;
            break;
          }
        }
        if (projected != null) {
          break;
        }
      }
    }
    final inList = projected != null;
    if (projected != null && shouldBumpUnread) {
      // The message callback can carry the new preview with the previous SDK
      // unread count. Carry the single optimistic increment into the durable
      // snapshot, but only when this preview actually advances the UI row;
      // duplicate callbacks must not add another unread item.
      final optimisticUnread = projected.unreadCount ?? 0;
      conversation.unreadCount = math.max(
        conversation.unreadCount ?? 0,
        optimisticUnread,
      );
    }
    _enqueuePersistChanged(
      [conversation],
      reason: 'send_patch',
      prepare: true,
      source: ConversationMutationSource.sdkRealtime,
      allowRecreate: false,
      identity: identity,
    );
    ConversationPerfGateLog.log(
      'persist_dedup_merge_send_patch',
      extras: <String, Object?>{
        'conversationID': conversation.conversationID,
        'buffer': _pendingPersistEvents.length,
        'busy': _isUiBusyForPersist,
        'optimisticUnread': shouldBumpUnread,
        'aggregateDeferred': true,
      },
    );
    if (!inList && convId.isNotEmpty) {
      if (shouldBumpUnread) {
        conversation.unreadCount = (conversation.unreadCount ?? 0) + 1;
      }
      await ChatSessionController.instance.applySdkProjectionPatch(
        reason: ConversationStoreProjectionReason.sdkProjectionRestore,
        upserted: <V2TimConversation>[conversation],
        forceAdmitIds: <String>{convId},
      );
    }
    return [conversation];
  }

  /// 未读以 SDK 和已确认的消息已读锚点为准，页面可见不代表新气泡已读。
  void _applySdkUnreadForPatch(V2TimConversation conversation) {
    ConversationLocalStore.instance.resolveSdkUnreadAgainstReadBarrier(
      conversation,
    );
  }

  Future<void> markConversationReadLocally(
    String conversationID, {
    bool forceImmediateUi = false,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return;
    }
    // A user-initiated read is authoritative and must immediately release
    // any short-lived optimistic unread protection for this conversation.
    ConversationUnreadGuard.clearOptimisticUnread(id);
    if (!forceImmediateUi) {
      final lastAt = _lastMarkReadAt;
      if (_lastMarkReadId == id &&
          lastAt != null &&
          DateTime.now().difference(lastAt) < _markReadDebounce) {
        return;
      }
    }
    ConversationUnreadTrace.log(
      'mark_read_locally_start',
      conversationID: id,
      extras: <String, Object?>{'forceImmediateUi': forceImmediateUi},
    );
    final override = markReadStoreOverride;
    final immediate = forceImmediateUi || shouldMarkReadReloadImmediately();
    if (override != null) {
      await override(conversationID);
      await _notifyUiAfterLocalWrite(fullReload: true, immediate: immediate);
      _lastMarkReadId = id;
      _lastMarkReadAt = DateTime.now();
      ConversationUnreadTrace.log(
        'mark_read_locally_done',
        conversationID: id,
        extras: <String, Object?>{'via': 'override'},
      );
      return;
    }
    final owner = _ownerUserId();
    final readBarrier = ConversationLocalStore.instance.recordReadClearedAnchor(
      id,
      ownerUserId: owner,
    );
    await _restoreDurableMutationState(ownerUserId: owner, conversationId: id);
    final plan = await ConversationMutationShadowBridge.instance
        .prepareLocalIntentCommit(
      ownerUserId: owner,
      conversationId: id,
      fieldPatch: const <ConversationMutationField, Object?>{
        ConversationMutationField.unread: 0,
      },
      // Keep the local read barrier in the same version domain as SDK
      // message patches. A local sequence number is much smaller than a
      // message timestamp/orderkey and would otherwise lose to an old SDK
      // snapshot.
      sourceVersion: readBarrier?.version ?? _readBarrierVersionFor(id),
    );
    final commit = plan == null
        ? null
        : await ConversationLocalStore.instance.commitCoordinatorPlan(
            plan: plan,
          );
    final updated = commit == null || commit.upsertedSnapshots.isEmpty
        ? null
        : commit.upsertedSnapshots.first;
    if (updated == null) {
      if (commit != null) {
        _lastMarkReadId = id;
        _lastMarkReadAt = DateTime.now();
      }
      ConversationUnreadTrace.log(
        'mark_read_locally_done',
        conversationID: id,
        extras: <String, Object?>{'via': 'noop'},
      );
      return;
    }
    await _notifyUiAfterLocalWrite(updated: updated, immediate: immediate);
    _lastMarkReadId = id;
    _lastMarkReadAt = DateTime.now();
    ConversationUnreadTrace.log(
      'mark_read_locally_done',
      conversationID: id,
      unreadAfter: updated.unreadCount ?? 0,
    );
  }

  int? _readBarrierVersionFor(String conversationID) {
    for (final conversation in ChatSessionController.instance.conversations) {
      if (!MessageConversationId.sameConversation(
        conversation.conversationID,
        conversationID,
      )) {
        continue;
      }
      final timestamp = conversation.lastMessage?.timestamp ?? 0;
      // Match ConversationReadBarrier's version domain. `orderkey` determines
      // list position only and must not make an old snapshot look post-read.
      return timestamp > 0 ? timestamp + 1 : null;
    }
    return null;
  }

  Future<MarkReadBatchResult> markConversationsReadLocallyBatch(
    Iterable<String> conversationIds,
  ) async {
    final owner = _ownerUserId();
    final plans = <ConversationDatabaseCommitPlan<V2TimConversation>>[];
    for (final rawId in conversationIds) {
      final id = rawId.trim();
      if (id.isEmpty) {
        continue;
      }
      await _restoreDurableMutationState(
        ownerUserId: owner,
        conversationId: id,
      );
      final readBarrier = ConversationLocalStore.instance
          .recordReadClearedAnchor(id, ownerUserId: owner);
      final plan = await ConversationMutationShadowBridge.instance
          .prepareLocalIntentCommit(
        ownerUserId: owner,
        conversationId: id,
        fieldPatch: const <ConversationMutationField, Object?>{
          ConversationMutationField.unread: 0,
        },
        sourceVersion: readBarrier?.version ?? _readBarrierVersionFor(id),
      );
      if (plan != null) {
        plans.add(plan);
      }
    }
    return ConversationLocalStore.instance.commitCoordinatorMarkReadPlans(
      plans: plans,
    );
  }

  Future<void> onViewModelPageLoaded({
    required List<V2TimConversation?> conversations,
    required bool isRefresh,
    required String nextSeq,
    required bool haveMoreData,
    required bool hasLoadedOnce,
  }) async {
    if (ImSnapshotBootstrapService.instance.shouldSuppressViewModelPersist) {
      _log(
        'view_model_page skipped (snapshot/login bootstrap gate) '
        'count=${conversations.length}',
      );
      return;
    }
    final typed = conversations.whereType<V2TimConversation>().toList();
    if (typed.isEmpty && !isRefresh) {
      return;
    }
    if (typed.isNotEmpty) {
      final persistable = _filterPersistableConversations(typed);
      if (persistable.isNotEmpty) {
        {
          await _commitSdkConversationBatch(
            ownerUserId: _ownerUserId(),
            conversations: persistable,
            source: ConversationMutationSource.sdkPage,
          );
          ConversationPerfGateLog.log(
            'mirror_skip_ui',
            extras: <String, Object?>{
              'via': 'view_model_page',
              'count': persistable.length,
            },
          );
        }
      }
      unawaited(_purgeRejectedGroupConversations(typed));
    }
    // UIKit 混流分页不得冒充「本地 typed 已同步」：hasSyncedOnce / 游标
    // 只由 syncFromSdkByType / bootstrapTypedFirstScreen 推进。
  }

  Future<void> onViewModelConversationsChanged(
    List<V2TimConversation> conversations,
  ) async {
    // Compatibility boundary only. UIKit mirrors the direct SDK realtime
    // listener and is deliberately not a persistence writer (Plan 093).
    ConversationPerfGateLog.log(
      'view_model_changed_diagnostic_only',
      extras: <String, Object?>{'count': conversations.length},
    );
  }

  static String _viewModelFingerprint(V2TimConversation conversation) {
    final last = conversation.lastMessage;
    return <Object?>[
      conversation.conversationID,
      conversation.type,
      conversation.userID,
      conversation.groupID,
      conversation.showName,
      conversation.faceUrl,
      conversation.unreadCount,
      conversation.recvOpt,
      conversation.groupType,
      conversation.customData,
      conversation.isPinned,
      conversation.orderkey,
      conversation.draftText,
      conversation.draftTimestamp,
      last?.msgID,
      last?.timestamp,
      last?.elemType,
      last?.status,
      last?.isPeerRead == true,
    ].join('\u001f');
  }

  static String _persistFingerprintKey(
    String canonicalConversationId,
    ConversationMutationSource source,
  ) =>
      '$canonicalConversationId\u001f${source.name}';

  void _prepareConversationForPersist(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    final unreadBefore = conversation.unreadCount ?? 0;
    var uiUnread = unreadBefore;
    for (final item in ChatSessionController.instance.conversations) {
      if (MessageConversationId.sameConversation(item.conversationID, id)) {
        uiUnread = item.unreadCount ?? 0;
        break;
      }
    }
    final unreadAfter = ConversationUnreadGuard.resolveForPersist(
      conversation: conversation,
      uiUnread: uiUnread,
      suppressStaleForRecentlyLeft: shouldSuppressStaleUnread(id),
    );
    if (unreadBefore != unreadAfter) {
      ConversationUnreadTrace.log(
        'persist_prepare',
        conversationID: id,
        unreadBefore: unreadBefore,
        unreadAfter: unreadAfter,
        extras: <String, Object?>{
          'uiUnread': uiUnread,
          'postPop': isInPostPopCoalesceWindow,
          'recentlyLeft': _recentlyLeftConversationId,
          'suppressedStale':
              shouldSuppressStaleUnread(id) && unreadAfter < unreadBefore,
        },
      );
    }
  }

  Future<void> onViewModelConversationsDeleted(
    List<String> ids, {
    bool force = false,
    bool immediate = false,
  }) async {
    await _persistDeleted(ids, force: force, immediate: immediate);
  }

  @visibleForTesting
  Future<void> persistChangedForTest(
    List<V2TimConversation> conversations, {
    String reason = 'test',
    ConversationMutationSource source = ConversationMutationSource.sdkRealtime,
    bool allowRecreate = false,
  }) async {
    enqueuePersistChangedForTest(
      conversations,
      reason: reason,
      source: source,
      allowRecreate: allowRecreate,
    );
    _persistDedupTimer?.cancel();
    _persistDedupTimer = null;
    await _flushPersistEventQueue(reason: reason);
  }

  @visibleForTesting
  Future<void> flushPersistChangedForTest({String reason = 'test'}) async {
    _persistDedupTimer?.cancel();
    _persistDedupTimer = null;
    await _flushPersistEventQueue(reason: reason);
  }

  @visibleForTesting
  Future<void> persistDeletedForTest(
    List<String> conversationIds, {
    bool force = false,
  }) async {
    await _persistDeleted(conversationIds, force: force);
  }

  @visibleForTesting
  void enqueuePersistChangedForTest(
    List<V2TimConversation> conversations, {
    String reason = 'changed',
    ConversationMutationSource source = ConversationMutationSource.sdkRealtime,
    bool allowRecreate = false,
  }) {
    _enqueuePersistChanged(
      conversations,
      reason: reason,
      prepare: true,
      source: source,
      allowRecreate: allowRecreate,
    );
  }

  void _enqueuePersistChanged(
    List<V2TimConversation> conversations, {
    required String reason,
    required bool prepare,
    required ConversationMutationSource source,
    required bool allowRecreate,
    SessionIdentity? identity,
  }) {
    if (conversations.isEmpty) {
      return;
    }
    if (identity != null && !_isCurrentRealtimeIdentity(identity)) return;
    final owner = identity?.ownerUserId ?? _ownerUserId();
    if (owner.isEmpty) {
      return;
    }
    if (_pendingPersistOwner != owner) {
      _pendingPersistEvents.clear();
      _pendingPersistOwner = owner;
      _pendingPersistOwnerGeneration++;
    }
    final ownerGeneration = _pendingPersistOwnerGeneration;
    for (final conversation in conversations) {
      final id = conversation.conversationID.trim();
      if (id.isEmpty) {
        continue;
      }
      if (prepare) {
        _prepareConversationForPersist(conversation);
      }
      final type = conversation.type == ConversationType.V2TIM_GROUP
          ? ConversationMutationConversationType.group
          : ConversationMutationConversationType.c2c;
      final canonical = canonicalizeConversationMutationId(id, type);
      if (canonical.isEmpty) {
        continue;
      }
      final fingerprint = _viewModelFingerprint(conversation);
      final fingerprintKey = _persistFingerprintKey(canonical, source);
      final duplicate = _pendingPersistEvents.any(
            (event) =>
                event.ownerGeneration == ownerGeneration &&
                event.canonicalConversationId == canonical &&
                event.source == source &&
                event.fingerprint == fingerprint,
          ) ||
          _persistInFlightFingerprints[fingerprintKey] == fingerprint ||
          _viewModelPersistFingerprints[fingerprintKey] == fingerprint;
      if (duplicate) {
        continue;
      }
      final sequence = ++_persistCommitSequence;
      _latestPersistSequenceById[canonical] = sequence;
      _pendingPersistEvents.add(
        _PendingConversationEvent(
          ownerUserId: owner,
          ownerGeneration: ownerGeneration,
          canonicalConversationId: canonical,
          sequence: sequence,
          source: source,
          allowRecreate: allowRecreate,
          reason: reason,
          snapshot: conversation,
          fingerprint: fingerprint,
          identity: identity,
        ),
      );
      final last = conversation.lastMessage;
      ConversationPerfGateLog.traceConversationProjection(
        stage: 'enqueue',
        conversationId: id,
        messageId: last?.msgID ?? last?.id ?? '',
        timestamp: last?.timestamp ?? 0,
        orderkey: conversation.orderkey ?? 0,
        source: source.name,
        sequence: sequence,
        decision: 'queued',
      );
    }
    if (_pendingPersistEvents.isEmpty) {
      return;
    }
    _persistDedupTimer?.cancel();
    if (_pendingPersistEvents.length >= _pendingPersistEventCap) {
      unawaited(_flushPersistEventQueue(reason: 'queue_cap'));
      return;
    }
    _persistDedupTimer = Timer(_persistDedupDelayForReason(reason), () {
      unawaited(_flushPersistEventQueue(reason: reason));
    });
  }

  bool _shouldPersistConversation(V2TimConversation conversation) {
    return GroupMembershipSyncService.instance.shouldShowConversation(
      conversation,
    );
  }

  List<V2TimConversation> _filterPersistableConversations(
    List<V2TimConversation> conversations,
  ) {
    return conversations
        .where(_shouldPersistConversation)
        .toList(growable: false);
  }

  Future<List<V2TimConversation>> _commitSdkConversationBatch({
    required String ownerUserId,
    required List<V2TimConversation> conversations,
    required ConversationMutationSource source,
    bool allowRecreate = false,
    void Function(ConversationSdkCommittedBatch result)? onCommittedBatch,
  }) async {
    if (conversations.isEmpty) {
      return const <V2TimConversation>[];
    }
    final sourceVersionFloors = <String, int>{};
    for (final conversation in conversations) {
      final floor =
          ConversationLocalStore.instance.resolveSdkUnreadAgainstReadBarrier(
        conversation,
        ownerUserId: ownerUserId,
      );
      if (floor > 0) {
        sourceVersionFloors[conversation.conversationID] = floor;
      }
    }
    final bridge = ConversationMutationShadowBridge.instance;
    final durableById =
        await ConversationLocalStore.instance.coordinatorDurableStates(
      ownerUserId: ownerUserId,
      conversationIds: conversations.map(
        (conversation) => conversation.conversationID,
      ),
    );
    for (final conversation in conversations) {
      final durable = durableById[conversation.conversationID] ??
          const ConversationCoordinatorDurableState(
            generation: 0,
            tombstoned: false,
          );
      bridge.restoreDurableConversationState(
        ownerUserId: ownerUserId,
        conversationId: conversation.conversationID,
        generation: durable.generation,
        tombstoned: durable.tombstoned,
      );
    }
    // Test overrides and the runtime kill switch intentionally retain the
    // complete legacy path. Production authoritative mode must not admit and
    // then write the same rows again through upsertBatch.
    if (upsertBatchOverride != null) {
      return upsertBatchOverride!(conversations);
    }
    if (!ConversationMutationShadowBridge.authoritativeSdkCommitEnabled) {
      // 072 rollback allowlist: retain one whole-path rollback, never a
      // production dual-write beside Coordinator commits.
      final admitted = await bridge.admitSdkConversationsForCommit(
        ownerUserId: ownerUserId,
        conversations: conversations,
        source: source,
        allowRecreate: allowRecreate,
      );
      if (admitted.isEmpty) {
        return const <V2TimConversation>[];
      }
      return ConversationLocalStore.instance.upsertBatch(
        conversations: admitted,
        ownerUserId: ownerUserId,
      );
    }

    final candidates = await bridge.prepareSdkConversationCommits(
      ownerUserId: ownerUserId,
      conversations: conversations,
      source: source,
      allowRecreate: allowRecreate,
      sourceVersionFloorByConversationId: sourceVersionFloors,
    );
    final result = await ConversationLocalStore.instance
        .commitCoordinatorSdkUpsertPlansBatchResult(
      plans:
          candidates.map((candidate) => candidate.plan).toList(growable: false),
    );
    onCommittedBatch?.call(result);
    return result.upserted;
  }

  /// Public phase-4 boundaries for SDK/snapshot rows produced outside this
  /// service. They all converge on the same Coordinator → Store commit path.
  Future<List<V2TimConversation>> commitSnapshotConversations({
    required String ownerUserId,
    required List<V2TimConversation> conversations,
  }) {
    return _commitSdkConversationBatch(
      ownerUserId: ownerUserId,
      conversations: conversations,
      source: ConversationMutationSource.snapshot,
    );
  }

  Future<List<V2TimConversation>> commitSdkHydratedConversations(
    List<V2TimConversation> conversations, {
    SessionIdentity? expectedIdentity,
  }) async {
    if (expectedIdentity != null &&
        !SessionIdentityService.instance.isCurrent(expectedIdentity))
      return const [];
    return _commitSdkConversationBatch(
      ownerUserId: expectedIdentity?.ownerUserId ?? _ownerUserId(),
      conversations: conversations,
      source: ConversationMutationSource.sdkPage,
    );
  }

  Future<List<V2TimConversation>> commitCreatedConversation(
    V2TimConversation conversation, {
    bool notifyUi = true,
  }) async {
    ConversationSdkCommittedBatch? committedBatch;
    final committed = await _commitSdkConversationBatch(
      ownerUserId: _ownerUserId(),
      conversations: <V2TimConversation>[conversation],
      source: ConversationMutationSource.sdkRealtime,
      allowRecreate: true,
      onCommittedBatch: (result) => committedBatch = result,
    );
    if (notifyUi && committed.isNotEmpty) {
      if (committedBatch != null) {
        await ChatSessionController.instance.applyCommittedProjection(
          ConversationUiSnapshotBatch<V2TimConversation>(
            upsertedSnapshots: committed,
            deletedCanonicalIds: const <String>[],
            structureChanged: committedBatch!.structureChanged,
            changedFieldMasks: committedBatch!.changedFieldMasks,
            commitGeneration: 0,
            unreadDeltas: committedBatch!.unreadDeltas.map(
              (delta) => ConversationUiUnreadDelta(
                conversationKey: delta.conversationKey,
                isGroup: delta.isGroup,
                oldNotifiable: delta.oldNotifiable,
                newNotifiable: delta.newNotifiable,
              ),
            ),
            unreadProjectionComplete: committedBatch!.unreadProjectionComplete,
          ),
          forceAdmitIds: <String>{conversation.conversationID},
        );
      } else {
        await ChatSessionController.instance.applySdkProjectionPatch(
          reason: ConversationStoreProjectionReason.sdkProjectionRestore,
          upserted: committed,
          forceAdmitIds: <String>{conversation.conversationID},
        );
      }
    }
    return committed;
  }

  Future<void> _purgeRejectedGroupConversations(
    List<V2TimConversation> conversations,
  ) async {
    if (!GroupMembershipSyncService.instance.hasSyncedGroupListOnce) {
      return;
    }
    for (final conversation in conversations) {
      if (_shouldPersistConversation(conversation)) {
        continue;
      }
      final convId = conversation.conversationID.trim();
      // 正在等待入群对齐的挂起项：禁止 prune，否则会话被清掉后只能杀进程恢复。
      if (convId.isNotEmpty &&
          _pendingNonMemberGroupConversations.containsKey(convId)) {
        continue;
      }
      final groupId = resolveGroupIdFromConversation(
        conversationId: conversation.conversationID,
        groupId: conversation.groupID,
      );
      if (groupId.isEmpty) {
        continue;
      }
      await GroupMembershipSyncService.instance.pruneStaleGroupConversations(
        reason: 'reject_non_member_persist',
      );
      return;
    }
  }

  Future<List<String>> _collectObsoleteGroupTwinIds({
    Iterable<String> extraIds = const [],
  }) async {
    final existing =
        await ConversationLocalStore.instance.listGroupConversationIds();
    return ChatIdFormat.obsoleteGroupConversationTwinIds(<String>[
      ...existing,
      ...extraIds,
    ]);
  }

  /// 删除「完整社群已存在」时残留的裸短码会话（本地精确删 + IM SDK）。
  Future<void> purgeSupersededBareShortGroupConversations({
    String reason = 'manual',
    List<String> extraObsoleteIds = const [],
  }) {
    return _purgeObsoleteGroupConversationTwins(
      reason: reason,
      upsertObsoleteIds: extraObsoleteIds,
    );
  }

  /// 删除会话双子残留（本地删 + IM SDK）。
  Future<void> _purgeObsoleteGroupConversationTwins({
    required String reason,
    List<String> upsertObsoleteIds = const [],
  }) async {
    final targets = upsertObsoleteIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (targets.isEmpty) {
      return;
    }
    final deleted = await _commitConversationDeletes(
      targets.toList(growable: false),
    );
    for (final id in targets) {
      try {
        await _conversationService.deleteConversation(conversationID: id);
      } catch (e) {
        _log(
          'purgeObsoleteGroupTwins sdk delete failed id=$id error=$e '
          'reason=$reason',
        );
      }
    }
    if (deleted.isNotEmpty || targets.isNotEmpty) {
      await _notifyUiAfterLocalWrite(
        deletedIds: targets.toList(growable: false),
      );
    }
    _log(
      'purgeObsoleteGroupTwins reason=$reason count=${targets.length} '
      'ids=${targets.take(6).join(',')}',
    );
  }

  late final _ingressPersistFlush = CoalescedAsyncFlush(
    () => _flushPersistEventQueue(reason: 'im_ingress'),
  );

  Future<void> _flushPersistEventQueue({required String reason}) async {
    _persistDedupTimer = null;
    final previous = _persistFlushTail;
    final current = previous.then((_) => _drainPersistEventQueue(reason));
    _persistFlushTail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    await current;
  }

  Future<void> _drainPersistEventQueue(String flushReason) async {
    if (_pendingPersistEvents.isEmpty) {
      return;
    }
    final events = List<_PendingConversationEvent>.from(_pendingPersistEvents)
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    _pendingPersistEvents.clear();
    persistFlushInvocationCount++;

    final accepted = <_PendingConversationEvent>[];
    final rejected = <V2TimConversation>[];
    for (final event in events) {
      if (event.ownerUserId != _pendingPersistOwner ||
          event.ownerGeneration != _pendingPersistOwnerGeneration) {
        continue;
      }
      if (event.identity != null &&
          (!_isCurrentRealtimeIdentity(event.identity) ||
              !await _hasCurrentMessageCoreLease(event.identity!))) {
        continue;
      }
      if (_shouldPersistConversation(event.snapshot)) {
        accepted.add(event);
      } else {
        rejected.add(event.snapshot);
      }
    }
    _stashPendingNonMemberGroupConversations(rejected);
    // Remove exact duplicates only. Distinct snapshots from the same source
    // are meaningful intermediate states (for example SENDING -> SUCCESS or
    // unread 1 -> 2 -> 3) and must remain in arrival order. Coalescing them by
    // conversation would silently drop a state before the coordinator can
    // apply its field-authority rules.
    final beforeCoalesceCount = accepted.length;
    final distinctEvents = <String, _PendingConversationEvent>{};
    for (final event in accepted) {
      final key = <Object?>[
        event.ownerUserId,
        event.ownerGeneration,
        event.source.name,
        event.allowRecreate,
        event.canonicalConversationId,
        event.fingerprint,
      ].join('\u001f');
      distinctEvents.putIfAbsent(key, () => event);
    }
    if (distinctEvents.length != beforeCoalesceCount) {
      accepted
        ..clear()
        ..addAll(distinctEvents.values)
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      ConversationUnreadTrace.log(
        'persist_flush_coalesced',
        extras: <String, Object?>{
          'before': beforeCoalesceCount,
          'after': accepted.length,
          'dropped': beforeCoalesceCount - accepted.length,
          'reason': flushReason,
          'mode': 'exact_duplicate_only',
        },
      );
    }
    if (accepted.isEmpty) {
      return;
    }

    final finalByCanonical = <String, V2TimConversation>{};
    final committedFieldMasks = <String, Set<ConversationMutationField>>{};
    final committedUnreadDeltas = <ConversationUiUnreadDelta>[];
    var unreadProjectionComplete = true;
    var committedStructureChanged = false;
    var index = 0;
    while (index < accepted.length) {
      final first = accepted[index];
      final batch = <_PendingConversationEvent>[first];
      index++;
      while (index < accepted.length) {
        final next = accepted[index];
        if (next.ownerUserId != first.ownerUserId ||
            next.ownerGeneration != first.ownerGeneration ||
            next.source != first.source ||
            next.allowRecreate != first.allowRecreate) {
          break;
        }
        batch.add(next);
        index++;
      }
      if (_pendingPersistOwner != first.ownerUserId ||
          _pendingPersistOwnerGeneration != first.ownerGeneration) {
        continue;
      }
      final snapshots = batch.map((event) => event.snapshot).toList();
      final fingerprints = <String, String>{
        for (final event in batch)
          _persistFingerprintKey(event.canonicalConversationId, event.source):
              event.fingerprint,
      };
      _persistInFlightFingerprints.addAll(fingerprints);
      late final List<V2TimConversation> merged;
      try {
        ConversationSdkCommittedBatch? batchResult;
        merged = upsertBatchOverride != null
            ? await upsertBatchOverride!(snapshots)
            : await _commitSdkConversationBatch(
                ownerUserId: first.ownerUserId,
                conversations: snapshots,
                source: first.source,
                allowRecreate: first.allowRecreate,
                onCommittedBatch: (result) => batchResult = result,
              );
        if (batchResult != null) {
          committedStructureChanged =
              committedStructureChanged || batchResult!.structureChanged;
          committedUnreadDeltas.addAll(batchResult!.unreadDeltas);
          unreadProjectionComplete =
              unreadProjectionComplete && batchResult!.unreadProjectionComplete;
          for (final entry in batchResult!.changedFieldMasks.entries) {
            committedFieldMasks[entry.key] = <ConversationMutationField>{
              ...(committedFieldMasks[entry.key] ??
                  const <ConversationMutationField>{}),
              ...entry.value,
            };
          }
        }
        if (_pendingPersistOwner == first.ownerUserId &&
            _pendingPersistOwnerGeneration == first.ownerGeneration) {
          for (final event in batch) {
            _viewModelPersistFingerprints[_persistFingerprintKey(
              event.canonicalConversationId,
              event.source,
            )] = event.fingerprint;
          }
        }
      } finally {
        for (final entry in fingerprints.entries) {
          if (_persistInFlightFingerprints[entry.key] == entry.value) {
            _persistInFlightFingerprints.remove(entry.key);
          }
        }
      }
      for (final conversation in merged) {
        final type = conversation.type == ConversationType.V2TIM_GROUP
            ? ConversationMutationConversationType.group
            : ConversationMutationConversationType.c2c;
        final canonical = canonicalizeConversationMutationId(
          conversation.conversationID,
          type,
        );
        if (canonical.isNotEmpty) {
          finalByCanonical[canonical] = _preferCommittedConversation(
            finalByCanonical[canonical],
            conversation,
          );
        }
      }
    }

    if (finalByCanonical.isEmpty ||
        accepted.first.ownerUserId != _pendingPersistOwner ||
        accepted.first.ownerGeneration != _pendingPersistOwnerGeneration) {
      return;
    }
    final merged = finalByCanonical.values.toList(growable: false);
    final archived = _archivedRows(merged);
    if (archived.isNotEmpty) _archivedSdkChanges.add(archived);
    // Backend archive membership needs only this subset index. Do not republish
    // SDK fields to the main list or start full-account reconciliation for it.
    if (accepted.every((event) => event.reason == 'archived_sdk_projection'))
      return;
    final hotListener = accepted.any(
      (event) => _isConversationListenerPersistReason(event.reason),
    );
    ConversationPinFlickerLog.log(
      'persist_flush',
      extras: <String, Object?>{
        'reason': flushReason,
        'count': accepted.length,
        'projected': merged.length,
        'deferring': ChatSessionController.instance.isDeferringPinReorder,
      },
    );
    for (final conversation in merged) {
      ConversationPerfGateLog.markRealtimePersistDone(
        conversationId: conversation.conversationID,
        reason: flushReason,
      );
    }
    await _notifyUiAfterLocalWrite(
      upserted: merged,
      immediate: hotListener,
      committedBatch: ConversationSdkCommittedBatch(
        upserted: merged,
        unreadDeltas: committedUnreadDeltas,
        unreadProjectionComplete: unreadProjectionComplete,
        changedFieldMasks: committedFieldMasks,
        structureChanged: committedStructureChanged,
      ),
    );
    // Both list modes publish committed unread deltas above. Reconcile the
    // full store promptly for rows outside the window; a trailing idle timer
    // can be postponed indefinitely by continuous incoming messages.
    if (accepted.any(
      (event) => event.source == ConversationMutationSource.sdkRealtime,
    )) {
      ConversationUnreadAggregate.instance.scheduleRefresh(
        reason: 'realtime_commit',
      );
    }
    unawaited(
      ConversationMutationShadowBridge.instance.compareLegacyProjection(
        ownerUserId: accepted.first.ownerUserId,
        conversations: merged,
      ),
    );
    await _purgeObsoleteGroupConversationTwins(
      reason: 'persist_flush:$flushReason',
      upsertObsoleteIds: await _collectObsoleteGroupTwinIds(
        extraIds: merged.map((c) => c.conversationID),
      ),
    );
    ConversationUnreadTrace.logConversations(
      'persist_flush_upserted',
      conversations: merged,
      extras: <String, Object?>{'reason': flushReason},
    );
  }

  /// The persistence override and some SDK adapters can return more than one
  /// snapshot for the same conversation in a single drain. Keep the strongest
  /// last-message projection instead of letting a late page snapshot roll a
  /// realtime preview back.
  V2TimConversation _preferCommittedConversation(
    V2TimConversation? existing,
    V2TimConversation incoming,
  ) {
    if (existing == null) return incoming;
    final preferred = ConversationLastMessagePrefer.preferLastMessage(
      existing: existing.lastMessage,
      incoming: incoming.lastMessage,
    );
    if (identical(preferred, existing.lastMessage)) return existing;
    if (identical(preferred, incoming.lastMessage) || preferred != null) {
      incoming.lastMessage = preferred;
      return incoming;
    }
    return existing;
  }

  Future<void> _persistDeleted(
    List<String> conversationIds, {
    bool force = false,
    bool immediate = false,
  }) async {
    if (conversationIds.isEmpty) {
      return;
    }
    final preserved = <String>[];
    final deletable = <String>[];
    for (final raw in conversationIds) {
      final id = raw.trim();
      if (id.isEmpty) {
        continue;
      }
      if (!force &&
          await ConversationLocalStore.instance
              .shouldSuppressConversationDeletionAfterHistoryClearAsync(id)) {
        preserved.add(id);
        continue;
      }
      deletable.add(id);
    }
    if (preserved.isNotEmpty) {
      _log(
        'persistDeleted skipped history-cleared count=${preserved.length} ids=$preserved',
      );
      // 产品：清空/删除均不留空壳。suppress 时 no-op，禁止回钉列表。
    }
    if (deletable.isEmpty) {
      return;
    }
    if (force) {
      for (final id in deletable) {
        ConversationLocalStore.instance.clearHistoryClearedMarkers(id);
        ArchiveHistoryProvider.clearHistoryClearPending(id);
      }
    }
    final deleted = await _commitConversationDeletes(deletable);
    await _notifyUiAfterLocalWrite(deletedIds: deleted, immediate: immediate);
    _notifyActiveChatClosed(deleted);
    _log(
      'persistDeleted count=${deletable.length}${force ? ' force=true' : ''}',
    );
  }

  void _notifyActiveChatClosed(List<String> deletedIds) {
    if (deletedIds.isEmpty) {
      return;
    }
    try {
      final model = serviceLocator<TUIConversationViewModel>();
      final selectedId =
          model.selectedConversation?.conversationID.trim() ?? '';
      if (selectedId.isNotEmpty) {
        final hit = deletedIds.any(
          (id) => MessageConversationId.sameConversation(id, selectedId),
        );
        if (hit) {
          model.assignSelectedConversation(null, notify: true);
        }
      }
    } catch (_) {}
    ConversationDeletedBus.instance.notifyDeleted(deletedIds);
  }

  Future<void> clearSession({String? ownerUserId}) async {
    await detachRealtimeListeners();
    _syncGeneration++;
    // Invalidate the lock immediately. The old SDK future may still complete,
    // but its owner/generation no longer matches and therefore cannot clear or
    // overwrite a new account's sync state in its finally block.
    _pageSyncInFlight = false;
    ConversationMutationShadowBridge.instance.clearSession();
    _c2cHistoryBackfillInFlight = null;
    _c2cHistoryBackfillScheduled = false;
    _c2cMetadataEnrichDone = false;
    _c2cFriendScanDone = false;
    _pendingSdkSync = null;
    _scopeHydrationTask = null;
    _scopeHydrationDone = false;
    _pendingPatches.clear();
    _patchesQueuedDuringSync = 0;
    _lastMarkReadId = null;
    _lastMarkReadAt = null;
    _syncServerFinishTimer?.cancel();
    _syncServerFinishTimer = null;
    _lastSyncServerFinishAt = null;
    _sdkServerSyncPending = false;
    _reloadUiCoalesceTimer?.cancel();
    _reloadUiCoalesceTimer = null;
    _chatTransitionDepth = 0;
    _postPopCoalesceUntil = null;
    _postPopCoalesceWindowStart = null;
    _postPopCoalesceScheduled = false;
    _persistDedupTimer?.cancel();
    _persistDedupTimer = null;
    _pendingPersistEvents.clear();
    _pendingPersistOwner = '';
    _pendingPersistOwnerGeneration++;
    _persistFlushTail = Future<void>.value();
    _latestPersistSequenceById.clear();
    _viewModelPersistFingerprints.clear();
    _persistInFlightFingerprints.clear();
    _recentlyLeftConversationId = null;
    _idleDrainTimer?.cancel();
    _idleDrainTimer = null;
    _idleDrainSessionPages = 0;
    _idleDrainCycleCount = 0;
    _backgroundDrainInFlight = false;
    await ConversationLocalStore.instance.clearSession(
      ownerUserId: ownerUserId,
    );
    ChatSessionController.instance.clearSessionProjection();
    ConversationListSyncNotifier.instance.clearSession();
  }
}
