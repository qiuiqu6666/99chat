import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/im_scale_metrics.dart';

import 'package:flutter/material.dart';
import 'package:flutter_slidable_plus_plus/flutter_slidable_plus_plus.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_entry_visibility.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
// 项 9：需要直接持有 ConversationTabStore 引用以广播冻结状态。
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_unread_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_system_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_empty_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_entry_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_feed_log.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_archived_entry_tile.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_empty_state.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_rows.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_ui.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_group_notice_entry_tile.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_row_retention.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/group_notice_feed_listenable.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_application.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart'
    show GroupSystemNoticeItem;
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_conversation_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

({int start, int end}) conversationAvatarWarmRange({
  required double offset,
  required double viewportDimension,
  required double rowExtent,
  required int rowCount,
  required int direction,
  required int lookaheadRows,
}) {
  if (rowCount <= 0 || rowExtent <= 0 || viewportDimension <= 0) {
    return (start: 0, end: 0);
  }
  final firstVisible = (offset / rowExtent).floor().clamp(0, rowCount - 1);
  final visibleCount = (viewportDimension / rowExtent).ceil();
  if (direction >= 0) {
    final start = (firstVisible + visibleCount).clamp(0, rowCount);
    return (
      start: start,
      end: (start + lookaheadRows).clamp(0, rowCount),
    );
  }
  return (
    start: (firstVisible - lookaheadRows).clamp(0, rowCount),
    end: firstVisible.clamp(0, rowCount),
  );
}

class ConversationFeedBody extends StatefulWidget {
  const ConversationFeedBody({
    super.key,
    this.workEnabled = true,
    required this.isGroupTab,
    required this.previewCacheScopeKey,
    required this.archiveScope,
    required this.theme,
    required this.feedScrollController,
    required this.scrollPhysics,
    required this.controller,
    required this.getVisibleConversations,
    required this.getArchivedConversations,
    required this.conversationTimestampMs,
    required this.buildConversationRow,
    required this.resolveConversationAvatarUrl,
    required this.onArchivedTap,
    required this.onGroupNoticeTap,
    required this.onGroupNoticePin,
    required this.onGroupNoticeToggleMute,
    required this.onGroupNoticeDelete,
    this.editingSelectionListenable,
    this.isEditingGetter,
    this.isGroupNoticeSelectedGetter,
    this.onGroupNoticeToggleSelect,
    this.onEnsureScopeHydrated,
    this.onScheduleFeedPageLoad,
    this.scopeHydrationFinished = true,
    this.folderFilterActive = false,
    this.folderEmptyMessage,
    this.feedBottomExhausted = false,
  });

  /// False while this retained home tab is offstage or covered by a route.
  /// Its last rendered tree stays mounted, but feed/list selection channels are
  /// detached so background commits do not rebuild rows.
  final bool workEnabled;
  final bool isGroupTab;
  final String previewCacheScopeKey;
  final ConversationArchiveScope archiveScope;
  final TUITheme theme;
  final ScrollController feedScrollController;
  final ScrollPhysics scrollPhysics;
  final TIMUIKitConversationController controller;
  final List<V2TimConversation> Function() getVisibleConversations;
  final List<V2TimConversation> Function() getArchivedConversations;
  final int Function(V2TimConversation conversation) conversationTimestampMs;
  final Widget Function(V2TimConversation conversation) buildConversationRow;
  final AvatarImageWarmSource Function(V2TimConversation conversation)
      resolveConversationAvatarUrl;
  final VoidCallback onArchivedTap;
  final VoidCallback onGroupNoticeTap;
  final Future<void> Function() onGroupNoticePin;
  final Future<void> Function() onGroupNoticeToggleMute;
  final Future<void> Function() onGroupNoticeDelete;
  final Listenable? editingSelectionListenable;
  final bool Function()? isEditingGetter;
  final bool Function()? isGroupNoticeSelectedGetter;
  final VoidCallback? onGroupNoticeToggleSelect;
  final VoidCallback? onEnsureScopeHydrated;
  final VoidCallback? onScheduleFeedPageLoad;
  final bool scopeHydrationFinished;

  /// 选中具体分组时隐藏归档/群通知入口行。
  final bool folderFilterActive;
  final String? folderEmptyMessage;

  /// 触底已确认无更多（本地+SDK）。
  final bool feedBottomExhausted;

  @override
  State<ConversationFeedBody> createState() => _ConversationFeedBodyState();
}

class _ConversationFeedBodyState extends State<ConversationFeedBody> {
  static final ValueNotifier<int> _inactiveFeedRevision = ValueNotifier<int>(0);
  static const int _avatarWarmLookaheadRows = 16;
  static const Duration _avatarWarmThrottleInterval =
      Duration(milliseconds: 48);

  /// 与会话行视觉高度大致对齐（按设备形态和字体缩放动态计算），用于置顶重排滚动补偿。
  ///
  /// 撤销说明：项 1 的 _MeasuredRow 会被骨架/真实 row 切换触发 setState，
  /// 导致 scroll offset 在 hydrate 过程中漂移，视觉上出现"列表回退"。
  /// 这里恢复使用纯估算值（72px），ListView.builder 用固定 itemExtent
  /// 配合 footer 行高 delegate 处理超出项，避免引入副作用。
  double get _effectiveRowExtent => conversationFeedRowExtent(context);

