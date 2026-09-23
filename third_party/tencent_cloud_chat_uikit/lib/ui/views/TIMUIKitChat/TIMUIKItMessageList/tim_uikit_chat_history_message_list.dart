import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/entry_unread_locator.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_partition_prefix.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_around_loader.dart';
import 'dart:async';
import 'dart:math';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_viewport_motion.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_scroll.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_history_layout.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/visible_sender_profile_refresh.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
// ignore: unused_import
import 'package:tencent_cloud_chat_uikit/ui/utils/optimize_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_message_enter_animation.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_message_row_reveal.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_message_list_skeleton.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_visibility.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/keepalive_wrapper.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_initial_window_reveal_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_cover_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/perf_timeline.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_resource_sample.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_geom_settle_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_open_layout_ready.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_inbound_scroll_follow.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_latest_load_intent.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_previous_prefetch_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/history_window_trim_ui_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_window_trim_transaction.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_viewport_insert_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_route_scroll_restore.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_page_ui_notifiers.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_image_batch_display.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_height_cache.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_reading_viewport_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/at_me_jump.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/first_unread_jump.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_latest_gate.dart';
import 'package:tencent_cloud_chat_uikit/data_services/conversation/conversation_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_pipeline_clock.dart';

import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue.dart';
import 'TIMUIKitTongue/unread_tongue_policy.dart';
import 'TIMUIKitTongue/back_to_bottom_capsule_policy.dart';
import 'TIMUIKitTongue/true_latest_end.dart';
import 'TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';

enum LoadingPlace { none, top, bottom }

enum ScrollType { toIndex, toIndexBegin }

class TIMUIKitHistoryMessageListController extends ChangeNotifier {
  AutoScrollController? scrollController = AutoScrollController();
  late ScrollType scrollType;
  late V2TimMessage targetMessage;

  TIMUIKitHistoryMessageListController({
    AutoScrollController? scrollController,
  }) {
    if (scrollController != null) {
      this.scrollController = scrollController;
    }
  }

  scrollToIndex(V2TimMessage message) {
    scrollType = ScrollType.toIndex;
    targetMessage = message;
    notifyListeners();
  }

  scrollToIndexBegin(V2TimMessage message) {
    scrollType = ScrollType.toIndexBegin;
    targetMessage = message;
    notifyListeners();
  }
}

class TIMUIKitHistoryMessageList extends StatefulWidget {
  /// message list
  final List<V2TimMessage?> messageList;

  /// tongue item builder
  final TongueItemBuilder? tongueItemBuilder;

  /// group at info, it can get from conversation info
  final List<V2TimGroupAtInfo?>? groupAtInfoList;

  /// use for build message item
  final Widget Function(BuildContext, V2TimMessage?)? itemBuilder;

  /// can controll message list scroll
  final TIMUIKitHistoryMessageListController? controller;

  /// use for message jump, if passed will jump to target message.
  final V2TimMessage? initFindingMsg;
  final MessageAnchor? searchJumpAnchor;

  /// use for load more message
  final Future<bool> Function(String?, LoadDirection direction,
      [int?, int?, V2TimMessage?]) onLoadMore;

  /// configuration for list view
  final TIMUIKitHistoryMessageListConfig? mainHistoryListConfig;

  final TUIChatSeparateViewModel model;

  final bool isAllowScroll;

  final V2TimConversation conversation;

  const TIMUIKitHistoryMessageList({
    Key? key,
    required this.model,
    required this.messageList,
    this.itemBuilder,
    this.controller,
    required this.onLoadMore,
    this.tongueItemBuilder,
    this.groupAtInfoList,
    this.initFindingMsg,
    this.searchJumpAnchor,
    this.isAllowScroll = true,
    this.mainHistoryListConfig,
    required this.conversation,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TIMUIKitHistoryMessageListState();
}

class _TIMUIKitHistoryMessageListState
    extends TIMUIKitState<TIMUIKitHistoryMessageList>
    with TickerProviderStateMixin {
  /// Pipeline 诊断：首次 tuiBuild 时输出 [Pipeline][first_visible] 一次。

  /// Reveal 诊断：前 5 次 tuiBuild 输出 [RevealTrace][tui_build] 时间锚点。
  V2TimMessage? findingMsg;
  MessageAnchor? findingAnchor;
  MessageAnchor? _entryUnreadOrigin;
  MessageAnchor? _atJumpOrigin;
  final _windowTransitionKey = GlobalKey<ChatHistoryWindowTransitionState>();
  bool _unreadWindowJumpInFlight = false;
  String findingSeq = "";
  late TIMUIKitHistoryMessageListController _controller;
  late AutoScrollController _autoScrollController;
  final GlobalKey _unreadCenterKey = GlobalKey();
  LoadingPlace loadingPlace = LoadingPlace.none;
  bool maybeHaveMoreMessageForFind = true;
  bool _scrollToFindInFlight = false;
  bool _initialSearchJumpPositioned = false;
  int? _searchJumpRequest;
  bool get _ownsSearchJumpRequest =>
      _searchJumpRequest == null ||
      (_chatGlobalModel?.isCurrentSearchJumpRequest(
              _conversationId(), _searchJumpRequest!) ??
          false);

  void _releaseAtJumpCenterOwnership({bool notify = true}) {
    if (_atJumpOrigin == null) {
      return;
    }
    _atJumpOrigin = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  bool get _initialSearchJumpPending =>
      (widget.searchJumpAnchor != null || widget.initFindingMsg != null) &&
      !_initialSearchJumpPositioned &&
      _chatGlobalModel?.getSearchJumpStatus(_conversationId()) !=
          SearchJumpStatus.failed;
  bool _pendingScrollToFind = false;
  int _findingRetryCount = 0;
  final ChatListPaginationUiGate _paginationUi = ChatListPaginationUiGate();
  final ChatPreviousLoadQueue _previousLoadQueue = ChatPreviousLoadQueue();
  final ChatLatestLoadIntent _latestLoadIntent = ChatLatestLoadIntent();
  int _latestPaginationGeneration = 0;
  int _previousPaginationGeneration = 0;
  bool Function()? _previousLoadWindowIsCurrent;
  final ValueNotifier<bool> _topHistoryLoadingVisible =
      ValueNotifier<bool>(false);
  final ChatListViewportInsertController _viewportInsert =
      ChatListViewportInsertController();
  final Map<String, Animation<double>> _shortInsertProgress = {};
  final Set<AnimationController> _shortInsertControllers = {};
  final ChatListRouteScrollRestore _routeScroll = ChatListRouteScrollRestore();
  final ChatPageUiNotifiers _pageUi = ChatPageUiNotifiers();

  // K.9：new message pill + 自动跟随
  int _unreadCountBelowViewport = 0;
  bool _isPinnedToBottom = true;
  static const double _kPinBottomThreshold = 80.0;

  // debounce 触发时读取的最新锚点。顶部回弹会持续产生滚动事件，
  // 若每次都重置计时器会把 debounce 无限饿死；改为"已有计时器在跑就不重置、
  // 只更新锚点"，保证一定能在 120ms 后触发一次加载。
  int? _shortViewportPreviousPointer;
  Offset? _shortViewportPreviousPointerStart;
  bool _shortViewportPreviousGestureRecorded = false;
  bool _shortViewportPreviousGestureCancelled = false;
  bool _userScrollGestureActive = false;
  String _lastGeomJumpAttemptReason = '';
  int _lastGeomJumpAttemptAtMs = 0;
  double? _lastOffsetSamplePixels;
  double? _lastOffsetSampleMinExtent;
  double? _lastOffsetSampleMaxExtent;
  final _historyWindowTrimUi = HistoryWindowTrimUiController<
      HistoryWindowTrimTicket, _PaginationViewportAnchor>();
  Timer? _historyWindowTrimIdleTimer;
  bool _historyWindowPaginationWasBlocked = false;
  int _historyWindowTrimIdleRetries = 0;
  // A pagination request can complete while the user is still dragging. Keep
  // the restore alive until ScrollEnd instead of exhausting frame retries.
  _PaginationRestoreRequest? _pendingPaginationRestoreAfterScrollEnd;
  // Once the user continues the same gesture after a page is requested, the
  // saved pre-request pixels are stale. Never restore that old offset at the
  // next ScrollEnd; the gesture owns the viewport from that point on.
  bool _paginationUserScrollSinceLoad = false;
  int _lastPaginationScrollWriteLogMs = 0;
  Timer? _postScrollInboundFlushTimer;
  Timer? _unreadTongueMetricsThrottleTimer;
  static const int _postScrollInboundFlushDelayMs = 160;
  static const int _scrollingUnreadTongueMetricsThrottleMs = 80;
  static const _loadLatestCooldownMs =
      ChatListPaginationUiGate.loadLatestCooldownMs;
  static const _loadPreviousCooldownMs =
      ChatListPaginationUiGate.loadPreviousCooldownMs;
  static const _historyScrollProtectMs =
      ChatListPaginationUiGate.historyScrollProtectMs;
  static const _loadPreviousScrollUnlockMs =
      ChatListPaginationUiGate.loadPreviousScrollUnlockMs;
  static const _scrollPaginationCompensationMs =
      ChatListPaginationUiGate.scrollPaginationCompensationMs;
  static const _readingHistoryThresholdPx =
      ChatListPaginationUiGate.readingHistoryThresholdPx;
  static const double _followingLatestEpsilonPx =
      TrueLatestEnd.geometryEpsilon;
  static const double _offsetJumpDiagThresholdPx = 200.0;
  // 预算与消费同帧发生（毫秒级），批次间隔在 600ms 以上：500ms 既不误杀正常
  // 消费，也保证 physics 某帧没被调到时余额不会跨批滞留。
  static const int _newestInsertRoomTtlMs = 500;
  // 接缓冲那一批的真实高度跨多帧到达，估高两个方向都会偏。锚点按实测
  // maxExtent 增量反复校正，12 帧覆盖观测到的懒布局窗口。
  static const int _revealAnchorMaxAttempts = 12;
  // 渐进接缓冲：提交后等待 layout 落地的最大帧数。正常情况下一帧就被
  // physics 全额补偿并清掉；零高行等不产生增长时靠这个过期兜底。
  static const int _progressiveRevealGrowthMaxFrames = 3;
  static const _loadPreviousTopReachResetPx =
      ChatListPaginationUiGate.loadPreviousTopReachResetPx;
  static const _loadPreviousTopNearPx =
      ChatListPaginationUiGate.loadPreviousTopNearPx;
  static const _loadPreviousOverscrollTolerancePx =
      ChatListPaginationUiGate.loadPreviousOverscrollTolerancePx;
  static const _minTopHistoryLoadingVisibleMs =
      ChatListPaginationUiGate.minTopHistoryLoadingVisibleMs;
  static const double _continuousViewportPushBasePixelsPerSecond =
      ChatListViewportInsertController
          .continuousViewportPushBasePixelsPerSecond;
  static const double _continuousViewportPushMaxPixelsPerSecond =
      ChatListViewportInsertController.continuousViewportPushMaxPixelsPerSecond;
  static const int _continuousViewportPushSpeedRampRows =
      ChatListViewportInsertController.continuousViewportPushSpeedRampRows;
  static const int _continuousViewportPushMeasureMaxAttempts =
      ChatListViewportInsertController.continuousViewportPushMeasureMaxAttempts;
  static const int _continuousViewportPushInitialLayoutSuppressMs =
      ChatListViewportInsertController
          .continuousViewportPushInitialLayoutSuppressMs;
  static const _viewportInsertSettleMs =
      ChatListViewportInsertController.viewportInsertSettleMs;
  static const _mediaSettleMs = ChatListViewportInsertController.mediaSettleMs;
  static const double _shortHistoryMessageEstimatedRowHeight =
      ChatListRouteScrollRestore.shortHistoryMessageEstimatedRowHeight;
  static const double _shortHistoryGroupTipsEstimatedRowHeight =
      ChatListRouteScrollRestore.shortHistoryGroupTipsEstimatedRowHeight;
  static const double _shortHistoryTimeDividerEstimatedRowHeight =
      ChatListRouteScrollRestore.shortHistoryTimeDividerEstimatedRowHeight;
  static const double _shortHistoryAlignmentHysteresis =
      ChatListRouteScrollRestore.shortHistoryAlignmentHysteresis;
  static const double _shortHistorySpacerRebuildTolerancePx =
      ChatListRouteScrollRestore.shortHistorySpacerRebuildTolerancePx;
  TUIChatGlobalModel? _chatGlobalModel;
  List<V2TimMessage?> _cachedUnreadList = [];
  List<V2TimMessage?> _cachedReadList = [];
  List<V2TimMessage?>? _contextMenuFrozenVisibleMessages;
  int _frozenWidgetListLen = -1;
  // Indices and mounted AutoScrollTags must refer to this exact projection,
  // never to a newer global commit that has not reached the widget tree yet.
  List<V2TimMessage?>? _renderedVisibleMessages;
  static const int _initialMountRowsPerFrame = 12;
  String? _initialMountBatchConversationID;
  int _initialMountLimit = 0;
  int _initialMountGeneration = 0;
  bool _initialMountFrameScheduled = false;
  bool _initialMountBatchComplete = false;
  int _cacheUnreadCount = -1;
  int _cacheMessageListLen = -1;
  int _cacheUnreadEndPoint = -1;
  int _cacheMessageListRevision = -1;
  int _cacheRestoreVersion = -1;
  String? _cacheLastMsgKey;
  String? _cacheHeadMsgKey;
  String? _cacheListStateKey;
  Map<String, int> _unreadIndexMap = {};
  Map<String, int> _readIndexMap = {};
  Map<String, int> _globalIndexMap = {};
  Map<String, int> _globalMessageIdentityIndexMap = {};
  bool _deferUnreadCenterPartition = false;
  String? _livePartitionAnchorHeadKey;
  V2TimMessage? _livePartitionAnchorHeadMessage;
  int? _contextMenuFrozenLayoutUnreadCount;
  int _lastResolvedLayoutUnreadCount = 0;
  int _lastDiagLayoutSafeUnread = -1;
  int _lastDiagLayoutUnread = -1;
  int _lastCenterDiagLayoutUnread = -1;
  int _lastCenterDiagUnreadEndPoint = -1;
  int _lastCenterDiagUnreadLen = -1;
  int _lastCenterDiagReadLen = -1;
  bool? _lastCenterDiagCenterActive;
  double? _lastPhysicsMaxExtentSeen;
  double _newestInsertRoom = 0.0;
  int _newestInsertRoomAtMs = 0;
  double? _incomingScrollAnchorPixels;
  double? _incomingScrollAnchorMaxExtent;
  int _incomingScrollAnchorGeneration = 0;
  _PaginationViewportAnchor? _revealViewportAnchor;
  HistoryReadingViewportAnchor? _revealGeometryAnchor;
  RenderObject? _revealAnchorRenderObject;
  int _revealAnchorGeneration = 0;
  bool _progressiveRevealGrowthPending = false;
  int _progressiveRevealGeneration = 0;
  Timer? _followingLatestRestoreRetryTimer;
  double? _lastGeometryViewportDimension;
  bool _listGeometryLatchHeld = false;
  int _listGeometryStableMetrics = 0;
  int _contextMenuViewportRestoreGeneration = 0;
  bool _contextMenuViewportRestoreScheduled = false;
  bool _contextMenuViewportRestoreCallbackPending = false;
  int _contextMenuViewportStableFrames = 0;
  int _searchJumpStabilizeUntilMs = 0;
  int _searchJumpGeneration = 0;
  Timer? _searchJumpLayoutDeadline;
  String? _initialUnreadAnchorConversationID;
  int _initialUnreadAnchorCount = 0;
  int _initialUnreadAnchorAttempts = 0;
  bool _initialUnreadAnchorScheduled = false;
  bool _initialUnreadAnchorInFlight = false;
  int _completedEntryUnreadCount = 0;
  _UnreadMessageAnchor? _firstUnreadAnchor;
  bool _firstUnreadAnchorJumped = false;
  bool _unreadTongueMetricsScheduled = false;
  List<V2TimMessage?>? _pendingUnreadTongueMetricsList;
  int _pendingUnreadTongueMetricsSafeCount = 0;
  int _lastUnreadTongueMetricsRunAtMs = 0;
  String? _lastUnreadTongueConversationID;
  int? _lastUnreadTongueRemaining;
  int _lastUnreadTongueSafeCount = 0;
  bool _unreadEntryBottomPinScheduled = false;
  TUIChatSeparateViewModel? _boundSeparateModel;
  int _lastHandledPinSeq = 0;
  int _lastHandledScrollFollowSeq = 0;
  int _lastInboundPresentationSupersedeSeq = 0;
  int _forcePinGeneration = 0;

  /// CVP 量高失败兜底：跳过 list-push / 媒体稳定 / settle 等待，立刻贴底。
  bool _forcePinIgnoreInsertWindows = false;
  bool _immediateOutgoingImageBatchPin = false;
  InboundScrollFollow? _inboundScrollFollow;
  late final int _createdAtMs;

  /// 进页揭示门：未 ready 时透明，避免贴底首帧再抬升。
  bool _historyOpenRevealReady = false;

  /// 一旦对用户亮过首屏，epoch 重置也不得再 Opacity=0，否则会「先出记录再闪一下」。
  bool _historyOpenRevealPainted = false;
  bool _compactHistoryCacheExtent = false;
  int _lastScrollNearTopTraceMs = 0;
  String _lastScrollNearTopTraceAnchor = '';
  int _lastScrollPrefetchTraceMs = 0;
  String _lastScrollPrefetchTraceAnchor = '';
  int _historyOpenRevealPostFrameCount = 0;
  int? _historyOpenRevealDeadlineMs;
  bool _historyOpenRevealWaitScheduled = false;
  bool _historyOpenRevealStarveLogged = false;

  /// 短历史：测前 starve 日志上限；长历史：2帧/120ms。
  int _historyOpenRevealMaxPostFrames = 2;
  int _historyOpenRevealTimeoutMs = 120;

  /// 短历史测后稳定窗。
  int _historyOpenRevealStableFrames = 0;
  int? _historyOpenRevealMeasuredAtMs;
  int _historyOpenRevealFramesSinceMeasured = 0;
  double? _historyOpenRevealLastSpacer;
  double? _historyOpenRevealLastContentH;
  bool _historyOpenRevealRowBumpPending = false;
  int? _historyOpenRevealReadyAtMs;
  int _historyOpenRevealHoldFrames = 0;
  int? _historyOpenRevealLastListLen;
  int? _historyOpenRevealLastListRev;
  int _layoutReadyEpochSigned = -1;
  int _layoutReadyEpochSeen = 0;

  /// 长历史 maxExtent 稳定采样。
  int _historyOpenRevealLongStableFrames = 0;
  double? _historyOpenRevealLastMaxExtent;
  int? _historyOpenRevealLongArmAtMs;

  /// 软超时遇上 loadPrevious 在飞时，最多再等这么久。
  int? _historyOpenRevealLongLoadWaitDeadlineMs;

  /// B1：post-frame 链中断保护用的 100ms 周期的 watchdog 定时器。
  /// 历史问题：链式 addPostFrameCallback 递归如果某次回调丢失，
  /// 整条 reveal gate 链停摆，连软超时都不触发（pch7hqqolk 走 6.7s 才到 commit）。
  Timer? _historyOpenRevealWatchdogTimer;

  /// reveal 后因异步历史写回清过 latch / 装不下时：禁止再 `spacer_prime`。
  bool _blockShortSpacerReprimeAfterReveal = false;

  // 80ms 延迟原本是给"快速历史加载"避免闪烁留的保险窗。
  // 命中本地缓存后骨架已不显示（见 chat.dart / app_chat_route.dart 的预热）；
  // 未命中时 0ms 也比 80ms 体感快，让骨架 fade-in 与首帧几乎同步。
  static const Duration _openingPlaceholderDelay = Duration(milliseconds: 0);
  static const Duration _openingPlaceholderFadeDuration = Duration(
    milliseconds: 80,
  );
  final ChatHistoryOpeningPlaceholderController _openingPlaceholder =
      ChatHistoryOpeningPlaceholderController();
  Timer? _openingPlaceholderDelayTimer;
  late final AnimationController _openingPlaceholderFadeController;
  late final Animation<double> _openingPlaceholderOpacity;
  int _openingPlaceholderFadeGeneration = 0;
  int? _openingPlaceholderFirstPaintAtMs;
  bool _openingPlaceholderDismissScheduled = false;
  bool _messagesFirstVisibleScheduled = false;
  bool _messagesFirstVisibleReported = false;
  String _openingPlaceholderDismissSource = 'reveal';

  @override
  void initState() {
    super.initState();
    _createdAtMs = DateTime.now().millisecondsSinceEpoch;
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageList',
      phase: 'initState',
      stateHash: identityHashCode(this),
      conv: widget.model.conversationID,
      keyDebug: widget.key?.toString(),
    );
    ChatGeomSettleTrace.begin(
      conversationID: widget.model.conversationID,
      openSeq: ChatJitterDiag.openSeq,
      capture: _captureGeomSettleSnapshot,
    );
    final convId = widget.model.conversationID;
    final globalModel = widget.model.globalModel;
    // Page UI is SSOT for open-chat scroll flags; GlobalModel mirrors via attach.
    globalModel.attachOpenChatPageUi(
      conversationId: convId,
      historyPosition: _pageUi.historyPosition,
      userScrolling: _pageUi.userScrolling,
    );
    globalModel.setChatListUserScrolling(false);
    // 本地已有消息时进页立刻补种行高（会话列表预载可能未跑到）。
    ChatMessageHeightCache.instance.seedEstimatesForMessages(
      globalModel.getMessageList(convId) ?? const <V2TimMessage>[],
    );
    _routeScroll.openedWithCachedHistory =
        globalModel.rawMessageCount(convId) > 0;
    _openingPlaceholderFadeController = AnimationController(
      vsync: this,
      duration: _openingPlaceholderFadeDuration,
      value: 1,
    );
    _openingPlaceholderOpacity = CurvedAnimation(
      parent: _openingPlaceholderFadeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    _openingPlaceholderFadeController.addStatusListener(
      _onOpeningPlaceholderFadeStatus,
    );
    _beginOpeningPlaceholderForCurrentConversation();
    if (_routeScroll.openedWithCachedHistory &&
        globalModel.hasInitialHistoryLoaded(convId)) {
      _routeScroll.wasInitialHistoryBootstrapping = false;
    }
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      _routeScroll.clearShortHistoryAlignmentLatch();
      ChatGeomSettleTrace.noteReason(
        'short_history_top_align_disabled',
        extras: <String, Object?>{
          'openedWithCachedHistory': _routeScroll.openedWithCachedHistory,
          'rawCount': globalModel.rawMessageCount(convId),
        },
      );
      ChatOpenPerfLog.mark(
        'short_history_top_align_disabled',
        conversationID: convId,
        extras: <String, Object?>{
          'openedWithCachedHistory': _routeScroll.openedWithCachedHistory,
        },
      );
    }
    // 暖窗：仅完整首屏立刻 ready。列表预热的几条消息若先亮，会贴底留白。
    // miss 时走短历史测高/稳定窗（见 _evaluateHistoryOpenReveal）。
    // 贴底模式：不依赖 short contentH 缓存，有完整暖窗即可 ready。
    if (_routeScroll.openedWithCachedHistory) {
      if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
        if (_isCompleteCachedOpenWindow(globalModel)) {
          _commitHistoryOpenRevealReady(
            source: 'opened_with_cache_bottom_align',
            bridgeSignal: false,
          );
        }
      } else {
        final cached =
            globalModel.getMessageList(convId) ?? const <V2TimMessage>[];
        final signature = TUIChatGlobalModel.historyIdentitySignature(cached);
        final lastMeasured =
            ChatMessageHeightCache.instance.measuredContentHeightFor(
          conversationID: convId,
          identitySignature: signature,
        );
        if (lastMeasured != null && lastMeasured > 0) {
          _commitHistoryOpenRevealReady(
            source: 'opened_with_cache',
            bridgeSignal: false,
          );
        } else {
          ChatGeomSettleTrace.noteReason(
            'warm_open_reveal_deferred_no_measured_content_h',
            extras: <String, Object?>{'len': cached.length},
          );
        }
      }
    }
    _controller = widget.controller ?? TIMUIKitHistoryMessageListController();
    _autoScrollController =
        _controller.scrollController ?? AutoScrollController();
    // K.9：监听 scroll 位置，更新是否贴底状态
    _autoScrollController.addListener(_onAutoScrollUpdate);
    _viewportInsert.rowRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _viewportInsert.rowRevealAnimation = CurvedAnimation(
      parent: _viewportInsert.rowRevealController!,
      curve: ChatViewportMotion.curve,
    );
    _viewportInsert.rowRevealController!.addStatusListener((status) {
      if (_viewportInsert.suppressRowRevealStatus) {
        return;
      }
      if (status == AnimationStatus.completed) {
        _pinScrollToBottomImmediate();
        _completeRowRevealTransaction();
      }
    });
    _controller.addListener(_controllerListener);
    initFinding();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindActiveScrollController();
      _onGlobalRouteRestoreChanged();
      if (!_mayUseShortHistoryTopAlignment()) {
        _releaseShortHistoryAlignmentAndPinBottom();
      }
    });
    _bindSeparateModelListener();
    _scheduleChatOpenPerfProbe(reason: 'initState');
    ChatHistoryOpenLayoutReady.epochRevision.addListener(
      _onLayoutReadyEpochRevision,
    );
  }

  void _onLayoutReadyEpochRevision() {
    if (!mounted) {
      return;
    }
    _syncHistoryOpenRevealEpochOrReset();
  }

  void _scheduleChatOpenPerfProbe({required String reason}) {
    final convId = _conversationId();
    final count = widget.messageList.length;
    final globalModel = widget.model.globalModel;
    final initialLoaded = globalModel.hasInitialHistoryLoaded(convId);
    final probeTrace = ChatOpenPerfLog.captureCurrent(conversationKey: convId);
    // 列表即将/正在挂图片气泡：同步开短暂 decode defer，覆盖首帧尖刺。
    if (count > 0) {
      globalModel.beginChatOpenImageDecodeDefer();
    }
    ChatOpenPerfLog.markHistoryListBuilt(
      conversationID: convId,
      messageCount: count,
      initialLoaded: initialLoaded,
      bootstrapping: !initialLoaded,
      trace: probeTrace,
    );
    if (count <= 0) {
      return;
    }
    if (_historyOpenRevealPainted && !_openingPlaceholder.shouldPaint) {
      _scheduleMessagesFirstVisibleAfterReveal(source: reason);
    }
  }

  bool get _isOpeningPlaceholderSearchJump =>
      widget.searchJumpAnchor != null || widget.initFindingMsg != null;

  void _beginOpeningPlaceholderForCurrentConversation() {
    _openingPlaceholderDelayTimer?.cancel();
    _openingPlaceholderDelayTimer = null;
    _openingPlaceholderFadeController.stop();
    _openingPlaceholderFadeController.value = 1;
    _openingPlaceholderDismissScheduled = false;
    _openingPlaceholderFadeGeneration = 0;
    _openingPlaceholderFirstPaintAtMs = null;
    final globalModel = widget.model.globalModel;
    final conversationID = _conversationId();
    final generation = _openingPlaceholder.begin(
      initialMessageCount: globalModel.rawMessageCount(conversationID),
      initialHistoryLoaded: globalModel.hasInitialHistoryLoaded(conversationID),
      isSearchJump: _isOpeningPlaceholderSearchJump,
      hasLockedEntryUnread: globalModel.hasLockedEntryUnreadFor(conversationID),
    );
    if (_openingPlaceholder.phase !=
        ChatHistoryOpeningPlaceholderPhase.waiting) {
      return;
    }
    _openingPlaceholderDelayTimer = Timer(
      _openingPlaceholderDelay,
      () => _showOpeningPlaceholderAfterDelay(generation),
    );
  }

  void _showOpeningPlaceholderAfterDelay(int generation) {
    _openingPlaceholderDelayTimer = null;
    if (!mounted) {
      return;
    }
    final globalModel = widget.model.globalModel;
    final conversationID = _conversationId();
    final shown = _openingPlaceholder.showAfterDelay(
      generation: generation,
      messageCount: globalModel.rawMessageCount(conversationID),
      initialHistoryLoaded: globalModel.hasInitialHistoryLoaded(conversationID),
      revealPainted: _historyOpenRevealPainted,
      isSearchJump: _isOpeningPlaceholderSearchJump,
      hasLockedEntryUnread: globalModel.hasLockedEntryUnreadFor(conversationID),
    );
    if (!shown) {
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _openingPlaceholder.generation ||
          !_openingPlaceholder.shouldPaint) {
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _openingPlaceholderFirstPaintAtMs = nowMs;
      ChatMainThreadPerf.recordDurationMicros(
        ChatMainThreadPerf.openingPlaceholderFirstPaintMs,
        (nowMs - _createdAtMs) * Duration.microsecondsPerMillisecond,
        source: widget.conversation.type != 1 ? 'group' : 'c2c',
      );
      ChatOpenPerfLog.mark(
        'opening_placeholder_first_paint',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'delayMs': _openingPlaceholderDelay.inMilliseconds,
          'isGroup': widget.conversation.type != 1,
        },
      );
    });
  }

  void _scheduleOpeningPlaceholderDismiss({required String source}) {
    final phase = _openingPlaceholder.phase;
    if (phase == ChatHistoryOpeningPlaceholderPhase.inactive ||
        phase == ChatHistoryOpeningPlaceholderPhase.removed) {
      _scheduleMessagesFirstVisibleAfterReveal(source: source);
      return;
    }
    if (phase == ChatHistoryOpeningPlaceholderPhase.dismissing ||
        _openingPlaceholderDismissScheduled) {
      return;
    }
    _openingPlaceholderDismissScheduled = true;
    final generation = _openingPlaceholder.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingPlaceholderDismissScheduled = false;
      if (!mounted || generation != _openingPlaceholder.generation) {
        return;
      }
      _openingPlaceholderDelayTimer?.cancel();
      _openingPlaceholderDelayTimer = null;
      final shouldFade = _openingPlaceholder.beginDismiss(generation);
      if (!shouldFade) {
        _scheduleMessagesFirstVisibleAfterReveal(source: source);
        return;
      }
      _openingPlaceholderDismissSource = source;
      _openingPlaceholderFadeGeneration = generation;
      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (disableAnimations) {
        _finishOpeningPlaceholderDismiss(generation);
        return;
      }
      setState(() {});
      _openingPlaceholderFadeController.reverse(from: 1);
    });
  }

  void _onOpeningPlaceholderFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        _openingPlaceholderFadeGeneration <= 0) {
      return;
    }
    _finishOpeningPlaceholderDismiss(_openingPlaceholderFadeGeneration);
  }

  void _finishOpeningPlaceholderDismiss(int generation) {
    if (!_openingPlaceholder.finishDismiss(generation)) {
      return;
    }
    _openingPlaceholderFadeGeneration = 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final firstPaintAtMs = _openingPlaceholderFirstPaintAtMs;
    if (firstPaintAtMs != null) {
      ChatMainThreadPerf.recordDurationMicros(
        ChatMainThreadPerf.openingPlaceholderVisibleMs,
        (nowMs - firstPaintAtMs) * Duration.microsecondsPerMillisecond,
        source: _openingPlaceholderDismissSource,
      );
    }
    ChatOpenPerfLog.mark(
      'opening_placeholder_removed',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'source': _openingPlaceholderDismissSource,
        'fadeMs': _openingPlaceholderFadeDuration.inMilliseconds,
        'messageCount': widget.messageList.length,
      },
    );
    if (mounted) {
      setState(() {});
    }
    _scheduleMessagesFirstVisibleAfterReveal(
      source: 'placeholder_${_openingPlaceholderDismissSource}_removed',
    );
  }

  void _scheduleMessagesFirstVisibleAfterReveal({required String source}) {
    if (_messagesFirstVisibleReported ||
        _messagesFirstVisibleScheduled ||
        !_historyOpenRevealPainted ||
        _openingPlaceholder.shouldPaint) {
      return;
    }
    _messagesFirstVisibleScheduled = true;
    final conversationID = _conversationId();
    final visibleTrace =
        ChatOpenPerfLog.captureCurrent(conversationKey: conversationID);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messagesFirstVisibleScheduled = false;
      if (!mounted ||
          conversationID != _conversationId() ||
          !_historyOpenRevealPainted ||
          _openingPlaceholder.shouldPaint) {
        return;
      }
      final painted = widget.messageList.length;
      if (painted <= 0) {
        return;
      }
      _messagesFirstVisibleReported = true;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      ChatMainThreadPerf.recordDurationMicros(
        ChatMainThreadPerf.messagesFirstVisibleMs,
        (nowMs - _createdAtMs) * Duration.microsecondsPerMillisecond,
        count: painted,
        source: source,
      );
      ChatOpenPerfLog.markMessagesFirstVisible(
        conversationID: conversationID,
        messageCount: painted,
        source: source,
        trace: visibleTrace,
      );
      ChatGeomSettleTrace.markMessagesVisible(
        conversationID: conversationID,
        messageCount: painted,
        source: source,
      );
    });
  }

  void _resetHistoryOpenRevealGate({bool resetPainted = true}) {
    _historyOpenRevealReady = false;
    if (resetPainted) {
      _historyOpenRevealPainted = false;
    }
    _historyOpenRevealPostFrameCount = 0;
    _historyOpenRevealDeadlineMs = null;
    _historyOpenRevealWaitScheduled = false;
    _historyOpenRevealStarveLogged = false;
    _historyOpenRevealMaxPostFrames = 2;
    _historyOpenRevealTimeoutMs = 120;
    _historyOpenRevealStableFrames = 0;
    _historyOpenRevealMeasuredAtMs = null;
    _historyOpenRevealFramesSinceMeasured = 0;
    _historyOpenRevealLastSpacer = null;
    _historyOpenRevealLastContentH = null;
    _historyOpenRevealRowBumpPending = false;
    _historyOpenRevealReadyAtMs = null;
    _historyOpenRevealHoldFrames = 0;
    _historyOpenRevealLastListLen = null;
    _historyOpenRevealLastListRev = null;
    _layoutReadyEpochSigned = -1;
    _layoutReadyEpochSeen = 0;
    _historyOpenRevealLongStableFrames = 0;
    _historyOpenRevealLastMaxExtent = null;
    _historyOpenRevealLongArmAtMs = null;
    _historyOpenRevealLongLoadWaitDeadlineMs = null;
  }

  /// prepare 后二次 begin 会抬 epoch；作废旧代际 ready / 采样并重跑稳定窗。
  void _syncHistoryOpenRevealEpochOrReset() {
    final epoch = ChatHistoryOpenLayoutReady.epochOf(_conversationId());
    if (epoch == 0 || epoch == _layoutReadyEpochSeen) {
      return;
    }
    final hadSigned =
        _layoutReadyEpochSigned >= 0 && _layoutReadyEpochSigned != epoch;
    final softResettle = !hadSigned &&
        (_historyOpenRevealReady ||
            _historyOpenRevealStableFrames > 0 ||
            _historyOpenRevealHoldFrames > 0 ||
            _historyOpenRevealMeasuredAtMs != null ||
            _historyOpenRevealLongArmAtMs != null);
    if (!hadSigned && !softResettle) {
      _layoutReadyEpochSeen = epoch;
      return;
    }
    ChatGeomSettleTrace.noteReason(
      'layout_ready_epoch_reset',
      extras: <String, Object?>{
        'signed': _layoutReadyEpochSigned,
        'seen': _layoutReadyEpochSeen,
        'current': epoch,
        'wasReady': _historyOpenRevealReady,
        'soft': softResettle && !hadSigned,
      },
    );
    _resetHistoryOpenRevealGate(resetPainted: false);
    _layoutReadyEpochSeen = epoch;
    if (!mounted) {
      return;
    }
    final shortCandidate =
        ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled &&
            (_routeScroll.shortHistoryAlignmentLatched ||
                _routeScroll.shortHistoryBottomSpacerHeight > 1 ||
                _mayUseShortHistoryTopAlignment());
    _scheduleHistoryOpenRevealWait(shortHistory: shortCandidate);
  }

  bool _historyOpenRevealWaitExpired() {
    if (_historyOpenRevealPostFrameCount >= _historyOpenRevealMaxPostFrames) {
      return true;
    }
    final deadline = _historyOpenRevealDeadlineMs;
    if (deadline == null) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch >= deadline;
  }

  bool get _isPostRevealMicroSuppressWindow {
    if (!_historyOpenRevealReady) {
      return false;
    }
    final readyAt = _historyOpenRevealReadyAtMs;
    if (readyAt == null) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch - readyAt < 500;
  }

  int _msSinceHistoryOpenRevealReady() {
    final readyAt = _historyOpenRevealReadyAtMs;
    if (readyAt == null) {
      return 0;
    }
    return DateTime.now().millisecondsSinceEpoch - readyAt;
  }

  bool _revealCommitScheduled = false;

  void _commitHistoryOpenRevealReady({
    required String source,
    bool bridgeSignal = true,
  }) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_revealCommitScheduled) return;
      _revealCommitScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealCommitScheduled = false;
        if (!mounted) return;
        setState(() {
          _commitHistoryOpenRevealReady(
            source: source,
            bridgeSignal: bridgeSignal,
          );
        });
      });
      return;
    }
    final canReveal = ChatInitialWindowRevealPolicy.canReveal(
      alreadyPainted: _historyOpenRevealPainted,
      explicitPosition: _isOpeningPlaceholderSearchJump ||
          widget.model.globalModel.hasLockedEntryUnreadFor(_conversationId()),
      completeWindow: _isCompleteCachedOpenWindow(widget.model.globalModel) ||
          (widget.messageList.isEmpty &&
              !_isInitialHistoryBootstrapping(widget.model.globalModel)),
      // Any already available local message can be revealed after layout. The
      // remaining history window is filled after the first frame and keeps its
      // bottom anchor, so cloud completion does not hold the whole route.
      hasMessages: widget.messageList.isNotEmpty,
    );
    if (!canReveal) {
      return;
    }
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.conversation.conversationID,
      userId: widget.conversation.userID,
      groupId: widget.conversation.groupID,
    );
    final readyOffsetMs = ChatPipelineClock.instance.offsetMs(pipelineKey);
    // ignore: avoid_print
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[RevealTrace] reason=commit conv=$pipelineKey '
        'source=$source '
        'alreadyReady=$_historyOpenRevealReady '
        'readyOffsetMs=$readyOffsetMs '
        'bridgeSignal=$bridgeSignal '
        'postFrames=$_historyOpenRevealPostFrameCount '
        'msgCount=${widget.messageList.length}',
      );
    }
    if (_historyOpenRevealReady) {
      _historyOpenRevealPainted = true;
      _scheduleOpeningPlaceholderDismiss(source: source);
      return;
    }
    final epoch = ChatHistoryOpenLayoutReady.epochOf(_conversationId());
    _historyOpenRevealReady = true;
    // Jump while Opacity is still 0 so the first painted frame is already at
    // the latest edge — otherwise smooth pin after reveal looks like content
    // floating up from the bottom.
    if (!_isOpeningPlaceholderSearchJump) {
      _pinScrollToBottomImmediate();
    }
    _historyOpenRevealPainted = true;
    _historyOpenRevealReadyAtMs = DateTime.now().millisecondsSinceEpoch;
    final isLongPath = source.startsWith('long_');
    ChatGeomSettleTrace.noteReason(
      'history_open_reveal_ready',
      extras: <String, Object?>{
        'source': source,
        'postFrames': _historyOpenRevealPostFrameCount,
        if (isLongPath) ...<String, Object?>{
          'longStableFrames': _historyOpenRevealLongStableFrames,
          'lastMaxExtent': _historyOpenRevealLastMaxExtent,
        } else ...<String, Object?>{
          'stableFrames': _historyOpenRevealStableFrames,
          'holdFrames': _historyOpenRevealHoldFrames,
          'framesSinceMeasured': _historyOpenRevealFramesSinceMeasured,
          'measured': _routeScroll.shortHistoryContentHeightMeasured,
          'latched': _routeScroll.shortHistoryAlignmentLatched,
        },
        'openedWithCachedHistory': _routeScroll.openedWithCachedHistory,
        'epoch': epoch,
        'bridgeSignal': bridgeSignal,
      },
    );
    if (bridgeSignal) {
      _layoutReadyEpochSigned = epoch;
      ChatHistoryOpenLayoutReady.signal(_conversationId(), epoch: epoch);
    }
    _scheduleOpeningPlaceholderDismiss(source: 'history_open_reveal_$source');
  }

  void _armHistoryOpenRevealWaitBudget({required bool shortHistory}) {
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.conversation.conversationID,
      userId: widget.conversation.userID,
      groupId: widget.conversation.groupID,
    );
    final armOffsetMs = ChatPipelineClock.instance.offsetMs(pipelineKey);
    if (shortHistory) {
      // 仅用于「测前」starve 诊断，绝不据此强制 reveal。
      _historyOpenRevealMaxPostFrames = 45;
      _historyOpenRevealTimeoutMs = 1500;
    } else {
      // 长历史：maxExtent 稳定 / 400ms 软超时，不再用 2 帧骗开整页。
      _historyOpenRevealMaxPostFrames = 48;
      _historyOpenRevealTimeoutMs = 400;
    }
    _historyOpenRevealDeadlineMs ??=
        DateTime.now().millisecondsSinceEpoch + _historyOpenRevealTimeoutMs;
    // ignore: avoid_print
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[RevealTrace] reason=arm conv=$pipelineKey '
        'shortHistory=$shortHistory '
        'maxPostFrames=$_historyOpenRevealMaxPostFrames '
        'timeoutMs=$_historyOpenRevealTimeoutMs '
        'hardCapMs=1500 '
        'armOffsetMs=$armOffsetMs '
        'msgCount=${widget.messageList.length} '
        'hasContentDimensions=${_singleScrollPositionOrNull()?.hasContentDimensions} '
        'alreadyReady=$_historyOpenRevealReady',
      );
    }
    // B1：post-frame 链中断保护 - 注册 100ms 周期的 watchdog 兜底定时器。
    // 历史问题：链式 addPostFrameCallback 递归如果某次回调丢失，
    // 整条 reveal gate 链停摆，连软超时都不触发（pch7hqqolk 走 6.7s 才到 commit）。
    // 这里加 watchdog：
    // 1. elapsed >= 1500ms → 强制 commit `source: 'watchdog_hard_cap'`
    // 2. _historyOpenRevealWaitScheduled=false → 重新调度（unstick 死链）
    _historyOpenRevealWatchdogTimer?.cancel();
    _historyOpenRevealWatchdogTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!mounted || _historyOpenRevealReady) {
          _historyOpenRevealWatchdogTimer?.cancel();
          _historyOpenRevealWatchdogTimer = null;
          return;
        }
        final armedAt = _historyOpenRevealLongArmAtMs;
        if (armedAt == null) {
          return;
        }
        final elapsed = DateTime.now().millisecondsSinceEpoch - armedAt;
        final watchdogKey = ChatPipelineClock.normalizeKey(
          rawConversationId: widget.conversation.conversationID,
          userId: widget.conversation.userID,
          groupId: widget.conversation.groupID,
        );
        final tickOffsetMs = ChatPipelineClock.instance.offsetMs(watchdogKey);
        if (elapsed >= 1500) {
          // ignore: avoid_print
          if (ChatHistoryTrace.enabled) {
            debugPrint(
              '[RevealTrace] reason=watchdog_hard_cap conv=$watchdogKey '
              'elapsedMs=$elapsed '
              'waitScheduled=$_historyOpenRevealWaitScheduled '
              'tickOffsetMs=$tickOffsetMs '
              'msgCount=${widget.messageList.length}',
            );
          }
          // A timer can fire after the route has stopped producing frames.
          // Rebuild the visibility wrapper even when no placeholder is fading.
          setState(() {
            _commitHistoryOpenRevealReady(source: 'watchdog_hard_cap');
          });
          _historyOpenRevealWatchdogTimer?.cancel();
          _historyOpenRevealWatchdogTimer = null;
          return;
        }
        if (!_historyOpenRevealWaitScheduled) {
          // ignore: avoid_print
          if (ChatHistoryTrace.enabled) {
            debugPrint(
              '[RevealTrace] reason=watchdog_unstick conv=$watchdogKey '
              'elapsedMs=$elapsed '
              'tickOffsetMs=$tickOffsetMs '
              'msgCount=${widget.messageList.length}',
            );
          }
          _scheduleHistoryOpenRevealWait(shortHistory: shortHistory);
        }
      },
    );
  }

  void _noteShortHistoryRevealMeasureStarve() {
    if (_historyOpenRevealStarveLogged) {
      return;
    }
    _historyOpenRevealStarveLogged = true;
    ChatGeomSettleTrace.noteReason(
      'short_reveal_measure_starve',
      extras: <String, Object?>{
        'postFrames': _historyOpenRevealPostFrameCount,
        'measured': _routeScroll.shortHistoryContentHeightMeasured,
        'latched': _routeScroll.shortHistoryAlignmentLatched,
        'spacer': _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(
          1,
        ),
        'contentH': _routeScroll.shortHistoryContentHeight.toStringAsFixed(1),
      },
    );
  }

  void _onShortHistoryFirstMeasured() {
    _historyOpenRevealMeasuredAtMs ??= DateTime.now().millisecondsSinceEpoch;
    _historyOpenRevealStableFrames = 0;
    _historyOpenRevealHoldFrames = 0;
    _historyOpenRevealFramesSinceMeasured = 0;
    _historyOpenRevealLastSpacer = null;
    _historyOpenRevealLastContentH = null;
    _historyOpenRevealLastListLen = null;
    _historyOpenRevealLastListRev = null;
    _historyOpenRevealRowBumpPending = false;
    _scheduleHistoryOpenRevealWait(shortHistory: true);
  }

  void _noteShortHistoryRowHeightBumpForReveal(double delta) {
    if (_historyOpenRevealReady || delta.abs() < 8) {
      return;
    }
    _historyOpenRevealRowBumpPending = true;
    _historyOpenRevealStableFrames = 0;
    _historyOpenRevealHoldFrames = 0;
  }

  void _noteShortHistoryListIdentityForReveal() {
    if (_historyOpenRevealReady) {
      return;
    }
    final len = widget.messageList.length;
    final rev = widget.model.globalModel.messageListRevisionFor(
      _conversationId(),
    );
    final lenChanged = _historyOpenRevealLastListLen != null &&
        _historyOpenRevealLastListLen != len;
    final revChanged = _historyOpenRevealLastListRev != null &&
        _historyOpenRevealLastListRev != rev;
    if (lenChanged || revChanged) {
      _historyOpenRevealStableFrames = 0;
      _historyOpenRevealHoldFrames = 0;
      _historyOpenRevealLastSpacer = null;
      _historyOpenRevealLastContentH = null;
    }
    _historyOpenRevealLastListLen = len;
    _historyOpenRevealLastListRev = rev;
  }

  bool _tickShortHistoryRevealStableWindow() {
    _noteShortHistoryListIdentityForReveal();
    final spacer = _routeScroll.shortHistoryBottomSpacerHeight;
    final contentH = _routeScroll.shortHistoryContentHeight;
    if (_historyOpenRevealRowBumpPending) {
      _historyOpenRevealStableFrames = 0;
      _historyOpenRevealHoldFrames = 0;
      _historyOpenRevealRowBumpPending = false;
    } else if (_historyOpenRevealLastSpacer != null &&
        _historyOpenRevealLastContentH != null) {
      final dSpacer = (spacer - _historyOpenRevealLastSpacer!).abs();
      final dContentH = (contentH - _historyOpenRevealLastContentH!).abs();
      if (dSpacer > 1 || dContentH > 1) {
        _historyOpenRevealStableFrames = 0;
        _historyOpenRevealHoldFrames = 0;
      } else {
        _historyOpenRevealStableFrames++;
      }
    } else {
      _historyOpenRevealStableFrames = 0;
      _historyOpenRevealHoldFrames = 0;
    }
    _historyOpenRevealLastSpacer = spacer;
    _historyOpenRevealLastContentH = contentH;
    final reached = _historyOpenRevealStableFrames >= 2;
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.conversation.conversationID,
      userId: widget.conversation.userID,
      groupId: widget.conversation.groupID,
    );
    final tickOffsetMs = ChatPipelineClock.instance.offsetMs(pipelineKey);
    // ignore: avoid_print
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[RevealTrace] reason=short_hold_tick conv=$pipelineKey '
        'holdFrames=$_historyOpenRevealHoldFrames '
        'stableFrames=$_historyOpenRevealStableFrames/2 '
        'reached=$reached '
        'spacerHeight=${spacer.toStringAsFixed(1)} '
        'contentHeight=${contentH.toStringAsFixed(1)} '
        'tickOffsetMs=$tickOffsetMs '
        'msgCount=${widget.messageList.length}',
      );
    }
    return reached;
  }

  bool _shortHistoryRevealStableTimedOut() {
    final measuredAt = _historyOpenRevealMeasuredAtMs;
    if (measuredAt == null) {
      return false;
    }
    if (_historyOpenRevealFramesSinceMeasured >= 8) {
      return true;
    }
    return DateTime.now().millisecondsSinceEpoch - measuredAt >= 250;
  }

  bool _isHistoryOpenPreviousLoadInFlight() {
    return _paginationUi.isLoadingPrevious ||
        _paginationUi.loadPreviousTask != null;
  }

  void _noteLongHistoryListIdentityForReveal() {
    if (_historyOpenRevealReady) {
      return;
    }
    final len = widget.messageList.length;
    final rev = widget.model.globalModel.messageListRevisionFor(
      _conversationId(),
    );
    final lenChanged = _historyOpenRevealLastListLen != null &&
        _historyOpenRevealLastListLen != len;
    final revChanged = _historyOpenRevealLastListRev != null &&
        _historyOpenRevealLastListRev != rev;
    if (lenChanged || revChanged) {
      _historyOpenRevealLongStableFrames = 0;
      _historyOpenRevealLastMaxExtent = null;
    }
    _historyOpenRevealLastListLen = len;
    _historyOpenRevealLastListRev = rev;
  }

  bool _tickLongHistoryExtentStableWindow() {
    _noteLongHistoryListIdentityForReveal();
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.conversation.conversationID,
      userId: widget.conversation.userID,
      groupId: widget.conversation.groupID,
    );
    final position0 = _singleScrollPositionOrNull();
    final maxE0 = position0?.maxScrollExtent;
    final tickOffsetMs = ChatPipelineClock.instance.offsetMs(pipelineKey);
    if (_isHistoryOpenPreviousLoadInFlight()) {
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[RevealTrace] reason=long_extent_tick conv=$pipelineKey '
          'lastMaxExtent=$_historyOpenRevealLastMaxExtent '
          'currentMaxExtent=$maxE0 '
          'delta=load_in_flight '
          'stableFrames=$_historyOpenRevealLongStableFrames/2 '
          'tickOffsetMs=$tickOffsetMs '
          'msgCount=${widget.messageList.length}',
        );
      }
      _historyOpenRevealLongStableFrames = 0;
      _historyOpenRevealLastMaxExtent = null;
      return false;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null || !position.hasContentDimensions) {
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[RevealTrace] reason=long_extent_tick conv=$pipelineKey '
          'lastMaxExtent=$_historyOpenRevealLastMaxExtent '
          'currentMaxExtent=null '
          'delta=no_content_dims '
          'stableFrames=$_historyOpenRevealLongStableFrames/2 '
          'tickOffsetMs=$tickOffsetMs '
          'msgCount=${widget.messageList.length}',
        );
      }
      _historyOpenRevealLongStableFrames = 0;
      _historyOpenRevealLastMaxExtent = null;
      return false;
    }
    final maxExtent = position.maxScrollExtent;
    // 贴底短内容：maxExtent≈0 对「已确认的短会话」是正常态。
    // 未灌满的预热窗绝不能据此揭开，否则会先看到底部几条、上半空白。
    if (widget.messageList.isNotEmpty &&
        maxExtent <= 1 &&
        !ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      final globalModel0 = widget.model.globalModel;
      final convId0 = _conversationId();
      final rawCount0 = globalModel0.rawMessageCount(convId0);
      final mayHaveOlder0 = globalModel0.mayHaveOlderHistory(convId0);
      // A1：模型明确无更多历史 + 已有消息 → 视为稳定，1 帧后立即 commit。
      // 场景：少消息会话（1-6 条），maxExtent≈0，永远稳定不了 maxExtent。
      // 修复前：等 400ms 软超时（pch7hqqolk 走 6.7s 是因为 post-frame 链中断）。
      // 修复后：1 帧后 stable=2/2 立即 commit。
      if (rawCount0 == widget.messageList.length && !mayHaveOlder0) {
        final pipelineKeyA1 = ChatPipelineClock.normalizeKey(
          rawConversationId: widget.conversation.conversationID,
          userId: widget.conversation.userID,
          groupId: widget.conversation.groupID,
        );
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[RevealTrace] reason=long_short_content_model_exhausted conv=$pipelineKeyA1 '
            'rawCount=$rawCount0 '
            'msgCount=${widget.messageList.length} '
            'mayHaveOlder=$mayHaveOlder0 '
            'tickOffsetMs=${ChatPipelineClock.instance.offsetMs(pipelineKeyA1)}',
          );
        }
        _historyOpenRevealLastMaxExtent = maxExtent;
        _historyOpenRevealLongStableFrames++;
        return _historyOpenRevealLongStableFrames >= 2;
      }
      if (!_isCompleteCachedOpenWindow(globalModel0)) {
        _historyOpenRevealLongStableFrames = 0;
        _historyOpenRevealLastMaxExtent = maxExtent;
        return false;
      }
      _historyOpenRevealLastMaxExtent = maxExtent;
      _historyOpenRevealLongStableFrames++;
      return _historyOpenRevealLongStableFrames >= 2;
    }
    // 有消息但尚未形成可滚范围：extent=0 不得冒充稳定。
    if (widget.messageList.isNotEmpty && maxExtent <= 1) {
      _historyOpenRevealLongStableFrames = 0;
      _historyOpenRevealLastMaxExtent = maxExtent;
      return false;
    }
    if (_historyOpenRevealLastMaxExtent != null) {
      final delta = (maxExtent - _historyOpenRevealLastMaxExtent!).abs();
      if (delta > 1) {
        _historyOpenRevealLongStableFrames = 0;
      } else {
        _historyOpenRevealLongStableFrames++;
      }
    } else {
      _historyOpenRevealLongStableFrames = 0;
    }
    _historyOpenRevealLastMaxExtent = maxExtent;
    final reached = _historyOpenRevealLongStableFrames >= 2;
    // ignore: avoid_print
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[RevealTrace] reason=long_extent_stable_progress conv=$pipelineKey '
        'lastMaxExtent=${_historyOpenRevealLastMaxExtent} '
        'currentMaxExtent=$maxExtent '
        'stableFrames=$_historyOpenRevealLongStableFrames/2 '
        'reached=$reached '
        'tickOffsetMs=$tickOffsetMs '
        'msgCount=${widget.messageList.length}',
      );
    }
    return reached;
  }

  bool _longHistoryRevealSoftTimedOut() {
    final armedAt = _historyOpenRevealLongArmAtMs;
    if (armedAt == null) {
      return false;
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - armedAt;
    final position = _singleScrollPositionOrNull();
    final underfilled = position != null &&
        position.hasContentDimensions &&
        position.maxScrollExtent <= 1 &&
        !_isCompleteCachedOpenWindow(widget.model.globalModel);
    final threshold = underfilled ? 1200 : 400;
    final reached = elapsed >= threshold;
    if (reached) {
      final pipelineKey = ChatPipelineClock.normalizeKey(
        rawConversationId: widget.conversation.conversationID,
        userId: widget.conversation.userID,
        groupId: widget.conversation.groupID,
      );
      final tickOffsetMs = ChatPipelineClock.instance.offsetMs(pipelineKey);
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[RevealTrace] reason=long_soft_timeout_check conv=$pipelineKey '
          'elapsedMs=$elapsed '
          'sinceArm=$elapsed '
          'loadPreviousInFlight=${_paginationUi.isLoadingPrevious || _paginationUi.loadPreviousTask != null} '
          'underfilled=$underfilled '
          'thresholdMs=$threshold '
          'tickOffsetMs=$tickOffsetMs '
          'msgCount=${widget.messageList.length}',
        );
      }
    }
    return reached;
  }

  bool _longHistoryRevealLoadWaitTimedOut() {
    final deadline = _historyOpenRevealLongLoadWaitDeadlineMs;
    if (deadline == null) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch >= deadline;
  }

  void _scheduleHistoryOpenRevealWait({required bool shortHistory}) {
    _armHistoryOpenRevealWaitBudget(shortHistory: shortHistory);
    if (_historyOpenRevealWaitScheduled || _historyOpenRevealReady) {
      return;
    }
    _historyOpenRevealWaitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyOpenRevealWaitScheduled = false;
      if (!mounted) {
        return;
      }
      _syncHistoryOpenRevealEpochOrReset();
      if (_historyOpenRevealReady) {
        return;
      }
      _historyOpenRevealPostFrameCount++;
      // A complete window arriving during the transition can use the same
      // bottom-aligned fast path as a window present at initState. The commit
      // pins the scroll position before revealing the real message tree.
      final position = _singleScrollPositionOrNull();
      if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled &&
          !_isOpeningPlaceholderSearchJump &&
          !widget.model.globalModel
              .hasLockedEntryUnreadFor(_conversationId()) &&
          widget.messageList.isNotEmpty &&
          _isCompleteCachedOpenWindow(widget.model.globalModel) &&
          position != null &&
          position.hasContentDimensions &&
          !_isHistoryOpenPreviousLoadInFlight()) {
        setState(() {
          _commitHistoryOpenRevealReady(source: 'complete_window_first_layout');
        });
        return;
      }
      if (shortHistory) {
        // 顶对齐总闸关闭时禁止走 short latch/测高等待，否则会在
        // !latchedOrSpaced / !measured 分支里无限续等，Opacity=0 永久空白。
        if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
          _scheduleHistoryOpenRevealWait(shortHistory: false);
          return;
        }
        final measured = _routeScroll.shortHistoryContentHeightMeasured;
        final latchedOrSpaced = _routeScroll.shortHistoryAlignmentLatched ||
            _routeScroll.shortHistoryBottomSpacerHeight > 1;
        if (!measured) {
          if (_historyOpenRevealWaitExpired()) {
            _noteShortHistoryRevealMeasureStarve();
            // 测高饿死时强制揭开，避免会话页永久透明。
            setState(() {
              _commitHistoryOpenRevealReady(source: 'short_measure_starve');
            });
            return;
          }
          _scheduleHistoryOpenRevealWait(shortHistory: true);
          return;
        }
        if (!latchedOrSpaced) {
          // 已测高但未 latch：改走长历史揭示，禁止空转。
          _scheduleHistoryOpenRevealWait(shortHistory: false);
          return;
        }
        _historyOpenRevealMeasuredAtMs ??=
            DateTime.now().millisecondsSinceEpoch;
        _historyOpenRevealFramesSinceMeasured++;
        final stable = _tickShortHistoryRevealStableWindow();
        if (stable) {
          _historyOpenRevealHoldFrames++;
          if (_historyOpenRevealHoldFrames >= 2) {
            setState(() {
              _commitHistoryOpenRevealReady(source: 'short_stable_hold');
            });
            return;
          }
          _scheduleHistoryOpenRevealWait(shortHistory: true);
          return;
        }
        if (_shortHistoryRevealStableTimedOut()) {
          if (_historyOpenRevealHoldFrames < 1) {
            _historyOpenRevealHoldFrames++;
            _scheduleHistoryOpenRevealWait(shortHistory: true);
            return;
          }
          setState(() {
            _commitHistoryOpenRevealReady(source: 'short_stable_timeout');
          });
          return;
        }
        _scheduleHistoryOpenRevealWait(shortHistory: true);
        return;
      }
      _historyOpenRevealLongArmAtMs ??= DateTime.now().millisecondsSinceEpoch;
      final longArmAtMs = _historyOpenRevealLongArmAtMs ?? 0;
      final elapsedSinceArm =
          DateTime.now().millisecondsSinceEpoch - longArmAtMs;
      // C1：放宽 early reveal 触发条件。
      // 历史问题：placeholderVisible=false（骨架屏从未进入 visible 阶段）
      //           导致 250ms early reveal 永远不触发。
      // 修复后：消息非空 + 200ms 已等 + 短内容（maxExtent≤1）+ 不在加载 → 立即 commit。
      final earlyRevealMaxExtent =
          _singleScrollPositionOrNull()?.maxScrollExtent ?? 0.0;
      final earlyRevealLoading = _paginationUi.isLoadingPrevious ||
          _paginationUi.loadPreviousTask != null;
      final earlyRevealCondition = widget.messageList.isNotEmpty &&
          _singleScrollPositionOrNull()?.hasContentDimensions == true &&
          elapsedSinceArm >= 50 &&
          earlyRevealMaxExtent <= 1 &&
          !earlyRevealLoading;
      final earlyRevealKey = ChatPipelineClock.normalizeKey(
        rawConversationId: widget.conversation.conversationID,
        userId: widget.conversation.userID,
        groupId: widget.conversation.groupID,
      );
      final earlyRevealTickOffsetMs =
          ChatPipelineClock.instance.offsetMs(earlyRevealKey);
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[RevealTrace] reason=long_early_reveal_check conv=$earlyRevealKey '
          'elapsedMs=$elapsedSinceArm '
          'placeholderVisible=${_openingPlaceholder.phase == ChatHistoryOpeningPlaceholderPhase.visible} '
          'messagesNonEmpty=${widget.messageList.isNotEmpty} '
          'maxExtent=$earlyRevealMaxExtent '
          'loadingPrevious=$earlyRevealLoading '
          'conditionMet=$earlyRevealCondition '
          'tickOffsetMs=$earlyRevealTickOffsetMs '
          'msgCount=${widget.messageList.length}',
        );
      }
      // C1：Early reveal gate (P-1)。
      // 历史 P-1：placeholderVisible + 250ms - 永远不触发（骨架屏不进入 visible）。
      // 修复后：短内容（maxExtent≤1）+ 200ms + 不在加载 → 立即 commit。
      // 完整缓存窗口走 opened_with_cache_* 路径不进这里。
      if (earlyRevealCondition) {
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[RevealTrace] reason=long_early_reveal_50ms conv=$earlyRevealKey '
            'msgCount=${widget.messageList.length} '
            'maxExtent=$earlyRevealMaxExtent '
            'tickOffsetMs=$earlyRevealTickOffsetMs',
          );
        }
        setState(() {
          _commitHistoryOpenRevealReady(source: 'long_early_reveal_50ms');
        });
        return;
      }
      if (_tickLongHistoryExtentStableWindow()) {
        setState(() {
          _commitHistoryOpenRevealReady(source: 'long_extent_stable');
        });
        return;
      }
      if (_longHistoryRevealSoftTimedOut()) {
        if (_isHistoryOpenPreviousLoadInFlight()) {
          _historyOpenRevealLongLoadWaitDeadlineMs ??=
              DateTime.now().millisecondsSinceEpoch + 300;
          if (!_longHistoryRevealLoadWaitTimedOut()) {
            ChatGeomSettleTrace.noteReason(
              'long_stable_timeout_wait_load',
              extras: <String, Object?>{
                'loadingPrevious': _paginationUi.isLoadingPrevious,
                'taskInFlight': _paginationUi.loadPreviousTask != null,
              },
            );
            _scheduleHistoryOpenRevealWait(shortHistory: false);
            return;
          }
        }
        setState(() {
          _commitHistoryOpenRevealReady(source: 'long_stable_timeout');
        });
        return;
      }
      // Hard cap (P-2): arm 后 1500ms 兜底强制 reveal。
      // 视频分析显示 o807qs2xe0 在 maxExtent 持续 reset + loadPrevious 在飞时
      // 灰色骨架屏停留 3.5s，必须兜底。
      final armedAtHard = _historyOpenRevealLongArmAtMs;
      if (armedAtHard != null &&
          DateTime.now().millisecondsSinceEpoch - armedAtHard >= 1500) {
        final pipelineKey = ChatPipelineClock.normalizeKey(
          rawConversationId: widget.conversation.conversationID,
          userId: widget.conversation.userID,
          groupId: widget.conversation.groupID,
        );
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[RevealTrace] reason=long_hard_cap_1500ms conv=$pipelineKey '
            'msgCount=${widget.messageList.length} '
            'loadingPrevious=${_paginationUi.isLoadingPrevious} '
            'taskInFlight=${_paginationUi.loadPreviousTask != null} '
            'stableFrames=$_historyOpenRevealLongStableFrames',
          );
        }
        setState(() {
          _commitHistoryOpenRevealReady(source: 'long_hard_cap_1500ms');
        });
        return;
      }
      _scheduleHistoryOpenRevealWait(shortHistory: false);
    });
    // Post-frame callbacks do not request a frame themselves. Keep the
    // geometry checks moving after the route transition has gone idle.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 统一揭示门：短历史测后稳定+hold；长历史 maxExtent 稳定；空会话确认后放行。
  /// 暖窗若已有会话实测 contentH 会在 initState ready；否则仍走本路径。
  bool _evaluateHistoryOpenReveal({
    required List<V2TimMessage?> messageList,
    required double viewportHeight,
  }) {
    _syncHistoryOpenRevealEpochOrReset();
    if (_historyOpenRevealReady) {
      return true;
    }
    if (viewportHeight <= 0) {
      return false;
    }
    if (messageList.isEmpty) {
      final globalModel = widget.model.globalModel;
      if (!_isInitialHistoryBootstrapping(globalModel)) {
        _commitHistoryOpenRevealReady(source: 'empty_history');
        return _historyOpenRevealReady;
      }
      return false;
    }

    final shortCandidate =
        ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled &&
            (_routeScroll.shortHistoryAlignmentLatched ||
                _routeScroll.shortHistoryBottomSpacerHeight > 1 ||
                _mayUseShortHistoryTopAlignment());

    if (shortCandidate) {
      if (_routeScroll.shortHistoryContentHeightMeasured &&
          (_routeScroll.shortHistoryAlignmentLatched ||
              _routeScroll.shortHistoryBottomSpacerHeight > 1)) {
        _historyOpenRevealMeasuredAtMs ??=
            DateTime.now().millisecondsSinceEpoch;
      }
      _armHistoryOpenRevealWaitBudget(shortHistory: true);
      if (!_routeScroll.shortHistoryContentHeightMeasured &&
          _historyOpenRevealWaitExpired()) {
        _noteShortHistoryRevealMeasureStarve();
      }
      _scheduleHistoryOpenRevealWait(shortHistory: true);
      return false;
    }

    _armHistoryOpenRevealWaitBudget(shortHistory: false);
    _historyOpenRevealLongArmAtMs ??= DateTime.now().millisecondsSinceEpoch;
    _scheduleHistoryOpenRevealWait(shortHistory: false);
    return false;
  }

  void _bindSeparateModelListener() {
    if (_boundSeparateModel == widget.model) {
      return;
    }
    _boundSeparateModel?.removeListener(_onSeparateModelUpdated);
    _boundSeparateModel = widget.model;
    _lastSeparateListRelevantEpoch = _separateListRelevantEpoch(widget.model);
    _boundSeparateModel?.addListener(_onSeparateModelUpdated);
  }

  /// 仅当「列表本身」相关状态变化时才整表 setState。
  /// selfMemberInfo / groupInfo / 禁言等变更不应在进场时掀翻消息列表。
  int _separateListRelevantEpoch(TUIChatSeparateViewModel model) {
    // 暖窗已在屏上时，进页 settle 内 loading/haveMore 抖动不必掀翻列表；
    // 日志里一次打开可出现十余次 separate_model_set_state。
    final multiSelectRevision = model.chatUiStateStore.modeRevision(
      model.conversationID,
    );
    if (_routeScroll.openedWithCachedHistory && _isInitialRouteSettleWindow) {
      return Object.hash(
        model.historyLoadNoticeRevision,
        model.historyReadingWindowRevision,
        model.jumpMsgID,
        model.isMultiSelect,
        multiSelectRevision,
      );
    }
    return Object.hash(
      model.isLoadingChatHistory,
      model.haveMoreData,
      model.haveMoreLatestData,
      model.historyLoadNoticeRevision,
      model.historyReadingWindowRevision,
      model.jumpMsgID,
      model.isMultiSelect,
      multiSelectRevision,
    );
  }

  int _lastSeparateListRelevantEpoch = -1;

  void _onSeparateModelUpdated() {
    if (!mounted) {
      return;
    }
    if (_previousLoadWindowIsCurrent?.call() == false) {
      _invalidatePreviousPagination();
      _syncTopHistoryLoadingVisible();
    }
    _scheduleVisibleLatestConfirmation();
    final epoch = _separateListRelevantEpoch(widget.model);
    if (epoch == _lastSeparateListRelevantEpoch) {
      ChatJitterDiag.log(
        'separate_model_skip',
        extras: <String, Object?>{
          'reason': 'list_irrelevant',
          'loading': widget.model.isLoadingChatHistory,
        },
      );
      return;
    }
    _lastSeparateListRelevantEpoch = epoch;
    ChatJitterDiag.log(
      'separate_model_set_state',
      extras: <String, Object?>{
        'loading': widget.model.isLoadingChatHistory,
        'haveMore': widget.model.haveMoreData,
        'jump': widget.model.jumpMsgID,
      },
    );
    setState(() {});
  }

  /// 首屏进页阶段的历史加载一律静默：暖窗已出列表时后台 hydrate 不盖转圈，
  /// 空列表也不用全屏 spinner 挡（直接空态等数据）。
  bool _shouldSilenceInitialHistoryLoading(TUIChatGlobalModel globalModel) {
    if (!globalModel.hasInitialHistoryLoaded(_conversationId())) {
      return true;
    }
    // 有暖缓存时进页后 hydrate 仍会短暂 isLoadingChatHistory；
    // 前 2.5s 内不显示居中/全屏转圈，避免「闪一下转圈又没了」。
    if (_routeScroll.openedWithCachedHistory &&
        DateTime.now().millisecondsSinceEpoch - _createdAtMs < 2500) {
      return true;
    }
    return false;
  }

  bool _shouldShowCenterHistoryLoading({
    required bool isLoadingHistory,
    required List<V2TimMessage?> messageList,
    required int effectiveUnreadNewMessageCount,
    required int loadedRealMessageCount,
    required TUIChatGlobalModel globalModel,
  }) {
    if (globalModel.isUserScrollToBottomInProgress(_conversationId())) {
      return false;
    }
    if (!isLoadingHistory) {
      return false;
    }
    if (_shouldSilenceInitialHistoryLoading(globalModel)) {
      return false;
    }
    if (messageList.isEmpty) {
      return true;
    }
    return effectiveUnreadNewMessageCount >=
            UnreadTonguePolicy.groupMinUnreadCount &&
        UnreadTonguePolicy.entryUnreadTongueEnabled &&
        loadedRealMessageCount < effectiveUnreadNewMessageCount;
  }

  Widget _buildCenterHistoryLoadingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: _buildHistoryLoadingSpinner(size: 36, strokeWidth: 3),
        ),
      ),
    );
  }

  Widget _buildHistoryLoadNotice(String notice) {
    return Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCC333333),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                notice,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const Color _historyLoadingSpinnerColor = Color(0xFF007AFF);

  Widget _buildHistoryLoadingSpinner({
    double size = 22,
    double strokeWidth = 2.5,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: _historyLoadingSpinnerColor,
      ),
    );
  }

  bool get _paginationPrependRevealActive =>
      _paginationUi.paginationPrependRevealPending &&
      !_paginationUi.silentTopHistoryLoading;

  bool _shouldHideMessageDuringPaginationPrependReveal(int? globalIndex) {
    if (!_paginationPrependRevealActive || globalIndex == null) {
      return false;
    }
    final fromIndex = _paginationUi.paginationPrependRevealFromGlobalIndex;
    return fromIndex > 0 && globalIndex >= fromIndex;
  }

  void _beginPaginationPrependReveal({
    required int listLenBefore,
    required bool nearTopLoad,
  }) {
    _paginationUi.paginationPrependRevealPending = false;
    _paginationUi.paginationPrependRevealFromGlobalIndex = 0;
    if (!nearTopLoad || _paginationUi.silentTopHistoryLoading) {
      return;
    }
    final insertCount = _rawMessageCount() - listLenBefore;
    if (insertCount <= 0 || listLenBefore <= 0) {
      return;
    }
    _paginationUi.paginationPrependRevealPending = true;
    _paginationUi.paginationPrependRevealFromGlobalIndex = listLenBefore;
    ChatHistoryTrace.log(
      'load_previous_prepend_reveal_arm',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'listLenBefore': listLenBefore,
        'listLenAfter': _rawMessageCount(),
        'fromGlobalIndex': listLenBefore,
      },
    );
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || !_paginationUi.paginationPrependRevealPending) {
        return;
      }
      ChatHistoryTrace.log(
        'load_previous_prepend_reveal_fallback',
        conversationID: _conversationId(),
      );
      _commitPaginationPrependReveal();
    });
  }

  void _commitPaginationPrependReveal({bool notify = true}) {
    if (!_paginationUi.paginationPrependRevealPending) {
      return;
    }
    _paginationUi.paginationPrependRevealPending = false;
    _paginationUi.paginationPrependRevealFromGlobalIndex = 0;
    _clearTopHistoryLoading(notify: false);
    ChatHistoryTrace.log(
      'load_previous_prepend_reveal_commit',
      conversationID: _conversationId(),
    );
    if (notify && mounted) {
      setState(() {});
    }
  }

  void _cancelPaginationPrependReveal({bool notify = true}) {
    if (!_paginationUi.paginationPrependRevealPending) {
      return;
    }
    _paginationUi.paginationPrependRevealPending = false;
    _paginationUi.paginationPrependRevealFromGlobalIndex = 0;
    if (notify && mounted) {
      setState(() {});
    }
  }

  bool get _shouldShowTopHistoryLoading {
    // Returning to latest is represented by the list motion itself. A top
    // spinner competes with that action and makes the scroll feel blocked.
    if (widget.model.globalModel
        .isUserScrollToBottomInProgress(_conversationId())) {
      return false;
    }
    // 首屏静默补拉：仍走 loadPrevious，但不渲染顶部转圈。
    if (_paginationUi.silentTopHistoryLoading) {
      return false;
    }
    if (_paginationPrependRevealActive) {
      return true;
    }
    if (_paginationUi.isLoadingPrevious ||
        _previousLoadQueue.isAdmitted ||
        loadingPlace == LoadingPlace.top) {
      return true;
    }
    if (_paginationUi.topHistoryLoadingShownAtMs <= 0) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch -
            _paginationUi.topHistoryLoadingShownAtMs <
        _minTopHistoryLoadingVisibleMs;
  }

  void _syncTopHistoryLoadingVisible() {
    final next = _shouldShowTopHistoryLoading;
    if (_topHistoryLoadingVisible.value == next) {
      return;
    }
    _topHistoryLoadingVisible.value = next;
  }

  void _promotePreviousLoadSpinnerIfNearTop(ScrollMetrics metrics) {
    if (!_paginationUi.silentTopHistoryLoading) {
      return;
    }
    if (!_paginationUi.isLoadingPrevious &&
        _paginationUi.loadPreviousTask == null) {
      return;
    }
    if (_isOverscrollingPastTop(metrics)) {
      return;
    }
    if (!HistoryPreviousPrefetchPolicy.shouldShowPreviousLoadSpinner(
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      hasPixels: metrics.hasPixels,
      hasContentDimensions: metrics.hasContentDimensions,
    )) {
      return;
    }
    _paginationUi.silentTopHistoryLoading = false;
    if (loadingPlace != LoadingPlace.top) {
      loadingPlace = LoadingPlace.top;
      _paginationUi.topHistoryLoadingShownAtMs =
          DateTime.now().millisecondsSinceEpoch;
    }
    _syncTopHistoryLoadingVisible();
  }

  void _scheduleMinTopHistoryLoadingHold() {
    final shownAt = _paginationUi.topHistoryLoadingShownAtMs;
    if (shownAt <= 0) {
      return;
    }
    final remain = _minTopHistoryLoadingVisibleMs -
        (DateTime.now().millisecondsSinceEpoch - shownAt);
    if (remain <= 0) {
      _paginationUi.topHistoryLoadingShownAtMs = 0;
      _syncTopHistoryLoadingVisible();
      return;
    }
    Future<void>.delayed(Duration(milliseconds: remain), () {
      if (!mounted) {
        return;
      }
      _paginationUi.topHistoryLoadingShownAtMs = 0;
      _syncTopHistoryLoadingVisible();
    });
  }

  Widget _buildTopHistoryLoadingIndicator({double size = 22}) {
    return _buildHistoryLoadingSpinner(size: size);
  }

  void _clearTopHistoryLoading({bool notify = true}) {
    _paginationUi.silentTopHistoryLoading = false;
    if (loadingPlace == LoadingPlace.top) {
      loadingPlace = LoadingPlace.none;
    }
    if (_paginationUi.topHistoryLoadingShownAtMs > 0 &&
        DateTime.now().millisecondsSinceEpoch -
                _paginationUi.topHistoryLoadingShownAtMs >=
            _minTopHistoryLoadingVisibleMs) {
      _paginationUi.topHistoryLoadingShownAtMs = 0;
    }
    if (notify) {
      _syncTopHistoryLoadingVisible();
    }
  }

  void _markTopHistoryLoadingScheduled({bool silent = false}) {
    _paginationUi.silentTopHistoryLoading = silent;
    if (silent) {
      // 静默：不占 loadingPlace、不记最短可见时间，避免闪一下转圈。
      _syncTopHistoryLoadingVisible();
      return;
    }
    loadingPlace = LoadingPlace.top;
    _paginationUi.topHistoryLoadingShownAtMs =
        DateTime.now().millisecondsSinceEpoch;
    _syncTopHistoryLoadingVisible();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) {
      _historyWindowTrimUi.cancel();
      _historyWindowTrimIdleTimer?.cancel();
      _historyWindowTrimIdleTimer = null;
    } else {
      _scheduleHistoryWindowTrim();
    }
    final nextModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    _chatGlobalModel = nextModel;
    _scheduleSeenLiveIncomingInViewport();
    if (_routeScroll.routeRestoreGlobalModel == nextModel) {
      return;
    }
    _routeScroll.routeRestoreGlobalModel?.removeListener(_onGlobalModelUpdated);
    _routeScroll.routeRestoreGlobalModel = nextModel;
    _routeScroll.routeRestoreGlobalModel?.addListener(_onGlobalModelUpdated);
  }

  bool _isViewportInsertSettling() =>
      _viewportInsert.isViewportInsertSettling();

  void _beginViewportInsertSettle() =>
      _viewportInsert.beginViewportInsertSettle();

  int _viewportInsertSettleRemainingMs() =>
      _viewportInsert.viewportInsertSettleRemainingMs();

  void _onGlobalModelUpdated() {
    _scheduleSeenLiveIncomingInViewport();
    _scheduleHistoryWindowTrim();
    _onGlobalRouteRestoreChanged();
    final globalModel = _routeScroll.routeRestoreGlobalModel;
    // Ending an explicit return can change only flags. Re-sample its visible
    // tail even when the projection did not rebuild. While reading history,
    // scroll/layout already owns sampling; each buffered arrival need not
    // enqueue another SQL proof for the same unchanged old viewport.
    if (globalModel != null &&
        _isFollowingLatest() &&
        globalModel.receivedNewMessageCountFor(_conversationId()) > 0) {
      _scheduleVisibleIncomingProgress();
      WidgetsBinding.instance.scheduleFrame();
    }
    if (globalModel != null &&
        (globalModel.isMessageContextMenuOverlayOpen ||
            globalModel.isContextMenuViewportRestoreActive(_conversationId()) ||
            globalModel.shouldLockChatScrollForMediaPreview ||
            globalModel.isRestoringScrollAfterMediaPreview ||
            globalModel.isSearchJumpPending(_conversationId()))) {
      _historyWindowTrimUi.cancel();
    }
    // Menu close can change only unread/buffer state, without changing the
    // message-list length. Arm anchor restoration from the model notification
    // itself so that path cannot miss the restore transaction.
    if (globalModel != null &&
        globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      _scheduleContextMenuViewportRestore();
    }
    if (globalModel != null && globalModel.isMessageContextMenuOverlayOpen) {
      // Abort any already-running automatic insertion transaction immediately
      // on menu open. Waiting for the ticker's next frame leaves a window in
      // which CVP can write a competing offset under the overlay.
      _abortViewportInsertSlideForSupersede();
      _cancelForcePinScroll();
      _clearIncomingScrollAnchor(reason: 'context_menu_open');
      return;
    }
    _onInboundPresentationSupersede();
    // A send request must supersede an insertion animation, not wait behind it.
    if (globalModel != null &&
        globalModel.pinToBottomImmediate &&
        globalModel.pinToBottomRequestSeq != _lastHandledPinSeq) {
      final requestedSeq = globalModel.pinToBottomRequestSeq;
      _onPinToBottomRequested();
      if (_lastHandledPinSeq == requestedSeq) return;
    }
    if (_viewportInsert.viewportInsertSlideActive) {
      return;
    }
    _onInboundScrollFollowTick();
    if (globalModel != null &&
        globalModel.chatConfig.inboundScrollFollowEnabled &&
        globalModel.isChunkedRevealActive(_conversationId())) {
      return;
    }
    _onPinToBottomRequested();
  }

  void _onInboundPresentationSupersede() {
    final globalModel = _routeScroll.routeRestoreGlobalModel;
    if (globalModel == null) {
      return;
    }
    final seq = globalModel.inboundPresentationSupersedeSeq;
    if (seq == _lastInboundPresentationSupersedeSeq) {
      return;
    }
    _lastInboundPresentationSupersedeSeq = seq;
    _abortViewportInsertSlideForSupersede();
  }

  /// Chunk layer cancelled this push to keep only the newest bubble. Snap open
  /// without acking projection — [MessageInboundChunkedReveal] owns that ack.
  void _abortViewportInsertSlideForSupersede() {
    for (final controller in _shortInsertControllers.toList()) {
      if (!controller.isCompleted) controller.value = 1;
    }
    if (!_viewportInsert.viewportInsertSlideActive &&
        _viewportInsert.activeRowRevealMessages.isEmpty &&
        _viewportInsert.queuedViewportInsertMessages.isEmpty) {
      return;
    }
    ChatJitterDiag.logInboundFlow(
      action: 'viewport_slide_abort_supersede',
      conv: _conversationId(),
      extras: _readingHistoryScrollSnapshot(),
    );
    _viewportInsert.viewportInsertSlideGeneration++;
    _viewportInsert.rowRevealGeneration++;
    _viewportInsert.viewportInsertSlideActive = false;
    _viewportInsert.continuousViewportPushActive = false;
    _viewportInsert.continuousViewportPushLastElapsed = null;
    _viewportInsert.continuousViewportPushLastCommandedPixels = null;
    _viewportInsert.continuousViewportPushIntegrationScheduled = false;
    _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey.clear();
    _viewportInsert.continuousViewportPushRemainingRowExtents.clear();
    ++_viewportInsert.continuousViewportPushIntegrationGeneration;
    _viewportInsert.continuousViewportPushTicker?.stop();
    _cancelForcePinScroll();
    final globalModel = _chatGlobalModel;
    if (globalModel != null) {
      for (final message in _viewportInsert.activeRowRevealMessages.values) {
        globalModel.finishMessageEnterAnimation(message);
      }
      for (final message
          in _viewportInsert.queuedViewportInsertMessages.values) {
        globalModel.finishMessageEnterAnimation(message);
      }
    }
    _viewportInsert.activeRowRevealMessages.clear();
    _viewportInsert.queuedViewportInsertMessages.clear();
    _viewportInsert.rowRevealFullExtentByKey.clear();
    final controller = _viewportInsert.rowRevealController;
    if (controller != null) {
      controller.stop();
      if (controller.value < 1) {
        // Messages already cleared so statusListener complete is a no-op.
        controller.value = 1;
      }
    }
  }

  InboundScrollFollow _ensureInboundScrollFollow() {
    return _inboundScrollFollow ??= InboundScrollFollow(
      scrollController: _autoScrollController,
      shouldFollow: () {
        final model = _chatGlobalModel;
        return mounted &&
            model != null &&
            !model.isChatListUserScrolling &&
            _shouldPinScrollToBottom(model);
      },
      defaultSmoothDuration: Duration(
        milliseconds:
            _chatGlobalModel?.chatConfig.inboundScrollFollowDurationMs ?? 100,
      ),
    );
  }

  void _onInboundScrollFollowTick() {
    if (!mounted) {
      return;
    }
    final globalModel = _routeScroll.routeRestoreGlobalModel;
    if (globalModel == null) {
      return;
    }
    if (!globalModel.chatConfig.inboundScrollFollowEnabled) {
      return;
    }
    final seq = globalModel.inboundScrollFollowSeq;
    if (seq == _lastHandledScrollFollowSeq) {
      return;
    }
    _lastHandledScrollFollowSeq = seq;

    final sessionEnding = globalModel.inboundScrollFollowSessionEnding;
    final chunk = globalModel.lastInboundScrollFollowChunk;
    if (!sessionEnding && chunk.isEmpty) {
      return;
    }
    if (!_shouldPinScrollToBottom(globalModel)) {
      return;
    }

    final mode = globalModel.chatConfig.inboundScrollFollowMode;
    final durationMs = globalModel.chatConfig.inboundScrollFollowDurationMs;
    _ensureInboundScrollFollow().handleChunk(
      chunk: chunk,
      sessionEnding: sessionEnding,
      mode: mode,
      smoothDuration: Duration(milliseconds: durationMs),
    );

    if (sessionEnding) {
      globalModel.setMessageListPosition(
        _conversationId(),
        HistoryMessagePosition.bottom,
        notify: false,
      );
    }
  }

  void _onPinToBottomRequested() {
    if (!mounted) {
      return;
    }
    final globalModel = _routeScroll.routeRestoreGlobalModel;
    if (globalModel == null) {
      return;
    }
    // Keep an already published request unconsumed if a picker opened before
    // this notification was delivered. Closing the overlay notifies us again.
    if (globalModel.isMediaPickerOverlayOpen) {
      return;
    }
    if (globalModel.isBulkMessageSyncActive(_conversationId())) {
      return;
    }
    if (globalModel.isUserScrollToBottomInProgress(_conversationId())) {
      return;
    }
    final seq = globalModel.pinToBottomRequestSeq;
    if (seq == _lastHandledPinSeq) {
      return;
    }
    final convId = globalModel.pinToBottomRequestConvId;
    if (convId == null ||
        !TUIChatGlobalModel.isSameConversationIdForHistory(
          convId,
          _conversationId(),
        )) {
      return;
    }
    _lastHandledPinSeq = seq;
    // Explicit unread navigation owns the viewport until its anchor is
    // verified. Do not replay an older automatic bottom pin after the jump.
    if (_unreadWindowJumpInFlight) return;
    final position = _singleScrollPositionOrNull();
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[MessageContextTrace] scroll_mutation type=pin_request conv=$convId seq=$seq force=${globalModel.pinToBottomForce} before=${position?.hasPixels == true ? position!.pixels : 'n/a'} min=${position?.minScrollExtent} max=${position?.maxScrollExtent} menuOpen=${globalModel.isMessageContextMenuOverlayOpen} restore=${globalModel.isContextMenuViewportRestoreActive(_conversationId())}',
      );
    }
    if (globalModel.pinToBottomForce) {
      if (globalModel.pinToBottomImmediate) {
        _abortViewportInsertSlideForSupersede();
        _endInboundViewportPushPresentation();
        _finishIncomingMessagesWithoutRowReveal(
          widget.messageList.whereType<V2TimMessage>()
              .where(_isOutgoingMediaMessage).toList(growable: false),
        );
        _clearIncomingScrollAnchor(reason: 'explicit_outgoing_batch_pin');
        _clearShortHistoryAlignmentLatch();
        _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = true;
        _immediateOutgoingImageBatchPin = true;
        setState(() {});
      }
      _scheduleForcePinScrollToBottom();
    } else {
      _schedulePinScrollToBottom();
    }
  }

  void _onGlobalRouteRestoreChanged() {
    if (!mounted) {
      return;
    }
    final globalModel = _routeScroll.routeRestoreGlobalModel;
    if (globalModel == null ||
        !globalModel.isRestoringScrollAfterMediaPreview) {
      return;
    }
    final version = globalModel.mediaPreviewRestoreVersion;
    if (version <= 0) {
      return;
    }
    if (_routeScroll.lastRouteRestoreVersion != version) {
      _routeScroll.lastRouteRestoreVersion = version;
      _routeScroll.routeRestoreAttempt = 0;
    }
    _scheduleRouteScrollRestore(_visibleMessageList(widget.messageList));
  }

  @override
  void didUpdateWidget(TIMUIKitHistoryMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model) ||
        oldWidget.model.conversationID != widget.model.conversationID ||
        oldWidget.searchJumpAnchor != widget.searchJumpAnchor ||
        oldWidget.initFindingMsg != widget.initFindingMsg) {
      _latestLoadIntent.cancel();
      _previousLoadQueue.cancel();
      _invalidatePreviousPagination();
    }
    _scheduleHistoryWindowTrim();
    if (oldWidget.messageList.isEmpty && widget.messageList.isNotEmpty) {
      // 冷开 local-first：initState 时 rawCount=0，这里补标，避免后续云端
      // 补数走「非暖窗 bootstrap 结束 → pin 底」造成跳动。
      _routeScroll.openedWithCachedHistory = true;
      _scheduleChatOpenPerfProbe(reason: 'didUpdate_first_messages');
    }
    if (oldWidget.model.conversationID != widget.model.conversationID) {
      _latestPaginationGeneration++;
      _paginationUi.isLoadingLatest = false;
      _releaseAtJumpCenterOwnership(notify: false);
      _historyWindowTrimUi.cancel();
      _historyWindowTrimIdleTimer?.cancel();
      _historyWindowTrimIdleTimer = null;
      _historyWindowPaginationWasBlocked = false;
      _initialSearchJumpPositioned = false;
      _renderedVisibleMessages = null;
      _resetInitialMountBatch();
      _contextMenuFrozenVisibleMessages = null;
      _contextMenuFrozenLayoutUnreadCount = null;
      _frozenWidgetListLen = -1;
      _clearShortHistoryAlignmentLatch();
      _resetHistoryOpenRevealGate();
      _messagesFirstVisibleScheduled = false;
      _messagesFirstVisibleReported = false;
      _routeScroll.openedWithCachedHistory =
          widget.model.globalModel.rawMessageCount(
                widget.model.conversationID,
              ) >
              0;
      _beginOpeningPlaceholderForCurrentConversation();
      _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = false;
      _paginationUi.triedPreviousAfterNoMore = false;
      _initialUnreadAnchorConversationID = null;
      _initialUnreadAnchorCount = 0;
      _initialUnreadAnchorAttempts = 0;
      _initialUnreadAnchorScheduled = false;
      _initialUnreadAnchorInFlight = false;
      _completedEntryUnreadCount = 0;
      _firstUnreadAnchor = null;
      _firstUnreadAnchorJumped = false;
      _lastUnreadTongueConversationID = null;
      _lastUnreadTongueRemaining = null;
      _lastUnreadTongueSafeCount = 0;
      _unreadEntryBottomPinScheduled = false;
      _lastHandledPinSeq = 0;
      _lastHandledScrollFollowSeq = 0;
      _lastInboundPresentationSupersedeSeq = 0;
      _disposeShortListInsertions(conversationID: oldWidget.model.conversationID);
      if (_viewportInsert.continuousViewportPushActive) {
        _viewportInsert.continuousViewportPushTicker?.stop();
        _chatGlobalModel?.endInboundViewportPush(
          oldWidget.model.conversationID,
        );
      }
      _viewportInsert.continuousViewportPushActive = false;
      _viewportInsert.continuousViewportPushLastElapsed = null;
      _viewportInsert.continuousViewportPushLastCommandedPixels = null;
      _viewportInsert.continuousViewportPushIntegrationScheduled = false;
      _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey.clear();
      _viewportInsert.continuousViewportPushRemainingRowExtents.clear();
      ++_viewportInsert.continuousViewportPushIntegrationGeneration;
      _viewportInsert.viewportInsertSlideGeneration++;
      _viewportInsert.viewportInsertSlideActive = false;
      _viewportInsert.activeRowRevealMessages.clear();
      _viewportInsert.queuedViewportInsertMessages.clear();
      _viewportInsert.rowRevealFullExtentByKey.clear();
      _cancelForcePinScroll();
      _inboundScrollFollow?.dispose();
      _inboundScrollFollow = null;
      _deferUnreadCenterPartition = false;
      _livePartitionAnchorHeadKey = null;
      _incomingScrollAnchorPixels = null;
      _incomingScrollAnchorMaxExtent = null;
      _incomingScrollAnchorGeneration++;
      _clearBufferedRevealAnchor();
      _contextMenuViewportRestoreScheduled = false;
      _contextMenuViewportRestoreCallbackPending = false;
      _contextMenuViewportStableFrames = 0;
      _contextMenuViewportRestoreGeneration++;
      _lastDiagLayoutSafeUnread = -1;
      _lastDiagLayoutUnread = -1;
      _lastCenterDiagLayoutUnread = -1;
      _lastCenterDiagUnreadEndPoint = -1;
      _lastCenterDiagUnreadLen = -1;
      _lastCenterDiagReadLen = -1;
      _lastCenterDiagCenterActive = null;
      _lastPhysicsMaxExtentSeen = null;
      _newestInsertRoom = 0.0;
      _newestInsertRoomAtMs = 0;
      _progressiveRevealGrowthPending = false;
      _progressiveRevealGeneration++;
      _cancelFollowingLatestRestoreRetry();
      _paginationUi.previousLoadConsumedThisTopReach = false;
      _paginationUi.previousRetryNeedsUserGesture = false;
      _paginationUi.lastTopReachConsumedAnchorKey = null;
      _paginationUi.previousLoadInFlightAnchorKey = null;
      _topHistoryLoadingVisible.value = false;
      _previousLoadQueue.cancel();
      _paginationUi.loadPreviousTask = null;
      _bindSeparateModelListener();
      _chatGlobalModel?.clearActiveChatScrollController(
        conversationID: oldWidget.model.conversationID,
      );
      _chatGlobalModel?.clearUnreadTongueMetrics(
        oldWidget.model.conversationID,
        notify: false,
      );
      _chatGlobalModel?.clearEntryUnreadTongueDismissed(
        oldWidget.model.conversationID,
        notify: false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bindActiveScrollController();
        _schedulePinScrollToBottom();
      });
      _scheduleChatOpenPerfProbe(reason: 'didUpdate_conversation');
    }
    if (widget.searchJumpAnchor != null &&
        oldWidget.searchJumpAnchor != widget.searchJumpAnchor) {
      _releaseAtJumpCenterOwnership(notify: false);
    }
    final newestSideAbsorbed = _onMessageListMaybeInserted(
      oldWidget.messageList,
      widget.messageList,
    );
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    _handleInitialHistoryBootstrapTransition(globalModel);
    final listLenChanged =
        oldWidget.messageList.length != widget.messageList.length;
    if (listLenChanged) {
      PerfTimeline.instant('chat_history_list_commit', arguments: {
        'conversationId': _conversationId(),
        'messageCount': widget.messageList.length,
      });
    }
    final currentRev = globalModel.messageListRevisionFor(_conversationId());
    final listRevChanged = _historyOpenRevealLastListRev != null &&
        _historyOpenRevealLastListRev != currentRev;
    if ((listLenChanged || listRevChanged) &&
        !_historyOpenRevealReady &&
        _layoutReadyEpochSigned < 0) {
      _historyOpenRevealStableFrames = 0;
      _historyOpenRevealHoldFrames = 0;
      _historyOpenRevealLastSpacer = null;
      _historyOpenRevealLastContentH = null;
      _historyOpenRevealLastListLen = null;
      _historyOpenRevealLastListRev = null;
      if (_mayUseShortHistoryTopAlignment() ||
          _routeScroll.shortHistoryAlignmentLatched ||
          _routeScroll.shortHistoryBottomSpacerHeight > 1) {
        _scheduleHistoryOpenRevealWait(shortHistory: true);
      }
    }
    if (listLenChanged && !_isInitialHistoryBootstrapping(globalModel)) {
      final oldLen = oldWidget.messageList.length;
      final newLen = widget.messageList.length;
      final convId = _conversationId();
      // 进页后云端补历史：贴底时旧消息只往上长，禁止 contentH/spacer 重置与
      // 二次 pin，否则最新气泡会跟着整表「蹦」一下。
      final openCloudFillAtBottom = newLen > oldLen &&
          !_isReadingHistory() &&
          globalModel.hasInitialHistoryLoaded(convId) &&
          globalModel.mayHaveOlderHistory(convId) &&
          globalModel.getMessageListPosition(convId) ==
              HistoryMessagePosition.bottom;
      if (openCloudFillAtBottom) {
        ChatGeomSettleTrace.noteReason(
          'open_cloud_fill_keep_bottom_anchor',
          extras: <String, Object?>{'oldLen': oldLen, 'newLen': newLen},
        );
        return;
      }
      final shortSpacerLatched = _routeScroll.shortHistoryAlignmentLatched ||
          _routeScroll.shortHistoryBottomSpacerHeight > 0;
      var asyncHistoryAbsorbed = false;
      if (ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled &&
          !newestSideAbsorbed &&
          _historyOpenRevealReady &&
          shortSpacerLatched &&
          mounted &&
          !_isReadingHistory() &&
          oldLen != newLen) {
        final absorb = _absorbAsyncHistoryListChangeIntoShortSpacer(
          oldList: oldWidget.messageList,
          newList: widget.messageList,
        );
        if (absorb == _AsyncSpacerAbsorbResult.ok) {
          asyncHistoryAbsorbed = true;
        } else if (absorb == _AsyncSpacerAbsorbResult.overflow) {
          _clearShortHistoryAlignmentLatch();
          _blockShortSpacerReprimeAfterReveal = true;
          ChatGeomSettleTrace.noteReason(
            'short_spacer_reprime_blocked_after_reveal',
            extras: <String, Object?>{
              'cause': 'async_history_overflow',
              'oldLen': oldLen,
              'newLen': newLen,
            },
          );
        }
      }
      final significantGrow =
          newLen >= oldLen + 3 || (oldLen > 0 && newLen >= oldLen * 2);
      if (!asyncHistoryAbsorbed &&
          significantGrow &&
          (_routeScroll.shortHistoryAlignmentLatched ||
              _routeScroll.shortHistoryBottomSpacerHeight > 0) &&
          mounted &&
          !_isReadingHistory()) {
        ChatGeomSettleTrace.noteReason(
          'short_spacer_cleared_on_len_grow',
          extras: <String, Object?>{
            'oldLen': oldLen,
            'newLen': newLen,
            'spacer':
                _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(1),
            'contentH': _routeScroll.shortHistoryContentHeight.toStringAsFixed(
              1,
            ),
          },
        );
        _clearShortHistoryAlignmentLatch();
        if (_historyOpenRevealReady) {
          _blockShortSpacerReprimeAfterReveal = true;
          ChatGeomSettleTrace.noteReason(
            'short_spacer_reprime_blocked_after_reveal',
            extras: <String, Object?>{
              'cause': 'cleared_on_len_grow',
              'oldLen': oldLen,
              'newLen': newLen,
            },
          );
        }
      }
      final keepShortHistoryContent = mounted &&
          !_isReadingHistory() &&
          (_routeScroll.shortHistoryAlignmentLatched ||
              _routeScroll.shortHistoryBottomSpacerHeight > 0) &&
          !(
              // reveal 后异步历史写回导致变短：禁止死守旧大 spacer（tip 会被顶）。
              _historyOpenRevealReady && newLen < oldLen) &&
          !_contentExceedsShortHistoryViewport(
            messageList: widget.messageList,
            viewportHeight: _resolvedShortHistoryViewportForDecision(context),
            context: context,
          );
      if (keepShortHistoryContent) {
        ChatGeomSettleTrace.noteReason(
          'content_h_reset_skipped_keep_short_history',
          extras: <String, Object?>{
            'spacer':
                _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(1),
            'contentH': _routeScroll.shortHistoryContentHeight.toStringAsFixed(
              1,
            ),
            'oldLen': oldLen,
            'newLen': newLen,
          },
        );
      } else if (!asyncHistoryAbsorbed) {
        _assignShortHistoryContentHeight(
          -1,
          reason: 'content_h_reset_on_list_len_change',
        );
      }
      if (mounted &&
          !_isReadingHistory() &&
          (_routeScroll.shortHistoryAlignmentLatched ||
              _routeScroll.shortHistoryBottomSpacerHeight > 0)) {
        final viewport = _resolvedShortHistoryViewportForDecision(context);
        if (_contentExceedsShortHistoryViewport(
          messageList: widget.messageList,
          viewportHeight: viewport,
          context: context,
        )) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isHistoryScrollProtected && !_isReadingHistory()) {
              setState(() {
                _releaseShortHistoryAlignmentAndPinBottom();
                if (_historyOpenRevealReady) {
                  _blockShortSpacerReprimeAfterReveal = true;
                }
              });
            }
          });
        }
      }
    }
  }

  bool _isInitialHistoryBootstrapping(TUIChatGlobalModel globalModel) {
    final convId = _conversationId();
    // 仅「首轮尚未确认」才算 bootstrapping。
    // 已确认空会话后的后台 loadChatRecord 不再挡空态，避免每次进空会话先转圈。
    return !globalModel.hasInitialHistoryLoaded(convId);
  }

  bool _isCompleteCachedOpenWindow(TUIChatGlobalModel globalModel) {
    final convId = _conversationId();
    final rawCount = globalModel.rawMessageCount(convId);
    if (rawCount >= HistoryMessageDartConstant.initialOpenFetchCount) {
      return true;
    }
    return globalModel.hasInitialHistoryLoaded(convId) &&
        !globalModel.mayHaveOlderHistory(convId) &&
        !globalModel.hasOpenHydrateInFlight(convId);
  }

  void _handleInitialHistoryBootstrapTransition(
    TUIChatGlobalModel globalModel,
  ) {
    final bootstrapping = _isInitialHistoryBootstrapping(globalModel);
    if (_routeScroll.wasInitialHistoryBootstrapping && !bootstrapping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // 暖/冷开同一语义：短历史已顶部对齐（或仍应顶部对齐）时，
        // bootstrap 完成不要 clear，否则 spacer 0→prime 再弹一次。
        if (_routeScroll.openedWithCachedHistory) {
          return;
        }
        if (_shouldPreserveShortHistoryLatchAfterOpenHydrate(context)) {
          ChatGeomSettleTrace.noteReason(
            'bootstrap_skip_clear_keep_short_history',
            extras: <String, Object?>{
              'spacer': _routeScroll.shortHistoryBottomSpacerHeight
                  .toStringAsFixed(1),
              'contentH':
                  _routeScroll.shortHistoryContentHeight.toStringAsFixed(1),
              'latched': _routeScroll.shortHistoryAlignmentLatched,
            },
          );
          return;
        }
        _clearShortHistoryAlignmentLatch();
        // 长历史 / 已超出视口：hydrate 完成后回到底部；用户已上滑则保持原位。
        // 进页阶段只用 jump，避免 soft pin 的 animateTo「从底部往上飘」。
        if (!_isHistoryScrollProtected &&
            globalModel.getMessageListPosition(_conversationId()) ==
                HistoryMessagePosition.bottom) {
          _pinScrollToBottomImmediate();
        }
      });
    }
    _routeScroll.wasInitialHistoryBootstrapping = bootstrapping;
  }

  /// 进页 hydrate/bootstrap 完成后是否应保留短历史顶部 latch。
  /// 超出视口则 false（允许 clear+贴底）；读历史则 true（不 clear、不 pin）。
  bool _shouldPreserveShortHistoryLatchAfterOpenHydrate(BuildContext context) {
    if (!mounted) {
      return false;
    }
    if (_routeScroll.shortHistoryAlignmentSuppressedByLiveInsert) {
      return false;
    }
    if (_isReadingHistory()) {
      return true;
    }
    final viewport = _resolvedShortHistoryViewportForDecision(context);
    if (_contentExceedsShortHistoryViewport(
      messageList: widget.messageList,
      viewportHeight: viewport,
      context: context,
    )) {
      return false;
    }
    if (_routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 0) {
      return true;
    }
    return _shouldAlignShortHistoryToTop(
      messageList: widget.messageList,
      safeUnreadCount: 0,
      viewportHeight: viewport,
      context: context,
    );
  }

  @override
  void deactivate() {
    _historyWindowTrimUi.cancel();
    _historyWindowTrimIdleTimer?.cancel();
    _historyWindowTrimIdleTimer = null;
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageList',
      phase: 'deactivate',
      stateHash: identityHashCode(this),
      conv: _conversationId(),
      livedMs: DateTime.now().millisecondsSinceEpoch - _createdAtMs,
      keyDebug: widget.key?.toString(),
      ancestors: _ancestorChainForDiag(),
    );
    super.deactivate();
  }

  @override
  void dispose() {
    _disposeShortListInsertions();
    _latestLoadIntent.dispose();
    _releaseAtJumpCenterOwnership(notify: false);
    _initialMountGeneration++;
    _historyWindowTrimUi.dispose();
    _historyWindowTrimIdleTimer?.cancel();
    _historyWindowTrimIdleTimer = null;
    _cancelFollowingLatestRestoreRetry();
    _searchJumpLayoutDeadline?.cancel();
    VisibleSenderProfileRefresh.cancelPending();
    ChatHistoryOpenLayoutReady.epochRevision.removeListener(
      _onLayoutReadyEpochRevision,
    );
    _historyOpenRevealWatchdogTimer?.cancel();
    _historyOpenRevealWatchdogTimer = null;
    ChatGeomSettleTrace.end(reason: 'dispose');
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'HistoryMessageList',
      phase: 'dispose',
      stateHash: identityHashCode(this),
      conv: _conversationId(),
      livedMs: DateTime.now().millisecondsSinceEpoch - _createdAtMs,
      keyDebug: widget.key?.toString(),
    );
    _previousLoadQueue.dispose();
    _paginationUi.disposeTimers();
    _clearScrollPaginationCompensation();
    _viewportInsert.viewportInsertSlideGeneration++;
    _viewportInsert.rowRevealGeneration++;
    _viewportInsert.viewportInsertSlideActive = false;
    _viewportInsert.continuousViewportPushActive = false;
    _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey.clear();
    _viewportInsert.continuousViewportPushRemainingRowExtents.clear();
    ++_viewportInsert.continuousViewportPushIntegrationGeneration;
    _viewportInsert.continuousViewportPushTicker?.dispose();
    _viewportInsert.continuousViewportPushTicker = null;
    _viewportInsert.viewportInsertSettleUntilMs = 0;
    _routeScroll.routeRestoreGlobalModel?.removeListener(_onGlobalModelUpdated);
    _routeScroll.routeRestoreGlobalModel = null;
    // K.9：移除 scroll 监听
    _autoScrollController.removeListener(_onAutoScrollUpdate);
    final globalModel = _chatGlobalModel;
    if (globalModel != null) {
      for (final message in _viewportInsert.activeRowRevealMessages.values) {
        globalModel.finishMessageEnterAnimation(message);
      }
      for (final message
          in _viewportInsert.queuedViewportInsertMessages.values) {
        globalModel.finishMessageEnterAnimation(message);
      }
      _viewportInsert.activeRowRevealMessages.clear();
      _viewportInsert.queuedViewportInsertMessages.clear();
      _viewportInsert.rowRevealFullExtentByKey.clear();
      if (globalModel.isChunkedRevealActive(_conversationId())) {
        globalModel.cancelInboundProjectionRevealToBuffer(_conversationId());
      }
    }
    _viewportInsert.activeRowRevealMessages.clear();
    _viewportInsert.queuedViewportInsertMessages.clear();
    _viewportInsert.rowRevealFullExtentByKey.clear();
    _openingPlaceholderDelayTimer?.cancel();
    _openingPlaceholderDelayTimer = null;
    _openingPlaceholderFadeController.removeStatusListener(
      _onOpeningPlaceholderFadeStatus,
    );
    _openingPlaceholderFadeController.dispose();
    _viewportInsert.rowRevealController?.dispose();
    _acknowledgeInboundProjectionRevealIfNeeded();
    _inboundScrollFollow?.dispose();
    _inboundScrollFollow = null;
    _postScrollInboundFlushTimer?.cancel();
    _postScrollInboundFlushTimer = null;
    _unreadTongueMetricsThrottleTimer?.cancel();
    _unreadTongueMetricsThrottleTimer = null;
    _pendingUnreadTongueMetricsList = null;
    _chatGlobalModel?.clearActiveChatScrollController(
      conversationID: _conversationId(),
    );
    _setUserScrolling(false);
    _chatGlobalModel?.clearUnreadTongueMetrics(
      _conversationId(),
      notify: false,
    );
    _chatGlobalModel?.clearEntryUnreadTongueDismissed(
      _conversationId(),
      notify: false,
    );
    _controller.removeListener(_controllerListener);
    _boundSeparateModel?.removeListener(_onSeparateModelUpdated);
    _boundSeparateModel = null;
    (_chatGlobalModel ?? widget.model.globalModel).detachOpenChatPageUi(
      historyPosition: _pageUi.historyPosition,
      userScrolling: _pageUi.userScrolling,
    );
    _latestMessageVisible.dispose();
    _topHistoryLoadingVisible.dispose();
    _pageUi.dispose();
    super.dispose();
  }

  void _setUserScrolling(bool scrolling) {
    // Writes ChatPageUiNotifiers via GlobalModel attach bridge (single write path).
    final global = _chatGlobalModel ?? widget.model.globalModel;
    final wasScrolling = global.isChatListUserScrolling;
    if (scrolling) {
      _postScrollInboundFlushTimer?.cancel();
      _postScrollInboundFlushTimer = null;
      if (_shortInsertProgress.isNotEmpty) {
        // A drag owns the viewport; do not keep expanding rows underneath it.
        for (final controller in _shortInsertControllers.toList()) {
          if (!controller.isCompleted) controller.value = 1;
        }
        global.endInboundViewportPush(_conversationId(), settleMilliseconds: 0);
      }
    }
    global.setChatListUserScrolling(scrolling);
    if (scrolling != wasScrolling) {
      PerfTimeline.instant(
        scrolling ? 'chat_history_scroll_start' : 'chat_history_scroll_end',
        arguments: {'conversationId': _conversationId()},
      );
    }
    if (wasScrolling && !scrolling) {
      final rawCount = global.rawMessageCount(_conversationId());
      if (ChatJitterDiag.enabled) {
        double? pixels;
        final position = _singleScrollPositionOrNull();
        if (position != null && position.hasPixels) {
          pixels = position.pixels;
        }
        ChatJitterDiag.noteScrollIdle(
          pixels: pixels,
          rawMessageCount: rawCount,
        );
      }
      ChatResourceSample.onRawMessageCount(rawCount);
      final convId = _conversationId();
      final listPosition = global.getMessageListPosition(convId);
      if (listPosition == HistoryMessagePosition.bottom) {
        ChatResourceSample.onBottom(rawMessageCount: rawCount);
        if (!_isSearchJumpStabilizing &&
            rawCount > ChatMessageWindowPolicy.softMax) {
          _compactMemoryWindowAtStableBoundary(reason: 'returned_to_bottom');
        }
      }
    }
  }

  void _compactMemoryWindowAtStableBoundary({required String reason}) {
    _scheduleHistoryWindowTrim();
  }

  bool _historyWindowTrimInteractionIdle(TUIChatGlobalModel global) {
    if (!mounted ||
        !widget.isAllowScroll ||
        ModalRoute.of(context)?.isCurrent == false ||
        _userScrollGestureActive ||
        global.isChatListUserScrolling ||
        _pageUi.userScrolling.value ||
        _isSearchJumpStabilizing ||
        global.isSearchJumpPending(_conversationId()) ||
        widget.model.isLoadingChatHistory ||
        _paginationUi.isLoadingPrevious ||
        _paginationUi.isLoadingLatest ||
        _paginationUi.loadPreviousTask != null ||
        _previousLoadQueue.isAdmitted ||
        (_paginationUi.loadLatestDebounce?.isActive ?? false) ||
        _shouldCompensateScrollForPagination() ||
        global.isMessageContextMenuOverlayOpen ||
        global.isContextMenuViewportRestoreActive(_conversationId()) ||
        global.isRestoringScrollAfterMediaPreview ||
        global.shouldLockChatScrollForMediaPreview ||
        global.isUserScrollToBottomInProgress(_conversationId()) ||
        _viewportInsert.viewportInsertSlideActive ||
        _viewportInsert.continuousViewportPushActive ||
        _isViewportInsertSettling()) return false;
    final position = _singleScrollPositionOrNull();
    return position != null &&
        position.hasPixels &&
        position.hasContentDimensions &&
        !position.outOfRange &&
        !position.isScrollingNotifier.value;
  }

  void _scheduleHistoryWindowTrim() {
    if (!mounted ||
        _historyWindowTrimUi.isDisposed ||
        _historyWindowTrimUi.isBusy ||
        _historyWindowTrimIdleTimer != null) return;
    final global = _chatGlobalModel ?? widget.model.globalModel;
    if (!global.historyWindowNeedsTrim(_conversationId())) return;
    _historyWindowTrimIdleTimer = Timer(const Duration(milliseconds: 180), () {
      _historyWindowTrimIdleTimer = null;
      if (!mounted) return;
      // Protection expires by time, without another model notification. Wait
      // once for that deadline; touch/fling and overlays retry on their end.
      final now = DateTime.now().millisecondsSinceEpoch;
      final protectedUntil = max(_paginationUi.historyScrollProtectUntilMs,
          _paginationUi.scrollPaginationCompensationUntilMs);
      if (protectedUntil > now) {
        _historyWindowTrimIdleTimer =
            Timer(Duration(milliseconds: protectedUntil - now + 24), () {
          _historyWindowTrimIdleTimer = null;
          _scheduleHistoryWindowTrim();
        });
        return;
      }
      unawaited(_trimHistoryWindowAtIdle());
    });
  }

  bool _historyWindowBlocksPagination() {
    final global = _chatGlobalModel ?? widget.model.globalModel;
    if (!_historyWindowTrimUi.isBusy &&
        !global.historyWindowPaginationBlocked(_conversationId())) return false;
    _historyWindowPaginationWasBlocked = true;
    _scheduleHistoryWindowTrim();
    return true;
  }

  Future<void> _trimHistoryWindowAtIdle() async {
    final model = widget.model;
    final global = _chatGlobalModel ?? model.globalModel;
    final conversationID = _conversationId();
    if (!global.historyWindowNeedsTrim(conversationID) ||
        !_historyWindowTrimInteractionIdle(global)) return;
    final transition = _windowTransitionKey.currentState;
    if (transition == null) return;
    final scope = global.historyWindowScopeFor(conversationID);
    final readingRevision = model.historyReadingWindowRevision;
    final trimStopwatch = Stopwatch()..start();
    int? transitionGeneration;
    final outcome = await _historyWindowTrimUi.run(
      isCurrentAndIdle: () =>
          mounted &&
          _conversationId() == conversationID &&
          identical(widget.model, model) &&
          identical(widget.model.globalModel, global) &&
          _historyWindowTrimInteractionIdle(global),
      capture: _captureVisiblePaginationViewportAnchor,
      prepare: (anchor) => global.prepareHistoryWindowTrim(
        conversationID: conversationID,
        anchorMsgID: anchor.msgID ?? '',
        anchorSeq: anchor.seq?.toString(),
      ),
      commit: (ticket) {
        final committed = global.commitHistoryWindowTrim(ticket);
        if (committed && mounted) {
          // The trim snapshot owns this coordinate change and restores the
          // same visible row after remount (including rollback).
          _livePartitionAnchorHeadKey = null;
          _livePartitionAnchorHeadMessage = null;
          _clearBufferedRevealAnchor(reason: 'trim_window');
          setState(() {});
        }
        return committed;
      },
      nextFrame: () => WidgetsBinding.instance.endOfFrame,
      restore: _restoreHistoryWindowTrimAnchor,
      maxRestoreFrames: 4,
      rollbackOnRestoreFailure: false,
      rollback: global.rollbackHistoryWindowTrim,
      finish: global.finishHistoryWindowTrim,
      onWindowSettled: () {
        // Cursor ownership follows the final data window, including when the
        // old, oversized window could not be restored. Fence late completions
        // after navigation, account changes or replacement reading windows.
        if (!mounted ||
            _historyWindowTrimUi.isDisposed ||
            _conversationId() != conversationID ||
            !identical(widget.model, model) ||
            !identical(model.globalModel, global) ||
            model.historyReadingWindowRevision != readingRevision ||
            scope == null ||
            !global.isHistoryWindowScopeCurrent(scope)) {
            return;
        }
        model.rebaseHistoryReadingWindowAfterTrim();
      },
      // Keep the last painted viewport until remount/correction (or rollback)
      // has settled. A missing snapshot defers this optional idle trim.
      beginVisualUpdate: () {
        final started = transition.begin(
          showProgress: false,
          requireSnapshot: true,
          maxRetention: const Duration(milliseconds: 150),
          onInterrupted: _historyWindowTrimUi.cancel,
        );
        if (started) transitionGeneration = transition.generation;
        return started;
      },
      endVisualUpdate: () async =>
          transition.release(expectedGeneration: transitionGeneration),
    );
    if (!mounted ||
        _conversationId() != conversationID ||
        !identical(widget.model, model) ||
        !identical(model.globalModel, global) ||
        scope == null ||
        !global.isHistoryWindowScopeCurrent(scope)) {
        return;
    }
    // Rows painted while the trim owned the viewport were intentionally not
    // acknowledged. Sample the restored reading edge once that owner settles.
    _scheduleVisibleIncomingProgress();
    WidgetsBinding.instance.scheduleFrame();
    ChatHistoryTrace.log('history_window_trim_ui_result',
        conversationID: conversationID,
        extras: {
          'outcome': outcome.name,
          'elapsedMs': trimStopwatch.elapsedMilliseconds,
          'maxRestoreFrames': 4,
        });
    if (outcome == HistoryWindowTrimUiOutcome.restored) {
      ChatHistoryTrace.log('memory_window_compact_stable_boundary',
          conversationID: conversationID,
          extras: {
            'after': global.rawMessageCount(conversationID),
            'pixelAnchorVerified': true
          });
    }
    if (outcome == HistoryWindowTrimUiOutcome.restored ||
        outcome == HistoryWindowTrimUiOutcome.keptCommitted ||
        outcome == HistoryWindowTrimUiOutcome.rollbackFailed) {
      // A failed rollback also leaves room to resume a previously blocked page.
      _historyWindowTrimIdleRetries = 0;
      _resumeHistoryWindowBlockedPagination(global);
    } else if (outcome == HistoryWindowTrimUiOutcome.skipped &&
        _historyWindowTrimIdleRetries++ < 3) {
      // A newer ingress revision can invalidate disk preparation. Retry the
      // current authority a bounded number of times, never the stale ticket.
      _scheduleHistoryWindowTrim();
    }
  }

  bool _restoreHistoryWindowTrimAnchor(
      _PaginationViewportAnchor anchor, int attempt) {
    // Membership has changed; do not trust the old index map or captured tag.
    final messages = _currentVisibleMessageList();
    var index = anchor.msgID?.isNotEmpty == true
        ? messages.indexWhere((message) => message?.msgID == anchor.msgID)
        : -1;
    if (index < 0 && anchor.seq != null) {
      index = messages.indexWhere((message) =>
          message != null &&
          int.tryParse(message.seq?.trim() ?? '') == anchor.seq);
    }
    if (index < 0) return false;
    final position = _singleScrollPositionOrNull();
    return HistoryWindowTrimViewportRestorer.restore(
      targetIndex: index,
      viewportTop: anchor.viewportTop,
      position: position,
      contextForIndex: (index) {
        if (index < 0 || index >= messages.length) return null;
        final tag = _autoScrollController.tagMap[-index];
        // A parent can still be rebuilding its projection. A numeric tag that
        // belongs to yesterday's row is not the newly resolved message.
        if (tag?.widget.key !=
            ValueKey<String>(_stableMessageListKey(messages[index], index)))
          return null;
        return tag?.context;
      },
      mountedIndices: _autoScrollController.tagMap.keys
          .map((key) => -key)
          .where((index) => index >= 0 && index < messages.length),
      jumpTo: (pixels) =>
          _geomJumpTo(pixels, reason: 'history_trim_mount_anchor'),
      correctMountedAnchor: () => _restorePaginationViewportAnchor(
        anchor: anchor,
        position: position!,
        attempt: attempt,
        resolvedGlobalIndex: index,
      ),
    );
  }

  void _resumeHistoryWindowBlockedPagination(TUIChatGlobalModel global) {
    if (!_historyWindowPaginationWasBlocked ||
        !_historyWindowTrimInteractionIdle(global)) return;
    _historyWindowPaginationWasBlocked = false;
    // The edge gesture already owns one retry. A direct trim-resume load here
    // would leave that retry queued and fetch a second page for the same input.
    if (_latestLoadIntent.isPending || _previousLoadQueue.isPending) return;
    final position = _singleScrollPositionOrNull();
    if (position == null) return;
    final messages = _currentVisibleMessageList();
    // Only a request previously rejected at the memory ceiling is resumed.
    // Normal idle layout never starts a chain of unsolicited page loads.
    if (!_isOverscrollingPastTop(position) &&
        HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
          pixels: position.pixels,
          maxScrollExtent: position.maxScrollExtent,
          prefetchPx: _historyPreviousPrefetchPx(),
          hasPixels: position.hasPixels,
          hasContentDimensions: position.hasContentDimensions,
        ) &&
        _canAttemptPreviousHistoryPagination()) {
      final anchor = _anchorForPreviousLoad(messages);
      if (anchor != null) {
        _paginationUi.previousLoadConsumedThisTopReach = false;
        _paginationUi.lastTopReachConsumedAnchorKey = null;
        _paginationUi.ignoreScrollLoadPrevious = 0;
        _queuePreviousLoad(anchor, source: _PreviousLoadSource.trimResume);
      }
    } else if (_isNearLatestScrollEdge(position) &&
        _allowsLatestHistoryPagination(global) &&
        _canProbeLatestHistory(global)) {
      final anchor = _anchorForLatestLoad(messages);
      if (anchor != null) unawaited(_loadLatest(anchor, globalModel: global));
    }
  }

  void _setCompactHistoryCacheExtent(bool compact) {
    if (_compactHistoryCacheExtent == compact || !mounted) {
      return;
    }
    final previousExtent = _effectiveHistoryCacheExtent();
    _compactHistoryCacheExtent = compact;
    // With no distinct scrolling extent, start/end gestures must not rebuild
    // all visible message rows just to change an otherwise unused flag.
    if (_effectiveHistoryCacheExtent() != previousExtent) setState(() {});
  }

  double _effectiveHistoryCacheExtent() {
    return widget.mainHistoryListConfig?.cacheExtent ?? 800;
  }

  double _historyPreviousPrefetchPx() {
    return HistoryPreviousPrefetchPolicy.prefetchDistancePx(
      _effectiveHistoryCacheExtent(),
    );
  }

  void _schedulePostScrollInboundFlush(TUIChatGlobalModel globalModel) {
    _postScrollInboundFlushTimer?.cancel();
    _postScrollInboundFlushTimer = Timer(
      const Duration(milliseconds: _postScrollInboundFlushDelayMs),
      () {
        _postScrollInboundFlushTimer = null;
        if (!mounted) {
          return;
        }
        if (globalModel.isChatListUserScrolling) {
          return;
        }
        if (!_isFollowingLatest()) {
          return;
        }
        final convId = _conversationId();
        ChatJitterDiag.logInboundFlow(
          action: 'post_scroll_flush_fire',
          conv: convId,
          extras: <String, Object?>{
            'buffered': globalModel.deferredIncomingBufferedCount(convId),
            'delayMs': _postScrollInboundFlushDelayMs,
          },
        );
        globalModel.flushDeferredIncomingMessages(convId, notify: false);
      },
    );
  }

  String _conversationId() => widget.model.conversationID;

  String _ancestorChainForDiag() {
    if (!mounted) return 'unmounted';
    final types = <String>[];
    context.visitAncestorElements((element) {
      types.add(element.widget.runtimeType.toString());
      return types.length < 8;
    });
    return types.join('>');
  }

  bool get _isHistoryScrollProtected {
    final globalModel =
        _routeScroll.routeRestoreGlobalModel ?? _chatGlobalModel;
    return _paginationUi.isHistoryScrollProtected(
      mediaPreviewRestoring:
          globalModel?.isRestoringScrollAfterMediaPreview ?? false,
    );
  }

  void _beginHistoryScrollProtection({int? milliseconds}) {
    _paginationUi.beginHistoryScrollProtection(milliseconds: milliseconds);
  }

  int _tongueMetricsUnreadCount(
    int safeUnreadCount,
    TUIChatGlobalModel globalModel,
  ) {
    final convId = _conversationId();
    if (globalModel.hasLockedEntryUnreadFor(convId)) {
      return globalModel.lockedEntryUnreadCount;
    }
    final live = globalModel.receivedNewMessageCountFor(convId);
    return live > safeUnreadCount ? live : safeUnreadCount;
  }

  bool _isOverscrollingPastTop(ScrollMetrics metrics) {
    if (!metrics.hasPixels || !metrics.hasContentDimensions) {
      return false;
    }
    return metrics.pixels >
        metrics.maxScrollExtent + _loadPreviousOverscrollTolerancePx;
  }

  double _clampScrollPixelsForPosition(ScrollPosition position, double pixels) {
    if (!position.hasContentDimensions) {
      return pixels;
    }
    return pixels.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  bool _isReadingHistory({double? threshold}) {
    final globalModel = widget.model.globalModel;
    final conversationID = _conversationId();
    if (!globalModel.isUserScrollToBottomInProgress(conversationID) &&
        (widget.model.haveMoreLatestData ||
            globalModel.memoryWindowMissingNewer(conversationID) ||
            globalModel.hasDurableHistoryDeferred(conversationID) ||
            globalModel.isSearchJumpPending(conversationID) ||
            globalModel.getMessageListPosition(conversationID) ==
                HistoryMessagePosition.notShowLatest)) {
      return true;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final effectiveThreshold = threshold ?? _readingHistoryThresholdPx;
    return position.pixels > position.minScrollExtent + effectiveThreshold;
  }

  bool _isFollowingLatest() {
    return _chatGlobalModel?.isFollowingLatest(_conversationId()) ?? true;
  }

  bool get _hasLiveCenter {
    final key = _livePartitionAnchorHeadKey;
    return key != null && key.isNotEmpty;
  }

  bool _isLatestMemoryWindow() {
    return widget.model.isLiveRestoreDataReady;
  }

  bool _isLiveViewportPushActive() {
    final globalModel = _chatGlobalModel;
    if (globalModel == null) {
      return false;
    }
    return globalModel.isInboundViewportPushActive(_conversationId()) ||
        _viewportInsert.continuousViewportPushActive ||
        _viewportInsert.viewportInsertSlideActive;
  }

  Map<String, Object?> _readingHistoryScrollSnapshot() {
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return const <String, Object?>{'scrollReady': false};
    }
    return <String, Object?>{
      'scrollReady': true,
      'pixels': position.pixels.toStringAsFixed(1),
      'minExtent': position.minScrollExtent.toStringAsFixed(1),
      'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
      'viewport': position.viewportDimension.toStringAsFixed(1),
      'distanceFromBottom':
          (position.pixels - position.minScrollExtent).toStringAsFixed(1),
    };
  }

  void _logReadingHistoryIncoming(
    String action, {
    Map<String, Object?> extras = const <String, Object?>{},
    TUIChatGlobalModel? globalModel,
  }) {
    final model = globalModel ?? _chatGlobalModel;
    ChatJitterDiag.logReadingHistoryIncoming(
      action: action,
      conv: _conversationId(),
      extras: <String, Object?>{
        'followingLatest': _isFollowingLatest(),
        'liveCenterFrozen': _hasLiveCenter,
        'readingHistory': _isReadingHistory(),
        'anchorPixels': _incomingScrollAnchorPixels,
        'historyProtected': _isHistoryScrollProtected,
        if (model != null)
          'listPosition': model.getMessageListPosition(_conversationId()).name,
        if (model != null) 'tongueUnread': model.unreadCountForTongue,
        ..._readingHistoryScrollSnapshot(),
        ...extras,
      },
    );
  }

  int _layoutUnreadCount(int safeUnreadCount) {
    final globalModel = _chatGlobalModel;
    // Deferred arrivals already live outside the committed window. Their
    // presence must not freeze a different window installed by navigation.
    if (_unreadWindowJumpInFlight && _entryUnreadOrigin == null) return 0;
    final menuTransactionActive = globalModel != null &&
        !globalModel.isSearchJumpPending(_conversationId()) &&
        (globalModel.isMessageContextMenuOverlayOpen ||
            globalModel.isContextMenuViewportRestoreActive(_conversationId()));
    if (menuTransactionActive) {
      return _contextMenuFrozenLayoutUnreadCount ??=
          _lastResolvedLayoutUnreadCount.clamp(0, safeUnreadCount);
    }
    _contextMenuFrozenLayoutUnreadCount = null;

    final int resolved;
    if (safeUnreadCount <= 0) {
      resolved = 0;
    } else if (!_firstUnreadAnchorJumped &&
        globalModel?.getMessageListPosition(_conversationId()) ==
            HistoryMessagePosition.bottom) {
      resolved = 0;
    } else {
      resolved = safeUnreadCount;
    }
    _lastResolvedLayoutUnreadCount = resolved;
    return resolved;
  }

  bool _syncFollowingLatestFromUserScroll({
    required bool userGesture,
    bool towardHistory = false,
    bool towardLatest = false,
    bool scrollEnded = false,
    bool dragActive = false,
    int anchorRetryFrames = 2,
  }) {
    final globalModel = _chatGlobalModel;
    if (globalModel == null) {
      return false;
    }
    if (!_isLatestMemoryWindow()) {
      return false;
    }
    final convId = _conversationId();
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final distance = position.pixels - position.minScrollExtent;
    final following = globalModel.isFollowingLatest(convId);
    final userIntent = userGesture || globalModel.isChatListUserScrolling;
    void logBlocked(String reason) {
      ChatJitterDiag.logFollowingLatest(
        action: following ? 'leave_blocked' : 'restore_blocked',
        conv: convId,
        extras: <String, Object?>{
          'reason': reason,
          'distance': distance.toStringAsFixed(1),
          'userGesture': userGesture,
          'towardHistory': towardHistory,
          'towardLatest': towardLatest,
          'scrollEnded': scrollEnded,
          'userScrolling': globalModel.isChatListUserScrolling,
          'pushActive': _isLiveViewportPushActive(),
          'returning': globalModel.isUserScrollToBottomInProgress(convId),
          'outOfRange': position.outOfRange,
          'following': following,
        },
        throttleKey: following ? 'leave_blocked' : 'restore_blocked',
        minIntervalMs: 250,
      );
    }

    if (globalModel.isGeometryViewportTransitionActive(convId)) {
      logBlocked('geometry_viewport');
      return false;
    }

    if (following) {
      // 手指正在拖动时用户意图优先于收消息的自动上推：global 侧的 push 引用
      // 计数有 settle 延迟，等它清掉会让「离开跟随」拖到 200px 以后才生效，
      // 期间上推和手指反向打架。点胶囊回底是用户自己要求的动作，仍不可打断。
      final gestureOverridesPush =
          dragActive && towardHistory && distance > _followingLatestEpsilonPx;
      if (globalModel.isUserScrollToBottomInProgress(convId)) {
        if (userIntent && distance > _followingLatestEpsilonPx) {
          logBlocked('returning');
        }
        return false;
      }
      if (_isLiveViewportPushActive() && !gestureOverridesPush) {
        if (userIntent && distance > _followingLatestEpsilonPx) {
          logBlocked('push_active');
        }
        return false;
      }
      if (!userIntent) {
        return false;
      }
      if (distance <= BackToBottomCapsulePolicy.followExitThresholdPx) {
        if (userIntent) {
          logBlocked('within_follow_exit');
        }
        return false;
      }
      if (!towardHistory) {
        logBlocked('not_toward_history');
        return false;
      }
      globalModel.setFollowingLatest(convId, false, notify: false);
      widget.model.freezeVisibleHistoryWindowIfNeeded();
      _logReadingHistoryIncoming('following_latest_leave');
      ChatJitterDiag.logFollowingLatest(
        action: 'leave',
        conv: convId,
        extras: <String, Object?>{
          'distance': distance.toStringAsFixed(1),
          'towardHistory': towardHistory,
          'dragActive': dragActive,
          'pushActive': _isLiveViewportPushActive(),
          'overrodePush': gestureOverridesPush,
        },
      );
      return true;
    }
    if (_isLiveViewportPushActive()) {
      logBlocked('push_active');
      return false;
    }
    if (position.outOfRange) {
      if (scrollEnded) {
        logBlocked('out_of_range');
      }
      return false;
    }
    final bufferedCount = globalModel.deferredIncomingBufferedCount(convId);
    if (bufferedCount > 0) {
      if (widget.model.haveMoreLatestData ||
          globalModel.memoryWindowMissingNewer(convId) ||
          widget.model.hasHistoryKnownTipMissing) {
        return false;
      }
      // Keep a bounded batch ahead of an active drag/fling. A single row per
      // layout-settle cycle cannot keep up with continuous finger movement:
      // the reader repeatedly hits the temporary minimum scroll extent.
      // Attachment is only preloading; unread progress still follows visible
      // row bottoms. Idle readers retain the one-row staging policy.
      if (globalModel.isUserScrollToBottomInProgress(convId)) {
        // 点胶囊回底事务自己冲刷全部缓冲。
        return false;
      }
      if (!scrollEnded && !towardLatest) {
        return false;
      }
      if (_progressiveRevealGrowthPending) {
        return false;
      }
      if (_paginationUi.isLoadingPrevious ||
          _paginationUi.loadPreviousTask != null ||
          _shouldCompensateScrollForPagination()) {
        return false;
      }
      final runway = _bufferedRevealRunwayPx(position);
      if (distance > runway) {
        if (scrollEnded) {
          logBlocked('still_away');
        }
        return false;
      }
      if (!_beginBufferedRevealAnchor()) {
        // A scroll notification can arrive before the row's layout settles.
        // Keep the buffer intact and retry after paint, using fresh geometry.
        if (anchorRetryFrames > 0 && !_bufferedRevealAnchorRetryScheduled) {
          _bufferedRevealAnchorRetryScheduled = true;
          final pixels = position.pixels;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _bufferedRevealAnchorRetryScheduled = false;
            if (!mounted || _conversationId() != convId) return;
            final latestPosition = _singleScrollPositionOrNull();
            // Do not admit rows after the reader changes direction.
            if (latestPosition == null || latestPosition.pixels > pixels + 0.5) {
              return;
            }
            _syncFollowingLatestFromUserScroll(
              userGesture: userGesture,
              towardLatest: towardLatest,
              scrollEnded: scrollEnded,
              dragActive: dragActive,
              anchorRetryFrames: anchorRetryFrames - 1,
            );
          });
          WidgetsBinding.instance.scheduleFrame();
        }
        return false;
      }
      _latchProgressiveNewestBoundary();
      _beginProgressiveRevealGrowth();
      final revealLimit = position.isScrollingNotifier.value
          ? 8
          : HistoryMessageDartConstant.revealBufferedTowardLatestStepCount;
      final revealed = widget.model.revealBufferedIncomingTowardLatest(
        limit: revealLimit,
        skipCooldown: true,
      );
      if (!revealed) {
        _clearProgressiveRevealGrowth(reason: 'reveal_refused');
        _clearBufferedRevealAnchor(reason: 'reveal_refused');
        return false;
      }
      _logReadingHistoryIncoming('following_latest_reveal');
      ChatJitterDiag.logFollowingLatest(
        action: 'reveal_toward_latest',
        conv: convId,
        extras: <String, Object?>{
          'distance': distance.toStringAsFixed(1),
          'scrollEnded': scrollEnded,
          'towardLatest': towardLatest,
          'runway': runway.toStringAsFixed(1),
          'limit': revealLimit,
          'buffered': globalModel.deferredIncomingBufferedCount(convId),
        },
      );
      return false;
    }
    if (distance > _followingLatestEpsilonPx) {
      if (scrollEnded) {
        logBlocked('still_away');
      }
      return false;
    }
    if (!scrollEnded &&
        !globalModel.isUserScrollToBottomInProgress(convId)) {
      return false;
    }
    if (_hasLiveCenter) {
      // The confirmation path first translates the fixed center back to the
      // ordinary bottom. Never enter live animations with the old center.
      _scheduleVisibleLatestConfirmation();
      return false;
    }
    logBlocked('waiting_for_visible_confirmation');
    return false;
  }

  void _maybeLatchLiveNewestSliver() {
    if (!_isFollowingLatest()) {
      return;
    }
    _syncFollowingLatestFromUserScroll(
      userGesture: _userScrollGestureActive ||
          (_chatGlobalModel?.isChatListUserScrolling ?? false),
      towardHistory: true,
    );
  }

  void _maybeReleaseLiveNewestSliver() {
    _syncFollowingLatestFromUserScroll(
      userGesture: _userScrollGestureActive ||
          (_chatGlobalModel?.isChatListUserScrolling ?? false),
      scrollEnded: true,
    );
  }

  void _maybeReleaseUnreadCenterDeferral() {
    if (!_deferUnreadCenterPartition) {
      return;
    }
    if (_isReadingHistory()) {
      return;
    }
    _deferUnreadCenterPartition = false;
    _clearIncomingScrollAnchor(reason: 'release_defer');
    _logReadingHistoryIncoming('defer_partition_release');
  }

  bool _shouldCompensateScrollForPagination() {
    if (_paginationUi.isLoadingPrevious ||
        _paginationUi.paginationRestoreAnchorMsgID != null ||
        _paginationUi.paginationRestoreAnchorSeq != null ||
        _paginationUi.previousLoadInFlightAnchorKey != null) {
      return true;
    }
    final until = _paginationUi.scrollPaginationCompensationUntilMs;
    return until > 0 && DateTime.now().millisecondsSinceEpoch < until;
  }

  void _captureIncomingScrollAnchor(TUIChatGlobalModel globalModel) {
    if (globalModel.isChatListUserScrolling) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }
    if (_incomingScrollAnchorPixels == null) {
      _incomingScrollAnchorPixels = position.pixels;
      _incomingScrollAnchorMaxExtent = position.maxScrollExtent;
    }
  }

  void _clearIncomingScrollAnchor({String? reason}) {
    if (_incomingScrollAnchorPixels == null &&
        _incomingScrollAnchorMaxExtent == null) {
      return;
    }
    _incomingScrollAnchorPixels = null;
    _incomingScrollAnchorMaxExtent = null;
    _incomingScrollAnchorGeneration++;
    if (reason != null) {
      _logReadingHistoryIncoming(
        'scroll_anchor_clear',
        extras: <String, Object?>{'reason': reason},
      );
    }
  }

  /// 渐进接缓冲的「跑道」：视口底边距列表底部小于该值时接下一条，让新行
  /// 在用户滑到之前已经完成 layout；下限覆盖快速甩动时约两帧的位移。
  double _bufferedRevealRunwayPx(ScrollPosition position) {
    const minPx = HistoryMessageDartConstant.revealBufferedTowardLatestRunwayMinPx;
    final viewport =
        position.hasViewportDimension ? position.viewportDimension : 0.0;
    if (viewport <= 0) {
      return minPx;
    }
    // Start staging a screen ahead while moving. The idle quarter-screen
    // runway can be consumed before the current batch has finished layout.
    if (position.isScrollingNotifier.value) {
      return max(viewport, minPx);
    }
    return max(
      viewport *
          HistoryMessageDartConstant.revealBufferedTowardLatestRunwayViewportRatio,
      minPx,
    );
  }

  void _latchProgressiveNewestBoundary({List<V2TimMessage?>? previousMessages}) {
    if (!_hasLiveCenter &&
        _atJumpOrigin == null &&
        _entryUnreadOrigin == null &&
        widget.searchJumpAnchor == null &&
        widget.initFindingMsg == null) {
      final head = (previousMessages ?? _currentVisibleMessageList())
          .whereType<V2TimMessage>()
          .where((message) => message.elemType != 11)
          .firstOrNull;
      if (head != null) {
        _livePartitionAnchorHeadKey = _messageIdentity(head);
        _livePartitionAnchorHeadMessage = head;
      }
    }
  }

  /// 标记一条缓冲等待布局，避免同一帧再接第二条；位置由真实行锚点补偿。
  void _beginProgressiveRevealGrowth() {
    _progressiveRevealGrowthPending = true;
    final generation = ++_progressiveRevealGeneration;
    _scheduleProgressiveRevealGrowthExpiry(
      generation,
      _progressiveRevealGrowthMaxFrames,
    );
  }

  void _scheduleProgressiveRevealGrowthExpiry(int generation, int framesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _progressiveRevealGeneration ||
          !_progressiveRevealGrowthPending) {
        return;
      }
      if (framesLeft <= 1) {
        _clearProgressiveRevealGrowth(reason: 'frames_exhausted');
        return;
      }
      _scheduleProgressiveRevealGrowthExpiry(generation, framesLeft - 1);
    });
    // A stable center can need no geometry correction and no further paint.
    // Drive this bounded expiry so an idle reader still gets the next row.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _clearProgressiveRevealGrowth({required String reason}) {
    if (!_progressiveRevealGrowthPending) {
      return;
    }
    _progressiveRevealGrowthPending = false;
    _progressiveRevealGeneration++;
    if (reason != 'reveal_refused') {
      final conv = _conversationId();
      final model = widget.model;
      // Fill the small measured runway after layout, even if the last gesture
      // has ended. Otherwise the next gesture can hit yesterday's list edge
      // before its next row is attached and require an extra swipe.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(widget.model, model) ||
            _conversationId() != conv ||
            ModalRoute.of(context)?.isCurrent == false ||
            model.globalModel.hasDurableHistoryDeferred(conv) ||
            model.globalModel.deferredIncomingBufferedCount(conv) == 0) return;
        _syncFollowingLatestFromUserScroll(
            userGesture: false, towardLatest: true, scrollEnded: true);
      });
      WidgetsBinding.instance.scheduleFrame();
    }
    ChatJitterDiag.logFollowingLatest(
      action: 'reveal_growth_clear',
      conv: _conversationId(),
      extras: <String, Object?>{'reason': reason},
    );
  }

  /// 最后一条缓冲接完后 300ms 内到底，会被 didAttachBufferedTowardLatestRecently
  /// 拒绝恢复跟随，而之后没有任何事件再触发判定。这里在 cooldown 过后补一次。
  void _scheduleFollowingLatestRestoreRetry() {
    _followingLatestRestoreRetryTimer?.cancel();
    _followingLatestRestoreRetryTimer = Timer(
      const Duration(
        milliseconds: ChatListPaginationUiGate.loadLatestCooldownMs + 20,
      ),
      () {
        _followingLatestRestoreRetryTimer = null;
        if (!mounted) {
          return;
        }
        final globalModel = _chatGlobalModel;
        if (globalModel == null ||
            globalModel.isChatListUserScrolling ||
            _userScrollGestureActive ||
            _isFollowingLatest()) {
          return;
        }
        if (globalModel.deferredIncomingBufferedCount(_conversationId()) > 0) {
          return;
        }
        _maybeReleaseLiveNewestSliver();
      },
    );
  }

  void _cancelFollowingLatestRestoreRetry() {
    _followingLatestRestoreRetryTimer?.cancel();
    _followingLatestRestoreRetryTimer = null;
  }

  bool _bufferedRevealAnchorRetryScheduled = false;

  /// Keep one real message fixed during a newer-page or buffered-row insert.
  /// ScrollPhysics corrects its geometry before paint, including during a drag.
  bool _beginBufferedRevealAnchor({
    bool scheduleRestore = true,
    List<V2TimMessage?>? previousMessages,
  }) {
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final anchor = _captureVisiblePaginationViewportAnchor(
      messages: previousMessages,
    );
    _revealViewportAnchor = anchor;
    final index = anchor == null
        ? null
        : previousMessages != null
            ? previousMessages.indexWhere((message) =>
                message != null &&
                (message.msgID == anchor.msgID ||
                    (anchor.seq != null &&
                        int.tryParse(message.seq ?? '') == anchor.seq)))
            : _globalIndexForPreviousLoadAnchor(
                _PreviousLoadAnchor(msgID: anchor.msgID, seq: anchor.seq));
    _revealAnchorRenderObject = index == null
        ? null
        : _autoScrollController.tagMap[-index]?.context.findRenderObject();
    _revealGeometryAnchor =
        HistoryReadingViewportAnchor.capture(_revealAnchorRenderObject);
    if (_revealViewportAnchor == null || _revealGeometryAnchor == null) {
      _clearBufferedRevealAnchor(reason: 'capture_unavailable');
      return false;
    }
    _revealAnchorGeneration++;
    if (scheduleRestore) _scheduleBufferedRevealAnchorRestore();
    return true;
  }

  double? _correctNewestInsertFromVisibleAnchor(ScrollMetrics metrics) {
    final anchor = _revealViewportAnchor;
    final geometry = _revealGeometryAnchor;
    if (anchor == null || geometry == null) return null;
    final global = _chatGlobalModel;
    if (global?.isFollowingLatest(_conversationId()) == true ||
        global?.isUserScrollToBottomInProgress(_conversationId()) == true ||
        global?.isSearchJumpPending(_conversationId()) == true ||
        global?.isMessageContextMenuOverlayOpen == true ||
        _paginationUi.isLoadingPrevious) {
      _clearBufferedRevealAnchor(reason: 'viewport_owner_changed');
      return null;
    }
    // Keep the measured render identity through layout. tagMap can still
    // contain deactivated elements while offscreen children are being removed.
    final row = _revealAnchorRenderObject;
    // Do not fall back to a noisy extent estimate while this row is relaying
    // out. A subsequent viewport layout will measure the same identity.
    if (row == null || !row.attached || _renderObjectNeedsLayout(row)) return 0.0;
    return geometry.correctionFor(row) ?? 0.0;
  }

  void _scheduleBufferedRevealAnchorRestore({int attempt = 0}) {
    final generation = _revealAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _revealAnchorGeneration) {
        return;
      }
      _restoreBufferedRevealAnchor(
        attempt: attempt,
        generation: generation,
      );
    });
  }

  void _restoreBufferedRevealAnchor({
    required int attempt,
    required int generation,
  }) {
    if (!mounted || generation != _revealAnchorGeneration) {
      return;
    }
    if (_revealViewportAnchor == null || _revealGeometryAnchor == null) {
      return;
    }
    // Cleanup only. Moving pixels in a post-frame callback paints the displaced
    // row first and then snaps it back; all corrections belong to layout.
    if (attempt < _revealAnchorMaxAttempts) {
      _scheduleBufferedRevealAnchorRestore(attempt: attempt + 1);
    } else {
      _clearBufferedRevealAnchor(reason: 'attempts_exhausted');
    }
  }

  void _clearBufferedRevealAnchor({String? reason}) {
    if (_revealViewportAnchor == null && _revealGeometryAnchor == null) {
      return;
    }
    _revealViewportAnchor = null;
    _revealGeometryAnchor = null;
    _revealAnchorRenderObject = null;
    _newestInsertRoom = 0.0;
    _newestInsertRoomAtMs = 0;
    _revealAnchorGeneration++;
    if (reason != null) {
      ChatJitterDiag.logFollowingLatest(
        action: 'reveal_anchor_clear',
        conv: _conversationId(),
        extras: <String, Object?>{'reason': reason},
      );
    }
  }

  int? _globalIndexForContextMenuAnchor(
    MessageContextMenuViewportAnchor anchor,
  ) {
    final identity = anchor.identity?.trim() ?? '';
    final messageList = _currentVisibleMessageList();
    if (identity.isNotEmpty) {
      for (var index = 0; index < messageList.length; index++) {
        final message = messageList[index];
        if (message == null || message.elemType == 11) {
          continue;
        }
        final msgID = message.msgID?.trim() ?? '';
        final localID = message.id?.toString().trim() ?? '';
        if (msgID == identity || localID == identity) {
          return index;
        }
      }
    }
    final seq = anchor.seq?.trim() ?? '';
    if (seq.isNotEmpty) {
      for (var index = 0; index < messageList.length; index++) {
        final message = messageList[index];
        if (message != null && message.elemType != 11 && message.seq == seq) {
          return index;
        }
      }
    }
    return null;
  }

  BuildContext? _contextForContextMenuAnchor(
    MessageContextMenuViewportAnchor anchor,
    int globalIndex,
  ) {
    final messageList = _currentVisibleMessageList();
    if (globalIndex < 0 || globalIndex >= messageList.length) {
      return null;
    }
    final expectedKey = ValueKey(
      _stableMessageListKey(messageList[globalIndex], globalIndex),
    );
    // AutoScrollController's tagMap is indexed by a mutable ordinal. During
    // partition/history updates that ordinal can lag the current projection;
    // search by the stable ValueKey before accepting a RenderBox.
    for (final tag in _autoScrollController.tagMap.values) {
      final context = tag.context;
      if (context.widget.key == expectedKey) {
        return context;
      }
    }
    return null;
  }

  void _scheduleContextMenuViewportRestore({int attempt = 0}) {
    final globalModel = _chatGlobalModel;
    if (globalModel == null ||
        !globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      _contextMenuViewportRestoreScheduled = false;
      _contextMenuViewportRestoreCallbackPending = false;
      return;
    }
    // Rebuilds can request restore repeatedly in the same frame. Keep a
    // single post-frame callback; duplicate callbacks otherwise issue several
    // jumpTo calls against the same layout pass and make the close look like
    // a visible bounce.
    if (_contextMenuViewportRestoreCallbackPending) {
      return;
    }
    _contextMenuViewportRestoreCallbackPending = true;
    if (!_contextMenuViewportRestoreScheduled) {
      _contextMenuViewportRestoreScheduled = true;
      _contextMenuViewportStableFrames = 0;
      _contextMenuViewportRestoreGeneration++;
    }
    final generation = _contextMenuViewportRestoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contextMenuViewportRestoreCallbackPending = false;
      if (!mounted ||
          generation != _contextMenuViewportRestoreGeneration ||
          !_contextMenuViewportRestoreScheduled) {
        return;
      }
      _restoreContextMenuViewportAnchorIfNeeded(
        globalModel: globalModel,
        attempt: attempt,
        generation: generation,
      );
    });
  }

  void _finishContextMenuViewportRestore(TUIChatGlobalModel globalModel) {
    _contextMenuViewportRestoreScheduled = false;
    _contextMenuViewportRestoreCallbackPending = false;
    _contextMenuViewportStableFrames = 0;
    _contextMenuViewportRestoreGeneration++;
    globalModel.completeContextMenuViewportRestore(_conversationId());
  }

  void _restoreContextMenuViewportAnchorIfNeeded({
    required TUIChatGlobalModel globalModel,
    required int attempt,
    required int generation,
  }) {
    if (!mounted ||
        generation != _contextMenuViewportRestoreGeneration ||
        !_contextMenuViewportRestoreScheduled) {
      return;
    }
    final convId = _conversationId();
    if (!globalModel.isContextMenuViewportRestoreActive(convId)) {
      _contextMenuViewportRestoreScheduled = false;
      return;
    }
    // A real gesture always wins over an automatic menu-close correction.
    if (globalModel.isChatListUserScrolling) {
      _finishContextMenuViewportRestore(globalModel);
      return;
    }
    final anchor = globalModel.contextMenuViewportAnchorFor(convId);
    final currentPixels = _singleScrollPositionOrNull()?.pixels;
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[MessageContextTrace] restore_attempt conv=$convId '
        'attempt=$attempt anchor=${anchor?.identity}/${anchor?.seq} '
        'desiredTop=${anchor?.viewportTop} pixels=$currentPixels '
        'rawCount=${globalModel.rawMessageCount(convId)}',
      );
    }
    if (anchor == null) {
      _contextMenuViewportStableFrames = 0;
      if (attempt < 300) {
        _scheduleContextMenuViewportRestore(attempt: attempt + 1);
      } else {
        _finishContextMenuViewportRestore(globalModel);
      }
      return;
    }
    final globalIndex = _globalIndexForContextMenuAnchor(anchor);
    final position = _singleScrollPositionOrNull();
    if (globalIndex == null ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      // The reverse sliver can need several frames to mount the selected row
      // after a buffered flush. Giving up at 8 frames releases the restore
      // gate while the row is still absent, allowing the inbound viewport
      // ticker to take over and visibly drag the list to the edge.
      _contextMenuViewportStableFrames = 0;
      if (attempt < 300) {
        _scheduleContextMenuViewportRestore(attempt: attempt + 1);
      } else {
        _finishContextMenuViewportRestore(globalModel);
      }
      return;
    }
    final tagContext = _contextForContextMenuAnchor(anchor, globalIndex);
    final scrollable =
        tagContext == null ? null : Scrollable.maybeOf(tagContext);
    final target = tagContext?.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (target is! RenderBox ||
        viewport is! RenderBox ||
        !target.attached ||
        !viewport.attached ||
        !target.hasSize ||
        !viewport.hasSize ||
        _renderObjectNeedsLayout(target) ||
        _renderObjectNeedsLayout(viewport)) {
      _contextMenuViewportStableFrames = 0;
      if (attempt < 300) {
        _scheduleContextMenuViewportRestore(attempt: attempt + 1);
      } else {
        _finishContextMenuViewportRestore(globalModel);
      }
      return;
    }
    final currentTop = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final targetPixels =
        HistoryPaginationScrollPhysics.restorePixelsForViewportAnchor(
      axisDirection: position.axisDirection,
      currentPixels: position.pixels,
      currentAnchorTop: currentTop,
      desiredAnchorTop: anchor.viewportTop,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    final correction = targetPixels - position.pixels;
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[MessageContextTrace] restore_calc conv=$convId '
        'attempt=$attempt index=$globalIndex currentTop=$currentTop '
        'desiredTop=${anchor.viewportTop} pixels=${position.pixels} '
        'target=$targetPixels correction=$correction '
        'min=${position.minScrollExtent} max=${position.maxScrollExtent}',
      );
    }
    if (correction.abs() > 0.5) {
      _contextMenuViewportStableFrames = 0;
      _geomJumpTo(
        targetPixels,
        reason: 'jump__restoreContextMenuViewportAnchor',
      );
      ChatJitterDiag.logInboundFlow(
        action: 'context_menu_viewport_anchor_restore',
        conv: convId,
        extras: <String, Object?>{
          'identity': anchor.identity,
          'seq': anchor.seq,
          'globalIndex': globalIndex,
          'beforeTop': currentTop.toStringAsFixed(1),
          'desiredTop': anchor.viewportTop.toStringAsFixed(1),
          'correction': correction.toStringAsFixed(1),
          'attempt': attempt,
        },
      );
    } else {
      _contextMenuViewportStableFrames++;
    }
    // Success is geometric, not time based: only release after the exact row
    // remains within tolerance for three consecutive laid-out frames.
    if (_contextMenuViewportStableFrames >= 3) {
      _finishContextMenuViewportRestore(globalModel);
    } else if (attempt < 300) {
      _scheduleContextMenuViewportRestore(attempt: attempt + 1);
    } else {
      _finishContextMenuViewportRestore(globalModel);
    }
  }

  void _scheduleIncomingScrollAnchorRestore({int attempt = 0}) {
    final generation = _incomingScrollAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _incomingScrollAnchorGeneration) {
        return;
      }
      _restoreIncomingScrollAnchorIfNeeded(
        attempt: attempt,
        generation: generation,
      );
    });
  }

  void _restoreIncomingScrollAnchorIfNeeded({
    required int attempt,
    required int generation,
  }) {
    if (!mounted || generation != _incomingScrollAnchorGeneration) {
      return;
    }
    final globalModel = _chatGlobalModel;
    if (globalModel?.isChatListUserScrolling ?? false) {
      return;
    }
    if (_hasLiveCenter) {
      return;
    }
    if (!_deferUnreadCenterPartition && !_isReadingHistory()) {
      _clearIncomingScrollAnchor();
      return;
    }
    final anchor = _incomingScrollAnchorPixels;
    if (anchor == null) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      if (attempt < 8) {
        _scheduleIncomingScrollAnchorRestore(attempt: attempt + 1);
      }
      return;
    }
    // reverse 列表在最新侧插入会增大 maxExtent。只钉回插入前的 pixels
    // 会把人正在看的历史顶向底部（往上推）。按 extent 增量把阅读位置钉住。
    final oldMax = _incomingScrollAnchorMaxExtent;
    final maxDelta =
        oldMax == null ? 0.0 : position.maxScrollExtent - oldMax;
    final target = (anchor + maxDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final before = position.pixels;
    final drift = (before - target).abs();
    if (drift > 1.0) {
      _geomJumpTo(target, reason: 'jump__restoreIncomingScrollAnchorIfNeeded');
      _logReadingHistoryIncoming(
        'scroll_anchor_restore',
        globalModel: globalModel,
        extras: <String, Object?>{
          'anchor': anchor.toStringAsFixed(1),
          'maxDelta': maxDelta.toStringAsFixed(1),
          'before': before.toStringAsFixed(1),
          'target': target.toStringAsFixed(1),
          'drift': drift.toStringAsFixed(1),
          'attempt': attempt,
          'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
        },
      );
    }
    if (attempt < 8) {
      _scheduleIncomingScrollAnchorRestore(attempt: attempt + 1);
    } else {
      _clearIncomingScrollAnchor();
    }
  }

  void _beginIncomingWhileReadingAnchorLock(TUIChatGlobalModel globalModel) {
    // 上拉分页已有专属的消息锚点与 extent 补偿。入站消息若在此期间再用
    // 加载前 pixels 建立多帧恢复，会和分页恢复争夺位置，造成来回跳动。
    if (_paginationUi.isLoadingPrevious ||
        _shouldCompensateScrollForPagination()) {
      _clearIncomingScrollAnchor(reason: 'pagination_precedence');
      _logReadingHistoryIncoming(
        'scroll_anchor_skip_pagination',
        globalModel: globalModel,
      );
      return;
    }
    _captureIncomingScrollAnchor(globalModel);
    _incomingScrollAnchorGeneration++;
    _logReadingHistoryIncoming(
      'scroll_anchor_lock',
      globalModel: globalModel,
      extras: <String, Object?>{
        'anchor': _incomingScrollAnchorPixels?.toStringAsFixed(1),
        'anchorMax': _incomingScrollAnchorMaxExtent?.toStringAsFixed(1),
      },
    );
    // 阅读位置由 ScrollPhysics.adjustPositionForNewDimensions 在绘制前补偿。
    // 这里再 jumpTo 会在画完被顶走的一帧后才拉回，造成闪一下。
  }

  void _beginScrollPaginationCompensation() {
    _extendScrollPaginationCompensation(
      milliseconds: _scrollPaginationCompensationMs,
    );
  }

  void _extendScrollPaginationCompensation({int? milliseconds}) {
    final extendMs = milliseconds ?? _scrollPaginationCompensationMs;
    final until = DateTime.now().millisecondsSinceEpoch + extendMs;
    if (until > _paginationUi.scrollPaginationCompensationUntilMs) {
      _paginationUi.scrollPaginationCompensationUntilMs = until;
    }
  }

  void _clearScrollPaginationCompensation() {
    _paginationUi.scrollPaginationCompensationUntilMs = 0;
  }

  void _scheduleScrollPaginationCompensationEnd({
    required int generation,
    required double anchorPixels,
    required double anchorMaxExtent,
    required _PaginationViewportAnchor? viewportAnchor,
  }) {
    _scheduleScrollPaginationPrependRestore(
      generation: generation,
      anchorPixels: anchorPixels,
      anchorMaxExtent: anchorMaxExtent,
      viewportAnchor: viewportAnchor,
      attempt: 0,
    );
  }

  void _scheduleScrollPaginationPrependRestore({
    required int generation,
    required double anchorPixels,
    required double anchorMaxExtent,
    required _PaginationViewportAnchor? viewportAnchor,
    required int attempt,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _paginationUi.scrollPaginationCompensationGeneration != generation) {
        return;
      }
      unawaited(
        _restoreScrollAfterPaginationPrepend(
          generation: generation,
          anchorPixels: anchorPixels,
          anchorMaxExtent: anchorMaxExtent,
          viewportAnchor: viewportAnchor,
          attempt: attempt,
        ),
      );
    });
  }

  void _resumePaginationRestoreAfterScrollEnd() {
    final pending = _pendingPaginationRestoreAfterScrollEnd;
    if (pending == null ||
        _paginationUi.scrollPaginationCompensationGeneration !=
            pending.generation) {
      return;
    }
    _pendingPaginationRestoreAfterScrollEnd = null;
    ChatHistoryTrace.log(
      'load_previous_restore_resumed_after_scroll_end',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'generation': pending.generation,
        'userScrolling': _chatGlobalModel?.isChatListUserScrolling,
      },
    );
    _scheduleScrollPaginationPrependRestore(
      generation: pending.generation,
      anchorPixels: pending.anchorPixels,
      anchorMaxExtent: pending.anchorMaxExtent,
      viewportAnchor: pending.viewportAnchor,
      attempt: 0,
    );
  }

  void _cancelPaginationRestoreForUserScroll({required String reason}) {
    final hadPending = _pendingPaginationRestoreAfterScrollEnd != null ||
        _shouldCompensateScrollForPagination() ||
        _paginationUi.paginationRestoreAnchorMsgID != null ||
        _paginationUi.paginationRestoreAnchorSeq != null;
    if (!hadPending) {
      return;
    }
    _paginationUi.scrollPaginationCompensationGeneration++;
    _pendingPaginationRestoreAfterScrollEnd = null;
    _clearPaginationRestoreAnchor();
    _clearScrollPaginationCompensation();
    ChatHistoryTrace.log(
      'load_previous_restore_cancelled_user_scroll',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'reason': reason,
        'userScrolling': _userScrollGestureActive,
        'pageUiUserScrolling': _pageUi.userScrolling.value,
      },
    );
  }

  Future<void> _restoreScrollAfterPaginationPrepend({
    required int generation,
    required double anchorPixels,
    required double anchorMaxExtent,
    required _PaginationViewportAnchor? viewportAnchor,
    required int attempt,
  }) async {
    const maxPinnedAnchorAttempts = 5;
    if (!mounted ||
        _paginationUi.scrollPaginationCompensationGeneration != generation) {
      return;
    }
    final userScrolling =
        (_chatGlobalModel?.isChatListUserScrolling ?? false) ||
            _userScrollGestureActive ||
            _pageUi.userScrolling.value;
    if (userScrolling) {
      _pendingPaginationRestoreAfterScrollEnd = _PaginationRestoreRequest(
        generation: generation,
        anchorPixels: anchorPixels,
        anchorMaxExtent: anchorMaxExtent,
        viewportAnchor: viewportAnchor,
      );
      ChatHistoryTrace.log(
        'load_previous_restore_waiting_for_scroll_end',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'generation': generation,
          'attempt': attempt,
          'userScrolling': true,
          'gestureActive': _userScrollGestureActive,
          'pageUiUserScrolling': _pageUi.userScrolling.value,
        },
      );
      return;
    }
    if (_pendingPaginationRestoreAfterScrollEnd?.generation == generation) {
      _pendingPaginationRestoreAfterScrollEnd = null;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      if (attempt >= maxPinnedAnchorAttempts - 1) {
        ChatHistoryTrace.log(
          'load_previous_viewport_anchor_restore_skipped',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'reason': 'scroll_position_not_ready',
            'attempt': attempt,
            'hasPosition': position != null,
            'hasPixels': position?.hasPixels,
            'hasContentDimensions': position?.hasContentDimensions,
          },
        );
      }
      if (attempt < maxPinnedAnchorAttempts - 1) {
        _scheduleScrollPaginationPrependRestore(
          generation: generation,
          anchorPixels: anchorPixels,
          anchorMaxExtent: anchorMaxExtent,
          viewportAnchor: viewportAnchor,
          attempt: attempt + 1,
        );
      } else {
        _clearPaginationRestoreAnchor();
        _clearScrollPaginationCompensation();
        _cancelPaginationPrependReveal(notify: false);
        if (mounted) {
          setState(() {});
        }
      }
      return;
    }

    // This chat is rendered as one `reverse: true` viewport. Older pages are
    // appended to the read sliver's visual top, so Flutter's layout already
    // keeps the mounted rows at the same viewport coordinates while the
    // extent grows. Do not replay the pre-request `pixels` value here. When
    // the boundary row is outside the cache, the old fallback used to jump
    // from a transient 0 to the stale offset (for example 0 -> 4821), and
    // every later page made that oscillation visible. Telegram's equivalent
    // path gives the active gesture/native layout precedence for the same
    // reason. Anchor recovery remains available for non-reversed lists.
    if (position.axisDirection == AxisDirection.up ||
        position.axisDirection == AxisDirection.left) {
      ChatHistoryTrace.log(
        'load_previous_reverse_append_native',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'attempt': attempt,
          'pixels': position.pixels,
          'maxExtent': position.maxScrollExtent,
          'oldMaxExtent': anchorMaxExtent,
          'extentDelta': position.maxScrollExtent - anchorMaxExtent,
          'viewportAnchor': viewportAnchor != null,
          'userScrolling': false,
        },
      );
      _clearPaginationRestoreAnchor();
      _clearScrollPaginationCompensation();
      _cancelPaginationPrependReveal(notify: false);
      return;
    }

    final viewportAnchorRestored = viewportAnchor != null &&
        _restorePaginationViewportAnchor(
          anchor: viewportAnchor,
          position: position,
          attempt: attempt,
        );
    final compensationPath = viewportAnchorRestored
        ? 'message_viewport_anchor'
        : 'extent_delta_fallback';
    final pinnedAtLoad = _wasPinnedNearTopForPagination(
      anchorPixels: anchorPixels,
      anchorMaxExtent: anchorMaxExtent,
    );
    final overscrollAtLoad =
        HistoryPaginationScrollPhysics.wasOverscrollingPastTop(
      anchorPixels: anchorPixels,
      anchorMaxExtent: anchorMaxExtent,
      tolerancePx: ChatListPaginationUiGate.loadPreviousOverscrollTolerancePx,
    );

    double? expectedExtentDeltaPixels;
    if (anchorMaxExtent > 0) {
      expectedExtentDeltaPixels =
          HistoryPaginationScrollPhysics.computeExtentDeltaRestorePixels(
        anchorPixels: anchorPixels,
        anchorMaxExtent: anchorMaxExtent,
        newMaxScrollExtent: position.maxScrollExtent,
        minScrollExtent: position.minScrollExtent,
      );
    }

    final restoreMsgIDForLog =
        _paginationUi.paginationRestoreAnchorMsgID?.trim() ?? '';
    final isFinalAttempt = attempt >= maxPinnedAnchorAttempts - 1;
    ChatHistoryTrace.log(
      isFinalAttempt
          ? 'load_previous_scroll_compensation_done'
          : 'load_previous_scroll_compensation_step',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'anchorPixels': anchorPixels,
        'anchorMaxExtent': anchorMaxExtent,
        'beforePixels': position.pixels,
        'pixels': position.pixels,
        'maxExtent': position.maxScrollExtent,
        'oldMaxExtent': anchorMaxExtent,
        'newMaxExtent': position.maxScrollExtent,
        'extentDelta': position.maxScrollExtent - anchorMaxExtent,
        'restoreMsgID': restoreMsgIDForLog,
        'path': compensationPath,
        'attempt': attempt,
        'axisDirection': position.axisDirection.name,
        'pinnedAtLoad': pinnedAtLoad,
        'overscrollAtLoad': overscrollAtLoad,
        'expectedExtentDeltaPixels': expectedExtentDeltaPixels,
        'viewportAnchorRestored': viewportAnchorRestored,
        'anchorViewportTop': viewportAnchor?.viewportTop,
      },
    );
    if (!viewportAnchorRestored &&
        position.axisDirection == AxisDirection.up &&
        // When an anchor row exists but is still outside the sliver cache,
        // let the viewport/physics settle first. Repeating jumpTo on every
        // post-frame retry makes the position alternate between the layout
        // correction (often 0) and the saved offset, which is the visible
        // shake reported during long history reads. Use the extent fallback
        // only when there is no row anchor, or once as a last-resort final
        // attempt after the row had a chance to mount.
        (viewportAnchor == null || isFinalAttempt)) {
      final fallbackPixels = anchorPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final drift = (position.pixels - fallbackPixels).abs();
      if (drift > 0.5) {
        _geomJumpTo(
          fallbackPixels,
          reason: 'jump__restorePaginationExtentAnchor',
        );
        ChatHistoryTrace.log(
          'load_previous_extent_anchor_restore',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'beforePixels': position.pixels,
            'afterPixels': fallbackPixels,
            'oldMaxExtent': anchorMaxExtent,
            'newMaxExtent': position.maxScrollExtent,
            'extentDelta': position.maxScrollExtent - anchorMaxExtent,
            'drift': drift,
            'axisDirection': position.axisDirection.name,
            'attempt': attempt,
          },
        );
      }
    }
    if (!isFinalAttempt) {
      _scheduleScrollPaginationPrependRestore(
        generation: generation,
        anchorPixels: anchorPixels,
        anchorMaxExtent: anchorMaxExtent,
        viewportAnchor: viewportAnchor,
        attempt: attempt + 1,
      );
      return;
    }
    _clearPaginationRestoreAnchor();
    _clearScrollPaginationCompensation();
    _cancelPaginationPrependReveal(notify: false);
    if (mounted) {
      setState(() {});
    }
  }

  bool _restorePaginationViewportAnchor({
    required _PaginationViewportAnchor anchor,
    required ScrollPosition position,
    required int attempt,
    int? resolvedGlobalIndex,
  }) {
    final globalIndex = resolvedGlobalIndex ??
        _globalIndexForPreviousLoadAnchor(
          _PreviousLoadAnchor(msgID: anchor.msgID, seq: anchor.seq),
        );
    if (globalIndex == null) {
      if (attempt >= 4) {
        ChatHistoryTrace.log(
          'load_previous_viewport_anchor_restore_skipped',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'reason': 'anchor_not_found',
            'attempt': attempt,
            'msgID': anchor.msgID,
            'seq': anchor.seq,
          },
        );
      }
      return false;
    }
    final tagContext = _autoScrollController.tagMap[-globalIndex]?.context;
    final scrollable =
        tagContext == null ? null : Scrollable.maybeOf(tagContext);
    final target = tagContext?.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (target is! RenderBox ||
        viewport is! RenderBox ||
        !target.attached ||
        !viewport.attached ||
        !target.hasSize ||
        !viewport.hasSize ||
        _renderObjectNeedsLayout(target) ||
        _renderObjectNeedsLayout(viewport)) {
      if (attempt >= 4) {
        ChatHistoryTrace.log(
          'load_previous_viewport_anchor_restore_skipped',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'reason': 'anchor_render_object_not_ready',
            'attempt': attempt,
            'globalIndex': globalIndex,
            'hasTagContext': tagContext != null,
            'targetType': target?.runtimeType.toString(),
            'viewportType': viewport?.runtimeType.toString(),
          },
        );
      }
      return false;
    }
    final currentTop = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final targetPixels =
        HistoryPaginationScrollPhysics.restorePixelsForViewportAnchor(
      axisDirection: position.axisDirection,
      currentPixels: position.pixels,
      currentAnchorTop: currentTop,
      desiredAnchorTop: anchor.viewportTop,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    final viewportDrift = currentTop - anchor.viewportTop;
    final pixelCorrection = targetPixels - position.pixels;
    if (pixelCorrection.abs() > 0.5) {
      _geomJumpTo(
        targetPixels,
        reason: 'jump__restorePaginationViewportAnchor',
      );
    }
    ChatHistoryTrace.log(
      'load_previous_viewport_anchor_restore',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'msgID': anchor.msgID,
        'seq': anchor.seq,
        'globalIndex': globalIndex,
        'attempt': attempt,
        'axisDirection': position.axisDirection.name,
        'desiredTop': anchor.viewportTop.toStringAsFixed(1),
        'currentTop': currentTop.toStringAsFixed(1),
        'viewportDrift': viewportDrift.toStringAsFixed(1),
        'pixelsBefore': position.pixels.toStringAsFixed(1),
        'targetPixels': targetPixels.toStringAsFixed(1),
      },
    );
    return true;
  }

  void _clearPaginationRestoreAnchor() {
    _paginationUi.paginationRestoreAnchorMsgID = null;
    _paginationUi.paginationRestoreAnchorSeq = null;
    _pendingPaginationRestoreAfterScrollEnd = null;
  }

  bool _wasPinnedNearTopForPagination({
    required double anchorPixels,
    required double anchorMaxExtent,
  }) {
    if (anchorMaxExtent <= 0) {
      return false;
    }
    return anchorPixels >= anchorMaxExtent - _loadPreviousTopNearPx;
  }

  ScrollPhysics? _buildHistoryScrollPhysics() {
    if (widget.isAllowScroll == false) {
      return const NeverScrollableScrollPhysics();
    }
    final globalModel = _chatGlobalModel ??
        Provider.of<TUIChatGlobalModel>(context, listen: false);
    // 全屏预览（尤其 opaque:false 下滑透出聊天）期间禁用列表滚动，
    // 避免下滑关闭手势穿透把会话记录拖走。
    if (globalModel.shouldLockChatScrollForMediaPreview) {
      return const NeverScrollableScrollPhysics();
    }
    // 微信式长按菜单打开时，底层聊天列表不响应拖动；滚动只留给菜单自身
    // 的长消息预览区域。
    if (globalModel.isMessageContextMenuOverlayOpen) {
      return const NeverScrollableScrollPhysics();
    }
    final configured = widget.mainHistoryListConfig?.physics;
    return HistoryPaginationScrollPhysics(
      parent: configured,
      newestInsertAnchorCorrection: _correctNewestInsertFromVisibleAnchor,
      shouldCompensate: _shouldCompensateScrollForPagination,
      // Newer SDK pages insert at the minimum edge of the reverse list.
      // Preserve the current rows before paint. Context-menu restoration
      // still uses its separate identity anchor without this compensation.
      // Search windows have a fixed sliver origin. Extent compensation here
      // would apply a second movement on top of Flutter's native anchoring.
      shouldPreserveNewestInsertExtent: _shouldPreserveNewestInsertExtent,
      lastSeenMaxExtent: () => _lastPhysicsMaxExtentSeen,
      onMaxExtentObserved: (value) => _lastPhysicsMaxExtentSeen = value,
      newestInsertRoom: () {
        if (_newestInsertRoom > 0 && _newestInsertRoomAtMs > 0) {
          final ageMs =
              DateTime.now().millisecondsSinceEpoch - _newestInsertRoomAtMs;
          if (ageMs > _newestInsertRoomTtlMs) {
            ChatJitterDiag.logFollowingLatest(
              action: 'newest_room_expire',
              conv: _conversationId(),
              extras: <String, Object?>{
                'dropped': _newestInsertRoom.toStringAsFixed(1),
                'ageMs': ageMs,
              },
            );
            _newestInsertRoom = 0.0;
            _newestInsertRoomAtMs = 0;
          }
        }
        return _newestInsertRoom;
      },
      revealGrowthPending: () => _progressiveRevealGrowthPending,
      onNewestInsertApplied: (applied) {
        // 渐进接缓冲是一次性的：实测增长补偿完就关掉全额通道，避免把后续
        // 无关的媒体撑高也算作这一条的高度。
        if (_progressiveRevealGrowthPending && applied > 0.5) {
          _clearProgressiveRevealGrowth(reason: 'applied');
        }
        // 懒布局让整批插入的真实增长跨多帧到达。一次补偿就清零预算，会让
        // 剩余增长在后续帧完全裸奔，净效果是视口被推到最新端。
        _newestInsertRoom -= applied;
        if (_newestInsertRoom <= 0.5) {
          _newestInsertRoom = 0.0;
          _newestInsertRoomAtMs = 0;
        }
      },
      pinnedNearTopTolerancePx: _loadPreviousTopNearPx,
    );
  }

  bool _shouldPreserveNewestInsertExtent() {
    if (_progressiveRevealGrowthPending) {
      return true;
    }
    if (_newestInsertRoom > 0.5) {
      return true;
    }
    if (_viewportInsert.continuousViewportPushActive ||
        _viewportInsert.viewportInsertSlideActive) {
      return false;
    }
    if (_chatGlobalModel?.isUserScrollToBottomInProgress(_conversationId()) ??
        false) {
      return false;
    }
    if (_chatGlobalModel?.isChatListUserScrolling ?? false) {
      return false;
    }
    if (widget.searchJumpAnchor != null ||
        widget.initFindingMsg != null ||
        _entryUnreadOrigin != null ||
        _atJumpOrigin != null) {
      return false;
    }
    if (_paginationUi.isLoadingLatest) {
      return true;
    }
    if (_deferUnreadCenterPartition) {
      return true;
    }
    return false;
  }

  ScrollPosition? _singleScrollPositionOrNull() {
    if (!_autoScrollController.hasClients) {
      return null;
    }
    if (_autoScrollController.positions.length == 1) {
      return _autoScrollController.position;
    }
    for (final position in _autoScrollController.positions) {
      if (position.hasPixels && position.hasContentDimensions) {
        return position;
      }
    }
    return _autoScrollController.positions.isEmpty
        ? null
        : _autoScrollController.positions.first;
  }

  ChatGeomSettleSnapshot? _captureGeomSettleSnapshot() {
    if (!mounted) {
      return null;
    }
    final position = _singleScrollPositionOrNull();
    return ChatGeomSettleTrace.snapshot(
      pixels: position?.hasPixels == true ? position!.pixels : null,
      minExtent: position?.hasContentDimensions == true
          ? position!.minScrollExtent
          : null,
      maxExtent: position?.hasContentDimensions == true
          ? position!.maxScrollExtent
          : null,
      viewport: position?.hasContentDimensions == true
          ? position!.viewportDimension
          : null,
      spacer: _routeScroll.shortHistoryBottomSpacerHeight,
      contentH: _routeScroll.shortHistoryContentHeight,
      latched: _routeScroll.shortHistoryAlignmentLatched,
    );
  }

  void _geomJumpTo(double pixels, {required String reason}) {
    _lastGeomJumpAttemptReason = reason;
    _lastGeomJumpAttemptAtMs = DateTime.now().millisecondsSinceEpoch;
    final globalModel = _chatGlobalModel;
    final menuTransactionActive = globalModel != null &&
        (globalModel.isMessageContextMenuOverlayOpen ||
            globalModel.isContextMenuViewportRestoreActive(_conversationId()));
    final isMenuRestoreWrite = reason.contains('restoreContextMenuViewport');
    if (menuTransactionActive && !isMenuRestoreWrite) {
      // Context-menu restore is the sole scroll writer while its transaction
      // is active. Reject stale CVP/pin/spacer callbacks instead of letting a
      // delayed producer seize the ScrollPosition after dismissal.
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[MessageContextTrace] scroll_mutation_blocked '
          'conv=${_conversationId()} reason=$reason',
        );
      }
      return;
    }
    if (_shouldCompensateScrollForPagination()) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastPaginationScrollWriteLogMs >= 250) {
        _lastPaginationScrollWriteLogMs = nowMs;
        final position = _singleScrollPositionOrNull();
        ChatHistoryTrace.log(
          'pagination_scroll_write',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'reason': reason,
            'beforePixels': position?.hasPixels == true
                ? position!.pixels.toStringAsFixed(1)
                : 'n/a',
            'target': pixels.toStringAsFixed(1),
            'axis': position?.axisDirection.name,
            'userScrolling': _userScrollGestureActive ||
                (_chatGlobalModel?.isChatListUserScrolling ?? false),
          },
        );
      }
    }
    ChatGeomSettleTrace.noteReason(
      reason,
      extras: <String, Object?>{'target': pixels.toStringAsFixed(1)},
    );
    // 「谁把视口推走了」的归因：offset_jump 只在跳变超阈值时记，且 physics
    // 的绘制前补偿走另一条路，中间那些无归因的位移只能在写入点自报。
    if (ChatJitterDiag.followingLatestEnabled) {
      final writePosition = _singleScrollPositionOrNull();
      ChatJitterDiag.logFollowingLatest(
        action: 'geom_jump',
        conv: _conversationId(),
        extras: <String, Object?>{
          'reason': reason,
          'before': writePosition?.hasPixels == true
              ? writePosition!.pixels.toStringAsFixed(1)
              : 'n/a',
          'target': pixels.toStringAsFixed(1),
          'minExtent': writePosition?.hasContentDimensions == true
              ? writePosition!.minScrollExtent.toStringAsFixed(1)
              : 'n/a',
          'maxExtent': writePosition?.hasContentDimensions == true
              ? writePosition!.maxScrollExtent.toStringAsFixed(1)
              : 'n/a',
        },
      );
    }
    _autoScrollController.jumpTo(pixels);
  }

  /// 非手势造成的 offset 突变探针：定位「谁把视口推走了」。
  void _sampleOffsetJump(ScrollNotification notification) {
    if (!ChatJitterDiag.followingLatestEnabled) {
      return;
    }
    final metrics = notification.metrics;
    if (!metrics.hasPixels || !metrics.hasContentDimensions) {
      return;
    }
    final dragging = notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    _sampleOffsetJumpGeometry(
      pixels: metrics.pixels,
      minExtent: metrics.minScrollExtent,
      maxExtent: metrics.maxScrollExtent,
      viewport: metrics.viewportDimension,
      dragging: dragging,
      source: 'scroll_update',
    );
  }

  void _sampleOffsetJumpGeometry({
    required double pixels,
    required double minExtent,
    required double maxExtent,
    required double viewport,
    required bool dragging,
    required String source,
  }) {
    if (!ChatJitterDiag.followingLatestEnabled) {
      return;
    }
    final prevPixels = _lastOffsetSamplePixels;
    final prevMinExtent = _lastOffsetSampleMinExtent;
    final prevMaxExtent = _lastOffsetSampleMaxExtent;
    // 基线必须无条件刷新：任何提前 return 都不能把上一次采样冻住，
    // 否则 delta 会变成跨越数秒的累积值而不是单次跳变。
    _lastOffsetSamplePixels = pixels;
    _lastOffsetSampleMinExtent = minExtent;
    _lastOffsetSampleMaxExtent = maxExtent;
    if (prevPixels == null || prevMinExtent == null) {
      return;
    }
    final prevDistance = prevPixels - prevMinExtent;
    final distance = pixels - minExtent;
    final delta = distance - prevDistance;
    if (delta.abs() <= _offsetJumpDiagThresholdPx) {
      return;
    }
    if (dragging) {
      return;
    }
    // 回底事务走 animateTo，不经过 _geomJumpTo，本来就要大幅移动。
    if (_chatGlobalModel?.isUserScrollToBottomInProgress(_conversationId()) ??
        false) {
      return;
    }
    // CVP 推入新消息时的瞬时位移是设计中的中间态，list_push_start 另有记录。
    if (_isLiveViewportPushActive()) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rawCount = _chatGlobalModel?.rawMessageCount(_conversationId());
    ChatJitterDiag.logFollowingLatest(
      action: 'offset_jump',
      conv: _conversationId(),
      extras: <String, Object?>{
        'source': source,
        'prevPixels': prevPixels.toStringAsFixed(1),
        'pixels': pixels.toStringAsFixed(1),
        'prevMinExtent': prevMinExtent.toStringAsFixed(1),
        'minExtent': minExtent.toStringAsFixed(1),
        if (prevMaxExtent != null)
          'prevMaxExtent': prevMaxExtent.toStringAsFixed(1),
        'maxExtent': maxExtent.toStringAsFixed(1),
        'viewport': viewport.toStringAsFixed(1),
        'prevDistance': prevDistance.toStringAsFixed(1),
        'distance': distance.toStringAsFixed(1),
        'delta': delta.toStringAsFixed(1),
        if (rawCount != null) 'rawCount': rawCount,
        'following': _isFollowingLatest(),
        'userScrolling': _chatGlobalModel?.isChatListUserScrolling ?? false,
        if (_lastGeomJumpAttemptReason.isNotEmpty)
          'lastJumpAttempt': _lastGeomJumpAttemptReason,
        if (_lastGeomJumpAttemptAtMs > 0)
          'sinceJumpMs': nowMs - _lastGeomJumpAttemptAtMs,
      },
      throttleKey: 'offset_jump',
      minIntervalMs: 250,
    );
  }

  /// 入站处理完后下一帧采样一次，捕获布局阶段（而非滚动事件）造成的位移。
  void _scheduleOffsetJumpProbe() {
    if (!ChatJitterDiag.followingLatestEnabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final position = _singleScrollPositionOrNull();
      if (position == null ||
          !position.hasPixels ||
          !position.hasContentDimensions) {
        return;
      }
      _sampleOffsetJumpGeometry(
        pixels: position.pixels,
        minExtent: position.minScrollExtent,
        maxExtent: position.maxScrollExtent,
        viewport: position.viewportDimension,
        dragging: false,
        source: 'post_frame',
      );
    });
  }

  /// center 划分点探针：未读数驱动的 unread/read 分界一移动，center 之前的
  /// sliver 长度就变，框架会 correctPixels 把视口推走。
  void _logCenterPartition({
    required int rawTongue,
    required bool locked,
    required int unreadNew,
    required bool tongueEnabled,
    required int effectiveUnread,
    required int loadedReal,
    required int safeUnread,
    required int layoutUnread,
    required bool centerActive,
    required bool isSearchJump,
    required int unreadEndPoint,
    required int unreadLen,
    required int readLen,
    required int msgLen,
  }) {
    if (!ChatJitterDiag.followingLatestEnabled) {
      return;
    }
    // build 每帧都跑，只在划分点真的动了才记录。
    if (layoutUnread == _lastCenterDiagLayoutUnread &&
        unreadEndPoint == _lastCenterDiagUnreadEndPoint &&
        unreadLen == _lastCenterDiagUnreadLen &&
        readLen == _lastCenterDiagReadLen &&
        centerActive == _lastCenterDiagCenterActive) {
      return;
    }
    _lastCenterDiagLayoutUnread = layoutUnread;
    _lastCenterDiagUnreadEndPoint = unreadEndPoint;
    _lastCenterDiagUnreadLen = unreadLen;
    _lastCenterDiagReadLen = readLen;
    _lastCenterDiagCenterActive = centerActive;
    final position = _singleScrollPositionOrNull();
    final hasGeom = position != null &&
        position.hasPixels &&
        position.hasContentDimensions;
    final received =
        _chatGlobalModel?.receivedNewMessageCountFor(_conversationId());
    ChatJitterDiag.logFollowingLatest(
      action: 'center_partition',
      conv: _conversationId(),
      extras: <String, Object?>{
        'rawTongue': rawTongue,
        'locked': locked,
        'unreadNew': unreadNew,
        'tongueEnabled': tongueEnabled,
        'effectiveUnread': effectiveUnread,
        'loadedReal': loadedReal,
        'safeUnread': safeUnread,
        'layoutUnread': layoutUnread,
        'centerActive': centerActive,
        'isSearchJump': isSearchJump,
        'unreadEndPoint': unreadEndPoint,
        'unreadLen': unreadLen,
        'readLen': readLen,
        'msgLen': msgLen,
        'hasLiveCenter': _hasLiveCenter,
        'deferPartition': _deferUnreadCenterPartition,
        'following': _isFollowingLatest(),
        if (received != null) 'received': received,
        // build 跑在 layout 之前，这两个是上一帧的几何结果。
        'framePixels': hasGeom ? position!.pixels.toStringAsFixed(1) : 'n/a',
        'frameMaxExtent':
            hasGeom ? position!.maxScrollExtent.toStringAsFixed(1) : 'n/a',
      },
    );
  }

  Future<void> _geomScrollToIndex(
    int index, {
    required String reason,
    AutoScrollPosition preferPosition = AutoScrollPosition.middle,
  }) {
    ChatGeomSettleTrace.noteReason(
      reason,
      extras: <String, Object?>{
        'index': index,
        'prefer': preferPosition.toString(),
      },
    );
    return _autoScrollController.scrollToIndex(
      index,
      preferPosition: preferPosition,
    );
  }

  void _assignShortHistorySpacer(double nextHeight, {required String reason}) {
    var normalized = nextHeight <= 1 ? 0.0 : nextHeight;
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled &&
        normalized > 0) {
      ChatGeomSettleTrace.noteReason(
        'short_history_spacer_blocked_top_align_disabled',
        extras: <String, Object?>{
          'reason': reason,
          'blockedNext': normalized.toStringAsFixed(1),
        },
      );
      normalized = 0.0;
    }
    final prev = _routeScroll.shortHistoryBottomSpacerHeight;
    final delta = (normalized - prev).abs();
    if (_isPostRevealMicroSuppressWindow) {
      final sinceReady = _msSinceHistoryOpenRevealReady();
      final maxSuppressDelta = sinceReady < 200 ? 4.0 : 2.0;
      if (delta <= maxSuppressDelta) {
        ChatGeomSettleTrace.noteReason(
          'spacer_micro_suppressed_post_reveal',
          extras: <String, Object?>{
            'prev': prev.toStringAsFixed(1),
            'next': normalized.toStringAsFixed(1),
            'delta': (normalized - prev).toStringAsFixed(1),
            'sinceReadyMs': sinceReady,
            'maxDelta': maxSuppressDelta,
            'reason': reason,
          },
        );
        return;
      }
    }
    ChatGeomSettleTrace.noteReason(
      reason,
      extras: <String, Object?>{
        'prev': prev.toStringAsFixed(1),
        'next': normalized.toStringAsFixed(1),
        'delta': (normalized - prev).toStringAsFixed(1),
      },
    );
    _routeScroll.shortHistoryBottomSpacerHeight = normalized;
  }

  void _assignShortHistoryContentHeight(
    double nextHeight, {
    required String reason,
  }) {
    final normalized = nextHeight < 0 ? -1.0 : nextHeight;
    final prev = _routeScroll.shortHistoryContentHeight;
    ChatGeomSettleTrace.noteReason(
      reason,
      extras: <String, Object?>{
        'prev': prev.toStringAsFixed(1),
        'next': normalized.toStringAsFixed(1),
        'delta': (normalized - prev).toStringAsFixed(1),
      },
    );
    _routeScroll.shortHistoryContentHeight = normalized;
    if (normalized < 0) {
      _routeScroll.shortHistoryContentHeightMeasured = false;
    } else if (reason == 'content_h_measure' || reason == 'content_h_set') {
      final becameMeasured = !_routeScroll.shortHistoryContentHeightMeasured;
      _routeScroll.shortHistoryContentHeightMeasured = true;
      if (becameMeasured) {
        _onShortHistoryFirstMeasured();
      }
    } else if (reason == 'content_h_prime_last_measured') {
      // 会话上次实测：视为已测 SSOT，禁止 _resolved* 用偏高估盖回（暖开 183→259）。
      _routeScroll.shortHistoryContentHeightMeasured = true;
    }
  }

  Future<bool> _alignGlobalMessageIndexToViewportTop(
    int targetGlobalIndex, {
    Duration duration = const Duration(milliseconds: 220),
    bool animate = true,
  }) async {
    return _jumpToFirstUnreadGlobalIndex(targetGlobalIndex);
  }

  _FirstUnreadJumpFrameCheck? _checkFirstUnreadJumpFrame(
    int targetGlobalIndex,
  ) {
    final scrollIndex = -targetGlobalIndex;
    final tagContext = _autoScrollController.tagMap[scrollIndex]?.context;
    if (tagContext == null) {
      return _FirstUnreadJumpFrameCheck.notReady(targetGlobalIndex);
    }
    final scrollable = Scrollable.maybeOf(tagContext);
    if (scrollable == null) {
      return _FirstUnreadJumpFrameCheck.notReady(targetGlobalIndex);
    }
    final targetRenderObject = tagContext.findRenderObject();
    final viewportRenderObject = scrollable.context.findRenderObject();
    if (targetRenderObject is! RenderBox ||
        !targetRenderObject.attached ||
        viewportRenderObject is! RenderBox ||
        !viewportRenderObject.attached ||
        !targetRenderObject.hasSize ||
        !viewportRenderObject.hasSize ||
        _renderObjectNeedsLayout(targetRenderObject) ||
        _renderObjectNeedsLayout(viewportRenderObject)) {
      return _FirstUnreadJumpFrameCheck.notReady(targetGlobalIndex);
    }

    final targetTop = targetRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
    const tolerance = 12.0;
    final targetPixels = RenderAbstractViewport.of(
      targetRenderObject,
    ).getOffsetToReveal(targetRenderObject, 0).offset;
    return _FirstUnreadJumpFrameCheck(
      targetGlobalIndex: targetGlobalIndex,
      isReady: true,
      topDelta: targetTop,
      tolerance: tolerance,
      targetPixels: targetPixels,
    );
  }

  Future<bool> _correctFirstUnreadJumpToTop(int targetGlobalIndex) async {
    final check = _checkFirstUnreadJumpFrame(targetGlobalIndex);
    if (check == null) {
      return false;
    }
    if (!check.isReady) {
      try {
        await _geomScrollToIndex(
          -targetGlobalIndex,
          preferPosition: AutoScrollPosition.begin,
          reason: 'scroll_to_index_begin',
        );
      } catch (_) {}
      return false;
    }
    if (check.isTopAligned) {
      return true;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      try {
        await _geomScrollToIndex(
          -targetGlobalIndex,
          preferPosition: AutoScrollPosition.begin,
          reason: 'scroll_to_index_begin',
        );
      } catch (_) {}
      return false;
    }
    final targetPixels = check.targetPixels?.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (targetPixels == null) {
      try {
        await _geomScrollToIndex(
          -targetGlobalIndex,
          preferPosition: AutoScrollPosition.begin,
          reason: 'scroll_to_index_begin',
        );
      } catch (_) {}
      return false;
    }
    if ((position.pixels - targetPixels).abs() <= 0.5) {
      try {
        await _geomScrollToIndex(
          -targetGlobalIndex,
          preferPosition: AutoScrollPosition.begin,
          reason: 'scroll_to_index_begin',
        );
      } catch (_) {}
      return false;
    }
    _geomJumpTo(targetPixels.toDouble(), reason: 'first_unread_jump_pixels');
    return false;
  }

  Future<bool> _stabilizeFirstUnreadJumpTarget(int targetGlobalIndex) async {
    var stableFrames = 0;
    for (var attempt = 0; attempt < 20; attempt++) {
      _lockSearchJumpStabilization(milliseconds: 4000);
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return false;
      }

      final corrected = await _correctFirstUnreadJumpToTop(targetGlobalIndex);
      if (!mounted) {
        return false;
      }
      if (corrected) {
        stableFrames++;
        if (stableFrames >= 3) {
          return true;
        }
      } else {
        stableFrames = 0;
      }
      // Verify consecutive rendered layouts, not 60ms wall-clock samples.
      // Three stable frames remain required before removing the retained view.
    }

    final finalCheck = _checkFirstUnreadJumpFrame(targetGlobalIndex);
    return finalCheck?.isTopAligned ?? false;
  }

  Future<bool> _jumpToFirstUnreadGlobalIndex(int targetGlobalIndex) async {
    if (!mounted || targetGlobalIndex < 0) {
      return false;
    }
    if (!_scrollMetricsReady()) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_scrollMetricsReady()) {
        return false;
      }
    }

    _lockSearchJumpStabilization(milliseconds: 4000);
    _paginationUi.ignoreScrollLoadPrevious += 2;

    try {
      for (var attempt = 0; attempt < 12; attempt++) {
        try {
          await _geomScrollToIndex(
            -targetGlobalIndex,
            preferPosition: AutoScrollPosition.begin,
            reason: 'scroll_to_index_begin',
          );
        } catch (_) {}
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return false;
        }
        final check = _checkFirstUnreadJumpFrame(targetGlobalIndex);
        if (check?.isReady == true) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      return _stabilizeFirstUnreadJumpTarget(targetGlobalIndex);
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted && _paginationUi.ignoreScrollLoadPrevious >= 2) {
          _paginationUi.ignoreScrollLoadPrevious -= 2;
        }
      });
    }
  }

  void _scheduleUnreadTongueMetricsUpdate(
    List<V2TimMessage?> messageList,
    int safeUnreadCount, {
    bool force = false,
  }) {
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final convId = _conversationId();
    if (force) {
      _unreadTongueMetricsThrottleTimer?.cancel();
      _unreadTongueMetricsThrottleTimer = null;
      _pendingUnreadTongueMetricsList = null;
      _pendingUnreadTongueMetricsSafeCount = 0;
    }
    if (safeUnreadCount <= 0 || messageList.isEmpty) {
      _unreadTongueMetricsThrottleTimer?.cancel();
      _unreadTongueMetricsThrottleTimer = null;
      _pendingUnreadTongueMetricsList = null;
      _pendingUnreadTongueMetricsSafeCount = 0;
      if (globalModel.hasLockedEntryUnreadFor(convId)) {
        return;
      }
      _lastUnreadTongueConversationID = null;
      _lastUnreadTongueRemaining = null;
      _lastUnreadTongueSafeCount = 0;
      globalModel.clearUnreadTongueMetrics(convId, notify: true);
      return;
    }
    if (!force &&
        (globalModel.isChatListUserScrolling || _userScrollGestureActive)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final waitMs = _scrollingUnreadTongueMetricsThrottleMs -
          (now - _lastUnreadTongueMetricsRunAtMs);
      if (waitMs > 0) {
        _pendingUnreadTongueMetricsList = messageList;
        _pendingUnreadTongueMetricsSafeCount = safeUnreadCount;
        _unreadTongueMetricsThrottleTimer ??= Timer(
          Duration(milliseconds: waitMs),
          () {
            _unreadTongueMetricsThrottleTimer = null;
            if (!mounted) {
              return;
            }
            final pendingList = _pendingUnreadTongueMetricsList;
            final pendingSafeCount = _pendingUnreadTongueMetricsSafeCount;
            _pendingUnreadTongueMetricsList = null;
            _pendingUnreadTongueMetricsSafeCount = 0;
            if (pendingList == null || pendingSafeCount <= 0) {
              return;
            }
            _enqueueUnreadTongueMetricsPostFrame(pendingList, pendingSafeCount);
          },
        );
        return;
      }
    }
    _enqueueUnreadTongueMetricsPostFrame(
      messageList,
      safeUnreadCount,
    );
  }

  void _enqueueUnreadTongueMetricsPostFrame(
    List<V2TimMessage?> messageList,
    int safeUnreadCount,
  ) {
    _pendingUnreadTongueMetricsList = messageList;
    _pendingUnreadTongueMetricsSafeCount = safeUnreadCount;
    if (_unreadTongueMetricsScheduled) {
      return;
    }
    _unreadTongueMetricsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadTongueMetricsScheduled = false;
      if (!mounted) {
        return;
      }
      final snapshot = _pendingUnreadTongueMetricsList ?? messageList;
      final count = _pendingUnreadTongueMetricsSafeCount;
      _pendingUnreadTongueMetricsList = null;
      _pendingUnreadTongueMetricsSafeCount = 0;
      _lastUnreadTongueMetricsRunAtMs = DateTime.now().millisecondsSinceEpoch;
      if (count <= 0 || snapshot.isEmpty) {
        return;
      }
      _updateUnreadTongueMetrics(snapshot, count);
    });
  }

  void _updateUnreadTongueMetrics(
    List<V2TimMessage?> messageList,
    int safeUnreadCount,
  ) {
    if (!mounted || safeUnreadCount <= 0 || messageList.isEmpty) {
      return;
    }
    // 已点过入口未读并跳走：不再用入口未读数刷右下角「新消息」胶囊。
    // 翻历史时的 live 计数仍要更新，否则数字会停住。
    if (_firstUnreadAnchorJumped && _isFollowingLatest()) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }

    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final convId = _conversationId();
    final nearLatest = position.pixels <= position.minScrollExtent + 24;

    if (nearLatest &&
        safeUnreadCount > 0 &&
        !_firstUnreadAnchorJumped &&
        globalModel.getMessageListPosition(convId) ==
            HistoryMessagePosition.bottom) {
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        remaining: safeUnreadCount,
        below: false,
        safeUnreadCount: safeUnreadCount,
      );
      return;
    }

    if (_hasLiveCenter) {
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        remaining: safeUnreadCount,
        below: true,
        safeUnreadCount: safeUnreadCount,
      );
      return;
    }

    final viewportHeight = position.viewportDimension;
    var realUnreadOrdinal = 0;
    var builtAnyUnread = false;
    var allBuiltUnreadBelowViewport = true;
    var allBuiltUnreadAboveViewport = true;
    int? oldestVisibleUnreadOrdinal;

    for (var i = 0;
        i < messageList.length && realUnreadOrdinal < safeUnreadCount;
        i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      final ordinalFromNewest = realUnreadOrdinal;
      realUnreadOrdinal++;
      final tagContext = _autoScrollController.tagMap[-i]?.context;
      final renderObject = tagContext?.findRenderObject();
      if (tagContext == null ||
          renderObject is! RenderBox ||
          !renderObject.attached) {
        continue;
      }
      final viewport = RenderAbstractViewport.of(renderObject);
      if (viewport is! RenderBox || !viewport.attached) {
        continue;
      }
      final leadingOffset =
          renderObject.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final trailingOffset = leadingOffset + renderObject.size.height;

      builtAnyUnread = true;
      if (leadingOffset <= viewportHeight + 4) {
        allBuiltUnreadBelowViewport = false;
      }
      if (trailingOffset >= -4) {
        allBuiltUnreadAboveViewport = false;
      }
      final isVisible =
          trailingOffset >= -4 && leadingOffset <= viewportHeight + 4;
      if (isVisible) {
        if (oldestVisibleUnreadOrdinal == null ||
            ordinalFromNewest > oldestVisibleUnreadOrdinal) {
          oldestVisibleUnreadOrdinal = ordinalFromNewest;
        }
      }
    }

    if (!builtAnyUnread) {
      // Lazy slivers may have none of the unread rows mounted. Preserve a
      // deterministic count instead of retaining stale metrics indefinitely.
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        remaining: safeUnreadCount,
        below: !nearLatest,
        safeUnreadCount: safeUnreadCount,
      );
      return;
    }

    if (oldestVisibleUnreadOrdinal != null) {
      // messageList is newest -> oldest. At the first unread anchor, the
      // oldest visible unread ordinal is safeUnreadCount - 1, so the capsule
      // shows the full unread count. When the user scrolls down toward the
      // latest message, the ordinal becomes smaller and the count decreases.
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        remaining: oldestVisibleUnreadOrdinal + 1,
        below: true,
        safeUnreadCount: safeUnreadCount,
      );
      return;
    }

    if (allBuiltUnreadBelowViewport) {
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        remaining: safeUnreadCount,
        below: true,
        safeUnreadCount: safeUnreadCount,
      );
      return;
    }

    if (allBuiltUnreadAboveViewport) {
      if (globalModel.hasLockedEntryUnreadFor(convId) &&
          globalModel.getMessageListPosition(convId) ==
              HistoryMessagePosition.bottom &&
          !_firstUnreadAnchorJumped) {
        _commitUnreadTongueMetrics(
          globalModel: globalModel,
          conversationID: convId,
          remaining: safeUnreadCount,
          below: false,
          safeUnreadCount: safeUnreadCount,
        );
        return;
      }
      _commitUnreadTongueMetrics(
        globalModel: globalModel,
        conversationID: convId,
        // Keep the count source consistent with the buffered unread state.
        // Returning zero here makes the tongue immediately rebound to the
        // global count on the next selector rebuild.
        remaining: safeUnreadCount,
        below: false,
        safeUnreadCount: safeUnreadCount,
      );
    }
  }

  void _commitUnreadTongueMetrics({
    required TUIChatGlobalModel globalModel,
    required String conversationID,
    required int remaining,
    required bool below,
    required int safeUnreadCount,
  }) {
    if (_lastUnreadTongueConversationID != conversationID) {
      _lastUnreadTongueConversationID = conversationID;
      _lastUnreadTongueRemaining = null;
      _lastUnreadTongueSafeCount = 0;
    }
    final safeRemaining = remaining.clamp(0, safeUnreadCount).toInt();
    var effectiveRemaining = safeRemaining;
    final lastRemaining = _lastUnreadTongueRemaining;
    // 滚动查看历史/向上翻旧消息时，提示条数字不能反向增加；
    // 它只表示“下面还剩多少条新消息没看”。真正收到的新消息会通过
    // safeUnreadCount 增长重新进入窗口，历史分页不会把数字越翻越大。
    if (lastRemaining != null &&
        safeUnreadCount <= _lastUnreadTongueSafeCount &&
        safeRemaining > lastRemaining) {
      effectiveRemaining = lastRemaining;
    }
    _lastUnreadTongueRemaining = effectiveRemaining;
    if (safeUnreadCount > _lastUnreadTongueSafeCount) {
      _lastUnreadTongueSafeCount = safeUnreadCount;
    }
    globalModel.setUnreadTongueMetrics(
      conversationID: conversationID,
      remaining: effectiveRemaining,
      below: below,
    );
  }

  void _bindActiveScrollController() {
    if (!mounted) return;
    final convId = _conversationId();
    if (convId.isEmpty) return;
    _chatGlobalModel?.bindActiveChatScrollController(
      conversationID: convId,
      scrollController: _autoScrollController,
    );
    _chatGlobalModel?.bindHistoryLiveWindowFreeze(
      conversationID: convId,
      freezeIfNeeded: widget.model.freezeVisibleHistoryWindowIfNeeded,
      canAppendIncoming: widget.model.canAppendIncomingToReadingWindow,
      didAppendIncoming: widget.model.didAppendIncomingToReadingWindow,
    );
  }

  bool _shouldRunRowReveal({bool forLiveListPush = false}) {
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    if (MediaQuery.of(context).disableAnimations ||
        !globalModel.shouldAnimateInboundPresentation ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    if (globalModel.isBulkMessageSyncActive(_conversationId())) {
      return false;
    }
    if (_isSearchJumpStabilizing) {
      return false;
    }
    if (globalModel.isRestoringScrollAfterMediaPreview) {
      return false;
    }
    if (globalModel.isMessageContextMenuOverlayOpen) {
      return false;
    }
    if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      return false;
    }
    if (!globalModel.chatConfig.messageEnterAnimationListPushEnabled) {
      return false;
    }
    // 短历史 / 进页 settle：收消息历史曾经为避免抢手势关掉 list-push，但发送会退回
    // 「气泡 slide + force-pin + 清 spacer」叠层抖动。直播插入统一走 list-push
    //（短列表用 row_reveal_grow，无二次滚底）。
    if (!forLiveListPush) {
      if (_mayUseShortHistoryTopAlignment()) {
        return false;
      }
      if (_isInitialRouteSettleWindow) {
        return false;
      }
    }
    final convId = _conversationId();
    if (!_isFollowingLatest()) {
      return false;
    }
    final listPosition = globalModel.getMessageListPosition(convId);
    if (listPosition == HistoryMessagePosition.notShowLatest) {
      if (forLiveListPush) {
        ChatJitterDiag.logFollowingLatest(
          action: 'reveal_blocked',
          conv: convId,
          extras: <String, Object?>{
            'reason': 'logical_notShowLatest',
            'logical': listPosition.name,
          },
          throttleKey: 'reveal_blocked',
          minIntervalMs: 250,
        );
      }
      return false;
    }
    return true;
  }

  bool _isWechatInsertAnimationStyle(TUIChatGlobalModel globalModel) {
    return globalModel.chatConfig.messageEnterAnimationStyle ==
        MessageEnterAnimationStyle.wechat;
  }

  bool _useWechatListPushTranslate(TUIChatGlobalModel globalModel) {
    return _isWechatInsertAnimationStyle(globalModel) &&
        globalModel.chatConfig.messageEnterAnimationListPushEnabled;
  }

  void _acknowledgeInboundProjectionRevealIfNeeded() {
    final globalModel = _chatGlobalModel;
    final convId = _conversationId();
    if (globalModel == null || convId.isEmpty) {
      return;
    }
    if (!globalModel.isInboundProjectionRevealWaiting(convId)) {
      return;
    }
    globalModel.completeInboundProjectionReveal(convId);
  }

  void _pinScrollToBottomImmediate() {
    final globalModel = _chatGlobalModel;
    if (globalModel == null ||
        !mounted ||
        _viewportInsert.viewportInsertSlideActive ||
        _isViewportInsertSettling()) {
      return;
    }
    if (!_shouldPinScrollToBottom(globalModel)) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }
    final target = position.minScrollExtent;
    final delta = (position.pixels - target).abs();
    ChatJitterDiag.logFollowingLatest(
      action: 'pin_bottom_immediate',
      conv: _conversationId(),
      extras: <String, Object?>{
        'willJump': delta > 0.5,
        'delta': delta.toStringAsFixed(1),
        ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
      },
    );
    if (delta > 0.5) {
      _geomJumpTo(target, reason: 'pin_bottom_immediate');
    }
    globalModel.setMessageListPosition(
      _conversationId(),
      HistoryMessagePosition.bottom,
      notify: false,
    );
    globalModel.markOpenChatFirstPinSettled(_conversationId());
  }

  // K.9：scroll 监听，更新贴底状态。
  bool _visibleLatestConfirmationScheduled = false;
  final ValueNotifier<bool> _latestMessageVisible = ValueNotifier<bool>(false);

  bool _isLatestMessageRowVisible() {
    if (_viewportInsert.viewportInsertSlideActive) return false;
    final messages = _currentVisibleMessageList();
    if (messages.isEmpty) return false;
    final tag = _autoScrollController.tagMap[0];
    final tagContext = tag?.context;
    if (tagContext == null ||
        tag?.widget.key !=
            ValueKey<String>(_stableMessageListKey(messages.first, 0))) {
      return false;
    }
    final row = tagContext.findRenderObject();
    final viewport = _viewportRenderBoxFor(tagContext);
    if (row is! RenderBox ||
        viewport == null ||
        !row.attached ||
        !row.hasSize ||
        row.size.height <= 0 ||
        _renderObjectNeedsLayout(row)) {
      return false;
    }
    final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + row.size.height;
    return bottom > 0 && bottom <= viewport.size.height + 4 &&
        (top >= -4 || row.size.height > viewport.size.height);
  }

  bool _liveCenterReleaseScheduled = false;

  void _scheduleLiveCenterRelease() {
    if (!mounted || !_hasLiveCenter || _liveCenterReleaseScheduled) return;
    _liveCenterReleaseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liveCenterReleaseScheduled = false;
      if (mounted) _releaseLiveCenterAtLatest();
    });
  }

  bool _releaseLiveCenterAtLatest({bool beforeFollowing = false}) {
    if (!_hasLiveCenter || !mounted) return false;
    final model = widget.model;
    final global = model.globalModel;
    final conv = _conversationId();
    final position = _singleScrollPositionOrNull();
    if ((!beforeFollowing && !_isFollowingLatest()) ||
        model.haveMoreLatestData ||
        global.memoryWindowMissingNewer(conv) ||
        global.isSearchJumpPending(conv) ||
        global.isUserScrollToBottomInProgress(conv) ||
        _userScrollGestureActive ||
        model.isLoadingChatHistory ||
        _paginationUi.isLoadingLatest ||
        _paginationUi.isLoadingPrevious ||
        _historyWindowTrimUi.isBusy ||
        _isLiveViewportPushActive() ||
        global.isMessageContextMenuOverlayOpen ||
        global.isContextMenuViewportRestoreActive(conv) ||
        position == null ||
        !position.hasContentDimensions ||
        position.outOfRange ||
        position.isScrollingNotifier.value ||
        !TrueLatestEnd.atListEndFromPosition(position)) return false;
    // At the measured newest edge the negative extent is the complete front
    // sliver height. Translate coordinates and remove the center together,
    // before the next paint; the newest row remains at the same screen pixel.
    final translation = -position.minScrollExtent;
    _clearBufferedRevealAnchor(reason: 'release_live_partition');
    position.correctBy(translation);
    _livePartitionAnchorHeadKey = null;
    _livePartitionAnchorHeadMessage = null;
    setState(() {});
    return true;
  }

  bool _visibleIncomingProgressScheduled = false;
  bool _visibleIncomingProgressInFlight = false;
  String? _visibleIncomingProgressSignature;
  String? _visibleIncomingProgressConversation;
  TUIChatSeparateViewModel? _visibleIncomingProgressModel;
  bool Function()? _visibleIncomingProgressFence;
  final Map<String, V2TimMessage> _pendingVisibleIncomingProgress = {};

  void _scheduleVisibleIncomingProgress() {
    if (!mounted || _visibleIncomingProgressScheduled) return;
    _visibleIncomingProgressScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleIncomingProgressScheduled = false;
      if (!mounted) return;
      final model = widget.model;
      final global = model.globalModel;
      final conv = _conversationId();
      if (_visibleIncomingProgressConversation != conv ||
          !identical(_visibleIncomingProgressModel, model) ||
          _visibleIncomingProgressFence?.call() != true) {
        _visibleIncomingProgressConversation = conv;
        _visibleIncomingProgressModel = model;
        _visibleIncomingProgressFence =
            global.captureHistoryUnreadVisitFence(conv);
        _visibleIncomingProgressSignature = null;
        _pendingVisibleIncomingProgress.clear();
      }
      // Loading a page is not a read. A measured visible row can settle an
      // identity while reading history, independently of FOLLOW.
      if (global.isGeometryViewportTransitionActive(conv) ||
          (global.receivedNewMessageCountFor(conv) <= 0 &&
              global.remainingLiveIncomingCountFor(conv) <= 0) ||
          ModalRoute.of(context)?.isCurrent == false ||
          _initialSearchJumpPending ||
          _isSearchJumpStabilizing ||
          model.isLoadingChatHistory ||
          _historyWindowTrimUi.isBusy ||
          _viewportInsert.viewportInsertSlideActive ||
          global.isMessageContextMenuOverlayOpen ||
          global.isContextMenuViewportRestoreActive(conv) ||
          global.shouldLockChatScrollForMediaPreview ||
          global.hasPendingScrollRestore(conv) ||
          global.isRestoringScrollAfterMediaPreview ||
          global.isUserScrollToBottomInProgress(conv)) return;
      final messages = _currentVisibleMessageList();
      int? readingEdge;
      for (var index = 0; index < messages.length; index++) {
        final message = messages[index];
        if (message == null || message.elemType == 11) continue;
        final tag = _autoScrollController.tagMap[-index];
        final rowContext = tag?.context;
        if (rowContext == null ||
            tag?.widget.key != ValueKey<String>(
                _stableMessageListKey(message, index))) continue;
        final row = rowContext.findRenderObject();
        final viewport = _viewportRenderBoxFor(rowContext);
        if (row is! RenderBox || viewport == null || !row.attached ||
            !row.hasSize || row.size.height <= 0 ||
            _renderObjectNeedsLayout(row)) continue;
        final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final bottom = top + row.size.height;
        // A long message is crossed once its bottom has entered the viewport.
        // A normal row must be fully visible, not merely prefetched or peeking.
        if (bottom > 0 && bottom <= viewport.size.height + 0.5 &&
            (top >= -0.5 || row.size.height > viewport.size.height)) {
          readingEdge = index;
          break;
        }
      }
      if (readingEdge == null) return;
      final signature = '$conv:${model.historyReadingWindowRevision}:'
          '${global.receivedNewMessageCountFor(conv)}:'
          '${global.remainingLiveIncomingCountFor(conv)}:'
          '${_messageIdentity(messages[readingEdge]!)}';
      if (signature == _visibleIncomingProgressSignature) {
        _drainVisibleIncomingProgress();
        return;
      }
      _visibleIncomingProgressSignature = signature;
      // One painted reading edge drives both ledgers. This includes rows
      // crossed between frames before a bounded window trims their widgets.
      global.markLiveIncomingSeen(
        conversationID: conv,
        ids: messages.skip(readingEdge).whereType<V2TimMessage>()
            .where(TUIChatGlobalModel.isConfirmedProjectionMessage)
            .map(TUIChatGlobalModel.liveIncomingIdentity),
      );
      // A fast drag can cross several rows in one frame. Only rows behind this
      // measured edge in the connected window qualify, never the prefetched
      // newer rows still below it. Exact IDs keep arrival order independent.
      for (final message in messages.skip(readingEdge).whereType<V2TimMessage>()) {
        if (message.elemType == 11) continue;
        final id = (message.msgID?.trim().isNotEmpty ?? false)
            ? message.msgID!.trim() : message.id?.trim() ?? '';
        if (id.isNotEmpty) _pendingVisibleIncomingProgress[id] = message;
      }
      _drainVisibleIncomingProgress();
    });
  }

  void _drainVisibleIncomingProgress() {
    if (_visibleIncomingProgressInFlight ||
        _pendingVisibleIncomingProgress.isEmpty || !mounted) return;
    final model = widget.model;
    final conv = _conversationId();
    final fence = _visibleIncomingProgressFence;
    bool sameProofOwner() => mounted && identical(widget.model, model) &&
        _conversationId() == conv &&
        identical(_visibleIncomingProgressFence, fence) && fence?.call() == true;
    bool current() => sameProofOwner() &&
        ModalRoute.of(context)?.isCurrent != false;
    if (!current()) return;
    _visibleIncomingProgressInFlight = true;
    var failed = false;
    unawaited(() async {
      List<V2TimMessage> batch = const [];
      try {
        while (current() && _pendingVisibleIncomingProgress.isNotEmpty) {
          batch = _pendingVisibleIncomingProgress.values.take(120).toList();
          for (final message in batch) {
            final id = (message.msgID?.trim().isNotEmpty ?? false)
                ? message.msgID!.trim() : message.id?.trim() ?? '';
            _pendingVisibleIncomingProgress.remove(id);
          }
          final consumed = await model.globalModel.acknowledgeVisibleHistoryMessages(
              conv, batch, isCurrent: current);
          if (!consumed && sameProofOwner()) {
            _visibleIncomingProgressSignature = null;
            if (!current()) {
              for (final message in batch) {
                final id = (message.msgID?.trim().isNotEmpty ?? false)
                    ? message.msgID!.trim() : message.id?.trim() ?? '';
                _pendingVisibleIncomingProgress[id] = message;
              }
            }
          }
          batch = const [];
        }
      } catch (_) {
        failed = true;
        if (sameProofOwner()) {
          // Keep crossed identities for a later retry even if the viewport has
          // since moved past them. Do not retry a failed write in a tight loop.
          _visibleIncomingProgressSignature = null;
          for (final message in batch) {
            final id = (message.msgID?.trim().isNotEmpty ?? false)
                ? message.msgID!.trim() : message.id?.trim() ?? '';
            _pendingVisibleIncomingProgress[id] = message;
          }
        }
      } finally {
        _visibleIncomingProgressInFlight = false;
        if (mounted) {
          _scheduleVisibleLatestConfirmation();
          _scheduleLiveCenterRelease();
          if (_pendingVisibleIncomingProgress.isNotEmpty &&
              (!failed || !sameProofOwner())) {
            if (current()) {
              _drainVisibleIncomingProgress();
            } else {
              // A new visit may have queued its own proof while this write
              // was finishing. Let a fresh sampler validate and wake it.
              _scheduleVisibleIncomingProgress();
              WidgetsBinding.instance.scheduleFrame();
            }
          }
        }
      }
    }());
  }

  bool _seenLiveIncomingScheduled = false;

  void _scheduleSeenLiveIncomingInViewport() {
    if (!mounted || _seenLiveIncomingScheduled ||
        (_chatGlobalModel?.remainingLiveIncomingCountFor(_conversationId()) ?? 0)
            <= 0) return;
    _seenLiveIncomingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seenLiveIncomingScheduled = false;
      _consumeSeenLiveIncomingInEffectiveViewport();
    });
    // Route/menu restoration may notify without changing the list or offset.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _consumeSeenLiveIncomingInEffectiveViewport() {
    if (!mounted) return;
    // A trim/search restore can lay rows out behind a frozen transition
    // snapshot. Those temporary coordinates are not evidence of a read.
    if (_historyWindowTrimUi.isBusy ||
        widget.model.isLoadingChatHistory ||
        _unreadWindowJumpInFlight || _isSearchJumpStabilizing ||
        ModalRoute.of(context)?.isCurrent == false) return;
    final global = _chatGlobalModel;
    if (global == null) {
      return;
    }
    final conv = _conversationId();
    if (global.remainingLiveIncomingCountFor(conv) <= 0 ||
        ModalRoute.of(context)?.isCurrent == false ||
        global.isMessageContextMenuOverlayOpen ||
        global.isContextMenuViewportRestoreActive(conv) ||
        global.shouldLockChatScrollForMediaPreview ||
        global.isRestoringScrollAfterMediaPreview ||
        global.hasPendingScrollRestore(conv) ||
        global.isSearchJumpPending(conv) ||
        _initialSearchJumpPending ||
        _isSearchJumpStabilizing ||
        widget.model.isLoadingChatHistory) {
      return;
    }
    final remaining = global.remainingLiveIncomingIdsFor(conv);
    if (remaining.isEmpty) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }
    // The input area already reserves keyboard space outside this viewport.
    // Subtracting MediaQuery insets here would exclude visible message rows.
    if (position.viewportDimension <= 0) {
      return;
    }
    final messages = _currentVisibleMessageList();
    final seen = <String>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message == null ||
          !TUIChatGlobalModel.isConfirmedProjectionMessage(message)) {
        continue;
      }
      final id = TUIChatGlobalModel.liveIncomingIdentity(message);
      if (id.isEmpty || !remaining.contains(id)) {
        continue;
      }
      final tag = _autoScrollController.tagMap[-index];
      final rowContext = tag?.context;
      if (rowContext == null ||
          tag?.widget.key !=
              ValueKey<String>(_stableMessageListKey(message, index))) {
        continue;
      }
      final row = rowContext.findRenderObject();
      final viewport = _viewportRenderBoxFor(rowContext);
      if (row is! RenderBox ||
          viewport == null ||
          !row.attached ||
          !row.hasSize ||
          !viewport.attached ||
          !viewport.hasSize ||
          _renderObjectNeedsLayout(row) ||
          row.size.height <= 0) {
        continue;
      }
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + row.size.height;
      // Identity bookkeeping must use the same completed-reading edge as the
      // durable ACK. A row merely peeking into the viewport is still unread.
      if (bottom > 0 && bottom <= viewport.size.height + 0.5 &&
          (top >= -0.5 || row.size.height > viewport.size.height)) {
        seen.add(id);
      }
    }
    if (seen.isNotEmpty) {
      global.markLiveIncomingSeen(conversationID: conv, ids: seen);
    }
  }

  void _updateLatestMessageVisibility() {
    if (!mounted) return;
    _scheduleVisibleIncomingProgress();
    _scheduleSeenLiveIncomingInViewport();
    _scheduleLiveCenterRelease();
    final next = _isLatestMessageRowVisible();
    if (_latestMessageVisible.value != next) {
      _latestMessageVisible.value = next;
    }
    if (next) {
      _chatGlobalModel?.markOpenChatFirstPinSettled(_conversationId());
    }
  }

  void _scheduleVisibleLatestConfirmation() {
    if (_visibleLatestConfirmationScheduled || !mounted) return;
    final model = widget.model;
    final conv = _conversationId();
    bool atEdge() {
      if (!mounted ||
          widget.model != model ||
          _conversationId() != conv ||
          ModalRoute.of(context)?.isCurrent == false ||
          _unreadWindowJumpInFlight ||
          model.isLoadingChatHistory ||
          model.globalModel.isUserScrollToBottomInProgress(conv) ||
          _isSearchJumpStabilizing ||
          _shouldCompensateScrollForPagination() ||
          _historyWindowTrimUi.isBusy ||
          model.globalModel.hasPendingScrollRestore(conv) ||
          model.globalModel.isMessageContextMenuOverlayOpen ||
          model.globalModel.isContextMenuViewportRestoreActive(conv))
        return false;
      final position = _singleScrollPositionOrNull();
      return TrueLatestEnd.atListEndFromPosition(position) &&
          _isLatestMessageRowVisible();
    }

    if (model.haveMoreLatestData ||
        !atEdge() ||
        (!model.hasHistoryReadingWindow &&
            !model.globalModel.hasDurableHistoryDeferred(conv))) return;
    _visibleLatestConfirmationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!atEdge()) return;
        // Release the fixed partition before restoring live following, so the
        // next incoming animation uses the ordinary bottom coordinate system.
        if (_hasLiveCenter) {
          if (!_releaseLiveCenterAtLatest(beforeFollowing: true)) return;
          await WidgetsBinding.instance.endOfFrame;
          if (!atEdge()) return;
        }
        final rows = _currentVisibleMessageList()
            .whereType<V2TimMessage>()
            .toList(growable: false);
        final confirmed = await model.confirmVisibleLatestWindow(
            visibleMessages: rows, isStillAtLatestEdge: atEdge);
        if (confirmed &&
            atEdge() &&
            !model.hasHistoryReadingWindow &&
            !model.globalModel.hasDurableHistoryDeferred(conv)) {
          _paginationUi.historyScrollProtectUntilMs = 0;
          _scheduleLiveCenterRelease();
          _maybeReleaseLiveNewestSliver();
          _maybeReleaseUnreadCenterDeferral();
        }
      } finally {
        _visibleLatestConfirmationScheduled = false;
      }
    });
  }

  void _onAutoScrollUpdate() {
    _updateLatestMessageVisibility();
    _scheduleVisibleLatestConfirmation();
    if (!_autoScrollController.hasClients) return;
    final position = _autoScrollController.position;
    if (!position.hasContentDimensions) return;
    // reverse: true 的 ListView：minScrollExtent 是最底部。
    final fromBottom = position.pixels - position.minScrollExtent;
    final nowPinned = fromBottom.abs() <= _kPinBottomThreshold;
    if (nowPinned != _isPinnedToBottom) {
      final hadPill = _unreadCountBelowViewport > 0;
      _isPinnedToBottom = nowPinned;
      if (nowPinned) {
        _unreadCountBelowViewport = 0;
      }
      if (hadPill) {
        setState(() {});
      }
    }
  }

  // K.13：用户点击「new message pill」回到底部。
  final _bottomTongueKey =
      GlobalKey<TIMUIKitHistoryMessageListTongueContainerState>();

  Future<void> _onJumpToBottomFromPill() async {
    await _bottomTongueKey.currentState
        ?.scrollToLatestAndDismissUnreadCapsule();
    if (mounted) setState(() => _unreadCountBelowViewport = 0);
  }

  void _armNewestInsertRoom(List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return;
    }
    final extent = _estimatedInsertedExtent(messages);
    if (extent <= 0.5) {
      return;
    }
    _newestInsertRoom = extent;
    _newestInsertRoomAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  double _estimatedInsertedExtent(List<V2TimMessage> messages) {
    final screenWidth = mounted ? MediaQuery.sizeOf(context).width : null;
    var extent = 0.0;
    for (final message in messages) {
      extent += ChatMessageHeightCache.instance.heightFor(message) ??
          ChatMessageHeightCache.instance.estimateRowHeight(
            message,
            screenWidth:
                screenWidth ?? ChatMessageHeightCache.defaultScreenWidth,
          ) ??
          _shortHistoryMessageEstimatedRowHeight;
    }
    return extent;
  }

  double? _cachedInsertedExtent(List<V2TimMessage> messages) {
    var extent = 0.0;
    for (final message in messages) {
      final key = _stableMessageListKey(message, 0);
      final revealedHeight = _viewportInsert.rowRevealFullExtentByKey[key];
      if (revealedHeight != null && revealedHeight > 0) {
        extent += revealedHeight;
        continue;
      }
      final height = ChatMessageHeightCache.instance.heightFor(message);
      if (height == null || height <= 0) {
        return null;
      }
      extent += height;
    }
    return extent > 0 ? extent : null;
  }

  /// 短消息 560px/s；气泡高度 ≥ 屏高 30% 视为长消息，720px/s。
  static const double _listPushTallBubbleViewportRatio = 0.30;
  static const double _listPushShortPixelsPerSecond = 560.0;
  static const double _listPushTallPixelsPerSecond = 720.0;

  double _listPushPixelsPerSecond({
    required double extent,
    required double viewportHeight,
  }) {
    if (viewportHeight <= 0 || extent <= 0) {
      return _listPushShortPixelsPerSecond;
    }
    if (extent / viewportHeight >= _listPushTallBubbleViewportRatio) {
      return _listPushTallPixelsPerSecond;
    }
    return _listPushShortPixelsPerSecond;
  }

  int _listPushDurationMs({
    required double motionExtent,
    required double viewportHeight,
    bool outgoing = false,
  }) {
    return ChatViewportMotion.durationFor(
      outgoing: outgoing,
      extent: viewportHeight > 0
          ? min(motionExtent, viewportHeight)
          : motionExtent,
    ).inMilliseconds;
  }

  /// didUpdateWidget 里、本帧 build 前调用：新行以 progress=0 进树，避免全高闪一帧。
  void _armZeroHeightViewportInsert(List<V2TimMessage> messages) {
    final controller = _viewportInsert.rowRevealController;
    if (controller == null || messages.isEmpty) {
      return;
    }
    if (controller.isAnimating ||
        _viewportInsert.activeRowRevealMessages.isNotEmpty) {
      _finishActiveRowRevealImmediately();
    }
    // 取消已排程的普通 row-reveal forward，避免抢同一 controller。
    ++_viewportInsert.rowRevealGeneration;
    _viewportInsert.activeRowRevealMessages.clear();
    final screenWidth = mounted ? MediaQuery.sizeOf(context).width : null;
    for (final message in messages) {
      // 长文本必须用真实屏宽估高；默认 390 会明显偏矮 → 上推后再长高 → 二次顶历史。
      if (screenWidth != null && screenWidth > 0) {
        ChatMessageHeightCache.instance.seedEstimateIfAbsent(
          message,
          screenWidth: screenWidth,
        );
      } else {
        ChatMessageHeightCache.instance.seedPlaceholderIfAbsent(message);
      }
      _viewportInsert.activeRowRevealMessages[_stableMessageListKey(
        message,
        0,
      )] = message;
    }
    _viewportInsert.suppressRowRevealStatus = true;
    controller.stop();
    controller.value = 0;
    _viewportInsert.suppressRowRevealStatus = false;
  }

  /// 把零高行一次撑满（不触发 status complete），供视口补偿滚动使用。
  void _expandArmedViewportInsertToFullHeight() {
    final controller = _viewportInsert.rowRevealController;
    if (controller == null || _viewportInsert.activeRowRevealMessages.isEmpty) {
      return;
    }
    _viewportInsert.suppressRowRevealStatus = true;
    controller.stop();
    controller.value = 1;
    _viewportInsert.suppressRowRevealStatus = false;
  }

  void _releaseArmedViewportInsertReveal() {
    final messages = _viewportInsert.takeArmedRevealMessages();
    if (messages.isEmpty) {
      return;
    }
    final globalModel = _chatGlobalModel ??
        (mounted
            ? Provider.of<TUIChatGlobalModel>(context, listen: false)
            : null);
    if (globalModel != null) {
      for (final message in messages) {
        _viewportInsert.rowRevealFullExtentByKey.remove(
          _stableMessageListKey(message, 0),
        );
        globalModel.finishMessageEnterAnimation(message);
      }
      globalModel.completeInboundProjectionReveal(_conversationId());
    }
    _viewportInsert.snapRevealControllerComplete();
  }

  void _beginMediaSettleForMessages(
    List<V2TimMessage> messages, {
    int? holdMs,
  }) {
    _viewportInsert.beginMediaSettleForKeys(
      messages.map((message) => _stableMessageListKey(message, 0)),
      holdMs: holdMs,
    );
  }

  bool _isMediaSettlingForKey(String key) =>
      _viewportInsert.isMediaSettlingForKey(key);

  void _silentAbsorbExtentDelta(double delta) {
    final model = _chatGlobalModel;
    if (model != null &&
        (model.isMessageContextMenuOverlayOpen ||
            model.isContextMenuViewportRestoreActive(_conversationId()))) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }
    if (delta.abs() < 0.5) {
      return;
    }
    if (model?.isChatListUserScrolling ?? false) {
      return;
    }
    if (_hasLiveCenter) {
      return;
    }
    // reverse 列表贴底（pixels==min）时底边就是布局锚点：行高无论变高还是
    // 变矮，viewport 底部内容都不动，任何 correctBy 都是反向制造位移——
    // 变高会修成负 offset（进页 scrollPx -4~-46 的过滚缺口，随后被 pin 弹回，
    // 即肉眼可见的「抖」）；变矮会把列表修离底部（日志里停在 16.8px）。
    if (position.pixels <= position.minScrollExtent + 0.5) {
      return;
    }
    // 离底时（上推动画/settle 中）照常吸收，但修正量夹在滚动范围内，
    // 防止把 offset 推进过滚区。
    final target = (position.pixels - delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final correction = target - position.pixels;
    if (correction.abs() < 0.5) {
      return;
    }
    _lastGeomJumpAttemptReason = 'correctBy__silentAbsorb';
    _lastGeomJumpAttemptAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      position.correctBy(correction);
    } catch (_) {
      final target = position.minScrollExtent;
      if ((position.pixels - target).abs() > 0.5) {
        _geomJumpTo(target, reason: 'jump__silentAbsorbExtentDelta');
      }
    }
  }

  bool _shouldSuppressContinuousInitialHeightCorrection(String rowKey) {
    final until = _viewportInsert
            .continuousViewportPushInitialLayoutUntilMsByKey[rowKey] ??
        0;
    if (until <= 0) {
      return false;
    }
    if (DateTime.now().millisecondsSinceEpoch < until) {
      return true;
    }
    _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey.remove(
      rowKey,
    );
    return false;
  }

  void _snapArmedViewportInsertRevealOpen() {
    final controller = _viewportInsert.rowRevealController;
    if (_viewportInsert.activeRowRevealMessages.isEmpty) {
      return;
    }
    if (controller != null) {
      controller.stop();
      if (controller.value < 1) {
        controller.value = 1;
      }
    }
    if (_viewportInsert.activeRowRevealMessages.isNotEmpty) {
      _completeRowRevealTransaction();
    }
  }

  void _beginInboundViewportPushPresentation() {
    final model = _chatGlobalModel ??
        (mounted
            ? Provider.of<TUIChatGlobalModel>(context, listen: false)
            : null);
    model?.beginInboundViewportPush(_conversationId());
  }

  void _endInboundViewportPushPresentation() {
    final model = _chatGlobalModel ??
        (mounted
            ? Provider.of<TUIChatGlobalModel>(context, listen: false)
            : null);
    model?.endInboundViewportPush(_conversationId());
  }

  void _queueViewportInsertMessages(List<V2TimMessage> messages) {
    final screenWidth = mounted ? MediaQuery.sizeOf(context).width : null;
    final suppressInitialLayoutUntil = DateTime.now().millisecondsSinceEpoch +
        _continuousViewportPushInitialLayoutSuppressMs;
    for (final message in messages) {
      if (screenWidth != null && screenWidth > 0) {
        ChatMessageHeightCache.instance.seedEstimateIfAbsent(
          message,
          screenWidth: screenWidth,
        );
      } else {
        ChatMessageHeightCache.instance.seedPlaceholderIfAbsent(message);
      }
      final rowKey = _stableMessageListKey(message, 0);
      _viewportInsert.queuedViewportInsertMessages[rowKey] = message;
      // 必须在零高行首次布局前标记。若等到 commit 才标记，placeholder ->
      // 实测高度产生的 silentAbsorb 已在上一帧排队，会与 fullExtent 重复补偿。
      _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey[rowKey] =
          suppressInitialLayoutUntil;
    }
    ChatJitterDiag.logInboundFlow(
      action: 'viewport_slide_queue',
      conv: _conversationId(),
      extras: <String, Object?>{
        'added': messages.length,
        'queued': _viewportInsert.queuedViewportInsertMessages.length,
        'generation': _viewportInsert.viewportInsertSlideGeneration,
        'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
      },
    );
  }

  void _drainQueuedViewportInsertMessages() {
    if (!mounted || _viewportInsert.queuedViewportInsertMessages.isEmpty) {
      return;
    }
    final queued = List<V2TimMessage>.from(
      _viewportInsert.queuedViewportInsertMessages.values,
    );
    _viewportInsert.queuedViewportInsertMessages.clear();
    _startWechatViewportInsertSlide(queued);
    // 排队行先前绑定的是静止 0；重建后才会绑定本轮 controller。
    if (mounted) {
      setState(() {});
    }
  }

  void _disposeShortListInsertions({String? conversationID}) {
    if (_shortInsertProgress.isNotEmpty) {
      (_chatGlobalModel ?? widget.model.globalModel).endInboundViewportPush(
        conversationID ?? _conversationId(),
        settleMilliseconds: 0,
      );
    }
    for (final controller in _shortInsertControllers) {
      controller.dispose();
    }
    _shortInsertControllers.clear();
    _shortInsertProgress.clear();
  }

  void _startShortListInsertions(List<V2TimMessage> messages) {
    final model = _chatGlobalModel ??
        Provider.of<TUIChatGlobalModel>(context, listen: false);
    final conv = _conversationId();
    final fresh = messages
        .where((message) =>
            !_shortInsertProgress.containsKey(_stableMessageListKey(message, 0)))
        .toList(growable: false);
    if (fresh.isEmpty) return;
    _lastHandledPinSeq = model.pinToBottomRequestSeq;
    _cancelForcePinScroll();
    if (_shortInsertProgress.isEmpty) _beginInboundViewportPushPresentation();
    _viewportInsert.viewportInsertSlideActive = true;
    final controller = AnimationController(
      vsync: this,
      duration: ChatViewportMotion.durationFor(
        outgoing: fresh.every((message) => message.isSelf == true),
        extent: _estimatedInsertedExtent(fresh),
      ),
    );
    final progress = controller.drive(CurveTween(curve: ChatViewportMotion.curve));
    _shortInsertControllers.add(controller);
    final keys = fresh.map((message) => _stableMessageListKey(message, 0)).toList();
    for (final key in keys) {
      _shortInsertProgress[key] = progress;
    }
    for (final message in fresh) {
      model.finishMessageEnterAnimation(message);
    }
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      for (final key in keys) {
        if (identical(_shortInsertProgress[key], progress)) {
          _shortInsertProgress.remove(key);
        }
      }
      if (_shortInsertProgress.isEmpty) {
        _viewportInsert.viewportInsertSlideActive = false;
        _beginViewportInsertSettle();
        model.endInboundViewportPush(conv);
      }
      if (mounted) setState(() {});
      // Keep the completed animation alive until render objects switch to 1.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_shortInsertControllers.remove(controller)) controller.dispose();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_shortInsertControllers.contains(controller) ||
          controller.isCompleted ||
          _conversationId() != conv) return;
      // Acknowledge measured layout, not animation completion. Later arrivals
      // get their own smooth extent, while earlier rows keep their velocity.
      controller.forward();
      model.completeInboundProjectionReveal(conv);
    });
  }

  void _startContinuousViewportInsertPush(List<V2TimMessage> messages) {
    final position = _singleScrollPositionOrNull();
    if (messages.isEmpty ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      _finishIncomingMessagesWithoutRowReveal(messages);
      return;
    }

    // Unfilled lists reveal real row extents. Overlapping inserts keep earlier
    // controllers running, even if this batch fills the viewport midway.
    if (!_viewportInsert.continuousViewportPushActive &&
        (_shortInsertProgress.isNotEmpty ||
            position.maxScrollExtent <= position.minScrollExtent + 0.5)) {
      _startShortListInsertions(messages);
      return;
    }

    final model = _chatGlobalModel ??
        Provider.of<TUIChatGlobalModel>(context, listen: false);
    _lastHandledPinSeq = model.pinToBottomRequestSeq;
    _cancelForcePinScroll();

    if (!_viewportInsert.continuousViewportPushActive) {
      if (_viewportInsert.activeRowRevealMessages.isNotEmpty ||
          (_viewportInsert.rowRevealController?.isAnimating ?? false)) {
        _finishActiveRowRevealImmediately();
      }
      _viewportInsert.continuousViewportPushActive = true;
      _viewportInsert.viewportInsertSlideActive = true;
      ++_viewportInsert.viewportInsertSlideGeneration;
      ++_viewportInsert.continuousViewportPushDiagTransaction;
      _viewportInsert.continuousViewportPushDiagFrame = 0;
      _viewportInsert.continuousViewportPushLastCommandedPixels =
          position.pixels;
      _beginInboundViewportPushPresentation();
      _viewportInsert.continuousViewportPushTicker ??= createTicker(
        _onContinuousViewportPushTick,
      );
      ChatJitterDiag.logFollowingLatest(
        action: 'list_push_start',
        conv: _conversationId(),
        extras: <String, Object?>{
          'count': messages.length,
          'pixels': position.pixels.toStringAsFixed(1),
          'minExtent': position.minScrollExtent.toStringAsFixed(1),
          ...model.stickToLatestDiagSnapshot(_conversationId()),
        },
      );
      ChatJitterDiag.logInboundFlow(
        action: 'continuous_viewport_push_begin',
        conv: _conversationId(),
        extras: <String, Object?>{
          'pixels': position.pixels.toStringAsFixed(1),
          'minExtent': position.minScrollExtent.toStringAsFixed(1),
          'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
          'viewport': position.viewportDimension.toStringAsFixed(1),
          'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
        },
      );
    }

    _queueViewportInsertMessages(messages);
    _scheduleContinuousViewportPushIntegration();
  }

  void _scheduleContinuousViewportPushIntegration({int attempt = 0}) {
    if (_viewportInsert.continuousViewportPushIntegrationScheduled ||
        _viewportInsert.queuedViewportInsertMessages.isEmpty) {
      return;
    }
    _viewportInsert.continuousViewportPushIntegrationScheduled = true;
    final generation =
        ++_viewportInsert.continuousViewportPushIntegrationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportInsert.continuousViewportPushIntegrationScheduled = false;
      if (!mounted ||
          !_viewportInsert.continuousViewportPushActive ||
          generation !=
              _viewportInsert.continuousViewportPushIntegrationGeneration ||
          _viewportInsert.queuedViewportInsertMessages.isEmpty) {
        return;
      }

      final measuredEntries = List<MapEntry<String, V2TimMessage>>.from(
        _viewportInsert.queuedViewportInsertMessages.entries,
      );
      var fullExtent = 0.0;
      var allMeasured = true;
      for (final entry in measuredEntries) {
        final height = _viewportInsert.rowRevealFullExtentByKey[entry.key];
        if (height == null || height <= 0.5) {
          allMeasured = false;
          break;
        }
        fullExtent += height;
      }
      if (!allMeasured || fullExtent <= 0.5) {
        if (attempt < _continuousViewportPushMeasureMaxAttempts) {
          _scheduleContinuousViewportPushIntegration(attempt: attempt + 1);
        } else {
          final pending = List<V2TimMessage>.from(
            _viewportInsert.queuedViewportInsertMessages.values,
          );
          _viewportInsert.queuedViewportInsertMessages.clear();
          _finishIncomingMessagesWithoutRowReveal(pending);
          _finishContinuousViewportPush(
            reachedBottom: false,
            forcePinOnMiss: true,
          );
        }
        return;
      }

      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (!mounted ||
            !_viewportInsert.continuousViewportPushActive ||
            generation !=
                _viewportInsert.continuousViewportPushIntegrationGeneration) {
          return;
        }
        final model = _chatGlobalModel;
        if (model != null &&
            (model.isMessageContextMenuOverlayOpen ||
                model.isContextMenuViewportRestoreActive(_conversationId()))) {
          _abortViewportInsertSlideForSupersede();
          return;
        }
        final currentPosition = _singleScrollPositionOrNull();
        if (currentPosition == null ||
            !currentPosition.hasPixels ||
            !currentPosition.hasContentDimensions ||
            (_chatGlobalModel?.isChatListUserScrolling ?? false)) {
          _finishContinuousViewportPush(reachedBottom: false);
          return;
        }

        final committed =
            measuredEntries.map((entry) => entry.value).toList(growable: false);
        final committedKeys = measuredEntries.map((entry) => entry.key).toSet();

        // 真实高度已在零高帧完成测量。frame callback 发生在 layout/paint 前：
        // 普通插入同帧抵消高度变化；超一屏的 burst 只保留末屏过渡。
        final pixelsBeforeCorrection = currentPosition.pixels;
        final minBeforeCorrection = currentPosition.minScrollExtent;
        final maxBeforeCorrection = currentPosition.maxScrollExtent;
        ChatJitterDiag.logInboundFlow(
          action: 'cvp_integrate_before',
          conv: _conversationId(),
          extras: <String, Object?>{
            'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
            'rows': committed.length,
            'measuredExtent': fullExtent.toStringAsFixed(2),
            'pixels': pixelsBeforeCorrection.toStringAsFixed(2),
            'min': minBeforeCorrection.toStringAsFixed(2),
            'max': maxBeforeCorrection.toStringAsFixed(2),
            'viewport': currentPosition.viewportDimension.toStringAsFixed(2),
            'outOfRange': currentPosition.outOfRange,
            'queuedTotal': _viewportInsert.queuedViewportInsertMessages.length,
          },
        );
        final correction = ChatViewportMotion.correction(
          currentPosition.pixels - currentPosition.minScrollExtent,
          fullExtent,
          currentPosition.viewportDimension,
        );
        currentPosition.correctBy(correction);
        _viewportInsert.motion.retarget(
          _viewportInsert.continuousViewportPushLastElapsed ?? Duration.zero,
          outgoing: committed.every((message) => message.isSelf == true),
          distance: currentPosition.pixels - currentPosition.minScrollExtent,
          restart: _viewportInsert.continuousViewportPushLastElapsed == null,
        );
        _viewportInsert.continuousViewportPushLastCommandedPixels =
            currentPosition.pixels;
        ChatJitterDiag.logInboundFlow(
          action: 'cvp_integrate_after_correct',
          conv: _conversationId(),
          extras: <String, Object?>{
            'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
            'requestedCorrection': correction.toStringAsFixed(2),
            'pixelsBefore': pixelsBeforeCorrection.toStringAsFixed(2),
            'pixelsAfter': currentPosition.pixels.toStringAsFixed(2),
            'appliedCorrection':
                (currentPosition.pixels - pixelsBeforeCorrection)
                    .toStringAsFixed(2),
            'maxStill': currentPosition.maxScrollExtent.toStringAsFixed(2),
            'outOfRange': currentPosition.outOfRange,
          },
        );
        for (final key in committedKeys) {
          _viewportInsert.queuedViewportInsertMessages.remove(key);
        }
        for (final entry in measuredEntries) {
          if (!committedKeys.contains(entry.key)) {
            continue;
          }
          final height = _viewportInsert.rowRevealFullExtentByKey[entry.key];
          if (height != null && height > 0.5) {
            _viewportInsert.continuousViewportPushRemainingRowExtents.add(
              height,
            );
          }
        }
        final globalModel = _chatGlobalModel;
        if (globalModel != null) {
          for (final message in committed) {
            globalModel.finishMessageEnterAnimation(message);
          }
          globalModel.completeInboundProjectionReveal(_conversationId());
        }
        for (final key in committedKeys) {
          _viewportInsert.rowRevealFullExtentByKey.remove(key);
        }
        final suppressInitialLayoutUntil =
            DateTime.now().millisecondsSinceEpoch +
                _continuousViewportPushInitialLayoutSuppressMs;
        for (final key in committedKeys) {
          _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey[key] =
              suppressInitialLayoutUntil;
        }
        _beginMediaSettleForMessages(committed, holdMs: 1200);
        if (mounted) {
          setState(() {});
        }
        ChatJitterDiag.logInboundFlow(
          action: 'continuous_viewport_push_integrate',
          conv: _conversationId(),
          extras: <String, Object?>{
            'rows': committed.length,
            'extent': fullExtent.toStringAsFixed(1),
            'pixels': currentPosition.pixels.toStringAsFixed(1),
            'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
          },
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          final laidOutPosition = _singleScrollPositionOrNull();
          if (laidOutPosition == null ||
              !laidOutPosition.hasPixels ||
              !laidOutPosition.hasContentDimensions) {
            return;
          }
          ChatJitterDiag.logInboundFlow(
            action: 'cvp_integrate_post_layout',
            conv: _conversationId(),
            extras: <String, Object?>{
              'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
              'measuredExtent': fullExtent.toStringAsFixed(2),
              'pixelsBefore': pixelsBeforeCorrection.toStringAsFixed(2),
              'pixelsAfter': laidOutPosition.pixels.toStringAsFixed(2),
              'pixelsDelta': (laidOutPosition.pixels - pixelsBeforeCorrection)
                  .toStringAsFixed(2),
              'maxBefore': maxBeforeCorrection.toStringAsFixed(2),
              'maxAfter': laidOutPosition.maxScrollExtent.toStringAsFixed(2),
              'maxDelta':
                  (laidOutPosition.maxScrollExtent - maxBeforeCorrection)
                      .toStringAsFixed(2),
              'extentError': (laidOutPosition.maxScrollExtent -
                      maxBeforeCorrection -
                      fullExtent)
                  .toStringAsFixed(2),
              'outOfRange': laidOutPosition.outOfRange,
            },
          );
        });
        _startContinuousViewportPushTicker();
        if (_viewportInsert.queuedViewportInsertMessages.isNotEmpty) {
          _scheduleContinuousViewportPushIntegration();
        }
      });
    });
  }

  void _startContinuousViewportPushTicker() {
    // Ticker.start 会以当前帧为时间原点。预置 zero 后，下一次 vsync 可直接
    // 使用首段 elapsed；旧逻辑首个 callback 只赋值后 return，白白空转一帧。
    _viewportInsert.startContinuousViewportPushTicker();
  }

  void _consumeContinuousViewportPushTravel(double travel) {
    _viewportInsert.consumeContinuousViewportPushTravel(travel);
  }

  void _onContinuousViewportPushTick(Duration elapsed) {
    if (!mounted || !_viewportInsert.continuousViewportPushActive) {
      _viewportInsert.continuousViewportPushTicker?.stop();
      return;
    }
    final globalModel = _chatGlobalModel;
    if (globalModel == null || globalModel.isChatListUserScrolling) {
      _finishContinuousViewportPush(reachedBottom: false);
      return;
    }
    // A context menu freezes the selected message in viewport coordinates.
    // An already-running inbound ticker used to keep issuing cvp_tick jumps
    // underneath the overlay, forcing close-time restoration to visibly jump
    // back from the bottom. Stop the transaction before any scroll write.
    if (globalModel.isMessageContextMenuOverlayOpen ||
        globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      _finishContinuousViewportPush(reachedBottom: false);
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      _finishContinuousViewportPush(reachedBottom: false);
      return;
    }
    final previousElapsed = _viewportInsert.continuousViewportPushLastElapsed;
    _viewportInsert.continuousViewportPushLastElapsed = elapsed;
    if (previousElapsed == null) {
      return;
    }
    final elapsedMicros = (elapsed - previousElapsed).inMicroseconds.clamp(
          0,
          50000,
        );
    final pendingRows =
        _viewportInsert.continuousViewportPushRemainingRowExtents.length +
            _viewportInsert.queuedViewportInsertMessages.length;
    // Once all measured rows have been integrated there is no viewport work
    // left for the ticker.  Keeping the ticker alive here causes an idle chat
    // page to schedule a frame on every vsync (and repeatedly flush layout,
    // paint and semantics).  The integration callback will start it again
    // when a new batch is queued.
    if (pendingRows == 0 &&
        !_viewportInsert.continuousViewportPushIntegrationScheduled) {
      _finishContinuousViewportPush(reachedBottom: false);
      return;
    }
    final distance = max(0.0, position.pixels - position.minScrollExtent);
    final travel = distance * _viewportInsert.motion.consumeFraction(
      elapsed,
      disableAnimations: MediaQuery.of(context).disableAnimations,
    );
    final speed = elapsedMicros > 0 ? travel * 1000000 / elapsedMicros : 0.0;
    final pixelsBefore = position.pixels;
    final externalDrift =
        _viewportInsert.continuousViewportPushLastCommandedPixels == null
            ? 0.0
            : pixelsBefore -
                _viewportInsert.continuousViewportPushLastCommandedPixels!;
    final target = max(
      position.minScrollExtent,
      position.pixels - travel,
    ).toDouble();
    if ((position.pixels - target).abs() > 0.1) {
      _geomJumpTo(target, reason: 'cvp_tick');
    }
    final pixelsAfter =
        _singleScrollPositionOrNull()?.pixels ?? position.pixels;
    final actualTravel = pixelsBefore - pixelsAfter;
    _consumeContinuousViewportPushTravel(actualTravel);
    _viewportInsert.continuousViewportPushLastCommandedPixels = pixelsAfter;
    final reachedBottom = (pixelsAfter - position.minScrollExtent).abs() <= 0.5;
    final frame = ++_viewportInsert.continuousViewportPushDiagFrame;
    // debugPrint 会在 UI isolate 上格式化并节流。120Hz 下逐帧记录会反过来制造
    // 动画卡顿；仅保留起始帧、每 15 帧采样、异常漂移和结束帧。
    final shouldLogTick = frame <= 3 ||
        frame % 15 == 0 ||
        externalDrift.abs() > 0.5 ||
        reachedBottom;
    if (shouldLogTick) {
      ChatJitterDiag.logInboundFlow(
        action: 'cvp_tick',
        conv: _conversationId(),
        extras: <String, Object?>{
          'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
          'tick': frame,
          'elapsedUs': elapsedMicros,
          'pendingRows': pendingRows,
          'speed': speed.toStringAsFixed(1),
          'requestedTravel': travel.toStringAsFixed(2),
          'pixelsBefore': pixelsBefore.toStringAsFixed(2),
          'target': target.toStringAsFixed(2),
          'pixelsAfter': pixelsAfter.toStringAsFixed(2),
          'actualTravel': actualTravel.toStringAsFixed(2),
          'externalDriftSinceLastTick': externalDrift.toStringAsFixed(2),
          'min': position.minScrollExtent.toStringAsFixed(2),
          'max': position.maxScrollExtent.toStringAsFixed(2),
          'viewport': position.viewportDimension.toStringAsFixed(2),
          'queued': _viewportInsert.queuedViewportInsertMessages.length,
          'integrationScheduled':
              _viewportInsert.continuousViewportPushIntegrationScheduled,
          'outOfRange': position.outOfRange,
        },
      );
    }
    if (reachedBottom &&
        _viewportInsert.queuedViewportInsertMessages.isEmpty &&
        !_viewportInsert.continuousViewportPushIntegrationScheduled) {
      _finishContinuousViewportPush(reachedBottom: true);
    }
  }

  void _finishContinuousViewportPush({
    required bool reachedBottom,
    bool forcePinOnMiss = false,
  }) {
    if (!_viewportInsert.continuousViewportPushActive) {
      return;
    }
    _viewportInsert.continuousViewportPushTicker?.stop();
    _viewportInsert.continuousViewportPushLastElapsed = null;
    _viewportInsert.continuousViewportPushLastCommandedPixels = null;
    _viewportInsert.continuousViewportPushActive = false;
    _viewportInsert.viewportInsertSlideActive = false;
    _viewportInsert.continuousViewportPushIntegrationScheduled = false;
    _viewportInsert.continuousViewportPushInitialLayoutUntilMsByKey.clear();
    _viewportInsert.continuousViewportPushRemainingRowExtents.clear();
    ++_viewportInsert.continuousViewportPushIntegrationGeneration;
    _beginViewportInsertSettle();
    _cancelForcePinScroll();
    if (_viewportInsert.queuedViewportInsertMessages.isNotEmpty) {
      final pending = List<V2TimMessage>.from(
        _viewportInsert.queuedViewportInsertMessages.values,
      );
      _finishIncomingMessagesWithoutRowReveal(pending);
      if (mounted) {
        setState(() {});
      }
    }
    final globalModel = _chatGlobalModel;
    final shouldForcePinOnMiss = forcePinOnMiss &&
        !reachedBottom &&
        mounted &&
        !(globalModel?.isChatListUserScrolling ?? false);
    if (reachedBottom && globalModel != null) {
      globalModel.setMessageListPosition(
        _conversationId(),
        HistoryMessagePosition.bottom,
        notify: false,
      );
    } else if (globalModel != null && !shouldForcePinOnMiss) {
      final position = _singleScrollPositionOrNull();
      if (position != null &&
          position.hasPixels &&
          position.hasContentDimensions) {
        final distance = position.pixels - position.minScrollExtent;
        final nextPosition = position.viewportDimension > 0 &&
                distance > position.viewportDimension
            ? HistoryMessagePosition.awayTwoScreen
            : HistoryMessagePosition.inTwoScreen;
        globalModel.setMessageListPosition(
          _conversationId(),
          nextPosition,
          notify: false,
        );
        if (nextPosition == HistoryMessagePosition.awayTwoScreen) {
          // correctBy 是静默修正，不会产生 ScrollNotification。爆发冻结后补发一次
          // 同位置通知，让 tongue 立即按“一屏外”状态显示回到底部入口。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            final settledPosition = _singleScrollPositionOrNull();
            if (settledPosition != null && settledPosition.hasPixels) {
              _geomJumpTo(
                settledPosition.pixels,
                reason: 'jump__finishIncomingMessagesWithoutRowReveal',
              );
            }
          });
        }
      }
    }
    _endInboundViewportPushPresentation();
    ChatJitterDiag.logInboundFlow(
      action: 'continuous_viewport_push_end',
      conv: _conversationId(),
      extras: <String, Object?>{
        'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
        'ticks': _viewportInsert.continuousViewportPushDiagFrame,
        'reachedBottom': reachedBottom,
        'forcePinOnMiss': shouldForcePinOnMiss,
        'queued': _viewportInsert.queuedViewportInsertMessages.length,
        'pixels': _singleScrollPositionOrNull()?.pixels.toStringAsFixed(2),
        'min': _singleScrollPositionOrNull()?.minScrollExtent.toStringAsFixed(
              2,
            ),
        'max': _singleScrollPositionOrNull()?.maxScrollExtent.toStringAsFixed(
              2,
            ),
      },
    );
    if (shouldForcePinOnMiss) {
      ChatJitterDiag.logInboundFlow(
        action: 'cvp_measure_miss_force_pin',
        conv: _conversationId(),
        extras: <String, Object?>{
          'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
        },
      );
      _scheduleForcePinScrollToBottom(ignoreInsertWindows: true);
    }
  }

  void _startWechatViewportInsertSlide(List<V2TimMessage> messages) {
    if (_viewportInsert.viewportInsertSlideActive) {
      _queueViewportInsertMessages(messages);
      return;
    }
    final controller = _viewportInsert.rowRevealController;
    final beforePosition = _singleScrollPositionOrNull();
    if (messages.isEmpty ||
        controller == null ||
        beforePosition == null ||
        !beforePosition.hasPixels ||
        !beforePosition.hasContentDimensions) {
      _finishIncomingMessagesWithoutRowReveal(messages);
      return;
    }

    // 发送会同时 requestPinToBottom(force)。先消费掉这次 pin，避免
    // cancel 之后又被 _onPinToBottomRequested 重新 schedule，和上推动画抢滚。
    final pinModel = _chatGlobalModel ??
        (mounted
            ? Provider.of<TUIChatGlobalModel>(context, listen: false)
            : null);
    if (pinModel != null) {
      _lastHandledPinSeq = pinModel.pinToBottomRequestSeq;
    }
    _cancelForcePinScroll();

    // 上推会短暂 jump 离底；先锁贴底语义，避免右侧「回到底部」闪一下。
    _beginInboundViewportPushPresentation();

    // Build 前零高：本帧不把旧消息顶走。
    _armZeroHeightViewportInsert(messages);

    final oldPixels = beforePosition.pixels;
    final oldMaxScrollExtent = beforePosition.maxScrollExtent;
    final generation = ++_viewportInsert.viewportInsertSlideGeneration;
    _viewportInsert.viewportInsertSlideActive = true;
    ChatJitterDiag.logInboundFlow(
      action: 'viewport_slide_schedule',
      conv: _conversationId(),
      extras: <String, Object?>{
        'rows': messages.length,
        'pixels': oldPixels.toStringAsFixed(1),
        'minExtent': beforePosition.minScrollExtent.toStringAsFixed(1),
        'maxExtent': oldMaxScrollExtent.toStringAsFixed(1),
        'armedZeroHeight': true,
        'hasOutgoing': messages.any((m) => m.isSelf == true),
        'mode': 'viewport_scroll',
        'generation': generation,
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _viewportInsert.viewportInsertSlideGeneration) {
        // 被更新一轮覆盖时，由新一代持有锁；勿 end 掉新锁。
        return;
      }

      var position = _singleScrollPositionOrNull();
      if (position == null ||
          !position.hasPixels ||
          !position.hasContentDimensions) {
        _viewportInsert.viewportInsertSlideActive = false;
        _releaseArmedViewportInsertReveal();
        _endInboundViewportPushPresentation();
        return;
      }

      if (_chatGlobalModel?.isChatListUserScrolling ?? false) {
        _viewportInsert.viewportInsertSlideActive = false;
        _releaseArmedViewportInsertReveal();
        _endInboundViewportPushPresentation();
        return;
      }

      final cachedExtent = _cachedInsertedExtent(messages);
      final estimatedExtent = _estimatedInsertedExtent(messages);
      var chosenExtent = (cachedExtent != null && cachedExtent > 0)
          ? cachedExtent
          : estimatedExtent;
      if (chosenExtent <= 0.5) {
        chosenExtent = _shortHistoryMessageEstimatedRowHeight;
      }

      final viewportHeight = position.viewportDimension;
      // 能否补偿要看「展开后」的可滚空间。旧逻辑用展开前 maxScrollExtent：
      // 当气泡高度 > 当前剩余可滚高度时会误判 no_scroll_room → grow，
      // 整段可见历史会被 SizeTransition 一起顶走。
      // 列表已可滚（oldMax > 0）时，expand 后 max 大约 +chosenExtent，应走 atomic。
      // 仅短列表（内容未铺满视口、max≈0）才走零→满 grow。
      final canCompensateJump = oldMaxScrollExtent > 0.5 &&
          (oldPixels + chosenExtent) > position.minScrollExtent + 0.5;

      // 短列表无滚动空间：收/发都走零→满 grow，直接从底部顶起。
      // 有空间时收/发统一走下方 atomic（expand 后同帧实测 jump + animateTo），
      // 不再把发送单独拆成 grow，否则观感会分叉。
      if (!canCompensateJump) {
        final durationMs = _listPushDurationMs(
          motionExtent: chosenExtent,
          viewportHeight: viewportHeight,
          outgoing: messages.every((message) => message.isSelf == true),
        );
        ChatJitterDiag.logInboundFlow(
          action: 'viewport_slide_start',
          conv: _conversationId(),
          extras: <String, Object?>{
            'rows': messages.length,
            'chosenExtent': chosenExtent.toStringAsFixed(1),
            'durationMs': durationMs,
            'mode': 'row_reveal_grow',
            'reason': 'no_scroll_room',
            'hasOutgoing': messages.any((m) => m.isSelf == true),
          },
        );
        controller.duration = Duration(milliseconds: durationMs);
        try {
          await controller.forward(from: 0);
        } catch (_) {
        } finally {
          if (mounted &&
              generation == _viewportInsert.viewportInsertSlideGeneration) {
            _viewportInsert.viewportInsertSlideActive = false;
            _beginViewportInsertSettle();
            // 收尾仍保持一段 absorb 窗，避免 grow 结束后二次 layout 再 pin 顶历史。
            _beginMediaSettleForMessages(messages, holdMs: 900);
            _cancelForcePinScroll();
            if (_viewportInsert.activeRowRevealMessages.isNotEmpty) {
              _releaseArmedViewportInsertReveal();
            } else {
              _acknowledgeInboundProjectionRevealIfNeeded();
            }
            _drainQueuedViewportInsertMessages();
            _endInboundViewportPushPresentation();
            ChatJitterDiag.logInboundFlow(
              action: 'viewport_slide_end',
              conv: _conversationId(),
              extras: <String, Object?>{
                'mode': 'row_reveal_grow',
                'generation': generation,
              },
            );
          }
        }
        return;
      }

      // 收/发统一：撑满后 flushLayout 用实测高度 jump，再 animateTo 从底部上推。
      _expandArmedViewportInsertToFullHeight();
      try {
        RendererBinding.instance.pipelineOwner.flushLayout();
      } catch (_) {
        // Layout pipeline may be unavailable in rare teardown races.
      }

      position = _singleScrollPositionOrNull();
      if (position == null ||
          !position.hasPixels ||
          !position.hasContentDimensions) {
        _viewportInsert.viewportInsertSlideActive = false;
        _releaseArmedViewportInsertReveal();
        _endInboundViewportPushPresentation();
        return;
      }

      final measuredExtent = max(
        0.0,
        position.maxScrollExtent - oldMaxScrollExtent,
      );
      // 补偿只能使用真实 layout 高度。预估偏大时 jump 会把历史向下拉一帧，
      // 随后的 animateTo 又向上推，正是录像里的方向反转。
      final pushExtent =
          measuredExtent > 0.5 ? measuredExtent : (cachedExtent ?? 0.0);
      if (pushExtent <= 0.5) {
        ChatJitterDiag.logInboundFlow(
          action: 'viewport_slide_no_measured_extent',
          conv: _conversationId(),
          extras: <String, Object?>{
            'estimatedExtent': estimatedExtent.toStringAsFixed(1),
            'measuredExtent': measuredExtent.toStringAsFixed(1),
          },
        );
        _viewportInsert.viewportInsertSlideActive = false;
        _beginViewportInsertSettle();
        _beginMediaSettleForMessages(messages, holdMs: 900);
        if (_viewportInsert.activeRowRevealMessages.isNotEmpty) {
          _releaseArmedViewportInsertReveal();
        }
        _drainQueuedViewportInsertMessages();
        _endInboundViewportPushPresentation();
        return;
      }
      // 展开后若仍几乎跳不动（极端短列表误判），回退 grow，避免「闪全高」。
      final predictedStart = oldPixels + pushExtent;
      if (predictedStart > position.maxScrollExtent + 0.5 &&
          (position.maxScrollExtent - position.minScrollExtent) < 0.5) {
        ChatJitterDiag.logInboundFlow(
          action: 'viewport_slide_fallback_grow',
          conv: _conversationId(),
          extras: <String, Object?>{
            'pushExtent': pushExtent.toStringAsFixed(1),
            'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
          },
        );
        // 已 expand 到 1：直接收尾，不再二次动画顶历史。
        _viewportInsert.viewportInsertSlideActive = false;
        _beginViewportInsertSettle();
        _beginMediaSettleForMessages(messages, holdMs: 900);
        _cancelForcePinScroll();
        if (_viewportInsert.activeRowRevealMessages.isNotEmpty) {
          _releaseArmedViewportInsertReveal();
        } else {
          _acknowledgeInboundProjectionRevealIfNeeded();
        }
        _drainQueuedViewportInsertMessages();
        _endInboundViewportPushPresentation();
        return;
      }
      final start = (oldPixels + pushExtent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _geomJumpTo(
        start.toDouble(),
        reason: 'jump__releaseArmedViewportInsertReveal',
      );
      position = _singleScrollPositionOrNull() ?? position;

      // 上推过程中文本还可能继续长高，提前进入 media-settle，走 silentAbsorb。
      _beginMediaSettleForMessages(messages, holdMs: 1200);

      if (!mounted ||
          generation != _viewportInsert.viewportInsertSlideGeneration) {
        return;
      }

      if (_chatGlobalModel?.isChatListUserScrolling ?? false) {
        _viewportInsert.viewportInsertSlideActive = false;
        _releaseArmedViewportInsertReveal();
        _endInboundViewportPushPresentation();
        return;
      }

      final travel = max(0.0, position.pixels - position.minScrollExtent);
      final motionExtent = travel > 0.5 ? travel : pushExtent;
      final target = position.minScrollExtent;
      final animateViewportHeight = position.viewportDimension;
      final animateDurationMs = _listPushDurationMs(
        motionExtent: motionExtent,
        viewportHeight: animateViewportHeight,
        outgoing: messages.every((message) => message.isSelf == true),
      );

      ChatJitterDiag.logInboundFlow(
        action: 'viewport_slide_start',
        conv: _conversationId(),
        extras: <String, Object?>{
          'rows': messages.length,
          'estimatedExtent': estimatedExtent.toStringAsFixed(1),
          'cachedExtent': cachedExtent?.toStringAsFixed(1),
          'measuredExtent': measuredExtent.toStringAsFixed(1),
          'chosenExtent': chosenExtent.toStringAsFixed(1),
          'pushExtent': pushExtent.toStringAsFixed(1),
          'motionExtent': motionExtent.toStringAsFixed(1),
          'viewportHeight': animateViewportHeight.toStringAsFixed(1),
          'pps': _listPushPixelsPerSecond(
            extent: motionExtent,
            viewportHeight: animateViewportHeight,
          ).toStringAsFixed(0),
          'start': position.pixels.toStringAsFixed(1),
          'target': target.toStringAsFixed(1),
          'durationMs': animateDurationMs,
          'mode': 'viewport_scroll_atomic',
        },
      );

      _beginMediaSettleForMessages(
        messages,
        holdMs: max(_mediaSettleMs, animateDurationMs + 400),
      );

      try {
        final model = _chatGlobalModel;
        if (model != null &&
            (model.isMessageContextMenuOverlayOpen ||
                model.isContextMenuViewportRestoreActive(_conversationId()))) {
          return;
        }
        await _autoScrollController.animateTo(
          target,
          duration: Duration(milliseconds: animateDurationMs),
          curve: ChatViewportMotion.curve,
        );
      } catch (_) {
      } finally {
        if (mounted &&
            generation == _viewportInsert.viewportInsertSlideGeneration) {
          _viewportInsert.viewportInsertSlideActive = false;
          _beginViewportInsertSettle();
          // 注意：不要用默认 400ms 覆盖上面的长窗，否则晚到的长高会走 pin 再顶历史。
          _beginMediaSettleForMessages(messages, holdMs: 1200);
          _cancelForcePinScroll();
          if (_viewportInsert.activeRowRevealMessages.isNotEmpty) {
            _releaseArmedViewportInsertReveal();
          } else {
            _acknowledgeInboundProjectionRevealIfNeeded();
          }
          _drainQueuedViewportInsertMessages();
          final globalModel = _chatGlobalModel;
          final endPosition = _singleScrollPositionOrNull();
          final reachedBottom = endPosition != null &&
              endPosition.hasPixels &&
              (endPosition.pixels - endPosition.minScrollExtent).abs() <= 1 &&
              !(globalModel?.isChatListUserScrolling ?? false);
          if (globalModel != null && reachedBottom) {
            globalModel.setMessageListPosition(
              _conversationId(),
              HistoryMessagePosition.bottom,
              notify: false,
            );
          }
          _endInboundViewportPushPresentation();
          ChatJitterDiag.logInboundFlow(
            action: 'viewport_slide_end',
            conv: _conversationId(),
            extras: <String, Object?>{
              'reachedBottom': reachedBottom,
              'pixels': endPosition?.hasPixels == true
                  ? endPosition!.pixels.toStringAsFixed(1)
                  : 'n/a',
              'minExtent': endPosition?.hasContentDimensions == true
                  ? endPosition!.minScrollExtent.toStringAsFixed(1)
                  : 'n/a',
              'userScrolling': globalModel?.isChatListUserScrolling,
              'generation': generation,
              'mode': 'viewport_scroll_atomic',
            },
          );
        }
      }
    });
  }

  bool _isRouteBackGestureInProgress() {
    if (!mounted) {
      return false;
    }
    return Navigator.maybeOf(context)?.userGestureInProgress ?? false;
  }

  void _onHeadMessageLaidOut(V2TimMessage message, Size size, Rect globalRect) {
    _updateLatestMessageVisibility();
    final previousHeight = ChatMessageHeightCache.instance.heightFor(message);
    if (size.height > 0) {
      ChatMessageHeightCache.instance.remember(message, size.height);
      final msgId = message.msgID?.trim() ?? message.id?.trim() ?? '';
      final shortId = msgId.length > 28
          ? '${msgId.substring(0, 12)}…${msgId.substring(msgId.length - 8)}'
          : msgId;
      ChatGeomSettleTrace.noteReason(
        'row_height_remember',
        extras: <String, Object?>{
          'msgId': shortId,
          'prev': previousHeight?.toStringAsFixed(1),
          'next': size.height.toStringAsFixed(1),
          'delta': previousHeight == null
              ? 'n/a'
              : (size.height - previousHeight).toStringAsFixed(1),
        },
      );
      if (previousHeight != null) {
        _noteShortHistoryRowHeightBumpForReveal(size.height - previousHeight);
      }
    }
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final rowKey = _stableMessageListKey(message, 0);
    final heightDelta =
        previousHeight == null ? 0.0 : size.height - previousHeight;
    final inMediaSettle = _isMediaSettlingForKey(rowKey);
    final suppressContinuousInitialCorrection =
        _shouldSuppressContinuousInitialHeightCorrection(rowKey);
    if (previousHeight != null &&
        heightDelta.abs() > 1 &&
        suppressContinuousInitialCorrection) {
      ChatJitterDiag.logInboundFlow(
        action: 'cvp_initial_height_correction_suppressed',
        conv: _conversationId(),
        extras: <String, Object?>{
          'before': previousHeight.toStringAsFixed(1),
          'after': size.height.toStringAsFixed(1),
          'delta': heightDelta.toStringAsFixed(1),
          'cvpTx': _viewportInsert.continuousViewportPushDiagTransaction,
        },
      );
    }
    if (previousHeight != null &&
        heightDelta.abs() > 1 &&
        !suppressContinuousInitialCorrection &&
        !globalModel.isChatListUserScrolling &&
        !_isRouteBackGestureInProgress() &&
        _shouldPinScrollToBottom(globalModel)) {
      // 上推进行中 / settle / 媒体稳定窗：长高必须 silentAbsorb。
      // 以前 slide 期间直接跳过 → 长文本二次 layout 把历史整体顶走，再 pin 一次。
      // 贴底时长高也优先 absorb：pin 会整表跳到底，观感就是「历史被一起推」。
      final preferSilentAbsorb = _viewportInsert.viewportInsertSlideActive ||
          _isViewportInsertSettling() ||
          inMediaSettle ||
          globalModel.isInboundPresentationBottomLocked(_conversationId());
      if (preferSilentAbsorb) {
        ChatJitterDiag.logInboundFlow(
          action: 'silent_extent_absorb',
          conv: _conversationId(),
          extras: <String, Object?>{
            'before': previousHeight.toStringAsFixed(1),
            'after': size.height.toStringAsFixed(1),
            'delta': heightDelta.toStringAsFixed(1),
            'mediaSettle': inMediaSettle,
            'viewportSlide': _viewportInsert.viewportInsertSlideActive,
          },
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              globalModel.isChatListUserScrolling ||
              _isRouteBackGestureInProgress()) {
            return;
          }
          _silentAbsorbExtentDelta(heightDelta);
        });
      } else {
        // 贴底时长高优先 silentAbsorb，避免 pin 整表跳造成「历史一起被推」。
        final scrollPosition = _singleScrollPositionOrNull();
        final nearBottom = scrollPosition != null &&
            scrollPosition.hasPixels &&
            scrollPosition.hasContentDimensions &&
            (scrollPosition.pixels - scrollPosition.minScrollExtent).abs() <=
                80;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          if (nearBottom) {
            _silentAbsorbExtentDelta(heightDelta);
          } else {
            _pinScrollToBottomImmediate();
          }
        });
      }
    }
    if (previousHeight != null &&
        (previousHeight - size.height).abs() >= 8 &&
        (globalModel.isChunkedRevealActive(_conversationId()) ||
            _viewportInsert.viewportInsertSlideActive ||
            inMediaSettle)) {
      ChatJitterDiag.logInboundFlow(
        action: 'row_height_changed',
        conv: _conversationId(),
        extras: <String, Object?>{
          'before': previousHeight.toStringAsFixed(1),
          'after': size.height.toStringAsFixed(1),
          'delta': (size.height - previousHeight).toStringAsFixed(1),
          'viewportSlide': _viewportInsert.viewportInsertSlideActive,
          'mediaSettle': inMediaSettle,
        },
        throttleKey: 'row_height_changed',
        minIntervalMs: 100,
      );
    }
    if (globalModel.isSendFlyOverlayPendingForMessage(message)) {
      globalModel.reportSendFlyTargetRect(message, globalRect);
    }
  }

  /// Returns true when newest-side inserts were absorbed into short spacer
  /// (caller must not double-absorb async history delta).
  bool _onMessageListMaybeInserted(
    List<V2TimMessage?> oldList,
    List<V2TimMessage?> newList,
  ) {
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    if (_isInitialHistoryBootstrapping(globalModel)) {
      globalModel.completeInboundProjectionReveal(_conversationId());
      return false;
    }
    // didUpdateWidget runs before child layout: tagMap still identifies the
    // old rows. Capture against that list, not the newly shifted indices.
    // This applies during a drag too; disabling pin alone does not preserve
    // a row's position in a reversed list when new rows are prepended.
    if (!_isFollowingLatest() && oldList.isNotEmpty && newList.isNotEmpty &&
        !globalModel.isUserScrollToBottomInProgress(_conversationId()) &&
        !globalModel.isSearchJumpPending(_conversationId())) {
      final oldHead = oldList.indexWhere((row) => row != null && row.elemType != 11);
      if (oldHead >= 0) {
        final oldKey = _stableMessageListKey(oldList[oldHead], oldHead);
        final shifted = newList.asMap().entries.any((entry) =>
            entry.key > oldHead &&
            _stableMessageListKey(entry.value, entry.key) == oldKey);
        if (shifted) {
          // Grow before a fixed sliver origin, so even a burst larger than the
          // viewport cannot recycle the reading row before it is measured.
          _latchProgressiveNewestBoundary(previousMessages: oldList);
          _beginBufferedRevealAnchor(previousMessages: oldList);
        }
      }
    }
    // 用户正在手动滑动列表时，进入后异步刷新/后台 merge 追加消息不应把列表
    // 拽回底部（否则表现为「刚进入上滑一点又被弹回底部」）。此时保持原位，
    // 新消息由未读提示条呈现，与微信一致。发送消息走独立 force-pin 路径，
    // 不经过这里，因此不受影响。
    if (globalModel.isChatListUserScrolling) {
      globalModel.completeInboundProjectionReveal(_conversationId());
      if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
        _finishContextMenuViewportRestore(globalModel);
      }
      return false;
    }
    final growth = newList.length - oldList.length;
    final oldKeys = oldList
        .asMap()
        .entries
        .map((entry) => _stableMessageListKey(entry.value, entry.key))
        .toSet();
    // 只认「最新侧连续新增」：从列表头往下扫，一碰到旧消息就停。
    // 全表 key 差分会把 tip 重写 / id↔msgID 切换误判成「历史也被插入」，
    // 零高 + list-push 时表现为旧消息连同历史一起再推一遍。
    final insertedMessages = <V2TimMessage>[];
    var insertedTipRows = 0;
    for (var index = 0; index < newList.length; index++) {
      final message = newList[index];
      if (message == null) {
        continue;
      }
      if (message.elemType == 11) {
        final tipKey = _stableMessageListKey(message, index);
        if (!oldKeys.contains(tipKey)) {
          insertedTipRows++;
        }
        continue;
      }
      final key = _stableMessageListKey(message, index);
      if (oldKeys.contains(key)) {
        break;
      }
      insertedMessages.add(message);
    }
    if (insertedMessages.isEmpty) {
      globalModel.completeInboundProjectionReveal(_conversationId());
      if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
        _scheduleContextMenuViewportRestore();
      }
      return false;
    }
    // A bounded latest window removes its oldest suffix while adding a newest
    // prefix. Net length can stay unchanged or shrink; account for that suffix
    // before capping inserts. Only grant trim credit when the old newest real
    // row survives, so a history replacement / identity rewrite is not treated
    // as a live insertion just because every old key disappeared.
    final newKeys = newList.asMap().entries
        .map((entry) => _stableMessageListKey(entry.value, entry.key)).toSet();
    final oldNewestIndex = oldList.indexWhere(
      (message) => message != null && message.elemType != 11,
    );
    var removedTail = 0;
    if (oldNewestIndex >= 0 && newKeys.contains(
      _stableMessageListKey(oldList[oldNewestIndex], oldNewestIndex),
    )) {
      for (var index = oldList.length - 1; index >= 0; index--) {
        if (newKeys.contains(_stableMessageListKey(oldList[index], index))) break;
        removedTail++;
      }
    }
    final insertionBudget = max(0, growth + removedTail);
    if (insertedMessages.length > insertionBudget) {
      ChatJitterDiag.logInboundFlow(
        action: 'list_insert_prefix_capped',
        conv: _conversationId(),
        extras: <String, Object?>{
          'rawInserted': insertedMessages.length,
          'growth': growth,
          'oldLen': oldList.length,
          'newLen': newList.length,
        },
      );
      insertedMessages.removeRange(insertionBudget, insertedMessages.length);
    }
    if (insertedMessages.isEmpty) {
      globalModel.completeInboundProjectionReveal(_conversationId());
      if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
        _scheduleContextMenuViewportRestore();
      }
      return false;
    }
    // Local gallery batches already have stable placeholder geometry. Reveal
    // them together and jump after layout, without the inbound list-push delay.
    if (isNewOutgoingImageBatch(insertedMessages) &&
        !_unreadWindowJumpInFlight &&
        !_isHistoryScrollProtected &&
        !_paginationUi.isLoadingPrevious &&
        _paginationUi.loadPreviousTask == null &&
        _paginationUi.previousLoadInFlightAnchorKey == null &&
        !_shouldCompensateScrollForPagination() &&
        !globalModel.isContextMenuViewportRestoreActive(_conversationId()) &&
        !globalModel.hasPendingScrollRestore(_conversationId()) &&
        !globalModel.isBulkMessageSyncActive(_conversationId()) &&
        !globalModel.isChunkedRevealActive(_conversationId())) {
      _abortViewportInsertSlideForSupersede();
      _endInboundViewportPushPresentation();
      _finishIncomingMessagesWithoutRowReveal(insertedMessages);
      _clearIncomingScrollAnchor(reason: 'outgoing_image_batch');
      _clearShortHistoryAlignmentLatch();
      _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = true;
      _immediateOutgoingImageBatchPin = true;
      _scheduleForcePinScrollToBottom();
      return true;
    }
    final outgoingMediaInserted =
        insertedMessages.where(_isOutgoingMediaMessage).toList(growable: false);
    if (outgoingMediaInserted.isNotEmpty) {
      _beginMediaSettleForMessages(outgoingMediaInserted, holdMs: 1200);
    }
    // 短历史顶部对齐：发送/插入优先吃 spacer（顶部不动），只有装不下才释放并上推。
    var absorbedShortHistoryInsert = false;
    if (_routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 0) {
      if (_absorbInsertedRowsIntoShortHistorySpacer(
        insertedMessages,
        insertedTipRows: insertedTipRows,
      )) {
        absorbedShortHistoryInsert = true;
        ChatJitterDiag.logInboundFlow(
          action: 'short_history_spacer_absorb_insert',
          conv: _conversationId(),
          extras: <String, Object?>{
            'inserted': insertedMessages.length,
            'insertedTipRows': insertedTipRows,
            'spacer':
                _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(1),
          },
        );
      } else {
        _clearShortHistoryAlignmentLatch();
        // 内容已放不进视口：本会话剩余生命周期改贴底，避免下一帧又造回大 spacer。
        _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = true;
      }
    }
    if (absorbedShortHistoryInsert) {
      // 吃 spacer 成功：禁止 list-push / pin，否则会把已顶部锚定的消息再往上推。
      // 估高偏小时多行自消息可能仍溢出视口：下一帧实测后必要时退场并贴底。
      _finishIncomingMessagesWithoutRowReveal(insertedMessages);
      final hasOutgoingSelf = insertedMessages.any((m) => m.isSelf == true);
      if (hasOutgoingSelf) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _breakShortHistoryIfOutgoingOverflowsViewport();
        });
      }
      if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
        _scheduleContextMenuViewportRestore();
      }
      return true;
    }
    final fastForwardInsertedMessages = insertedMessages
        .where(globalModel.consumeInboundFastForwardFlag)
        .toList(growable: false);
    final fastForwardKeys = fastForwardInsertedMessages
        .map((message) => _stableMessageListKey(message, 0))
        .toSet();
    if (fastForwardInsertedMessages.isNotEmpty) {
      for (final message in fastForwardInsertedMessages) {
        globalModel.finishMessageEnterAnimation(message);
      }
      // Fast-forwarded rows intentionally skip animation. Commit them at the
      // latest edge before the retained animated tail starts on the next tick.
      if (!globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _pinScrollToBottomImmediate();
          }
        });
      }
    }
    final animatingMessages = insertedMessages
        .where(
          (message) =>
              !fastForwardKeys.contains(_stableMessageListKey(message, 0)),
        )
        .where(globalModel.isMessageEnterAnimationPending)
        .toList(growable: false);
    final incomingInsertedMessages = insertedMessages
        .where(
          (message) =>
              message.isSelf != true &&
              !fastForwardKeys.contains(_stableMessageListKey(message, 0)),
        )
        .toList(growable: false);
    final outgoingAnimatingMessages = animatingMessages
        .where((message) => message.isSelf == true)
        .toList(growable: false);
    // Local sends share the viewport owner even when Android skips bubble
    // effects. Completed/failed history rows must not replay a send.
    final outgoingTextInserted = insertedMessages
        .where((message) => message.isSelf == true &&
            message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING &&
            !fastForwardKeys.contains(_stableMessageListKey(message, 0)))
        .where(
          (message) => message.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        )
        .toList(growable: false);
    final outgoingNonTextAnimating = outgoingAnimatingMessages
        .where(
          (message) => message.elemType != MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        )
        .toList(growable: false);
    final incomingAnimatingMessages = animatingMessages
        .where((message) => message.isSelf != true)
        .toList(growable: false);
    final position = _singleScrollPositionOrNull();
    ChatJitterDiag.logInboundFlow(
      action: 'list_insert_classified',
      conv: _conversationId(),
      extras: <String, Object?>{
        'oldLen': oldList.length,
        'newLen': newList.length,
        'inserted': insertedMessages.length,
        'incoming': incomingInsertedMessages.length,
        'outgoingAnimating': outgoingAnimatingMessages.length,
        'animating': incomingAnimatingMessages.length,
        'growth': growth,
        'insertedTipRows': insertedTipRows,
        'untrackedGrowth': growth - insertedMessages.length - insertedTipRows,
        'fastForward': fastForwardInsertedMessages.length,
        'queue': globalModel.pendingInboundProjectionCount(_conversationId()),
        'waiting': globalModel.isInboundProjectionRevealWaiting(
          _conversationId(),
        ),
        'logicalPosition':
            globalModel.getMessageListPosition(_conversationId()).name,
        'pixels': position?.hasPixels == true
            ? position!.pixels.toStringAsFixed(1)
            : 'n/a',
        'minExtent': position?.hasContentDimensions == true
            ? position!.minScrollExtent.toStringAsFixed(1)
            : 'n/a',
      },
    );
    if (incomingInsertedMessages.isEmpty &&
        outgoingAnimatingMessages.isEmpty &&
        _viewportInsert.activeRowRevealMessages.isEmpty &&
        !_viewportInsert.viewportInsertSlideActive &&
        !(_viewportInsert.rowRevealController?.isAnimating ?? false) &&
        globalModel.isInboundProjectionRevealWaiting(_conversationId())) {
      globalModel.completeInboundProjectionReveal(_conversationId());
    }
    if (oldList.isEmpty && newList.isNotEmpty) {
      _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
      return false;
    }
    if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      // The scroll physics owns this one geometry transaction. Commit all
      // buffered rows at full height now; row reveal/list-push would continue
      // changing extent after the menu disappears and reintroduce a wobble.
      _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
      _clearIncomingScrollAnchor(reason: 'context_menu_viewport_restore');
      _scheduleContextMenuViewportRestore();
      return false;
    }
    // 自动 list-push 本身会暂时把 pixels 推离 minExtent；这不是用户在读历史。
    // 若此时锁定阅读锚点，restore 会逐帧把 ticker 拉回旧 offset，形成来回抖动。
    final inboundPushOwnsViewport =
        _viewportInsert.continuousViewportPushActive ||
            _viewportInsert.viewportInsertSlideActive ||
            globalModel.isInboundPresentationBottomLocked(_conversationId());
    if (inboundPushOwnsViewport) {
      _clearIncomingScrollAnchor(reason: 'inbound_push_owns_viewport');
    }
    // 上拉分页 prepend 必须优先于「读历史锚点锁」。否则会把 offset 拉回插入前，
    // 与 HistoryPaginationScrollPhysics / 分页 restore 对打，表现为历史加载完朝新消息跳一下。
    if (_paginationUi.isLoadingPrevious ||
        _paginationUi.loadPreviousTask != null ||
        _paginationUi.previousLoadInFlightAnchorKey != null ||
        _shouldCompensateScrollForPagination()) {
      _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
      return false;
    }
    final frozenIncoming = !_isFollowingLatest();
    if (globalModel.isAttachingBufferedTowardLatest) {
      final attachingInserted = incomingInsertedMessages
          .where(widget.model.isMessageInHistoryReadingWindow)
          .toList(growable: false);
      _armNewestInsertRoom(attachingInserted);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _chatGlobalModel?.endAttachingBufferedTowardLatest();
      });
    }
    if (frozenIncoming && incomingInsertedMessages.isNotEmpty) {
      final leakedIncoming = incomingInsertedMessages
          .where((message) => !widget.model.isMessageInHistoryReadingWindow(message))
          .toList(growable: false);
      ChatJitterDiag.logReadingHistoryIncoming(
        action: leakedIncoming.isNotEmpty
            ? 'freeze_violation'
            : 'frozen_ignore_incoming',
        conv: _conversationId(),
        extras: <String, Object?>{
          'oldLen': oldList.length,
          'newLen': newList.length,
          'incoming': incomingInsertedMessages.length,
          'leaked': leakedIncoming.length,
          'userScrolling': globalModel.isChatListUserScrolling,
        },
      );
      _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
    }
    final liveIncomingInsertedMessages = frozenIncoming
        ? const <V2TimMessage>[]
        : incomingInsertedMessages;
    final wechatListPush = _useWechatListPushTranslate(globalModel);
    // Receive and local send share one viewport owner, without a bubble tween.
    var listPushMessages = <V2TimMessage>[
      ...liveIncomingInsertedMessages,
      if (wechatListPush) ...outgoingNonTextAnimating,
      if (wechatListPush) ...outgoingTextInserted,
    ];
    // 同一帧多条必须整批进入同一个零高事务。以前只动画最新 1 条、其余直接
    // 全高落位；快速收消息时这些 overflow 会先顶动历史，再由最新气泡上推。
    // atomic 路径会按整批实测高度做一次补偿，因此不会让历史随批次跳动。
    if (listPushMessages.length > 1) {
      ChatJitterDiag.logInboundFlow(
        action: 'list_push_batch',
        conv: _conversationId(),
        extras: <String, Object?>{
          'animated': listPushMessages.length,
          'queuedBehindActive': _viewportInsert.viewportInsertSlideActive,
        },
      );
    }
    if (wechatListPush &&
        (listPushMessages.isNotEmpty || outgoingMediaInserted.isNotEmpty)) {
      final pushMessages = <String, V2TimMessage>{
        for (final message in [...listPushMessages, ...outgoingMediaInserted])
          _stableMessageListKey(message, 0): message,
      }.values.toList(growable: false);
      final canReveal = _shouldRunRowReveal(forLiveListPush: true);
      final following = _isFollowingLatest();
      final chunked = globalModel.isChunkedRevealActive(_conversationId());
      final bulk = _chatGlobalModel?.isBulkMessageSyncActive(_conversationId()) ??
          false;
      final insertPath = canReveal && following
          ? 'list_push'
          : (!_isHistoryScrollProtected && following && !chunked && !bulk)
              ? 'pin'
              : 'hold';
      String? holdReason;
      if (insertPath == 'hold') {
        if (!following) {
          holdReason = 'not_following';
        } else if (_isHistoryScrollProtected) {
          holdReason = 'history_protected';
        } else if (chunked) {
          holdReason = 'chunked';
        } else if (bulk) {
          holdReason = 'bulk_sync';
        } else {
          holdReason = 'reveal_blocked';
        }
      }
      ChatJitterDiag.logFollowingLatest(
        action: 'list_insert_decision',
        conv: _conversationId(),
        extras: <String, Object?>{
          'path': insertPath,
          'canReveal': canReveal,
          'following': following,
          'historyProtected': _isHistoryScrollProtected,
          'pushCount': pushMessages.length,
          if (holdReason != null) 'holdReason': holdReason,
          ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
        },
      );
      if (canReveal && following) {
        _startContinuousViewportInsertPush(pushMessages);
      } else if (!_isHistoryScrollProtected &&
          following &&
          !globalModel.isChunkedRevealActive(_conversationId()) &&
          !(_chatGlobalModel?.isBulkMessageSyncActive(_conversationId()) ??
              false)) {
        // 发送路径里 suppressOutgoingPinScroll 只挡 soft pin，不该吞掉落位；
        // force-pin 会单独处理贴底。
        _finishIncomingMessagesWithoutRowReveal(pushMessages);
        if (!(_chatGlobalModel?.shouldSuppressOutgoingPinScroll() ?? false)) {
          _schedulePinScrollToBottom();
        }
      } else {
        _finishIncomingMessagesWithoutRowReveal(pushMessages);
      }
    } else if (liveIncomingInsertedMessages.isNotEmpty &&
        _shouldRunRowReveal() &&
        _isFollowingLatest()) {
      ChatJitterDiag.logFollowingLatest(
        action: 'list_insert_decision',
        conv: _conversationId(),
        extras: <String, Object?>{
          'path': incomingAnimatingMessages.isNotEmpty
              ? 'row_reveal'
              : 'pin',
          'following': true,
          'pushCount': incomingInsertedMessages.length,
          ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
        },
      );
      if (incomingAnimatingMessages.isNotEmpty) {
        _startRowRevealTransaction(incomingAnimatingMessages);
      } else {
        _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
        _schedulePinScrollToBottom();
      }
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
    } else if (!_isHistoryScrollProtected &&
        !(_chatGlobalModel?.shouldSuppressOutgoingPinScroll() ?? false) &&
        _isFollowingLatest() &&
        !globalModel.isChunkedRevealActive(_conversationId()) &&
        !(_chatGlobalModel?.isBulkMessageSyncActive(_conversationId()) ??
            false)) {
      ChatJitterDiag.logFollowingLatest(
        action: 'list_insert_decision',
        conv: _conversationId(),
        extras: <String, Object?>{
          'path': 'pin',
          'following': true,
          'pushCount': incomingInsertedMessages.length,
          ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
        },
      );
      _finishIncomingMessagesWithoutRowReveal(incomingInsertedMessages);
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
      _schedulePinScrollToBottom();
    } else {
      ChatJitterDiag.logFollowingLatest(
        action: 'list_insert_decision',
        conv: _conversationId(),
        extras: <String, Object?>{
          'path': 'hold',
          'holdReason': !_isFollowingLatest()
              ? 'not_following'
              : (_isHistoryScrollProtected
                  ? 'history_protected'
                  : 'other'),
          'following': _isFollowingLatest(),
          'historyProtected': _isHistoryScrollProtected,
          'pushCount': incomingInsertedMessages.length,
          ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
        },
      );
      if (!_isFollowingLatest() &&
          !globalModel.isAttachingBufferedTowardLatest &&
          liveIncomingInsertedMessages.isNotEmpty) {
        ChatJitterDiag.logReadingHistoryIncoming(
          action: 'freeze_violation',
          conv: _conversationId(),
          extras: <String, Object?>{
            'pushCount': liveIncomingInsertedMessages.length,
          },
        );
      }
      _finishIncomingMessagesWithoutRowReveal(liveIncomingInsertedMessages);
      _finishIncomingMessagesWithoutRowReveal(outgoingAnimatingMessages);
    }
    if (_isReadingHistory() && !_shouldRunRowReveal()) {
      _logReadingHistoryIncoming(
        'pin_blocked',
        globalModel: globalModel,
        extras: <String, Object?>{
          'historyProtected': _isHistoryScrollProtected,
          'suppressOutgoingPin':
              _chatGlobalModel?.shouldSuppressOutgoingPinScroll() ?? false,
        },
      );
    }
    _scheduleOffsetJumpProbe();
    return false;
  }

  bool _shouldPinScrollToBottom(TUIChatGlobalModel globalModel) {
    final reason = _pinScrollBlockReason(globalModel);
    if (reason == null) {
      return true;
    }
    ChatJitterDiag.logFollowingLatest(
      action: 'pin_refused',
      conv: _conversationId(),
      extras: <String, Object?>{
        'reason': reason,
        ...globalModel.stickToLatestDiagSnapshot(_conversationId()),
      },
      throttleKey: 'pin_refused',
      minIntervalMs: 250,
    );
    return false;
  }

  String? _pinScrollBlockReason(TUIChatGlobalModel globalModel) {
    if (_mayUseShortHistoryTopAlignment()) {
      return 'short_history_top';
    }
    // 用户正在手动滑动时不做滚底补偿（list-push 补偿阈值 80px 会把「上滑一点」
    // 的用户拽回底部）。发送消息的 force-pin 不经过这里，不受影响。
    if (globalModel.isChatListUserScrolling) {
      return 'user_scrolling';
    }
    if (_isSearchJumpStabilizing) {
      return 'search_jump';
    }
    if (_paginationUi.isLoadingLatest) {
      return 'loading_latest';
    }
    if (widget.model.haveMoreLatestData) {
      return 'have_more_latest';
    }
    if (globalModel.memoryWindowMissingNewer(_conversationId())) {
      return 'memory_missing_newer';
    }
    if (globalModel.hasDurableHistoryDeferred(_conversationId())) {
      return 'durable_deferred';
    }
    if (globalModel.isWalletOverlayOpen) {
      return 'wallet_overlay';
    }
    if (globalModel.isMediaPickerOverlayOpen) {
      return 'picker_overlay';
    }
    if (globalModel.isMediaPreviewOverlayOpen) {
      return 'preview_overlay';
    }
    if (globalModel.isMessageContextMenuOverlayOpen) {
      return 'context_menu';
    }
    if (globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      return 'context_menu_restore';
    }
    if (globalModel.isRestoringScrollAfterMediaPreview) {
      return 'preview_restore';
    }
    final convId = _conversationId();
    if (globalModel.hasPendingScrollRestore(convId)) {
      return 'pending_scroll_restore';
    }
    if (!_isFollowingLatest()) {
      return 'not_following';
    }
    // awayTwoScreen 是视口派生量，跟随最新端时不能用它挡 pin；离底保护由下面
    // 的 24px 物理距离兜底。notShowLatest 代表窗口不含最新端，必须继续拦。
    if (globalModel.getMessageListPosition(convId) ==
        HistoryMessagePosition.notShowLatest) {
      return 'logical_notShowLatest';
    }
    if (_deferUnreadCenterPartition) {
      return 'unread_center_defer';
    }
    if (!globalModel.isInboundViewportPushActive(convId) &&
        !globalModel.isUserScrollToBottomInProgress(convId)) {
      final position = _singleScrollPositionOrNull();
      if (position != null &&
          position.hasPixels &&
          position.hasContentDimensions &&
          position.pixels - position.minScrollExtent >
              (globalModel.chatConfig.desktopStickToLatestEnabled
                  ? 80.0
                  : _followingLatestEpsilonPx)) {
        return globalModel.chatConfig.desktopStickToLatestEnabled
            ? 'physically_away_80'
            : 'physically_away_24';
      }
    }
    return null;
  }

  /// 进页布局冻结窗：覆盖 hydrate + 首轮 loadLatest 常见耗时，避免 spacer/loading 抖。
  bool get _isInitialRouteSettleWindow =>
      DateTime.now().millisecondsSinceEpoch - _createdAtMs < 2500;

  void _schedulePinScrollToBottomOnUnreadEntry({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pinScrollToBottomOnUnreadEntry(attempt: attempt);
    });
  }

  void _pinScrollToBottomOnUnreadEntry({int attempt = 0}) {
    const maxAttempts = 12;
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final convId = _conversationId();
    if (globalModel.unreadCountForTongue <= 0 ||
        globalModel.getMessageListPosition(convId) !=
            HistoryMessagePosition.bottom ||
        _firstUnreadAnchorJumped) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      if (attempt < maxAttempts) {
        _schedulePinScrollToBottomOnUnreadEntry(attempt: attempt + 1);
      }
      return;
    }
    const pinThreshold = 80.0;
    final target = position.minScrollExtent;
    if ((position.pixels - target).abs() > 0.5) {
      _geomJumpTo(target, reason: 'pin_unread_entry');
    }
    globalModel.setMessageListPosition(
      convId,
      HistoryMessagePosition.bottom,
      notify: false,
    );
    final frozenUnread = globalModel.unreadCountForTongue;
    if (frozenUnread > 0) {
      globalModel.setUnreadTongueMetrics(
        conversationID: convId,
        remaining: frozenUnread,
        below: false,
        notify: true,
      );
    }
    if (attempt < maxAttempts - 1 && position.pixels > target + pinThreshold) {
      _schedulePinScrollToBottomOnUnreadEntry(attempt: attempt + 1);
    }
  }

  void _schedulePinScrollToBottom({int attempt = 0}) {
    if (_isHistoryScrollProtected) {
      return;
    }
    if (attempt == 0) {
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        _pinScrollToBottomImmediate();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pinScrollToBottomIfNeeded(attempt: attempt);
    });
  }

  void _cancelForcePinScroll() {
    _forcePinGeneration++;
    _forcePinIgnoreInsertWindows = false;
    _immediateOutgoingImageBatchPin = false;
  }

  void _scheduleForcePinScrollToBottom({
    int attempt = 0,
    int? generation,
    bool ignoreInsertWindows = false,
  }) {
    if (_unreadWindowJumpInFlight) {
      _cancelForcePinScroll();
      return;
    }
    final gen = generation ?? ++_forcePinGeneration;
    if (generation == null) {
      _forcePinIgnoreInsertWindows = ignoreInsertWindows;
    }
    // 上拉历史保护窗口内不要直接放弃：延后重试，保证发送/点输入框仍能回底。
    // An explicit send supersedes the passive 520ms history cooldown. Keep
    // waiting for a real pagination transaction; gestures are checked below.
    final waitForHistory = _immediateOutgoingImageBatchPin
        ? (_paginationUi.isLoadingPrevious ||
            _paginationUi.ignoreScrollLoadPrevious > 0)
        : _isHistoryScrollProtected;
    if (waitForHistory) {
      final maxAttempts = _immediateOutgoingImageBatchPin
          ? 32
          : (_isInitialRouteSettleWindow ? 4 : 8);
      if (attempt < maxAttempts) {
        Future<void>.delayed(const Duration(milliseconds: 48), () {
          if (!mounted || gen != _forcePinGeneration) {
            return;
          }
          _scheduleForcePinScrollToBottom(
            attempt: attempt + 1,
            generation: gen,
          );
        });
      }
      return;
    }
    if (_isRouteBackGestureInProgress() ||
        (_chatGlobalModel?.isChatListUserScrolling ?? false)) {
      _cancelForcePinScroll();
      return;
    }
    if (attempt == 0 && !_immediateOutgoingImageBatchPin) {
      scheduleMicrotask(() {
        if (!mounted || gen != _forcePinGeneration) {
          return;
        }
        _forcePinScrollToBottomIfNeeded(attempt: attempt, generation: gen);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _forcePinGeneration) {
        return;
      }
      _forcePinScrollToBottomIfNeeded(attempt: attempt, generation: gen);
    });
    if (_immediateOutgoingImageBatchPin) {
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _forcePinScrollToBottomIfNeeded({
    int attempt = 0,
    required int generation,
  }) {
    if (generation != _forcePinGeneration) {
      return;
    }
    if (_unreadWindowJumpInFlight) {
      _cancelForcePinScroll();
      return;
    }
    // 进入本方法即 force-pin 意图（软贴底走 _pinScrollToBottomIfNeeded）。
    // 短历史顶部对齐期间必须先退场再贴底，否则发送多行后最新气泡不可见。
    if (_routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 0) {
      _clearShortHistoryAlignmentLatch();
      _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = true;
    }
    if (!_forcePinIgnoreInsertWindows &&
        !_immediateOutgoingImageBatchPin &&
        _viewportInsert.viewportInsertSlideActive) {
      // list-push 拥有本轮上推：结束后再视需要补一次贴底，勿直接丢弃 force-pin。
      final maxAttempts = _isInitialRouteSettleWindow ? 4 : 8;
      if (attempt < maxAttempts) {
        Future<void>.delayed(const Duration(milliseconds: 48), () {
          if (!mounted || generation != _forcePinGeneration) {
            return;
          }
          _scheduleForcePinScrollToBottom(
            attempt: attempt + 1,
            generation: generation,
          );
        });
      }
      return;
    }
    if (!_forcePinIgnoreInsertWindows &&
        !_immediateOutgoingImageBatchPin &&
        _viewportInsert.hasAnyMediaSettling()) {
      // 图片/视频首帧 layout、decode 期间勿 force-pin，与 silentAbsorb 对打会抖。
      // 出站媒体稳定窗最长 1200ms；24 * 64ms = 1536ms，必须覆盖完整
      // 稳定窗。旧值 6/16 次会在 384/1024ms 提前耗尽，pin seq 又已消费，
      // 导致相册返回后新图片留在视口外，必须手动滑动才能看到。
      const maxAttempts = 24;
      if (attempt < maxAttempts) {
        Future<void>.delayed(const Duration(milliseconds: 64), () {
          if (!mounted || generation != _forcePinGeneration) {
            return;
          }
          _scheduleForcePinScrollToBottom(
            attempt: attempt + 1,
            generation: generation,
          );
        });
      }
      return;
    }
    if (!_forcePinIgnoreInsertWindows &&
        !_immediateOutgoingImageBatchPin &&
        _viewportInsert.continuousViewportPushActive) {
      final maxAttempts = _isInitialRouteSettleWindow ? 4 : 8;
      if (attempt < maxAttempts) {
        Future<void>.delayed(const Duration(milliseconds: 48), () {
          if (!mounted || generation != _forcePinGeneration) {
            return;
          }
          _scheduleForcePinScrollToBottom(
            attempt: attempt + 1,
            generation: generation,
          );
        });
      }
      return;
    }
    if (_isRouteBackGestureInProgress() ||
        (_chatGlobalModel?.isChatListUserScrolling ?? false)) {
      _cancelForcePinScroll();
      return;
    }
    if (!_forcePinIgnoreInsertWindows &&
        !_immediateOutgoingImageBatchPin &&
        _isViewportInsertSettling()) {
      final delayMs = _viewportInsertSettleRemainingMs();
      Future<void>.delayed(Duration(milliseconds: max(delayMs, 16)), () {
        if (!mounted || generation != _forcePinGeneration) {
          return;
        }
        _scheduleForcePinScrollToBottom(
          attempt: attempt,
          generation: generation,
        );
      });
      return;
    }
    final maxAttempts = _isInitialRouteSettleWindow ? 4 : 8;
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    if (globalModel.isChatListUserScrolling) {
      _cancelForcePinScroll();
      return;
    }
    if (globalModel.isUserScrollToBottomInProgress(_conversationId())) {
      return;
    }
    if (globalModel.isWalletOverlayOpen ||
        (!_forcePinIgnoreInsertWindows &&
            globalModel.isMediaPickerOverlayOpen) ||
        globalModel.isMediaPreviewOverlayOpen ||
        globalModel.isMessageContextMenuOverlayOpen ||
        globalModel.isRestoringScrollAfterMediaPreview) {
      return;
    }
    final convId = _conversationId();
    if (globalModel.hasPendingScrollRestore(convId)) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null) {
      if (attempt < maxAttempts) {
        _scheduleForcePinScrollToBottom(
          attempt: attempt + 1,
          generation: generation,
        );
      }
      return;
    }
    if (!position.hasPixels || !position.hasContentDimensions) {
      if (attempt < maxAttempts) {
        _scheduleForcePinScrollToBottom(
          attempt: attempt + 1,
          generation: generation,
        );
      }
      return;
    }

    final target = position.minScrollExtent;
    final awayFromBottom = (position.pixels - target).abs() > 0.5;
    // Already near bottom during outgoing suppress: stop chasing frames.
    if (!awayFromBottom && globalModel.shouldSuppressOutgoingPinScroll()) {
      _immediateOutgoingImageBatchPin = false;
      return;
    }
    if (awayFromBottom) {
      ChatJitterDiag.logScroll(
        reason: 'force_pin_bottom_a$attempt',
        pixels: position.pixels,
        minExtent: target,
        maxExtent: position.maxScrollExtent,
      );
      _scrollToBottomTarget(
        target,
        globalModel,
        immediate: _immediateOutgoingImageBatchPin,
      );
    }
    globalModel.setMessageListPosition(
      convId,
      HistoryMessagePosition.bottom,
      notify: false,
    );

    // Only keep chasing bottom while layout is still drifting. Unconditional
    // 8-frame retries after list-push often re-nudge settled content.
    if (attempt < maxAttempts - 1 && awayFromBottom) {
      _scheduleForcePinScrollToBottom(
        attempt: attempt + 1,
        generation: generation,
      );
    } else {
      _immediateOutgoingImageBatchPin = false;
    }
  }

  void _pinScrollToBottomIfNeeded({int attempt = 0}) {
    if (_viewportInsert.viewportInsertSlideActive) {
      return;
    }
    if (_isRouteBackGestureInProgress() ||
        (_chatGlobalModel?.isChatListUserScrolling ?? false)) {
      return;
    }
    if (_isViewportInsertSettling()) {
      final delayMs = _viewportInsertSettleRemainingMs();
      Future<void>.delayed(Duration(milliseconds: max(delayMs, 16)), () {
        if (!mounted) {
          return;
        }
        _schedulePinScrollToBottom(attempt: attempt);
      });
      return;
    }
    final maxAttempts = _isInitialRouteSettleWindow ? 3 : 8;
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    if (globalModel.isBulkMessageSyncActive(_conversationId())) {
      return;
    }
    if (globalModel.isUserScrollToBottomInProgress(_conversationId())) {
      return;
    }
    if (!_shouldPinScrollToBottom(globalModel)) {
      return;
    }
    if (KeyboardViewportTransitionCoordinator.active?.isAnimating == true) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null) {
      if (attempt < maxAttempts) {
        _schedulePinScrollToBottom(attempt: attempt + 1);
      }
      return;
    }
    if (!position.hasPixels || !position.hasContentDimensions) {
      if (attempt < maxAttempts) {
        _schedulePinScrollToBottom(attempt: attempt + 1);
      }
      return;
    }

    const bottomEpsilon = 24.0;
    final nearBottom =
        position.pixels <= position.minScrollExtent + bottomEpsilon;
    final contentFitsViewport =
        position.maxScrollExtent <= position.minScrollExtent + bottomEpsilon;

    if (nearBottom || contentFitsViewport) {
      final target = position.minScrollExtent;
      if ((position.pixels - target).abs() > 0.5) {
        _scrollToBottomTarget(target, globalModel);
      }
      globalModel.setMessageListPosition(
        _conversationId(),
        HistoryMessagePosition.bottom,
        notify: false,
      );
    }

    if (attempt < maxAttempts - 1 && (nearBottom || contentFitsViewport)) {
      _schedulePinScrollToBottom(attempt: attempt + 1);
    }
  }

  void _scrollToBottomTarget(
    double target,
    TUIChatGlobalModel globalModel, {
    bool immediate = false,
  }) {
    // 用户手指优先：异步媒体布局、发送回调或旧的 post-frame pin 可能在
    // 手势已经开始后才到达。此时再 jump/animate 会抢夺 ScrollPosition，
    // 表现为列表卡住、拖动方向反转或松手后又被拉回底部。调用方大多有
    // 自己的保护，但这里是所有贴底路径的最后一道闸门。
    if (globalModel.isChatListUserScrolling || _userScrollGestureActive) {
      return;
    }
    if (globalModel.isMessageContextMenuOverlayOpen ||
        globalModel.isContextMenuViewportRestoreActive(_conversationId())) {
      return;
    }
    // Open / just-revealed: always jump. Smooth follow is for live inbound only.
    if (immediate ||
        !_historyOpenRevealPainted ||
        _isInitialRouteSettleWindow ||
        _isPostRevealMicroSuppressWindow) {
      _geomJumpTo(target, reason: 'scroll_to_bottom_instant_open');
      return;
    }
    final useSmooth = globalModel.chatConfig.inboundScrollFollowEnabled &&
        globalModel.chatConfig.inboundScrollFollowMode ==
            InboundScrollFollowMode.smooth;
    if (useSmooth) {
      unawaited(
        _autoScrollController.animateTo(
          target,
          duration: Duration(
            milliseconds: globalModel.chatConfig.inboundScrollFollowDurationMs,
          ),
          curve: Curves.easeInOut,
        ),
      );
      return;
    }
    _geomJumpTo(target, reason: 'scroll_to_bottom_target');
  }

  void _startRowRevealTransaction(List<V2TimMessage> messages) {
    final controller = _viewportInsert.rowRevealController;
    if (controller == null || messages.isEmpty) {
      _finishIncomingMessagesWithoutRowReveal(messages);
      return;
    }
    if (controller.isAnimating ||
        _viewportInsert.activeRowRevealMessages.isNotEmpty) {
      _finishActiveRowRevealImmediately();
    }
    final generation = ++_viewportInsert.rowRevealGeneration;
    _viewportInsert.activeRowRevealMessages.clear();
    for (final message in messages) {
      _viewportInsert.activeRowRevealMessages[_stableMessageListKey(
        message,
        0,
      )] = message;
    }
    final globalModel = _chatGlobalModel ??
        Provider.of<TUIChatGlobalModel>(context, listen: false);
    final pendingCount = globalModel.pendingInboundProjectionCount(
      _conversationId(),
    );
    final durationMs = _isWechatInsertAnimationStyle(globalModel)
        ? 240
        : switch (pendingCount) {
            >= 40 => 200,
            >= 16 => 280,
            >= 6 => 360,
            >= 2 => 440,
            _ => 520,
          };
    controller.duration = Duration(milliseconds: durationMs);
    controller.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _viewportInsert.rowRevealGeneration ||
          _viewportInsert.activeRowRevealMessages.isEmpty ||
          controller.isCompleted) {
        return;
      }
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.forward(from: 0);
    });
  }

  void _finishIncomingMessagesWithoutRowReveal(List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return;
    }
    final globalModel = _chatGlobalModel ??
        (mounted
            ? Provider.of<TUIChatGlobalModel>(context, listen: false)
            : null);
    if (globalModel == null) {
      return;
    }
    for (final message in messages) {
      final key = _stableMessageListKey(message, 0);
      _viewportInsert.queuedViewportInsertMessages.remove(key);
      _viewportInsert.rowRevealFullExtentByKey.remove(key);
      globalModel.finishMessageEnterAnimation(message);
    }
    globalModel.completeInboundProjectionReveal(_conversationId());
  }

  void _finishActiveRowRevealImmediately() {
    final controller = _viewportInsert.rowRevealController;
    if (controller == null || _viewportInsert.activeRowRevealMessages.isEmpty) {
      return;
    }
    if (controller.value < 1) {
      controller.stop();
      controller.value = 1;
    }
    _completeRowRevealTransaction();
  }

  void _completeRowRevealTransaction() {
    if (_viewportInsert.activeRowRevealMessages.isEmpty) {
      return;
    }
    final messages = List<V2TimMessage>.from(
      _viewportInsert.activeRowRevealMessages.values,
    );
    _viewportInsert.activeRowRevealMessages.clear();
    final globalModel = _chatGlobalModel ??
        Provider.of<TUIChatGlobalModel>(context, listen: false);
    for (final message in messages) {
      globalModel.finishMessageEnterAnimation(message);
    }
    globalModel.completeInboundProjectionReveal(_conversationId());
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleRouteScrollRestore(List<V2TimMessage?> renderList) {
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    if (!globalModel.isRestoringScrollAfterMediaPreview) {
      _routeScroll.routeRestoreScheduled = false;
      return;
    }
    final version = globalModel.mediaPreviewRestoreVersion;
    if (version <= 0) {
      return;
    }
    if (_routeScroll.lastRouteRestoreVersion != version) {
      _routeScroll.lastRouteRestoreVersion = version;
      _routeScroll.routeRestoreAttempt = 0;
      _routeScroll.routeRestoreScheduled = false;
    }
    if (_routeScroll.routeRestoreAttempt >= 24) {
      globalModel.finishScrollAfterMediaPreview(_conversationId());
      _routeScroll.routeRestoreScheduled = false;
      return;
    }
    if (_routeScroll.routeRestoreScheduled) {
      return;
    }
    _routeScroll.routeRestoreScheduled = true;
    final snapshot = List<V2TimMessage?>.from(renderList);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeScroll.routeRestoreScheduled = false;
      if (!mounted) {
        return;
      }
      _restoreRouteScroll(snapshot, version);
    });
  }

  Future<void> _restoreRouteScroll(
    List<V2TimMessage?> renderList,
    int version,
  ) async {
    if (!mounted || version != _routeScroll.lastRouteRestoreVersion) {
      return;
    }
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final convId = _conversationId();
    var restored = false;
    final offset = globalModel.getScrollRestoreOffset(convId);
    final offsetPosition = _singleScrollPositionOrNull();
    if (offset != null && offsetPosition != null) {
      final position = offsetPosition;
      if (position.hasPixels && position.hasContentDimensions) {
        final target = offset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((position.pixels - target).abs() > 0.5) {
          _geomJumpTo(
            target.toDouble(),
            reason: 'jump__scheduleRouteScrollRestore',
          );
        }
        restored = true;
      }
    }
    if (!restored) {
      // 不要用 scrollToIndex(middle) 兜底：会把入口图片气泡拽到视口正中。
      // 预览路由 maintainState，列表位姿应保持；只重试 offset jump，否则就地解锁。
      _routeScroll.routeRestoreAttempt++;
      if (_routeScroll.routeRestoreAttempt < 3 && offset != null) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) {
            _scheduleRouteScrollRestore(renderList);
          }
        });
        return;
      }
      globalModel.finishScrollAfterMediaPreview(convId);
      _routeScroll.routeRestoreScheduled = false;
      return;
    }
    globalModel.finishScrollAfterMediaPreview(convId);
    _routeScroll.routeRestoreAttempt = 0;
    _routeScroll.routeRestoreScheduled = false;
  }

  String _messageIdentity(V2TimMessage message) {
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      return msgID;
    }
    final id = message.id;
    if (id != null && id.toString().isNotEmpty) {
      return id.toString();
    }
    return '';
  }

  RenderBox? _viewportRenderBoxFor(BuildContext tagContext) {
    final scrollable = Scrollable.maybeOf(tagContext);
    final viewportRenderObject = scrollable?.context.findRenderObject();
    if (viewportRenderObject is! RenderBox ||
        !viewportRenderObject.attached ||
        !viewportRenderObject.hasSize ||
        _renderObjectNeedsLayout(viewportRenderObject)) {
      return null;
    }
    return viewportRenderObject;
  }

  int? _globalIndexForMessageIdentity(String messageId) {
    if (messageId.isEmpty) {
      return null;
    }
    final mapped = _globalMessageIdentityIndexMap[messageId];
    if (mapped != null) {
      return mapped;
    }
    final messageList = _currentVisibleMessageList();
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (message == null || message.elemType == 11) {
        continue;
      }
      if (_messageIdentity(message) == messageId) {
        return i;
      }
    }
    return null;
  }

  int? _globalIndexForPreviousLoadAnchor(_PreviousLoadAnchor anchor) {
    final msgID = anchor.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      final byIdentity = _globalIndexForMessageIdentity(msgID);
      if (byIdentity != null) {
        return byIdentity;
      }
    }
    final seq = anchor.seq;
    if (seq == null || seq <= 0) {
      return null;
    }
    final messageList = _currentVisibleMessageList();
    for (var i = 0; i < messageList.length; i++) {
      if (int.tryParse(messageList[i]?.seq?.trim() ?? '') == seq) {
        return i;
      }
    }
    return null;
  }

  _PaginationViewportAnchor? _capturePaginationViewportAnchor(
    _PreviousLoadAnchor anchor,
  ) {
    final globalIndex = _globalIndexForPreviousLoadAnchor(anchor);
    if (globalIndex == null) {
      return _captureVisiblePaginationViewportAnchor();
    }
    final tagContext = _autoScrollController.tagMap[-globalIndex]?.context;
    final scrollable =
        tagContext == null ? null : Scrollable.maybeOf(tagContext);
    final target = tagContext?.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (target is! RenderBox ||
        viewport is! RenderBox ||
        !target.attached ||
        !viewport.attached ||
        !target.hasSize ||
        !viewport.hasSize ||
        _renderObjectNeedsLayout(target) ||
        _renderObjectNeedsLayout(viewport)) {
      return _captureVisiblePaginationViewportAnchor();
    }
    final viewportTop =
        target.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final captured = _PaginationViewportAnchor(
      msgID: anchor.msgID?.trim(),
      seq: anchor.seq,
      viewportTop: viewportTop,
    );
    ChatHistoryTrace.log(
      'load_previous_viewport_anchor_capture',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'msgID': captured.msgID,
        'seq': captured.seq,
        'globalIndex': globalIndex,
        'viewportTop': viewportTop.toStringAsFixed(1),
      },
    );
    return captured;
  }

  /// Captures a mounted row near the current viewport when the pagination
  /// boundary itself is outside the sliver cache. This keeps the user's
  /// visible content stable even when the boundary row was just evicted.
  _PaginationViewportAnchor? _captureVisiblePaginationViewportAnchor({
    List<V2TimMessage?>? messages,
  }) {
    final messageList = messages ?? _currentVisibleMessageList();
    _PaginationViewportAnchor? best;
    var bestDistance = double.infinity;
    for (final entry in _autoScrollController.tagMap.entries) {
      final globalIndex = -entry.key;
      if (globalIndex < 0 || globalIndex >= messageList.length) {
        continue;
      }
      final tagContext = entry.value.context;
      final target = tagContext?.findRenderObject();
      final viewport =
          tagContext == null ? null : _viewportRenderBoxFor(tagContext);
      if (target is! RenderBox ||
          viewport is! RenderBox ||
          !target.attached ||
          !viewport.attached ||
          !target.hasSize ||
          !viewport.hasSize ||
          _renderObjectNeedsLayout(target) ||
          _renderObjectNeedsLayout(viewport)) {
        continue;
      }
      final top = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + target.size.height;
      if (bottom < -1 || top > viewport.size.height + 1) {
        continue;
      }
      final distance = (top - viewport.size.height / 3).abs();
      if (distance >= bestDistance) {
        continue;
      }
      final message = messageList[globalIndex];
      if (message == null ||
          message.elemType == 11 ||
          ((message.msgID?.trim().isEmpty ?? true) &&
              (int.tryParse(message.seq?.trim() ?? '') ?? 0) <= 0)) {
        continue;
      }
      if (entry.value.widget.key !=
          ValueKey<String>(_stableMessageListKey(message, globalIndex)))
        continue;
      bestDistance = distance;
      best = _PaginationViewportAnchor(
        msgID: message.msgID?.trim(),
        seq: int.tryParse(message.seq?.trim() ?? ''),
        viewportTop: top,
      );
    }
    if (best != null) {
      ChatHistoryTrace.log(
        'load_previous_viewport_anchor_capture_fallback',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'msgID': best.msgID,
          'seq': best.seq,
          'viewportTop': best.viewportTop,
        },
      );
    }
    return best;
  }

  int _rawMessageCount() {
    return _chatGlobalModel?.rawMessageCount(_conversationId()) ??
        widget.messageList.length;
  }

  void _finishPreviousLoadPagination({String? anchorMsgID, String? anchorSeq}) {
    _paginationUi.finishPreviousLoadInFlight();
    if (!_isSearchJumpStabilizing) {
      final gm = _chatGlobalModel;
      final conv = _conversationId();
      if (gm != null) {
        final position = gm.getMessageListPosition(conv);
        final stillReadingHistory =
            position == HistoryMessagePosition.awayTwoScreen ||
                position == HistoryMessagePosition.notShowLatest;
        final isSearchJump = widget.searchJumpAnchor != null ||
            widget.initFindingMsg != null ||
            findingAnchor != null ||
            findingMsg != null ||
            _atJumpOrigin != null;
        if (!isSearchJump &&
            stillReadingHistory &&
            gm.rawMessageCount(conv) >
                ChatMessageWindowPolicy.historyReadSoftMax) {
          ChatHistoryTrace.log(
            'memory_window_trim_held_reading_history',
            conversationID: conv,
            extras: <String, Object?>{
              'count': gm.rawMessageCount(conv),
              'historyReadSoftMax': ChatMessageWindowPolicy.historyReadSoftMax,
              'anchorMsgID': anchorMsgID,
              'anchorSeq': anchorSeq,
            },
          );
        }
        if (!stillReadingHistory) {
          gm.setMemoryWindowSuppressed(conv, false);
        }
      }
    }
  }

  int _messageSortTime(V2TimMessage message) {
    return message.timestamp ?? int.tryParse(message.seq?.trim() ?? '') ?? 0;
  }

  _PreviousLoadAnchor? _anchorFromMessage(V2TimMessage message) {
    final msgID = message.msgID?.trim();
    final seq = int.tryParse(message.seq ?? '');
    if (msgID != null && msgID.isNotEmpty) {
      return _PreviousLoadAnchor(msgID: msgID, seq: seq, message: message);
    }
    if (seq != null && seq > 0) {
      return _PreviousLoadAnchor(msgID: null, seq: seq, message: message);
    }
    return null;
  }

  _PreviousLoadAnchor? _anchorForPreviousLoad(List<V2TimMessage?> list) {
    // 上拉锚点：仅 SDK 可翻页消息，或归档消息（走归档分页）。
    // 本地 tip（ce_ / localGroupTips）永远不参与上拉游标。
    final sdkCapable = <V2TimMessage>[];
    final archiveOnly = <V2TimMessage>[];
    for (final item in list) {
      if (item == null || item.elemType == 11) {
        continue;
      }
      if (HistoryPaginationAnchor.isLocalInjectedMessage(item)) {
        continue;
      }
      if (HistoryPaginationAnchor.canUseForSdkPagination(item)) {
        sdkCapable.add(item);
      } else if (HistoryPaginationAnchor.isArchiveHistoryMessage(item)) {
        archiveOnly.add(item);
      }
    }
    final picked =
        HistoryPaginationAnchor.oldestSdkPaginationAnchor(sdkCapable) ??
            HistoryPaginationAnchor.oldestArchiveCursorAnchor(archiveOnly);
    if (picked == null) {
      // tip-only / 无可翻页实体时勿刷日志。
      return null;
    }
    if (!HistoryPaginationAnchor.canUseForSdkPagination(picked)) {
      ChatHistoryTrace.log(
        'anchor_previous_non_sdk',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'msgID': picked.msgID,
          'seq': picked.seq,
          'ts': picked.timestamp,
        },
      );
    }
    return _anchorFromMessage(picked);
  }

  /// 向下滑加载更新消息：沿当前 SDK 窗口的最新边界继续分页。
  _PreviousLoadAnchor? _anchorForLatestLoad(List<V2TimMessage?> list) {
    final cursor = widget.model.historyNewerPageCursor;
    if (cursor != null) return _anchorFromMessage(cursor);
    V2TimMessage? picked;
    for (final item in list) {
      if (item == null || item.elemType == 11) {
        continue;
      }
      // 本地 tip 不上参与最新方向分页锚点。
      if (HistoryPaginationAnchor.isLocalInjectedMessage(item)) {
        continue;
      }
      if (!HistoryPaginationAnchor.canUseForSdkPagination(item) &&
          !HistoryPaginationAnchor.isArchiveHistoryMessage(item)) {
        continue;
      }
      // Group sequence is authoritative even when timestamps are out of order.
      if (picked == null ||
          TUIChatGlobalModel.compareMessagesChronological(item, picked) > 0) {
        picked = item;
      }
    }
    return picked == null ? null : _anchorFromMessage(picked);
  }

  bool _isSearchJumpHistoryMode(TUIChatGlobalModel globalModel) {
    // Entry-unread navigation installs the same bounded, two-sided history
    // window as search navigation. After positioning it deliberately changes
    // the logical position to awayTwoScreen so the return-to-bottom capsule
    // can appear; the stable unread anchor must therefore keep newer paging
    // enabled independently of that position value.
    if (_entryUnreadOrigin != null ||
        _atJumpOrigin != null ||
        widget.searchJumpAnchor != null ||
        widget.initFindingMsg != null) {
      return true;
    }
    final position = globalModel.getMessageListPosition(_conversationId());
    return position == HistoryMessagePosition.notShowLatest;
  }

  bool _canProbeLatestHistory(TUIChatGlobalModel globalModel) {
    return widget.model.haveMoreLatestData ||
        globalModel.memoryWindowMissingNewer(_conversationId()) ||
        globalModel.hasDurableHistoryDeferred(_conversationId());
  }

  /// A local-first window is not cloud proof.  While the older boundary is
  /// still unknown we must let the first deliberate upward gesture enter the
  /// normal previous-page loader, even though `haveMoreData` is false for the
  /// transient unknown state.  Only an exhausted result may stop pagination.
  bool _canAttemptPreviousHistoryPagination() {
    return widget.model.haveMoreData ||
        widget.model.historyAvailability == HistoryAvailability.unknown;
  }

  String _previousLoadAnchorKey(_PreviousLoadAnchor anchor) {
    final msgID = anchor.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      return 'msg:$msgID';
    }
    return 'seq:${anchor.seq ?? -1}';
  }

  bool _shouldTriggerLoadPreviousFromScroll(
    ScrollMetrics metrics, {
    _PreviousLoadAnchor? anchor,
  }) {
    if (!metrics.hasPixels || !metrics.hasContentDimensions) {
      return false;
    }
    // 不可滚动列表（内容不足一屏）不参与滚动分页，避免回弹抖动触发死循环。
    if (metrics.maxScrollExtent <= 0) {
      return false;
    }
    if (_isOverscrollingPastTop(metrics)) {
      return false;
    }
    final inPrefetch = HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      prefetchPx: _historyPreviousPrefetchPx(),
      hasPixels: metrics.hasPixels,
      hasContentDimensions: metrics.hasContentDimensions,
    );
    if (!inPrefetch) {
      return false;
    }
    final nearTop = HistoryPreviousPrefetchPolicy.shouldShowPreviousLoadSpinner(
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      hasPixels: metrics.hasPixels,
      hasContentDimensions: metrics.hasContentDimensions,
    );
    // ScrollUpdateNotification 可在一帧内触发多次。Profile 下保留诊断，
    // 但按时间/锚点限流，避免 debugPrint 自身放大上滑卡顿。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final anchorKey =
        anchor == null ? 'none' : _previousLoadAnchorKey(anchor);
    if (nearTop) {
      final shouldTrace = anchorKey != _lastScrollNearTopTraceAnchor ||
          nowMs - _lastScrollNearTopTraceMs >= 500;
      if (!shouldTrace) {
        return true;
      }
      _lastScrollNearTopTraceMs = nowMs;
      _lastScrollNearTopTraceAnchor = anchorKey;
      ChatHistoryTrace.log(
        'scroll_near_top',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'pixels': metrics.pixels.toStringAsFixed(1),
          'maxExtent': metrics.maxScrollExtent.toStringAsFixed(1),
          'haveMoreData': widget.model.haveMoreData,
          'anchorMsgID': anchor?.msgID,
          'anchorSeq': anchor?.seq,
          'topReachConsumed': _paginationUi.previousLoadConsumedThisTopReach,
          'ignoreScroll': _paginationUi.ignoreScrollLoadPrevious,
          'loadingPrevious': _paginationUi.isLoadingPrevious,
          'taskInFlight': _paginationUi.loadPreviousTask != null,
          'triedAfterNoMore': _paginationUi.triedPreviousAfterNoMore,
        },
      );
    } else {
      final shouldTrace = anchorKey != _lastScrollPrefetchTraceAnchor ||
          nowMs - _lastScrollPrefetchTraceMs >= 500;
      if (!shouldTrace) {
        return true;
      }
      _lastScrollPrefetchTraceMs = nowMs;
      _lastScrollPrefetchTraceAnchor = anchorKey;
      ChatHistoryTrace.log(
        'scroll_previous_prefetch',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'pixels': metrics.pixels.toStringAsFixed(1),
          'maxExtent': metrics.maxScrollExtent.toStringAsFixed(1),
          'prefetchPx': _historyPreviousPrefetchPx(),
          'haveMoreData': widget.model.haveMoreData,
          'anchorMsgID': anchor?.msgID,
          'anchorSeq': anchor?.seq,
          'topReachConsumed': _paginationUi.previousLoadConsumedThisTopReach,
          'ignoreScroll': _paginationUi.ignoreScrollLoadPrevious,
          'loadingPrevious': _paginationUi.isLoadingPrevious,
          'taskInFlight': _paginationUi.loadPreviousTask != null,
          'triedAfterNoMore': _paginationUi.triedPreviousAfterNoMore,
        },
      );
    }
    return true;
  }

  bool _isInPreviousGestureBand(ScrollMetrics? metrics) =>
      metrics != null &&
      metrics.hasPixels &&
      metrics.hasContentDimensions &&
      metrics.maxScrollExtent > metrics.minScrollExtent + 0.5 &&
      metrics.pixels >= metrics.maxScrollExtent - _loadPreviousTopNearPx;

  bool _historyPhysicsAllowsUserScrolling(ScrollPhysics physics) {
    // allowUserScrolling does not delegate to parent, unlike offset handling.
    // Our pagination wrapper must not hide a configured NeverScrollable parent.
    for (ScrollPhysics? current = physics;
        current != null;
        current = current.parent) {
      if (!current.allowUserScrolling) return false;
    }
    return true;
  }

  void _cancelPendingPreviousGesture() {
    if (!_previousLoadQueue.isPending) return;
    _previousLoadQueue.cancel();
    if (!_paginationUi.isLoadingPrevious && !_paginationUi.isLoadingLatest) {
      _clearTopHistoryLoading();
    }
  }

  void _rememberPreviousEdgeGesture(ScrollMetrics metrics,
      {bool allowShortViewport = false}) {
    if (_previousLoadWindowIsCurrent?.call() == false) {
      _invalidatePreviousPagination();
    }
    if (!_isInPreviousGestureBand(metrics) &&
        !(allowShortViewport &&
            metrics.hasPixels &&
            metrics.hasContentDimensions &&
            metrics.maxScrollExtent - metrics.minScrollExtent <= 1)) return;
    _queuePreviousLoad(null,
        source: allowShortViewport
            ? _PreviousLoadSource.shortTouch
            : _PreviousLoadSource.edgeGesture);
  }

  _PreviousLoadAnchor? _anchorForPreviousIntent(_PreviousLoadIntent intent) =>
      intent.anchor ?? _anchorForPreviousLoad(_currentVisibleMessageList());

  ChatPreviousLoadDecision _evaluatePreviousLoadIntent(
      _PreviousLoadIntent intent) {
    final userGesture = intent.source == _PreviousLoadSource.edgeGesture ||
        intent.source == _PreviousLoadSource.shortTouch;
    final canWait = userGesture || intent.source == _PreviousLoadSource.trimResume;
    final blocked = canWait
        ? ChatPreviousLoadDecision.wait
        : ChatPreviousLoadDecision.discard;
    final global = _chatGlobalModel ?? widget.model.globalModel;
    final position = _singleScrollPositionOrNull();
    if (!mounted ||
        !identical(widget.model, intent.model) ||
        _conversationId() != intent.conversationID ||
        !intent.windowIsCurrent() ||
        global.isSearchJumpPending(intent.conversationID) ||
        global.isUserScrollToBottomInProgress(intent.conversationID) ||
        (userGesture &&
            (!widget.isAllowScroll ||
                ModalRoute.of(context)?.isCurrent == false ||
                intent.gesture != _paginationUi.previousUserGestureSequence ||
                intent.gesture <= _paginationUi.previousLoadGestureSequence ||
                (intent.source == _PreviousLoadSource.shortTouch &&
                    position != null &&
                    !_historyPhysicsAllowsUserScrolling(position.physics))))) {
      return ChatPreviousLoadDecision.discard;
    }
    if (intent.silent &&
        _historyOpenRevealReady &&
        intent.source != _PreviousLoadSource.viewportFill) {
      return ChatPreviousLoadDecision.discard;
    }
    // All paths share these locks. A waiting gesture does not itself prevent
    // trim. Dragging past the older edge is already a valid pagination intent;
    // waiting for that overscroll to rebound stalls loading under the finger.
    if (_paginationUi.isLoadingPrevious ||
        _paginationUi.loadPreviousTask != null ||
        _paginationUi.isLoadingLatest ||
        _historyWindowTrimUi.isBusy ||
        global.historyWindowPaginationBlocked(intent.conversationID) ||
        _isSearchJumpStabilizing ||
        _isHistoryScrollProtected ||
        _shouldCompensateScrollForPagination() ||
        !_paginationUi.canScheduleLoadPrevious(
            searchJumpStabilizing: false, historyScrollProtected: false) ||
        global.isMessageContextMenuOverlayOpen ||
        global.isContextMenuViewportRestoreActive(intent.conversationID) ||
        global.shouldLockChatScrollForMediaPreview ||
        global.isRestoringScrollAfterMediaPreview ||
        (userGesture &&
            (position == null ||
                !position.hasPixels ||
                !position.hasContentDimensions ||
                position.pixels < position.minScrollExtent))) return blocked;
    // The former scroll scheduler admitted one explicit end probe even when
    // haveMoreData was already false. Its transaction also owns reading-window
    // suppression; removing it changes how subsequent arrivals are buffered.
    final firstEndProbe = intent.source == _PreviousLoadSource.edgeGesture &&
        !_paginationUi.triedPreviousAfterNoMore;
    if (userGesture &&
        !_canAttemptPreviousHistoryPagination() && !firstEndProbe) {
      return ChatPreviousLoadDecision.discard;
    }
    // An edge intent was qualified by its input adapter. Lazy layout can grow
    // maxScrollExtent during debounce; only real reversal/owner changes revoke it.
    // A short touch additionally depends on still having a usable short/edge view.
    if (intent.source == _PreviousLoadSource.shortTouch &&
        !_isInPreviousGestureBand(position) &&
        position!.maxScrollExtent - position.minScrollExtent > 1) {
      return ChatPreviousLoadDecision.discard;
    }
    if (!widget.model.haveMoreData &&
        widget.model.historyAvailability == HistoryAvailability.exhausted &&
        _paginationUi.triedPreviousAfterNoMore) {
      return ChatPreviousLoadDecision.discard;
    }
    final anchor = _anchorForPreviousIntent(intent);
    if (anchor == null) return ChatPreviousLoadDecision.discard;
    final anchorKey = _previousLoadAnchorKey(anchor);
    // Evaluate without consuming a gesture or releasing a failed cursor.
    // Those transitions belong to the synchronous dispatch below.
    final changedFailedCursor = _paginationUi.previousRetryNeedsUserGesture &&
        _paginationUi.lastTopReachConsumedAnchorKey != null &&
        anchorKey != _paginationUi.lastTopReachConsumedAnchorKey;
    final touchRetry = intent.retryGesture;
    if (_paginationUi.previousRetryNeedsUserGesture &&
        !changedFailedCursor && !touchRetry) {
      return ChatPreviousLoadDecision.needsGesture;
    }
    if (_paginationUi.previousLoadConsumedThisTopReach &&
        !changedFailedCursor &&
        !(touchRetry && _paginationUi.previousRetryNeedsUserGesture) &&
        intent.source != _PreviousLoadSource.viewportFill &&
        intent.source != _PreviousLoadSource.trimResume) {
      return ChatPreviousLoadDecision.discard;
    }
    return ChatPreviousLoadDecision.ready;
  }

  void _queuePreviousLoad(_PreviousLoadAnchor? anchor,
      {required _PreviousLoadSource source, bool silent = false}) {
    final model = widget.model;
    final intent = (
      anchor: anchor,
      source: source,
      model: model,
      conversationID: _conversationId(),
      windowIsCurrent: model.captureHistoryWindowPublicationFence(),
      gesture: _paginationUi.previousUserGestureSequence,
      silent: silent,
      retryGesture: source == _PreviousLoadSource.shortTouch &&
          _paginationUi.previousRetryNeedsUserGesture &&
          !_paginationUi.isLoadingPrevious &&
          _paginationUi.loadPreviousTask == null,
    );
    _previousLoadQueue.request(
      userGesture: source == _PreviousLoadSource.edgeGesture ||
          source == _PreviousLoadSource.shortTouch,
      evaluate: () => _evaluatePreviousLoadIntent(intent),
      load: () => _loadPrevious(intent),
      onDecision: (decision) {
        if (!mounted) return;
        if (!identical(widget.model, model) ||
            _conversationId() != intent.conversationID ||
            !intent.windowIsCurrent()) {
          if (!_previousLoadQueue.isAdmitted &&
              !_paginationUi.isLoadingPrevious && !_paginationUi.isLoadingLatest) {
            _clearTopHistoryLoading();
          }
          return;
        }
        if (decision == ChatPreviousLoadDecision.ready) {
          _markTopHistoryLoadingScheduled(silent: silent);
        } else {
          _historyWindowBlocksPagination();
          final position = _singleScrollPositionOrNull();
          if (position != null) {
            _logScrollLoadPreviousBlocked(
                metrics: position,
                anchor: _anchorForPreviousIntent(intent),
                reason: 'queue_${source.name}_${decision.name}');
          }
          if (!_previousLoadQueue.isAdmitted &&
              !_paginationUi.isLoadingPrevious && !_paginationUi.isLoadingLatest) {
            _clearTopHistoryLoading();
          }
        }
      },
    );
  }

  void _logScrollLoadPreviousBlocked({
    required ScrollMetrics metrics,
    _PreviousLoadAnchor? anchor,
    required String reason,
  }) {
    if (!metrics.hasPixels || !metrics.hasContentDimensions) {
      return;
    }
    if (!HistoryPreviousPrefetchPolicy.isInPreviousPrefetchBand(
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      prefetchPx: _historyPreviousPrefetchPx(),
      hasPixels: metrics.hasPixels,
      hasContentDimensions: metrics.hasContentDimensions,
    )) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _paginationUi.lastScrollBlockLogMs < 800) {
      return;
    }
    _paginationUi.lastScrollBlockLogMs = nowMs;
    ChatHistoryTrace.log(
      'scroll_load_blocked',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        'reason': reason,
        'pixels': metrics.pixels.toStringAsFixed(1),
        'maxExtent': metrics.maxScrollExtent.toStringAsFixed(1),
        'haveMoreData': widget.model.haveMoreData,
        'triedAfterNoMore': _paginationUi.triedPreviousAfterNoMore,
        'anchorMsgID': anchor?.msgID,
        'anchorSeq': anchor?.seq,
        'topReachConsumed': _paginationUi.previousLoadConsumedThisTopReach,
        'ignoreScroll': _paginationUi.ignoreScrollLoadPrevious,
        'loadingPrevious': _paginationUi.isLoadingPrevious,
        'taskInFlight': _paginationUi.loadPreviousTask != null,
      },
    );
  }

  void _scheduleLoadPrevious(
    _PreviousLoadAnchor? anchor, {
    bool silent = false,
    bool allowAfterRevealForViewportFill = false,
  }) {
    if (anchor == null) return;
    _queuePreviousLoad(anchor,
        source: allowAfterRevealForViewportFill
            ? _PreviousLoadSource.viewportFill
            : _PreviousLoadSource.prefetch,
        silent: silent);
  }

  bool _allowsLatestHistoryPagination(TUIChatGlobalModel globalModel) {
    // Durable arrivals keep the logical position away from bottom until the
    // connected newer pages are visible. Physical edge checks below must still
    // be able to load those pages; otherwise each state waits for the other.
    if (globalModel.historyWindowCanReadNewer(_conversationId()) ||
        globalModel.hasDurableHistoryDeferred(_conversationId())) {
      return true;
    }
    if (_isSearchJumpHistoryMode(globalModel)) {
      return true;
    }
    final listPosition = globalModel.getMessageListPosition(_conversationId());
    // 读历史（一屏外/非最新）期间禁止 latest 探测 replace 列表；回底后再补拉。
    return listPosition == HistoryMessagePosition.bottom ||
        listPosition == HistoryMessagePosition.inTwoScreen;
  }

  bool _shouldAttemptLatestHistoryLoad({
    required TUIChatGlobalModel globalModel,
    required int safeUnreadCount,
  }) {
    if (_isSearchJumpStabilizing ||
        _historyWindowBlocksPagination() ||
        !_canProbeLatestHistory(globalModel) ||
        globalModel.isRestoringScrollAfterMediaPreview ||
        _paginationUi.isLoadingPrevious ||
        _paginationUi.isLoadingLatest ||
        _shouldCompensateScrollForPagination()) {
      return false;
    }
    final listPosition = globalModel.getMessageListPosition(_conversationId());
    final searchJump = _isSearchJumpHistoryMode(globalModel);
    if (!SearchJumpLatestGate.shouldAllowLatestPagination(
      position: listPosition,
      haveMoreLatestData: widget.model.haveMoreLatestData ||
          globalModel.hasDurableHistoryDeferred(_conversationId()),
      memoryWindowMissingNewer: globalModel.memoryWindowMissingNewer(
        _conversationId(),
      ),
    )) {
      return false;
    }
    // 上翻补偿忽略期内：普通 latest 探测暂停；但内存窗口已裁掉较新端时仍允许补拉。
    if (_paginationUi.ignoreScrollLoadPrevious > 0 &&
        !globalModel.memoryWindowMissingNewer(_conversationId())) {
      return false;
    }
    if (!_allowsLatestHistoryPagination(globalModel)) {
      return false;
    }
    return _isNearLatestScrollEdge(
      _singleScrollPositionOrNull(),
      relaxed: searchJump,
    );
  }

  bool _canScheduleLoadLatest() =>
      !_historyWindowBlocksPagination() &&
      _paginationUi.canScheduleLoadLatest();

  void _scheduleLoadLatest(
    _PreviousLoadAnchor? anchor, {
    required TUIChatGlobalModel globalModel,
    required int safeUnreadCount,
  }) {
    if (anchor == null) return;
    final model = widget.model;
    final conversationID = _conversationId();
    final windowIsCurrent = model.captureHistoryWindowPublicationFence();
    // Record the gesture before checking temporary gates. Unlike a debounce
    // used as a trim lock, this pending intent cannot prevent its own recovery.
    final remainingCooldownMs = _paginationUi.lastLoadLatestCompletedAtMs +
        ChatListPaginationUiGate.loadLatestCooldownMs -
        DateTime.now().millisecondsSinceEpoch;
    _latestLoadIntent.request(
      delay: Duration(milliseconds: max(220, remainingCooldownMs)),
      evaluate: () {
        if (!mounted ||
            !identical(widget.model, model) ||
            _conversationId() != conversationID ||
            !windowIsCurrent() ||
            !widget.isAllowScroll ||
            ModalRoute.of(context)?.isCurrent == false ||
            globalModel.isUserScrollToBottomInProgress(conversationID) ||
            globalModel.isSearchJumpPending(conversationID)) {
          return ChatLatestLoadDecision.discard;
        }
        // A trim or overlay restore can temporarily move the coordinate origin
        // or replace the visible cursor. Only stable geometry can invalidate
        // the user's edge gesture; otherwise keep it until that owner releases.
        if ((_routeScroll.openedWithCachedHistory &&
                _isInitialRouteSettleWindow) ||
            globalModel.isMessageContextMenuOverlayOpen ||
            globalModel.isContextMenuViewportRestoreActive(conversationID) ||
            globalModel.shouldLockChatScrollForMediaPreview ||
            _paginationUi.isLoadingPrevious ||
            _paginationUi.isLoadingLatest ||
            _shouldCompensateScrollForPagination() ||
            !_canScheduleLoadLatest()) {
          return ChatLatestLoadDecision.blocked;
        }
        if (!_canProbeLatestHistory(globalModel) ||
            !_allowsLatestHistoryPagination(globalModel) ||
            !_isNearLatestScrollEdge(_singleScrollPositionOrNull(),
                relaxed: _isSearchJumpHistoryMode(globalModel))) {
          return ChatLatestLoadDecision.discard;
        }
        if (!_shouldLoadLatestOnScroll(
              globalModel: globalModel,
              safeUnreadCount: safeUnreadCount,
            )) {
          return ChatLatestLoadDecision.blocked;
        }
        return ChatLatestLoadDecision.ready;
      },
      onReady: () {
        // Older loads/trim may have replaced the cursor while the user waited.
        final currentAnchor = _anchorForLatestLoad(_currentVisibleMessageList());
        if (currentAnchor != null) {
          unawaited(_loadLatest(currentAnchor, globalModel: globalModel));
        }
      },
    );
  }

  Future<void> _loadLatest(
    _PreviousLoadAnchor anchor, {
    required TUIChatGlobalModel globalModel,
    int anchorRetryFrames = 2,
  }) async {
    if (_historyWindowBlocksPagination() ||
        _paginationUi.isLoadingLatest ||
        _paginationUi.isLoadingPrevious ||
        !mounted ||
        _isSearchJumpStabilizing ||
        globalModel.isUserScrollToBottomInProgress(_conversationId()) ||
        !_canProbeLatestHistory(globalModel)) return;

    if (!_beginBufferedRevealAnchor(scheduleRestore: false)) {
      if (anchorRetryFrames > 0) {
        final conversationID = _conversationId();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _conversationId() == conversationID) {
          await _loadLatest(anchor,
              globalModel: globalModel, anchorRetryFrames: anchorRetryFrames - 1);
        }
      }
      return;
    }
    final model = widget.model;
    final conversationID = _conversationId();
    final windowIsCurrent = model.captureHistoryWindowPublicationFence();
    final generation = ++_latestPaginationGeneration;
    bool ownsLoad() => mounted &&
        generation == _latestPaginationGeneration &&
        identical(widget.model, model) && _conversationId() == conversationID;
    _latchProgressiveNewestBoundary();
    _paginationUi.isLoadingLatest = true;
    final wasSuppressed =
        globalModel.isMemoryWindowSuppressed(_conversationId());
    globalModel.setMemoryWindowSuppressed(_conversationId(), true);
    globalModel.setMessageListPosition(
        _conversationId(), HistoryMessagePosition.notShowLatest,
        notify: false);
    _beginHistoryScrollProtection();
    loadingPlace = LoadingPlace.top;
    setState(() {});
    try {
      await model.loadChatRecord(
        direction: LoadDirection.latest,
        count: HistoryMessageDartConstant.getCount,
        lastMsgID: anchor.msgID,
        lastMsgSeq: anchor.seq ?? -1,
        lastMsg: anchor.message,
      );
      // Keep compensation armed through layout, before the page is painted.
      // One scroll request reads one page; it never pins or drains to latest.
      if (ownsLoad() && windowIsCurrent()) await waitForSearchJumpLayout();
    } finally {
      // An older SDK future can finish after return-to-latest/search has
      // installed a different window. Release this request's loading flag,
      // but never restore its old anchor/suppression onto the replacement.
      if (ownsLoad()) {
        if (windowIsCurrent()) _scheduleBufferedRevealAnchorRestore();
        _paginationUi.lastLoadLatestCompletedAtMs =
            DateTime.now().millisecondsSinceEpoch;
        _paginationUi.isLoadingLatest = false;
        _scheduleHistoryWindowTrim();
        if (windowIsCurrent()) {
          if (!globalModel.isSearchJumpPending(conversationID)) {
            globalModel.setMemoryWindowSuppressed(conversationID, wasSuppressed);
          }
          _beginHistoryScrollProtection();
        }
        if (loadingPlace == LoadingPlace.top && !_paginationUi.isLoadingPrevious) {
          loadingPlace = LoadingPlace.none;
        }
        setState(() {});
      }
    }
  }

  bool _renderObjectNeedsLayout(RenderObject renderObject) {
    var needsLayout = false;
    assert(() {
      needsLayout = renderObject.debugNeedsLayout;
      return true;
    }());
    return needsLayout;
  }

  bool _isNearLatestScrollEdge(ScrollMetrics? metrics, {bool relaxed = false}) {
    if (metrics == null) {
      return false;
    }
    if (!metrics.hasPixels || !metrics.hasContentDimensions) {
      return false;
    }
    final viewport = metrics.viewportDimension;
    final threshold = relaxed ? (viewport * 0.35).clamp(160.0, 720.0) : 96.0;
    return metrics.pixels <= metrics.minScrollExtent + threshold;
  }

  bool _shouldLoadLatestOnScroll({
    required TUIChatGlobalModel globalModel,
    required int safeUnreadCount,
  }) {
    return _shouldAttemptLatestHistoryLoad(
      globalModel: globalModel,
      safeUnreadCount: safeUnreadCount,
    );
  }

  bool get _isSearchJumpStabilizing {
    return _initialSearchJumpPending ||
        _unreadWindowJumpInFlight ||
        _scrollToFindInFlight ||
        DateTime.now().millisecondsSinceEpoch < _searchJumpStabilizeUntilMs;
  }

  void _lockSearchJumpStabilization({int milliseconds = 900}) {
    final until = DateTime.now().millisecondsSinceEpoch + milliseconds;
    if (until > _searchJumpStabilizeUntilMs) {
      _searchJumpStabilizeUntilMs = until;
    }
    // 搜索/引用定位拉史期间禁止窗口裁剪，避免目标消息被 trim。
    _chatGlobalModel?.setMemoryWindowSuppressed(_conversationId(), true);
  }

  Future<void> _loadPrevious(_PreviousLoadIntent intent) async {
    // Queue evaluation and dispatch have no asynchronous gap. Only this entry
    // consumes the admitted gesture/cursor; SDK and viewport ownership stay here.
    final anchor = _anchorForPreviousIntent(intent);
    if (anchor == null) return;
    if (intent.retryGesture &&
        _paginationUi.previousRetryNeedsUserGesture) {
      _paginationUi.onUserDragStart();
    }
    _paginationUi.releasePreviousRetryForChangedAnchor(
        _previousLoadAnchorKey(anchor));
    if (widget.model.haveMoreData) {
      _paginationUi.triedPreviousAfterNoMore = false;
    }
    PerfTimeline.instant('chat_history_page_request', arguments: {
      'conversationId': _conversationId(),
    });
    _paginationUi.markTopReachConsumedForPreviousLoad(
      _previousLoadAnchorKey(anchor),
    );
    final task = _loadPreviousImpl(anchor);
    _paginationUi.loadPreviousTask = task;
    try {
      await task;
    } finally {
      if (identical(_paginationUi.loadPreviousTask, task)) {
        _paginationUi.loadPreviousTask = null;
      }
      _scheduleHistoryWindowTrim();
    }
  }

  void _invalidatePreviousPagination() {
    _previousPaginationGeneration++;
    _previousLoadWindowIsCurrent = null;
    _shortViewportPreviousPointer = null;
    _shortViewportPreviousPointerStart = null;
    _shortViewportPreviousGestureRecorded = false;
    _shortViewportPreviousGestureCancelled = false;
    _previousLoadQueue.cancel();
    _paginationUi.loadingIndicatorTimer?.cancel();
    _paginationUi.loadingIndicatorTimer = null;
    _paginationUi.loadPreviousTask = null;
    _paginationUi.isLoadingPrevious = false;
    _paginationUi.previousLoadInFlightAnchorKey = null;
    _paginationUi.previousLoadConsumedThisTopReach = false;
    _paginationUi.previousRetryNeedsUserGesture = false;
    _paginationUi.lastTopReachConsumedAnchorKey = null;
    _paginationUi.ignoreScrollLoadPrevious = 0;
    _paginationUi.historyScrollProtectUntilMs = 0;
    _paginationUi.latestLoadSuppressedUntilMs = 0;
    _paginationUi.lastLoadPreviousCompletedAtMs = 0;
    _paginationUi.scrollPaginationCompensationGeneration++;
    _clearPaginationRestoreAnchor();
    _clearScrollPaginationCompensation();
    _clearTopHistoryLoading(notify: false);
  }

  Future<void> _loadPreviousImpl(_PreviousLoadAnchor anchor) async {
    if (_chatGlobalModel?.isMessageContextMenuOverlayOpen ?? false) {
      return;
    }
    if (_paginationUi.isLoadingPrevious || !mounted) {
      _clearTopHistoryLoading();
      return;
    }
    final model = widget.model;
    final conversationID = _conversationId();
    final generation = ++_previousPaginationGeneration;
    final windowIsCurrent = model.captureHistoryWindowPublicationFence();
    _previousLoadWindowIsCurrent = windowIsCurrent;
    bool ownsLoad() => mounted &&
        generation == _previousPaginationGeneration &&
        identical(widget.model, model) &&
        _conversationId() == conversationID;
    if (!widget.model.haveMoreData) {
      if (widget.model.historyAvailability == HistoryAvailability.exhausted &&
          _paginationUi.triedPreviousAfterNoMore) {
        _clearTopHistoryLoading();
        return;
      }
      // A cold C2C window may still be hydrating (or migrating from the
      // c2c_<user> alias). Do not consume the one-shot "no more" probe until
      // that initial window is known to be committed; an empty/duplicate
      // first probe must remain retryable.
      final convId = _conversationId();
      final initialWindowStable =
          widget.model.globalModel.hasInitialHistoryLoaded(convId) &&
              widget.model.globalModel.rawMessageCount(convId) > 0;
      if (initialWindowStable &&
          widget.model.historyAvailability == HistoryAvailability.exhausted) {
        _paginationUi.triedPreviousAfterNoMore = true;
      }
    }
    _paginationUi.isLoadingPrevious = true;
    _paginationUserScrollSinceLoad = false;
    _chatGlobalModel?.beginPreviousPageImageDecodeDefer();
    _paginationUi.previousLoadInFlightAnchorKey = _previousLoadAnchorKey(
      anchor,
    );
    _paginationUi.paginationRestoreAnchorMsgID = anchor.msgID;
    _paginationUi.paginationRestoreAnchorSeq = anchor.seq;
    _beginHistoryScrollProtection();
    _beginScrollPaginationCompensation();
    _paginationUi.ignoreScrollLoadPrevious += 2;
    // 上拉分页 + 读历史期间禁止窗口裁剪，避免刚 prepend 的行被 trim 掉。
    if (!_isSearchJumpStabilizing) {
      _chatGlobalModel?.setMemoryWindowSuppressed(_conversationId(), true);
    }
    _chatGlobalModel?.setMemoryWindowAnchor(
      _conversationId(),
      msgID: anchor.msgID,
      seq: anchor.seq?.toString(),
    );
    _chatGlobalModel?.setMessageListPosition(
      _conversationId(),
      HistoryMessagePosition.notShowLatest,
      notify: false,
    );
    // 上拉分页期间勿清空 short-history spacer，否则 maxScrollExtent 先缩后扩导致补偿失真。
    double anchorPixels = 0;
    double anchorMaxExtent = 0;
    final loadPosition = _singleScrollPositionOrNull();
    if (loadPosition != null &&
        loadPosition.hasPixels &&
        loadPosition.hasContentDimensions) {
      anchorMaxExtent = loadPosition.maxScrollExtent;
      anchorPixels = loadPosition.pixels;
    }
    // The normal chat viewport is reversed and older rows are appended at its
    // visual top. Native sliver layout is the anchor in that mode; walking the
    // cached tag map only adds main-thread work and creates another restore
    // source. Keep the row anchor for non-reversed consumers.
    final viewportAnchor = loadPosition?.axisDirection == AxisDirection.up ||
            loadPosition?.axisDirection == AxisDirection.left
        ? null
        : _capturePaginationViewportAnchor(anchor);
    _paginationUi.loadingIndicatorTimer?.cancel();
    if (mounted) {
      // 静默补拉不改 loadingPlace，避免顶部转圈被点亮。
      if (!_paginationUi.silentTopHistoryLoading) {
        loadingPlace = LoadingPlace.top;
      }
      _syncTopHistoryLoadingVisible();
    }
    var loaded = false;
    final listLenBefore = _rawMessageCount();
    final compensationGeneration =
        ++_paginationUi.scrollPaginationCompensationGeneration;
    try {
      ChatHistoryTrace.log(
        'load_previous_start',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'anchorMsgID': anchor.msgID,
          'anchorSeq': anchor.seq,
          'listLenBefore': listLenBefore,
          'widgetListLenBefore': widget.messageList.length,
          'haveMoreData': widget.model.haveMoreData,
          'anchorPixels': anchorPixels,
          'anchorMaxExtent': anchorMaxExtent,
          'memorySuppressed':
              _chatGlobalModel?.isMemoryWindowSuppressed(_conversationId()) ??
                  false,
          'position':
              _chatGlobalModel?.getMessageListPosition(_conversationId()).name,
        },
      );
      ChatJitterDiag.log(
        'history_pagination',
        conv: _conversationId(),
        extras: <String, Object?>{
          'stage': 'ui_load_start',
          'anchorMsgID': anchor.msgID,
          'anchorSeq': anchor.seq,
          'listLenBefore': listLenBefore,
          'widgetListLenBefore': widget.messageList.length,
          'anchorPixels': anchorPixels,
          'anchorMaxExtent': anchorMaxExtent,
        },
      );
      loaded = await widget.onLoadMore(
        anchor.msgID,
        LoadDirection.previous,
        null,
        anchor.seq,
        anchor.message,
      );
    } catch (error) {
      ChatHistoryTrace.log(
        'load_previous_error',
        conversationID: _conversationId(),
        extras: <String, Object?>{'error': error.toString()},
      );
      if (ownsLoad() && windowIsCurrent()) {
        _paginationUi.previousLoadConsumedThisTopReach = false;
        _paginationUi.lastTopReachConsumedAnchorKey = null;
        _clearScrollPaginationCompensation();
      }
      rethrow;
    } finally {
      if (ownsLoad() && !windowIsCurrent()) {
        // A return/search/account replacement owns the new window. Retire only
        // this old pagination transaction; never install its old restore there.
        _invalidatePreviousPagination();
        _syncTopHistoryLoadingVisible();
      } else if (ownsLoad()) {
        _paginationUi.loadingIndicatorTimer?.cancel();
        _paginationUi.lastLoadPreviousCompletedAtMs =
            DateTime.now().millisecondsSinceEpoch;
        _paginationUi.isLoadingPrevious = false;
        _paginationUi.latestLoadSuppressedUntilMs =
            DateTime.now().millisecondsSinceEpoch + _historyScrollProtectMs;
        _beginHistoryScrollProtection();
        final listLenAfter = _rawMessageCount();
        // 窗口策略可能在 prepend 同一提交中裁掉已离开视口的较新端，
        // 因而 raw count 会下降；只要提交改变了窗口，就仍需完成视口补偿。
        // onLoadMore=true means the Writer committed a page. A bounded memory
        // window may trim the newer edge in the same transaction, so raw list
        // length is not a valid commit signal.
        final effectiveLoaded = loaded;
        if (!effectiveLoaded) {
          // 空批/拒绝 shrink/无新增：等待下一次上滑重试。
          // 保留贴顶消费位，避免 build、惯性滚动或短视口自动补页反复请求。
          final convId = _conversationId();
          final initialWindowStable =
              widget.model.globalModel.hasInitialHistoryLoaded(convId) &&
                  widget.model.globalModel.rawMessageCount(convId) > 0;
          _paginationUi.releaseTopReachConsumedAfterRetryableNoGrowth(
            haveMoreData: widget.model.haveMoreData ||
                widget.model.historyAvailability ==
                    HistoryAvailability.unknown ||
                !initialWindowStable,
          );
          if (widget.model.historyAvailability == HistoryAvailability.unknown) {
            _paginationUi.triedPreviousAfterNoMore = false;
          }
          _clearPaginationRestoreAnchor();
          _clearScrollPaginationCompensation();
          _cancelPaginationPrependReveal(notify: false);
          _clearTopHistoryLoading();
        } else {
          // 不做 opacity 隐藏 + 二次 reveal：依赖 ScrollPhysics 同步补偿，新消息直接从顶部插入。
          _cancelPaginationPrependReveal(notify: false);
          _clearTopHistoryLoading();
          _extendScrollPaginationCompensation();
          _chatGlobalModel?.beginPreviousPageImageDecodeDefer();
          // 列表已增长：放开同一次贴顶消费位，便于继续上滑/回弹拉下一页。
          // 此处不自动连拉，等下一次滚动事件。
          _paginationUi.releaseTopReachConsumedAfterSuccessfulPage(
            haveMoreData: widget.model.haveMoreData,
          );
        }
        _scheduleMinTopHistoryLoadingHold();
        ChatHistoryTrace.log(
          'load_previous_done',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'loaded': loaded,
            'effectiveLoaded': effectiveLoaded,
            'listLenBefore': listLenBefore,
            'listLenAfter': listLenAfter,
            'widgetListLenAfter': widget.messageList.length,
            'haveMoreData': widget.model.haveMoreData,
            'triedAfterNoMore': _paginationUi.triedPreviousAfterNoMore,
            'delta': listLenAfter - listLenBefore,
            'topReachConsumed': _paginationUi.previousLoadConsumedThisTopReach,
            'releasedTopReach': !_paginationUi.previousLoadConsumedThisTopReach,
          },
        );
        ChatJitterDiag.log(
          'history_pagination',
          conv: _conversationId(),
          extras: <String, Object?>{
            'stage': 'ui_load_done',
            'loaded': loaded,
            'effectiveLoaded': effectiveLoaded,
            'listLenBefore': listLenBefore,
            'listLenAfter': listLenAfter,
            'widgetListLenAfter': widget.messageList.length,
            'delta': listLenAfter - listLenBefore,
          },
        );
        ChatResourceSample.onRawMessageCount(_rawMessageCount());
        // Register the window trim callback before the viewport restore callback
        // so the anchor is measured against the final post-trim list.
        _finishPreviousLoadPagination(
          anchorMsgID: anchor.msgID,
          anchorSeq: anchor.seq?.toString(),
        );
        if (effectiveLoaded && !_paginationUserScrollSinceLoad) {
          _scheduleScrollPaginationCompensationEnd(
            generation: compensationGeneration,
            anchorPixels: anchorPixels,
            anchorMaxExtent: anchorMaxExtent,
            viewportAnchor: viewportAnchor,
          );
        } else if (effectiveLoaded) {
          // The user kept dragging after this request started. Telegram-style
          // behavior is to leave the current gesture position authoritative;
          // restoring the pre-request offset here creates the observed
          // 0 -> oldOffset jump when ScrollEnd arrives later.
          _cancelPaginationRestoreForUserScroll(
            reason: 'gesture_continued_during_request',
          );
          ChatHistoryTrace.log(
            'load_previous_restore_skipped_user_scroll',
            conversationID: _conversationId(),
            extras: <String, Object?>{
              'listLenBefore': listLenBefore,
              'listLenAfter': listLenAfter,
              'anchorPixels': anchorPixels,
            },
          );
        }
        Future<void>.delayed(
          const Duration(milliseconds: _loadPreviousScrollUnlockMs),
          () {
            if (ownsLoad() && !windowIsCurrent()) {
              _invalidatePreviousPagination();
              _syncTopHistoryLoadingVisible();
            } else if (ownsLoad()) {
              if (_paginationUi.ignoreScrollLoadPrevious >= 2) {
                _paginationUi.ignoreScrollLoadPrevious -= 2;
              } else if (_paginationUi.ignoreScrollLoadPrevious > 0) {
                _paginationUi.ignoreScrollLoadPrevious = 0;
              }
              _previousLoadWindowIsCurrent = null;
            }
          },
        );
      }
    }
  }

  bool _messageMatchesTarget(V2TimMessage? current, V2TimMessage target) {
    if (current == null || current.elemType == 11 || current.elemType == 101) {
      return false;
    }
    final targetMsgID = target.msgID?.trim() ?? '';
    final currentMsgID = current.msgID?.trim() ?? '';
    if (targetMsgID.isNotEmpty && currentMsgID.isNotEmpty) {
      return currentMsgID == targetMsgID;
    }
    final targetId = target.id?.trim() ?? '';
    final currentId = current.id?.trim() ?? '';
    if (targetId.isNotEmpty && currentId.isNotEmpty) {
      return currentId == targetId;
    }
    final targetSeq = target.seq?.trim() ?? '';
    final currentSeq = current.seq?.trim() ?? '';
    if (targetSeq.isNotEmpty && currentSeq.isNotEmpty) {
      return currentSeq == targetSeq;
    }
    if ((targetMsgID.isNotEmpty &&
            currentMsgID.isNotEmpty &&
            currentMsgID != targetMsgID) ||
        (targetId.isNotEmpty &&
            currentId.isNotEmpty &&
            currentId != targetId) ||
        (targetSeq.isNotEmpty &&
            currentSeq.isNotEmpty &&
            currentSeq != targetSeq)) {
      return false;
    }
    final targetSender = target.sender?.trim() ?? target.userID?.trim() ?? '';
    final currentSender =
        current.sender?.trim() ?? current.userID?.trim() ?? '';
    if (current.timestamp != null &&
        target.timestamp != null &&
        current.timestamp == target.timestamp) {
      return targetSender.isNotEmpty &&
          currentSender.isNotEmpty &&
          targetSender == currentSender &&
          target.elemType != null &&
          current.elemType != null &&
          target.elemType == current.elemType;
    }
    return false;
  }

  int? _globalIndexForTargetMessage(V2TimMessage target) {
    final messageList = _currentVisibleMessageList();
    int? matchedIndex;
    for (var i = 0; i < messageList.length; i++) {
      if (_messageMatchesTarget(messageList[i], target)) {
        if (matchedIndex != null) {
          return null;
        }
        matchedIndex = i;
      }
    }
    return matchedIndex;
  }

  int? _globalIndexForAnchor(MessageAnchor target) {
    final messageList = _currentVisibleMessageList();
    int? matchedIndex;
    for (var i = 0; i < messageList.length; i++) {
      if (target.matches(messageList[i])) {
        if (matchedIndex != null) {
          return null;
        }
        matchedIndex = i;
      }
    }
    return matchedIndex;
  }

  int? _globalIndexForSeq(String targetSeq) {
    final messageList = _currentVisibleMessageList();
    final want = int.tryParse(targetSeq.trim());
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (message == null ||
          message.elemType == 11 ||
          message.elemType == 101) {
        continue;
      }
      final raw = message.seq?.trim() ?? '';
      if (raw == targetSeq.trim()) {
        return i;
      }
      if (want != null) {
        final current = int.tryParse(raw);
        if (current != null && current == want) {
          return i;
        }
      }
    }
    return null;
  }

  V2TimMessage? _messageForAnchor(MessageAnchor target) {
    final messageList = _currentVisibleMessageList();
    for (final message in messageList) {
      if (target.matches(message)) {
        return message;
      }
    }
    return null;
  }

  bool _scrollMetricsReady() {
    final position = _singleScrollPositionOrNull();
    return position != null &&
        position.hasPixels &&
        position.hasContentDimensions &&
        position.maxScrollExtent.isFinite &&
        position.minScrollExtent.isFinite;
  }

  bool _isInitialFindingTarget(V2TimMessage target) {
    final initial = widget.initFindingMsg;
    return initial != null && _messageMatchesTarget(initial, target);
  }

  void _scheduleScrollToFindingMsgDelayed({
    Duration delay = const Duration(milliseconds: 120),
  }) {
    Future<void>.delayed(delay, () {
      if (mounted) {
        _scheduleScrollToFindingMsg();
      }
    });
  }

  int? _resolveSearchJumpGlobalIndex(_SearchJumpTarget target) {
    return target.resolveIndex();
  }

  _SearchJumpFrameCheck? _checkSearchJumpTargetFrame(_SearchJumpTarget target) {
    final targetGlobalIndex = _resolveSearchJumpGlobalIndex(target);
    if (targetGlobalIndex == null) {
      return null;
    }
    final tagContext =
        _autoScrollController.tagMap[-targetGlobalIndex]?.context;
    final rendered = _currentVisibleMessageList();
    // A retained tag can occupy the same numeric index during replacement.
    // Geometry is evidence only after its stable message key also matches.
    if (tagContext == null ||
        targetGlobalIndex < 0 ||
        targetGlobalIndex >= rendered.length ||
        tagContext.widget.key !=
            ValueKey(_stableMessageListKey(
                rendered[targetGlobalIndex], targetGlobalIndex))) {
      return _SearchJumpFrameCheck.notReady(targetGlobalIndex);
    }
    final scrollable = Scrollable.maybeOf(tagContext);
    if (scrollable == null) {
      return _SearchJumpFrameCheck.notReady(targetGlobalIndex);
    }
    final targetRenderObject = tagContext.findRenderObject();
    final viewportRenderObject = scrollable.context.findRenderObject();
    if (targetRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !targetRenderObject.attached ||
        !viewportRenderObject.attached ||
        !targetRenderObject.hasSize ||
        !viewportRenderObject.hasSize ||
        _renderObjectNeedsLayout(targetRenderObject) ||
        _renderObjectNeedsLayout(viewportRenderObject)) {
      return _SearchJumpFrameCheck.notReady(targetGlobalIndex);
    }

    final targetTop = targetRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
    final targetCenter = targetTop + targetRenderObject.size.height / 2;
    final viewportCenter = viewportRenderObject.size.height / 2;
    final centerDelta = targetCenter - viewportCenter;
    const tolerance = 2.0;
    final strictCenter = _entryUnreadOrigin != null ||
        _atJumpOrigin != null ||
        widget.searchJumpAnchor != null ||
        widget.initFindingMsg != null;
    return _SearchJumpFrameCheck(
      targetGlobalIndex: targetGlobalIndex,
      isReady: true,
      centerDelta: !strictCenter &&
              searchJumpAtReachablePosition(
                targetTop: targetTop,
                targetHeight: targetRenderObject.size.height,
                viewportHeight: viewportRenderObject.size.height,
                metrics: scrollable.position,
                tolerance: tolerance,
              )
          ? 0
          : centerDelta,
      tolerance: tolerance,
    );
  }

  Future<bool> _correctSearchJumpTargetToCenter(
    _SearchJumpTarget target,
  ) async {
    final check = _checkSearchJumpTargetFrame(target);
    if (check == null) {
      return false;
    }
    final targetGlobalIndex = check.targetGlobalIndex;
    if (!check.isReady) {
      await _geomScrollToIndex(
        -targetGlobalIndex,
        preferPosition: AutoScrollPosition.middle,
        reason: 'scroll_to_index_middle',
      );
      return false;
    }
    if (check.isCentered) {
      return true;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      await _geomScrollToIndex(
        -targetGlobalIndex,
        preferPosition: AutoScrollPosition.middle,
        reason: 'scroll_to_index_middle',
      );
      return false;
    }
    final centeredPixels = searchJumpCenterOffset(
      centerDelta: check.centerDelta,
      metrics: position,
    );
    _geomJumpTo(centeredPixels, reason: 'search_jump_measured_center');
    return false;
  }

  Future<bool> _stabilizeCenteredSearchJumpTarget(
    _SearchJumpTarget target, {
    required int generation,
  }) async {
    var stableFrames = 0;
    // The unread handoff retains the old viewport until geometry is verified.
    // Consecutive layout frames are enough; do not add fixed sleeps while the
    // user is waiting behind the loader.
    final unreadHandoff = _unreadWindowJumpInFlight;
    for (var attempt = 0; attempt < 14; attempt++) {
      _lockSearchJumpStabilization(milliseconds: 2600);
      await waitForSearchJumpLayout();
      if (!mounted ||
          !_ownsSearchJumpRequest ||
          generation != _searchJumpGeneration) {
        return false;
      }

      final centered = await _correctSearchJumpTargetToCenter(target);
      if (!mounted ||
          !_ownsSearchJumpRequest ||
          generation != _searchJumpGeneration) {
        return false;
      }
      if (centered) {
        stableFrames++;
        if (stableFrames >= (unreadHandoff ? 3 : 4)) {
          return true;
        }
      } else {
        stableFrames = 0;
      }
      if (!unreadHandoff) {
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
      if (!mounted ||
          !_ownsSearchJumpRequest ||
          generation != _searchJumpGeneration) {
        return false;
      }
    }

    final finalCheck = _checkSearchJumpTargetFrame(target);
    return finalCheck != null && finalCheck.isReady && finalCheck.isCentered;
  }

  Future<bool> _centerOnGlobalIndex(
    int targetGlobalIndex, {
    int attempt = 0,
    _SearchJumpTarget? target,
    int? generation,
  }) async {
    if (!mounted ||
        !_ownsSearchJumpRequest ||
        (generation != null && generation != _searchJumpGeneration)) {
      return false;
    }
    _lockSearchJumpStabilization(milliseconds: 2600);
    if (!_scrollMetricsReady()) {
      if (attempt < 12) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return _centerOnGlobalIndex(
          targetGlobalIndex,
          attempt: attempt + 1,
          target: target,
          generation: generation,
        );
      }
      return false;
    }

    // 只使用 scroll_to_index 自带的安全定位，避免在图片/视频/长文本还没
    // layout 完成时手动 getOffsetToReveal / jumpTo 触发 debugNeedsLayout 红屏。
    try {
      await waitForSearchJumpLayout();
      if (!mounted ||
          !_ownsSearchJumpRequest ||
          (generation != null && generation != _searchJumpGeneration)) {
        return false;
      }
      final resolvedTargetGlobalIndex = target == null
          ? targetGlobalIndex
          : _resolveSearchJumpGlobalIndex(target);
      if (resolvedTargetGlobalIndex == null) return false;
      final materialized = await materializeSearchJumpTarget(
        controller: _autoScrollController,
        resolveIndex: () => target == null
            ? resolvedTargetGlobalIndex
            : _resolveSearchJumpGlobalIndex(target),
        isActive: () =>
            mounted &&
            _ownsSearchJumpRequest &&
            (generation == null || generation == _searchJumpGeneration),
      );
      if (!materialized) return false;
      // Materialization can span multiple frames and list revisions. Never
      // scroll to a stale numeric index belonging to a different message.
      final currentIndex = target == null
          ? resolvedTargetGlobalIndex
          : _resolveSearchJumpGlobalIndex(target);
      if (currentIndex == null) return false;
      if (_unreadWindowJumpInFlight && target != null) {
        // The target is materialized and the previous viewport is retained.
        // Align measured geometry directly instead of animating unseen rows
        // for 250ms. The same strict center verification still runs below.
        await _correctSearchJumpTargetToCenter(target);
      } else {
        await _geomScrollToIndex(
          -currentIndex,
          preferPosition: AutoScrollPosition.middle,
          reason: 'scroll_to_index_middle',
        );
      }
      final stabilized = target == null
          ? true
          : await _stabilizeCenteredSearchJumpTarget(
              target,
              generation: generation ?? _searchJumpGeneration,
            );
      _lockSearchJumpStabilization(milliseconds: 1600);
      return stabilized;
    } catch (_) {
      if (attempt < 8) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) {
          return _centerOnGlobalIndex(
            targetGlobalIndex,
            attempt: attempt + 1,
            target: target,
            generation: generation,
          );
        }
      }
      return false;
    }
  }

  void _scheduleScrollToFindingMsg() {
    if ((findingMsg == null && findingAnchor == null) ||
        _scrollToFindInFlight ||
        _pendingScrollToFind) {
      return;
    }
    _pendingScrollToFind = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingScrollToFind = false;
      if (!mounted) {
        return;
      }
      final anchor = findingAnchor;
      if (anchor != null) {
        _onScrollToAnchor(anchor);
        return;
      }
      if (findingMsg != null) {
        _onScrollToIndex(findingMsg!);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  initFinding() async {
    final anchor = widget.searchJumpAnchor;
    final target = widget.initFindingMsg;
    if (anchor == null && target == null) {
      return;
    }
    // initState precedes didChangeDependencies; the provider field is not
    // attached yet, so capture this route's request directly from the model.
    _searchJumpRequest =
        widget.model.globalModel.searchJumpRequestFor(_conversationId());
    var retries = 0;
    while (widget.messageList.isEmpty && retries < 60) {
      final jumpStatus =
          _chatGlobalModel?.getSearchJumpStatus(_conversationId()) ??
              SearchJumpStatus.idle;
      if (jumpStatus == SearchJumpStatus.failed ||
          jumpStatus == SearchJumpStatus.success) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
      retries++;
      if (!mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    MessageAnchor? resolvedAnchor = anchor;
    if (resolvedAnchor == null && target != null) {
      resolvedAnchor = MessageAnchor.fromConversationMessage(
        widget.conversation,
        target,
      );
    }
    final jumpStatus =
        _chatGlobalModel?.getSearchJumpStatus(_conversationId()) ??
            SearchJumpStatus.idle;
    if (jumpStatus == SearchJumpStatus.failed) {
      setState(() {
        _findingRetryCount = 0;
        findingAnchor = null;
        findingMsg = null;
        maybeHaveMoreMessageForFind = false;
        loadingPlace = LoadingPlace.none;
      });
      return;
    }
    setState(() {
      _findingRetryCount = 0;
      findingAnchor = resolvedAnchor;
      findingMsg = target;
      maybeHaveMoreMessageForFind = resolvedAnchor == null && target != null;
    });
    _scheduleScrollToFindingMsg();
  }

  _controllerListener() {
    final scrollType = _controller.scrollType;
    final targetMessage = _controller.targetMessage;
    switch (scrollType) {
      case ScrollType.toIndex:
        _onScrollToIndex(targetMessage);
        break;
      case ScrollType.toIndexBegin:
        _onScrollToIndexBegin(targetMessage);
        break;
      default:
    }
  }

  String _messageEnterAnimationWidgetKey(V2TimMessage message) {
    final id = message.id;
    if (id != null && id.toString().isNotEmpty) {
      return 'msg_enter_${id.toString()}';
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.isNotEmpty) {
      return 'msg_enter_$msgID';
    }
    return 'msg_enter_${message.timestamp}_${message.seq}';
  }

  String _stableMessageListKey(V2TimMessage? message, int index) {
    if (message == null) {
      return 'empty_$index';
    }
    if (message.elemType == 11) {
      // Time-divider rows are generated by the display projection. Their
      // position is not an identity: prepend/replace must not turn a divider
      // into a different child merely because its index moved.
      return 'time_${message.timestamp ?? message.seq ?? 'unknown'}';
    }
    final outgoingStableId = readOutgoingStableId(message);
    if (outgoingStableId != null) {
      return 'outgoing_$outgoingStableId';
    }
    final msgID = message.msgID;
    if (msgID != null && msgID.trim().isNotEmpty) {
      // msgID is the SDK/server identity. Local `id` can differ between an
      // optimistic row, a send callback and a history replacement, so it must
      // not be preferred for a Sliver child key.
      return 'msgid_${msgID.trim()}';
    }
    final id = message.id;
    if (id != null && id.toString().trim().isNotEmpty) {
      // Only use the local id while the row has no server identity yet.
      return 'local_${id.toString().trim()}';
    }
    // Position-independent fallback. The key MUST stay stable when a message
    // changes index, otherwise `findChildIndexCallback` (which is populated
    // with the identifier computed at index 0) cannot relocate the recycled
    // element and Flutter pins the row at a stale slot until the element tree
    // is torn down (i.e. only an app restart fixes the visual order).
    final sender = message.sender ?? message.userID ?? '';
    final random = message.random ?? 0;
    final seq = message.seq ?? '';
    final fallback = sender.isEmpty &&
            (message.timestamp == null || message.timestamp == 0) &&
            seq.isEmpty &&
            random == 0
        ? '_local_${message.hashCode}'
        : '';
    return 'msg_${sender}_${message.timestamp ?? ''}_${seq}_${random}_${message.elemType}$fallback';
  }

  List<V2TimMessage?> _visibleMessageList(List<V2TimMessage?> source) {
    final list = <V2TimMessage?>[];
    final seenKeys = <String>{};
    for (final item in source) {
      if (item == null) continue;
      if (!widget.model.isVisibleOnReadingTimeline(item)) continue;
      // 零高度消息先丢掉，再折叠因此贴在一起的时间分割线，避免孤儿分割线。
      if (item.elemType != 11 &&
          item.elemType != 101 &&
          !TUIChatGlobalModel.messageAnchorsTimeDivider(item)) {
        continue;
      }
      if (item.elemType == 11 && (list.isEmpty || list.last?.elemType == 11)) {
        continue;
      }
      // A history page and an inbound/send callback can contain the same row
      // in different object instances. Never expose duplicate child keys to a
      // Sliver; keep the first row in newest-first order and let the next
      // authoritative commit replace its content.
      final stableKey = _stableMessageListKey(item, list.length);
      if (!seenKeys.add(stableKey)) continue;
      list.add(item);
    }
    return list;
  }

  void _resetInitialMountBatch() {
    _initialMountGeneration++;
    _initialMountBatchConversationID = _conversationId();
    _initialMountLimit = 0;
    _initialMountFrameScheduled = false;
    _initialMountBatchComplete = false;
  }

  List<V2TimMessage?> _applyInitialMountBatch(
    List<V2TimMessage?> full,
  ) {
    final conversationID = _conversationId();
    if (_initialMountBatchConversationID != conversationID) {
      _resetInitialMountBatch();
    }
    final requiresImmediateFullProjection = _entryUnreadOrigin != null ||
        _atJumpOrigin != null ||
        widget.searchJumpAnchor != null ||
        widget.initFindingMsg != null ||
        _userScrollGestureActive ||
        _isReadingHistory();
    if (requiresImmediateFullProjection) {
      _initialMountBatchComplete = true;
      _initialMountLimit = full.length;
      return full;
    }
    if (full.length <= _initialMountRowsPerFrame) {
      _initialMountLimit = full.length;
      // Local history commonly arrives as a short list before a much larger
      // cloud result. Keep the initial-mount gate open so that later 50+ row
      // jump is still mounted in bounded frame-sized chunks.
      return full;
    }
    if (_initialMountBatchComplete) return full;
    if (_initialMountLimit <= 0) {
      _initialMountLimit = _initialMountRowsPerFrame;
    }
    if (_initialMountLimit >= full.length) {
      _initialMountBatchComplete = true;
      return full;
    }
    _scheduleNextInitialMountBatch(full.length);
    return List<V2TimMessage?>.unmodifiable(
      full.take(_initialMountLimit),
    );
  }

  void _scheduleNextInitialMountBatch(int targetLength) {
    if (_initialMountFrameScheduled || !mounted) return;
    _initialMountFrameScheduled = true;
    final generation = _initialMountGeneration;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _initialMountFrameScheduled = false;
      if (!mounted || generation != _initialMountGeneration) return;
      final next = min(
        targetLength,
        _initialMountLimit + _initialMountRowsPerFrame,
      );
      if (next == _initialMountLimit) return;
      setState(() {
        _initialMountLimit = next;
        _initialMountBatchComplete = next >= targetLength;
      });
    });
  }

  List<V2TimMessage?> _currentVisibleMessageList() {
    return _renderedVisibleMessages ?? _visibleMessageList(widget.messageList);
  }

  Widget _getMessageItemBuilder(V2TimMessage? messageItem) {
    if (widget.itemBuilder != null) {
      final child = widget.itemBuilder!(context, messageItem);
      if (messageItem == null) {
        return child;
      }
      if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
        final messageId = messageItem.msgID ??
            messageItem.id ??
            'seq_${messageItem.seq}_${messageItem.timestamp}';
        final type = messageItem.elemType;
        if (ChatCoverDiag.logOnce(
          'bubble_builder',
          messageId,
          'conv=${_conversationId()} type=$type ts=${messageItem.timestamp} '
              'seq=${messageItem.seq} listLen=${widget.messageList.length}',
        )) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !ChatCoverDiag.canLog) return;
            ChatCoverDiag.logOnce(
              'bubble_first_frame',
              messageId,
              'conv=${_conversationId()} type=$type mounted=$mounted',
            );
          });
        }
      }
      final elemType = messageItem.elemType;
      if (elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS ||
          elemType == 11 ||
          elemType == 101) {
        return child;
      }
      final globalModel = Provider.of<TUIChatGlobalModel>(
        context,
        listen: false,
      );
      final skipEnterAnimation = widget
              .mainHistoryListConfig?.skipMessageEnterAnimationForMessage
              ?.call(messageItem) ??
          globalModel.chatConfig.skipMessageEnterAnimationForMessage?.call(
            messageItem,
          ) ??
          false;
      if (skipEnterAnimation ||
          _hasLiveCenter ||
          _deferUnreadCenterPartition ||
          _isReadingHistory() ||
          globalModel.isBulkMessageSyncActive(_conversationId()) ||
          (messageItem.isSelf == true &&
              messageItem.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT)) {
        if (globalModel.isMessageEnterAnimationPending(messageItem)) {
          globalModel.finishMessageEnterAnimation(messageItem);
        }
        return child;
      }
      if (globalModel.isMessageEnterAnimationPending(messageItem)) {
        final rowKey = _stableMessageListKey(messageItem, 0);
        final wechatListPush = _useWechatListPushTranslate(globalModel);
        // Row reveal / WeChat list-push owns the motion. A bubble slide on top
        // would double-push (inbound and self).
        if (_viewportInsert.activeRowRevealMessages.containsKey(rowKey) ||
            (wechatListPush && _viewportInsert.viewportInsertSlideActive)) {
          return child;
        }
        // 发送在微信 list-push 模式下永不走气泡滑入：否则会与 list-push /
        // force-pin 叠成「出现抖动」。list-push 收尾会 finish；若本帧未武装
        // 上推则立刻 finish，避免 pending 粘住。
        if (wechatListPush && messageItem.isSelf == true) {
          if (!_viewportInsert.activeRowRevealMessages.containsKey(rowKey) &&
              !_viewportInsert.viewportInsertSlideActive) {
            globalModel.finishMessageEnterAnimation(messageItem);
          }
          return child;
        }
        if (_isSearchJumpStabilizing) {
          globalModel.finishMessageEnterAnimation(messageItem);
          return child;
        }
        final stableKey = _messageEnterAnimationWidgetKey(messageItem);
        final enterParams = MessageEnterAnimationParams.fromStyle(
          globalModel.chatConfig.messageEnterAnimationStyle,
          isOutgoing: messageItem.isSelf == true,
        );
        return _MessageEnterAnimationGate(
          message: messageItem,
          globalModel: globalModel,
          stableKey: stableKey,
          enterParams: enterParams,
          animateExtent: false,
          onEnterAnimationFinished: messageItem.isSelf != true && wechatListPush
              ? _acknowledgeInboundProjectionRevealIfNeeded
              : null,
          child: child,
        );
      }
      return child;
    }
    return Container();
  }

  bool _isHeavyListMessage(V2TimMessage? message) {
    if (message == null) {
      return false;
    }
    switch (message.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      case MessageElemType.V2TIM_ELEM_TYPE_FACE:
      case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
        final checker = widget.mainHistoryListConfig?.isHeavyCustomMessage;
        return checker != null ? checker(message) : false;
      case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
        // 不再因「文字长」KeepAlive；避免 Window≈120 时长文 Element 常驻。
        // 特殊交互态如需保活，由业务显式 checker / 其它路径处理。
        return false;
      default:
        return false;
    }
  }

  bool _isOutgoingMediaMessage(V2TimMessage message) {
    if (message.isSelf != true) {
      return false;
    }
    switch (message.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        return true;
      default:
        return false;
    }
  }

  String _listStateCacheKey(List<V2TimMessage?> messageList) {
    final buffer = StringBuffer();
    // messageList is newest-first; scan the head where sends/reorders happen.
    final scanEnd = messageList.length > 16 ? 16 : messageList.length;
    for (var i = 0; i < scanEnd; i++) {
      final message = messageList[i];
      if (message == null || message.elemType == 11) {
        continue;
      }
      final id = message.msgID ?? message.id ?? '$i';
      final seq = message.seq ?? '';
      buffer.write('$id:$seq:${message.status};');
    }
    return buffer.toString();
  }

  bool _isRealChatMessage(V2TimMessage? message) {
    return message != null && message.elemType != 11;
  }

  bool _isUnreadAnchorMessage(V2TimMessage? message) {
    return _isRealChatMessage(message) && message?.elemType != 101;
  }

  int _unreadAnchorMessageCount(List<V2TimMessage?> messageList) {
    return messageList.where(_isUnreadAnchorMessage).length;
  }

  int _realUnreadEndPoint(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    if (unreadMessageCount <= 0 || messageList.isEmpty) {
      return 0;
    }
    var realCount = 0;
    var end = 0;
    while (end < messageList.length && realCount < unreadMessageCount) {
      if (_isUnreadAnchorMessage(messageList[end])) {
        realCount++;
      }
      end++;
    }
    if (end < messageList.length && messageList[end]?.elemType == 11) {
      end++;
    }
    return end.clamp(0, messageList.length).toInt();
  }

  int? _firstUnreadGlobalIndex(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    if (unreadMessageCount <= 0 || messageList.isEmpty) {
      return null;
    }
    var realCount = 0;
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      realCount++;
      if (realCount == unreadMessageCount) {
        return i;
      }
    }
    return null;
  }

  _UnreadMessageAnchor? _unreadAnchorFromCount(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    var realCount = 0;
    V2TimMessage? message;
    for (final item in messageList) {
      if (!_isUnreadAnchorMessage(item)) {
        continue;
      }
      realCount++;
      if (realCount == unreadMessageCount) {
        message = item;
        break;
      }
    }
    if (message == null) {
      return null;
    }
    final identity = _messageIdentity(message);
    final seq = int.tryParse(message.seq?.trim() ?? '');
    if (identity.isEmpty && (seq == null || seq <= 0)) {
      return null;
    }
    return _UnreadMessageAnchor(
      conversationID: _conversationId(),
      identity: identity,
      seq: seq,
    );
  }

  int? _globalIndexForUnreadAnchor(
    List<V2TimMessage?> messageList,
    _UnreadMessageAnchor anchor,
  ) {
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      if (anchor.identity.isNotEmpty &&
          _messageIdentity(message!) == anchor.identity) {
        return i;
      }
      if (anchor.seq != null &&
          int.tryParse(message!.seq?.trim() ?? '') == anchor.seq) {
        return i;
      }
    }
    return null;
  }

  void _captureFirstUnreadAnchor(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    if (unreadMessageCount <= 0 ||
        _unreadAnchorMessageCount(messageList) < unreadMessageCount ||
        (_firstUnreadAnchor != null &&
            _firstUnreadAnchor!.conversationID == _conversationId())) {
      return;
    }
    _firstUnreadAnchor = _unreadAnchorFromCount(
      messageList,
      unreadMessageCount,
    );
  }

  Future<_UnreadMessageAnchor?> _ensureFirstUnreadAnchor(
    int unreadMessageCount,
  ) async {
    final existing = _firstUnreadAnchor;
    if (existing != null && existing.conversationID == _conversationId()) {
      return existing;
    }
    // 大未读禁止按条数追翻；仅小未读 count_fallback 可用。
    if (unreadMessageCount > FirstUnreadJump.maxCountFallbackUnread) {
      return null;
    }
    final maxRounds = (unreadMessageCount / 80).ceil() + 6;
    for (var round = 0; round < maxRounds && mounted; round++) {
      final messageList = _currentVisibleMessageList();
      _captureFirstUnreadAnchor(messageList, unreadMessageCount);
      final captured = _firstUnreadAnchor;
      if (captured != null) {
        return captured;
      }
      final previousAnchor = _anchorForPreviousLoad(messageList);
      final loadedCount = _unreadAnchorMessageCount(messageList);
      final remaining = unreadMessageCount - loadedCount;
      final requestCount = remaining.clamp(1, 80).toInt();
      var loadedMore = false;
      if (previousAnchor != null) {
        loadedMore = await widget.onLoadMore(
          previousAnchor.msgID,
          LoadDirection.previous,
          requestCount,
          previousAnchor.seq,
          previousAnchor.message,
        );
      } else {
        loadedMore = await widget.model.loadChatRecord(
          count: requestCount,
          direction: LoadDirection.previous,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!loadedMore &&
          _unreadAnchorMessageCount(_currentVisibleMessageList()) <
              unreadMessageCount) {
        final beforeCount = _unreadAnchorMessageCount(messageList);
        await widget.model.loadChatRecord(
          count: requestCount,
          direction: LoadDirection.previous,
          lastMsgID: previousAnchor?.msgID,
          lastMsgSeq: previousAnchor?.seq ?? -1,
          lastMsg: previousAnchor?.message,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final afterCount = _unreadAnchorMessageCount(
          _currentVisibleMessageList(),
        );
        if (afterCount <= beforeCount) {
          break;
        }
      }
    }
    return _firstUnreadAnchor;
  }

  int? _latestUnreadGlobalIndex(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    if (unreadMessageCount <= 0 || messageList.isEmpty) {
      return null;
    }
    var realCount = 0;
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isRealChatMessage(message)) {
        continue;
      }
      realCount++;
      if (realCount <= unreadMessageCount) {
        return i;
      }
      break;
    }
    return null;
  }

  int _realMessageCount(List<V2TimMessage?> messageList) {
    var count = 0;
    for (final message in messageList) {
      if (_isRealChatMessage(message)) {
        count++;
      }
    }
    return count;
  }

  void _scheduleInitialUnreadAnchor(
    List<V2TimMessage?> messageList,
    int unreadMessageCount,
  ) {
    if (unreadMessageCount <= 0 || messageList.isEmpty) {
      return;
    }
    final convId = _conversationId();
    if (_initialUnreadAnchorConversationID == convId &&
        _initialUnreadAnchorCount == unreadMessageCount) {
      return;
    }
    if (_initialUnreadAnchorScheduled || _initialUnreadAnchorInFlight) {
      return;
    }
    if (_realMessageCount(messageList) < unreadMessageCount) {
      if (_initialUnreadAnchorAttempts < 30 && !_initialUnreadAnchorScheduled) {
        _initialUnreadAnchorAttempts++;
        _initialUnreadAnchorScheduled = true;
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          _initialUnreadAnchorScheduled = false;
          if (mounted) {
            _scheduleInitialUnreadAnchor(
              _visibleMessageList(widget.messageList),
              unreadMessageCount,
            );
          }
        });
      }
      return;
    }
    _initialUnreadAnchorScheduled = true;
    _initialUnreadAnchorInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initialUnreadAnchorScheduled = false;
      if (!mounted) {
        _initialUnreadAnchorInFlight = false;
        return;
      }
      try {
        await _scrollToFirstUnread(
          unreadMessageCount,
          preferTop: true,
          animate: false,
          stabilize: false,
        );
      } finally {
        _initialUnreadAnchorInFlight = false;
      }
    });
  }

  Future<void> _scrollToLatestUnread(
    int unreadMessageCount, {
    int attempt = 0,
  }) async {
    if (!mounted || unreadMessageCount <= 0) {
      return;
    }
    final contextMenuModel = _chatGlobalModel;
    if (contextMenuModel != null &&
        (contextMenuModel.isMessageContextMenuOverlayOpen ||
            contextMenuModel.isContextMenuViewportRestoreActive(
              _conversationId(),
            ))) {
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      if (attempt < 30) {
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          if (mounted) {
            _scrollToLatestUnread(unreadMessageCount, attempt: attempt + 1);
          }
        });
      }
      return;
    }
    try {
      await _autoScrollController.animateTo(
        position.minScrollExtent,
        duration: attempt == 0
            ? const Duration(milliseconds: 1)
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
      if (attempt < 2) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) {
            _scrollToLatestUnread(unreadMessageCount, attempt: attempt + 1);
          }
        });
      } else {
        _initialUnreadAnchorConversationID = _conversationId();
        _initialUnreadAnchorCount = unreadMessageCount;
        _initialUnreadAnchorAttempts = 0;
        _completedEntryUnreadCount = 0;
        final globalModel = Provider.of<TUIChatGlobalModel>(
          context,
          listen: false,
        );
        globalModel.setUnreadCountForTongue(unreadMessageCount, notify: false);
        globalModel.setUnreadTongueMetrics(
          conversationID: _conversationId(),
          remaining: unreadMessageCount,
          below: false,
          notify: true,
        );
        globalModel.setMessageListPosition(
          _conversationId(),
          HistoryMessagePosition.bottom,
          notify: false,
        );
      }
    } catch (_) {
      if (attempt < 30) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) {
            _scrollToLatestUnread(unreadMessageCount, attempt: attempt + 1);
          }
        });
      }
    }
  }

  Future<void> _scrollToFirstUnread(
    int unreadMessageCount, {
    bool preferTop = false,
    bool animate = true,
    bool stabilize = true,
    int attempt = 0,
  }) async {
    if (!mounted || unreadMessageCount <= 0) {
      return;
    }
    final messageList = _visibleMessageList(widget.messageList);
    final targetGlobalIndex = _firstUnreadGlobalIndex(
      messageList,
      unreadMessageCount,
    );
    if (targetGlobalIndex == null) {
      if (attempt < 30) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) {
          await _scrollToFirstUnread(
            unreadMessageCount,
            preferTop: preferTop,
            animate: animate,
            stabilize: stabilize,
            attempt: attempt + 1,
          );
        }
      }
      return;
    }
    if (_singleScrollPositionOrNull() == null) {
      if (attempt < 30) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          await _scrollToFirstUnread(
            unreadMessageCount,
            preferTop: preferTop,
            animate: animate,
            stabilize: stabilize,
            attempt: attempt + 1,
          );
        }
      }
      return;
    }
    try {
      final aligned = preferTop
          ? await _alignGlobalMessageIndexToViewportTop(
              targetGlobalIndex,
              animate: animate,
            )
          : await () async {
              ChatGeomSettleTrace.noteReason(
                'finding_scroll_to_index',
                extras: <String, Object?>{'index': -targetGlobalIndex},
              );
              return _autoScrollController
                  .scrollToIndex(
                    -targetGlobalIndex,
                    preferPosition: AutoScrollPosition.middle,
                  )
                  .then((_) => true)
                  .catchError((_) => false);
            }();
      if (!aligned) {
        if (attempt < 30) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (mounted) {
            await _scrollToFirstUnread(
              unreadMessageCount,
              preferTop: preferTop,
              animate: animate,
              stabilize: stabilize,
              attempt: attempt + 1,
            );
          }
        }
        return;
      }
      // 首次布局中图片/视频/长文本高度会在下一帧继续变化，补两次顶对齐，
      // 确保点击“xx条新消息”后稳定停在最早一条未读消息。
      if (stabilize && attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) {
          await _scrollToFirstUnread(
            unreadMessageCount,
            preferTop: preferTop,
            animate: animate,
            stabilize: stabilize,
            attempt: attempt + 1,
          );
        }
      } else {
        _initialUnreadAnchorConversationID = _conversationId();
        _initialUnreadAnchorCount = unreadMessageCount;
        _initialUnreadAnchorAttempts = 0;
        _completedEntryUnreadCount = 0;
        final globalModel = Provider.of<TUIChatGlobalModel>(
          context,
          listen: false,
        );
        _lastUnreadTongueConversationID = null;
        _lastUnreadTongueRemaining = null;
        _lastUnreadTongueSafeCount = 0;
        globalModel.setUnreadCountForTongue(unreadMessageCount, notify: false);
        globalModel.setUnreadTongueMetrics(
          conversationID: _conversationId(),
          remaining: unreadMessageCount,
          below: true,
          notify: false,
        );
        globalModel.setMessageListPosition(
          _conversationId(),
          HistoryMessagePosition.awayTwoScreen,
          notify: false,
        );
        _scheduleUnreadTongueMetricsUpdate(
          _visibleMessageList(widget.messageList),
          unreadMessageCount,
          force: true,
        );
      }
    } catch (_) {
      if (attempt < 30) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) {
          await _scrollToFirstUnread(
            unreadMessageCount,
            preferTop: preferTop,
            animate: animate,
            stabilize: stabilize,
            attempt: attempt + 1,
          );
        }
      }
    }
  }

  Future<bool> _scrollToUnreadAnchor(
    _UnreadMessageAnchor anchor, {
    int attempt = 0,
    bool triedSequenceLoad = false,
  }) async {
    if (!mounted || anchor.conversationID != _conversationId()) {
      return false;
    }
    final messageList = _currentVisibleMessageList();
    final targetGlobalIndex = _globalIndexForUnreadAnchor(messageList, anchor);
    if (targetGlobalIndex == null) {
      if (!triedSequenceLoad && anchor.seq != null && anchor.seq! > 0) {
        final loaded = await widget.model.loadListForSpecificMessage(
          seq: anchor.seq!,
        );
        if (loaded && mounted) {
          await WidgetsBinding.instance.endOfFrame;
          return _scrollToUnreadAnchor(
            anchor,
            attempt: attempt,
            triedSequenceLoad: true,
          );
        }
      }
      if (attempt < 8) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (mounted) {
          return _scrollToUnreadAnchor(
            anchor,
            attempt: attempt + 1,
            triedSequenceLoad: triedSequenceLoad,
          );
        }
      }
      return false;
    }
    return _jumpToFirstUnreadGlobalIndex(targetGlobalIndex);
  }

  Future<bool> _scrollToFirstUnreadFromTongue(int requestedUnreadCount) async {
    if (_unreadWindowJumpInFlight || !mounted) return false;
    _releaseAtJumpCenterOwnership();
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final convId = _conversationId();
    final previousPosition = globalModel.getMessageListPosition(convId);
    final previousOrigin = _entryUnreadOrigin;
    final previousPixels = _singleScrollPositionOrNull()?.pixels;
    final previousWindow = _currentVisibleMessageList();
    bool positioned = false;
    // Keep the current layout until the requested window supplies its anchor.
    _deferUnreadCenterPartition = true;
    _clearIncomingScrollAnchor(reason: 'jump_first_unread');
    final fallbackCount = requestedUnreadCount;
    if (fallbackCount <= 0) {
      return false;
    }
    _unreadWindowJumpInFlight = true;
    _cancelForcePinScroll();
    _abortViewportInsertSlideForSupersede();
    _lockSearchJumpStabilization(milliseconds: 4000);
    final transition = _windowTransitionKey.currentState;
    transition?.begin(showSpinner: true);
    _searchJumpRequest = globalModel.beginSearchJump(convId);
    final request = _searchJumpRequest;
    bool current() =>
        mounted &&
        _conversationId() == convId &&
        request == _searchJumpRequest &&
        _ownsSearchJumpRequest;
    globalModel.setMemoryWindowSuppressed(convId, true);
    // Match history-message navigation before installing the centered slivers.
    // Setting this only after success adds edge space after verification and
    // moves the target away from the position that was just checked.
    globalModel.setMessageListPosition(
      convId,
      HistoryMessagePosition.notShowLatest,
      notify: false,
    );
    _firstUnreadAnchorJumped = true;
    _unreadEntryBottomPinScheduled = true;
    if (mounted) {
      loadingPlace = LoadingPlace.top;
      setState(() {});
    }
    try {
      await waitForSearchJumpLayout();
      if (!current()) return false;
      final didScroll = await _jumpToFirstUnreadAroundWindow(fallbackCount);
      if (!current()) return false;
      if (!didScroll) {
        _firstUnreadAnchorJumped = false;
        _showCantFindFirstUnread();
        return false;
      }
      positioned = true;
      _initialUnreadAnchorConversationID = convId;
      _initialUnreadAnchorCount = fallbackCount;
      _initialUnreadAnchorAttempts = 0;
      globalModel.setMessageListPosition(
        convId,
        HistoryMessagePosition.awayTwoScreen,
        notify: false,
      );
      // 跳到首条未读后：清掉入口未读胶囊计数，避免右下角变成「xxx条新消息」。
      globalModel.releaseEntryUnreadReminder(convId);
      globalModel.markEntryUnreadTongueDismissed(
        conversationID: convId,
        unreadCount: fallbackCount,
        notify: false,
      );
      globalModel.clearUnreadTongueMetrics(convId, notify: true);
      globalModel.setSearchJumpStatus(convId, SearchJumpStatus.success,
          requestID: _searchJumpRequest, notify: true);
      return true;
    } catch (_) {
      if (current()) _showCantFindFirstUnread();
      return false;
    } finally {
      if (current() && globalModel.isSearchJumpPending(convId)) {
        globalModel.setSearchJumpStatus(convId, SearchJumpStatus.failed,
            requestID: _searchJumpRequest, notify: true);
        globalModel.setMemoryWindowSuppressed(convId, false);
      }
      if (current()) {
        loadingPlace = LoadingPlace.none;
        if (!positioned) {
          final list = _currentVisibleMessageList();
          final sameWindow = list.length == previousWindow.length &&
              list.asMap().entries.every((entry) =>
                  _stableMessageListKey(entry.value, entry.key) ==
                  _stableMessageListKey(previousWindow[entry.key], entry.key));
          _entryUnreadOrigin = previousOrigin != null &&
                  _globalIndexForAnchor(previousOrigin) != null
              ? previousOrigin
              : null;
          _firstUnreadAnchorJumped = _entryUnreadOrigin != null;
          _deferUnreadCenterPartition = true;
          _contextMenuFrozenLayoutUnreadCount = null;
          globalModel.setMessageListPosition(
              convId,
              sameWindow
                  ? previousPosition
                  : HistoryMessagePosition.notShowLatest,
              notify: false);
          setState(() {});
          await waitForSearchJumpLayout();
          if (current()) {
            final position = _singleScrollPositionOrNull();
            if (position != null && position.hasContentDimensions) {
              position.jumpTo((sameWindow ? previousPixels ?? 0 : 0)
                  .clamp(position.minScrollExtent, position.maxScrollExtent)
                  .toDouble());
            }
          }
        } else {
          setState(() {});
        }
      }
      await transition?.finish();
      _unreadWindowJumpInFlight = false;
      if (current()) {
        // Positioning has finished and the retained frame is gone. Release
        // the cooldown now, not several seconds into the user's next scroll.
        _searchJumpStabilizeUntilMs = 0;
        globalModel.setMemoryWindowSuppressed(convId, false);
      }
    }
  }

  void _showCantFindFirstUnread() {
    onTIMCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t("无法定位到首条未读"),
        infoCode: 6660401,
      ),
    );
  }

  Future<V2TimConversation> _conversationWithFreshReadCursor() async {
    final local = widget.conversation;
    final id = local.conversationID?.trim() ?? '';
    if (id.isEmpty) {
      return local;
    }
    try {
      final fresh = await serviceLocator<ConversationService>()
          .getConversation(
            conversationID: id,
          )
          .timeout(const Duration(seconds: 2));
      if (fresh == null) {
        return local;
      }
      // Prefer live read cursors from SDK; keep UI lastMessage if fresher.
      if ((fresh.groupReadSequence ?? 0) > 0) {
        local.groupReadSequence = fresh.groupReadSequence;
      }
      if ((fresh.c2cReadTimestamp ?? 0) > 0) {
        local.c2cReadTimestamp = fresh.c2cReadTimestamp;
      }
      if (fresh.lastMessage != null) {
        local.lastMessage = fresh.lastMessage;
      }
      return local;
    } catch (_) {
      return local;
    }
  }

  int? _newestMessageSeqForUnreadJump() {
    final list = _currentVisibleMessageList();
    for (final msg in list) {
      final seq = int.tryParse(msg?.seq?.trim() ?? '') ?? 0;
      if (seq > 0) {
        return seq;
      }
    }
    return int.tryParse(widget.conversation.lastMessage?.seq?.trim() ?? '');
  }

  void _logFirstUnreadJump(String event, Map<String, Object?> extras) {
    // 入口未读跳转诊断日志默认关闭，避免刷屏。
    if (!ChatHistoryTrace.enabled) {
      return;
    }
    final buffer = StringBuffer('[FirstUnreadJump] event=$event');
    extras.forEach((key, value) {
      if (value == null) {
        return;
      }
      buffer.write(' $key=$value');
    });
    // ignore: avoid_print
    print(buffer.toString());
    ChatHistoryTrace.log(
      event,
      conversationID: _conversationId(),
      extras: extras,
    );
  }

  Future<bool> _jumpToFirstUnreadAroundWindow(int fallbackCount) async {
    final request = _searchJumpRequest;
    final conversationID = _conversationId();
    bool current() =>
        mounted &&
        conversationID == _conversationId() &&
        request == _searchJumpRequest &&
        _ownsSearchJumpRequest;
    // C2C must start from the entry snapshot, never a freshly advanced read
    // timestamp or a random per-sender seq. Only the clicked target window is published.
    if (widget.conversation.type == 1) {
      final last = widget.model.entryUnreadLastMessage;
      if (last == null) return false;
      final target = await EntryUnreadLocator.find(
        unreadCount: fallbackCount,
        latestAtEntry: last,
        isCurrent: current,
        older: (cursor) => MessageHistoryAroundLoader.loadSide(
          isGroup: false,
          newer: false,
          targetSeq: 0,
          targetMsgID: cursor.msgID,
          targetMessage: cursor,
          read: (type, {required lastMsgSeq, lastMsgID, lastMsg}) =>
              widget.model.globalModel.getHistoryMessageListThroughIm06(
                  userID: _conversationId(),
                  count: 80,
                  getType: type,
                  lastMsgID: lastMsgID,
                  lastMsg: lastMsg,
                  lastMsgSeq: -1),
        ),
      );
      if (!current() || target == null) return false;
      final anchor =
          MessageAnchor.fromConversationMessage(widget.conversation, target);
      final loaded = await widget.model
          .loadListForSpecificMessage(
              anchor: anchor, targetMessage: target, searchJumpRequest: request)
          .timeout(const Duration(seconds: 12));
      if (!current() || !loaded) return false;
      await waitForSearchJumpLayout();
      if (!current()) return false;
      final index = _globalIndexForAnchor(anchor);
      return index != null && await _finishFirstUnreadJump(index);
    }
    final lockedSeq =
        widget.model.globalModel.lockedFirstUnreadSeqFor(conversationID);
    // Entry unread is frozen before mark-read. A fresh read cursor cannot
    // improve an already locked anchor, and adds a network round trip.
    final conversation = lockedSeq > 0
        ? widget.conversation
        : await _conversationWithFreshReadCursor();
    if (!current()) {
      return false;
    }
    final isGroup = conversation.type != 1;
    final last =
        widget.model.entryUnreadLastMessage ?? conversation.lastMessage;
    final lastSeq = int.tryParse(last?.seq?.trim() ?? '') ??
        _newestMessageSeqForUnreadJump();
    final target = FirstUnreadJump.resolve(
      unreadCount: fallbackCount,
      isGroup: isGroup,
      groupReadSequence: conversation.groupReadSequence,
      c2cReadTimestamp: conversation.c2cReadTimestamp,
      lastMessageSeq: lastSeq,
      lastMessageTimestamp: last?.timestamp,
      lockedFirstUnreadSeq: lockedSeq > 0 ? lockedSeq : null,
    );
    _logFirstUnreadJump('entry_unread_jump_begin', <String, Object?>{
      'unread': fallbackCount,
      'isGroup': isGroup,
      'strategy': target?.strategy,
      'seq': target?.seq,
      'readTs': target?.timestampSec,
      'groupReadSeq': conversation.groupReadSequence,
      'c2cReadTs': conversation.c2cReadTimestamp,
      'lastSeq': lastSeq,
      'lockedSeq': lockedSeq,
    });
    if (target == null) {
      _logFirstUnreadJump('entry_unread_jump_no_target', <String, Object?>{
        'unread': fallbackCount,
        'isGroup': isGroup,
        'groupReadSeq': conversation.groupReadSequence,
        'lastSeq': lastSeq,
        'lockedSeq': lockedSeq,
      });
      return false;
    }

    int? targetGlobalIndex;
    if ((target.strategy == 'group_read_seq' ||
            target.strategy == 'seq_from_unread' ||
            target.strategy == 'locked_seq') &&
        target.seq != null) {
      final readSeq = target.groupReadCursorSeq ?? 0;
      // Install the same around-message window as history search, including
      // when the latest page happens to contain this seq. This establishes
      // paging/positioning state before computing the target's visible index.
      final loaded = await widget.model
          .loadListForSpecificMessage(
            seq: target.seq!,
            searchJumpRequest: request,
          )
          .timeout(const Duration(seconds: 12));
      if (!current()) {
        return false;
      }
      if (!loaded) {
        _logFirstUnreadJump('entry_unread_jump_load_fail', <String, Object?>{
          'seq': target.seq,
          'strategy': target.strategy,
        });
        return false;
      }
      // 整窗替换后等两帧，再按 seq 重定位（勿沿用替换前的最新页 index）。
      await waitForSearchJumpLayout();
      if (!current()) {
        return false;
      }
      await waitForSearchJumpLayout();
      if (!current()) {
        return false;
      }
      targetGlobalIndex = _globalIndexForSeq(target.seq!.toString());
      final oldestAfterLoad = _oldestLoadedSeqInWindow();
      if (targetGlobalIndex == null &&
          oldestAfterLoad != null &&
          oldestAfterLoad <= target.seq!) {
        targetGlobalIndex = _globalIndexForFirstUnreadAfterSeq(readSeq);
      }
      // Closest is only OK within a small seq neighborhood of the target.
      final closest = _globalIndexForClosestSeq(
        target.seq!,
        preferAtOrAfter: true,
      );
      if (targetGlobalIndex == null && closest != null) {
        final closestSeq = int.tryParse(
              _currentVisibleMessageList()[closest]?.seq?.trim() ?? '',
            ) ??
            0;
        if (closestSeq > 0 && (closestSeq - target.seq!).abs() <= 20) {
          targetGlobalIndex = closest;
        }
      }
      _logFirstUnreadJump(
        'entry_unread_jump_after_replace',
        <String, Object?>{
          'seq': target.seq,
          'index': targetGlobalIndex,
          'listLen': _currentVisibleMessageList().length,
          'oldestSeq': oldestAfterLoad,
          'newestSeq': _newestLoadedSeqInWindow(),
        },
      );
      if (targetGlobalIndex == null) {
        _logFirstUnreadJump(
          'entry_unread_jump_index_missing',
          <String, Object?>{
            'seq': target.seq,
            'listLen': _currentVisibleMessageList().length,
            'oldestSeq': _oldestLoadedSeqInWindow(),
          },
        );
        return false;
      }
      final landedSeq = int.tryParse(
            _currentVisibleMessageList()[targetGlobalIndex]?.seq?.trim() ?? '',
          ) ??
          0;
      if (landedSeq > 0 && (landedSeq - target.seq!).abs() > 50) {
        _logFirstUnreadJump(
          'entry_unread_jump_landed_too_far',
          <String, Object?>{
            'wantSeq': target.seq,
            'landedSeq': landedSeq,
            'index': targetGlobalIndex,
          },
        );
        return false;
      }
      return _finishFirstUnreadJump(
        targetGlobalIndex,
        preferSeq: target.seq!.toString(),
      );
    }

    if (target.strategy == 'c2c_read_ts' && target.timestampSec != null) {
      final readTs = target.timestampSec!;
      targetGlobalIndex = _globalIndexForFirstUnreadAfterTimestamp(readTs);
      if (targetGlobalIndex != null) {
        return _finishFirstUnreadJump(targetGlobalIndex);
      }
      // 无按时间 around API：仅小未读允许 count_fallback 追翻。
      if (fallbackCount > FirstUnreadJump.maxCountFallbackUnread) {
        _logFirstUnreadJump(
          'entry_unread_jump_c2c_too_large',
          <String, Object?>{'unread': fallbackCount, 'readTs': readTs},
        );
        return false;
      }
    }

    if (target.strategy == 'count_fallback' ||
        target.strategy == 'c2c_read_ts') {
      if (fallbackCount > FirstUnreadJump.maxCountFallbackUnread) {
        return false;
      }
      _firstUnreadAnchor = null;
      final anchor = await _ensureFirstUnreadAnchor(fallbackCount);
      if (anchor != null) {
        targetGlobalIndex = _globalIndexForUnreadAnchor(
          _currentVisibleMessageList(),
          anchor,
        );
      }
      targetGlobalIndex ??= _firstUnreadGlobalIndex(
        _currentVisibleMessageList(),
        fallbackCount,
      );
      if (targetGlobalIndex == null) {
        return false;
      }
      return _finishFirstUnreadJump(targetGlobalIndex);
    }

    return false;
  }

  int? _oldestLoadedSeqInWindow() {
    final list = _currentVisibleMessageList();
    int? oldest;
    for (final msg in list) {
      if (!_isUnreadAnchorMessage(msg)) {
        continue;
      }
      final seq = int.tryParse(msg?.seq?.trim() ?? '') ?? 0;
      if (seq <= 0) {
        continue;
      }
      if (oldest == null || seq < oldest) {
        oldest = seq;
      }
    }
    return oldest;
  }

  int? _newestLoadedSeqInWindow() {
    final list = _currentVisibleMessageList();
    int? newest;
    for (final msg in list) {
      if (!_isUnreadAnchorMessage(msg)) {
        continue;
      }
      final seq = int.tryParse(msg?.seq?.trim() ?? '') ?? 0;
      if (seq <= 0) {
        continue;
      }
      if (newest == null || seq > newest) {
        newest = seq;
      }
    }
    return newest;
  }

  int? _globalIndexForClosestSeq(
    int targetSeq, {
    bool preferAtOrAfter = false,
  }) {
    final messageList = _currentVisibleMessageList();
    int? bestIndex;
    var bestDelta = 1 << 30;
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      final seq = int.tryParse(message?.seq?.trim() ?? '') ?? 0;
      if (seq <= 0) {
        continue;
      }
      if (preferAtOrAfter && seq < targetSeq) {
        continue;
      }
      final delta = (seq - targetSeq).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    if (bestIndex != null) {
      return bestIndex;
    }
    // Fallback: any closest seq (including older).
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      final seq = int.tryParse(message?.seq?.trim() ?? '') ?? 0;
      if (seq <= 0) {
        continue;
      }
      final delta = (seq - targetSeq).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<bool> _finishFirstUnreadJump(
    int targetGlobalIndex, {
    String? preferSeq,
  }) async {
    final request = _searchJumpRequest;
    final conversationID = _conversationId();
    bool current() =>
        mounted &&
        _conversationId() == conversationID &&
        request == _searchJumpRequest &&
        _ownsSearchJumpRequest;
    if (!current()) return false;
    final list = _currentVisibleMessageList();
    String? anchorMsgID;
    String? anchorSeq;
    if (targetGlobalIndex >= 0 && targetGlobalIndex < list.length) {
      final msg = list[targetGlobalIndex];
      anchorMsgID = msg?.msgID;
      anchorSeq = msg?.seq?.trim();
    }
    anchorSeq ??= preferSeq?.trim();

    if (targetGlobalIndex < 0 ||
        targetGlobalIndex >= list.length ||
        list[targetGlobalIndex] == null) return false;
    final targetAnchor = MessageAnchor.fromConversationMessage(
        widget.conversation, list[targetGlobalIndex]!);
    setState(() {
      _entryUnreadOrigin = targetAnchor;
      _deferUnreadCenterPartition = false;
    });
    await waitForSearchJumpLayout();
    if (!current()) return false;
    final generation = ++_searchJumpGeneration;
    final didScroll = await _centerOnGlobalIndex(targetGlobalIndex,
        target: _SearchJumpTarget(
            resolveIndex: () => _globalIndexForAnchor(targetAnchor)),
        generation: generation);
    if (!current()) return false;
    if (didScroll) {
      final matched = _messageForAnchor(targetAnchor);
      final jumpId =
          matched == null ? targetAnchor.stableKey : _messageIdentity(matched);
      if (jumpId.isNotEmpty) widget.model.jumpMsgID = jumpId;
      _releaseSearchJumpMemoryWindowSuppress(
        anchorMsgID: anchorMsgID,
        anchorSeq: anchorSeq,
      );
      _logFirstUnreadJump('entry_unread_jump_success', <String, Object?>{
        'index': targetGlobalIndex,
        'msgID': anchorMsgID,
        'seq': anchorSeq,
        'haveMoreData': widget.model.haveMoreData,
        'haveMoreLatestData': widget.model.haveMoreLatestData,
      });
    } else {
      _logFirstUnreadJump('entry_unread_jump_scroll_fail', <String, Object?>{
        'index': targetGlobalIndex,
        'seq': anchorSeq,
        'listLen': _currentVisibleMessageList().length,
      });
    }
    return didScroll;
  }

  int? _globalIndexForFirstUnreadAfterSeq(int readSeq) {
    if (readSeq <= 0) {
      return null;
    }
    final messageList = _currentVisibleMessageList();
    int? bestIndex;
    int? bestSeq;
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      final seq = int.tryParse(message?.seq?.trim() ?? '');
      if (seq == null || seq <= readSeq) {
        continue;
      }
      if (bestSeq == null || seq < bestSeq) {
        bestSeq = seq;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int? _globalIndexForFirstUnreadAfterTimestamp(int readTs) {
    if (readTs <= 0) {
      return null;
    }
    final messageList = _currentVisibleMessageList();
    int? bestIndex;
    int? bestTs;
    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      if (!_isUnreadAnchorMessage(message)) {
        continue;
      }
      final ts = message?.timestamp;
      if (ts == null || ts <= readTs) {
        continue;
      }
      if (bestTs == null || ts < bestTs) {
        bestTs = ts;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  bool _canPrependUnreadHead({
    required List<V2TimMessage?> messageList,
    required int unreadEndPoint,
    required int delta,
    required String? lastMsgKey,
    required int restoreVersion,
    required int messageListRevision,
  }) {
    if (delta <= 0 || _cacheMessageListLen <= 0) {
      return false;
    }
    if (unreadEndPoint != _cacheUnreadEndPoint + delta) {
      return false;
    }
    if (unreadEndPoint > messageList.length) {
      return false;
    }
    if (lastMsgKey != _cacheLastMsgKey) {
      return false;
    }
    if (_cacheRestoreVersion != restoreVersion) {
      return false;
    }
    if (_cacheMessageListRevision != messageListRevision) {
      return false;
    }
    if (_cachedReadList.length != messageList.length - unreadEndPoint) {
      return false;
    }
    for (var i = 0; i < _cachedReadList.length; i++) {
      final previous = _cachedReadList[i];
      final next = messageList[unreadEndPoint + i];
      if (identical(previous, next)) {
        continue;
      }
      if (previous?.elemType == 11 &&
          next?.elemType == 11 &&
          previous!.timestamp == next!.timestamp) {
        continue;
      }
      return false;
    }
    return true;
  }

  void _rebuildListPartitionsIfNeeded({
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required int unreadEndPoint,
    required int restoreVersion,
    required int messageListRevision,
    required String Function(V2TimMessage? message, int index)
        getMessageIdentifier,
  }) {
    final lastMsg = messageList.isNotEmpty ? messageList.last : null;
    final lastMsgKey =
        lastMsg == null ? null : getMessageIdentifier(lastMsg, 0);
    final headMsg = messageList.isNotEmpty ? messageList.first : null;
    final headMsgKey =
        headMsg == null ? null : getMessageIdentifier(headMsg, 0);
    final listStateKey = _listStateCacheKey(messageList);
    if (_cacheMessageListLen == messageList.length &&
        _cacheUnreadCount == safeUnreadCount &&
        _cacheUnreadEndPoint == unreadEndPoint &&
        _cacheLastMsgKey == lastMsgKey &&
        _cacheHeadMsgKey == headMsgKey &&
        _cacheListStateKey == listStateKey &&
        _cacheRestoreVersion == restoreVersion &&
        _cacheMessageListRevision == messageListRevision) {
      return;
    }
    final delta = messageList.length - _cacheMessageListLen;
    if (_canPrependUnreadHead(
      messageList: messageList,
      unreadEndPoint: unreadEndPoint,
      delta: delta,
      lastMsgKey: lastMsgKey,
      restoreVersion: restoreVersion,
      messageListRevision: messageListRevision,
    )) {
      _cachedUnreadList = List<V2TimMessage?>.unmodifiable(
        unreadEndPoint == 0
            ? const <V2TimMessage?>[]
            : messageList.sublist(0, unreadEndPoint).reversed,
      );
      _unreadIndexMap = {};
      for (var i = 0; i < _cachedUnreadList.length; i++) {
        _unreadIndexMap[getMessageIdentifier(_cachedUnreadList[i], 0)] = i;
      }
      _globalIndexMap = {};
      _globalMessageIdentityIndexMap = {};
      for (var i = 0; i < messageList.length; i++) {
        _globalIndexMap[getMessageIdentifier(messageList[i], i)] = i;
        final message = messageList[i];
        if (message != null && message.elemType != 11) {
          final identity = _messageIdentity(message);
          if (identity.isNotEmpty) {
            _globalMessageIdentityIndexMap[identity] = i;
          }
        }
      }
      ChatJitterDiag.log(
        'partition_incremental_unread_head',
        extras: <String, Object?>{
          'delta': delta,
          'unreadLen': _cachedUnreadList.length,
          'readLen': _cachedReadList.length,
          'rev': messageListRevision,
        },
      );
      _cacheRestoreVersion = restoreVersion;
      _cacheMessageListRevision = messageListRevision;
      _cacheMessageListLen = messageList.length;
      _cacheUnreadCount = safeUnreadCount;
      _cacheUnreadEndPoint = unreadEndPoint;
      _cacheLastMsgKey = lastMsgKey;
      _cacheHeadMsgKey = headMsgKey;
      _cacheListStateKey = listStateKey;
      return;
    }
    final canAppendReadTail = delta > 0 &&
        _cacheMessageListLen > 0 &&
        _cacheHeadMsgKey != null &&
        headMsgKey == _cacheHeadMsgKey &&
        _cacheUnreadCount == safeUnreadCount &&
        _cacheUnreadEndPoint == unreadEndPoint &&
        unreadEndPoint <= _cacheMessageListLen &&
        _cacheListStateKey == listStateKey &&
        _cacheRestoreVersion == restoreVersion &&
        retainsMessagePartitionPrefix(
          current: messageList,
          unread: _cachedUnreadList,
          read: _cachedReadList,
        );
    if (canAppendReadTail) {
      final appended = messageList.sublist(
        _cacheMessageListLen,
        messageList.length,
      );
      final readStartInCache = _cachedReadList.length;
      // Do not mutate the list captured by the previous Sliver delegate.
      // Even a tail-only addAll changes the delegate's closure-visible data
      // between layout passes. Publish a new immutable snapshot instead.
      _cachedReadList = List<V2TimMessage?>.unmodifiable(<V2TimMessage?>[
        ..._cachedReadList,
        ...appended,
      ]);
      for (var i = 0; i < appended.length; i++) {
        final globalIndex = _cacheMessageListLen + i;
        final message = appended[i];
        final stableKey = getMessageIdentifier(message, globalIndex);
        _readIndexMap[stableKey] = readStartInCache + i;
        _globalIndexMap[stableKey] = globalIndex;
        if (message != null && message.elemType != 11) {
          final identity = _messageIdentity(message);
          if (identity.isNotEmpty) {
            _globalMessageIdentityIndexMap[identity] = globalIndex;
          }
        }
      }
      ChatJitterDiag.log(
        'partition_incremental_tail',
        extras: <String, Object?>{
          'delta': delta,
          'readLen': _cachedReadList.length,
          'rev': messageListRevision,
        },
      );
      _cacheRestoreVersion = restoreVersion;
      _cacheMessageListRevision = messageListRevision;
      _cacheMessageListLen = messageList.length;
      _cacheUnreadCount = safeUnreadCount;
      _cacheUnreadEndPoint = unreadEndPoint;
      _cacheLastMsgKey = lastMsgKey;
      _cacheHeadMsgKey = headMsgKey;
      _cacheListStateKey = listStateKey;
      return;
    }
    final changed = <String>[];
    if (_cacheMessageListLen != messageList.length) {
      changed.add('len:$_cacheMessageListLen→${messageList.length}');
    }
    if (_cacheUnreadCount != safeUnreadCount) {
      changed.add('unread:$_cacheUnreadCount→$safeUnreadCount');
    }
    if (_cacheLastMsgKey != lastMsgKey) {
      changed.add('lastMsg');
    }
    if (_cacheListStateKey != listStateKey) {
      changed.add('listState');
    }
    if (_cacheRestoreVersion != restoreVersion) {
      changed.add('restore:$_cacheRestoreVersion→$restoreVersion');
    }
    if (_cacheMessageListRevision != messageListRevision) {
      changed.add('rev:$_cacheMessageListRevision→$messageListRevision');
    }
    ChatJitterDiag.log(
      'partition_cache_miss',
      extras: <String, Object?>{
        'changed': changed.join(','),
        'rev': messageListRevision,
        'unread': safeUnreadCount,
        'len': messageList.length,
      },
    );
    _cacheRestoreVersion = restoreVersion;
    _cacheMessageListRevision = messageListRevision;
    _cacheMessageListLen = messageList.length;
    _cacheUnreadCount = safeUnreadCount;
    _cacheUnreadEndPoint = unreadEndPoint;
    _cacheLastMsgKey = lastMsgKey;
    _cacheHeadMsgKey = headMsgKey;
    _cacheListStateKey = listStateKey;
    _cachedUnreadList = List<V2TimMessage?>.unmodifiable(
      unreadEndPoint == 0
          ? const <V2TimMessage?>[]
          : messageList.sublist(0, unreadEndPoint).reversed,
    );
    _cachedReadList = List<V2TimMessage?>.unmodifiable(
      messageList.sublist(unreadEndPoint, messageList.length),
    );
    ChatHistoryTrace.log(
      'render_partitions_rebuilt',
      conversationID: _conversationId(),
      extras: <String, Object?>{
        ...?_chatGlobalModel?.historyProjectionDiagnostics(_conversationId()),
        'messageListLen': messageList.length,
        'safeUnreadCount': safeUnreadCount,
        'unreadEndPoint': unreadEndPoint,
        'unreadLen': _cachedUnreadList.length,
        'readLen': _cachedReadList.length,
        'messageListRevision': messageListRevision,
        'restoreVersion': restoreVersion,
        'listStateKey': listStateKey,
      },
    );
    _unreadIndexMap = {};
    for (var i = 0; i < _cachedUnreadList.length; i++) {
      _unreadIndexMap[getMessageIdentifier(_cachedUnreadList[i], 0)] = i;
    }
    _readIndexMap = {};
    for (var i = 0; i < _cachedReadList.length; i++) {
      _readIndexMap[getMessageIdentifier(_cachedReadList[i], 0)] = i;
    }
    _logRenderedReadOrder();
    _globalIndexMap = {};
    _globalMessageIdentityIndexMap = {};
    for (var i = 0; i < messageList.length; i++) {
      _globalIndexMap[getMessageIdentifier(messageList[i], i)] = i;
      final message = messageList[i];
      if (message != null && message.elemType != 11) {
        final identity = _messageIdentity(message);
        if (identity.isNotEmpty) {
          _globalMessageIdentityIndexMap[identity] = i;
        }
      }
    }
  }

  /// Logs the exact order the read partition will render, which is what the
  /// user actually sees. `_cachedReadList` is newest-first (index 0 is painted
  /// at the bottom in the reversed viewport). Compare this with the
  /// `[IM_SEND_ORDER]` logs: if this order is correct but the screen looks
  /// wrong, the problem is Flutter element recycling, not the data pipeline.
  void _logRenderedReadOrder() {
    if (!ChatJitterDiag.enabled) {
      return;
    }
    final list = _cachedReadList;
    if (list.isEmpty) {
      return;
    }
    final buffer = StringBuffer();
    final scanEnd = list.length > 8 ? 8 : list.length;
    for (var i = 0; i < scanEnd; i++) {
      final message = list[i];
      if (message == null) {
        buffer.write('#$i=null;');
        continue;
      }
      if (message.elemType == 11) {
        buffer.write('#$i=divider;');
        continue;
      }
      final tag = message.msgID?.trim().isNotEmpty == true
          ? message.msgID!.trim()
          : (message.id?.trim() ?? '');
      buffer.write(
        '#$i seq=${message.seq ?? ''} ts=${message.timestamp ?? ''} '
        'st=${message.status ?? ''} key=${_stableMessageListKey(message, i)} '
        'tag=$tag;',
      );
    }
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[IM_RENDER_ORDER] conv=${_conversationId()} readLen=${list.length} '
        'bottomUp=$buffer',
      );
    }
    final position = _singleScrollPositionOrNull();
    ChatJitterDiag.logListRebuild(
      reason: 'im_render_order',
      readLen: list.length,
      scrollPixels: position?.hasPixels == true ? position!.pixels : null,
      maxExtent: position?.hasContentDimensions == true
          ? position!.maxScrollExtent
          : null,
      spacer: _routeScroll.shortHistoryBottomSpacerHeight,
      caller: ChatJitterDiag.compactStack(),
    );
  }

  bool _isShortHistoryTopAlignmentBlocked(int safeUnreadCount) {
    return safeUnreadCount > 0 ||
        findingMsg != null ||
        findingAnchor != null ||
        widget.initFindingMsg != null ||
        widget.searchJumpAnchor != null ||
        _atJumpOrigin != null;
  }

  bool _isKeyboardInsetActive(BuildContext context) {
    final coordinator = KeyboardViewportTransitionCoordinator.active ??
        KeyboardTransitionScope.maybeOf(context);
    if (coordinator == null) {
      return false;
    }
    return coordinator.isAnimating;
  }

  void _clearShortHistoryAlignmentLatch() {
    ChatGeomSettleTrace.noteReason(
      'short_history_latch_clear',
      extras: <String, Object?>{
        'prevSpacer':
            _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(1),
        'prevContentH': _routeScroll.shortHistoryContentHeight.toStringAsFixed(
          1,
        ),
      },
    );
    _routeScroll.clearShortHistoryAlignmentLatch();
  }

  /// 短历史吃 spacer「估高成功」后的溢出兜底：自消息实测仍超视口时退出顶部对齐并贴底。
  void _breakShortHistoryIfOutgoingOverflowsViewport() {
    if (!_routeScroll.shortHistoryAlignmentLatched &&
        _routeScroll.shortHistoryBottomSpacerHeight <= 0) {
      return;
    }
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    final messageList = globalModel.getMessageList(_conversationId()) ??
        const <V2TimMessage?>[];
    final viewport = _resolvedShortHistoryViewportForDecision(context);
    if (!_contentExceedsShortHistoryViewport(
      messageList: messageList,
      viewportHeight: viewport,
      context: context,
    )) {
      return;
    }
    ChatJitterDiag.logInboundFlow(
      action: 'short_history_outgoing_overflow_break',
      conv: _conversationId(),
      extras: <String, Object?>{
        'viewport': viewport.toStringAsFixed(1),
        'spacer': _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(
          1,
        ),
      },
    );
    _clearShortHistoryAlignmentLatch();
    _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert = true;
    _scheduleForcePinScrollToBottom();
  }

  /// 新消息进入顶部对齐的短历史时，按新行估高收缩底部 spacer，
  /// 让消息原地接在最后一条下方、保持顶部锚定。返回 false 表示
  /// 内容已放不进视口（或状态不满足），应回落为贴底布局。
  /// 估高误差由下一帧的实测测量（_maybeScheduleShortHistoryTopAlignment）
  /// 自行校正。
  bool _absorbInsertedRowsIntoShortHistorySpacer(
    List<V2TimMessage> insertedMessages, {
    int insertedTipRows = 0,
  }) {
    if (!_routeScroll.shortHistoryAlignmentLatched &&
        _routeScroll.shortHistoryBottomSpacerHeight <= 0) {
      return false;
    }
    var insertedHeight = 0.0;
    for (final message in insertedMessages) {
      if (message.elemType == 11) {
        insertedHeight += _shortHistoryTimeDividerEstimatedRowHeight;
        continue;
      }
      final cachedHeight = ChatMessageHeightCache.instance.heightFor(message);
      if (cachedHeight != null && cachedHeight > 0) {
        insertedHeight += cachedHeight;
        continue;
      }
      insertedHeight +=
          ChatMessageHeightCache.instance.estimateRowHeight(message) ??
              (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS
                  ? _shortHistoryGroupTipsEstimatedRowHeight
                  : _shortHistoryMessageEstimatedRowHeight);
    }
    if (insertedTipRows > 0) {
      insertedHeight +=
          insertedTipRows * _shortHistoryTimeDividerEstimatedRowHeight;
    }
    if (insertedHeight <= 0) {
      return true;
    }
    final next = _routeScroll.shortHistoryBottomSpacerHeight - insertedHeight;
    // 仅「装不下」才失败：spacer 吃到 0 仍算成功（刚好铺满），不要提前上推。
    if (next < 0) {
      return false;
    }
    _assignShortHistorySpacer(
      next <= 1 ? 0.0 : next,
      reason: 'spacer_absorb_insert',
    );
    _routeScroll.shortHistoryAlignmentLatched = true;
    if (_routeScroll.shortHistoryContentHeight >= 0) {
      _assignShortHistoryContentHeight(
        _routeScroll.shortHistoryContentHeight + insertedHeight,
        reason: 'content_h_absorb_insert_add',
      );
    } else {
      _assignShortHistoryContentHeight(
        insertedHeight,
        reason: 'content_h_absorb_insert',
      );
    }
    return true;
  }

  /// reveal 后暖开归档/云补导致的中间插入或缩窗：用 Δcontent 对冲 spacer，钉住 tip。
  _AsyncSpacerAbsorbResult _absorbAsyncHistoryListChangeIntoShortSpacer({
    required List<V2TimMessage?> oldList,
    required List<V2TimMessage?> newList,
  }) {
    if (!_routeScroll.shortHistoryAlignmentLatched &&
        _routeScroll.shortHistoryBottomSpacerHeight <= 0) {
      return _AsyncSpacerAbsorbResult.skipped;
    }
    final oldKeys = <String>{};
    for (var i = 0; i < oldList.length; i++) {
      final message = oldList[i];
      if (message == null) {
        continue;
      }
      oldKeys.add(_asyncHistoryIdentityKey(message, i));
    }
    final newKeys = <String>{};
    for (var i = 0; i < newList.length; i++) {
      final message = newList[i];
      if (message == null) {
        continue;
      }
      newKeys.add(_asyncHistoryIdentityKey(message, i));
    }
    var addedHeight = 0.0;
    for (var i = 0; i < newList.length; i++) {
      final message = newList[i];
      if (message == null) {
        continue;
      }
      final key = _asyncHistoryIdentityKey(message, i);
      if (oldKeys.contains(key)) {
        continue;
      }
      addedHeight += _estimateShortHistoryRowHeight(message);
    }
    var removedHeight = 0.0;
    for (var i = 0; i < oldList.length; i++) {
      final message = oldList[i];
      if (message == null) {
        continue;
      }
      final key = _asyncHistoryIdentityKey(message, i);
      if (newKeys.contains(key)) {
        continue;
      }
      removedHeight += _estimateShortHistoryRowHeight(message);
    }
    final deltaContent = addedHeight - removedHeight;
    if (deltaContent.abs() < 0.5) {
      return _AsyncSpacerAbsorbResult.skipped;
    }
    final prevSpacer = _routeScroll.shortHistoryBottomSpacerHeight;
    final nextSpacer = prevSpacer - deltaContent;
    if (nextSpacer < 0) {
      return _AsyncSpacerAbsorbResult.overflow;
    }
    final reason = deltaContent > 0
        ? 'short_spacer_absorb_async_grow'
        : 'short_spacer_absorb_async_shrink';
    _assignShortHistorySpacer(
      nextSpacer <= 1 ? 0.0 : nextSpacer,
      reason: reason,
    );
    _routeScroll.shortHistoryAlignmentLatched = true;
    if (_routeScroll.shortHistoryContentHeight >= 0) {
      _assignShortHistoryContentHeight(
        (_routeScroll.shortHistoryContentHeight + deltaContent)
            .clamp(0.0, double.infinity)
            .toDouble(),
        reason: '${reason}_content_h',
      );
    }
    ChatGeomSettleTrace.noteReason(
      reason,
      extras: <String, Object?>{
        'oldLen': oldList.length,
        'newLen': newList.length,
        'addedH': addedHeight.toStringAsFixed(1),
        'removedH': removedHeight.toStringAsFixed(1),
        'deltaContent': deltaContent.toStringAsFixed(1),
        'prevSpacer': prevSpacer.toStringAsFixed(1),
        'nextSpacer':
            _routeScroll.shortHistoryBottomSpacerHeight.toStringAsFixed(1),
      },
    );
    return _AsyncSpacerAbsorbResult.ok;
  }

  String _asyncHistoryIdentityKey(V2TimMessage message, int index) {
    final msgId = message.msgID?.trim() ?? '';
    if (msgId.isNotEmpty) {
      return 'msgid_$msgId';
    }
    return _stableMessageListKey(message, index);
  }

  double _estimateShortHistoryRowHeight(V2TimMessage message) {
    if (message.elemType == 11) {
      return _shortHistoryTimeDividerEstimatedRowHeight;
    }
    final cachedHeight = ChatMessageHeightCache.instance.heightFor(message);
    if (cachedHeight != null && cachedHeight > 0) {
      return cachedHeight;
    }
    return ChatMessageHeightCache.instance.estimateRowHeight(message) ??
        (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS
            ? _shortHistoryGroupTipsEstimatedRowHeight
            : _shortHistoryMessageEstimatedRowHeight);
  }

  void _updateShortHistoryBaselineViewport(double viewportHeight) {
    if (viewportHeight > 0 && !_isKeyboardInsetActive(context)) {
      _routeScroll.shortHistoryBaselineViewportHeight = viewportHeight;
    }
  }

  void _tryLatchShortHistoryAlignment({
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required double viewportHeight,
    required BuildContext context,
  }) {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      if (_routeScroll.shortHistoryAlignmentLatched ||
          _routeScroll.shortHistoryBottomSpacerHeight > 0) {
        _clearShortHistoryAlignmentLatch();
      }
      return;
    }
    if (_isShortHistoryTopAlignmentBlocked(safeUnreadCount)) {
      _clearShortHistoryAlignmentLatch();
      return;
    }
    if (_contentExceedsShortHistoryViewport(
      messageList: messageList,
      viewportHeight: viewportHeight,
      context: context,
    )) {
      // 键盘动画中视口会瞬时变矮：清 latch 后再 re-prime 会造成 211↔379 大跳。
      if (_isKeyboardInsetActive(context) ||
          _routeScroll.shortHistoryAlignmentLatched) {
        return;
      }
      _clearShortHistoryAlignmentLatch();
      return;
    }
    if (_shouldAlignShortHistoryToTop(
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: viewportHeight,
      context: context,
    )) {
      _routeScroll.shortHistoryAlignmentLatched = true;
      _updateShortHistoryBaselineViewport(viewportHeight);
    } else if (!_routeScroll.shortHistoryAlignmentLatched) {
      _clearShortHistoryAlignmentLatch();
    }
  }

  bool _contentExceedsShortHistoryViewport({
    required List<V2TimMessage?> messageList,
    required double viewportHeight,
    required BuildContext context,
    double? measuredContentHeight,
  }) {
    if (viewportHeight <= 0) {
      return false;
    }
    final verticalPadding = _resolvedHistoryListVerticalPadding(context);
    var contentHeight = measuredContentHeight ?? -1.0;
    if (contentHeight < 0) {
      final tilesHeight = _visibleHistoryTilesHeight(
        expectedMessageCount: _shortHistoryTileCount(messageList),
      );
      if (tilesHeight >= 0) {
        contentHeight = tilesHeight;
      }
    }
    if (contentHeight < 0) {
      contentHeight = _resolvedShortHistoryContentHeight(messageList);
    }
    return contentHeight > 0 &&
        contentHeight + verticalPadding + _shortHistoryAlignmentHysteresis >=
            viewportHeight;
  }

  bool _shouldKeepShortHistoryTopAlignment({
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required double viewportHeight,
    required BuildContext context,
  }) {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      return false;
    }
    if (_isShortHistoryTopAlignmentBlocked(safeUnreadCount)) {
      return false;
    }
    if (_routeScroll.shortHistoryAlignmentSuppressedByLiveInsert) {
      return false;
    }
    // 已 latch：键盘开关过程中始终保持顶部对齐（只重算 spacer，不释放）。
    if (_routeScroll.shortHistoryAlignmentLatched) {
      return true;
    }
    // 键盘弹出后用当前（变矮的）视口判定/算 spacer；
    // 无键盘时可用 baseline，避免输入栏微抖导致反复 latch。
    final resolvedViewport = _isKeyboardInsetActive(context)
        ? viewportHeight
        : (_routeScroll.shortHistoryBaselineViewportHeight > 0
            ? _routeScroll.shortHistoryBaselineViewportHeight
            : viewportHeight);
    if (_contentExceedsShortHistoryViewport(
      messageList: messageList,
      viewportHeight: resolvedViewport,
      context: context,
    )) {
      return false;
    }
    return _shouldAlignShortHistoryToTop(
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: resolvedViewport,
      context: context,
    );
  }

  double _resolvedShortHistoryViewportForDecision(BuildContext context) {
    final position = _singleScrollPositionOrNull();
    if (position != null &&
        position.hasContentDimensions &&
        position.viewportDimension > 0) {
      return position.viewportDimension;
    }
    if (_routeScroll.shortHistoryBaselineViewportHeight > 0) {
      return _routeScroll.shortHistoryBaselineViewportHeight;
    }
    return _shortHistoryAvailableViewportHeight(context);
  }

  void _releaseShortHistoryAlignmentAndPinBottom() {
    final wasShort = _routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 0 ||
        _routeScroll.shortHistoryContentHeight >= 0;
    _clearShortHistoryAlignmentLatch();
    if (wasShort && mounted && !_isHistoryScrollProtected) {
      // 进页 settle 内只清 latch，禁止强制 pin，避免估高校正触发贴底跳动。
      if (_isInitialRouteSettleWindow) {
        return;
      }
      _schedulePinScrollToBottom();
    }
  }

  double _shortHistoryAvailableViewportHeight(BuildContext context) {
    final coordinator = KeyboardViewportTransitionCoordinator.active;
    var viewport = coordinator?.lastViewHeight ?? 0;
    var padTop = coordinator?.lastPaddingTop ?? 0;
    var padBottom = coordinator?.lastPaddingBottom ?? 0;
    if (viewport <= 0) {
      final view = View.maybeOf(context);
      if (view != null) {
        final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
        viewport = view.physicalSize.height / dpr;
        padTop = view.padding.top / dpr;
        padBottom = view.padding.bottom / dpr;
      }
    }
    // 聊天区域约为全屏去掉顶栏、输入栏与安全区后的高度。
    return (viewport - padTop - padBottom) * 0.62;
  }

  bool _shouldAlignShortHistoryToTop({
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required double viewportHeight,
    required BuildContext context,
  }) {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      return false;
    }
    if (_routeScroll.shortHistoryAlignmentSuppressedByLiveInsert) {
      return false;
    }
    if (_isShortHistoryTopAlignmentBlocked(safeUnreadCount)) {
      return false;
    }
    if (_shortHistoryRealMessageCount(messageList) == 0) {
      return false;
    }
    if (viewportHeight <= 0) {
      return false;
    }
    final verticalPadding = _resolvedHistoryListVerticalPadding(context);
    final contentHeight = _resolvedShortHistoryContentHeight(messageList);
    if (contentHeight > 0) {
      return contentHeight +
              verticalPadding +
              _shortHistoryAlignmentHysteresis <
          viewportHeight;
    }
    final estimate = _estimateShortHistoryContentHeight(messageList);
    return estimate > 0 &&
        estimate + verticalPadding + _shortHistoryAlignmentHysteresis <
            viewportHeight;
  }

  bool _mayUseShortHistoryTopAlignment() {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      return false;
    }
    if (findingMsg != null ||
        findingAnchor != null ||
        widget.initFindingMsg != null ||
        widget.searchJumpAnchor != null ||
        _atJumpOrigin != null) {
      return false;
    }
    if (_shortHistoryRealMessageCount(widget.messageList) == 0) {
      return false;
    }
    if (!mounted) {
      return _estimateShortHistoryContentHeight(widget.messageList) > 0;
    }
    if (_routeScroll.shortHistoryAlignmentSuppressedByLiveInsert) {
      return false;
    }
    if (_routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 0) {
      return true;
    }
    final available = _resolvedShortHistoryViewportForDecision(context);
    return _shouldAlignShortHistoryToTop(
      messageList: widget.messageList,
      safeUnreadCount: 0,
      viewportHeight: available,
      context: context,
    );
  }

  double _resolvedHistoryListVerticalPadding(BuildContext context) {
    final padding = widget.mainHistoryListConfig?.padding;
    if (padding == null) {
      return 0;
    }
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return padding.resolve(direction).vertical;
  }

  double _visibleHistoryTilesHeight({required int expectedMessageCount}) {
    var total = 0.0;
    var measured = 0;
    for (final tag in _autoScrollController.tagMap.values) {
      final tagContext = tag.context;
      final renderObject = tagContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        continue;
      }
      total += renderObject.size.height;
      measured++;
    }
    // 短列表会完整构建所有消息行；只有全部行都拿到布局尺寸时才采用
    // 实测总高，避免可见 tag 尚未齐全时用部分高度生成过大的 spacer。
    return measured < expectedMessageCount ? -1 : total;
  }

  int _shortHistoryRealMessageCount(List<V2TimMessage?> messageList) {
    return messageList
        .where((message) => message != null && message.elemType != 11)
        .length;
  }

  /// 短历史测高期望的 tile 数（含时间分割线），与 AutoScrollTag 一一对应。
  int _shortHistoryTileCount(List<V2TimMessage?> messageList) {
    return messageList.where((message) => message != null).length;
  }

  List<V2TimMessage> _nonNullHistoryMessages(List<V2TimMessage?> messageList) {
    if (messageList is List<V2TimMessage>) return messageList;
    return messageList.whereType<V2TimMessage>().toList(growable: false);
  }

  String _historyIdentitySignatureForList(List<V2TimMessage?> messageList) {
    return TUIChatGlobalModel.historyIdentitySignature(
      _nonNullHistoryMessages(messageList),
    );
  }

  double _estimateShortHistoryContentHeight(List<V2TimMessage?> messageList) {
    final screenWidth = mounted
        ? MediaQuery.sizeOf(context).width
        : ChatMessageHeightCache.defaultScreenWidth;
    var total = 0.0;
    var counted = 0;
    for (final message in messageList) {
      if (message == null) {
        continue;
      }
      // 时间分割线必须计入：空会话首条会「先气泡、后闪时间」，contentH 偏小再回弹。
      if (message.elemType == 11) {
        counted++;
        total += _shortHistoryTimeDividerEstimatedRowHeight;
        continue;
      }
      counted++;
      final cachedHeight = ChatMessageHeightCache.instance.heightFor(message);
      if (cachedHeight != null && cachedHeight > 0) {
        total += cachedHeight;
        continue;
      }
      // 缓存未命中时用类型感知估高（文本 TextPainter / 图视频占位），避免一律 56。
      final estimated = ChatMessageHeightCache.instance.estimateRowHeight(
            message,
            screenWidth: screenWidth,
          ) ??
          (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS
              ? _shortHistoryGroupTipsEstimatedRowHeight
              : _shortHistoryMessageEstimatedRowHeight);
      total += estimated;
    }
    return counted == 0 ? -1 : total;
  }

  double _resolvedShortHistoryContentHeight(List<V2TimMessage?> messageList) {
    final estimate = _estimateShortHistoryContentHeight(messageList);
    if (_routeScroll.shortHistoryContentHeight >= 0) {
      // 实测落地后 display 必须以 stored 为 SSOT，禁止 estimate 软覆盖
      //（日志里 spacer 201↔127 即 estimate=549 盖住 measured=475）。
      if (_routeScroll.shortHistoryContentHeightMeasured) {
        if (estimate > _routeScroll.shortHistoryContentHeight + 8) {
          ChatGeomSettleTrace.noteReason(
            'estimate_resolve_blocked_after_measure',
            extras: <String, Object?>{
              'estimate': estimate.toStringAsFixed(1),
              'contentH':
                  _routeScroll.shortHistoryContentHeight.toStringAsFixed(1),
            },
          );
        }
        return _routeScroll.shortHistoryContentHeight;
      }
      // 仅估高阶段：首帧若只量到气泡、时间分割线尚未入 tagMap，stored 会偏小；
      // 用含 divider 的估高兜住，避免 spacer 先过大再回弹。
      if (estimate > _routeScroll.shortHistoryContentHeight + 8) {
        return estimate;
      }
      return _routeScroll.shortHistoryContentHeight;
    }
    return estimate;
  }

  void _setShortHistoryContentHeight(double nextHeight) {
    final normalized = nextHeight < 0 ? -1.0 : nextHeight;
    if ((_routeScroll.shortHistoryContentHeight - normalized).abs() <= 0.5) {
      return;
    }
    final prev = _routeScroll.shortHistoryContentHeight;
    setState(() {
      _assignShortHistoryContentHeight(normalized, reason: 'content_h_set');
    });
    ChatJitterDiag.logLayoutPulse(
      reason: 'short_history_content_h',
      contentH: normalized,
      spacer: _routeScroll.shortHistoryBottomSpacerHeight,
      latched: _routeScroll.shortHistoryAlignmentLatched,
    );
    ChatJitterDiag.log(
      'content_h_change',
      extras: <String, Object?>{
        'prev': prev.toStringAsFixed(1),
        'next': normalized.toStringAsFixed(1),
        'delta': (normalized - prev).toStringAsFixed(1),
      },
    );
  }

  void _setShortHistoryBottomSpacer(double nextHeight) {
    final normalized = nextHeight <= 1 ? 0.0 : nextHeight;
    if ((_routeScroll.shortHistoryBottomSpacerHeight - normalized).abs() <= 1) {
      return;
    }
    final prev = _routeScroll.shortHistoryBottomSpacerHeight;
    _assignShortHistorySpacer(normalized, reason: 'spacer_set');
    final position = _singleScrollPositionOrNull();
    ChatJitterDiag.logLayoutPulse(
      reason: 'short_history_spacer',
      spacer: normalized,
      contentH: _routeScroll.shortHistoryContentHeight,
      scrollPixels: position?.hasPixels == true ? position!.pixels : null,
      maxExtent: position?.hasContentDimensions == true
          ? position!.maxScrollExtent
          : null,
      latched: _routeScroll.shortHistoryAlignmentLatched,
    );
    ChatJitterDiag.log(
      'spacer_change',
      extras: <String, Object?>{
        'prev': prev.toStringAsFixed(1),
        'next': normalized.toStringAsFixed(1),
        'delta': (normalized - prev).toStringAsFixed(1),
      },
    );
  }

  double _shortHistorySpacerForViewport(
    BuildContext context,
    double viewportHeight, {
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
  }) {
    if (!_shouldKeepShortHistoryTopAlignment(
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: viewportHeight,
      context: context,
    )) {
      return 0;
    }
    final contentHeight = _resolvedShortHistoryContentHeight(messageList);
    if (contentHeight < 0) {
      return 0;
    }
    final verticalPadding = _resolvedHistoryListVerticalPadding(context);
    var target = viewportHeight - contentHeight - verticalPadding;
    if (target < 0) {
      target = 0;
    }
    return target;
  }

  double _displayShortHistoryBottomSpacer(
    BuildContext context, {
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required double viewportHeight,
  }) {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      if (_routeScroll.shortHistoryAlignmentLatched ||
          _routeScroll.shortHistoryBottomSpacerHeight > 0) {
        _clearShortHistoryAlignmentLatch();
      }
      return 0;
    }
    final keyboardActive = _isKeyboardInsetActive(context);
    final keyboardJustDismissed =
        _routeScroll.shortHistoryKeyboardJustDismissed;

    _primeShortHistorySpacerFromEstimate(
      context: context,
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: viewportHeight,
    );
    if (viewportHeight > 0) {
      _tryLatchShortHistoryAlignment(
        messageList: messageList,
        safeUnreadCount: safeUnreadCount,
        viewportHeight: viewportHeight,
        context: context,
      );
    }
    // B2：latch 后 estimate 不得覆盖已有 contentH（尤其实测后）。
    final estimate = _estimateShortHistoryContentHeight(messageList);
    if (_routeScroll.shortHistoryAlignmentLatched &&
        estimate > 0 &&
        _routeScroll.shortHistoryContentHeight >= 0 &&
        estimate > _routeScroll.shortHistoryContentHeight + 8) {
      ChatGeomSettleTrace.noteReason(
        'estimate_blocked_after_measure',
        extras: <String, Object?>{
          'estimate': estimate.toStringAsFixed(1),
          'contentH': _routeScroll.shortHistoryContentHeight.toStringAsFixed(1),
          'measured': _routeScroll.shortHistoryContentHeightMeasured,
        },
      );
    }

    // 已 latch：始终用「视口 − 内容」算 spacer（含键盘动画帧）。
    // 不再用 delta 累积——收起后 delta/拦截一旦不同步，spacer 会停在键盘矮值，
    // 表现为顶部大空白、消息沉在中下部，且要等下一轮才慢慢纠正。
    if (_routeScroll.shortHistoryAlignmentLatched && viewportHeight > 0) {
      final contentHeight = _resolvedShortHistoryContentHeight(messageList);
      if (contentHeight >= 0) {
        final verticalPadding = _resolvedHistoryListVerticalPadding(context);
        var target = viewportHeight - contentHeight - verticalPadding;
        if (target < 0) {
          target = 0;
        }
        final normalized = target <= 1 ? 0.0 : target;
        final prevVp = _routeScroll.shortHistoryLastTrackedViewportHeight;
        final viewportGrew = prevVp > 0 && viewportHeight > prevVp + 1;
        final viewportShrunk = prevVp > 0 && viewportHeight + 1 < prevVp;
        // 估高误差抬高 spacer（视口没变）仍拦截；视口变大/键盘收起/变矮必须跟。
        final wouldGrow =
            normalized > _routeScroll.shortHistoryBottomSpacerHeight + 1;
        if (wouldGrow &&
            !keyboardActive &&
            !keyboardJustDismissed &&
            !viewportGrew &&
            !viewportShrunk &&
            _routeScroll.shortHistoryBottomSpacerHeight > 1) {
          if (viewportHeight > 0) {
            _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;
          }
          return _routeScroll.shortHistoryBottomSpacerHeight;
        }
        if ((normalized - _routeScroll.shortHistoryBottomSpacerHeight).abs() >
            1) {
          _assignShortHistorySpacer(normalized, reason: 'spacer_set');
          if (keyboardJustDismissed || viewportGrew) {
            ChatJitterDiag.logLayoutPulse(
              reason: keyboardJustDismissed
                  ? 'short_history_spacer_keyboard_dismiss'
                  : 'short_history_spacer_viewport_grow',
              spacer: normalized,
              contentH: contentHeight,
              latched: true,
            );
          }
        }
        _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;
        return _routeScroll.shortHistoryBottomSpacerHeight;
      }
    }

    final spacer = _shortHistorySpacerForViewport(
      context,
      viewportHeight,
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
    );
    if ((spacer - _routeScroll.shortHistoryBottomSpacerHeight).abs() > 1) {
      _assignShortHistorySpacer(spacer, reason: 'spacer_display_sync');
    }
    if (viewportHeight > 0) {
      _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;
    }
    if (_routeScroll.shortHistoryAlignmentLatched ||
        _routeScroll.shortHistoryBottomSpacerHeight > 1) {
      return _routeScroll.shortHistoryBottomSpacerHeight;
    }
    return spacer;
  }

  /// 首帧用估高预填 contentH/spacer，避免暖窗短列表先贴底、测高后再跳到顶部。
  void _primeShortHistorySpacerFromEstimate({
    required BuildContext context,
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
    required double viewportHeight,
  }) {
    if (!ChatListRouteScrollRestore.shortHistoryTopAlignmentEnabled) {
      return;
    }
    if (viewportHeight <= 0 ||
        _isShortHistoryTopAlignmentBlocked(safeUnreadCount) ||
        _routeScroll.shortHistoryAlignmentSuppressedByLiveInsert) {
      return;
    }
    final signature = _historyIdentitySignatureForList(messageList);
    final lastMeasured =
        ChatMessageHeightCache.instance.measuredContentHeightFor(
      conversationID: _conversationId(),
      identitySignature: signature,
    );
    final estimate = lastMeasured != null && lastMeasured > 0
        ? lastMeasured
        : _estimateShortHistoryContentHeight(messageList);
    if (lastMeasured != null && lastMeasured > 0) {
      ChatGeomSettleTrace.noteReason(
        'content_h_prime_last_measured',
        extras: <String, Object?>{'contentH': lastMeasured.toStringAsFixed(1)},
      );
    }
    // B2：仅 contentH 未就绪且未实测时允许 estimate 写入；禁止抬高覆盖。
    if (estimate > 0 &&
        _routeScroll.shortHistoryContentHeight < 0 &&
        !_routeScroll.shortHistoryContentHeightMeasured) {
      _assignShortHistoryContentHeight(
        estimate,
        reason: lastMeasured != null && lastMeasured > 0
            ? 'content_h_prime_last_measured'
            : 'content_h_prime_estimate',
      );
    }
    if (!_shouldAlignShortHistoryToTop(
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: viewportHeight,
      context: context,
    )) {
      return;
    }
    final target = _shortHistorySpacerForViewport(
      context,
      viewportHeight,
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
    );
    // 已 latch：键盘收起后用公式恢复 spacer，禁止再走「从 0 re-prime」
    //（日志里 spacer_prime 211→379 就是这条路径抖起来的）。
    if (target > 1 &&
        _routeScroll.shortHistoryBottomSpacerHeight <= 1 &&
        _routeScroll.shortHistoryAlignmentLatched) {
      if (_blockShortSpacerReprimeAfterReveal) {
        ChatGeomSettleTrace.noteReason(
          'short_spacer_reprime_blocked_after_reveal',
          extras: <String, Object?>{
            'cause': 'spacer_prime_relatch',
            'target': target.toStringAsFixed(1),
          },
        );
        return;
      }
      _assignShortHistorySpacer(target, reason: 'spacer_prime_relatch');
      _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;
      return;
    }
    if (target > 1 && _routeScroll.shortHistoryBottomSpacerHeight <= 1) {
      if (_blockShortSpacerReprimeAfterReveal) {
        ChatGeomSettleTrace.noteReason(
          'short_spacer_reprime_blocked_after_reveal',
          extras: <String, Object?>{
            'cause': 'spacer_prime',
            'target': target.toStringAsFixed(1),
          },
        );
        return;
      }
      _assignShortHistorySpacer(target, reason: 'spacer_prime');
      _routeScroll.shortHistoryAlignmentLatched = true;
      _updateShortHistoryBaselineViewport(viewportHeight);
      _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;
      ChatJitterDiag.logLayoutPulse(
        reason: 'short_history_spacer_prime',
        spacer: target,
        contentH: _routeScroll.shortHistoryContentHeight,
        latched: true,
      );
    }
  }

  void _persistShortHistoryMeasuredContentHeight(
    List<V2TimMessage?> messageList,
    double contentHeight,
  ) {
    if (contentHeight <= 0) {
      return;
    }
    ChatMessageHeightCache.instance.rememberMeasuredContentHeight(
      conversationID: _conversationId(),
      identitySignature: _historyIdentitySignatureForList(messageList),
      contentHeight: contentHeight,
    );
  }

  /// Apply measured spacer; when Δ large and scroll room exists, compensate
  /// pixels so content does not visibly jump. At maxExtent≈0 compensation is
  /// a no-op — warm/cold reveal deferral + lastMeasured prime cover that case.
  void _applyShortHistorySpacerMeasureTarget({
    required double target,
    required double viewportHeight,
  }) {
    final normalized = target <= 1 ? 0.0 : target;
    final prev = _routeScroll.shortHistoryBottomSpacerHeight;
    final delta = normalized - prev;
    final absDelta = delta.abs();
    final globalModel = _chatGlobalModel;
    final userScrolling = globalModel?.isChatListUserScrolling == true ||
        _pageUi.userScrolling.value;
    final position = _singleScrollPositionOrNull();
    final canLockAnchor = !userScrolling &&
        !_isHistoryScrollProtected &&
        absDelta > _shortHistorySpacerRebuildTolerancePx &&
        position != null &&
        position.hasPixels &&
        position.hasContentDimensions &&
        position.maxScrollExtent > 1;

    _assignShortHistorySpacer(normalized, reason: 'spacer_measure_target');
    _routeScroll.shortHistoryLastTrackedViewportHeight = viewportHeight;

    if (!canLockAnchor || position == null) {
      return;
    }
    // reverse 列表底 spacer 变高且贴底时消息上移；有滚动余量时把 pixels 往同向推回。
    final nextPixels = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((nextPixels - position.pixels).abs() > 0.5) {
      _geomJumpTo(nextPixels, reason: 'spacer_measure_lock_anchor');
    }
  }

  void _scheduleShortViewportHistoryFill(_PreviousLoadAnchor? anchor) {
    // 缓存暖开时也可能只恢复到几条消息。只要模型明确还有历史且列表仍
    // 不可滚动，就继续静默补页；否则用户无法通过滚动触发上一页。
    // C-fix：首屏 reveal 未完成时，禁止此自动补页入口触发 schedule_previous。
    // 否则首屏 widget 树刚进 vsync（maxScrollExtent<1）就会立即再拉 SDK，
    // 阻塞 first_paint。允许时机：reveal 已完成 OR 已有过 reveal 过的会话重开。
    final viewportFillKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.conversation.conversationID,
      userId: widget.conversation.userID,
      groupId: widget.conversation.groupID,
    );
    final precheckOffsetMs =
        ChatPipelineClock.instance.offsetMs(viewportFillKey);
    // ignore: avoid_print
    if (ChatHistoryTrace.enabled) {
      debugPrint(
        '[RevealTrace] reason=viewport_fill_entry conv=$viewportFillKey '
        'revealPainted=$_historyOpenRevealPainted '
        'hasContentDimensions=${_singleScrollPositionOrNull()?.hasContentDimensions} '
        'maxScrollExtent=${_singleScrollPositionOrNull()?.maxScrollExtent} '
        'haveMoreData=${widget.model.haveMoreData} '
        'shortFillScheduled=${_routeScroll.shortViewportHistoryFillScheduled} '
        'loadingPrevious=${_paginationUi.isLoadingPrevious} '
        'taskInFlight=${_paginationUi.loadPreviousTask != null} '
        'tickOffsetMs=$precheckOffsetMs '
        'msgCount=${widget.messageList.length}',
      );
    }
    if (_routeScroll.shortViewportHistoryFillScheduled ||
        anchor == null ||
        !_canAttemptPreviousHistoryPagination() ||
        _paginationUi.isLoadingPrevious ||
        _paginationUi.loadPreviousTask != null ||
        _isHistoryScrollProtected ||
        _isSearchJumpStabilizing) {
      return;
    }
    final scheduledModel = widget.model;
    final scheduledConversation = _conversationId();
    final scheduledWindowIsCurrent =
        scheduledModel.captureHistoryWindowPublicationFence();
    _routeScroll.shortViewportHistoryFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeScroll.shortViewportHistoryFillScheduled = false;
      // C-fix 续：post-frame 再次校验 reveal 状态；reveal 未完成直接 return。
      if (!mounted ||
          !identical(widget.model, scheduledModel) ||
          _conversationId() != scheduledConversation ||
          !scheduledWindowIsCurrent() ||
          !_historyOpenRevealPainted ||
          !_canAttemptPreviousHistoryPagination() ||
          _paginationUi.isLoadingPrevious ||
          _paginationUi.loadPreviousTask != null ||
          _isHistoryScrollProtected ||
          _isSearchJumpStabilizing) {
        final postOffsetMs =
            ChatPipelineClock.instance.offsetMs(viewportFillKey);
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[RevealTrace] reason=viewport_fill_post_frame_skip conv=$viewportFillKey '
            'revealPainted=$_historyOpenRevealPainted '
            'loadingPrevious=${_paginationUi.isLoadingPrevious} '
            'taskInFlight=${_paginationUi.loadPreviousTask != null} '
            'tickOffsetMs=$postOffsetMs '
            'msgCount=${widget.messageList.length}',
          );
        }
        return;
      }
      final position = _singleScrollPositionOrNull();
      if (position == null ||
          !position.hasContentDimensions ||
          position.maxScrollExtent - position.minScrollExtent > 1) {
        final postOffsetMs =
            ChatPipelineClock.instance.offsetMs(viewportFillKey);
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[RevealTrace] reason=viewport_fill_post_frame_skip conv=$viewportFillKey '
            'skipReason=scrollable_or_no_dims '
            'maxScrollExtent=${position?.maxScrollExtent} '
            'tickOffsetMs=$postOffsetMs '
            'msgCount=${widget.messageList.length}',
          );
        }
        return;
      }
      final postOffsetMs2 =
          ChatPipelineClock.instance.offsetMs(viewportFillKey);
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[RevealTrace] reason=viewport_fill_post_frame conv=$viewportFillKey '
          'revealPainted=$_historyOpenRevealPainted '
          'maxScrollExtent=${position.maxScrollExtent} '
          'haveMoreData=${widget.model.haveMoreData} '
          'shortFillScheduled=${_routeScroll.shortViewportHistoryFillScheduled} '
          'tickOffsetMs=$postOffsetMs2 '
          'msgCount=${widget.messageList.length}',
        );
      }
      // 不可滚动时没有 ScrollUpdate，主动补一页直到填满 viewport 或模型
      // 明确返回无更多。该入口不参与 iOS 顶部回弹判定，避免原来的死循环。
      // 首屏自动补拉静默：不显示顶部转圈。页面已 reveal 或缓存暖开时也
      // 必须允许该专用入口补页，直到列表可滚动或模型返回无更多。
      _scheduleLoadPrevious(
        anchor,
        silent: true,
        allowAfterRevealForViewportFill: true,
      );
    });
  }

  void _scheduleShortHistoryTopAlignment({
    required BuildContext context,
    required List<V2TimMessage?> messageList,
    required int safeUnreadCount,
  }) {
    if (_shouldCompensateScrollForPagination()) {
      return;
    }
    if (_paginationUi.isLoadingPrevious || _isHistoryScrollProtected) {
      return;
    }
    final globalModel = Provider.of<TUIChatGlobalModel>(context, listen: false);
    // 暖窗已出屏时允许首帧估高 latch；仅冷启动空壳仍等 bootstrap 结束。
    if (_isInitialHistoryBootstrapping(globalModel) &&
        !_routeScroll.openedWithCachedHistory) {
      return;
    }
    final scrollPosition = _singleScrollPositionOrNull();
    final fallbackViewport = _isKeyboardInsetActive(context) &&
            scrollPosition != null &&
            scrollPosition.hasContentDimensions &&
            scrollPosition.viewportDimension > 0
        ? scrollPosition.viewportDimension
        : _shortHistoryAvailableViewportHeight(context);
    if (!_shouldKeepShortHistoryTopAlignment(
      messageList: messageList,
      safeUnreadCount: safeUnreadCount,
      viewportHeight: fallbackViewport,
      context: context,
    )) {
      if (_routeScroll.shortHistoryBottomSpacerHeight > 0 ||
          _routeScroll.shortHistoryContentHeight >= 0 ||
          _routeScroll.shortHistoryAlignmentLatched) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isHistoryScrollProtected) {
            _releaseShortHistoryAlignmentAndPinBottom();
            setState(() {});
          }
        });
      }
      return;
    }
    if (_routeScroll.shortHistoryAlignmentMeasureScheduled) {
      return;
    }
    _routeScroll.shortHistoryAlignmentMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeScroll.shortHistoryAlignmentMeasureScheduled = false;
      if (!mounted) {
        return;
      }
      final keyboardActive = _isKeyboardInsetActive(context);
      final contentHeight = _visibleHistoryTilesHeight(
        expectedMessageCount: _shortHistoryTileCount(messageList),
      );
      if (contentHeight < 0) {
        return;
      }
      final position = _singleScrollPositionOrNull();
      if (position != null && position.hasContentDimensions) {
        final viewportHeight = position.viewportDimension;
        _tryLatchShortHistoryAlignment(
          messageList: messageList,
          safeUnreadCount: safeUnreadCount,
          viewportHeight: viewportHeight,
          context: context,
        );
        if (!_shouldKeepShortHistoryTopAlignment(
          messageList: messageList,
          safeUnreadCount: safeUnreadCount,
          viewportHeight: viewportHeight,
          context: context,
        )) {
          if (_routeScroll.shortHistoryBottomSpacerHeight > 0 ||
              _routeScroll.shortHistoryContentHeight >= 0 ||
              _routeScroll.shortHistoryAlignmentLatched) {
            if (!_isHistoryScrollProtected) {
              setState(() {
                _releaseShortHistoryAlignmentAndPinBottom();
              });
            }
          }
          return;
        }
        // 键盘动画中只更新 contentH，spacer 由 display 路径按视口 delta 跟。
        if (!keyboardActive) {
          final verticalPadding = _resolvedHistoryListVerticalPadding(context);
          var target = viewportHeight - contentHeight - verticalPadding;
          if (target < 0) {
            target = 0;
          }
          _applyShortHistorySpacerMeasureTarget(
            target: target,
            viewportHeight: viewportHeight,
          );
        }
      }
      final estimate = _estimateShortHistoryContentHeight(messageList);
      if (_routeScroll.shortHistoryContentHeight < 0 &&
          estimate > 0 &&
          (contentHeight - estimate).abs() <= 24) {
        _assignShortHistoryContentHeight(
          contentHeight,
          reason: 'content_h_measure',
        );
        _persistShortHistoryMeasuredContentHeight(messageList, contentHeight);
        return;
      }
      if (keyboardActive) {
        // 键盘态只升不降 contentH，避免漏测时间线时把估高压小再抖。
        if (contentHeight > _routeScroll.shortHistoryContentHeight + 0.5) {
          _assignShortHistoryContentHeight(
            contentHeight,
            reason: 'content_h_measure',
          );
          _persistShortHistoryMeasuredContentHeight(messageList, contentHeight);
        }
        return;
      }
      // 实测与当前值差异很小（首帧估算基本命中）时静默记录，
      // 不再触发整帧重建；spacer 的毫厘修正会让首屏列表可见地跳动。
      final delta = _routeScroll.shortHistoryContentHeight < 0
          ? double.infinity
          : (_routeScroll.shortHistoryContentHeight - contentHeight).abs();
      if (delta <= _shortHistorySpacerRebuildTolerancePx) {
        _assignShortHistoryContentHeight(
          contentHeight,
          reason: 'content_h_measure',
        );
        _persistShortHistoryMeasuredContentHeight(messageList, contentHeight);
        // 静默校正 spacer（不 setState）：顶部锚定不变，只微调底部留白。
        if (position != null &&
            position.hasContentDimensions &&
            _routeScroll.shortHistoryAlignmentLatched) {
          final viewportHeight = position.viewportDimension;
          final verticalPadding = _resolvedHistoryListVerticalPadding(context);
          var target = viewportHeight - contentHeight - verticalPadding;
          if (target < 0) {
            target = 0;
          }
          _applyShortHistorySpacerMeasureTarget(
            target: target,
            viewportHeight: viewportHeight,
          );
        }
        return;
      }
      // 进页 settle 窗口：只静默更新 contentH / spacer，不 setState、不 pin。
      if (_isInitialRouteSettleWindow) {
        _assignShortHistoryContentHeight(
          contentHeight,
          reason: 'content_h_measure',
        );
        _persistShortHistoryMeasuredContentHeight(messageList, contentHeight);
        if (position != null && position.hasContentDimensions) {
          final viewportHeight = position.viewportDimension;
          final verticalPadding = _resolvedHistoryListVerticalPadding(context);
          var target = viewportHeight - contentHeight - verticalPadding;
          if (target < 0) {
            target = 0;
          }
          _applyShortHistorySpacerMeasureTarget(
            target: target,
            viewportHeight: viewportHeight,
          );
        }
        return;
      }
      _setShortHistoryContentHeight(contentHeight);
      _persistShortHistoryMeasuredContentHeight(messageList, contentHeight);
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _wrapListMessageItem(V2TimMessage? message, Widget child) {
    final skipRepaint = message != null &&
        (widget.mainHistoryListConfig?.skipRepaintBoundaryForMessage?.call(
              message,
            ) ??
            false);
    if (skipRepaint) {
      return ClipRect(
        clipBehavior: Clip.hardEdge,
        child: ColoredBox(color: Colors.transparent, child: child),
      );
    }
    final content = RepaintBoundary(child: child);
    if (!_isHeavyListMessage(message)) {
      return content;
    }
    return KeepAliveWrapper(keepAlive: true, child: content);
  }

  Widget _buildScrollMessageTile(
    V2TimMessage? messageItem,
    int index, {
    int? globalIndex,
  }) {
    final stableListKey = _stableMessageListKey(messageItem, index);
    // Group only: enqueue near-visible senders for capped/TTL getUsersInfo.
    // Cost ∝ built rows, never ∝ total group members.
    if (messageItem != null && messageItem.isSelf != true) {
      final groupId = messageItem.groupID?.trim() ??
          widget.conversation.groupID?.trim() ??
          '';
      if (groupId.isNotEmpty) {
        VisibleSenderProfileRefresh.noteSender(
          messageItem.sender ?? messageItem.userID,
          selfUserId: TIMUIKitCore.getInstance().loginUserInfo?.userID,
        );
      }
    }
    final resolvedGlobalIndex =
        globalIndex ?? _globalIndexMap[stableListKey] ?? index;
    Widget tile = AutoScrollTag(
      controller: _autoScrollController,
      index: -resolvedGlobalIndex,
      key: ValueKey(stableListKey),
      // 搜索/引用/转发消息定位只负责滚动到目标，不再让 AutoScrollTag
      // 自动闪烁边框/遮罩。转发消息卡片自身带边框时，高亮闪烁会被误认为
      // 定位抖动或消息状态异常。
      highlightColor: Colors.transparent,
      child: _wrapListMessageItem(
        messageItem,
        _getMessageItemBuilder(messageItem),
      ),
    );
    if (resolvedGlobalIndex == 0 && messageItem != null) {
      tile = _HeadMessageLayoutReporter(
        message: messageItem,
        onLaidOut: _onHeadMessageLaidOut,
        child: tile,
      );
    }
    final rowRevealKey = messageItem == null ? null : stableListKey;
    if (rowRevealKey != null) {
      final isActive = _viewportInsert.activeRowRevealMessages.containsKey(
        rowRevealKey,
      );
      final isQueued = _viewportInsert.queuedViewportInsertMessages.containsKey(
        rowRevealKey,
      );
      // Short-list growth and scroll-based insertion share the same easing.
      final Animation<double>? activeProgress = !isActive
          ? null
          : (_viewportInsert.rowRevealAnimation ??
              _viewportInsert.rowRevealController);
      final rowProgress = _shortInsertProgress[rowRevealKey] ??
          activeProgress ??
          (isQueued
              ? const AlwaysStoppedAnimation<double>(0)
              : const AlwaysStoppedAnimation<double>(1));
      tile = ChatMessageRowReveal(
        key: ValueKey<String>(rowRevealKey),
        progress: rowProgress,
        onFullHeightChanged: (height) {
          if (isActive || isQueued) {
            final previousHeight =
                _viewportInsert.rowRevealFullExtentByKey[rowRevealKey];
            _viewportInsert.rowRevealFullExtentByKey[rowRevealKey] = height;
            if (previousHeight == null ||
                (height - previousHeight).abs() > 0.5) {
              final position = _singleScrollPositionOrNull();
              ChatJitterDiag.logInboundFlow(
                action: 'cvp_row_measured',
                conv: _conversationId(),
                extras: <String, Object?>{
                  'cvpTx':
                      _viewportInsert.continuousViewportPushDiagTransaction,
                  'rowKeyHash': rowRevealKey.hashCode,
                  'active': isActive,
                  'queued': isQueued,
                  'before': previousHeight?.toStringAsFixed(2) ?? 'none',
                  'height': height.toStringAsFixed(2),
                  'pixels': position?.hasPixels == true
                      ? position!.pixels.toStringAsFixed(2)
                      : 'n/a',
                  'min': position?.hasContentDimensions == true
                      ? position!.minScrollExtent.toStringAsFixed(2)
                      : 'n/a',
                  'max': position?.hasContentDimensions == true
                      ? position!.maxScrollExtent.toStringAsFixed(2)
                      : 'n/a',
                  'phase': SchedulerBinding.instance.schedulerPhase.name,
                },
              );
            }
          }
        },
        child: tile,
      );
    }
    if (_shouldHideMessageDuringPaginationPrependReveal(resolvedGlobalIndex)) {
      tile = Opacity(opacity: 0, child: tile);
    }
    // SliverChildBuilderDelegate only sees the direct child's key. Wrappers
    // such as Opacity, layout reporters and reveal animations must not hide
    // the message identity during prepend/replace, otherwise
    // findChildIndexCallback cannot relocate the existing RenderBox.
    // ⚠️ DEBUG ONLY - MsgSizeTrace diagnostic - Remove after bug fix
    return KeyedSubtree(
      key: ValueKey<String>(stableListKey),
      child: Builder(
        builder: (innerContext) {
          _debugLogMessageItemSize(
            innerContext,
            messageItem,
            index,
            globalIndex: globalIndex,
          );
          return tile;
        },
      ),
    );
  }

  // ⚠️ DEBUG ONLY - MsgSizeTrace diagnostic - Remove after bug fix
  void _debugLogMessageItemSize(
    BuildContext context,
    V2TimMessage? messageItem,
    int index, {
    int? globalIndex,
  }) {
    assert(() {
      final pipelineKey = ChatPipelineClock.normalizeKey(
        rawConversationId: widget.conversation.conversationID,
        userId: widget.conversation.userID,
        groupId: widget.conversation.groupID,
      );
      // 仅对目标会话打印，避免日志噪音
      if (!pipelineKey.contains('acnj6oxey9')) {
        return true;
      }
      final msgID = messageItem?.msgID ?? 'n/a';
      final elemType = messageItem?.elemType ?? -1;
      // ignore: avoid_print
      if (ChatHistoryTrace.enabled) {
        debugPrint(
          '[MsgSizeTrace] conv=$pipelineKey idx=$index '
          'globalIdx=${globalIndex ?? -1} msgID=$msgID elemType=$elemType '
          'buildTime=true',
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ro = context.findRenderObject();
        if (ro == null) {
          // ignore: avoid_print
          if (ChatHistoryTrace.enabled) {
            debugPrint(
              '[MsgSizeTrace] conv=$pipelineKey idx=$index '
              'globalIdx=${globalIndex ?? -1} msgID=$msgID elemType=$elemType '
              'renderObjectNull=true',
            );
          }
          return;
        }
        if (ro is! RenderBox) {
          // ignore: avoid_print
          if (ChatHistoryTrace.enabled) {
            debugPrint(
              '[MsgSizeTrace] conv=$pipelineKey idx=$index '
              'globalIdx=${globalIndex ?? -1} msgID=$msgID elemType=$elemType '
              'notRenderBox=true roType=${ro.runtimeType} isRenderSliver=${ro is RenderSliver}',
            );
          }
          return;
        }
        double maxChildHeight = 0;
        int childCount = 0;
        ro.visitChildren((child) {
          if (child is RenderBox) {
            childCount++;
            final h = child.size.height;
            if (h > maxChildHeight) maxChildHeight = h;
          }
        });
        final anchor = _singleScrollPositionOrNull();
        final maxE = anchor?.hasContentDimensions == true
            ? anchor!.maxScrollExtent.toStringAsFixed(1)
            : 'n/a';
        // ignore: avoid_print
        if (ChatHistoryTrace.enabled) {
          debugPrint(
            '[MsgSizeTrace] conv=$pipelineKey idx=$index '
            'globalIdx=${globalIndex ?? -1} msgID=$msgID elemType=$elemType '
            'itemHeight=${ro.size.height.toStringAsFixed(1)} '
            'maxChildH=${maxChildHeight.toStringAsFixed(1)} '
            'childrenCount=$childCount maxExtent=$maxE',
          );
        }
      });
      return true;
    }());
  }
  // === END DEBUG ONLY ===

  void _releaseSearchJumpMemoryWindowSuppress({
    String? anchorMsgID,
    String? anchorSeq,
  }) {
    final gm = _chatGlobalModel;
    final conv = _conversationId();
    if (gm == null) {
      return;
    }
    gm.setMemoryWindowSuppressed(conv, false);
    gm.applyMessageMemoryWindowNow(
      conv,
      memoryWindowAnchorMsgID: anchorMsgID,
      memoryWindowAnchorSeq: anchorSeq,
    );
  }

  void showCantFindMsg() {
    if (!_ownsSearchJumpRequest) return;
    _searchJumpLayoutDeadline?.cancel();
    ++_searchJumpGeneration;
    ChatHistoryTrace.log('search_jump_layout_failed',
        conversationID: _conversationId(),
        extras: {
          'targetSeq': findingAnchor?.seq,
          'attempts': _findingRetryCount
        });
    _initialSearchJumpPositioned = true;
    _findingRetryCount = 0;
    findingMsg = null;
    findingAnchor = null;
    findingSeq = "";
    loadingPlace = LoadingPlace.none;
    _releaseSearchJumpMemoryWindowSuppress();
    _chatGlobalModel?.setSearchJumpStatus(
      _conversationId(),
      SearchJumpStatus.failed,
      notify: true,
    );
    if (mounted) {
      setState(() {});
    }
    onTIMCallback(
      TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t("无法定位到原消息"),
        infoCode: 6660401,
      ),
    );
  }

  _onScrollToAnchor(MessageAnchor targetAnchor) async {
    if (!_ownsSearchJumpRequest) return;
    if (_scrollToFindInFlight) {
      return;
    }
    _lockSearchJumpStabilization(milliseconds: 2600);
    // The shared list may still contain the old window while SDK loading runs.
    // Wait for the provider's replacement before resolving any visible index.
    if ((widget.searchJumpAnchor != null || widget.initFindingMsg != null) &&
        _initialSearchJumpPending &&
        _chatGlobalModel?.getSearchJumpStatus(_conversationId()) !=
            SearchJumpStatus.success &&
        _chatGlobalModel?.getSearchJumpStatus(_conversationId()) !=
            SearchJumpStatus.positioning) {
      _scheduleScrollToFindingMsgDelayed();
      return;
    }
    if (widget.messageList.isEmpty) {
      final jumpStatus =
          _chatGlobalModel?.getSearchJumpStatus(_conversationId()) ??
              SearchJumpStatus.idle;
      if (jumpStatus == SearchJumpStatus.failed) {
        return;
      }
      _scheduleScrollToFindingMsgDelayed();
      return;
    }
    _searchJumpLayoutDeadline ??= Timer(const Duration(seconds: 8), () {
      if (mounted && _initialSearchJumpPending) showCantFindMsg();
    });
    _scrollToFindInFlight = true;
    loadingPlace = LoadingPlace.top;
    final generation = ++_searchJumpGeneration;
    final searchTarget = _SearchJumpTarget(
      resolveIndex: () => _globalIndexForAnchor(targetAnchor),
    );
    try {
      final targetGlobalIndex = _resolveSearchJumpGlobalIndex(searchTarget);
      if (_findingRetryCount == 0) {
        ChatHistoryTrace.log('search_jump_position_begin',
            conversationID: _conversationId(),
            extras: {
              'targetSeq': targetAnchor.seq,
              'index': targetGlobalIndex,
              'rows': widget.messageList.length,
              'scrollClients': _autoScrollController.positions.length
            });
      }
      if (targetGlobalIndex != null) {
        final centered = await _centerOnGlobalIndex(
          targetGlobalIndex,
          target: searchTarget,
          generation: generation,
        );
        if (!mounted || !_ownsSearchJumpRequest) return;
        if (centered) {
          _searchJumpLayoutDeadline?.cancel();
          ChatHistoryTrace.log('search_jump_positioned',
              conversationID: _conversationId(),
              extras: {
                'targetSeq': targetAnchor.seq,
                'index': targetGlobalIndex,
                'pixels': _singleScrollPositionOrNull()?.pixels
              });
          _findingRetryCount = 0;
          final matched = _messageForAnchor(targetAnchor);
          findingAnchor = null;
          findingMsg = null;
          _initialSearchJumpPositioned = true;
          final jumpId = matched == null
              ? targetAnchor.stableKey
              : _messageIdentity(matched);
          if (jumpId.isNotEmpty) {
            widget.model.jumpMsgID = jumpId;
          }
          loadingPlace = LoadingPlace.none;
          _releaseSearchJumpMemoryWindowSuppress(
            anchorMsgID: matched?.msgID ?? targetAnchor.msgID,
            anchorSeq: matched?.seq ?? targetAnchor.seq,
          );
          _chatGlobalModel?.setSearchJumpStatus(
            _conversationId(),
            SearchJumpStatus.success,
            requestID: _searchJumpRequest,
            notify: true,
          );
          if (mounted) setState(() {});
          return;
        }
      }
      if (!mounted ||
          !_ownsSearchJumpRequest ||
          generation != _searchJumpGeneration) return;
      if (_findingRetryCount < 40) {
        _findingRetryCount++;
        findingAnchor = targetAnchor;
        _scheduleScrollToFindingMsgDelayed();
      } else {
        showCantFindMsg();
      }
    } finally {
      _scrollToFindInFlight = false;
    }
  }

  _onScrollToIndex(V2TimMessage targetMsg) async {
    if (_scrollToFindInFlight) {
      return;
    }
    _lockSearchJumpStabilization(milliseconds: 2600);
    final targetTimeStamp = targetMsg.timestamp;
    if (targetTimeStamp == null) {
      showCantFindMsg();
      return;
    }
    if (widget.messageList.isEmpty) {
      final jumpStatus =
          _chatGlobalModel?.getSearchJumpStatus(_conversationId()) ??
              SearchJumpStatus.idle;
      if (jumpStatus == SearchJumpStatus.failed) {
        return;
      }
      _scheduleScrollToFindingMsgDelayed();
      return;
    }
    _scrollToFindInFlight = true;
    loadingPlace = LoadingPlace.top;
    final generation = ++_searchJumpGeneration;
    final searchTarget = _SearchJumpTarget(
      resolveIndex: () => _globalIndexForTargetMessage(targetMsg),
    );

    try {
      final targetGlobalIndex = _resolveSearchJumpGlobalIndex(searchTarget);
      if (targetGlobalIndex != null) {
        maybeHaveMoreMessageForFind = false;
        final centered = await _centerOnGlobalIndex(
          targetGlobalIndex,
          target: searchTarget,
          generation: generation,
        );
        if (centered) {
          _findingRetryCount = 0;
          findingMsg = null;
          _initialSearchJumpPositioned = true;
          final jumpId = _messageIdentity(targetMsg);
          if (jumpId.isNotEmpty) {
            widget.model.jumpMsgID = jumpId;
          }
          loadingPlace = LoadingPlace.none;
          _releaseSearchJumpMemoryWindowSuppress(
            anchorMsgID: targetMsg.msgID,
            anchorSeq: targetMsg.seq,
          );
          if (mounted) {
            setState(() {});
          }
          return;
        }

        // 已经在当前窗口里找到目标，只是列表还没稳定到可滚动状态。
        // 不要继续拉历史，否则会把搜索跳转变成连续 older 分页，导致红屏。
        if (_findingRetryCount < 12) {
          _findingRetryCount++;
          findingMsg = targetMsg;
          _scheduleScrollToFindingMsgDelayed();
        } else {
          showCantFindMsg();
        }
        return;
      }

      // 从搜索结果进入聊天时，Provider 已经按目标消息构建上下文窗口。
      // 如果此刻还没找到，优先等待列表刷新，不主动继续翻旧消息，避免
      // 连续触发 group_history_message older 拉取造成无法定位和红屏。
      if (_isInitialFindingTarget(targetMsg)) {
        if (_findingRetryCount < 40) {
          _findingRetryCount++;
          findingMsg = targetMsg;
          _scheduleScrollToFindingMsgDelayed();
        } else {
          showCantFindMsg();
        }
        return;
      }

      // References and controller jumps also open directly around the target.
      // Never walk older pages looking for a message outside this window.
      final loaded = await widget.model.loadListForSpecificMessage(
        targetMessage: targetMsg,
      );
      if (!mounted) return;
      if (loaded) {
        findingMsg = targetMsg;
        _scheduleScrollToFindingMsgDelayed();
      } else {
        showCantFindMsg();
      }
    } finally {
      _scrollToFindInFlight = false;
    }
  }

  /// Tongue 「@我」：优先内存命中；否则 around-seq 开窗（同搜索跳转），禁止 seq 差追翻。
  Future<bool> _onScrollToIndexBySeq(String targetSeq) async {
    if (_scrollToFindInFlight) {
      return false;
    }
    _lockSearchJumpStabilization(milliseconds: 2600);
    loadingPlace = LoadingPlace.top;
    // Clear legacy chase flag so build() cannot re-enter this path.
    findingSeq = "";

    final targetSeqInt = AtMeJump.parseTargetSeq(targetSeq);
    final canonicalSeq = AtMeJump.canonicalSeqString(targetSeq);
    if (targetSeqInt == null || canonicalSeq == null) {
      showCantFindMsg();
      loadingPlace = LoadingPlace.none;
      return false;
    }

    _atJumpOrigin = MessageAnchor(
      conversationID: _conversationId(),
      convType: widget.conversation.type ?? 2,
      seq: canonicalSeq,
    );
    if (mounted) {
      setState(() {});
    }

    _scrollToFindInFlight = true;
    final transition = _windowTransitionKey.currentState;
    var startedTransition = false;
    try {
      var targetGlobalIndex = _globalIndexForSeq(canonicalSeq);
      if (targetGlobalIndex == null) {
        ChatHistoryTrace.log(
          'at_me_around_jump_begin',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'targetSeq': canonicalSeq,
            'listLen': widget.messageList.length,
            'haveMoreData': widget.model.haveMoreData,
            'haveMoreLatestData': widget.model.haveMoreLatestData,
          },
        );
        transition?.begin(showSpinner: false, showProgress: false);
        startedTransition = true;
        final loaded = await widget.model.loadListForSpecificMessage(
          seq: targetSeqInt,
        );
        if (!mounted) {
          return false;
        }
        if (!loaded) {
          ChatHistoryTrace.log(
            'at_me_around_jump_fail',
            conversationID: _conversationId(),
            extras: <String, Object?>{'targetSeq': canonicalSeq},
          );
          _releaseAtJumpCenterOwnership();
          showCantFindMsg();
          loadingPlace = LoadingPlace.none;
          return false;
        }
        _renderedVisibleMessages = null;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return false;
        }
        targetGlobalIndex = _globalIndexForSeq(canonicalSeq);
      }

      var centered = false;
      if (targetGlobalIndex != null) {
        centered = await _centerOnAtMeSeq(canonicalSeq, targetGlobalIndex);
      } else {
        ChatHistoryTrace.log(
          'at_me_around_jump_missing_after_load',
          conversationID: _conversationId(),
          extras: <String, Object?>{
            'targetSeq': canonicalSeq,
            'listLen': widget.messageList.length,
          },
        );
      }
      if (!centered) {
        final visible = _visibleMessageList(widget.messageList);
        final seqs = <int?>[
          for (final message in visible)
            _isUnreadAnchorMessage(message)
                ? int.tryParse(message?.seq?.trim() ?? '')
                : null,
        ];
        final fallbackIndex = AtMeJump.pickVisibleIndex(seqs, targetSeqInt);
        if (fallbackIndex == null) {
          _releaseAtJumpCenterOwnership();
          showCantFindMsg();
          loadingPlace = LoadingPlace.none;
          return false;
        }
        final fallbackMsg = visible[fallbackIndex];
        if (fallbackMsg == null) {
          _releaseAtJumpCenterOwnership();
          showCantFindMsg();
          loadingPlace = LoadingPlace.none;
          return false;
        }
        final fallbackSeq = AtMeJump.canonicalSeqString(fallbackMsg.seq);
        if (fallbackSeq == null) {
          _releaseAtJumpCenterOwnership();
          showCantFindMsg();
          loadingPlace = LoadingPlace.none;
          return false;
        }
        _atJumpOrigin = MessageAnchor.fromConversationMessage(
          widget.conversation,
          fallbackMsg,
        );
        centered = await _centerOnAtMeSeq(fallbackSeq, fallbackIndex);
        if (!centered) {
          _releaseAtJumpCenterOwnership();
          showCantFindMsg();
          loadingPlace = LoadingPlace.none;
          return false;
        }
      }
      ChatHistoryTrace.log(
        'at_me_around_jump_success',
        conversationID: _conversationId(),
        extras: <String, Object?>{
          'targetSeq': canonicalSeq,
          'listLen': widget.messageList.length,
          'haveMoreData': widget.model.haveMoreData,
          'haveMoreLatestData': widget.model.haveMoreLatestData,
          'position': _chatGlobalModel
                  ?.getMessageListPosition(_conversationId())
                  .name ??
              '',
        },
      );
      return true;
    } finally {
      _scrollToFindInFlight = false;
      if (startedTransition) {
        await transition?.finish();
      }
      if (mounted && loadingPlace != LoadingPlace.none) {
        loadingPlace = LoadingPlace.none;
      }
    }
  }

  Future<bool> _centerOnAtMeSeq(
    String canonicalSeq,
    int targetGlobalIndex,
  ) async {
    String? targetMsgID;
    final messageList = _visibleMessageList(widget.messageList);
    if (targetGlobalIndex >= 0 && targetGlobalIndex < messageList.length) {
      targetMsgID = messageList[targetGlobalIndex]?.msgID;
    }
    final generation = ++_searchJumpGeneration;
    final searchTarget = _SearchJumpTarget(
      resolveIndex: () => _globalIndexForSeq(canonicalSeq),
    );
    final centered = await _centerOnGlobalIndex(
      targetGlobalIndex,
      target: searchTarget,
      generation: generation,
    );
    if (centered && targetMsgID != null && targetMsgID.isNotEmpty) {
      widget.model.jumpMsgID = targetMsgID;
    }
    loadingPlace = LoadingPlace.none;
    if (centered) {
      _releaseSearchJumpMemoryWindowSuppress(
        anchorMsgID: targetMsgID,
        anchorSeq: canonicalSeq,
      );
    }
    if (mounted) {
      setState(() {});
    }
    return centered;
  }

  _onScrollToIndexBegin(V2TimMessage targetMsg) {
    _lockSearchJumpStabilization(milliseconds: 2600);
    final lastTimestamp =
        widget.messageList[widget.messageList.length - 1]?.timestamp;
    final msgList = widget.messageList;
    final int targetTimeStamp = targetMsg.timestamp!;

    if (targetTimeStamp >= lastTimestamp!) {
      bool isFound = false;
      int targetIndex = 1;
      for (int i = msgList.length - 1; i >= 0; i--) {
        final currentMsg = msgList[i];
        if (_messageMatchesTarget(currentMsg, targetMsg)) {
          isFound = true;
          targetIndex = -i;
          break;
        }
      }
      if (isFound && targetIndex != 1) {
        final targetGlobalIndex = -targetIndex;
        final generation = ++_searchJumpGeneration;
        final searchTarget = _SearchJumpTarget(
          resolveIndex: () => _globalIndexForTargetMessage(targetMsg),
        );
        _centerOnGlobalIndex(
          targetGlobalIndex,
          target: searchTarget,
          generation: generation,
        );
      }
    }
  }

  List<V2TimMessage?> _getReceivedMessageList(int receivedMessageListCount) {
    if (receivedMessageListCount == 0) {
      return [];
    }
    final haveTimeStampMessage =
        widget.messageList[receivedMessageListCount]?.elemType == 11;
    final endPoint = haveTimeStampMessage
        ? receivedMessageListCount + 1
        : receivedMessageListCount;
    return widget.messageList.sublist(0, endPoint).reversed.toList();
  }

  Widget _buildTongueContainer(List<V2TimMessage?> messageList) {
    return TIMUIKitHistoryMessageListTongueContainer(
      key: _bottomTongueKey,
      conversation: widget.conversation,
      model: widget.model,
      messageList: messageList,
      scrollController: _autoScrollController,
      scrollToIndexBySeq: _onScrollToIndexBySeq,
      scrollToFirstUnread: _scrollToFirstUnreadFromTongue,
      // Keep history interactive during network/database waits. A retained
      // snapshot here would absorb dragging for the entire reload.
      groupAtInfoList: widget.groupAtInfoList,
      tongueItemBuilder: widget.tongueItemBuilder,
      pageHistoryPosition: _pageUi.historyPosition,
      latestMessageVisible: _latestMessageVisible,
      verifyLatestMessageVisible: _isLatestMessageRowVisible,
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    KeyboardViewportTransitionCoordinator.active?.noteHistoryBuild();
    _scheduleVisibleIncomingProgress();
    _scheduleLiveCenterRelease();
    final globalModel = context.read<TUIChatGlobalModel>();
    final freezeProjection = !globalModel
            .isSearchJumpPending(_conversationId()) &&
        (globalModel.isMessageContextMenuOverlayOpen ||
            globalModel.isContextMenuViewportRestoreActive(_conversationId()));
    if (freezeProjection) {
      // Freeze only the context-menu viewport transaction. An explicit
      // navigation owns a replacement window even when it shrinks or has
      // the same row count; buffered arrivals cannot pin the previous page.
      final currentFrozen = _contextMenuFrozenVisibleMessages;
      if (currentFrozen == null ||
          widget.messageList.length > _frozenWidgetListLen) {
        _contextMenuFrozenVisibleMessages = List<V2TimMessage?>.unmodifiable(
          _visibleMessageList(widget.messageList),
        );
        _frozenWidgetListLen = widget.messageList.length;
      }
    } else {
      _contextMenuFrozenVisibleMessages = null;
      _frozenWidgetListLen = -1;
    }
    final fullMessageList = _contextMenuFrozenVisibleMessages ??
        _visibleMessageList(widget.messageList);
    final messageList = freezeProjection
        ? fullMessageList
        : _applyInitialMountBatch(fullMessageList);
    _renderedVisibleMessages = messageList;
    _handleInitialHistoryBootstrapTransition(globalModel);
    // Never exchange this list for a spinner/empty container while history is
    // loading. That structural replacement deactivates the scroll tree just
    // as the first page arrives, loses its controller state, and produces a
    // visible hitch. The stable tree below simply has zero Sliver children
    // until the committed message window changes.
    final jumpStatus = globalModel.getSearchJumpStatus(_conversationId());
    final isSearchJump = _atJumpOrigin != null ||
        _entryUnreadOrigin != null ||
        widget.searchJumpAnchor != null ||
        widget.initFindingMsg != null;
    final stillBootstrapping = !globalModel.hasInitialHistoryLoaded(
      _conversationId(),
    );

    final rawUnreadNewMessageCount = globalModel.unreadCountForTongue;
    final dismissedEntryUnreadCount =
        globalModel.getDismissedEntryUnreadTongueCount(_conversationId());
    final completedEntryUnreadCount =
        dismissedEntryUnreadCount > _completedEntryUnreadCount
            ? dismissedEntryUnreadCount
            : _completedEntryUnreadCount;
    final unreadNewMessageCount =
        globalModel.hasLockedEntryUnreadFor(_conversationId())
            ? globalModel.lockedEntryUnreadCount
            : (rawUnreadNewMessageCount <= completedEntryUnreadCount
                ? 0
                : rawUnreadNewMessageCount);
    final tongueEnabled = UnreadTonguePolicy.isEntryUnreadEnabled(
      widget.conversation,
      unreadNewMessageCount,
    );
    final effectiveUnreadNewMessageCount =
        tongueEnabled ? unreadNewMessageCount : 0;
    final loadedRealMessageCount = _unreadAnchorMessageCount(messageList);
    final safeUnreadCount =
        effectiveUnreadNewMessageCount > loadedRealMessageCount
            ? loadedRealMessageCount
            : effectiveUnreadNewMessageCount;
    final layoutUnreadCount = _layoutUnreadCount(safeUnreadCount);
    if (ChatJitterDiag.enabled &&
        safeUnreadCount > 0 &&
        (layoutUnreadCount != _lastDiagLayoutUnread ||
            safeUnreadCount != _lastDiagLayoutSafeUnread)) {
      _lastDiagLayoutUnread = layoutUnreadCount;
      _lastDiagLayoutSafeUnread = safeUnreadCount;
      if (layoutUnreadCount < safeUnreadCount) {
        _logReadingHistoryIncoming(
          'layout_partition_deferred',
          globalModel: globalModel,
          extras: <String, Object?>{
            'safeUnread': safeUnreadCount,
            'layoutUnread': layoutUnreadCount,
            'centerSplit': layoutUnreadCount > 0,
          },
        );
      } else if (_hasLiveCenter) {
        _logReadingHistoryIncoming(
          'layout_partition_active',
          globalModel: globalModel,
          extras: <String, Object?>{
            'safeUnread': safeUnreadCount,
            'layoutUnread': layoutUnreadCount,
          },
        );
      }
    }
    final shouldShowUnreadMessage = layoutUnreadCount > 0;
    final historyOrigin = _atJumpOrigin ??
        _entryUnreadOrigin ??
        widget.searchJumpAnchor ??
        (widget.initFindingMsg == null
            ? null
            : MessageAnchor.fromConversationMessage(
                widget.conversation, widget.initFindingMsg!));
    // The split is a stable message identity, independent from the reminder
    // count. Newer pages grow before this center without moving the old rows.
    if (_hasLiveCenter &&
        (historyOrigin != null ||
            globalModel.isUserScrollToBottomInProgress(_conversationId()))) {
      _livePartitionAnchorHeadKey = null;
      _livePartitionAnchorHeadMessage = null;
      _clearBufferedRevealAnchor(reason: 'explicit_window_navigation');
    }
    var liveSplit = _hasLiveCenter
        ? messageList.indexWhere((message) =>
            message != null &&
            _messageIdentity(message) == _livePartitionAnchorHeadKey)
        : -1;
    if (_hasLiveCenter && liveSplit < 0) {
      if (!widget.model.hasHistoryReadingWindow && _isFollowingLatest()) {
        // A send/input-triggered newest-window replacement owns its new bottom.
        _livePartitionAnchorHeadKey = null;
        _livePartitionAnchorHeadMessage = null;
        _clearBufferedRevealAnchor(reason: 'replaced_latest_window');
      } else {
        final anchor = _livePartitionAnchorHeadMessage;
        liveSplit = anchor == null ? 0 : messageList.indexWhere((message) =>
            message != null &&
            TUIChatGlobalModel.compareMessagesChronological(message, anchor) <= 0);
        if (liveSplit < 0) liveSplit = messageList.length;
      }
    }
    final unreadEndPoint = historyOrigin != null
        ? searchHistorySplitIndex(messageList, historyOrigin)
        : _hasLiveCenter ? liveSplit : _realUnreadEndPoint(messageList, layoutUnreadCount);
    final tongueMetricsUnreadCount = _tongueMetricsUnreadCount(
      safeUnreadCount,
      globalModel,
    );
    if (_firstUnreadAnchorJumped &&
        globalModel.getMessageListPosition(_conversationId()) ==
            HistoryMessagePosition.bottom) {
      _firstUnreadAnchor = null;
      _firstUnreadAnchorJumped = false;
    } else {
      _captureFirstUnreadAnchor(messageList, effectiveUnreadNewMessageCount);
    }
    if (effectiveUnreadNewMessageCount > 0) {
      if (!_unreadEntryBottomPinScheduled &&
          !_firstUnreadAnchorJumped &&
          !_deferUnreadCenterPartition &&
          !_hasLiveCenter &&
          !_isReadingHistory() &&
          globalModel.getMessageListPosition(_conversationId()) ==
              HistoryMessagePosition.bottom) {
        _unreadEntryBottomPinScheduled = true;
        _schedulePinScrollToBottomOnUnreadEntry();
      }
    }
    if (globalModel.hasLockedEntryUnreadFor(_conversationId()) &&
        tongueMetricsUnreadCount > 0) {
      _scheduleUnreadTongueMetricsUpdate(messageList, tongueMetricsUnreadCount);
    }
    String getMessageIdentifier(V2TimMessage? message, int index) {
      return _stableMessageListKey(message, index);
    }

    _rebuildListPartitionsIfNeeded(
      messageList: messageList,
      safeUnreadCount: layoutUnreadCount,
      unreadEndPoint: unreadEndPoint,
      restoreVersion: globalModel.mediaPreviewRestoreVersion,
      messageListRevision: globalModel.messageListRevisionFor(
        _conversationId(),
      ),
      getMessageIdentifier: getMessageIdentifier,
    );
    final unreadMessageList = _cachedUnreadList;
    final readMessageList = _cachedReadList;
    final previousAnchor = _anchorForPreviousLoad(readMessageList) ??
        _anchorForPreviousLoad(messageList);
    final latestAnchor = _anchorForLatestLoad(messageList);
    final configuredShrinkWrap =
        widget.mainHistoryListConfig?.shrinkWrap ?? false;
    final unreadCenter = isSearchJump || shouldShowUnreadMessage || _hasLiveCenter
        ? _unreadCenterKey : null;
    _logCenterPartition(
      rawTongue: rawUnreadNewMessageCount,
      locked: globalModel.hasLockedEntryUnreadFor(_conversationId()),
      unreadNew: unreadNewMessageCount,
      tongueEnabled: tongueEnabled,
      effectiveUnread: effectiveUnreadNewMessageCount,
      loadedReal: loadedRealMessageCount,
      safeUnread: safeUnreadCount,
      layoutUnread: layoutUnreadCount,
      centerActive: unreadCenter != null,
      isSearchJump: isSearchJump,
      unreadEndPoint: unreadEndPoint,
      unreadLen: unreadMessageList.length,
      readLen: readMessageList.length,
      msgLen: messageList.length,
    );
    // Flutter does not allow CustomScrollView to use center together with
    // shrinkWrap. Keep the unread anchor behavior and disable shrinkWrap only
    // for this case to avoid breaking incoming-message rendering.
    final effectiveShrinkWrap =
        unreadCenter == null && !isSearchJump ? configuredShrinkWrap : false;
    final keyboardActive = _isKeyboardInsetActive(context);
    _routeScroll.shortHistoryKeyboardJustDismissed =
        _routeScroll.shortHistoryKeyboardWasActive && !keyboardActive;
    if (_routeScroll.shortHistoryKeyboardJustDismissed) {
      // 收起键盘：保留 latch，清 baseline 让 spacer 按完整视口重算。
      _routeScroll.shortHistoryBaselineViewportHeight = -1;
    }
    _routeScroll.shortHistoryKeyboardWasActive = keyboardActive;
    _scheduleShortHistoryTopAlignment(
      context: context,
      messageList: messageList,
      safeUnreadCount: layoutUnreadCount,
    );

    final throttleFunction = OptimizeUtils.multiThrottle((
      index,
      LoadDirection direction,
    ) async {
      final message = index >= 0 && index < readMessageList.length
          ? readMessageList[index]
          : null;
      final msgID = message?.msgID ??
          TIMUIKitChatUtils.getMessageIDWithinIndex(readMessageList, index);
      await widget.onLoadMore(msgID, direction, null, null, message);
    }, 20);

    final throttleFunctionWithMsgID = OptimizeUtils.multiThrottle((
      msgID,
      LoadDirection direction,
    ) async {
      await widget.onLoadMore(msgID, direction);
    }, 200);

    if (findingAnchor != null || findingMsg != null) {
      _scheduleScrollToFindingMsg();
    }

    final shouldShowCenterHistoryLoading = _initialSearchJumpPending ||
        (messageList.isEmpty
            ? isSearchJump
                ? jumpStatus == SearchJumpStatus.loading
                : stillBootstrapping &&
                    globalModel.hasLockedEntryUnreadFor(_conversationId()) &&
                    !_shouldSilenceInitialHistoryLoading(globalModel)
            : _shouldShowCenterHistoryLoading(
                isLoadingHistory: widget.model.isLoadingChatHistory,
                messageList: messageList,
                effectiveUnreadNewMessageCount: effectiveUnreadNewMessageCount,
                loadedRealMessageCount: loadedRealMessageCount,
                globalModel: globalModel,
              ));
    final historyLoadNotice = widget.model.historyLoadNotice?.trim() ?? '';

    var historyScrollBehavior =
        ScrollConfiguration.of(context).copyWith(scrollbars: false);
    if (PlatformUtils().isNativeDesktop) {
      historyScrollBehavior = historyScrollBehavior.copyWith(
        dragDevices: historyScrollBehavior.dragDevices
            .difference({PointerDeviceKind.mouse}),
      );
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) {
          _updateLatestMessageVisibility();
          _scheduleVisibleLatestConfirmation();
          final dim = notification.metrics.hasViewportDimension
              ? notification.metrics.viewportDimension
              : 0.0;
          final previous = _lastGeometryViewportDimension;
          _lastGeometryViewportDimension = dim > 0 ? dim : previous;
          final userScrolling =
              (_chatGlobalModel?.isChatListUserScrolling ?? false) ||
                  _userScrollGestureActive;
          if (_listGeometryLatchHeld && userScrolling) {
            final conv = _conversationId();
            _chatGlobalModel?.endGeometryViewportTransition(conv);
            _listGeometryLatchHeld = false;
            _listGeometryStableMetrics = 0;
          } else if (previous != null && dim > 0 && !userScrolling) {
            final delta = (dim - previous).abs();
            final conv = _conversationId();
            if (delta > TrueLatestEnd.geometryEpsilon) {
              if (!_listGeometryLatchHeld) {
                _chatGlobalModel?.beginGeometryViewportTransition(conv);
                _listGeometryLatchHeld = true;
              }
              _listGeometryStableMetrics = 0;
            } else if (_listGeometryLatchHeld) {
              _listGeometryStableMetrics++;
              if (_listGeometryStableMetrics >= 2) {
                _chatGlobalModel?.endGeometryViewportTransition(conv);
                _listGeometryLatchHeld = false;
                _listGeometryStableMetrics = 0;
              }
            }
          }
        }
        return false;
      },
      child: ChatHistoryWindowTransition(
      key: _windowTransitionKey,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          ScrollConfiguration(
            behavior: historyScrollBehavior,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth != 0) {
                  return false;
                }
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  // A short-window retry waits for a deliberate older drag.
                  // Merely starting a reversed drag must not release its latch.
                  if (_shortViewportPreviousPointer == null) {
                    _paginationUi.onUserDragStart();
                  }
                  if (!_initialSearchJumpPending && !_scrollToFindInFlight) {
                    // Once the result is revealed, the user's gesture owns the
                    // viewport. Do not retain the positioning cooldown for 2.6s.
                    _searchJumpStabilizeUntilMs = 0;
                  }
                  if (_paginationUi.isLoadingPrevious ||
                      _paginationUi.loadPreviousTask != null ||
                      _shouldCompensateScrollForPagination()) {
                    _paginationUserScrollSinceLoad = true;
                    _cancelPaginationRestoreForUserScroll(
                      reason: 'scroll_start_after_load',
                    );
                  }
                  _historyWindowTrimUi.cancel();
                  _historyWindowTrimIdleTimer?.cancel();
                  _historyWindowTrimIdleTimer = null;
                  _historyWindowTrimIdleRetries = 0;
                  _releaseAtJumpCenterOwnership();
                  _userScrollGestureActive = true;
                  _cancelFollowingLatestRestoreRetry();
                  _setUserScrolling(true);
                  _setCompactHistoryCacheExtent(true);
                  _cancelForcePinScroll();
                  // 只取消上推 generation，不要 snap/jump，否则会掐断用户拖动且可能丢 ScrollEnd。
                  if (_viewportInsert.viewportInsertSlideActive) {
                    _viewportInsert.viewportInsertSlideGeneration++;
                    _viewportInsert.viewportInsertSlideActive = false;
                    _releaseArmedViewportInsertReveal();
                  }
                  _clearIncomingScrollAnchor(reason: 'user_scroll_start');
                  final metrics = notification.metrics;
                  if (!_isHistoryScrollProtected &&
                      metrics.hasPixels &&
                      metrics.hasContentDimensions) {
                    _paginationUi.resetTopReachConsumedIfScrolledAway(
                      pixels: metrics.pixels,
                      maxScrollExtent: metrics.maxScrollExtent,
                    );
                  }
                } else if (notification is ScrollUpdateNotification ||
                    notification is OverscrollNotification) {
                  final latestScrollDelta =
                      notification is ScrollUpdateNotification
                          ? notification.scrollDelta ?? 0
                          : (notification as OverscrollNotification).overscroll;
                  final latestDragActive =
                      (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null) ||
                      (notification is OverscrollNotification &&
                          notification.dragDetails != null);
                  final latestUserGesture = _userScrollGestureActive ||
                      globalModel.isChatListUserScrolling ||
                      latestDragActive ||
                      _singleScrollPositionOrNull()?.userScrollDirection ==
                          ScrollDirection.forward;
                  // iOS bounce reverses delta after release without a new drag.
                  final previousUserGesture = latestScrollDelta > 0 &&
                      (latestUserGesture ||
                          _singleScrollPositionOrNull()?.userScrollDirection ==
                              ScrollDirection.reverse);
                  final shortViewportPreviousGesture =
                      _shortViewportPreviousPointer != null &&
                      _shortViewportPreviousGestureRecorded &&
                      notification.metrics.hasContentDimensions &&
                      notification.metrics.maxScrollExtent -
                              notification.metrics.minScrollExtent <=
                          1;
                  if (latestDragActive && (latestScrollDelta < 0 ||
                      (!_isInPreviousGestureBand(notification.metrics) &&
                          !shortViewportPreviousGesture))) {
                    _cancelPendingPreviousGesture();
                  }
                  if ((latestDragActive && latestScrollDelta > 0) ||
                      ((_userScrollGestureActive ||
                              globalModel.isChatListUserScrolling ||
                              latestDragActive) &&
                          !_isNearLatestScrollEdge(notification.metrics,
                              relaxed: _isSearchJumpHistoryMode(globalModel)))) {
                    _latestLoadIntent.cancel();
                  }
                  if (notification is ScrollUpdateNotification &&
                      notification.dragDetails != null &&
                      (_paginationUi.isLoadingPrevious ||
                          _paginationUi.loadPreviousTask != null ||
                          _shouldCompensateScrollForPagination())) {
                    _paginationUserScrollSinceLoad = true;
                    _cancelPaginationRestoreForUserScroll(
                      reason: 'scroll_update_after_load',
                    );
                  }
                  if (notification is ScrollUpdateNotification &&
                      notification.dragDetails != null &&
                      !_compactHistoryCacheExtent) {
                    _setCompactHistoryCacheExtent(true);
                  }
                  _syncFollowingLatestFromUserScroll(
                    userGesture: (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) ||
                        _userScrollGestureActive ||
                        globalModel.isChatListUserScrolling,
                    towardHistory: notification is ScrollUpdateNotification &&
                        (notification.scrollDelta ?? 0) > 0,
                    towardLatest: notification is ScrollUpdateNotification &&
                        (notification.scrollDelta ?? 0) < 0,
                    dragActive: notification is ScrollUpdateNotification &&
                        notification.dragDetails != null,
                  );
                  _sampleOffsetJump(notification);
                  if (globalModel.hasLockedEntryUnreadFor(_conversationId()) &&
                      tongueMetricsUnreadCount > 0) {
                    _scheduleUnreadTongueMetricsUpdate(
                      messageList,
                      tongueMetricsUnreadCount,
                    );
                  }
                  final metrics = notification.metrics;
                  _promotePreviousLoadSpinnerIfNearTop(metrics);
                  if (previousUserGesture) {
                    if (_isInPreviousGestureBand(metrics)) {
                      _rememberPreviousEdgeGesture(metrics);
                    } else if (_shouldTriggerLoadPreviousFromScroll(
                        metrics, anchor: previousAnchor)) {
                      _scheduleLoadPrevious(previousAnchor,
                          silent: !HistoryPreviousPrefetchPolicy
                              .shouldShowPreviousLoadSpinner(
                            pixels: metrics.pixels,
                            maxScrollExtent: metrics.maxScrollExtent,
                            hasPixels: metrics.hasPixels,
                            hasContentDimensions: metrics.hasContentDimensions,
                          ));
                    }
                  }
                  if (latestUserGesture &&
                      latestScrollDelta < 0 &&
                      metrics.hasPixels &&
                      metrics.hasContentDimensions) {
                    final nearLatest = _isNearLatestScrollEdge(
                      metrics,
                      relaxed: _isSearchJumpHistoryMode(globalModel),
                    );
                    if (nearLatest) {
                      _scheduleLoadLatest(
                        latestAnchor,
                        globalModel: globalModel,
                        safeUnreadCount: safeUnreadCount,
                      );
                    }
                  }
                } else if (notification is ScrollEndNotification) {
                  // 无论是否标记过 active，都清全局滚动态，防止掐断后丢 End 导致永久失灵。
                  _userScrollGestureActive = false;
                  _scheduleVisibleLatestConfirmation();
                  _scheduleHistoryWindowTrim();
                  _setUserScrolling(false);
                  _resumePaginationRestoreAfterScrollEnd();
                  _setCompactHistoryCacheExtent(false);
                  final deferBefore = _deferUnreadCenterPartition;
                  _syncFollowingLatestFromUserScroll(
                    userGesture: _userScrollGestureActive ||
                        globalModel.isChatListUserScrolling,
                    scrollEnded: true,
                  );
                  if (!_isFollowingLatest() && _isLatestMemoryWindow()) {
                    final settled = _singleScrollPositionOrNull();
                    if (settled != null &&
                        settled.hasPixels &&
                        settled.hasContentDimensions &&
                        (settled.pixels - settled.minScrollExtent) <=
                            _followingLatestEpsilonPx &&
                        globalModel.deferredIncomingBufferedCount(
                              _conversationId(),
                            ) ==
                            0 &&
                        widget.model.didAttachBufferedTowardLatestRecently) {
                      _scheduleFollowingLatestRestoreRetry();
                    }
                  }
                  _maybeReleaseUnreadCenterDeferral();
                  if (_isFollowingLatest() &&
                      globalModel.deferredIncomingBufferedCount(
                            _conversationId(),
                          ) >
                          0) {
                    _schedulePostScrollInboundFlush(globalModel);
                  }
                  if (deferBefore != _deferUnreadCenterPartition && mounted) {
                    setState(() {});
                  }
                  if (globalModel.hasLockedEntryUnreadFor(_conversationId()) &&
                      safeUnreadCount > 0) {
                    _scheduleUnreadTongueMetricsUpdate(
                      messageList,
                      tongueMetricsUnreadCount,
                      force: true,
                    );
                  }
                  if (_isHistoryScrollProtected) {
                    if (_paginationUi.ignoreScrollLoadPrevious > 0) {
                      _paginationUi.ignoreScrollLoadPrevious--;
                    }
                    return false;
                  }
                  if (_paginationUi.ignoreScrollLoadPrevious > 0) {
                    _paginationUi.ignoreScrollLoadPrevious--;
                    return false;
                  }
                  final metrics = notification.metrics;
                  // Both paging directions are driven by ScrollUpdate, not by
                  // layout completion or an idle ScrollEnd callback.
                }
                return false;
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _scheduleShortViewportHistoryFill(previousAnchor);
                  final shortHistoryBottomSpacer =
                      _displayShortHistoryBottomSpacer(
                    context,
                    messageList: messageList,
                    safeUnreadCount: layoutUnreadCount,
                    viewportHeight: constraints.maxHeight,
                  );
                  // 整页 gate Offstage 期间仍需 layout/测高；可见性由 Chat 页 gate 统一控制。
                  _evaluateHistoryOpenReveal(
                    messageList: messageList,
                    viewportHeight: constraints.maxHeight,
                  );
                  final showSearchEdgeSpace = isSearchJump &&
                      !globalModel
                          .isUserScrollToBottomInProgress(_conversationId()) &&
                      globalModel.getMessageListPosition(_conversationId()) !=
                          HistoryMessagePosition.bottom;
                  final scrollView = CustomScrollView(
                    center: unreadCenter,
                    key: widget.mainHistoryListConfig?.key,
                    primary: widget.mainHistoryListConfig?.primary,
                    physics: _buildHistoryScrollPhysics(),
                    // padding: widget.mainHistoryListConfig?.padding ?? EdgeInsets.zero,
                    // itemExtent: widget.mainHistoryListConfig?.itemExtent,
                    // prototypeItem: widget.mainHistoryListConfig?.prototypeItem,
                    cacheExtent: _effectiveHistoryCacheExtent(),
                    semanticChildCount:
                        widget.mainHistoryListConfig?.semanticChildCount,
                    dragStartBehavior:
                        widget.mainHistoryListConfig?.dragStartBehavior ??
                            DragStartBehavior.start,
                    keyboardDismissBehavior:
                        widget.mainHistoryListConfig?.keyboardDismissBehavior ??
                            ScrollViewKeyboardDismissBehavior.onDrag,
                    restorationId: widget.mainHistoryListConfig?.restorationId,
                    clipBehavior: widget.mainHistoryListConfig?.clipBehavior ??
                        Clip.hardEdge,
                    reverse: true,
                    shrinkWrap: effectiveShrinkWrap,
                    controller: _autoScrollController,
                    slivers: [
                      if (isSearchJump)
                        SearchHistoryEdgeSpace(
                            newer: true, enabled: showSearchEdgeSpace),
                      if (!isSearchJump && shortHistoryBottomSpacer > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(height: shortHistoryBottomSpacer),
                        ),
                      SliverPadding(
                        padding: widget.mainHistoryListConfig?.padding ??
                            EdgeInsets.zero,
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (BuildContext context, int index) {
                              final messageItem = unreadMessageList[index];
                              return _buildScrollMessageTile(
                                messageItem,
                                index,
                                globalIndex:
                                    _globalIndexMap[getMessageIdentifier(
                                  messageItem,
                                  index,
                                )],
                              );
                            },
                            childCount: unreadMessageList.length,
                            addRepaintBoundaries: widget.mainHistoryListConfig
                                    ?.addRepaintBoundaries ??
                                true,
                            findChildIndexCallback: (Key key) {
                              if (key is! ValueKey<String>) {
                                return null;
                              }
                              final valueKey = key;
                              final index = _unreadIndexMap[valueKey.value];
                              if (index == null ||
                                  index < 0 ||
                                  index >= unreadMessageList.length) {
                                return null;
                              }
                              return index;
                            },
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.zero,
                        key: _unreadCenterKey,
                      ),
                      SliverPadding(
                        padding: widget.mainHistoryListConfig?.padding ??
                            EdgeInsets.zero,
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (BuildContext context, int index) {
                              final messageItem = readMessageList[index];
                              return _buildScrollMessageTile(
                                messageItem,
                                index,
                                globalIndex:
                                    _globalIndexMap[getMessageIdentifier(
                                  messageItem,
                                  index,
                                )],
                              );
                            },
                            childCount: readMessageList.length,
                            addRepaintBoundaries: widget.mainHistoryListConfig
                                    ?.addRepaintBoundaries ??
                                true,
                            findChildIndexCallback: (Key key) {
                              if (key is! ValueKey<String>) {
                                return null;
                              }
                              final valueKey = key;
                              final index = _readIndexMap[valueKey.value];
                              if (index == null ||
                                  index < 0 ||
                                  index >= readMessageList.length) {
                                return null;
                              }
                              return index;
                            },
                          ),
                        ),
                      ),
                      if (isSearchJump)
                        SearchHistoryEdgeSpace(
                            newer: false, enabled: showSearchEdgeSpace),
                    ],
                  );
                  // 占位仍为满不透明时继续让真列表在下面测高；淡出开始的同一帧
                  // 再亮真列表，避免两组气泡先重叠一帧后才交接。
                  final placeholderStillOpaque = _openingPlaceholder.phase ==
                      ChatHistoryOpeningPlaceholderPhase.visible;
                  return ChatHistoryVisibility(
                    visible: !_initialSearchJumpPending &&
                        _historyOpenRevealPainted &&
                        !placeholderStillOpaque,
                    child: Listener(
                      onPointerDown: (event) {
                        final position = _singleScrollPositionOrNull();
                        if (event.kind != PointerDeviceKind.touch ||
                            _shortViewportPreviousPointer != null ||
                            !_paginationUi.previousRetryNeedsUserGesture ||
                            !widget.isAllowScroll ||
                            position == null ||
                            !_historyPhysicsAllowsUserScrolling(
                                position.physics) ||
                            !position.hasContentDimensions ||
                            position.maxScrollExtent -
                                    position.minScrollExtent >
                                1) return;
                        _shortViewportPreviousPointer = event.pointer;
                        _shortViewportPreviousPointerStart = event.position;
                        _shortViewportPreviousGestureRecorded = false;
                        _shortViewportPreviousGestureCancelled = false;
                      },
                      onPointerMove: (event) {
                        if (event.pointer != _shortViewportPreviousPointer ||
                            _shortViewportPreviousGestureCancelled) return;
                        final position = _singleScrollPositionOrNull();
                        final global =
                            _chatGlobalModel ?? widget.model.globalModel;
                        // A menu, preview or configured physics can claim an
                        // already-down pointer. Its later moves are not chat
                        // pagination intent and must not replay after unlock.
                        if (!widget.isAllowScroll ||
                            position == null ||
                            !_historyPhysicsAllowsUserScrolling(
                                position.physics) ||
                            global.isMessageContextMenuOverlayOpen ||
                            global.isContextMenuViewportRestoreActive(
                                _conversationId()) ||
                            global.shouldLockChatScrollForMediaPreview ||
                            global.isRestoringScrollAfterMediaPreview) {
                          _shortViewportPreviousGestureCancelled = true;
                          _cancelPendingPreviousGesture();
                          return;
                        }
                        if (_shortViewportPreviousGestureRecorded) {
                          if (event.delta.dy < 0) {
                            _shortViewportPreviousGestureCancelled = true;
                            _cancelPendingPreviousGesture();
                          }
                          return;
                        }
                        final delta = event.position -
                            _shortViewportPreviousPointerStart!;
                        if (delta.distance <= kTouchSlop) return;
                        if (delta.dy <= delta.dx.abs()) {
                          _shortViewportPreviousGestureCancelled = true;
                          _cancelPendingPreviousGesture();
                          return;
                        }
                        if (!position.hasContentDimensions ||
                            position.maxScrollExtent -
                                    position.minScrollExtent >
                                1) return;
                        // A non-scrollable viewport emits no drag notification.
                        // Record one gesture while retaining the failed-page
                        // latch until the queue is ready to dispatch its retry.
                        _shortViewportPreviousGestureRecorded = true;
                        _paginationUi.previousUserGestureSequence++;
                        _previousLoadQueue.cancel();
                        _latestLoadIntent.cancel();
                        _rememberPreviousEdgeGesture(position,
                            allowShortViewport: true);
                      },
                      onPointerUp: (event) {
                        if (event.pointer == _shortViewportPreviousPointer) {
                          _shortViewportPreviousPointer = null;
                          _shortViewportPreviousPointerStart = null;
                        }
                      },
                      onPointerCancel: (event) {
                        if (event.pointer == _shortViewportPreviousPointer) {
                          if (_shortViewportPreviousGestureRecorded) {
                            _cancelPendingPreviousGesture();
                          }
                          _shortViewportPreviousPointer = null;
                          _shortViewportPreviousPointerStart = null;
                        }
                      },
                      onPointerSignal: (event) {
                        // Mouse wheels have no ScrollStart dragDetails.
                        if (event is PointerScrollEvent &&
                            event.scrollDelta.dy != 0) {
                          final retryPending =
                              _paginationUi.previousRetryNeedsUserGesture;
                          _paginationUi.onUserDragStart();
                          if (event.scrollDelta.dy > 0) {
                            _cancelPendingPreviousGesture();
                          }
                          final wheelPosition = _singleScrollPositionOrNull();
                          if (event.scrollDelta.dy < 0 && wheelPosition != null) {
                            _latestLoadIntent.cancel();
                            _rememberPreviousEdgeGesture(wheelPosition);
                          }
                          // At the edge a wheel may produce no ScrollUpdate.
                          // reverse:true maps a negative wheel delta to older.
                          if (retryPending && event.scrollDelta.dy < 0) {
                            final position = _singleScrollPositionOrNull();
                            final anchor = _anchorForPreviousLoad(
                              _currentVisibleMessageList(),
                            );
                            if (position != null &&
                                position.maxScrollExtent <= 0) {
                              _scheduleShortViewportHistoryFill(anchor);
                            } else if (position != null &&
                                _shouldTriggerLoadPreviousFromScroll(
                                  position,
                                  anchor: anchor,
                                )) {
                              _scheduleLoadPrevious(anchor);
                            }
                          }
                        }
                      },
                      child: scrollView,
                    ),
                  );
                },
              ),
            ),
          ),
          if (_openingPlaceholder.shouldPaint)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _openingPlaceholderOpacity,
                  child: RepaintBoundary(
                    key: const ValueKey<String>('chat_opening_placeholder'),
                    child: ChatMessageListSkeleton(
                      theme: value.theme,
                      showAvatars: widget.conversation.type != 1,
                    ),
                  ),
                ),
              ),
            ),
          // Search positioning also sets loadingPlace=top. Its centered loader
          // takes precedence so one operation never paints two spinners.
          if (!shouldShowCenterHistoryLoading)
            ValueListenableBuilder<bool>(
              valueListenable: _topHistoryLoadingVisible,
              builder: (context, visible, child) {
                if (!visible) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: historyLoadNotice.isEmpty ? 12 : 46,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(child: _buildTopHistoryLoadingIndicator()),
                  ),
                );
              },
            ),
          if (historyLoadNotice.isNotEmpty)
            _buildHistoryLoadNotice(historyLoadNotice),
          _buildTongueContainer(messageList),
          if (shouldShowCenterHistoryLoading)
            _buildCenterHistoryLoadingOverlay(),
          // K.9：new message pill（用户不在底部时显示）
          if (_unreadCountBelowViewport > 0 && !_isPinnedToBottom)
            Positioned(
              bottom: 16,
              right: 16,
              child: _NewMessagePill(
                count: _unreadCountBelowViewport,
                onTap: _onJumpToBottomFromPill,
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _HistoryMessageListSelectorData {
  final List<V2TimMessage?> messageList;
  final int restoreVersion;
  final int messageListRevision;
  final int projectionRevision;
  final bool scrollLockedForOverlay;

  const _HistoryMessageListSelectorData({
    required this.messageList,
    required this.restoreVersion,
    required this.messageListRevision,
    required this.projectionRevision,
    required this.scrollLockedForOverlay,
  });
}

class _UnreadMessageAnchor {
  final String conversationID;
  final String identity;
  final int? seq;

  const _UnreadMessageAnchor({
    required this.conversationID,
    required this.identity,
    required this.seq,
  });
}

enum _PreviousLoadSource { edgeGesture, shortTouch, prefetch, viewportFill, trimResume }

typedef _PreviousLoadIntent = ({
  _PreviousLoadAnchor? anchor,
  _PreviousLoadSource source,
  TUIChatSeparateViewModel model,
  String conversationID,
  bool Function() windowIsCurrent,
  int gesture,
  bool silent,
  bool retryGesture,
});

class _PreviousLoadAnchor {
  final String? msgID;
  final int? seq;
  final V2TimMessage? message;

  const _PreviousLoadAnchor({
    required this.msgID,
    required this.seq,
    this.message,
  });
}

class _PaginationViewportAnchor {
  final String? msgID;
  final int? seq;
  final double viewportTop;

  const _PaginationViewportAnchor({
    required this.msgID,
    required this.seq,
    required this.viewportTop,
  });
}

class _PaginationRestoreRequest {
  final int generation;
  final double anchorPixels;
  final double anchorMaxExtent;
  final _PaginationViewportAnchor? viewportAnchor;

  const _PaginationRestoreRequest({
    required this.generation,
    required this.anchorPixels,
    required this.anchorMaxExtent,
    required this.viewportAnchor,
  });
}

class _SearchJumpTarget {
  final int? Function() resolveIndex;

  const _SearchJumpTarget({required this.resolveIndex});
}

class _FirstUnreadJumpFrameCheck {
  final int targetGlobalIndex;
  final bool isReady;
  final double topDelta;
  final double tolerance;
  final double? targetPixels;

  const _FirstUnreadJumpFrameCheck({
    required this.targetGlobalIndex,
    required this.isReady,
    required this.topDelta,
    required this.tolerance,
    this.targetPixels,
  });

  factory _FirstUnreadJumpFrameCheck.notReady(int targetGlobalIndex) {
    return _FirstUnreadJumpFrameCheck(
      targetGlobalIndex: targetGlobalIndex,
      isReady: false,
      topDelta: double.infinity,
      tolerance: 0,
    );
  }

  bool get isTopAligned => isReady && topDelta.abs() <= tolerance;
}

class _SearchJumpFrameCheck {
  final int targetGlobalIndex;
  final bool isReady;
  final double centerDelta;
  final double tolerance;
  const _SearchJumpFrameCheck({
    required this.targetGlobalIndex,
    required this.isReady,
    required this.centerDelta,
    required this.tolerance,
  });

  factory _SearchJumpFrameCheck.notReady(int targetGlobalIndex) {
    return _SearchJumpFrameCheck(
      targetGlobalIndex: targetGlobalIndex,
      isReady: false,
      centerDelta: double.infinity,
      tolerance: 0,
    );
  }

  bool get isCentered => isReady && centerDelta.abs() <= tolerance;
}

/// 仅包裹全局最新消息（globalIndex == 0），上报行高与发送浮层目标位。
/// 禁止使用 GlobalKey：未读/已读分区各有 index 0，GlobalKey 会冲突并导致列表空白。
class _HeadMessageLayoutReporter extends StatefulWidget {
  const _HeadMessageLayoutReporter({
    required this.message,
    required this.onLaidOut,
    required this.child,
  });

  final V2TimMessage message;
  final void Function(V2TimMessage message, Size size, Rect globalRect)
      onLaidOut;
  final Widget child;

  @override
  State<_HeadMessageLayoutReporter> createState() =>
      _HeadMessageLayoutReporterState();
}

class _HeadMessageLayoutReporterState
    extends State<_HeadMessageLayoutReporter> {
  int _reportAttempts = 0;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant _HeadMessageLayoutReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportIfReady());
  }

  void _reportIfReady() {
    if (!mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      if (_reportAttempts < 4) {
        _reportAttempts++;
        _scheduleReport();
      }
      return;
    }
    final offset = box.localToGlobal(Offset.zero);
    widget.onLaidOut(widget.message, box.size, offset & box.size);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MessageEnterAnimationGate extends StatefulWidget {
  final V2TimMessage message;
  final Widget child;
  final TUIChatGlobalModel globalModel;
  final String stableKey;
  final MessageEnterAnimationParams enterParams;
  final bool animateExtent;
  final VoidCallback? onEnterAnimationFinished;

  const _MessageEnterAnimationGate({
    required this.message,
    required this.child,
    required this.globalModel,
    required this.stableKey,
    required this.enterParams,
    this.animateExtent = false,
    this.onEnterAnimationFinished,
  });

  @override
  State<_MessageEnterAnimationGate> createState() =>
      _MessageEnterAnimationGateState();
}

class _MessageEnterAnimationGateState
    extends State<_MessageEnterAnimationGate> {
  late bool _showAnimation;

  @override
  void initState() {
    super.initState();
    _showAnimation = widget.globalModel.isMessageEnterAnimationPending(
      widget.message,
    );
  }

  void _onAnimationFinished() {
    widget.globalModel.finishMessageEnterAnimation(widget.message);
    widget.onEnterAnimationFinished?.call();
    if (mounted) {
      setState(() {
        _showAnimation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showAnimation) {
      return widget.child;
    }
    return ListenableBuilder(
      listenable: widget.globalModel,
      builder: (context, _) {
        var child = widget.child;
        if (widget.globalModel.shouldHideBubbleForSendFly(widget.message)) {
          child = Opacity(opacity: 0, child: child);
        }
        return ChatMessageEnterAnimation(
          key: ValueKey(widget.stableKey),
          duration: widget.enterParams.duration,
          slideCurve: widget.enterParams.slideCurve,
          fallbackSlideDistance: widget.enterParams.slideDistance,
          startOpacity: widget.enterParams.startOpacity,
          slideFromInputAnchor: widget.enterParams.slideFromInputAnchor,
          slideBelowInputOffset: widget.enterParams.slideBelowInputOffset,
          useOpacityFade: widget.enterParams.useOpacityFade,
          animateExtent: widget.animateExtent,
          extentCurve: widget.message.isSelf == true
              ? widget.enterParams.slideCurve
              : Curves.easeInOutCubic,
          onFinished: _onAnimationFinished,
          child: child,
        );
      },
    );
  }
}

String _recentMessageOrderSignature(List<V2TimMessage?> messageList) {
  if (messageList.isEmpty) {
    return 'empty';
  }
  final buffer = StringBuffer();
  final scanEnd = messageList.length > 16 ? 16 : messageList.length;
  for (var i = 0; i < scanEnd; i++) {
    final message = messageList[i];
    if (message == null || message.elemType == 11) {
      continue;
    }
    final msgID = message.msgID?.trim() ?? '';
    final id = message.id?.trim() ?? '';
    final seq = message.seq?.trim() ?? '';
    buffer.write(
      '${msgID.isNotEmpty ? msgID : id}|$seq|${message.status ?? ''};',
    );
  }
  return buffer.toString();
}

class TIMUIKitHistoryMessageListSelector extends TIMUIKitStatelessWidget {
  final Widget Function(BuildContext, List<V2TimMessage?>, Widget?) builder;
  final String conversationID;

  TIMUIKitHistoryMessageListSelector({
    Key? key,
    required this.builder,
    required this.conversationID,
  }) : super(key: key);

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    return Selector<TUIChatGlobalModel, _HistoryMessageListSelectorData>(
      builder: (context, data, child) =>
          builder(context, data.messageList, child),
      shouldRebuild: (previous, next) {
        // restoreVersion 仅用于滚动恢复调度，不应触发整表重建（否则头像会闪一下）。
        if (previous.scrollLockedForOverlay != next.scrollLockedForOverlay) {
          return true;
        }
        if (previous.projectionRevision != next.projectionRevision) {
          return true;
        }
        if (previous.messageListRevision != next.messageListRevision) {
          return true;
        }
        if (previous.messageList.length != next.messageList.length) {
          return true;
        }
        return _recentMessageOrderSignature(previous.messageList) !=
            _recentMessageOrderSignature(next.messageList);
      },
      selector: (context, model) {
        // GlobalModel publishes immutable structure. Reuse that exact display
        // projection across the model and Sliver instead of copying per notify.
        final messageList = model.getMessageList(conversationID) ??
            const <V2TimMessage>[];
        return _HistoryMessageListSelectorData(
          messageList: messageList,
          restoreVersion: model.mediaPreviewRestoreVersion,
          messageListRevision: model.messageListRevisionFor(conversationID),
          projectionRevision: model.messageProjectionRevisionFor(
            conversationID,
          ),
          scrollLockedForOverlay: model.shouldLockChatScrollForMediaPreview,
        );
      },
    );
  }
}

enum _AsyncSpacerAbsorbResult { ok, overflow, skipped }

// K.9：new message pill（用户上滑后有新消息时浮层提示）
class _NewMessagePill extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _NewMessagePill({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).primaryColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                '$count 条新消息',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