  late final GroupNoticeFeedListenable _groupNoticeFeedListenable;
  late Listenable _structureFeedListenable;
  String _lastFeedOrderSnapshot = '';
  List<String> _lastVisibleIds = const <String>[];
  int _lastStructureRevision = -1;
  int _cachedGroupNoticeSignature = 0;
  List<GroupSystemNoticeItem>? _cachedNotices;
  int _cachedNoticesSignature = 0;
  List<ConversationFeedRow>? _cachedFeedRows;
  Map<String, int>? _cachedRowIndexMap;
  int _cachedRowIndexSignature = 0;
  bool _cachedIncludeArchived = false;
  bool _cachedIncludeGroupNotice = false;
  bool _cachedGroupNoticePinned = false;
  Widget? _inactiveTabCachedChild;
  TUITheme? _inactiveTabCachedTheme;
  int? _inactiveTabCachedContentRevision;
  int? _inactiveTabCachedSessionGeneration;

  bool _feedTickerActive = true;
  final ConversationRowRetention _rowRetention = ConversationRowRetention();
  Timer? _avatarWarmTimer;
  double? _lastAvatarWarmOffset;
  double? _pendingAvatarWarmOffset;
  double? _pendingAvatarWarmViewport;
  int _pendingAvatarWarmDirection = 1;
  bool _hasWarmedInitialAvatarWindow = false;
  bool _isFastScrolling = false;
  Timer? _avatarWarmResumeTimer;

  /// 已处理的 PeerProfile revision，避免同一次 Bus 在 builder 路径重复套用。
  int _lastHandledPeerProfileRevision = -1;

  @override
  void initState() {
    super.initState();
    ImScaleMetrics.retain();
    _groupNoticeFeedListenable = GroupNoticeFeedListenable();
    _structureFeedListenable = _buildStructureFeedListenable();
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    widget.feedScrollController.addListener(_onPredictiveAvatarWarm);
    // 项 9：监听 isScrollingNotifier 广播冻结 sort 状态给 TabStore。
    if (widget.feedScrollController.hasClients) {
      widget.feedScrollController.position.isScrollingNotifier
          .addListener(_onScrollFreezeChange);
      _scrollFreezeListenerAttached = true;
    } else {
      widget.feedScrollController.addListener(_onFirstScrollAttach);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmInitialAvatarWindow();
      // 首次 attach 后挂上 isScrollingNotifier 监听
      if (widget.feedScrollController.hasClients &&
          !_scrollFreezeListenerAttached) {
        widget.feedScrollController.removeListener(_onFirstScrollAttach);
        widget.feedScrollController.position.isScrollingNotifier
            .addListener(_onScrollFreezeChange);
        _scrollFreezeListenerAttached = true;
      }
    });
  }

  // 项 9：滚动状态变化时通知 TabStore 冻结/解冻 sort。
  bool _scrollFreezeListenerAttached = false;
  void _onFirstScrollAttach() {
    if (!mounted || !widget.feedScrollController.hasClients) return;
    if (_scrollFreezeListenerAttached) return;
    widget.feedScrollController.removeListener(_onFirstScrollAttach);
    widget.feedScrollController.position.isScrollingNotifier
        .addListener(_onScrollFreezeChange);
    _scrollFreezeListenerAttached = true;
  }

  void _onScrollFreezeChange() {
    if (!mounted || !widget.feedScrollController.hasClients) return;
    final isScrolling =
        widget.feedScrollController.position.isScrollingNotifier.value;
    if (isScrolling) {
      _isFastScrolling = true;
      _avatarWarmTimer?.cancel();
      _avatarWarmTimer = null;
      _avatarWarmResumeTimer?.cancel();
      _avatarWarmResumeTimer = null;
    } else {
      _isFastScrolling = false;
      _avatarWarmResumeTimer?.cancel();
      _avatarWarmResumeTimer = Timer(Duration.zero, () {
        if (mounted) _drainPredictiveAvatarWarm();
      });
    }
    ConversationTabStore.instance.setSortFrozenByScroll(isScrolling);
  }

  @override
  void didUpdateWidget(covariant ConversationFeedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 非活跃 Tab 整表缓存不得跨深浅主题复用。
    if (!identical(oldWidget.theme, widget.theme)) {
      _inactiveTabCachedChild = null;
      _inactiveTabCachedTheme = null;
      _inactiveTabCachedContentRevision = null;
    }
    if (oldWidget.archiveScope != widget.archiveScope ||
        oldWidget.isGroupTab != widget.isGroupTab) {
      _structureFeedListenable = _buildStructureFeedListenable();
    }
    if (!oldWidget.workEnabled && widget.workEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _warmInitialAvatarWindow();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.of(context);
    if (!_feedTickerActive && active && widget.workEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _warmInitialAvatarWindow();
      });
    }
    _feedTickerActive = active;
  }

  /// Archive / folder / group-notice / settings / live — not list content.
  Listenable _buildStructureFeedListenable() {
    final listenables = <Listenable>[
      archivedConversationIDsNotifierFor(widget.archiveScope),
      // 分组混显单聊+群聊时，另一侧归档变化也要刷新。
      archivedConversationIDsNotifierFor(
        widget.archiveScope == ConversationArchiveScope.group
            ? ConversationArchiveScope.c2c
            : ConversationArchiveScope.group,
      ),
      ArchivedConversationEntryVisibility.instance
          .notifierFor(widget.archiveScope),
      ConversationFolderStore.instance.foldersNotifier,
      _groupNoticeFeedListenable,
      GroupNoticeEntrySettingsService.instance,
      // joinedGroupsRevision 已由 Conversation._onJoinedGroupsRevision 处理；
      // 这里再监听会让同一次 revision 触发两次整棵 Feed 重建。
    ];
    if (widget.isGroupTab) {
      listenables.add(GroupLiveIndexStore.instance);
    }
    return Listenable.merge(listenables);
  }

  @override
  void dispose() {
    ImScaleMetrics.release();
    widget.feedScrollController.removeListener(_onPredictiveAvatarWarm);
    widget.feedScrollController.removeListener(_onFirstScrollAttach);
    if (widget.feedScrollController.hasClients &&
        _scrollFreezeListenerAttached) {
      widget.feedScrollController.position.isScrollingNotifier
          .removeListener(_onScrollFreezeChange);
    }
    // 项 9：dispose 时主动解冻，避免冻结状态泄漏到下一次进入。
    ConversationTabStore.instance.setSortFrozenByScroll(false);
    _avatarWarmTimer?.cancel();
    _avatarWarmResumeTimer?.cancel();
    PeerProfileRefreshBus.instance.revision.removeListener(
      _onPeerProfileRefresh,
    );
    _groupNoticeFeedListenable.dispose();
    _rowRetention.dispose();
    super.dispose();
  }

  /// 滚动中按固定节奏预热即将进入视口的 thumb。
  ///
  /// 这里必须是 leading-edge throttle，不能做 debounce：滚动通知每帧到达，
  /// debounce 会一直被取消，最终只在用户停手后才解码，来不及服务首帧。
  void _onPredictiveAvatarWarm() {
    if (ConversationPerfFlags.conversationRowRetentionEnabled) {
      _rowRetention.scheduleProbe();
    }
    if (!mounted ||
        !_feedTickerActive ||
        _isFastScrolling ||
        !widget.feedScrollController.hasClients) {
      return;
    }
    final position = widget.feedScrollController.position;
    if (!position.isScrollingNotifier.value ||
        position.viewportDimension <= 0) {
      return;
    }
    final offset = position.pixels;
    final previous = _lastAvatarWarmOffset;
    _lastAvatarWarmOffset = offset;
    final direction = previous == null || offset >= previous ? 1 : -1;
    _pendingAvatarWarmOffset = offset;
    _pendingAvatarWarmViewport = position.viewportDimension;
    _pendingAvatarWarmDirection = direction;
    if (_avatarWarmTimer == null) {
      _drainPredictiveAvatarWarm();
    }
  }

  void _drainPredictiveAvatarWarm() {
    _avatarWarmTimer?.cancel();
    _avatarWarmTimer = null;
    final offset = _pendingAvatarWarmOffset;
    final viewport = _pendingAvatarWarmViewport;
    if (!mounted || !_feedTickerActive || offset == null || viewport == null) {
      _pendingAvatarWarmOffset = null;
      _pendingAvatarWarmViewport = null;
      return;
    }
    if (_isFastScrolling) return;
    _pendingAvatarWarmOffset = null;
    _pendingAvatarWarmViewport = null;
    final rows = widget.getVisibleConversations();
    final range = conversationAvatarWarmRange(
      offset: offset,
      viewportDimension: viewport,
      rowExtent: _effectiveRowExtent,
      rowCount: rows.length,
      direction: _pendingAvatarWarmDirection,
      lookaheadRows: _avatarWarmLookaheadRows,
    );
    _warmAvatarRange(rows, start: range.start, end: range.end);
    _avatarWarmTimer = Timer(_avatarWarmThrottleInterval, () {
      _avatarWarmTimer = null;
      if (_pendingAvatarWarmOffset != null) {
        _drainPredictiveAvatarWarm();
      }
    });
  }

  void _warmInitialAvatarWindow() {
    if (!widget.workEnabled || !_feedTickerActive) return;
    if (_hasWarmedInitialAvatarWindow) return;
    final rows = widget.getVisibleConversations();
    if (rows.isEmpty) return;
    _hasWarmedInitialAvatarWindow = true;
    final visibleCount = widget.feedScrollController.hasClients
        ? (widget.feedScrollController.position.viewportDimension /
                _effectiveRowExtent)
            .ceil()
        : 8;
    _warmAvatarRange(
      rows,
      start: 0,
      end: (visibleCount + _avatarWarmLookaheadRows).clamp(0, rows.length),
    );
  }

  void _warmAvatarRange(
    List<V2TimConversation> rows, {
    required int start,
    required int end,
  }) {
    if (!mounted || start >= end) return;
    final sources = rows
        .sublist(start, end)
        .map(widget.resolveConversationAvatarUrl)
        .where((source) => source.url?.trim().isNotEmpty == true)
        .toList(growable: false);
    if (sources.isEmpty) return;
    unawaited(
      AvatarImageWarm.warmSources(
        sources,
        context: context,
        logicalSize: conversationFeedAvatarSize(context),
      ),
    );
  }

  /// 备注等资料变更：只点名同步一条 C2C，不订阅整表 DisplayNameStore。
  void _onPeerProfileRefresh() {
    final rev = PeerProfileRefreshBus.instance.revision.value;
    if (rev == _lastHandledPeerProfileRevision) {
      return;
    }
    _lastHandledPeerProfileRevision = rev;
    final uid = PeerProfileRefreshBus.instance.lastUserId?.trim() ?? '';
    if (uid.isEmpty) {
      return;
    }
    ChatSessionController.instance.applyPeerDisplayNameFromStore(
      uid,
      busRevision: rev,
    );
  }

  static bool _sameIdSequence(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// 置顶重排后的滚动策略：保持原 offset，不滚顶、不 +H。
  ///
  /// 旧 keep_viewport 每次 +72（日志 1450→1522）会把列表往上推一截；
  /// 行高也并非固定 72，估算补偿容易过推。重排后只钉住 offset。
  void _compensateScrollForPinReorder({
    required List<String> prevVisibleIds,
    required List<String> nextVisibleIds,
    required String orderSnapshot,
  }) {
    final hint = ChatSessionController.instance.takePinReorderScrollHint();
    if (hint == null) {
      return;
    }
    final id = hint.conversationID.trim();
    final scopeFrom = prevVisibleIds.indexOf(id);
    final scopeTo = nextVisibleIds.indexOf(id);
    final controller = widget.feedScrollController;
    if (!controller.hasClients) {
      ConversationPinFlickerLog.log(
        'pin_scroll_skip',
        conversationID: id,
        extras: <String, Object?>{
          'scope': widget.previewCacheScopeKey,
          'reason': 'no_clients',
          'globalFrom': hint.fromIndex,
          'globalTo': hint.toIndex,
          'scopeFrom': scopeFrom,
          'scopeTo': scopeTo,
        },
      );
      return;
    }

    final offsetBefore = controller.offset;
    final maxBefore = controller.position.maxScrollExtent;
    final viewportH = controller.position.viewportDimension;
    final firstVisible =
        (offsetBefore / _effectiveRowExtent).floor().clamp(0, 1 << 20);
    final viewportRows =
        (viewportH / _effectiveRowExtent).ceil().clamp(1, 1 << 20) + 1;
    final lastVisible = firstVisible + viewportRows;
    final fromOnScreen =
        scopeFrom >= 0 && scopeFrom >= firstVisible && scopeFrom < lastVisible;
    final toOnScreen =
        scopeTo >= 0 && scopeTo >= firstVisible && scopeTo < lastVisible;

    // 钉住当前 offset：不 correctBy(+H)，避免「往上推一点点」。
    // 若布局把 pixels 夹出原位，下一帧拉回（绝不能跳到 0）。
    final pinnedOffset = offsetBefore;
    if (controller.hasClients &&
        (controller.offset - pinnedOffset).abs() > 0.5) {
      controller.position.correctBy(pinnedOffset - controller.offset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }
      final max = controller.position.maxScrollExtent;
      final target = pinnedOffset.clamp(0.0, max);
      if ((controller.offset - target).abs() > 1.0) {
        controller.jumpTo(target);
        ConversationPinFlickerLog.log(
          'pin_scroll_postframe',
          conversationID: id,
          extras: <String, Object?>{
            'scope': widget.previewCacheScopeKey,
            'offset': controller.offset.toStringAsFixed(1),
            'target': target.toStringAsFixed(1),
            'max': max.toStringAsFixed(1),
          },
        );
      }
    });

    ConversationPinFlickerLog.log(
      'pin_scroll_compensate',
      conversationID: id,
      extras: <String, Object?>{
        'scope': widget.previewCacheScopeKey,
        'mode': 'keep_offset',
        'fromOnScreen': fromOnScreen,
        'toOnScreen': toOnScreen,
        'viewportRows': viewportRows,
        'globalFrom': hint.fromIndex,
        'globalTo': hint.toIndex,
        'scopeFrom': scopeFrom,
        'scopeTo': scopeTo,
        'firstVisibleEst': firstVisible,
        'maxBefore': maxBefore.toStringAsFixed(1),
        'offsetBefore': offsetBefore.toStringAsFixed(1),
        'offsetAfter':
            controller.hasClients ? controller.offset.toStringAsFixed(1) : 'na',
        'deltaPx': '0.0',
        'isPinned': hint.isPinned,
        'order': orderSnapshot,
      },
    );
  }

  List<V2TimGroupApplication> _applications() {
    return GroupJoinApplicationService.instance.applications;
  }

  List<GroupSystemNoticeItem> _notices() {
    // Cache the sorted notices list: only re-copy and re-sort when the
    // source list's length or content signature changes. This avoids
    // an O(N log N) copy+sort on every structure rebuild.
    final source = GroupSystemNoticeService.instance.notices;
    final sourceLen = source.length;
    var sig = sourceLen;
    for (var i = 0; i < sourceLen; i++) {
      sig = sig * 31 + (source[i].timestamp ?? 0);
    }
    if (_cachedNotices != null && sig == _cachedNoticesSignature) {
      return _cachedNotices!;
    }
    _cachedNoticesSignature = sig;
    _cachedNotices = List<GroupSystemNoticeItem>.from(source)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _cachedNotices!;
  }

  @override
  Widget build(BuildContext context) {
    ConversationFeedPerf.increment(
      'feed_state_build',
      reason: widget.isGroupTab ? 'group' : 'c2c',
    );
    ConversationPinFlickerLog.log(
      'feed_state_build',
      extras: <String, Object?>{
        'scope': widget.previewCacheScopeKey,
        'isGroupTab': widget.isGroupTab,
      },
    );
    // 外壳固定：列表数据变化时只重建 ListView 内容，避免整页闪白。
    // ClipRect：左右滑行内容不得画出会话列表区域（尤其 Web 侧栏布局）。
    // 单聊/群聊列表不提供下拉刷新（避免误触触发全量 sync）。
    // Outer: archive / folder / group-notice chrome. Inner: list content only.
    return ClipRect(
      child: SlidableAutoCloseBehavior(
        child: AnimatedBuilder(
          animation: widget.workEnabled
              ? _structureFeedListenable
              : const _ConversationFeedNeverListenable(),
          builder: (context, _) => ValueListenableBuilder<int>(
            valueListenable: widget.workEnabled
                ? ChatSessionController.instance.feedRevision
                : _inactiveFeedRevision,
            builder: (context, _, __) => _buildCurrentFeed(context),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentFeed(BuildContext context) {
    final sessionGeneration =
        ChatSessionController.instance.windowState.sessionGeneration;
    if (_inactiveTabCachedSessionGeneration != sessionGeneration) {
      _inactiveTabCachedChild = null;
    }
    ConversationFeedPerf.increment(
      'feed_revision_listener_build',
      reason: widget.workEnabled ? 'active' : 'inactive',
    );
    // Keep the mounted list while hidden, even if SDK content has advanced.
    // Active entry always reads current data; no stale revision is acknowledged.
    // This gate precedes group-notice scans and visible-row materialization.
    if (!widget.workEnabled &&
        _inactiveTabCachedChild != null &&
        identical(_inactiveTabCachedTheme, widget.theme)) {
      ConversationFeedPerf.increment('feed_inactive_cache_hit');
      return _inactiveTabCachedChild!;
    }
    final applications = _applications();
    final notices = _notices();
    final settings = GroupNoticeEntrySettingsService.instance;
    final includeArchivedEntry = !widget.folderFilterActive &&
        ArchivedConversationEntryVisibility.instance
            .shouldShow(widget.archiveScope);
    final includeGroupNoticeEntry =
        !widget.folderFilterActive && widget.isGroupTab;
    final noticeSignature = groupNoticeFeedSignature(
      applications: applications,
      notices: notices,
      includeGroupNoticeEntry: includeGroupNoticeEntry,
      groupNoticePinned: settings.isPinned,
      dismissWatermarkMs: settings.dismissWatermarkMs,
    );
    if (includeGroupNoticeEntry ||
        noticeSignature != _cachedGroupNoticeSignature) {
      GroupNoticeFeedLog.log('feed_structure', extras: {
        'scope': widget.previewCacheScopeKey,
        'isGroupTab': widget.isGroupTab,
        'include': includeGroupNoticeEntry,
        'sigChanged': noticeSignature != _cachedGroupNoticeSignature,
        'sig': noticeSignature,
        'prevSig': _cachedGroupNoticeSignature,
        'pinned': settings.isPinned,
        'dismissWm': settings.dismissWatermarkMs,
        'snap': GroupNoticeFeedLog.snapshot(
          applications: applications,
          notices: notices,
          signature: noticeSignature,
          unread: GroupNoticeUnreadService.instance.unreadCount,
        ),
      });
    }

    return _buildFeedForSession(
      context: context,
      applications: applications,
      notices: notices,
      settings: settings,
      includeArchivedEntry: includeArchivedEntry,
      includeGroupNoticeEntry: includeGroupNoticeEntry,
      noticeSignature: noticeSignature,
    );
  }

  Widget _buildFeedForSession({
    required BuildContext context,
    required List<V2TimGroupApplication> applications,
    required List<GroupSystemNoticeItem> notices,
    required GroupNoticeEntrySettingsService settings,
    required bool includeArchivedEntry,
    required bool includeGroupNoticeEntry,
    required int noticeSignature,
  }) {
    final buildWatch =
        ConversationFeedPerf.isEnabled ? (Stopwatch()..start()) : null;
    // 非活跃且主题 identity / contentRevision 未变：复用整表缓存。
    // 变了才重建（C1-a 新鲜度）。主题 identity 变化时清空缓存（见 didUpdateWidget）。
    // 进首页路由转场时当前 Tab 也可能 TickerMode=false；
    // 缓存为空时仍要 build 一次，避免启动图结束后先空壳再灌列表。
    final tabActive = TickerMode.of(context);
    final contentRevision = ChatSessionController.instance.contentRevision;
    if (shouldReuseInactiveConversationFeed(
      tabActive: tabActive,
      hasCachedChild: _inactiveTabCachedChild != null,
      cachedThemeToken: _inactiveTabCachedTheme,
      currentThemeToken: widget.theme,
      cachedContentRevision: _inactiveTabCachedContentRevision,
      currentContentRevision: contentRevision,
    )) {
      ConversationFeedPerf.increment('feed_inactive_cache_hit');
      buildWatch?.stop();
      ConversationFeedPerf.recordDurationMicros(
        'feed_build',
        buildWatch?.elapsedMicroseconds ?? 0,
      );
      return _inactiveTabCachedChild!;
    }
    if (!tabActive && _inactiveTabCachedChild == null) {
      ConversationPinFlickerLog.log(
        'feed_list_prime_while_inactive',
        extras: <String, Object?>{
          'scope': widget.previewCacheScopeKey,
        },
      );
    } else if (!tabActive) {
      ConversationPinFlickerLog.log(
        'feed_list_inactive_rebuild',
        extras: <String, Object?>{
          'scope': widget.previewCacheScopeKey,
          'contentRevision': contentRevision,
        },
      );
    }

    final structureRevision = ChatSessionController.instance.structureRevision;
    // The feed must be driven by the committed conversation snapshot. The
    // virtual path exposes the total row count before its async hydrate window
    // is ready, so ListView asks for real indices that have no conversation
    // object yet and paints gaps (or skeletons) during a fling. Pagination
    // appends to this snapshot without removing its head.
    final emptyMessage = widget.folderEmptyMessage ??
        (widget.isGroupTab
            ? AppI18n.of(context).t(
                zhHans: '暂无群聊',
                zhHant: '暫無群聊',
                en: 'No groups yet',
                ja: 'グループはありません',
                ko: '그룹이 없습니다',
              )
            : AppI18n.of(context).t(
                zhHans: '暂无会话',
                zhHant: '暫無會話',
                en: 'No chats yet',
                ja: '会話はありません',
                ko: '대화가 없습니다',
              ));

    final visibleWatch =
        ConversationFeedPerf.isEnabled ? (Stopwatch()..start()) : null;
    final visibleConversations = widget.getVisibleConversations();
    visibleWatch?.stop();
    ConversationFeedPerf.recordDurationMicros(
      'feed_visible_materialization',
      visibleWatch?.elapsedMicroseconds ?? 0,
    );
    if (visibleConversations.isEmpty &&
        !ConversationListSyncNotifier.instance.isSyncing &&
        !widget.scopeHydrationFinished) {
      widget.onEnsureScopeHydrated?.call();
    }
    final nextVisibleIds = visibleConversations
        .map((c) => c.conversationID.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final canPatchStructure = structureRevision == _lastStructureRevision &&
        _cachedFeedRows != null &&
        _sameIdSequence(_lastVisibleIds, nextVisibleIds) &&
        includeArchivedEntry == _cachedIncludeArchived &&
        includeGroupNoticeEntry == _cachedIncludeGroupNotice &&
        settings.isPinned == _cachedGroupNoticePinned &&
        noticeSignature == _cachedGroupNoticeSignature;
    final List<ConversationFeedRow> rows;
    final rowsWatch =
        ConversationFeedPerf.isEnabled ? (Stopwatch()..start()) : null;
    if (canPatchStructure) {
      ConversationFeedPerf.increment('feed_rows_patch');
      rows = patchConversationFeedRowsById(
        cached: _cachedFeedRows!,
        visible: visibleConversations,
        conversationTimestampMs: widget.conversationTimestampMs,
      );
      ConversationFeedPerf.increment(
        identical(rows, _cachedFeedRows)
            ? 'feed_rows_patch_noop'
            : 'feed_rows_patch_changed',
      );
    } else {
      ConversationFeedPerf.increment('feed_rows_full_build');
      rows = buildConversationFeedRows(
        conversations: visibleConversations,
        includeArchivedEntry: includeArchivedEntry,
        includeGroupNoticeEntry: includeGroupNoticeEntry,
        applications: applications,
        notices: notices,
        conversationTimestampMs: widget.conversationTimestampMs,
        groupNoticePinned: settings.isPinned,
        groupNoticeDismissWatermarkMs: settings.dismissWatermarkMs,
      );
    }
    rowsWatch?.stop();
    ConversationFeedPerf.recordDurationMicros(
      'feed_rows_build',
      rowsWatch?.elapsedMicroseconds ?? 0,
    );
    _cachedFeedRows = rows;
    _lastStructureRevision = structureRevision;
    _cachedIncludeArchived = includeArchivedEntry;
    _cachedIncludeGroupNotice = includeGroupNoticeEntry;
    _cachedGroupNoticePinned = settings.isPinned;
    _cachedGroupNoticeSignature = noticeSignature;
    // 虚拟列表通过 typeIndex 定位子项，不需要构建整窗 ID→index map。
    // 该 map 仅供普通 ListView 的 findChildIndexCallback 使用。
    // Cache the map: only rebuild when the row list signature changes.
    Map<String, int> rowIndexByConversationId;
    {
      var sig = rows.length;
      for (var i = 0; i < rows.length; i++) {
        final id = rows[i].conversation?.conversationID ?? '';
        sig = sig * 31 + id.hashCode;
      }
      if (_cachedRowIndexMap != null && sig == _cachedRowIndexSignature) {
        rowIndexByConversationId = _cachedRowIndexMap!;
      } else {
        rowIndexByConversationId = <String, int>{};
        for (var i = 0; i < rows.length; i++) {
          final id = rows[i].conversation?.conversationID;
          if (id != null && id.isNotEmpty) {
            rowIndexByConversationId[
                ConversationTabStore.instance.rowIdentityKey(id)] = i;
          }
        }
        _cachedRowIndexMap = rowIndexByConversationId;
        _cachedRowIndexSignature = sig;
      }
    }
    final order = ConversationPinFlickerLog.orderSnapshot(
      visibleConversations,
    );
    final prevVisibleIds = _lastVisibleIds;
    if (tabActive &&
        prevVisibleIds.isEmpty &&
        nextVisibleIds.isNotEmpty &&
        !_hasWarmedInitialAvatarWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _warmInitialAvatarWindow();
      });
    }
    // 长列表勿 join 全量 ID 串：用长度+hash 判序变更即可。
    var idsHash = nextVisibleIds.length;
    for (final id in nextVisibleIds) {
      idsHash = Object.hash(idsHash, id);
    }
    final idsOrder = '${nextVisibleIds.length}:$idsHash';
    final orderChanged = idsOrder != _lastFeedOrderSnapshot;
    _lastFeedOrderSnapshot = idsOrder;
    _lastVisibleIds = nextVisibleIds;
    final scrollOffset = widget.feedScrollController.hasClients
        ? widget.feedScrollController.offset
        : -1.0;
    final firstVisibleEst =
        scrollOffset < 0 ? -1 : (scrollOffset / _effectiveRowExtent).floor();
    ConversationPinFlickerLog.log(
      'feed_list_rebuild',
      extras: <String, Object?>{
        'scope': widget.previewCacheScopeKey,
        'rows': rows.length,
        'visible': visibleConversations.length,
        'orderChanged': orderChanged,
        'tabActive': tabActive,
        'deferring': ChatSessionController.instance.isDeferringPinReorder,
        'scroll': scrollOffset < 0 ? 'na' : scrollOffset.toStringAsFixed(1),
        'firstVisibleEst': firstVisibleEst,
        'order': order,
      },
    );
    ConversationFeedPerf.increment(
      'feed_list_rebuild',
      reason: tabActive ? 'active' : 'inactive',
    );
    ConversationFeedPerf.gauge('feed_rows', rows.length);
    ConversationFeedPerf.gauge(
      'feed_visible',
      visibleConversations.length,
    );
    ConversationFeedPerf.gauge('structureRevision', structureRevision);
    ConversationFeedPerf.gauge(
      'feedRevision',
      ChatSessionController.instance.feedRevision.value,
    );
    if (tabActive) {
      _compensateScrollForPinReorder(
        prevVisibleIds: prevVisibleIds,
        nextVisibleIds: nextVisibleIds,
        orderSnapshot: order,
      );
    }

    final built = rows.isEmpty
        ? ConversationFeedEmptyState(
            isGroupTab: widget.isGroupTab,
            businessEmptyBuilder: (context) => AppEmptyState(
              padding: const EdgeInsets.only(top: 80),
              message: emptyMessage,
            ),
          )
        : _buildFeedListView(
            rows: rows,
            rowIndexByConversationId: rowIndexByConversationId,
            settings: settings,
          );
    _inactiveTabCachedChild = built;
    _inactiveTabCachedTheme = widget.theme;
    _inactiveTabCachedContentRevision = contentRevision;
    _inactiveTabCachedSessionGeneration =
        ChatSessionController.instance.windowState.sessionGeneration;
    buildWatch?.stop();
    ConversationFeedPerf.recordDurationMicros(
      'feed_build',
      buildWatch?.elapsedMicroseconds ?? 0,
    );
    return built;
  }

  /// 列表级分割线：会话 item 本身只负责内容，分割线统一由 feed 槽位绘制。
  Widget _buildFeedRowWithDivider(
    BuildContext context,
    Widget child, {
    required bool showDivider,
    bool editing = false,
  }) {
    return ConversationFeedRowFrame(
      key: child.key,
      showDivider: showDivider,
      dividerInset: conversationFeedDividerInset(context, editing: editing),
      dividerColor: widget.theme.weakDividerColor ?? const Color(0xFFE5E6E9),
      child: child,
    );
  }

  Widget _buildFeedListView({
    required List<ConversationFeedRow> rows,
    required Map<String, int> rowIndexByConversationId,
    required GroupNoticeEntrySettingsService settings,
  }) {
    final showExhaustedFooter = widget.feedBottomExhausted;
    final extra = showExhaustedFooter ? 1 : 0;

    return ListView.builder(
      key: PageStorageKey<String>(
        'conversation_feed_${widget.previewCacheScopeKey}',
      ),
      controller: widget.feedScrollController,
      physics: widget.scrollPhysics,
      addAutomaticKeepAlives:
          ConversationPerfFlags.conversationRowRetentionEnabled,
      cacheExtent: ConversationPerfFlags.conversationFeedCacheExtent,
      // Fixed item extent for all conversation rows. The footer is
      // taller than a row, but ListView.builder with itemExtent
      // delegates the last item's height to the builder when it
      // exceeds itemExtent. This eliminates per-frame layout for the
      // vast majority of rows during scroll — the single biggest
      // difference from Telegram's scroll smoothness.
      itemExtent: _effectiveRowExtent,
      itemCount: rows.length + extra,
      findChildIndexCallback: (Key key) {
        if (key is! ValueKey<String>) {
          return null;
        }
        return rowIndexByConversationId[key.value];
      },
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                AppI18n.of(context).t(
                  zhHans: '没有更多了',
                  zhHant: '沒有更多了',
                  en: 'No more',
                  ja: 'これ以上ありません',
                  ko: '더 이상 없음',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.weakTextColor,
                ),
              ),
            ),
          );
        }
        final row = rows[index];
        final showDivider = index < rows.length - 1;
        final editing = widget.isEditingGetter?.call() ?? false;
        if (row.kind == ConversationFeedRowKind.archived) {
          return _buildFeedRowWithDivider(
            context,
            ConversationArchivedEntryTile(
              theme: widget.theme,
              archiveScope: widget.archiveScope,
              getArchivedConversations: widget.getArchivedConversations,
              onTap: widget.onArchivedTap,
            ),
            showDivider: showDivider,
            editing: editing,
          );
        }
        if (row.kind == ConversationFeedRowKind.groupNotice) {
          final listenable = widget.editingSelectionListenable;
          Widget buildNoticeTile() {
            final editing = widget.isEditingGetter?.call() ?? false;
            final selected =
                widget.isGroupNoticeSelectedGetter?.call() ?? false;
            return ConversationGroupNoticeEntryTile(
              theme: widget.theme,
              controller: widget.controller,
              onTap: widget.onGroupNoticeTap,
              onPin: widget.onGroupNoticePin,
              onToggleMute: widget.onGroupNoticeToggleMute,
              onDelete: widget.onGroupNoticeDelete,
              isPinned: settings.isPinned,
              isMuted: settings.isMuted,
              isEditing: editing,
              isSelected: selected,
              onToggleSelect: widget.onGroupNoticeToggleSelect,
              wrapWithSlidable: !editing,
            );
          }

          if (listenable == null) {
            return _buildFeedRowWithDivider(
              context,
              buildNoticeTile(),
              showDivider: showDivider,
              editing: editing,
            );
          }
          return _buildFeedRowWithDivider(
            context,
            AnimatedBuilder(
              animation: listenable,
              builder: (context, _) => buildNoticeTile(),
            ),
            showDivider: showDivider,
            editing: editing,
          );
        }
        final conversation = row.conversation;
        if (conversation == null) {
          return const SizedBox.shrink();
        }
        final identity = ConversationTabStore.instance
            .rowIdentityKey(conversation.conversationID);
        final retainEnabled =
            ConversationPerfFlags.conversationRowRetentionEnabled;
        final slot = _ConversationFeedRowSlot(
          key: retainEnabled ? null : ValueKey(identity),
          conversation: conversation,
          themeToken: widget.theme,
          builder: widget.buildConversationRow,
        );
        return _buildFeedRowWithDivider(
          context,
          retainEnabled
              ? ConversationRowRetentionHost(
                  key: ValueKey(identity),
                  identity: identity,
                  retention: _rowRetention,
                  child: slot,
                )
              : slot,
          showDivider: showDivider,
          editing: editing,
        );
      },
    );
  }
}

/// The Sliver must see the conversation key on its direct child. Keeping this
/// frame shape when the last row gains a divider also preserves that row's
/// avatar, swipe controller and cached preview when another page is appended.
class ConversationFeedRowFrame extends StatelessWidget {
  const ConversationFeedRowFrame({
    super.key,
    required this.child,
    required this.showDivider,
    required this.dividerInset,
    required this.dividerColor,
  });

  final Widget child;
  final bool showDivider;
  final double dividerInset;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _ConversationDividerPainter(
          showDivider: showDivider,
          inset: dividerInset,
          color: dividerColor,
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: showDivider ? 0.6 : 0),
          child: child,
        ),
      );
}

class _ConversationDividerPainter extends CustomPainter {
  const _ConversationDividerPainter({
    required this.showDivider,
    required this.inset,
    required this.color,
  });

  final bool showDivider;
  final double inset;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showDivider) return;
    canvas.drawRect(
      Rect.fromLTRB(inset.clamp(0.0, size.width),
          (size.height - 0.6).clamp(0.0, size.height), size.width, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ConversationDividerPainter oldDelegate) =>
      showDivider != oldDelegate.showDivider ||
      inset != oldDelegate.inset ||
      color != oldDelegate.color;
}

class _ConversationFeedNeverListenable implements Listenable {
  const _ConversationFeedNeverListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// 会话行槽位：数据指纹与主题令牌均未变时复用同一 child，避免无关刷新打断左右滑。
/// 主题切换（[themeToken] 身份变化）必须失效缓存，否则可见行会残留旧背景色。
class _ConversationFeedRowSlot extends StatefulWidget {
  const _ConversationFeedRowSlot({
    super.key,
    required this.conversation,
    required this.themeToken,
    required this.builder,
  });

  final V2TimConversation conversation;
  final TUITheme themeToken;
  final Widget Function(V2TimConversation conversation) builder;

  @override
  State<_ConversationFeedRowSlot> createState() =>
      _ConversationFeedRowSlotState();
}

class _ConversationFeedRowSlotState extends State<_ConversationFeedRowSlot> {
  late int _fingerprint;
  late TUITheme _themeToken;
  late Widget Function(V2TimConversation conversation) _builder;
  late Widget _child;

  @override
  void initState() {
    super.initState();
    _fingerprint = ChatSessionController.conversationUiFingerprintHash(
      widget.conversation,
    );
    _themeToken = widget.themeToken;
    _builder = widget.builder;
    // ListView's default per-child repaint boundary already owns this row.
    _child = widget.builder(widget.conversation);
    ConversationFeedPerf.increment('feed_row_create');
  }

  @override
  void didUpdateWidget(covariant _ConversationFeedRowSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFingerprint = ChatSessionController.conversationUiFingerprintHash(
      widget.conversation,
    );
    final builderChanged = !identical(widget.builder, _builder);
    final needsRebuild = conversationFeedRowSlotNeedsRebuild(
      nextFingerprint: nextFingerprint,
      currentFingerprint: _fingerprint,
      nextThemeToken: widget.themeToken,
      currentThemeToken: _themeToken,
    );
    // 指纹与主题均未变则复用行；忽略 builder 引用变化（父页 setState 常导致 tear-off 重绑）。
    if (!needsRebuild) {
      ConversationFeedPerf.increment('feed_row_reuse');
      if (builderChanged) {
        _builder = widget.builder;
      }
      return;
    }
    final oldPinned = oldWidget.conversation.isPinned == true;
    final newPinned = widget.conversation.isPinned == true;
    final themeChanged = !identical(widget.themeToken, _themeToken);
    ConversationFeedPerf.increment(
      'feed_row_rebuild',
      reason: themeChanged ? 'theme' : 'data',
    );
    ConversationPinFlickerLog.log(
      'feed_row_rebuild',
      conversationID: widget.conversation.conversationID,
      extras: <String, Object?>{
        'pinChanged': oldPinned != newPinned,
        'oldPinned': oldPinned,
        'newPinned': newPinned,
        'builderChanged': builderChanged,
        'themeChanged': themeChanged,
      },
    );
    _fingerprint = nextFingerprint;
    _themeToken = widget.themeToken;
    _builder = widget.builder;
    _child = widget.builder(widget.conversation);
  }

  @override
  Widget build(BuildContext context) => _child;
}
