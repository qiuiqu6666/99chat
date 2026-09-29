**A 包完整源码摘录**

这些是当前工作树的原文快照，不是修改后的实现。用 Dart AST 边界提取完整方法/类型，保留原文件路径、起止行号和哈希；依赖导入和未摘录上下文可回到原文件核对。

1. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/navigation/app_chat_route.dart:1>)，原文件 lib/src/navigation/app_chat_route.dart，1–353 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/chat.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_viewport_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_pipeline_clock.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';

/// Telegram-style route presence registry: a conversation owns at most one
/// active Chat route in the same Navigator. It does not share Chat State across
/// conversations; it only lets callers return to an existing conversation
/// route instead of stacking a duplicate instance.
class AppChatRouteRegistry {
  AppChatRouteRegistry._();

  static final AppChatRouteRegistry instance = AppChatRouteRegistry._();

  final Map<NavigatorState, Map<String, List<Route<dynamic>>>> _routes =
      <NavigatorState, Map<String, List<Route<dynamic>>>>{};

  void register({
    required NavigatorState navigator,
    required String sessionKey,
    required Route<dynamic> route,
  }) {
    final key = sessionKey.trim();
    if (key.isEmpty) {
      return;
    }
    final routes =
        (_routes[navigator] ??= <String, List<Route<dynamic>>>{}).putIfAbsent(
      key,
      () => <Route<dynamic>>[],
    );
    routes.removeWhere((candidate) => identical(candidate, route));
    routes.add(route);
  }

  void unregister({
    required NavigatorState navigator,
    required String sessionKey,
    required Route<dynamic> route,
  }) {
    final routes = _routes[navigator];
    if (routes == null) {
      return;
    }
    final key = sessionKey.trim();
    final sessionRoutes = routes[key];
    sessionRoutes?.removeWhere((candidate) => identical(candidate, route));
    if (sessionRoutes?.isEmpty ?? false) {
      routes.remove(key);
    }
    if (routes.isEmpty) {
      _routes.remove(navigator);
    }
  }

  Route<dynamic>? activeRoute(
    NavigatorState navigator,
    String sessionKey,
  ) {
    final key = sessionKey.trim();
    final navigatorRoutes = _routes[navigator];
    final sessionRoutes = navigatorRoutes?[key];
    if (sessionRoutes == null) {
      return null;
    }
    sessionRoutes.removeWhere(
      (route) => !route.isActive || !identical(route.navigator, navigator),
    );
    if (sessionRoutes.isEmpty) {
      navigatorRoutes?.remove(key);
      if (navigatorRoutes?.isEmpty ?? false) {
        _routes.remove(navigator);
      }
      return null;
    }
    return sessionRoutes.last;
  }

  @visibleForTesting
  void reset() => _routes.clear();

  /// Defensive helper: returns true iff at least one active Chat route is
  /// currently registered in any navigator. Used by callers that want to
  /// distinguish "ActiveChatRegistry still remembers a conversation id" from
  /// "an actual Chat route is mounted right now". Helps prevent UI notifies
  /// from being deferred forever when registry state is orphaned (e.g.
  /// dispose path that throws before reaching `leave`).
  bool hasAnyActiveChatRoute() {
    for (final navigatorRoutes in _routes.values) {
      for (final sessionRoutes in navigatorRoutes.values) {
        if (sessionRoutes.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}

String appChatSessionKey(V2TimConversation conversation) {
  final resolved = MessageConversationId.resolve(
        conversationID: conversation.conversationID,
        groupID: conversation.groupID,
        userID: conversation.userID,
      ) ??
      '';
  final comparable = MessageConversationId.normalizeComparableKey(resolved);
  if (comparable.isEmpty) {
    return '';
  }
  final isGroup = conversation.type == 2 ||
      (conversation.groupID?.trim().isNotEmpty ?? false) ||
      MessageConversationId.looksLikeGroupConversationId(resolved);
  return '${isGroup ? 'group' : 'c2c'}:$comparable';
}

class _AppChatRoutePresence extends StatefulWidget {
  const _AppChatRoutePresence({
    required this.sessionKey,
    required this.child,
  });

  final String sessionKey;
  final Widget child;

  @override
  State<_AppChatRoutePresence> createState() => _AppChatRoutePresenceState();
}

class _AppChatRoutePresenceState extends State<_AppChatRoutePresence> {
  NavigatorState? _navigator;
  Route<dynamic>? _route;
  Animation<double>? _primaryAnimation;
  Animation<double>? _secondaryAnimation;

  void _updateInteractionGate([AnimationStatus? _]) {
    bool moving(Animation<double>? animation) =>
        animation?.status == AnimationStatus.forward ||
        animation?.status == AnimationStatus.reverse;
    BackgroundMediaGate.instance.setBusy(
      this, moving(_primaryAnimation) || moving(_secondaryAnimation),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route == null ||
        (identical(_navigator, navigator) && identical(_route, route))) {
      return;
    }
    _unregister();
    _navigator = navigator;
    _route = route;
    _primaryAnimation = route.animation;
    _secondaryAnimation = route.secondaryAnimation;
    _primaryAnimation?.addStatusListener(_updateInteractionGate);
    _secondaryAnimation?.addStatusListener(_updateInteractionGate);
    _updateInteractionGate();
    AppChatRouteRegistry.instance.register(
      navigator: navigator,
      sessionKey: widget.sessionKey,
      route: route,
    );
  }

  void _unregister() {
    _primaryAnimation?.removeStatusListener(_updateInteractionGate);
    _secondaryAnimation?.removeStatusListener(_updateInteractionGate);
    _primaryAnimation = null;
    _secondaryAnimation = null;
    BackgroundMediaGate.instance.setBusy(this, false);
    final navigator = _navigator;
    final route = _route;
    if (navigator == null || route == null) {
      return;
    }
    AppChatRouteRegistry.instance.unregister(
      navigator: navigator,
      sessionKey: widget.sessionKey,
      route: route,
    );
    _navigator = null;
    _route = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Route<T> appChatRoute<T>(
  V2TimConversation conversation, {
  int? entryUnreadCount,
  V2TimMessage? initFindingMsg,
  MessageAnchor? searchJumpAnchor,
  bool? initialC2cCanMessage,
  String? c2cPermissionHintSource,
}) {
  final resolvedAnchor = searchJumpAnchor ??
      (initFindingMsg == null
          ? null
          : MessageAnchor.fromConversationMessage(
              conversation,
              initFindingMsg,
            ));
  final sessionKey = appChatSessionKey(conversation);
  return AppMaterialPageRoute<T>(
    settings: const RouteSettings(name: AppRoutes.chat),
    // 聊天页禁止转场 snapshot：转场结束切回 live 树时会卸掉消息列表 State，
    // 表现为 t+300ms partition_cache_miss 全字段 -1→N 的整表重建抖动。
    allowSnapshotting: false,
    routeVisibilityDeferredFrames: 1,
    // 消息列表与上推动画抢边缘命中时，略加宽左缘返回条更稳。
    edgeStartWidthPx: 40,
    builder: (_) => _AppChatRoutePresence(
      sessionKey: sessionKey,
      child: RepaintBoundary(
        // 侧滑只合成图层，避免 20 条气泡跟着手势每帧 relayout。
        child: Chat(
          key: ValueKey<String>('chat_session_$sessionKey'),
          selectedConversation: conversation,
          entryUnreadCount: entryUnreadCount,
          initFindingMsg: initFindingMsg,
          searchJumpAnchor: resolvedAnchor,
          initialC2cCanMessage: initialC2cCanMessage,
          c2cPermissionHintSource: c2cPermissionHintSource,
        ),
      ),
    ),
  );
}

/// Opens a conversation or returns to its existing active route in this
/// Navigator. Different conversations never share a Chat State.
Future<T?> openOrReuseAppChat<T>(
  BuildContext context,
  V2TimConversation conversation, {
  int? entryUnreadCount,
  V2TimMessage? initFindingMsg,
  MessageAnchor? searchJumpAnchor,
  bool? initialC2cCanMessage,
  String? c2cPermissionHintSource,
}) async {
  if (!context.mounted) {
    return Future<T?>.value();
  }
  final navigator = Navigator.of(context);
  final sessionKey = appChatSessionKey(conversation);
  // Pipeline [2] - push_begin：进入 openOrReuseAppChat 主流程
  // 用 normalizeKey 与 conversation.dart / chat.dart / UIKit 内的 key 保持一致。
  final pipelineKey = ChatPipelineClock.normalizeKey(
    rawConversationId: conversation.conversationID,
    userId: conversation.userID,
    groupId: conversation.groupID,
  );
  ChatPipelineClock.instance.trace(pipelineKey, 'push_begin',
      extras: <String, Object?>{'canReuse': initFindingMsg == null && searchJumpAnchor == null});
  // Search/anchor opens carry a new navigation subject. Until the existing
  // Chat State exposes an in-place target-message activation API, preserve the
  // established dedicated route semantics instead of silently dropping it.
  final canReuse = initFindingMsg == null && searchJumpAnchor == null;
  final existing = canReuse
      ? AppChatRouteRegistry.instance.activeRoute(navigator, sessionKey)
      : null;
  if (existing != null) {
    if (!existing.isCurrent) {
      navigator.popUntil((route) => identical(route, existing));
    }
    // Keep the same completion contract as Navigator.push: callers awaiting
    // this helper must resume only after the chat route is actually popped.
    // Returning an already-completed Future here makes a reused route look as
    // if the user had left chat, which can trigger unread finalize/hydrate
    // while the reused chat is still visible.
    return existing.popped.then<T?>((value) {
      if (value == null) {
        return null;
      }
      return value is T ? value : null;
    });
  }
  // 只等本地 fast classify。H0 由 prepareOpenViewport 并行启动，不阻塞 push。
  final waitStart = DateTime.now();
  try {
    final media = MediaQuery.maybeOf(context);
    final viewportHeight = (media?.size.height ?? 640) -
        (media?.padding.top ?? 0) -
        kToolbarHeight -
        56;
    await ChatOpenViewportCoordinator.instance.prepareOpenViewport(
      conversation: conversation,
      viewportHeight: viewportHeight,
      source: 'route',
    );
  } catch (_) {
    // 预热失败不阻塞导航；chat.dart 端的 in-flight 仍会重试。
  }
  // Pipeline [3] - push_after_wait：本地分类交接，不是 H0 grace。
  final waitElapsed = DateTime.now().difference(waitStart).inMilliseconds;
  ChatPipelineClock.instance.trace(pipelineKey, 'push_after_wait',
      elapsedMs: waitElapsed,
      extras: <String, Object?>{
        'timedOut': waitElapsed >=
            ChatOpenViewportCoordinator.localBudget.inMilliseconds,
      });
  if (!context.mounted) {
    return null;
  }
  return navigator.push<T>(
    appChatRoute<T>(
      conversation,
      entryUnreadCount: entryUnreadCount,
      initFindingMsg: initFindingMsg,
      searchJumpAnchor: searchJumpAnchor,
      initialC2cCanMessage: initialC2cCanMessage,
      c2cPermissionHintSource: c2cPermissionHintSource,
    ),
  );
}

Future<T?> openChatWithAnchor<T>(
  BuildContext context,
  V2TimConversation conversation, {
  MessageAnchor? anchor,
}) {
  if (!context.mounted) {
    return Future<T?>.value();
  }
  return openOrReuseAppChat<T>(
    context,
    conversation,
    searchJumpAnchor: anchor,
  );
}

~~~

2. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_open_viewport_coordinator.dart:1>)，原文件 lib/src/services/chat_open_viewport_coordinator.dart，1–658 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:tencent_cloud_chat_demo/src/models/chat_entry_snapshot.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/open_viewport_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// 进聊首窗快照状态机。
///
/// 导航只允许等待本地 fast classify。H0 可以并行启动，但不能成为
/// push 的必经 await。Chat 页第一帧只吃 Collection 锁定的那份 snapshot。
/// 云端 freshness 仍由 ConversationHistorySyncCoordinator 在首帧后负责。
/// 这里不能再把完整云历史绑回进页关键路径。
enum ChatOpenViewportPhase {
  idle,
  preparing,
  prepared,
  viewportReady,
  transitioning,
  visible,
  cancelled,
}

class ChatOpenViewportCoordinator {
  ChatOpenViewportCoordinator._();

  static final ChatOpenViewportCoordinator instance =
      ChatOpenViewportCoordinator._();

  int _requestId = 0;
  String? _activeKey;
  ChatOpenViewportPhase _phase = ChatOpenViewportPhase.idle;
  int get currentRequestId => _requestId;

  ChatOpenViewportPhase get phase => _phase;

  ChatOpenViewportPhase phaseFor(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return ChatOpenViewportPhase.idle;
    }
    return _phase;
  }

  bool isCurrent(int requestId, String conversationKey) {
    final key = conversationKey.trim();
    return requestId == _requestId &&
        key.isNotEmpty &&
        key == (_activeKey ?? '');
  }

  void markTransitioning(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return;
    }
    _phase = ChatOpenViewportPhase.transitioning;
  }

  void markVisible(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return;
    }
    _phase = ChatOpenViewportPhase.visible;
  }

  void resetForTest() {
    _requestId = 0;
    _activeKey = null;
    _phase = ChatOpenViewportPhase.idle;
  }

  ChatOpenPrepareWorkSnapshot recordPrepareStart({
    required int requestId,
    required String source,
  }) {
    return ChatOpenPerfLog.recordPrepareStart(
      requestId: requestId,
      source: source,
    );
  }

  ChatOpenPrepareWorkSnapshot? snapshotFor(int requestId) {
    return ChatOpenPerfLog.snapshotFor(requestId);
  }

  /// 兼容旧观测埋点的准备预算。实际点击路径另有更短的本地快照交接预算，
  /// 不得扩展到网络 RTT。
  static const Duration prepareTimeout = Duration(milliseconds: 400);

  /// Memory + 本地库 fast budget。云不在这条路径。
  static const Duration localBudget = Duration(milliseconds: 100);

  /// 本地空/洞时允许 H0 latest page 赶上转场的 grace。超时继续转场。
  static const Duration cloudGraceBudget = Duration(milliseconds: 200);

  /// 点击会话时启动一次本地首窗读取。该任务只访问 IM SDK 本地库，
  /// 不访问云端；聊天页和 UIKit 通过同一个 Future 复用结果。
  Future<bool> ensureLocalSnapshotForOpen({
    required V2TimConversation conversation,
    Duration timeout = const Duration(milliseconds: 280),
    ChatOpenTraceContext? logTrace,
    bool windowAlreadyCleared = false,
  }) async {
    final key = _conversationKey(conversation);
    if (key.isEmpty) {
      return false;
    }
    final hydrateTrace = logTrace ??
        ChatOpenPerfLog.captureCurrent(conversationKey: key);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // Search owns its anchor window; a latest-window result cannot satisfy it.
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key)) {
      return _ensureLatestWindowResetForOpen(
        conversation: conversation,
        key: key,
        globalModel: globalModel,
        timeout: timeout,
        logTrace: hydrateTrace,
        windowAlreadyCleared: windowAlreadyCleared,
      );
    }
    if (ConversationPreviewHistorySync.canSkipOpenRebootstrap(
      globalModel: globalModel,
      conversationKey: key,
      preview: conversation.lastMessage,
    )) return true;
    final identity = SessionIdentityService.instance.capture();
    final last = conversation.lastMessage;
    final signature = '${identity.ownerUserId}|${identity.generation}|'
        '${last?.msgID}|${last?.seq}|${last?.timestamp}|'
        '${globalModel.messageDeltaClearEpochFor(key)}';
    final task = globalModel.ensureOpenHydrate(
      key,
      requestSignature: signature,
      canPublish: () =>
          SessionIdentityService.instance.capture() == identity &&
          globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle,
      load: () => ChatHistoryPeekBootstrap.apply(
        conversation: conversation,
        globalModel: globalModel,
        allowCloudVerification: false,
        logTrace: hydrateTrace,
      ),
    );
    try {
      return (await task.timeout(timeout)).shouldSuppressOrdinaryLoad;
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'local_snapshot_wait_timeout',
        conversationID: key,
        extras: <String, Object?>{'timeoutMs': timeout.inMilliseconds},
        trace: hydrateTrace,
      );
      return false;
    }
  }

  /// First open after a real reconnect. The reset service, not the ordinary
  /// local hydrate, owns the first window: no stale cache is shown and the
  /// open hydrate stays in flight until a validated window is installed.
  Future<bool> _ensureLatestWindowResetForOpen({
    required V2TimConversation conversation,
    required String key,
    required TUIChatGlobalModel globalModel,
    required Duration timeout,
    required ChatOpenTraceContext logTrace,
    required bool windowAlreadyCleared,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final last = conversation.lastMessage;
    final epoch = ImConnectStatusService.recoveryEpoch;
    final signature = 'latest_window_reset|$epoch|'
        '${identity.ownerUserId}|${identity.generation}|'
        '${last?.msgID}|${last?.seq}|${last?.timestamp}|'
        '${globalModel.messageDeltaClearEpochFor(key)}';
    final openGeneration =
        ChatViewportCollection.instance.openGenerationFor(key);
    if (openGeneration <= 0) {
      // Press-warm / no page attached yet. A reset operation is page-bound
      // (it lives until the page is gone); the real open goes through
      // prepareOpenViewport, which attaches first and then starts it.
      ChatOpenPerfLog.mark(
        'chat_open_latest_window_reset_wait_attach',
        conversationID: key,
        trace: logTrace,
      );
      return false;
    }
    ChatOpenPerfLog.mark(
      'chat_open_latest_window_reset_begin',
      conversationID: key,
      extras: <String, Object?>{
        'epoch': epoch,
        'openGeneration': openGeneration,
        'rawCount': globalModel.rawMessageCount(key),
      },
      trace: logTrace,
    );
    final task = globalModel.ensureOpenHydrate(
      key,
      requestSignature: signature,
      canPublish: () =>
          SessionIdentityService.instance.capture() == identity &&
          ChatViewportCollection.instance.openGenerationFor(key) ==
              openGeneration &&
          !ChatViewportCollection.instance.isOpenGenerationAbandoned(
            key,
            openGeneration,
          ) &&
          globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle,
      load: () async {
        final outcome = await ChatLatestWindowResetService.instance.runForOpen(
          conversation: conversation,
          globalModel: globalModel,
          openGeneration: openGeneration,
          windowAlreadyCleared: windowAlreadyCleared,
        );
        return outcome == LatestWindowResetOutcome.trusted ||
            outcome == LatestWindowResetOutcome.installedProvisional ||
            outcome == LatestWindowResetOutcome.offlineProvisional;
      },
    );
    try {
      return (await task.timeout(timeout)).shouldSuppressOrdinaryLoad;
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'latest_window_reset_wait_timeout',
        conversationID: key,
        extras: <String, Object?>{'timeoutMs': timeout.inMilliseconds},
        trace: logTrace,
      );
      return false;
    }
  }

  String _conversationKey(V2TimConversation conversation) {
    return ConversationPreviewHistorySync.conversationMessageCacheKey(
          conversation,
        ) ??
        conversation.conversationID.trim();
  }

  /// 捕获当前本地快照。调用方应 fire-and-forget，返回快照仅用于观测/测试，
  /// 可能 `!isViewportReady`。
  ///
  /// [timeout] 仅保留为兼容的观测参数；不会等待 SDK、云端或完整历史窗口。
  Future<ChatEntrySnapshot> prepareForOpen({
    required V2TimConversation conversation,
    Duration timeout = prepareTimeout,
  }) async {
    final requestId = ++_requestId;
    final cacheKey = ConversationPreviewHistorySync.conversationMessageCacheKey(
          conversation,
        ) ??
        conversation.conversationID.trim();
    final conversationID = conversation.conversationID.trim();
    _activeKey = cacheKey;
    _phase = ChatOpenViewportPhase.preparing;
    // Start local hydration before the route is pushed. The caller can await
    // ensureLocalSnapshotForOpen for a short bounded handoff; this method
    // itself remains non-blocking for existing callers.
    unawaited(ensureLocalSnapshotForOpen(
      conversation: conversation,
      logTrace: ChatOpenPerfLog.captureCurrent(conversationKey: cacheKey),
    ));
    ChatOpenPerfLog.mark(
      'viewport_preparing',
      conversationID: cacheKey,
      extras: <String, Object?>{
        'requestId': requestId,
        'timeoutMs': timeout.inMilliseconds,
      },
    );

    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final snap = ChatEntrySnapshot.capture(
      globalModel: globalModel,
      conversationKey: cacheKey,
      conversationID: conversationID,
      requestId: requestId,
      tip: conversation.lastMessage,
    );

    if (!isCurrent(requestId, cacheKey)) {
      _phase = ChatOpenViewportPhase.cancelled;
      ChatOpenPerfLog.mark(
        'viewport_prepare_stale',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'currentRequestId': _requestId,
        },
      );
      return snap;
    }

    // Prepare 可能在 route 已 transitioning/visible 后完成。不能把状态倒退
    // 回 prepared/viewportReady，否则后续生命周期判断会误以为页面尚未出现。
    final alreadyTransitioning =
        _phase == ChatOpenViewportPhase.transitioning ||
            _phase == ChatOpenViewportPhase.visible;
    if (!alreadyTransitioning) {
      _phase = ChatOpenViewportPhase.prepared;
    }
    final ready = snap.isViewportReady;
    if (ready) {
      if (!alreadyTransitioning) {
        _phase = ChatOpenViewportPhase.viewportReady;
      }
      ChatOpenPerfLog.mark(
        alreadyTransitioning ? 'viewport_ready_background' : 'viewport_ready',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'rawCount': snap.messageCount,
          'completeWindow': snap.completeOpenWindow,
          'emptyConfirmed': snap.emptyConfirmed,
        },
      );
    } else {
      ChatOpenPerfLog.mark(
        'viewport_ready_miss',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'rawCount': snap.messageCount,
          'initialLoaded': snap.initialHistoryLoaded,
          'mayHaveOlder': snap.mayHaveOlderHistory,
        },
      );
    }
    return snap;
  }

  /// 导航前准备当前可展示窗口。返回连续视口描述，而不是条数。
  Future<ChatOpenViewportResult> prepareOpenViewport({
    required V2TimConversation conversation,
    double viewportHeight = ChatViewportReadiness.defaultViewportHeight,
    Duration timeout = localBudget,
    Duration cloudGrace = cloudGraceBudget,
    String source = 'unknown',
  }) async {
    final key = _conversationKey(conversation);
    if (key.isEmpty) {
      return ChatViewportReadiness.classify(
        conversationKey: '',
        newestFirst: const <V2TimMessage>[],
        useSeqContiguity: false,
        viewportHeight: viewportHeight,
        source: ChatViewportSource.memory,
      );
    }
    final requestId = ++_requestId;
    _activeKey = key;
    _phase = ChatOpenViewportPhase.preparing;
    final identity = SessionIdentityService.instance.capture();
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: identity,
      attachSource: 'prepare',
    );
    recordPrepareStart(requestId: requestId, source: source);
    final prepareTrace = ChatOpenPerfLog.captureCurrent(
      requestId: requestId,
      conversationKey: key,
    );
    final isGroup = conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    Map<String, Object?> prepareExtras([
      Map<String, Object?> more = const <String, Object?>{},
    ]) {
      final snap = snapshotFor(requestId);
      return <String, Object?>{
        'requestId': requestId,
        'prepareId': requestId,
        'source': source,
        'openGeneration': collection.openGeneration,
        'sessionGeneration': identity.generation,
        'owned': snap?.owned ?? false,
        'joined': snap?.joined ?? false,
        'dbRead': snap?.dbRead ?? false,
        'sdkRead': snap?.sdkRead ?? false,
        'committed': snap?.committed ?? false,
        ...more,
      };
    }

    ChatOpenPerfLog.mark(
      'viewport_prepare_start',
      conversationID: key,
      extras: prepareExtras(),
      trace: prepareTrace,
    );

    ChatOpenViewportResult project(ChatViewportSource viewportSource) {
      return collection.project(
        conversationKey: key,
        newestFirst: List<V2TimMessage>.from(
          globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
        ),
        useSeqContiguity: isGroup,
        viewportHeight: viewportHeight,
        source: viewportSource,
        coverage: globalModel.messageHistoryCoverageFor(key),
      );
    }

    void logFirstViewport(ChatOpenViewportResult result) {
      ChatOpenPerfLog.mark(
        'chat_open_first_viewport_extent',
        conversationID: key,
        extras: <String, Object?>{
          'extent': result.estimatedContentExtent,
          'target': result.viewportTargetExtent,
          'ready': result.isViewportReady,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'chat_open_first_viewport_message_count',
        conversationID: key,
        extras: <String, Object?>{
          'continuousCount': result.continuousCount,
          'rawCount': globalModel.rawMessageCount(key),
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'chat_open_first_frame_source',
        conversationID: key,
        extras: <String, Object?>{
          'source': result.source.name,
          'coverage': result.coverageState.name,
          'needsLatestRepair': result.needsLatestRepair,
        },
        trace: prepareTrace,
      );
    }

    void logPrepareEnd(ChatOpenViewportResult result, {required String work}) {
      ChatOpenPerfLog.mark(
        'viewport_prepare_end',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ready': result.isViewportReady,
          'coverage': result.coverageState.name,
          'isCurrent': isCurrent(requestId, key),
          'work': work,
        }),
        trace: prepareTrace,
      );
    }

    bool previewAhead() => ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
      preview: conversation.lastMessage,
      cached: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
    );

    if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key) &&
        globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle) {
      // Reconnect-epoch changed: the cache and the in-memory window are not
      // allowed to be the visible first frame. Wipe synchronously so the
      // locked initial snapshot is empty, then let the reset own hydration.
      // The ordinary H0 repair must not compete with the reset request.
      OpenViewportCache.instance.invalidate(key);
      // Single wipe owner: this prepare clears the window once, and tells the
      // reset operation so it never clears again (a second removeMessageList
      // would bump clearEpoch / writer state under the running request). If an
      // operation is already in flight for this key, it owns the window.
      final resetInFlight =
          ChatLatestWindowResetService.instance.isResetInFlight(key);
      if (!resetInFlight &&
          (globalModel.rawMessageCount(key) > 0 ||
              globalModel.hasInitialHistoryLoaded(key))) {
        globalModel.removeMessageList(key);
      }
      unawaited(ensureLocalSnapshotForOpen(
        conversation: conversation,
        timeout: timeout,
        logTrace: prepareTrace,
        windowAlreadyCleared: !resetInFlight,
      ));
      final result = project(ChatViewportSource.memory);
      collection.lockInitial(result);
      collection.markRepair(ChatViewportRepairKind.openViewport);
      if (_phase != ChatOpenViewportPhase.transitioning &&
          _phase != ChatOpenViewportPhase.visible) {
        _phase = ChatOpenViewportPhase.prepared;
      }
      ChatOpenPerfLog.mark(
        'viewport_prepare_latest_window_reset',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'epoch': ImConnectStatusService.recoveryEpoch,
        }),
        trace: prepareTrace,
      );
      logFirstViewport(result);
      logPrepareEnd(result, work: 'latest_window_reset');
      return result;
    }

    final cached = OpenViewportCache.instance.peek(key);
    if (cached != null && cached.isViewportReady && !previewAhead()) {
      ChatOpenPerfLog.mark(
        'chat_open_cache_hit',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': requestId,
          'continuousCount': cached.continuousCount,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'viewport_prepare_cache_hit',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'continuousCount': cached.continuousCount,
        }),
        trace: prepareTrace,
      );
      final fromMemory = project(ChatViewportSource.cache);
      if (fromMemory.isViewportReady) {
        collection.lockInitial(fromMemory);
        _phase = ChatOpenViewportPhase.viewportReady;
        logFirstViewport(fromMemory);
        logPrepareEnd(fromMemory, work: 'cache_hit');
        return fromMemory;
      }
    }

    final localStartedAt = DateTime.now();
    var result = project(ChatViewportSource.memory);
    var localWork = 'memory_hit';
    if (!result.isViewportReady || previewAhead()) {
      ChatOpenPerfLog.mark(
        'viewport_prepare_local_begin',
        conversationID: key,
        extras: prepareExtras(),
        trace: prepareTrace,
      );
      await ensureLocalSnapshotForOpen(
        conversation: conversation,
        timeout: timeout,
        logTrace: prepareTrace,
      );
      result = project(ChatViewportSource.local);
      final snap = snapshotFor(requestId);
      localWork = (snap?.joined ?? false)
          ? 'join'
          : ((snap?.owned ?? false) || (snap?.dbRead ?? false) ? 'real' : 'join');
      ChatOpenPerfLog.mark(
        'viewport_prepare_local_end',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ready': result.isViewportReady,
          'work': localWork,
        }),
        trace: prepareTrace,
      );
    }
    ChatOpenPerfLog.mark(
      'chat_open_local_ready_us',
      conversationID: key,
      extras: <String, Object?>{
        'durationUs':
            DateTime.now().difference(localStartedAt).inMicroseconds,
        'ready': result.isViewportReady,
        'coverage': result.coverageState.name,
      },
      trace: prepareTrace,
    );
    collection.lockInitial(result);
    if (result.isViewportReady && !previewAhead()) {
      _phase = ChatOpenViewportPhase.viewportReady;
      OpenViewportCache.instance.put(key, result);
      logFirstViewport(result);
      logPrepareEnd(result, work: localWork);
      return result;
    }

    if (result.needsLatestRepair || previewAhead()) {
      final ticket = ChatViewportRepairTicket(
        ownerUserId: identity.ownerUserId,
        accountGeneration: identity.generation,
        conversationKey: key,
        openGeneration: collection.openGeneration,
        requestAnchorMsgId: result.anchor?.msgID,
        requestAnchorSeq: result.anchor?.seq,
      );
      ChatOpenPerfLog.mark(
        'chat_open_h0_started',
        conversationID: key,
        extras: <String, Object?>{
          'coverage': result.coverageState.name,
          'continuousCount': result.continuousCount,
          'openGeneration': ticket.openGeneration,
          'graceMs': cloudGrace.inMilliseconds,
          'awaitGrace': false,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'viewport_prepare_h0_begin',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'graceMs': cloudGrace.inMilliseconds,
        }),
        trace: prepareTrace,
      );
      collection.markRepair(ChatViewportRepairKind.openViewport);
      // H0 是并行机会：启动 single-flight，但不把 grace 做成 push 的必经 await。
      unawaited(
        ConversationHistorySyncCoordinator.instance.repairOpenViewport(
          conversation: conversation,
          ticket: ticket,
          logTrace: prepareTrace,
        ),
      );
    }

    if (result.isViewportReady) {
      _phase = ChatOpenViewportPhase.viewportReady;
    } else if (_phase != ChatOpenViewportPhase.transitioning &&
        _phase != ChatOpenViewportPhase.visible) {
      _phase = ChatOpenViewportPhase.prepared;
    }
    OpenViewportCache.instance.put(key, result);
    logFirstViewport(result);
    logPrepareEnd(result, work: localWork);
    return result;
  }
}


~~~

3. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_latest_window_reset_service.dart:1>)，原文件 lib/src/services/chat_latest_window_reset_service.dart，1–1012 行。

~~~dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_sync_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

/// Terminal state of one latest-window reset operation.
enum LatestWindowResetOutcome {
  /// Continuous latest window installed, edge aligned with the preview and
  /// freshness proven. Trust + 30s recovery success written.
  trusted,

  /// Window installed and edge aligned, but the operation ended (page or
  /// session became invalid) before a fresh proof was obtained.
  installedProvisional,

  /// Confirmed offline: fresh LOCAL continuous window shown. Never trusted.
  offlineProvisional,

  /// In-page only: the user is reading history / offline; nothing changed.
  deferred,

  /// Not applicable (no key, cannot peek, no reset needed, superseded).
  skipped,

  /// Nothing could be installed before the operation became invalid.
  failed,
}

/// Every external dependency the reset needs. Production reads the live
/// singletons; tests override through [ChatLatestWindowResetService.debugEnvironment].
class LatestWindowResetEnvironment {
  LatestWindowResetEnvironment({
    int Function()? recoveryEpoch,
    bool Function()? transportReady,
    bool Function()? serverSyncPending,
    ValueListenable<NetworkReachability>? networkStatus,
    Future<ConversationPeekLoadResult> Function(V2TimConversation)? loadCloud,
    Future<ConversationPeekLoadResult> Function(V2TimConversation)? loadLocal,
    bool Function(SessionIdentity identity)? isIdentityCurrent,
    List<Duration>? fastRetryDelays,
    List<Duration>? slowRetryDelays,
    Duration? inPagePollInterval,
  })  : recoveryEpoch = recoveryEpoch ?? (() => ImConnectStatusService.recoveryEpoch),
        transportReady =
            transportReady ?? (() => ImConnectStatusService.isTransportReady),
        serverSyncPending = serverSyncPending ??
            (() => ImSdkRelationshipSyncAnchor.serverSyncPending),
        networkStatus = networkStatus ?? NetworkStatusService.instance.status,
        loadCloud = loadCloud ?? ConversationPeekService.loadForChatEntry,
        loadLocal = loadLocal ?? ConversationPeekService.loadLocalForChatEntry,
        isIdentityCurrent = isIdentityCurrent ??
            ((identity) => SessionIdentityService.instance.isCurrent(identity)),
        fastRetryDelays = fastRetryDelays ?? defaultFastRetryDelays,
        slowRetryDelays = slowRetryDelays ?? defaultSlowRetryDelays,
        inPagePollInterval =
            inPagePollInterval ?? const Duration(milliseconds: 500);

  static const List<Duration> defaultFastRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 800),
    Duration(seconds: 2),
  ];

  /// After the fast attempts the operation stays alive: 5s / 15s / 60s, then
  /// every 60s, until a window is trusted or the page / session is gone. A
  /// roaming sync finish wakes the next attempt immediately.
  static const List<Duration> defaultSlowRetryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 60),
  ];

  final int Function() recoveryEpoch;
  final bool Function() transportReady;
  final bool Function() serverSyncPending;
  final ValueListenable<NetworkReachability> networkStatus;
  final Future<ConversationPeekLoadResult> Function(V2TimConversation) loadCloud;
  final Future<ConversationPeekLoadResult> Function(V2TimConversation) loadLocal;
  final bool Function(SessionIdentity identity) isIdentityCurrent;
  final List<Duration> fastRetryDelays;
  final List<Duration> slowRetryDelays;
  final Duration inPagePollInterval;

  bool get networkOnline => networkStatus.value == NetworkReachability.online;
  bool get networkOffline => networkStatus.value == NetworkReachability.offline;
}

class _ResetOperation {
  _ResetOperation({
    required this.id,
    required this.conversationKey,
    required this.openGeneration,
    required this.identity,
    required this.inPage,
    required this.conversation,
    required this.globalModel,
  });

  final int id;
  final String conversationKey;
  final int openGeneration;
  final SessionIdentity identity;
  final bool inPage;
  final V2TimConversation conversation;
  final TUIChatGlobalModel globalModel;
  final Completer<LatestWindowResetOutcome> completer =
      Completer<LatestWindowResetOutcome>();
  Completer<void>? syncWake;

  /// One wipe per operation, whoever performs it.
  bool windowCleared = false;
  bool installedProvisional = false;

  Future<LatestWindowResetOutcome> get future => completer.future;
}

class _ResetContext {
  const _ResetContext(this.conversation, this.globalModel);
  final V2TimConversation conversation;
  final TUIChatGlobalModel globalModel;
}

/// Owns the "continuous latest window" recovery after a real reconnect.
///
/// One operation per conversation key. A first-open operation never shows a
/// stale cache and installs only a validated window; an in-page operation
/// re-checks the user's position before any visible change and narrows the
/// visible window through `restampVisibleWindowToLatest`. The operation stays
/// alive (fast then slow retries) until a window is trusted or the page /
/// session it belongs to is gone; the skeleton is never left without an owner.
class ChatLatestWindowResetService {
  ChatLatestWindowResetService._();

  static final ChatLatestWindowResetService instance =
      ChatLatestWindowResetService._();

  @visibleForTesting
  static LatestWindowResetEnvironment? debugEnvironment;

  LatestWindowResetEnvironment get _env =>
      debugEnvironment ?? _defaultEnvironment;
  static final LatestWindowResetEnvironment _defaultEnvironment =
      LatestWindowResetEnvironment();

  final Map<String, _ResetOperation> _inFlightByKey = <String, _ResetOperation>{};

  /// Conversations whose current visible window was installed without proof
  /// (installedProvisional / offlineProvisional) or never installed after a
  /// failed open. They need a reset even when the epoch has not moved.
  final Set<String> _provisionalKeys = <String>{};

  /// Last conversation/global model seen per key so a network transition can
  /// re-run the reset for the currently open page without page cooperation.
  final Map<String, _ResetContext> _contextByKey = <String, _ResetContext>{};
  int _opSequence = 0;
  ValueListenable<NetworkReachability>? _listenedNetwork;
  NetworkReachability? _lastNetwork;

  @visibleForTesting
  int debugWipeInvocations = 0;

  bool needsLatestWindowReset(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty) return false;
    return ChatLatestWindowTrust.instance.needsLatestWindowReset(
      conversationKey: key,
      currentEpoch: _env.recoveryEpoch(),
      provisionalRegistered: _provisionalKeys.contains(key),
    );
  }

  bool isResetInFlight(String conversationKey) =>
      _inFlightByKey.containsKey(conversationKey.trim());

  @visibleForTesting
  Future<LatestWindowResetOutcome>? inFlightFutureFor(String conversationKey) =>
      _inFlightByKey[conversationKey.trim()]?.future;

  bool isProvisional(String conversationKey) =>
      _provisionalKeys.contains(conversationKey.trim());

  void clearSession() {
    _provisionalKeys.clear();
    _contextByKey.clear();
    for (final op in _inFlightByKey.values) {
      op.syncWake?.complete();
    }
  }

  @visibleForTesting
  void resetForTest() {
    clearSession();
    _inFlightByKey.clear();
    _listenedNetwork?.removeListener(_onNetworkStatusChanged);
    _listenedNetwork = null;
    _lastNetwork = null;
    debugWipeInvocations = 0;
  }

  /// First open after a real reconnect: (wipe unless the caller already did),
  /// fetch, validate, install. Returns `skipped` when no reset is needed.
  Future<LatestWindowResetOutcome> runForOpen({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    bool windowAlreadyCleared = false,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) {
    return _run(
      conversation: conversation,
      globalModel: globalModel,
      openGeneration: openGeneration,
      lifeCycle: lifeCycle,
      inPage: false,
      reason: 'open',
      windowAlreadyCleared: windowAlreadyCleared,
      onFirstWindowCommitted: onFirstWindowCommitted,
    );
  }

  /// Reconnect / network recovery while the page is open. Waits (polling)
  /// until the user is at the bottom, then repairs.
  Future<LatestWindowResetOutcome> runInPage({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    required String reason,
    ChatLifeCycle? lifeCycle,
  }) {
    return _run(
      conversation: conversation,
      globalModel: globalModel,
      openGeneration: openGeneration,
      lifeCycle: lifeCycle,
      inPage: true,
      reason: reason,
    );
  }

  Future<LatestWindowResetOutcome> _run({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    required bool inPage,
    required String reason,
    bool windowAlreadyCleared = false,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (key == null || key.isEmpty) return LatestWindowResetOutcome.skipped;
    if (!ConversationPeekService.canPeek(conversation)) {
      return LatestWindowResetOutcome.skipped;
    }
    _ensureNetworkListener();
    _contextByKey[key] = _ResetContext(conversation, globalModel);
    if (!needsLatestWindowReset(key)) return LatestWindowResetOutcome.skipped;
    final existing = _inFlightByKey[key];
    if (existing != null) {
      if (_opIsCurrent(existing)) return existing.future;
      // A reopened page must not wait for a request bound to the page it left.
      // That request still checks its generation before publishing a response.
      final wake = existing.syncWake;
      if (wake != null && !wake.isCompleted) wake.complete();
    }

    final op = _ResetOperation(
      id: ++_opSequence,
      conversationKey: key,
      openGeneration: openGeneration,
      identity: SessionIdentityService.instance.capture(),
      inPage: inPage,
      conversation: conversation,
      globalModel: globalModel,
    )..windowCleared = windowAlreadyCleared;
    _inFlightByKey[key] = op;
    _trace('latest_window_reset_start', op, extras: <String, Object?>{
      'reason': reason,
      'inPage': inPage,
      'windowAlreadyCleared': windowAlreadyCleared,
      'rawCount': globalModel.rawMessageCount(key),
    });
    void wake() => op.syncWake?.complete();
    globalModel.addRoamingSyncListener(wake);
    LatestWindowResetOutcome outcome = LatestWindowResetOutcome.failed;
    try {
      outcome = await _execute(
        op: op,
        lifeCycle: lifeCycle,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('latest_window_reset error key=$key $error\n$stack');
      }
      outcome = LatestWindowResetOutcome.failed;
    } finally {
      globalModel.removeRoamingSyncListener(wake);
      if (identical(_inFlightByKey[key], op)) _inFlightByKey.remove(key);
      _trace('latest_window_reset_done', op, extras: <String, Object?>{
        'outcome': outcome.name,
      });
      if (!op.completer.isCompleted) op.completer.complete(outcome);
    }
    return outcome;
  }

  // ---------------------------------------------------------------------------
  // Network recovery while a provisional page is open
  // ---------------------------------------------------------------------------

  void _ensureNetworkListener() {
    final status = _env.networkStatus;
    if (identical(_listenedNetwork, status)) return;
    _listenedNetwork?.removeListener(_onNetworkStatusChanged);
    _listenedNetwork = status;
    _lastNetwork = status.value;
    status.addListener(_onNetworkStatusChanged);
  }

  void _onNetworkStatusChanged() {
    final status = _listenedNetwork;
    if (status == null) return;
    final previous = _lastNetwork;
    final next = status.value;
    _lastNetwork = next;
    if (next != NetworkReachability.online || previous == next) return;
    // Wake every sleeping operation: an offline-deferred attempt can retry now.
    for (final op in _inFlightByKey.values) {
      op.syncWake?.complete();
    }
    final collection = ChatViewportCollection.instance;
    final openKey = collection.conversationKey ?? '';
    if (openKey.isEmpty || !collection.uiAttached) return;
    if (!needsLatestWindowReset(openKey) || isResetInFlight(openKey)) return;
    final context = _contextByKey[openKey];
    if (context == null) return;
    unawaited(runInPage(
      conversation: context.conversation,
      globalModel: context.globalModel,
      openGeneration: collection.openGeneration,
      reason: 'network_online',
    ));
  }

  // ---------------------------------------------------------------------------
  // Validity / position checks
  // ---------------------------------------------------------------------------

  bool _opIsCurrent(_ResetOperation op) {
    if (!_env.isIdentityCurrent(op.identity)) return false;
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      op.conversationKey,
      op.openGeneration,
    )) {
      return false;
    }
    if (op.openGeneration > 0) {
      // A newer open (same or other conversation) took over the collection.
      if ((collection.conversationKey ?? '') != op.conversationKey) {
        return false;
      }
      if (collection.openGeneration != op.openGeneration) return false;
    }
    if (op.inPage && !collection.uiAttached) return false;
    return true;
  }

  /// In-page only. The user must still be following the latest edge and no
  /// other history owner may be mid-flight.
  bool _userAllowsVisibleReset(_ResetOperation op) {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    if (!_opIsCurrent(op)) return false;
    if (globalModel.getMessageListPosition(key) !=
        HistoryMessagePosition.bottom) {
      return false;
    }
    if (globalModel.isChatListUserScrolling) return false;
    if (!globalModel.isFollowingLatest(key)) return false;
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    if (globalModel.hasActiveHistoryReconciliation(key)) return false;
    return true;
  }

  /// Second check after the network round trip. Identical to the entry check
  /// minus the "no active request" rule, because the active request is ours.
  bool _userAllowsVisibleResetAfterFetch(_ResetOperation op) {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    if (!_opIsCurrent(op)) return false;
    if (globalModel.getMessageListPosition(key) !=
        HistoryMessagePosition.bottom) {
      return false;
    }
    if (globalModel.isChatListUserScrolling) return false;
    if (!globalModel.isFollowingLatest(key)) return false;
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    return true;
  }

  Future<bool> _waitUntilUserAllowsReset(_ResetOperation op) async {
    var logged = false;
    while (true) {
      if (!_opIsCurrent(op)) return false;
      if (_userAllowsVisibleReset(op)) return true;
      if (!logged) {
        logged = true;
        _trace('latest_window_reset_defer_reading_history', op);
      }
      await Future<void>.delayed(_env.inPagePollInterval);
    }
  }

  // ---------------------------------------------------------------------------
  // Main flow
  // ---------------------------------------------------------------------------

  void _wipeOnce(_ResetOperation op) {
    if (op.windowCleared) return;
    op.windowCleared = true;
    final globalModel = op.globalModel;
    final key = op.conversationKey;
    if (globalModel.rawMessageCount(key) > 0 ||
        globalModel.hasInitialHistoryLoaded(key)) {
      _trace('latest_window_reset_wipe_stale', op, extras: <String, Object?>{
        'rawCount': globalModel.rawMessageCount(key),
      });
      debugWipeInvocations++;
      globalModel.removeMessageList(key);
    }
  }

  Future<LatestWindowResetOutcome> _execute({
    required _ResetOperation op,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    if (!_opIsCurrent(op)) return LatestWindowResetOutcome.skipped;

    if (_env.networkOffline) {
      if (op.inPage) {
        // Nothing can be proven offline; the provisional flag keeps the reset
        // armed and the network listener re-runs it on the online transition.
        _provisionalKeys.add(key);
        return LatestWindowResetOutcome.deferred;
      }
      final offline = await _installOfflineProvisional(
        op: op,
        lifeCycle: lifeCycle,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
      // The first-open operation ends here; the network listener owns the
      // online transition for the page that is now showing this window.
      return offline;
    }

    if (!op.inPage) {
      // Never show a stale window, even briefly (unless the coordinator
      // already cleared it synchronously before locking the first frame).
      _wipeOnce(op);
    }

    final isGroup = _isGroup(op.conversation);
    var attempt = 0;
    while (true) {
      final delay = _delayForAttempt(attempt);
      if (delay > Duration.zero) {
        await _delayOrWake(op, delay);
      }
      attempt++;
      if (!_opIsCurrent(op)) return _endInvalid(op);
      if (_env.networkOffline) {
        // Went offline mid-operation. Keep the operation alive; the network
        // listener wakes it as soon as the device is online again.
        _trace('latest_window_reset_wait_network', op, extras: <String, Object?>{
          'attempt': attempt,
        });
        continue;
      }
      if (op.inPage) {
        if (!await _waitUntilUserAllowsReset(op)) return _endInvalid(op);
      } else if (op.globalModel.hasActiveHistoryReconciliation(key)) {
        // Another owner is mid-flight; give it a tick before taking the lane
        // rather than nesting request lifecycles.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!_opIsCurrent(op)) return _endInvalid(op);
        if (op.globalModel.hasActiveHistoryReconciliation(key)) {
          op.globalModel.cancelHistoryReconciliation(key);
        }
      }

      final attemptOutcome = await _attemptCloudLatestWindow(
        op: op,
        attempt: attempt,
        lifeCycle: lifeCycle,
        isGroup: isGroup,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
      switch (attemptOutcome) {
        case _AttemptOutcome.trusted:
          return LatestWindowResetOutcome.trusted;
        case _AttemptOutcome.installedProvisional:
          op.installedProvisional = true;
          _provisionalKeys.add(key);
          continue;
        case _AttemptOutcome.deferred:
          _provisionalKeys.add(key);
          return LatestWindowResetOutcome.deferred;
        case _AttemptOutcome.superseded:
          return _endInvalid(op);
        case _AttemptOutcome.retry:
          continue;
      }
    }
  }

  LatestWindowResetOutcome _endInvalid(_ResetOperation op) {
    // The page / session this operation belonged to is gone. Whatever it had
    // installed stays provisional, unless a newer operation has taken over.
    if (identical(_inFlightByKey[op.conversationKey], op)) {
      _provisionalKeys.add(op.conversationKey);
    }
    return op.installedProvisional
        ? LatestWindowResetOutcome.installedProvisional
        : LatestWindowResetOutcome.skipped;
  }

  Duration _delayForAttempt(int attempt) {
    final fast = _env.fastRetryDelays;
    if (attempt < fast.length) return fast[attempt];
    final slow = _env.slowRetryDelays;
    if (slow.isEmpty) return fast.isEmpty ? Duration.zero : fast.last;
    final index = attempt - fast.length;
    return slow[index < slow.length ? index : slow.length - 1];
  }

  /// Returns true when woken early (roaming sync finish / network online).
  Future<bool> _delayOrWake(_ResetOperation op, Duration delay) async {
    final wake = Completer<void>();
    op.syncWake = wake;
    try {
      await wake.future.timeout(delay);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      if (identical(op.syncWake, wake)) op.syncWake = null;
    }
  }

  Future<_AttemptOutcome> _attemptCloudLatestWindow({
    required _ResetOperation op,
    required int attempt,
    required bool isGroup,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    final conversation = op.conversation;
    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
    final networkBefore = globalModel.messageReconciliationNetworkState;
    final syncPendingBefore = _env.serverSyncPending();
    final epochBefore = _env.recoveryEpoch();

    // Single request lifecycle: this service is the only owner.
    final request = globalModel.beginHistoryReconciliation(
      conversationID: key,
      requestedSource: MessageReconciliationSource.cloud,
      networkState: networkBefore,
    );
    final ConversationPeekLoadResult result;
    try {
      result = await _env.loadCloud(conversation);
    } catch (error) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_load_failed',
      );
      _trace('latest_window_reset_retry_error', op, extras: <String, Object?>{
        'attempt': attempt,
        'error': error.toString(),
      });
      return _opIsCurrent(op)
          ? _AttemptOutcome.retry
          : _AttemptOutcome.superseded;
    }
    final networkAfter = globalModel.messageReconciliationNetworkState;
    final syncPendingAfter = _env.serverSyncPending();
    final provenance = MessageReconciliationProvenance.resolve(
      requestedSource: MessageReconciliationSource.cloud,
      beforeRequest: networkBefore,
      afterResponse: networkAfter,
    );
    final epochAfter = _env.recoveryEpoch();
    final fresh = result.receivedCloudResponse &&
        freshnessProven(
          cloudTransportConfirmed: provenance.cloudTransportConfirmed,
          networkOnline: _env.networkOnline,
          transportReady: _env.transportReady(),
          serverSyncPendingBefore: syncPendingBefore,
          serverSyncPendingAfter: syncPendingAfter,
        ) &&
        epochBefore == epochAfter;

    if (!_opIsCurrent(op)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_superseded',
      );
      return _AttemptOutcome.superseded;
    }
    if (op.inPage && !_userAllowsVisibleResetAfterFetch(op)) {
      // Second position check: the user moved into history while the request
      // was in flight. Do not touch the visible timeline.
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_user_left_bottom',
      );
      _trace('latest_window_reset_defer_after_fetch', op);
      return _AttemptOutcome.deferred;
    }

    final raw = List<V2TimMessage>.from(result.messages);
    final preview = conversation.lastMessage;

    if (raw.isEmpty) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_empty',
      );
      if (preview == null && result.receivedCloudResponse && fresh) {
        // Genuinely empty conversation confirmed by the server.
        globalModel.markLocalInitialHistoryVisible(key);
        globalModel.markInitialHistoryMayHaveOlder(key, mayHaveOlder: false);
        globalModel.setMessageListPosition(
          key,
          HistoryMessagePosition.bottom,
          notify: true,
        );
        _markTrusted(op, epochAfter);
        onFirstWindowCommitted?.call();
        return _AttemptOutcome.trusted;
      }
      _trace('latest_window_reset_retry_empty', op, extras: <String, Object?>{
        'attempt': attempt,
        'receivedCloudResponse': result.receivedCloudResponse,
        'fresh': fresh,
      });
      return _AttemptOutcome.retry;
    }

    // 1. Validate the RAW window first. The preview is the target, never part
    //    of the data being validated.
    final edge = latestEdgeMatchesPreview(preview: preview, rawWindow: raw);
    final contiguous = windowIsSelfContiguous(rawWindow: raw, isGroup: isGroup);
    // SDK pages omit deleted/unavailable messages, so numeric seq gaps do not
    // prove that a fresh latest-page response is incomplete. Keep the strict
    // continuity check for unverified/local fallback data. A missing preview
    // is also not a stale edge: the fresh SDK page can establish that edge.
    final edgeAccepted = edge.matched ||
        (preview == null && fresh && rawConfirmedLatest(raw) != null);
    final windowAccepted = contiguous || fresh;
    if (!edgeAccepted || !windowAccepted) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: !edgeAccepted
            ? 'latest_window_reset_edge_mismatch'
            : 'latest_window_reset_not_contiguous',
      );
      _trace('latest_window_reset_reject_raw', op, extras: <String, Object?>{
        'attempt': attempt,
        'edgeMatched': edge.matched,
        'edgeAccepted': edgeAccepted,
        'contiguous': contiguous,
        'fresh': fresh,
        'rawNewestSeq': raw.first.seq,
        'previewSeq': preview?.seq,
        'previewMsgID': preview?.msgID,
        ...ChatHistoryTrace.windowSummary(raw, prefix: 'raw'),
      });
      return _AttemptOutcome.retry;
    }

    // 2. Only now transform and splice UI-retained items.
    var messages = raw;
    if (lifeCycle?.didGetHistoricalMessageList != null) {
      messages = await lifeCycle!.didGetHistoricalMessageList(messages);
    }
    if (clearedAt > 0 || ArchiveHistoryProvider.isInHistoryClearGrace(key)) {
      messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: key,
        messages: messages,
      );
    }
    if (!_opIsCurrent(op) ||
        (op.inPage && !_userAllowsVisibleResetAfterFetch(op))) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_stale_before_commit',
      );
      return op.inPage ? _AttemptOutcome.deferred : _AttemptOutcome.superseded;
    }
    if (messages.isEmpty) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_filtered_empty',
      );
      return _AttemptOutcome.retry;
    }
    if (!op.inPage) {
      await ChatImageMessagePrefetch.prepareFirstWindowMedia(
        messages,
        budget: ChatImageMessagePrefetch.initialMediaBudget,
        onMessageResolved: globalModel.mergeMessageMediaMetadata,
      );
    }
    final window = _spliceSelfLastMessageIfMissing(
      last: preview,
      messages: isGroup
          ? CallBubbleDedupe.prepareOpenHistoryMessages(messages)
          : TUIChatGlobalModel.dedupeMessages(messages),
    );

    // 3. INSTALL. The request's clearEpoch must still be the one it began
    //    with; a wipe or clear in between makes the commit stale.
    if (clearedAt != await ArchiveHistoryProvider.historyClearedAtMs(key)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_clear_epoch_changed',
      );
      return _AttemptOutcome.retry;
    }
    final batch = result.toBatch(
      conversationKey: key,
      requestedSource: MessageReconciliationSource.cloud,
      actualSource: provenance.actualSource,
      requestGeneration: request.generation,
      clearEpoch: clearedAt,
      cloudResponseProven: provenance.cloudTransportConfirmed,
      batchKind: MessageHistoryBatchKind.latestWindow,
      messages: window,
    );
    final commit = globalModel.completeHistoryBatch(
      request: request,
      batch: batch,
      networkState: provenance.networkState,
      clearEpoch: clearedAt,
      memoryWindowPreferLatest: true,
      historyCommitSource:
          op.inPage ? 'latest_window_reset_in_page' : 'latest_window_reset_open',
    );
    if (commit == null) {
      _trace('latest_window_reset_commit_rejected', op, extras: <String, Object?>{
        'attempt': attempt,
      });
      return _AttemptOutcome.retry;
    }
    if (op.inPage) {
      final restamped = globalModel.restampVisibleWindowToLatest(
        conversationID: key,
        latestWindow: batch.messages.toList(growable: false),
      );
      if (!restamped) {
        // completeHistoryBatch for a latest window intentionally keeps older
        // rows; if restamp cannot narrow (no scope / active request), force the
        // validated continuous window alone so we never leave a holey merge.
        globalModel.setMessageList(
          key,
          batch.messages.toList(growable: false),
          replace: true,
          needResetNewMessageCount: false,
          applyMemoryWindow: false,
          memoryWindowPreferLatest: true,
          historyCommitSource: 'latest_window_reset_force_narrow',
        );
        globalModel.markMemoryWindowMissingOlder(key);
      }
      _trace('latest_window_reset_restamp', op, extras: <String, Object?>{
        'restamped': restamped,
        'forcedNarrow': !restamped,
      });
    }

    final canCertify = result.receivedCloudResponse &&
        provenance.cloudTransportConfirmed &&
        _env.networkOnline &&
        _env.transportReady() &&
        !_env.serverSyncPending();
    if (canCertify) {
      globalModel.markCloudInitialHistoryVerified(key);
    } else {
      globalModel.markLocalInitialHistoryVisible(key);
    }
    globalModel.markInitialHistoryMayHaveOlder(
      key,
      mayHaveOlder: result.hasMoreOlder ||
          window.length >= HistoryMessageDartConstant.initialOpenFetchCount,
    );
    globalModel.setMessageListPosition(
      key,
      HistoryMessagePosition.bottom,
      notify: !op.inPage,
    );
    onFirstWindowCommitted?.call();
    _trace('latest_window_reset_installed', op, extras: <String, Object?>{
      'attempt': attempt,
      'fresh': fresh,
      'previewUnverifiable': edge.previewUnverifiable,
      'certified': canCertify,
      'rawCount': commit.rawCount,
      'hasMoreOlder': result.hasMoreOlder,
    });

    // 4. TRUST only with freshness proof.
    if (fresh) {
      _markTrusted(op, epochAfter);
      return _AttemptOutcome.trusted;
    }
    return _AttemptOutcome.installedProvisional;
  }

  void _markTrusted(_ResetOperation op, int epoch) {
    final key = op.conversationKey;
    _provisionalKeys.remove(key);
    ChatLatestWindowTrust.instance.markTrusted(key, epoch);
    ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(
      MessageConversationId.normalizeComparableKey(key),
    );
    ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);
  }

  // ---------------------------------------------------------------------------
  // Offline provisional
  // ---------------------------------------------------------------------------

  Future<LatestWindowResetOutcome> _installOfflineProvisional({
    required _ResetOperation op,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    final conversation = op.conversation;
    final isGroup = _isGroup(conversation);
    // Never reuse the stale cache as the offline window either.
    _wipeOnce(op);
    _provisionalKeys.add(key);
    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
    final networkState = globalModel.messageReconciliationNetworkState;
    final request = globalModel.beginHistoryReconciliation(
      conversationID: key,
      requestedSource: MessageReconciliationSource.local,
      networkState: networkState,
    );
    final local = await _env.loadLocal(conversation);
    if (!_opIsCurrent(op)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_offline_superseded',
      );
      return LatestWindowResetOutcome.skipped;
    }
    var messages = List<V2TimMessage>.from(local.messages);
    if (messages.isNotEmpty && lifeCycle?.didGetHistoricalMessageList != null) {
      messages = await lifeCycle!.didGetHistoricalMessageList(messages);
    }
    if (clearedAt > 0 || ArchiveHistoryProvider.isInHistoryClearGrace(key)) {
      messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: key,
        messages: messages,
      );
    }
    final window = TUIChatGlobalModel.sortMessagesNewestFirst(
      isGroup
          ? CallBubbleDedupe.prepareOpenHistoryMessages(messages)
          : TUIChatGlobalModel.dedupeMessages(messages),
    );
    // Only this page's own continuity is validated; nothing about the server.
    // A local page with a seq hole is not a continuous window at all.
    if (window.isEmpty ||
        !windowIsSelfContiguous(rawWindow: window, isGroup: isGroup)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: window.isEmpty
            ? 'latest_window_offline_local_empty'
            : 'latest_window_offline_local_not_contiguous',
      );
      _trace('latest_window_offline_no_local_window', op, extras: <String, Object?>{
        'localCount': window.length,
      });
      // Empty + offline state; skeleton/empty, never a patched old cache.
      return LatestWindowResetOutcome.failed;
    }
    final batch = local.toBatch(
      conversationKey: key,
      requestedSource: MessageReconciliationSource.local,
      actualSource: MessageReconciliationSource.local,
      requestGeneration: request.generation,
      clearEpoch: clearedAt,
      cloudResponseProven: false,
      batchKind: MessageHistoryBatchKind.localSnapshot,
      messages: window,
    );
    final commit = globalModel.completeHistoryBatch(
      request: request,
      batch: batch,
      networkState: networkState,
      clearEpoch: clearedAt,
      historyCommitSource: 'latest_window_offline_provisional',
    );
    if (commit == null) {
      _trace('latest_window_offline_commit_rejected', op);
      return LatestWindowResetOutcome.failed;
    }
    globalModel.markLocalInitialHistoryVisible(key);
    globalModel.markInitialHistoryMayHaveOlder(
      key,
      mayHaveOlder: ChatHistoryPeekBootstrap.localFirstImpliesMayHaveOlder(
        localCount: window.length,
        localReportedHasMoreOlder: local.hasMoreOlder,
      ),
    );
    globalModel.setMessageListPosition(
      key,
      HistoryMessagePosition.bottom,
      notify: true,
    );
    onFirstWindowCommitted?.call();
    _trace('latest_window_offline_installed', op, extras: <String, Object?>{
      'count': window.length,
      'localCount': local.messages.length,
    });
    return LatestWindowResetOutcome.offlineProvisional;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _isGroup(V2TimConversation conversation) {
    return (conversation.groupID?.trim().isNotEmpty ?? false) ||
        conversation.type == 2;
  }

  /// Same semantics as the bootstrap splice: a self-sent preview tip missing
  /// from the (already validated) window is appended at the newest end.
  static List<V2TimMessage> _spliceSelfLastMessageIfMissing({
    required V2TimMessage? last,
    required List<V2TimMessage> messages,
  }) {
    if (last == null || last.isSelf != true) return messages;
    if (ConversationPreviewHistorySync.isMessageVisibleInList(last, messages)) {
      return messages;
    }
    return TUIChatGlobalModel.sortMessagesNewestFirst(
      TUIChatGlobalModel.dedupeMessages(<V2TimMessage>[last, ...messages]),
    );
  }

  void _trace(
    String event,
    _ResetOperation op, {
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    ChatHistoryTrace.log(
      event,
      conversationID: op.conversationKey,
      extras: <String, Object?>{
        'op': op.id,
        'openGeneration': op.openGeneration,
        ...extras,
      },
    );
  }
}

enum _AttemptOutcome { trusted, installedProvisional, deferred, superseded, retry }

~~~

4. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_history_peek_bootstrap.dart:1>)，原文件 lib/src/services/chat_history_peek_bootstrap.dart，1–1405 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/history_empty_retry_backoff.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_batch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_anchor.dart';

/// 用与会话预览相同的方式，为聊天页首屏灌入历史消息。
class ChatHistoryPeekBootstrap {
  ChatHistoryPeekBootstrap._();

  static final Map<String, Future<bool>> _inFlightByKey =
      <String, Future<bool>>{};
  static final Map<String, _LocalPhaseFlight> _localPhaseByKey =
      <String, _LocalPhaseFlight>{};
  static int _clearGeneration = 0;

  /// 让本地首窗先完成首帧挂载，再开始 C2C 云端校验。
  /// 这不是网络重试退避；只适用于本地首窗已经可见的打开路径。
  static const Duration c2cCloudVerifyAfterLocalFirst =
      Duration(milliseconds: 120);

  static const List<Duration> defaultRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 350),
    Duration(milliseconds: 900),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 3000),
  ];

  /// 本地-only 首屏是否仍可能有更早历史（含云端未漫游部分）。
  ///
  /// [localReportedHasMoreOlder] 来自 SDK 本地 isFinished 取反，不能单独采信：
  /// 本机只有 tip/最新一条且本地扫完时也会是 false，但云端可能还有一整窗。
  static bool localFirstImpliesMayHaveOlder({
    required int localCount,
    required bool localReportedHasMoreOlder,
    int fetchCount = HistoryMessageDartConstant.initialOpenFetchCount,
  }) {
    if (localCount <= 0) {
      return localReportedHasMoreOlder;
    }
    if (localCount < fetchCount) {
      return true;
    }
    return localReportedHasMoreOlder;
  }

  /// 内存空窗或未满首屏的薄窗：应先读本地库并尽早 signal，避免干等 CLOUD
  /// 导致 AbsorbPointer 门一直关着（能返回、列表滑不动）。
  static bool shouldAttemptLocalFirstBeforeCloud({
    required int memoryCount,
    required bool completeOpenWindow,
    int fetchCount = HistoryMessageDartConstant.initialOpenFetchCount,
  }) {
    if (completeOpenWindow) {
      return false;
    }
    if (memoryCount <= 0) {
      return true;
    }
    return memoryCount < fetchCount;
  }

  /// 本地拉取是否应替换当前内存窗（空窗，或本地不少于内存条数）。
  static bool shouldReplaceMemoryWithLocalFirst({
    required int memoryCount,
    required int localCount,
  }) {
    if (localCount <= 0) {
      return false;
    }
    if (memoryCount <= 0) {
      return true;
    }
    return localCount >= memoryCount;
  }

  @visibleForTesting
  static bool canAcceptEmptyCloudWindow({
    required int warmMessageCount,
    required MessageHistoryCoverage? coverage,
  }) {
    return warmMessageCount > 0 &&
        coverage != null &&
        coverage.acceptsEmptyLatestWindow;
  }

  /// 会话 tip 是自己发出且不在即将上屏的列表里时，拼到 newest 端。
  /// 不按时间戳丢弃：tip 不在列表即应可见。
  @visibleForTesting
  static List<V2TimMessage> spliceSelfLastMessageIfMissing({
    required V2TimMessage? last,
    required List<V2TimMessage> messages,
  }) {
    if (last == null || last.isSelf != true) {
      return messages;
    }
    if (ConversationPreviewHistorySync.isMessageVisibleInList(last, messages)) {
      return messages;
    }
    return TUIChatGlobalModel.sortMessagesNewestFirst(
      TUIChatGlobalModel.dedupeMessages(<V2TimMessage>[last, ...messages]),
    );
  }

  static bool _isC2cConversation(V2TimConversation conversation) {
    return (conversation.groupID?.trim().isEmpty ?? true) &&
        ((conversation.userID?.trim().isNotEmpty ?? false) ||
            conversation.type == 1);
  }

  static bool _usesOfficialSdkHistory(V2TimConversation conversation) {
    if (_isC2cConversation(conversation)) {
      final userID = conversation.userID?.trim() ?? '';
      return !userID.startsWith('@TOA#_');
    }
    return (conversation.groupID?.trim().isNotEmpty ?? false) ||
        conversation.type == 2;
  }

  /// Final authority and first-paint source are separate policies. Ordinary
  /// C2C/group chats use cloud authority but still allow an SDK-local snapshot.
  @visibleForTesting
  static bool allowsLocalSnapshotFirst(V2TimConversation conversation) {
    return ConversationPeekService.canPeek(conversation);
  }

  static final _emptyCloudBackoff = HistoryEmptyRetryBackoff();

  static String _retryKey(String conversationID) {
    final identity = SessionIdentityService.instance.capture();
    return '${identity.ownerUserId}|${identity.generation}|$conversationID';
  }

  static String _retrySignature(
      V2TimConversation conversation, TUIChatGlobalModel model, String key) {
    final last = conversation.lastMessage;
    return '${last?.msgID}|${last?.seq}|${last?.timestamp}|'
        '${model.messageListRevisionFor(key)}|'
        '${model.messageDeltaClearEpochFor(key)}|'
        '${model.messageReconciliationNetworkState.name}';
  }

  static bool isCloudRetryDeferred(
      V2TimConversation conversation, TUIChatGlobalModel model) {
    final key = ConversationPreviewHistorySync.conversationMessageCacheKey(
        conversation);
    return key != null &&
        _emptyCloudBackoff.isDeferred(
            _retryKey(key), _retrySignature(conversation, model, key));
  }

  static void invalidateCloudRetry(V2TimConversation conversation) {
    final key = ConversationPreviewHistorySync.conversationMessageCacheKey(
        conversation);
    if (key != null) _emptyCloudBackoff.invalidate(_retryKey(key));
  }

  static void clearSession() {
    _clearGeneration++;
    for (final phase in _localPhaseByKey.values) {
      phase.complete(false);
    }
    _localPhaseByKey.clear();
    _inFlightByKey.clear();
    _emptyCloudBackoff.clear();
  }

  static String _flightKey({
    required SessionIdentity identity,
    required String conversationKey,
    required bool allowCloudVerification,
    required int clearEpoch,
    required bool clearPending,
  }) {
    return '${identity.ownerUserId}|${identity.generation}|'
        '$conversationKey|$allowCloudVerification|$clearEpoch|$clearPending';
  }

  static Future<bool> apply({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    ChatLifeCycle? lifeCycle,
    List<Duration>? retryDelays,

    /// 首屏只展示 SDK 本地快照，不在这次打开任务里发起云端校验。
    /// 用户主动上拉、重连同步和恢复任务仍可使用云端分页。
    bool allowCloudVerification = true,
    void Function()? onFirstWindowCommitted,
    ChatOpenTraceContext? logTrace,
    int? boundOpenGeneration,
  }) async {
    final key = ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (key == null || key.isEmpty) {
      return false;
    }
    if (_boundOpenAbandoned(key, boundOpenGeneration)) {
      return false;
    }
    // After a real reconnect the latest-window reset is the only first-window
    // owner for this conversation. An ordinary LOCAL/CLOUD bootstrap here
    // would reinstall the pre-reconnect page the reset exists to replace.
    if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key) ||
        ChatLatestWindowResetService.instance.isResetInFlight(key)) {
      ChatHistoryTrace.log(
        'bootstrap_skip_latest_window_reset_pending',
        conversationID: key,
        extras: <String, Object?>{
          'epoch': ImConnectStatusService.recoveryEpoch,
          'inFlight': ChatLatestWindowResetService.instance.isResetInFlight(key),
        },
      );
      return false;
    }

    final selfTrace = logTrace ??
        ChatOpenPerfLog.captureCurrent(conversationKey: key);

    final identity = SessionIdentityService.instance.capture();
    final clearGeneration = _clearGeneration;
    // Capture the per-conversation clear fence before joining or creating a
    // shared task. A route that started before a single-conversation clear
    // must not join the new task and issue a fresh read with the old state.
    final entryClearEpoch =
        await ArchiveHistoryProvider.historyClearedAtMs(key);
    final entryClearPending = ArchiveHistoryProvider.isHistoryClearPending(key);
    if (clearGeneration != _clearGeneration ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return false;
    }
    Future<bool> acceptJoinedResult(bool result) async {
      if (!result) return false;
      final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
      return clearGeneration == _clearGeneration &&
          SessionIdentityService.instance.isCurrent(identity) &&
          clearedAt == entryClearEpoch &&
          ArchiveHistoryProvider.isHistoryClearPending(key) ==
              entryClearPending;
    }

    final flightKey = _flightKey(
      identity: identity,
      conversationKey: key,
      allowCloudVerification: allowCloudVerification,
      clearEpoch: entryClearEpoch,
      clearPending: entryClearPending,
    );
    final inFlight = _inFlightByKey[flightKey];
    if (inFlight != null) {
      ChatOpenPerfLog.markHydrateJoined(
        selfTrace.requestId,
        trace: selfTrace,
      );
      ChatOpenPerfLog.mark(
        'peek_apply_join',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': selfTrace.requestId,
          'prepareId': selfTrace.requestId,
        },
        trace: selfTrace,
      );
      final result = await acceptJoinedResult(await inFlight);
      if (result) onFirstWindowCommitted?.call();
      return result;
    }

    final localKey = _flightKey(
      identity: identity,
      conversationKey: key,
      allowCloudVerification: false,
      clearEpoch: entryClearEpoch,
      clearPending: entryClearPending,
    );
    var localPhase = _localPhaseByKey[localKey];
    if (localPhase?.completed == true &&
        !globalModel.hasInitialHistoryLoaded(key)) {
      // A cloud verifier can still retain the completed local handoff after
      // leaving/re-entering the page evicts its window. That old success no
      // longer supplies a first window. Keep the cloud flight, but let this
      // open own a fresh local read; an actually loaded empty window remains
      // reusable through its initial-history flag.
      _localPhaseByKey.remove(localKey);
      localPhase = null;
    }
    if (!allowCloudVerification && localPhase != null) {
      localPhase.retain();
      ChatOpenPerfLog.markHydrateJoined(
        selfTrace.requestId,
        trace: selfTrace,
      );
      ChatOpenPerfLog.mark(
        'peek_apply_local_join',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': selfTrace.requestId,
          'prepareId': selfTrace.requestId,
        },
        trace: selfTrace,
      );
      try {
        final result = await acceptJoinedResult(await localPhase.future);
        if (result) onFirstWindowCommitted?.call();
        return result;
      } finally {
        _releaseLocalPhase(localKey, localPhase);
      }
    }
    localPhase ??= _LocalPhaseFlight();
    final ownsLocalPhase = !_localPhaseByKey.containsKey(localKey);
    if (ownsLocalPhase) {
      _localPhaseByKey[localKey] = localPhase;
    } else {
      localPhase.retain();
    }

    // Register the cloud task before waiting for local. A second cloud
    // verifier must join this Future instead of each starting its own cloud
    // pass after the shared local Future completes.
    late final Future<bool> task;
    task = () async {
      try {
        var localHandoffCompleted = allowCloudVerification &&
            globalModel.hasInitialHistoryLoaded(key) &&
            globalModel.rawMessageCount(key) > 0;
        if (allowCloudVerification &&
            !ownsLocalPhase &&
            !localHandoffCompleted) {
          try {
            localHandoffCompleted = await localPhase!.future;
          } catch (_) {
            localHandoffCompleted = false;
          }
          if (!SessionIdentityService.instance.isCurrent(identity) ||
              clearGeneration != _clearGeneration) {
            return false;
          }
          if (!localHandoffCompleted) {
            return false;
          }
        }
        if (allowCloudVerification &&
            isCloudRetryDeferred(conversation, globalModel)) {
          ChatHistoryTrace.log('bootstrap_empty_cloud_backoff',
              conversationID: key);
          return false;
        }
        if (_boundOpenAbandoned(key, boundOpenGeneration)) {
          return false;
        }
        return await _applyImpl(
          conversation: conversation,
          globalModel: globalModel,
          lifeCycle: lifeCycle,
          retryDelays: retryDelays,
          allowCloudVerification: allowCloudVerification,
          key: key,
          clearGeneration: clearGeneration,
          entryClearEpoch: entryClearEpoch,
          entryClearPending: entryClearPending,
          localHandoffCompleted: localHandoffCompleted,
          localPhase: localPhase!,
          onFirstWindowCommitted: onFirstWindowCommitted,
          logTrace: selfTrace,
          boundOpenGeneration: boundOpenGeneration,
        );
      } finally {
        localPhase!.complete(false);
      }
    }();
    _inFlightByKey[flightKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_inFlightByKey[flightKey], task)) {
        _inFlightByKey.remove(flightKey);
      }
      _releaseLocalPhase(localKey, localPhase);
    }
  }

  static bool _boundOpenAbandoned(String key, int? boundOpenGeneration) {
    if (boundOpenGeneration == null) {
      return false;
    }
    return ChatViewportCollection.instance.isOpenGenerationAbandoned(
      key,
      boundOpenGeneration,
    );
  }

  static void _releaseLocalPhase(String key, _LocalPhaseFlight phase) {
    phase.release();
    if (phase.users == 0 &&
        phase.completed &&
        identical(_localPhaseByKey[key], phase)) {
      _localPhaseByKey.remove(key);
    }
  }

  static Future<bool> _applyImpl({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    ChatLifeCycle? lifeCycle,
    List<Duration>? retryDelays,
    required bool allowCloudVerification,
    required String key,
    required int clearGeneration,
    required int entryClearEpoch,
    required bool entryClearPending,
    required bool localHandoffCompleted,
    required _LocalPhaseFlight localPhase,
    void Function()? onFirstWindowCommitted,
    required ChatOpenTraceContext logTrace,
    int? boundOpenGeneration,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    bool sessionIsCurrent() =>
        clearGeneration == _clearGeneration &&
        SessionIdentityService.instance.capture() == identity;
    bool boundAbandoned() => _boundOpenAbandoned(key, boundOpenGeneration);
    var firstWindowSignaled = false;
    final firstWindowAlreadyVisible =
        globalModel.hasInitialHistoryLoaded(key) &&
            globalModel.rawMessageCount(key) > 0;
    void signalFirstWindow() {
      if (firstWindowSignaled) {
        return;
      }
      if (boundAbandoned()) {
        return;
      }
      if (allowCloudVerification && firstWindowAlreadyVisible) {
        return;
      }
      firstWindowSignaled = true;
      ChatOpenPerfLog.markOwnedCommit(trace: logTrace);
      ChatOpenPerfLog.mark(
        'app_bootstrap_commit',
        extras: <String, Object?>{
          'requestId': logTrace.requestId,
          'prepareId': logTrace.requestId,
        },
        trace: logTrace,
      );
      onFirstWindowCommitted?.call();
    }

    void signalLocalPhase(bool result) => localPhase.complete(result);
    Future<bool> clearFenceIsCurrent() async {
      final currentEpoch = await ArchiveHistoryProvider.historyClearedAtMs(key);
      return currentEpoch == entryClearEpoch &&
          ArchiveHistoryProvider.isHistoryClearPending(key) ==
              entryClearPending;
    }

    if (!sessionIsCurrent() || !await clearFenceIsCurrent()) return false;
    if (boundAbandoned()) return false;

    if (!ConversationPeekService.canPeek(conversation)) {
      ChatHistoryTrace.log('bootstrap_skip_cannot_peek', conversationID: key);
      return false;
    }

    // Search jumps own history initialization. Do not let the warm/latest
    // bootstrap race the anchor request and overwrite its context window.
    final jumpStatus = globalModel.getSearchJumpStatus(key);
    if (jumpStatus == SearchJumpStatus.loading ||
        jumpStatus == SearchJumpStatus.positioning) {
      ChatHistoryTrace.log(
        'bootstrap_skip_search_jump_loading',
        conversationID: key,
      );
      return false;
    }

    final beforeWarm = globalModel.messageListMap[key];
    // Local-first entry has already completed even for a short window. Cloud
    // verification owns freshness separately; do not re-read the same local
    // twenty rows merely because cloud coverage remains provisional.
    if (!allowCloudVerification &&
        ConversationPreviewHistorySync.isWarmWindowReadyForOpen(
          globalModel: globalModel,
          conversationKey: key,
          preview: conversation.lastMessage,
        )) {
      ChatHistoryTrace.log('bootstrap_skip_local_window_ready',
          conversationID: key);
      signalLocalPhase(true);
      signalFirstWindow();
      return true;
    }
    ChatHistoryTrace.log(
      'bootstrap_start',
      conversationID: key,
      extras: <String, Object?>{
        'rawConvID': conversation.conversationID,
        'groupID': conversation.groupID ?? '',
        'displayName': conversation.showName?.trim() ?? '',
        'warmLoaded': globalModel.hasInitialHistoryLoaded(key),
        ...ChatHistoryTrace.windowSummary(beforeWarm, prefix: 'warm'),
      },
    );

    final existingAtStart = globalModel.mergedAliasMessageList(key);
    var cachedCoverage = globalModel.messageHistoryCoverageFor(key);
    Future<bool> warmCoverageAllowsSkip() async {
      if (ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
        preview: conversation.lastMessage,
        cached: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
      )) return false;
      cachedCoverage ??=
          await globalModel.ensureMessageHistoryCoverageLoaded(key);
      return cachedCoverage!.acceptsEmptyLatestWindow;
    }

    if (_usesOfficialSdkHistory(conversation) &&
        HistoryPaginationAnchor.shouldRejectC2cPeekRestamp(
          existingCount: existingAtStart.length,
          incomingCount: HistoryMessageDartConstant.initialOpenFetchCount,
        )) {
      // Release the already-warm UI before the metadata read. Missing or
      // provisional coverage continues into the cloud verification path.
      signalFirstWindow();
      if (!await warmCoverageAllowsSkip()) {
        ChatHistoryTrace.log(
          'bootstrap_c2c_filled_needs_cloud_verify',
          conversationID: key,
          extras: <String, Object?>{
            'coverageStatus': cachedCoverage?.status.name ?? 'missing',
          },
        );
      } else {
        OutgoingVisibleProbe.log(
          'bootstrap_skip_c2c_filled_sdk',
          conversationID: key,
          extras: <String, Object?>{'existingCount': existingAtStart.length},
        );
        signalLocalPhase(true);
        return true;
      }
    }

    // 重连预热 / 冷开并行 peek 已灌窗且 tip 对齐：跳过再打 LOCAL→CLOUD→归档。
    if (ConversationPreviewHistorySync.canSkipOpenRebootstrap(
      globalModel: globalModel,
      conversationKey: key,
      preview: conversation.lastMessage,
    )) {
      signalFirstWindow();
      if (!await warmCoverageAllowsSkip()) {
        ChatHistoryTrace.log(
          'bootstrap_warm_needs_cloud_verify',
          conversationID: key,
          extras: <String, Object?>{
            'coverageStatus': cachedCoverage?.status.name ?? 'missing',
          },
        );
      } else {
        OutgoingVisibleProbe.log(
          'bootstrap_warm_skip',
          conversationID: key,
          extras: OutgoingVisibleProbe.trackedInList(beforeWarm),
        );
        ChatHistoryTrace.log(
          'bootstrap_skip_already_warm',
          conversationID: key,
          extras: ChatHistoryTrace.windowSummary(beforeWarm, prefix: 'warm'),
        );
        ChatOpenPerfLog.mark(
          'page_bootstrap_warm_skip',
          conversationID: key,
          extras: <String, Object?>{'warmCount': beforeWarm?.length ?? 0},
          trace: logTrace,
        );
        signalLocalPhase(true);
        return true;
      }
    }

    // 清空宽限期内且内存已有消息：过滤水位前旧消息后直接展示。
    // 内存仍为空时不在这里 return，继续单次 peek，以免漏掉清空后的新消息。
    if (ArchiveHistoryProvider.isInHistoryClearGrace(key) &&
        globalModel.hasInitialHistoryLoaded(key) &&
        globalModel.rawMessageCount(key) > 0) {
      final existing =
          globalModel.messageListMap[key] ?? const <V2TimMessage>[];
      final kept = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: key,
        messages: existing,
      );
      if (!sessionIsCurrent() || !await clearFenceIsCurrent()) return false;
      if (boundAbandoned()) return false;
      final localRequest = globalModel.beginHistoryReconciliation(
        conversationID: key,
        requestedSource: MessageReconciliationSource.local,
        networkState: globalModel.messageReconciliationNetworkState,
      );
      final localBatch = MessageHistoryBatch<V2TimMessage>(
        conversationKey: key,
        requestedSource: MessageReconciliationSource.local,
        actualSource: MessageReconciliationSource.local,
        batchKind: MessageHistoryBatchKind.localSnapshot,
        requestGeneration: localRequest.generation,
        clearEpoch: await ArchiveHistoryProvider.historyClearedAtMs(key),
        isFinished: true,
        hasMoreOlder: false,
        cloudHasMoreNewer: false,
        cloudResponseProven: false,
        messages: spliceSelfLastMessageIfMissing(
          last: conversation.lastMessage,
          messages: kept,
        ),
      );
      final localCommit = globalModel.completeHistoryBatch(
        request: localRequest,
        batch: localBatch,
        networkState: globalModel.messageReconciliationNetworkState,
        clearEpoch: localBatch.clearEpoch,
        historyCommitSource: 'bootstrap_clear_grace_local',
      );
      if (localCommit == null) return false;
      globalModel.markLocalInitialHistoryVisible(key);
      ChatHistoryTrace.log(
        'bootstrap_keep_clear_grace',
        conversationID: key,
        extras: ChatHistoryTrace.windowSummary(kept, prefix: 'kept'),
      );
      signalLocalPhase(true);
      signalFirstWindow();
      return true;
    }

    // 曾清空过 / 宽限期内空列表：只拉一轮并过滤水位前消息，缩短空会话进页等待。
    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
    final inClearGrace = ArchiveHistoryProvider.isInHistoryClearGrace(key);
    final clearPendingAtStart = ArchiveHistoryProvider.isHistoryClearPending(
      key,
    );
    await globalModel.ensureMessageHistoryCoverageLoaded(
      key,
      clearEpoch: clearedAt,
    );

    bool positionAllowsCommit() {
      return globalModel.getMessageListPosition(key) ==
              HistoryMessagePosition.bottom &&
          globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle;
    }

    Future<bool> canCommitInitialWindow() async {
      if (!sessionIsCurrent() || !await clearFenceIsCurrent()) return false;
      if (!positionAllowsCommit()) {
        ChatHistoryTrace.log(
          'bootstrap_abort_history_position',
          conversationID: key,
        );
        return false;
      }
      final currentClearedAt = await ArchiveHistoryProvider.historyClearedAtMs(
        key,
      );
      final currentClearPending = ArchiveHistoryProvider.isHistoryClearPending(
        key,
      );
      if (currentClearedAt != clearedAt ||
          currentClearPending != clearPendingAtStart) {
        ChatHistoryTrace.log(
          'bootstrap_abort_history_clear_changed',
          conversationID: key,
          extras: <String, Object?>{
            'clearedAtBefore': clearedAt,
            'clearedAtNow': currentClearedAt,
            'pendingBefore': clearPendingAtStart,
            'pendingNow': currentClearPending,
          },
        );
        return false;
      }
      return sessionIsCurrent() && await clearFenceIsCurrent();
    }

    // 冷启动 / 薄窗：先只读本地并尽快提交，让聊天树可交互；
    // 后面的 LOCAL→CLOUD→归档仅负责补齐校对。
    // 薄窗若跳过本步，会干等云端 → AbsorbPointer 门长期不关（能返回不能滑）。
    final memoryCountBeforeLocal = globalModel.rawMessageCount(key);
    final completeBeforeLocal =
        ConversationPreviewHistorySync.isCompleteOpenHistoryWindow(
      globalModel: globalModel,
      conversationKey: key,
    );
    final isC2c = _isC2cConversation(conversation);
    final usesOfficialSdkHistory = _usesOfficialSdkHistory(conversation);
    var localFirstPaintCommitted = false;
    var localSdkHasMoreOlder = true; // 任意默认保守：直到 local fetch 完成才确定
    if (!localHandoffCompleted &&
        allowsLocalSnapshotFirst(conversation) &&
        shouldAttemptLocalFirstBeforeCloud(
          memoryCount: memoryCountBeforeLocal,
          completeOpenWindow: completeBeforeLocal,
        ) &&
        positionAllowsCommit()) {
      if (boundAbandoned()) {
        signalLocalPhase(false);
        return false;
      }
      final localNetworkState = globalModel.messageReconciliationNetworkState;
      final localRequest = globalModel.beginHistoryReconciliation(
        conversationID: key,
        requestedSource: MessageReconciliationSource.local,
        networkState: localNetworkState,
      );
      final localFetchStopwatch = Stopwatch()..start();
      ChatOpenPerfLog.markOwnedDbRead(trace: logTrace);
      ChatOpenPerfLog.mark(
        'peek_apply_local_real',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': logTrace.requestId,
          'prepareId': logTrace.requestId,
        },
        trace: logTrace,
      );
      final epochBeforeLocal = ImConnectStatusService.recoveryEpoch;
      final local = await ConversationPeekService.loadLocalForChatEntry(
        conversation,
      );
      if (boundAbandoned()) {
        globalModel.failHistoryReconciliation(
          request: localRequest,
          reason: 'bootstrap_open_generation_abandoned',
        );
        signalLocalPhase(false);
        return false;
      }
      if (epochBeforeLocal != ImConnectStatusService.recoveryEpoch) {
        // A real reconnect completed while the local page was being read;
        // that page is now the stale window. Hand over to the reset owner.
        globalModel.failHistoryReconciliation(
          request: localRequest,
          reason: 'bootstrap_local_stale_recovery_epoch',
        );
        ChatHistoryTrace.log(
          'bootstrap_local_stale_recovery_epoch',
          conversationID: key,
          extras: <String, Object?>{
            'epochBefore': epochBeforeLocal,
            'epochNow': ImConnectStatusService.recoveryEpoch,
          },
        );
        signalLocalPhase(false);
        return false;
      }
      localSdkHasMoreOlder = local.hasMoreOlder;
      var localMessages = List<V2TimMessage>.from(local.messages);
      if (isC2c) {
        ChatOpenPerfLog.mark(
          'c2c_local_fetch_done',
          conversationID: key,
          extras: <String, Object?>{
            'count': localMessages.length,
            'durationMs': localFetchStopwatch.elapsedMilliseconds,
            'position': globalModel.getMessageListPosition(key).name,
            'searchStatus': globalModel.getSearchJumpStatus(key).name,
            'rawCount': globalModel.rawMessageCount(key),
          },
          trace: logTrace,
        );
      }
      if (localMessages.isNotEmpty &&
          lifeCycle?.didGetHistoricalMessageList != null) {
        localMessages =
            await lifeCycle!.didGetHistoricalMessageList(localMessages);
      }
      // Start only the newest visible media rows before the local snapshot is
      // committed. This call does not wait for network URL lookup or decode;
      // misses continue in the background through the row-local media path.
      if (localMessages.isNotEmpty) {
        await ChatImageMessagePrefetch.prepareFirstWindowMedia(
          localMessages,
          budget: ChatImageMessagePrefetch.initialMediaBudget,
          onMessageResolved: globalModel.mergeMessageMediaMetadata,
        );
      }
      if (localMessages.isNotEmpty &&
          shouldReplaceMemoryWithLocalFirst(
            memoryCount: globalModel.rawMessageCount(key),
            localCount: localMessages.length,
          ) &&
          await canCommitInitialWindow()) {
        OutgoingVisibleProbe.log(
          'bootstrap_local_first',
          conversationID: key,
          extras: <String, Object?>{
            'memoryCountBefore': memoryCountBeforeLocal,
            'localCount': localMessages.length,
            'willReplace': true,
            'lastMessage': conversation.lastMessage == null
                ? ''
                : OutgoingVisibleProbe.brief(conversation.lastMessage!),
            'memoryTracked': OutgoingVisibleProbe.trackedInList(
              globalModel.rawMessageList(key),
            ).toString(),
            'localTracked':
                OutgoingVisibleProbe.trackedInList(localMessages).toString(),
          },
        );
        final localWindow = ChatViewportReadiness.mergePreserveRealtime(
          current: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
          incoming: ChatViewportReadiness.takeNewestContiguous(
            newestFirst: spliceSelfLastMessageIfMissing(
              last: conversation.lastMessage,
              messages:
                  CallBubbleDedupe.prepareOpenHistoryMessages(localMessages),
            ),
            useSeqContiguity: !isC2c,
          ),
        );
        final localBatch = local.toBatch(
          conversationKey: key,
          requestedSource: MessageReconciliationSource.local,
          actualSource: MessageReconciliationSource.local,
          requestGeneration: localRequest.generation,
          clearEpoch: clearedAt,
          cloudResponseProven: false,
          batchKind: MessageHistoryBatchKind.localSnapshot,
          messages: localWindow,
        );
        final localCommit = globalModel.completeHistoryBatch(
          request: localRequest,
          batch: localBatch,
          networkState: localNetworkState,
          clearEpoch: clearedAt,
          historyCommitSource: 'bootstrap_local_snapshot',
        );
        if (localCommit == null) {
          if (isC2c) {
            ChatOpenPerfLog.mark(
              'c2c_local_commit_rejected',
              conversationID: key,
              extras: <String, Object?>{
                'count': localMessages.length,
                'durationMs': localFetchStopwatch.elapsedMilliseconds,
                'position': globalModel.getMessageListPosition(key).name,
                'searchStatus': globalModel.getSearchJumpStatus(key).name,
                'rawCount': globalModel.rawMessageCount(key),
                'requestKeyAlias': localRequest.conversationKey != key,
              },
              trace: logTrace,
            );
          }
          globalModel.failHistoryReconciliation(
            request: localRequest,
            reason: 'bootstrap_local_snapshot_stale',
          );
        } else {
          if (isC2c) {
            ChatOpenPerfLog.mark(
              'c2c_local_commit_committed',
              conversationID: key,
              extras: <String, Object?>{
                'count': localMessages.length,
                'durationMs': localFetchStopwatch.elapsedMilliseconds,
                'position': globalModel.getMessageListPosition(key).name,
                'searchStatus': globalModel.getSearchJumpStatus(key).name,
                'rawCount': localCommit.rawCount,
                'requestKeyAlias': localRequest.conversationKey != key,
              },
              trace: logTrace,
            );
          }
          // Local data releases the first-frame gate but is not cloud proof.
          globalModel.markLocalInitialHistoryVisible(key);
          // 本地 isFinished 只表示本机库扫完，不等于云端没有更早历史。
          // 不满首屏窗口时必须保持 mayHaveOlder，否则会把 1 条当「完整短会话」
          // 提前揭开，云端补数时再整表蹦出。
          globalModel.markInitialHistoryMayHaveOlder(
            key,
            mayHaveOlder: localFirstImpliesMayHaveOlder(
              localCount: localMessages.length,
              localReportedHasMoreOlder: local.hasMoreOlder,
            ),
          );
          globalModel.setMessageListPosition(
            key,
            HistoryMessagePosition.bottom,
            notify: true,
          );
          ChatOpenPerfLog.mark(
            'page_bootstrap_local_first',
            conversationID: key,
            extras: <String, Object?>{
              'localCount': localMessages.length,
              'localHasMoreOlder': local.hasMoreOlder,
              'memoryCountBefore': memoryCountBeforeLocal,
            },
            trace: logTrace,
          );
          // 有本地最新消息就立刻揭开首屏（贴底）；云端在同任务后续静默合并，
          // 反转列表 + bottom 锚点让旧消息向上长、最新一条不跳。
          localFirstPaintCommitted = true;
          signalFirstWindow();
        }
      } else {
        globalModel.failHistoryReconciliation(
          request: localRequest,
          reason: localMessages.isEmpty
              ? 'bootstrap_local_snapshot_empty'
              : 'bootstrap_local_snapshot_not_eligible',
        );
      }
    }

    if (!allowCloudVerification) {
      if (boundAbandoned()) {
        signalLocalPhase(false);
        return false;
      }
      // 首屏策略到这里仍只允许本地快照。即使本地为空，也要把“本地
      // 已读完、云端尚未校验”的状态发布出去，否则页面会一直等待首屏
      // gate；后续用户上拉时再走正常云端分页。
      final localVisibleCount = globalModel.rawMessageCount(key);
      // 充分利用 localSdkHasMoreOlder：SDK 已经扫完本地（hasMoreOlder=false）
      // 时不再人为设 true，否则 schedule_previous_attempt 会因为
      // haveMoreData=true 反复触发，UI 看见重复 5 条同 SDK 返回的“噪音补拉”。
      // 不满首窗仍保持 true（与 localFirstImpliesMayHaveOlder 保持一致）。
      final mayHaveOlder = localFirstImpliesMayHaveOlder(
        localCount: localVisibleCount,
        localReportedHasMoreOlder: localSdkHasMoreOlder,
      );
      if (!await canCommitInitialWindow()) {
        // 搜索定位、挂起的滚动恢复或用户已经离开底部时，不要为了释放
        // 首屏 gate 强行改写滚动位置；当前窗口仍由 UIKit 自己接管。
        signalFirstWindow();
        signalLocalPhase(false);
        ChatHistoryTrace.log(
          'bootstrap_local_only_deferred_by_position',
          conversationID: key,
        );
        return false;
      }
      globalModel.markLocalInitialHistoryVisible(key);
      globalModel.markInitialHistoryMayHaveOlder(
        key,
        mayHaveOlder: mayHaveOlder,
      );
      globalModel.setMessageListPosition(
        key,
        HistoryMessagePosition.bottom,
        notify: true,
      );
      signalLocalPhase(true);
      signalFirstWindow();
      ChatHistoryTrace.log(
        'bootstrap_local_only_done',
        conversationID: key,
        extras: <String, Object?>{
          'localCount': localVisibleCount,
          'mayHaveOlder': mayHaveOlder,
        },
      );
      return true;
    }

    // The local handoff is complete before cloud verification begins. A
    // local-only opener joining a cloud-first task can now return its local
    // result without waiting for the network pass.
    signalLocalPhase(true);

    var delays = (clearedAt > 0 || inClearGrace)
        ? const <Duration>[Duration.zero]
        : (retryDelays ?? defaultRetryDelays);
    if (localFirstPaintCommitted && isC2c && delays.isNotEmpty) {
      // The first cloud request should not compete with the first route frame.
      // Keep caller-provided retry cadence for subsequent attempts.
      delays = <Duration>[c2cCloudVerifyAfterLocalFirst, ...delays.skip(1)];
    }
    for (var index = 0; index < delays.length; index++) {
      final delay = delays[index];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!sessionIsCurrent() || !await clearFenceIsCurrent()) return false;
      if (boundAbandoned()) return false;
      if (!positionAllowsCommit()) {
        ChatHistoryTrace.log(
          'bootstrap_abort_history_position',
          conversationID: key,
        );
        return false;
      }

      final networkBefore = globalModel.messageReconciliationNetworkState;
      final request = globalModel.beginHistoryReconciliation(
        conversationID: key,
        requestedSource: MessageReconciliationSource.cloud,
        networkState: networkBefore,
      );
      final retryKey = _retryKey(key);
      final retrySignature = _retrySignature(conversation, globalModel, key);
      final sdkFetchStopwatch = Stopwatch()..start();
      ChatOpenPerfLog.markOwnedSdkRead(trace: logTrace);
      ChatOpenPerfLog.mark(
        'peek_apply_sdk_real',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': logTrace.requestId,
          'prepareId': logTrace.requestId,
        },
        trace: logTrace,
      );
      final result = await ConversationPeekService.loadForChatEntry(
        conversation,
      );
      if (boundAbandoned()) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_open_generation_abandoned',
        );
        return false;
      }
      if (isC2c) {
        ChatOpenPerfLog.mark(
          'c2c_sdk_callback_received',
          conversationID: key,
          extras: <String, Object?>{
            'count': result.messages.length,
            'durationMs': sdkFetchStopwatch.elapsedMilliseconds,
            'retry': index,
            'position': globalModel.getMessageListPosition(key).name,
            'searchStatus': globalModel.getSearchJumpStatus(key).name,
            'rawCount': globalModel.rawMessageCount(key),
          },
          trace: logTrace,
        );
      }
      if (!await canCommitInitialWindow()) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_cloud_scope_or_position_changed',
        );
        ChatHistoryTrace.log(
          'bootstrap_abort_history_position',
          conversationID: key,
        );
        return false;
      }
      if (result.messages.isEmpty) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_cloud_window_empty',
        );
        // SDK/归档本轮为空：保留已有 peek 暖窗，禁止用空结果抹掉。
        final warmCount = globalModel.rawMessageCount(key);
        final coverage = globalModel.messageHistoryCoverageFor(key);
        if (canAcceptEmptyCloudWindow(
          warmMessageCount: warmCount,
          coverage: coverage,
        )) {
          ChatHistoryTrace.log(
            'bootstrap_empty_keep_verified_warm',
            conversationID: key,
            extras: <String, Object?>{
              'retry': index,
              ...ChatHistoryTrace.windowSummary(
                globalModel.messageListMap[key],
                prefix: 'warm',
              ),
            },
          );
          return true;
        }
        if (result.receivedCloudResponse) {
          _emptyCloudBackoff.recordEmpty(retryKey, retrySignature);
          ChatHistoryTrace.log('bootstrap_empty_cloud_deferred',
              conversationID: key);
          return false;
        }
        ChatHistoryTrace.log(
          warmCount > 0
              ? 'bootstrap_empty_keep_provisional_and_retry'
              : 'bootstrap_empty_retry',
          conversationID: key,
          extras: <String, Object?>{
            'retry': index,
            'coverageStatus': coverage?.status.name ?? 'missing',
            'coverageHoles': coverage?.holes.length ?? 0,
          },
        );
        continue;
      }

      _emptyCloudBackoff.invalidate(retryKey);
      var messages = List<V2TimMessage>.from(result.messages);
      final networkAfter = globalModel.messageReconciliationNetworkState;
      final provenance = MessageReconciliationProvenance.resolve(
        requestedSource: MessageReconciliationSource.cloud,
        beforeRequest: networkBefore,
        afterResponse: networkAfter,
      );
      if (lifeCycle?.didGetHistoricalMessageList != null) {
        messages = await lifeCycle!.didGetHistoricalMessageList(messages);
      }
      if (clearedAt > 0 || ArchiveHistoryProvider.isInHistoryClearGrace(key)) {
        messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
          conversationID: key,
          messages: messages,
        );
      }
      if (!await canCommitInitialWindow()) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_cloud_snapshot_stale',
        );
        return false;
      }
      if (messages.isEmpty) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_cloud_window_filtered_empty',
        );
        continue;
      }
      if (!localFirstPaintCommitted) {
        // Keep cloud reconciliation bounded by history transport only. Media
        // enrichment is already scheduled and must not delay first paint.
        await ChatImageMessagePrefetch.prepareFirstWindowMedia(
          messages,
          budget: ChatImageMessagePrefetch.initialMediaBudget,
          onMessageResolved: globalModel.mergeMessageMediaMetadata,
        );
      }

      final existing = globalModel.mergedAliasMessageList(key);
      final warmTs = existing.isEmpty
          ? 0
          : (existing
              .map((m) => m.timestamp ?? 0)
              .fold<int>(0, (a, b) => a > b ? a : b));
      final fetchedTs = messages
          .map((m) => m.timestamp ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b);
      // 拉到的首屏几乎全是旧归档，且比暖窗 tip/更新消息更旧：禁止灌入。
      if (HistoryPaginationAnchor.isStaleArchiveDominatedWindow(
        messages,
        referenceTimestampSec:
            warmTs > 0 ? warmTs : conversation.lastMessage?.timestamp,
      )) {
        globalModel.failHistoryReconciliation(
          request: request,
          reason: 'bootstrap_skip_stale_archive',
        );
        ChatHistoryTrace.log(
          'bootstrap_skip_stale_archive',
          conversationID: key,
          extras: <String, Object?>{
            'retry': index,
            'warmNewestTs': warmTs,
            'fetchedNewestTs': fetchedTs,
            ...ChatHistoryTrace.windowSummary(messages, prefix: 'fetched'),
          },
        );
        if (canAcceptEmptyCloudWindow(
          warmMessageCount: globalModel.rawMessageCount(key),
          coverage: globalModel.messageHistoryCoverageFor(key),
        )) {
          return true;
        }
        continue;
      }
      OutgoingVisibleProbe.log(
        'bootstrap_replace',
        conversationID: key,
        extras: <String, Object?>{
          'retry': index,
          'existingCount': existing.length,
          'fetchedCount': messages.length,
          'lastMessage': conversation.lastMessage == null
              ? ''
              : OutgoingVisibleProbe.brief(conversation.lastMessage!),
          'existingTracked':
              OutgoingVisibleProbe.trackedInList(existing).toString(),
          'fetchedTracked':
              OutgoingVisibleProbe.trackedInList(messages).toString(),
        },
      );
      ChatHistoryTrace.log(
        'bootstrap_replace',
        conversationID: key,
        extras: <String, Object?>{
          'retry': index,
          'hasMoreOlder': result.hasMoreOlder,
          'warmNewestTs': warmTs,
          'fetchedNewestTs': fetchedTs,
          'fetchedOlderThanWarm':
              warmTs > 0 && fetchedTs > 0 && fetchedTs < warmTs,
          ...ChatHistoryTrace.windowSummary(existing, prefix: 'before'),
          ...ChatHistoryTrace.windowSummary(messages, prefix: 'fetched'),
        },
      );

      final completeWindow =
          messages.length >= HistoryMessageDartConstant.initialOpenFetchCount;
      final exhaustedOlder = !result.hasMoreOlder;
      // 聊天首屏必须保留已经加载的历史。预加载结果可能只是 SDK 漫游尚未
      // 同步完成的部分窗口，不能像会话预览一样整表替换。
      // 已补到超过首屏的窗，禁止再用 20 条 peek 冲掉更早 IM。
      final preserveFilled = usesOfficialSdkHistory
          ? HistoryPaginationAnchor.shouldRejectC2cPeekRestamp(
              existingCount: existing.length,
              incomingCount: messages.length,
            )
          : HistoryPaginationAnchor.shouldPreserveFilledHistoryOverPeek(
              existingCount: existing.length,
              fetchedCount: messages.length,
            );
      if (preserveFilled) {
        OutgoingVisibleProbe.log(
          'bootstrap_preserve_filled_over_peek',
          conversationID: key,
          extras: <String, Object?>{
            'existingCount': existing.length,
            'fetchedCount': messages.length,
          },
        );
      }
      final merged = usesOfficialSdkHistory
          ? TUIChatGlobalModel.mergeC2cOfficialOlderPage(
              existing: existing,
              fetched: messages,
            )
          : existing.isNotEmpty && !preserveFilled
              ? TUIChatGlobalModel.mergePeekWindowWithLiveMemory(
                  existing: existing,
                  fetched: messages,
                )
              : TUIChatGlobalModel.mergeHistoricalWithInMemory(
                  existing: existing,
                  fetched: messages,
                );
      // 贴底静默合并：已有本地 tip 时不要因 notify 位置抖动触发二次 pin。
      final hadLocalFirst = existing.isNotEmpty;
      final cloudWindow = spliceSelfLastMessageIfMissing(
        last: conversation.lastMessage,
        messages: usesOfficialSdkHistory
            ? TUIChatGlobalModel.dedupeMessages(messages)
            : CallBubbleDedupe.prepareOpenHistoryMessages(merged),
      );
      final cloudBatch = result.toBatch(
        conversationKey: key,
        requestedSource: MessageReconciliationSource.cloud,
        actualSource: provenance.actualSource,
        requestGeneration: request.generation,
        clearEpoch: clearedAt,
        cloudResponseProven: provenance.cloudResponseProven,
        batchKind: MessageHistoryBatchKind.latestWindow,
        messages: cloudWindow,
      );
      final cloudCommit = globalModel.completeHistoryBatch(
        request: request,
        batch: cloudBatch,
        networkState: provenance.networkState,
        clearEpoch: clearedAt,
        memoryWindowPreferLatest: true,
        historyCommitSource: 'bootstrap_latest_window',
        skipEquivalentHistoryWindow: true,
      );
      if (cloudCommit == null) {
        if (isC2c) {
          ChatOpenPerfLog.mark(
            'c2c_sdk_callback_commit_rejected',
            conversationID: key,
            extras: <String, Object?>{
              'count': messages.length,
              'durationMs': sdkFetchStopwatch.elapsedMilliseconds,
              'retry': index,
              'position': globalModel.getMessageListPosition(key).name,
              'searchStatus': globalModel.getSearchJumpStatus(key).name,
              'rawCount': globalModel.rawMessageCount(key),
              'requestKeyAlias': request.conversationKey != key,
            },
            trace: logTrace,
          );
        }
        continue;
      }
      if (isC2c) {
        ChatOpenPerfLog.mark(
          'c2c_sdk_callback_committed',
          conversationID: key,
          extras: <String, Object?>{
            'count': messages.length,
            'durationMs': sdkFetchStopwatch.elapsedMilliseconds,
            'retry': index,
            'position': globalModel.getMessageListPosition(key).name,
            'searchStatus': globalModel.getSearchJumpStatus(key).name,
            'rawCount': cloudCommit.rawCount,
            'requestKeyAlias': request.conversationKey != key,
          },
          trace: logTrace,
        );
      }
      if (provenance.proofKind == MessageHistoryProofKind.serverContinuity) {
        globalModel.markCloudInitialHistoryVerified(key);
      } else {
        globalModel.markLocalInitialHistoryVisible(key);
      }
      globalModel.markInitialHistoryMayHaveOlder(
        key,
        // 满窗口通常仍有更早消息；SDK 明确无更早时再关掉探测。
        mayHaveOlder: !exhaustedOlder,
      );
      globalModel.setMessageListPosition(
        key,
        HistoryMessagePosition.bottom,
        notify: completeWindow && !hadLocalFirst,
      );
      OutgoingVisibleProbe.log(
        'bootstrap_done',
        conversationID: key,
        extras: OutgoingVisibleProbe.trackedInList(
          globalModel.messageListMap[key],
        ),
      );
      ChatHistoryTrace.log(
        'bootstrap_done',
        conversationID: key,
        extras: ChatHistoryTrace.windowSummary(
          globalModel.messageListMap[key],
          prefix: 'after',
        ),
      );
      signalFirstWindow();
      return true;
    }
    if (!await canCommitInitialWindow()) {
      return false;
    }
    // 清空后 / 确实无历史：标记 empty-loaded，避免上层一直转圈。
    if (clearedAt > 0 || inClearGrace) {
      globalModel.markLocalInitialHistoryVisible(key);
      globalModel.markInitialHistoryMayHaveOlder(key, mayHaveOlder: false);
    }
    ChatHistoryTrace.log(
      'bootstrap_miss',
      conversationID: key,
      extras: <String, Object?>{
        'clearedAt': clearedAt,
        'inClearGrace': inClearGrace,
      },
    );
    return false;
  }
}

class _LocalPhaseFlight {
  final Completer<bool> _completer = Completer<bool>();
  int users = 1;

  Future<bool> get future => _completer.future;

  bool get completed => _completer.isCompleted;

  void retain() {
    users++;
  }

  void release() {
    if (users > 0) {
      users--;
    }
  }

  void complete(bool result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }
}

~~~

5. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_history_sync_coordinator.dart:1>)，原文件 lib/src/services/conversation_history_sync_coordinator.dart，1–766 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_cloud_catch_up.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

enum ConversationHistorySyncOutcome {
  verified,
  retryable,
  offline,
  unauthorized,
  stale,
}

class _QueuedHistoryVerification {
  const _QueuedHistoryVerification({
    required this.conversation,
    required this.reason,
    required this.identity,
    required this.lifecycle,
    required this.retryNumber,
    this.logTrace,
  });

  final V2TimConversation conversation;
  final String reason;
  final SessionIdentity identity;
  final int lifecycle;
  final int retryNumber;
  final ChatOpenTraceContext? logTrace;
}

/// Owns the post-first-frame history reconciliation lifecycle.
///
/// The chat page may publish a local SDK snapshot immediately, but it must not
/// also own cloud verification, roaming completion, gap repair, and retries.
/// This coordinator provides one account/session-scoped flight per
/// conversation and routes every remote result through TUIChatGlobalModel's
/// reconciliation writer.
class ConversationHistorySyncCoordinator {
  ConversationHistorySyncCoordinator._();

  static final ConversationHistorySyncCoordinator instance =
      ConversationHistorySyncCoordinator._();

  static const List<Duration> _retryDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 5),
  ];

  // A completed bounded pass that still lacks cloud proof is retried later,
  // but never on an unbounded timer. Reconnect/open events may still trigger
  // an immediate fresh pass and supersede this queue item.
  static const List<Duration> _queueRetryDelays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 60),
    Duration(minutes: 5),
  ];

  // Native IM calls can otherwise keep a conversation in-flight indefinitely
  // on a stalled mobile network. The coordinator releases the flight after
  // this bound and schedules the existing bounded retry path.
  static const Duration _sdkHistoryTimeout = Duration(seconds: 12);

  final Map<String, Future<ConversationHistorySyncOutcome>> _inFlight =
      <String, Future<ConversationHistorySyncOutcome>>{};
  final Map<String, Future<ConversationHistorySyncOutcome>> _h0InFlight =
      <String, Future<ConversationHistorySyncOutcome>>{};
  final Map<String, _QueuedHistoryVerification> _retryQueue =
      <String, _QueuedHistoryVerification>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  final Map<String, int> _retryAttempts = <String, int>{};
  final Set<String> _userOlderPaginationKeys = <String>{};
  final Map<String, Future<void>> _olderPaginationInFlight =
      <String, Future<void>>{};
  final Set<String> _cancelledConversations = <String>{};
  int _lifecycleGeneration = 0;

  void cancelConversation(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isEmpty) return;
    _cancelledConversations.add(key);
    // Keep the Future in the map until it settles. Removing it here would let
    // a route re-entry start a second native request while the old one is
    // still running.
    _retryTimers.removeWhere((k, timer) {
      if (!k.endsWith('|$key')) return false;
      timer.cancel();
      _retryQueue.remove(k);
      _retryAttempts.remove(k);
      return true;
    });
  }

  /// Marks a user-driven older-page request as higher priority than the
  /// background verification pass for the same conversation.
  void beginUserOlderPagination(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isNotEmpty) {
      _userOlderPaginationKeys.add(key);
    }
  }

  void endUserOlderPagination(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isNotEmpty) {
      _userOlderPaginationKeys.remove(key);
    }
  }

  bool isUserOlderPaginationActive(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    return key.isNotEmpty && _userOlderPaginationKeys.contains(key);
  }

  /// Serializes deliberate upward-page requests for one conversation. UIKit
  /// can emit duplicate edge callbacks while the list is settling; joining
  /// the existing Future avoids concurrent native SDK history calls.
  Future<void> runUserOlderPagination({
    required String conversationID,
    required Future<void> Function() task,
  }) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isEmpty) return task();
    final existing = _olderPaginationInFlight[key];
    if (existing != null) return existing;
    final flight = task().timeout(_sdkHistoryTimeout);
    _olderPaginationInFlight[key] = flight;
    return flight.whenComplete(() {
      if (identical(_olderPaginationInFlight[key], flight)) {
        _olderPaginationInFlight.remove(key);
      }
    });
  }

  String _h0FlightKey(ChatViewportRepairTicket ticket) {
    final conversationKey = _normalizeConversationKey(ticket.conversationKey);
    return '${ticket.ownerUserId}@${ticket.accountGeneration}|$conversationKey|latest';
  }

  String _normalizeConversationKey(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower.startsWith('c2c_')) {
      final user = ChatIdFormat.rawUserUid(value.substring(4));
      return user.isEmpty ? '' : 'c2c_$user';
    }
    if (lower.startsWith('group_')) {
      final group = ChatIdFormat.canonicalGroupStorageId(value.substring(6));
      return group.isEmpty ? '' : 'group_$group';
    }
    if (ChatIdFormat.isIMGroupOrCommunityId(value) ||
        ChatIdFormat.isCommunityShortToken(value)) {
      final group = ChatIdFormat.canonicalGroupStorageId(value);
      return group.isEmpty ? '' : 'group_$group';
    }
    final user = ChatIdFormat.canonicalC2cUserId(value);
    return user.isEmpty ? value : 'c2c_$user';
  }

  Future<bool> _waitForUserOlderPagination(String conversationKey) async {
    // A warm request that has not entered the native SDK yet must yield to a
    // deliberate upward gesture. The bounded wait prevents a stuck UI flight
    // from holding the background verifier forever.
    for (var attempt = 0; attempt < 200; attempt++) {
      if (!isUserOlderPaginationActive(conversationKey)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return !isUserOlderPaginationActive(conversationKey);
  }

  /// H0：只修“当前首屏画不好”。flight key = account + conversation + latest。
  /// 页面退出作废该 openGeneration：不再开始新的 LOCAL/SDK，晚到 callback 不得写窗。
  Future<ConversationHistorySyncOutcome> repairOpenViewport({
    required V2TimConversation conversation,
    required ChatViewportRepairTicket ticket,
    ChatOpenTraceContext? logTrace,
  }) {
    final key = _h0FlightKey(ticket);
    final existing = _h0InFlight[key];
    if (existing != null) {
      return existing;
    }
    final h0Trace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    late final Future<ConversationHistorySyncOutcome> task;
    task = _runOpenViewportRepair(
      conversation: conversation,
      ticket: ticket,
      logTrace: h0Trace,
    ).whenComplete(() {
      if (identical(_h0InFlight[key], task)) {
        _h0InFlight.remove(key);
      }
    });
    _h0InFlight[key] = task;
    return task;
  }

  Future<ConversationHistorySyncOutcome> _runOpenViewportRepair({
    required V2TimConversation conversation,
    required ChatViewportRepairTicket ticket,
    required ChatOpenTraceContext logTrace,
  }) async {
    if (!_isCurrent(
      SessionIdentity(
        ownerUserId: ticket.ownerUserId,
        generation: ticket.accountGeneration,
      ),
      _lifecycleGeneration,
    )) {
      return ConversationHistorySyncOutcome.stale;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      ticket.conversationKey,
      ticket.openGeneration,
    )) {
      ChatOpenPerfLog.mark(
        'viewport_ticket_rejected',
        extras: <String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
          'ticketRejectedReason': collection.ticketRejectedReason(ticket),
          'sameConversationCache': collection.sameConversationCache(ticket),
          'uiAttached': collection.uiAttached,
        },
        trace: logTrace,
      );
      return ConversationHistorySyncOutcome.stale;
    }
    try {
      final applied = await ChatHistoryPeekBootstrap.apply(
        conversation: conversation,
        globalModel: globalModel,
        retryDelays: const <Duration>[Duration.zero],
        allowCloudVerification: true,
        logTrace: logTrace,
        boundOpenGeneration: ticket.openGeneration,
      ).timeout(_sdkHistoryTimeout);
      ChatOpenPerfLog.mark(
        'viewport_prepare_h0_commit',
        extras: <String, Object?>{
          'applied': applied,
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
        },
        trace: logTrace,
      );
      if (collection.isOpenGenerationAbandoned(
            ticket.conversationKey,
            ticket.openGeneration,
          ) ||
          !collection.acceptsTicket(ticket)) {
        ChatOpenPerfLog.mark(
          'viewport_ticket_rejected',
          extras: <String, Object?>{
            'ticketGeneration': ticket.openGeneration,
            'currentOpenGeneration': collection.openGeneration,
            'ticketRejectedReason': collection.ticketRejectedReason(ticket),
            'sameConversationCache': collection.sameConversationCache(ticket),
            'uiAttached': collection.uiAttached,
          },
          trace: logTrace,
        );
        return ConversationHistorySyncOutcome.stale;
      }
      ChatOpenPerfLog.mark(
        'viewport_ticket_accepted',
        extras: <String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
        },
        trace: logTrace,
      );
      collection.markRepair(ChatViewportRepairKind.none);
      return applied
          ? ConversationHistorySyncOutcome.verified
          : ConversationHistorySyncOutcome.retryable;
    } catch (_) {
      return ConversationHistorySyncOutcome.retryable;
    }
  }

  Future<ConversationHistorySyncOutcome> verifyAfterFirstFrame({
    required V2TimConversation conversation,
    String reason = 'chat_open',
    Duration delay = const Duration(milliseconds: 700),
    ChatOpenTraceContext? logTrace,
    int? boundOpenGeneration,
  }) {
    final verifyTrace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    Future<ConversationHistorySyncOutcome> startVerify() {
      return _verifyAfterFirstFrame(
        conversation: conversation,
        reason: reason,
        delay: delay,
        fromRetry: false,
        logTrace: verifyTrace,
        boundOpenGeneration: boundOpenGeneration,
      );
    }

    final rawConversationKey =
        ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (rawConversationKey == null || rawConversationKey.isEmpty) {
      return startVerify();
    }
    final conversationKey = _normalizeConversationKey(rawConversationKey);
    final identity = SessionIdentityService.instance.capture();
    final h0 = _h0InFlight[_h0FlightKey(
      ChatViewportRepairTicket(
        ownerUserId: identity.ownerUserId,
        accountGeneration: identity.generation,
        conversationKey: conversationKey,
        openGeneration: 0,
      ),
    )];
    if (h0 == null) {
      return startVerify();
    }
    return h0.then((_) => startVerify());
  }

  Future<ConversationHistorySyncOutcome> _verifyAfterFirstFrame({
    required V2TimConversation conversation,
    required String reason,
    required Duration delay,
    required bool fromRetry,
    ChatOpenTraceContext? logTrace,
    int? boundOpenGeneration,
  }) {
    final rawConversationKey =
        ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (rawConversationKey == null || rawConversationKey.isEmpty) {
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    final conversationKey = _normalizeConversationKey(rawConversationKey);
    if (conversationKey.isEmpty) {
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    if (_latestWindowResetOwnsConversation(rawConversationKey)) {
      // After a real reconnect the reset service owns the first cloud read.
      // Do not start (or timer-retry) an ordinary verify pass beside it.
      ChatHistoryTrace.log(
        'verify_skip_latest_window_reset_owner',
        conversationID: rawConversationKey,
        extras: <String, Object?>{'reason': reason},
      );
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    final verifyTrace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    final identity = SessionIdentityService.instance.capture();
    final key =
        '${identity.ownerUserId}@${identity.generation}|$conversationKey';
    // An explicit entry makes this conversation active again even while the
    // previous route's delayed native task is still shared. Otherwise that
    // task observes its old cancellation and the new page inherits `stale`
    // without ever reading a first window. Timer retries cannot revive a
    // cancelled route; account/session identity remains part of the key.
    if (!fromRetry) _cancelledConversations.remove(conversationKey);
    final existing = _inFlight[key];
    if (existing != null) {
      if (boundOpenGeneration == null) return existing;
      final lifecycle = _lifecycleGeneration;
      // Join native work, but do not inherit an abandoned page's stale result.
      // The original task removes itself before this continuation runs.
      return existing.then((outcome) {
        if (outcome != ConversationHistorySyncOutcome.stale ||
            !_isCurrent(identity, lifecycle) ||
            _isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return outcome;
        }
        return _verifyAfterFirstFrame(
          conversation: conversation,
          reason: reason,
          delay: Duration.zero,
          fromRetry: fromRetry,
          logTrace: verifyTrace,
          boundOpenGeneration: boundOpenGeneration,
        );
      });
    }
    if (!fromRetry &&
        (reason.contains('reconnect') || reason.contains('resume'))) {
      ChatHistoryPeekBootstrap.invalidateCloudRetry(conversation);
    }
    if (ChatHistoryPeekBootstrap.isCloudRetryDeferred(
        conversation, serviceLocator<TUIChatGlobalModel>())) {
      // Leave the existing bounded retry timer intact on repeated route opens.
      _cancelledConversations.remove(conversationKey);
      _enqueueRetry(
          key: key,
          conversation: conversation,
          reason: reason,
          identity: identity,
          lifecycle: _lifecycleGeneration,
          logTrace: verifyTrace);
      return Future.value(ConversationHistorySyncOutcome.retryable);
    }
    // A cancelled route may be opened again after its old Future settled.
    _cancelledConversations.remove(conversationKey);

    // An explicit open/reconnect request supersedes a delayed retry for the
    // same account and conversation.
    _retryTimers.remove(key)?.cancel();
    _retryQueue.remove(key);
    if (!fromRetry) {
      _retryAttempts.remove(key);
    }

    final lifecycle = _lifecycleGeneration;
    late final Future<ConversationHistorySyncOutcome> task;
    task = _runVerification(
      conversation: conversation,
      conversationKey: conversationKey,
      identity: identity,
      lifecycle: lifecycle,
      reason: reason,
      delay: delay,
      logTrace: verifyTrace,
      boundOpenGeneration: boundOpenGeneration,
    ).then((outcome) {
      if (outcome == ConversationHistorySyncOutcome.retryable ||
          outcome == ConversationHistorySyncOutcome.offline) {
        _enqueueRetry(
          key: key,
          conversation: conversation,
          reason: reason,
          identity: identity,
          lifecycle: lifecycle,
          logTrace: verifyTrace,
        );
      } else {
        _retryAttempts.remove(key);
      }
      return outcome;
    }).whenComplete(() {
      if (identical(_inFlight[key], task)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = task;
    return task;
  }

  Future<ConversationHistorySyncOutcome> reconcileConversation({
    required String conversationID,
    V2TimConversation? conversation,
    String reason = 'reconnect',
  }) async {
    final key = conversationID.trim();
    if (key.isEmpty) {
      return ConversationHistorySyncOutcome.retryable;
    }
    final identity = SessionIdentityService.instance.capture();
    final lifecycle = _lifecycleGeneration;
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final resetKey = conversation == null
        ? key
        : (ConversationPreviewHistorySync.conversationMessageCacheKey(
              conversation,
            ) ??
            key);
    if (_latestWindowResetOwnsConversation(resetKey)) {
      // The anchor-based cloud catch-up would page forward from a stale
      // anchor. The latest-window reset replaces it for this conversation.
      ChatHistoryTrace.log(
        'reconcile_skip_latest_window_reset_owner',
        conversationID: key,
        extras: <String, Object?>{'reason': reason},
      );
      return ConversationHistorySyncOutcome.retryable;
    }
    // A completely empty in-memory window is not proof that the cloud range
    // is complete. The low-level catch-up intentionally treats an empty
    // memory list as a no-op, so use the conversation-aware bootstrap here to
    // perform the first cloud-backed page and establish coverage.
    if (conversation != null &&
        (globalModel.rawMessageList(key)?.isEmpty ?? true)) {
      return verifyAfterFirstFrame(
        conversation: conversation,
        reason: reason,
        delay: Duration.zero,
      );
    }
    final result = await globalModel.reconcileConversationCloud(
      key,
      reason: reason,
    );
    if (!_isCurrent(identity, lifecycle)) {
      return ConversationHistorySyncOutcome.stale;
    }
    final coverage = await globalModel.ensureMessageHistoryCoverageLoaded(key);
    if (coverage.status == MessageHistoryCoverageStatus.verified &&
        !coverage.hasOpenHoles) {
      return ConversationHistorySyncOutcome.verified;
    }
    // `settled` means the bounded pass stopped safely. It is not proof that
    // the cloud range is complete, so keep mayHaveOlder armed and let the
    // caller/lifecycle retry later.
    final outcome = _outcomeFromCatchUp(result);
    return outcome == ConversationHistorySyncOutcome.verified
        ? ConversationHistorySyncOutcome.retryable
        : outcome;
  }

  bool _latestWindowResetOwnsConversation(String cacheKey) {
    final key = cacheKey.trim();
    if (key.isEmpty) return false;
    final service = ChatLatestWindowResetService.instance;
    return service.needsLatestWindowReset(key) || service.isResetInFlight(key);
  }

  /// Called by logout, account switching, and app teardown.  Native SDK
  /// requests cannot always be cancelled, so this invalidates their commit
  /// authority instead of trying to interrupt them.
  void invalidate() {
    _lifecycleGeneration++;
    ChatHistoryPeekBootstrap.clearSession();
    ChatLatestWindowResetService.instance.clearSession();
    _inFlight.clear();
    _h0InFlight.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryQueue.clear();
    _retryAttempts.clear();
    _userOlderPaginationKeys.clear();
  }

  void _enqueueRetry({
    required String key,
    required V2TimConversation conversation,
    required String reason,
    required SessionIdentity identity,
    required int lifecycle,
    ChatOpenTraceContext? logTrace,
  }) {
    if (!_isCurrent(identity, lifecycle) || _retryTimers.containsKey(key)) {
      return;
    }
    final retryNumber = (_retryAttempts[key] ?? 0) + 1;
    if (retryNumber > _queueRetryDelays.length) {
      _retryQueue.remove(key);
      return;
    }
    _retryAttempts[key] = retryNumber;
    final request = _QueuedHistoryVerification(
      conversation: conversation,
      reason: reason,
      identity: identity,
      lifecycle: lifecycle,
      retryNumber: retryNumber,
      logTrace: logTrace,
    );
    _retryQueue[key] = request;
    _retryTimers[key] = Timer(_queueRetryDelays[retryNumber - 1], () {
      _retryTimers.remove(key);
      final queued = _retryQueue.remove(key);
      if (queued == null || !_isCurrent(queued.identity, queued.lifecycle)) {
        return;
      }
      unawaited(
        _verifyAfterFirstFrame(
          conversation: queued.conversation,
          reason: 'retry_${queued.reason}_${queued.retryNumber}',
          delay: Duration.zero,
          fromRetry: true,
          logTrace: queued.logTrace,
        ),
      );
    });
  }

  Future<ConversationHistorySyncOutcome> _runVerification({
    required V2TimConversation conversation,
    required String conversationKey,
    required SessionIdentity identity,
    required int lifecycle,
    required String reason,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
    int? boundOpenGeneration,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!_isCurrent(identity, lifecycle)) {
      return ConversationHistorySyncOutcome.stale;
    }
    if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
      return ConversationHistorySyncOutcome.stale;
    }

    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // F-fix：warm scheduler 已经标 mayHaveOlder=false（SDK isFinished=true），
    // 且内存里已有数据 → 直接认为已验证，不再重试以免触发 build 风暴。
    if (!globalModel.mayHaveOlderHistory(conversationKey) &&
        globalModel.rawMessageCount(conversationKey) > 0 &&
        !ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
          preview: conversation.lastMessage,
          cached: globalModel.rawMessageList(conversationKey) ?? const [],
        )) {
      ChatHistoryTrace.log(
        'verify_after_first_frame_short_circuit_exhausted',
        conversationID: conversationKey,
        extras: <String, Object?>{
          'reason': reason,
          'rawCount': globalModel.rawMessageCount(conversationKey),
        },
      );
      return ConversationHistorySyncOutcome.verified;
    }
    var lastOutcome = ConversationHistorySyncOutcome.retryable;
    for (var index = 0; index < _retryDelays.length; index++) {
      if (index > 0 && _retryDelays[index] > Duration.zero) {
        await Future<void>.delayed(_retryDelays[index]);
      }
      if (!_isCurrent(identity, lifecycle)) {
        return ConversationHistorySyncOutcome.stale;
      }

      if (!await _waitForUserOlderPagination(conversationKey)) {
        return ConversationHistorySyncOutcome.retryable;
      }

      try {
        if (_cancelledConversations
            .contains(_normalizeConversationKey(conversationKey))) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return ConversationHistorySyncOutcome.stale;
        }
        final applied = await ChatHistoryPeekBootstrap.apply(
          conversation: conversation,
          globalModel: globalModel,
          retryDelays: const <Duration>[Duration.zero],
          allowCloudVerification: true,
          logTrace: logTrace,
          boundOpenGeneration: boundOpenGeneration,
        ).timeout(_sdkHistoryTimeout);
        if (!_isCurrent(identity, lifecycle)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (!applied &&
            ChatHistoryPeekBootstrap.isCloudRetryDeferred(
                conversation, globalModel)) {
          return ConversationHistorySyncOutcome.retryable;
        }
        if (!applied) {
          lastOutcome = ConversationHistorySyncOutcome.retryable;
          continue;
        }

        final coverage = await globalModel.ensureMessageHistoryCoverageLoaded(
          conversationKey,
        );
        if (!_isCurrent(identity, lifecycle)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (coverage.status == MessageHistoryCoverageStatus.verified &&
            !coverage.hasOpenHoles) {
          return ConversationHistorySyncOutcome.verified;
        }

        // The latest-window verification and targeted gap repair share the
        // same writer.  Do not fetch a second full history window.
        if (coverage.hasOpenHoles ||
            coverage.status == MessageHistoryCoverageStatus.partial ||
            coverage.status == MessageHistoryCoverageStatus.offlineLocalOnly) {
          final catchUp = await globalModel
              .reconcileConversationCloud(
                conversationKey,
                reason: 'gap_repair_$reason',
              )
              .timeout(_sdkHistoryTimeout);
          lastOutcome = _outcomeFromCatchUp(catchUp);
          if (lastOutcome == ConversationHistorySyncOutcome.verified) {
            return lastOutcome;
          }
        } else {
          lastOutcome = ConversationHistorySyncOutcome.retryable;
        }
      } catch (_) {
        lastOutcome = ConversationHistorySyncOutcome.retryable;
      }
    }
    return lastOutcome;
  }

  bool _isBoundOpenAbandoned(String conversationKey, int? boundOpenGeneration) {
    if (boundOpenGeneration == null) {
      return false;
    }
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      conversationKey,
      boundOpenGeneration,
    )) {
      return true;
    }
    final attachedKey = collection.conversationKey;
    if (attachedKey != null &&
        attachedKey.isNotEmpty &&
        attachedKey != conversationKey) {
      return collection.isOpenGenerationAbandoned(
        attachedKey,
        boundOpenGeneration,
      );
    }
    return false;
  }

  bool _isCurrent(SessionIdentity identity, int lifecycle) {
    return lifecycle == _lifecycleGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  ConversationHistorySyncOutcome _outcomeFromCatchUp(
    MessageCloudCatchUpResult result,
  ) {
    switch (result.disposition) {
      case MessageCloudCatchUpDisposition.complete:
        return ConversationHistorySyncOutcome.verified;
      case MessageCloudCatchUpDisposition.settled:
        return ConversationHistorySyncOutcome.retryable;
      case MessageCloudCatchUpDisposition.offline:
        return ConversationHistorySyncOutcome.offline;
      case MessageCloudCatchUpDisposition.retry:
      case MessageCloudCatchUpDisposition.continuation:
      case MessageCloudCatchUpDisposition.stalled:
        return ConversationHistorySyncOutcome.retryable;
    }
  }
}

~~~

6. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat_page/chat_post_open_scheduler.dart:1>)，原文件 lib/src/chat_page/chat_post_open_scheduler.dart，1–168 行。

~~~dart
import 'dart:async';

import '../services/chat_thermal_perf.dart';

typedef ChatPostOpenCanRun = bool Function();
typedef ChatPostOpenTask = FutureOr<void> Function();

enum ChatActivityState { active, interacting, covered, background, disposed }

enum ChatTaskPriority { essential, background }

class _ScheduledChatOpenTask {
  const _ScheduledChatOpenTask({
    required this.generation,
    required this.key,
    required this.canRun,
    required this.task,
    required this.timeout,
    required this.priority,
  });

  final int generation;
  final String key;
  final ChatPostOpenCanRun canRun;
  final ChatPostOpenTask task;
  final Duration timeout;
  final ChatTaskPriority priority;
}

/// Owns delayed post-open chat work so first-frame scheduling is visible in one
/// place instead of being scattered across `Future.delayed` calls.
class ChatPostOpenScheduler {
  static const Duration routeFallbackDelay = Duration(milliseconds: 1000);
  static const Duration p1Delay = Duration(milliseconds: 80);
  static const Duration p2Delay = Duration(milliseconds: 220);
  static const Duration idleDelay = Duration(milliseconds: 380);
  static const Duration muteNetworkDelay = Duration(milliseconds: 450);
  static const Duration defaultTaskTimeout = Duration(seconds: 8);

  ChatPostOpenScheduler({this.maxConcurrent = 2}) : assert(maxConcurrent > 0);

  final int maxConcurrent;

  final Set<Timer> _timers = <Timer>{};
  final List<_ScheduledChatOpenTask> _ready = <_ScheduledChatOpenTask>[];
  final Set<String> _taskKeys = <String>{};
  int _generation = 0;
  // A new route generation cannot cancel work already running in the SDK.
  int _running = 0;
  ChatActivityState _activity = ChatActivityState.active;

  ChatActivityState get activity => _activity;

  void setActivity(ChatActivityState state) {
    if (_activity == state || _activity == ChatActivityState.disposed) return;
    _activity = state;
    if (state == ChatActivityState.disposed) {
      ChatThermalPerf.increment('activity_disposed');
      cancelPending();
    } else {
      ChatThermalPerf.increment('activity_transition');
      _drain();
    }
  }

  int beginRun() {
    _cancelTimers();
    _generation++;
    return _generation;
  }

  void schedule({
    required int generation,
    required Duration delay,
    required ChatPostOpenCanRun canRun,
    required ChatPostOpenTask task,
    String key = '',
    Duration timeout = defaultTaskTimeout,
    ChatTaskPriority priority = ChatTaskPriority.essential,
  }) {
    if (_activity == ChatActivityState.disposed || generation != _generation) {
      return;
    }
    final normalizedKey = key.trim();
    final taskKey = normalizedKey.isEmpty ? '' : '$generation:$normalizedKey';
    if (taskKey.isNotEmpty && !_taskKeys.add(taskKey)) {
      ChatThermalPerf.increment('task_duplicate_suppressed');
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (generation != _generation || !canRun()) {
        ChatThermalPerf.increment('task_cancelled_before_ready');
        _taskKeys.remove(taskKey);
        return;
      }
      _ready.add(_ScheduledChatOpenTask(
        generation: generation,
        key: taskKey,
        canRun: canRun,
        task: task,
        timeout: timeout,
        priority: priority,
      ));
      _drain();
    });
    _timers.add(timer);
  }

  void cancelPending() {
    _cancelTimers();
    _generation++;
  }

  void dispose() {
    setActivity(ChatActivityState.disposed);
  }

  void _cancelTimers() {
    for (final timer in _timers.toList(growable: false)) {
      timer.cancel();
    }
    _timers.clear();
    _ready.clear();
    _taskKeys.clear();
  }

  void _drain() {
    while (_running < maxConcurrent && _ready.isNotEmpty) {
      final index = _ready.indexWhere((task) => _allows(task.priority));
      if (index < 0) {
        ChatThermalPerf.increment('task_held_by_activity');
        return;
      }
      final pending = _ready.removeAt(index);
      if (pending.generation != _generation || !pending.canRun()) {
        ChatThermalPerf.increment('task_dropped_before_start');
        _taskKeys.remove(pending.key);
        continue;
      }
      _running++;
      ChatThermalPerf.increment('task_started');
      // Timeout is diagnostic: Future.timeout does not cancel the actual task.
      final watchdog = Timer(pending.timeout, () {
        ChatThermalPerf.increment('task_timeout');
      });
      Future<void>.sync(pending.task)
          .catchError((Object _) {})
          .whenComplete(() {
        watchdog.cancel();
        _running--;
        _taskKeys.remove(pending.key);
        ChatThermalPerf.increment('task_completed');
        _drain();
      });
    }
  }

  bool _allows(ChatTaskPriority priority) {
    if (priority == ChatTaskPriority.essential) {
      return _activity != ChatActivityState.disposed;
    }
    return _activity == ChatActivityState.active ||
        _activity == ChatActivityState.interacting;
  }
}

~~~

7. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat_page/chat_open_lifecycle.dart:1>)，原文件 lib/src/chat_page/chat_open_lifecycle.dart，1–117 行。

~~~dart
import 'chat_mute_refresh_queue.dart';

enum ChatOpenPhase {
  created,
  historyReady,
  interactive,
  enriched,
  disposed,
}

/// One-shot / gate flags for opening a chat conversation page.
class ChatOpenLifecycle {
  ChatOpenPhase phase = ChatOpenPhase.created;
  int conversationGeneration = 0;
  bool postOpenTasksScheduled = false;
  final muteRefreshQueue = ChatMuteRefreshQueue();
  bool scheduledVisibleSdkUnreadClean = false;
  bool clearedExternalEntryOnDeactivate = false;
  Future<void>? openHistoryGate;
  // The layout gate may soft-timeout while history preparation continues.
  Future<void>? openHistoryPreparationGate;
  String openHistoryGateConvKey = '';
  int postOpenTasksGeneration = 0;

  /// 递增后丢弃已 schedule 的禁言网络补证（退页 / 重进）。
  int muteFetchGeneration = 0;

  int beginConversation() {
    cancelPendingMuteFetch();
    cancelPendingPostOpenTasks();
    phase = ChatOpenPhase.created;
    openHistoryGate = null;
    openHistoryPreparationGate = null;
    openHistoryGateConvKey = '';
    return ++conversationGeneration;
  }

  bool markHistoryReady(int generation) =>
      _advance(generation, ChatOpenPhase.created, ChatOpenPhase.historyReady);

  bool markInteractive(int generation) => _advance(
        generation,
        ChatOpenPhase.historyReady,
        ChatOpenPhase.interactive,
      );

  bool markEnriched(int generation) =>
      _advance(generation, ChatOpenPhase.interactive, ChatOpenPhase.enriched);

  bool _advance(
    int generation,
    ChatOpenPhase expected,
    ChatOpenPhase next,
  ) {
    if (generation != conversationGeneration || phase != expected) {
      return false;
    }
    phase = next;
    return true;
  }

  void cancelPendingMuteFetch() {
    muteFetchGeneration++;
    muteRefreshQueue.cancel();
  }

  int beginPostOpenTasks() {
    postOpenTasksScheduled = true;
    return ++postOpenTasksGeneration;
  }

  Future<void> waitForOpenHistoryGate() async {
    final gate = openHistoryGate;
    if (gate == null) {
      return;
    }
    try {
      await gate;
    } catch (_) {
      // Post-open tasks must still run when history preparation fails.
    }
  }

  Future<void> waitForOpenHistoryPreparationGate() async {
    final gates = <Future<void>>[
      if (openHistoryGate != null) openHistoryGate!,
      if (openHistoryPreparationGate != null) openHistoryPreparationGate!,
    ];
    await Future.wait(
      gates.map((gate) async {
        try {
          await gate;
        } catch (_) {
          // Post-open tasks must still run when either gate fails.
        }
      }),
    );
  }

  void cancelPendingPostOpenTasks() {
    postOpenTasksGeneration++;
    postOpenTasksScheduled = false;
  }

  void resetForDispose() {
    cancelPendingMuteFetch();
    cancelPendingPostOpenTasks();
    scheduledVisibleSdkUnreadClean = false;
    clearedExternalEntryOnDeactivate = false;
    openHistoryGate = null;
    openHistoryPreparationGate = null;
    openHistoryGateConvKey = '';
    conversationGeneration++;
    phase = ChatOpenPhase.disposed;
  }
}

~~~

8. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_viewport/chat_viewport_models.dart:1>)，原文件 lib/src/services/chat_viewport/chat_viewport_models.dart，1–131 行。

~~~dart
import 'package:flutter/foundation.dart';

/// 当前可展示视口的覆盖状态。只描述**最新锚点附近**，不是整段会话历史。
enum ChatViewportCoverageState {
  /// 最新连续窗口足够铺满首屏。
  readyLocal,

  /// 有连续消息，但估算高度不足一屏。
  partialLocal,

  /// 最新窗口附近存在 gap。更老位置的洞不算。
  gapLocal,

  /// 本地当前没有可展示消息。不等于确定无历史。
  emptyLocal,

  /// 云端已证明该会话没有历史。
  emptyVerified,

  /// 最新窗口已和云校正（H2 之后）。
  verified,
}

enum ChatViewportSource {
  cache,
  memory,
  local,
  cloudMerged,
}

enum ChatViewportRepairKind {
  none,
  openViewport,
  freshnessVerify,
}

@immutable
class ChatViewportAnchor {
  const ChatViewportAnchor({
    this.msgID,
    this.seq,
    this.timestamp,
  });

  final String? msgID;
  final int? seq;
  final int? timestamp;

  bool get isResolved =>
      (msgID != null && msgID!.isNotEmpty) || (seq != null && seq! > 0);
}

/// 开页准备结果：投影描述，不是第二份消息实体仓库。
@immutable
class ChatOpenViewportResult {
  const ChatOpenViewportResult({
    required this.conversationKey,
    required this.mountedMessageIds,
    required this.anchor,
    required this.estimatedContentExtent,
    required this.viewportTargetExtent,
    required this.coverageState,
    required this.isContiguous,
    required this.needsLatestRepair,
    required this.reachedKnownLocalBoundary,
    required this.source,
    required this.continuousCount,
    this.gapBeforeSeq,
    this.isHugeGap = false,
    this.emptyVerified = false,
    this.openGeneration = 0,
  });

  final String conversationKey;
  final List<String> mountedMessageIds;
  final ChatViewportAnchor? anchor;
  final double estimatedContentExtent;
  final double viewportTargetExtent;
  final ChatViewportCoverageState coverageState;
  final bool isContiguous;
  final bool needsLatestRepair;
  final bool reachedKnownLocalBoundary;
  final ChatViewportSource source;
  final int continuousCount;
  final int? gapBeforeSeq;
  final bool isHugeGap;
  final bool emptyVerified;
  final int openGeneration;

  /// 首屏可转场：连续，且高度够一屏，或已到达已知边界（含 EMPTY_VERIFIED）。
  bool get isViewportReady {
    if (!isContiguous) {
      return false;
    }
    if (coverageState == ChatViewportCoverageState.emptyLocal) {
      return false;
    }
    if (coverageState == ChatViewportCoverageState.emptyVerified) {
      return true;
    }
    return estimatedContentExtent >= viewportTargetExtent ||
        reachedKnownLocalBoundary;
  }

  bool get isEmptyLocal =>
      coverageState == ChatViewportCoverageState.emptyLocal;
}

/// H0 请求票：返回时校验账号 / 会话 / 开页代 / 请求锚点。
@immutable
class ChatViewportRepairTicket {
  const ChatViewportRepairTicket({
    required this.ownerUserId,
    required this.accountGeneration,
    required this.conversationKey,
    required this.openGeneration,
    this.requestAnchorMsgId,
    this.requestAnchorSeq,
  });

  final String ownerUserId;
  final int accountGeneration;
  final String conversationKey;
  final int openGeneration;
  final String? requestAnchorMsgId;
  final int? requestAnchorSeq;

  String get flightKey =>
      '$ownerUserId@$accountGeneration|$conversationKey|latest';
}

~~~

9. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_viewport/chat_viewport_collection.dart:1>)，原文件 lib/src/services/chat_viewport/chat_viewport_collection.dart，1–245 行。

~~~dart
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';

/// 当前聊天视口协调层：只持有投影与 merge 状态，不存第四份消息实体。
///
/// 消息体仍来自 [TUIChatGlobalModel.messageListMap] / HistoryWindowStore。
class ChatViewportCollection {
  ChatViewportCollection._();

  static final ChatViewportCollection instance = ChatViewportCollection._();

  String? _conversationKey;
  int _openGeneration = 0;
  SessionIdentity? _identity;
  ChatOpenViewportResult? _state;
  ChatOpenViewportResult? _initialState;
  ChatViewportRepairKind _repair = ChatViewportRepairKind.none;
  bool _uiAttached = false;
  final Set<String> _abandonedOpenGenerations = <String>{};

  String? get conversationKey => _conversationKey;
  int get openGeneration => _openGeneration;
  ChatOpenViewportResult? get state => _state;
  ChatOpenViewportResult? get initialState => _initialState;
  ChatViewportRepairKind get repair => _repair;
  bool get uiAttached => _uiAttached;

  int openGenerationFor(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_conversationKey ?? '')) {
      return 0;
    }
    return _openGeneration;
  }

  static String _abandonedKey(String conversationKey, int openGeneration) {
    return '$conversationKey#$openGeneration';
  }

  /// 该次 open generation 是否已因 detach 作废。未 attach / 未 detach 的 generation 不是 abandoned。
  bool isOpenGenerationAbandoned(
    String conversationKey,
    int openGeneration,
  ) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return false;
    }
    return _abandonedOpenGenerations.contains(
      _abandonedKey(key, openGeneration),
    );
  }

  void attach({
    required String conversationKey,
    required SessionIdentity identity,
    String attachSource = '',
  }) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return;
    }
    if (key == _conversationKey &&
        _identity == identity &&
        _uiAttached) {
      ChatOpenPerfLog.mark(
        'viewport_attach_skip',
        conversationID: key,
        extras: <String, Object?>{
          'openGeneration': _openGeneration,
          'attachSource': attachSource,
        },
      );
      return;
    }
    final previousGeneration = _openGeneration;
    _conversationKey = key;
    _identity = identity;
    _openGeneration += 1;
    _uiAttached = true;
    _repair = ChatViewportRepairKind.none;
    _initialState = null;
    ChatOpenPerfLog.mark(
      'viewport_attach_bump',
      conversationID: key,
      extras: <String, Object?>{
        'previousGeneration': previousGeneration,
        'openGeneration': _openGeneration,
        'attachSource': attachSource,
      },
    );
  }

  /// 取消页面等待，并作废该 openGeneration 的后续写窗。
  /// 已发出的 SDK 请求无法取消，但回调不得再提交到该 generation。
  void detachUi({required String conversationKey, required int openGeneration}) {
    final key = conversationKey.trim();
    if (key.isEmpty ||
        key != (_conversationKey ?? '') ||
        openGeneration != _openGeneration) {
      return;
    }
    _abandonedOpenGenerations.add(_abandonedKey(key, openGeneration));
    _uiAttached = false;
    _repair = ChatViewportRepairKind.none;
  }

  void resetForTest() {
    _conversationKey = null;
    _openGeneration = 0;
    _identity = null;
    _state = null;
    _initialState = null;
    _repair = ChatViewportRepairKind.none;
    _uiAttached = false;
    _abandonedOpenGenerations.clear();
  }

  /// 锁定本轮开页第一帧 snapshot。后续 H0/H2 只升级 [_state]，不改第一帧。
  void lockInitial(ChatOpenViewportResult result) {
    if (result.conversationKey != (_conversationKey ?? '')) {
      return;
    }
    _state = result;
    _initialState ??= result;
  }

  /// 当前消息窗是否已经包含第一帧 snapshot，而不是 lastMessage 半成品。
  bool matchesInitialWindow(List<V2TimMessage> newestFirst) {
    final initial = _initialState;
    if (initial == null || initial.conversationKey != (_conversationKey ?? '')) {
      return false;
    }
    if (initial.mountedMessageIds.isEmpty) {
      return true;
    }
    if (newestFirst.length < initial.continuousCount) {
      return false;
    }
    final ids = <String>{
      for (final message in newestFirst)
        ChatViewportReadiness.messageId(message),
    }..removeWhere((id) => id.isEmpty);
    for (final id in initial.mountedMessageIds) {
      if (id.isEmpty || !ids.contains(id)) {
        return false;
      }
    }
    return true;
  }

  bool acceptsTicket(ChatViewportRepairTicket ticket) {
    if (_identity == null) {
      return false;
    }
    return ticket.ownerUserId == _identity!.ownerUserId &&
        ticket.accountGeneration == _identity!.generation &&
        ticket.conversationKey == (_conversationKey ?? '') &&
        ticket.openGeneration == _openGeneration &&
        _uiAttached;
  }

  String ticketRejectedReason(ChatViewportRepairTicket ticket) {
    if (_identity == null) {
      return 'identityNull';
    }
    if (ticket.ownerUserId != _identity!.ownerUserId ||
        ticket.accountGeneration != _identity!.generation) {
      return 'accountMismatch';
    }
    if (ticket.conversationKey != (_conversationKey ?? '')) {
      return 'conversationMismatch';
    }
    if (ticket.openGeneration != _openGeneration) {
      return 'generationMismatch';
    }
    if (!_uiAttached) {
      return 'uiDetached';
    }
    return 'generationMismatch';
  }

  bool sameConversationCache(ChatViewportRepairTicket ticket) {
    return ticket.conversationKey == (_conversationKey ?? '') &&
        ticket.ownerUserId == (_identity?.ownerUserId ?? '') &&
        ticket.accountGeneration == (_identity?.generation ?? -1);
  }

  void markRepair(ChatViewportRepairKind kind) {
    _repair = kind;
  }

  ChatOpenViewportResult project({
    required String conversationKey,
    required List<V2TimMessage> newestFirst,
    required bool useSeqContiguity,
    required double viewportHeight,
    required ChatViewportSource source,
    MessageHistoryCoverage? coverage,
    bool reachedKnownLocalBoundary = false,
  }) {
    final result = ChatViewportReadiness.classify(
      conversationKey: conversationKey,
      newestFirst: newestFirst,
      useSeqContiguity: useSeqContiguity,
      viewportHeight: viewportHeight,
      source: source,
      coverage: coverage,
      reachedKnownLocalBoundary: reachedKnownLocalBoundary,
      openGeneration: conversationKey == _conversationKey ? _openGeneration : 0,
    );
    if (conversationKey == _conversationKey) {
      _state = result;
    }
    return result;
  }

  /// 所有输入都 merge。当前视口已比 incoming 新时只合并、不替换。
  List<V2TimMessage> mergeIncoming({
    required List<V2TimMessage> current,
    required List<V2TimMessage> incoming,
    required bool useSeqContiguity,
  }) {
    if (ChatViewportReadiness.incomingIsStaleAgainstCurrent(
      current: current,
      incoming: incoming,
      useSeqContiguity: useSeqContiguity,
    )) {
      return ChatViewportReadiness.mergePreserveRealtime(
        current: current,
        incoming: incoming,
      );
    }
    return ChatViewportReadiness.mergePreserveRealtime(
      current: current,
      incoming: incoming,
    );
  }
}

~~~

10. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_viewport/open_viewport_cache.dart:1>)，原文件 lib/src/services/chat_viewport/open_viewport_cache.dart，1–207 行。

~~~dart
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// 消息 Tab 可见会话的轻量首屏缓存。只读 Memory / 本地库，不碰云、不修洞。
class OpenViewportCache {
  OpenViewportCache._();

  static final OpenViewportCache instance = OpenViewportCache._();

  static const int maxVisible = 8;
  static const int minVisible = 5;
  static const int maxMessagesPerConversation = 30;

  final LinkedHashMap<String, ChatOpenViewportResult> _entries =
      LinkedHashMap<String, ChatOpenViewportResult>();

  /// Recovery epoch each entry was prepared under. An entry from an earlier
  /// epoch predates a real reconnect and can no longer skip a latest-window
  /// repair.
  final Map<String, int> _epochByKey = <String, int>{};
  bool _paused = false;
  int _generation = 0;

  /// Tests inject the recovery epoch; production reads the connect service.
  @visibleForTesting
  static int Function()? debugRecoveryEpochProvider;

  static int get _currentEpoch =>
      (debugRecoveryEpochProvider ?? (() => ImConnectStatusService.recoveryEpoch))();

  ChatOpenViewportResult? peek(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return null;
    }
    final hit = _entries.remove(key);
    if (hit == null) {
      _epochByKey.remove(key);
      return null;
    }
    final epoch = _epochByKey[key];
    final currentEpoch = _currentEpoch;
    if (epoch != null && epoch != currentEpoch) {
      _epochByKey.remove(key);
      ChatOpenPerfLog.mark(
        'open_viewport_cache_stale_epoch',
        conversationID: key,
        extras: <String, Object?>{
          'entryEpoch': epoch,
          'currentEpoch': currentEpoch,
        },
      );
      return null;
    }
    _entries[key] = hit;
    return hit;
  }

  void put(String conversationKey, ChatOpenViewportResult result) {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return;
    }
    _entries.remove(key);
    _entries[key] = result;
    _epochByKey[key] = _currentEpoch;
    while (_entries.length > maxVisible) {
      final evicted = _entries.keys.first;
      _entries.remove(evicted);
      _epochByKey.remove(evicted);
    }
  }

  void invalidate(String conversationKey) {
    final key = conversationKey.trim();
    _entries.remove(key);
    _epochByKey.remove(key);
  }

  void pause({String reason = 'feed_scroll'}) {
    _paused = true;
    _generation++;
  }

  void resume() {
    _paused = false;
    _generation++;
  }

  void resetForTest() {
    _entries.clear();
    _epochByKey.clear();
    _paused = false;
    _generation = 0;
  }

  bool get isPaused => _paused;

  /// 停稳后准备当前可见 5～8 个会话。禁止拉云、改 coverage、下载媒体。
  Future<void> prepareVisible({
    required List<V2TimConversation> visible,
    double viewportHeight = 560,
    String reason = 'home_idle',
  }) async {
    if (_paused || visible.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final candidates = visible.take(maxVisible).toList(growable: false);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    for (final conversation in candidates) {
      if (_paused || generation != _generation) {
        return;
      }
      final key =
          ConversationPreviewHistorySync.conversationMessageCacheKey(
                conversation,
              ) ??
              conversation.conversationID.trim();
      if (key.isEmpty) {
        continue;
      }
      // A conversation awaiting a latest-window reset must not receive a
      // pre-reconnect local page into memory; that page is the stale window
      // the reset exists to replace.
      if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key)) {
        invalidate(key);
        continue;
      }
      final cached = peek(key);
      if (cached != null && cached.isViewportReady) {
        continue;
      }
      final memory = List<V2TimMessage>.from(
        globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
      );
      var source = ChatViewportSource.memory;
      var messages = memory;
      if (messages.isEmpty && ConversationPeekService.canPeek(conversation)) {
        final local = await ConversationPeekService.loadLocalForChatEntry(
          conversation,
        );
        if (_paused || generation != _generation) {
          return;
        }
        final isGroupPeek = conversation.type == 2 ||
            (conversation.groupID?.trim().isNotEmpty ?? false);
        messages = ChatViewportReadiness.takeNewestContiguous(
          newestFirst: local.messages
              .take(maxMessagesPerConversation)
              .toList(growable: false),
          useSeqContiguity: isGroupPeek,
        );
        source = ChatViewportSource.local;
        if (messages.isNotEmpty &&
            (globalModel.rawMessageList(key)?.isEmpty ?? true)) {
          globalModel.setMessageList(
            key,
            ChatViewportCollection.instance.mergeIncoming(
              current: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
              incoming: messages,
              useSeqContiguity: isGroupPeek,
            ),
            historyCommitSource: 'open_viewport_cache_local',
          );
        }
      }
      final isGroup = conversation.type == 2 ||
          (conversation.groupID?.trim().isNotEmpty ?? false);
      final result = ChatViewportCollection.instance.project(
        conversationKey: key,
        newestFirst: messages,
        useSeqContiguity: isGroup,
        viewportHeight: viewportHeight,
        source: source,
      );
      put(key, result);
      ChatOpenPerfLog.mark(
        'open_viewport_cache_prepared',
        conversationID: key,
        extras: <String, Object?>{
          'reason': reason,
          'source': source.name,
          'count': result.continuousCount,
          'ready': result.isViewportReady,
        },
      );
    }
  }
}

~~~

11. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_open_perf_log.dart:1>)，原文件 lib/src/services/chat_open_perf_log.dart，1–928 行。

~~~dart
import 'dart:async';

import 'package:flutter/foundation.dart';

/// 发布版可见：进入聊天页耗时追踪。过滤关键字：`[ChatOpenPerf]`
///
/// 用法：Xcode / `flutter logs` / Android logcat 搜 `ChatOpenPerf`。
/// 每条含 `elapsedMs`（距点击）与 `deltaMs`（距上一里程碑），以及 `region` 中文阶段名。
/// Debug 和 Profile 默认输出，Release 永不输出。
class ChatOpenPerfLog {
  ChatOpenPerfLog._();

  /// Debug 构建仍采集账本，便于测试与必要时重开控制台。
  static const bool enabled = kDebugMode;

  /// Profile 构建关闭控制台；需要真机采样时再改回 true。
  static const bool enabledInProfile = false;

  /// 高频控制台输出开关。关闭后仍写 debugSink / 计数器。
  static const bool consoleOutputEnabled = false;

  static bool get isEnabled =>
      !kReleaseMode && (enabled || (kProfileMode && enabledInProfile));

  /// Tests can capture the exact line without scraping stdout.
  @visibleForTesting
  static void Function(String line)? debugSink;

  @visibleForTesting
  static Duration settleSummaryDelay = const Duration(milliseconds: 2000);

  static const int _maxLedgers = 16;
  static final List<_ChatOpenTraceLedger> _ledgers = <_ChatOpenTraceLedger>[];
  static final _ChatOpenTraceLedger _detached = _ChatOpenTraceLedger(
    sessionId: '-',
    convId: '',
    t0Ms: 0,
  );
  static _ChatOpenTraceLedger? _current;

  static int? _hydrateOwnerRequestId;
  static int lastPrepareRequestId = 0;
  static final List<ChatOpenPrepareWorkSnapshot> _prepareSnaps =
      <ChatOpenPrepareWorkSnapshot>[];

  static int get prepareCount => _current?.prepareCount ?? 0;
  static int get actualHydrateCount => _current?.actualHydrateCount ?? 0;
  static int get hydrateJoinCount => _current?.hydrateJoinCount ?? 0;
  static int get hydrateReuseCount => _current?.hydrateReuseCount ?? 0;
  static int get hydrateStartedCount => _current?.hydrateStartedCount ?? 0;
  static int get hydrateCommitCount => _current?.hydrateCommitCount ?? 0;
  static int get hydrateAbortedCount => _current?.hydrateAbortedCount ?? 0;
  static int get ignoredPrepareCount => _current?.ignoredPrepareCount ?? 0;
  static int get ignoredAfterDbRead => _current?.ignoredAfterDbRead ?? 0;
  static int get ignoredAfterSdkRead => _current?.ignoredAfterSdkRead ?? 0;
  static int get ignoredAfterCommit => _current?.ignoredAfterCommit ?? 0;
  static int get attachCount => _current?.attachCount ?? 0;
  static int get attachBumpCount => _current?.attachBumpCount ?? 0;
  static int get attachSkipCount => _current?.attachSkipCount ?? 0;
  static int get generationRejectCount => _current?.generationRejectCount ?? 0;
  static int get appBootstrapProducerCount =>
      _current?.appBootstrapProducerCount ?? 0;
  static int get reloadIfEmptyCount => _current?.reloadIfEmptyCount ?? 0;
  static int get uikitProducerCount => _current?.uikitProducerCount ?? 0;
  static String get lastIgnoredReason => _current?.lastIgnoredReason ?? '';
  static String get lastRejectReason => _current?.lastRejectReason ?? '';

  static const Set<String> _plaintextKeys = <String>{
    'session',
    'chatopentraceid',
    'requestid',
    'prepareid',
    'opengeneration',
    'ticketgeneration',
    'currentopengeneration',
    'sessiongeneration',
    'accountgeneration',
    'source',
    'reason',
    'outcome',
    'kind',
    'producer',
    'joined',
    'owned',
    'ignoredreason',
    'stalereason',
    'ticketaccepted',
    'ticketrejectedreason',
    'hydratekind',
    'work',
    'dbread',
    'sdkread',
    'committed',
    'hasinflight',
    'waitms',
    'timeoutms',
    'gracems',
    'durationus',
    'durationms',
    'preparecount',
    'actualhydratecount',
    'hydratejoincount',
    'hydratereusecount',
    'hydratestartedcount',
    'hydratecommitcount',
    'hydrateabortedcount',
    'ignoredpreparecount',
    'ignoredafterdbread',
    'ignoredaftersdkread',
    'ignoredaftercommit',
    'attachcount',
    'attachbumpcount',
    'attachskipcount',
    'generationrejectcount',
    'appbootstrapproducercount',
    'reloadifemptycount',
    'uikitproducercount',
    'tabindex',
    'tabname',
    'convtype',
    'scope',
    'caller',
    'action',
    'result',
    'beforefirstframe',
    'localonly',
    'rawcount',
    'localcount',
    'cachedraw',
    'initialloaded',
    'ready',
    'coverage',
    'phase',
    'iscurrent',
    'sameconversationcache',
    'uiattached',
    'previousgeneration',
    'attachsource',
    'gracehit',
    'historyposition',
    'note',
    'region',
    'elapsedms',
    'deltams',
    'prev',
    'totalms',
    'type',
    'entryunread',
    'completewindow',
    'emptyconfirmed',
    'mayhaveolder',
    'continuouscount',
    'extent',
    'target',
    'needslatestrepair',
    'bootstrapping',
    'messagecount',
    'waitedms',
    'applied',
    'coldstart',
    'iscurrenttab',
  };

  static String get sessionId => _current?.sessionId ?? '';

  static String get chatOpenTraceId {
    final id = _current?.sessionId ?? '';
    return id.isEmpty ? '-' : id;
  }

  static ChatOpenTraceContext captureCurrent({
    int? requestId,
    String? conversationKey,
  }) {
    final current = _current;
    if (current == null) {
      return ChatOpenTraceContext(
        session: '-',
        chatOpenTraceId: '-',
        requestId: requestId ?? lastPrepareRequestId,
        conversationKey: (conversationKey ?? '').trim(),
        t0Ms: 0,
      );
    }
    return ChatOpenTraceContext(
      session: current.sessionId,
      chatOpenTraceId: current.sessionId,
      requestId: requestId ?? lastPrepareRequestId,
      conversationKey: (conversationKey ?? current.convId).trim(),
      t0Ms: current.t0Ms,
    );
  }

  /// 点会话 / 即将打开聊天时调用，开启一轮会话时钟。
  static void beginOpen({
    required String conversationID,
    required String phase,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    if (!isEnabled) {
      return;
    }
    final id = conversationID.trim();
    final t0Ms = DateTime.now().millisecondsSinceEpoch;
    final sessionId = 'open_${t0Ms.toRadixString(36)}_${_hashId(id)}';
    final ledger = _ChatOpenTraceLedger(
      sessionId: sessionId,
      convId: id,
      t0Ms: t0Ms,
    );
    _ledgers.add(ledger);
    _pruneLedgers(keep: ledger);
    _current = ledger;
    _scheduleSettleSummary(ledger);
    _print(
      'session_begin',
      conversationID: id,
      extras: <String, Object?>{
        'phase': phase,
        'session': sessionId,
        'chatOpenTraceId': sessionId,
        'region': regionOf('session_begin'),
        'elapsedMs': 0,
        'deltaMs': 0,
        ...extras,
      },
    );
  }

  /// 相对 [beginOpen] 的里程碑（含 elapsedMs + deltaMs）。
  static void mark(
    String event, {
    String? conversationID,
    Map<String, Object?> extras = const <String, Object?>{},
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ??
        captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    _tally(ledger, event, extras);
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = ctx.t0Ms > 0 ? now - ctx.t0Ms : -1;
    final delta = ledger.lastMarkMs > 0 ? now - ledger.lastMarkMs : -1;
    final prev = ledger.lastEvent.isEmpty ? '-' : ledger.lastEvent;
    _print(
      event,
      conversationID: conversationID ?? ctx.conversationKey,
      extras: <String, Object?>{
        'session': ctx.session.isEmpty ? '-' : ctx.session,
        'chatOpenTraceId':
            ctx.chatOpenTraceId.isEmpty ? '-' : ctx.chatOpenTraceId,
        'region': regionOf(event),
        'elapsedMs': elapsed,
        'deltaMs': delta,
        'prev': prev,
        ...extras,
      },
    );
    ledger.lastMarkMs = now;
    ledger.lastEvent = event;
  }

  /// 历史列表 Widget 首次 build（可能仍空壳）。每 session 一次。
  static void markHistoryListBuilt({
    required String conversationID,
    required int messageCount,
    required bool initialLoaded,
    bool bootstrapping = false,
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    if (ledger.historyListBuiltLogged) {
      return;
    }
    ledger.historyListBuiltLogged = true;
    mark(
      'history_list_first_build',
      conversationID: conversationID,
      extras: <String, Object?>{
        'messageCount': messageCount,
        'initialLoaded': initialLoaded,
        'bootstrapping': bootstrapping,
      },
      trace: ctx,
    );
  }

  /// 消息列表首次非空并完成一帧绘制。每 session 一次 —— 这是「消息出现」主指标。
  static void markMessagesFirstVisible({
    required String conversationID,
    required int messageCount,
    String source = 'list',
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    if (ledger.firstMessagesVisibleLogged) {
      return;
    }
    if (messageCount <= 0) {
      return;
    }
    ledger.firstMessagesVisibleLogged = true;
    mark(
      'messages_first_visible',
      conversationID: conversationID,
      extras: <String, Object?>{
        'messageCount': messageCount,
        'source': source,
        'note': '首屏消息对用户可见（post-frame）',
      },
      trace: ctx,
    );
    _printSummary(ledger, ctx);
    emitOpenTraceSummary(phase: 'first_visible', trace: ctx);
  }

  static void emitOpenTraceSummary({
    required String phase,
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent();
    final ledger = _findLedger(ctx.chatOpenTraceId);
    if (ledger == null || ledger.t0Ms <= 0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _print(
      'open_trace_summary',
      conversationID: ctx.conversationKey.isEmpty
          ? ledger.convId
          : ctx.conversationKey,
      extras: <String, Object?>{
        'session': ledger.sessionId,
        'chatOpenTraceId': ledger.sessionId,
        'region': regionOf('open_trace_summary'),
        'phase': phase,
        'elapsedMs': now - ledger.t0Ms,
        'prepareCount': ledger.prepareCount,
        'actualHydrateCount': ledger.actualHydrateCount,
        'hydrateJoinCount': ledger.hydrateJoinCount,
        'hydrateReuseCount': ledger.hydrateReuseCount,
        'hydrateStartedCount': ledger.hydrateStartedCount,
        'hydrateCommitCount': ledger.hydrateCommitCount,
        'hydrateAbortedCount': ledger.hydrateAbortedCount,
        'ignoredPrepareCount': ledger.ignoredPrepareCount,
        'ignoredAfterDbRead': ledger.ignoredAfterDbRead,
        'ignoredAfterSdkRead': ledger.ignoredAfterSdkRead,
        'ignoredAfterCommit': ledger.ignoredAfterCommit,
        'attachCount': ledger.attachCount,
        'attachBumpCount': ledger.attachBumpCount,
        'attachSkipCount': ledger.attachSkipCount,
        'generationRejectCount': ledger.generationRejectCount,
        'appBootstrapProducerCount': ledger.appBootstrapProducerCount,
        'reloadIfEmptyCount': ledger.reloadIfEmptyCount,
        'uikitProducerCount': ledger.uikitProducerCount,
        'lastIgnoredReason': ledger.lastIgnoredReason,
        'lastRejectReason': ledger.lastRejectReason,
        'note': phase == 'settle_2s'
            ? '2s 观察窗，不是打开完成态'
            : '打开链路计数快照',
      },
    );
  }

  static void _printSummary(
    _ChatOpenTraceLedger ledger,
    ChatOpenTraceContext ctx,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _print(
      'open_summary',
      conversationID: ctx.conversationKey.isEmpty
          ? ledger.convId
          : ctx.conversationKey,
      extras: <String, Object?>{
        'session': ledger.sessionId,
        'chatOpenTraceId': ledger.sessionId,
        'region': regionOf('open_summary'),
        'totalMs': now - ledger.t0Ms,
        'lastEvent': ledger.lastEvent.isEmpty ? '-' : ledger.lastEvent,
        'note': '从点击会话到消息首次可见',
      },
    );
  }

  static void _scheduleSettleSummary(_ChatOpenTraceLedger ledger) {
    ledger.settleTimer?.cancel();
    ledger.settleTimer = Timer(settleSummaryDelay, () {
      ledger.settleTimer = null;
      emitOpenTraceSummary(phase: 'settle_2s', trace: ledger.toContext());
    });
  }

  static ChatOpenPrepareWorkSnapshot recordPrepareStart({
    required int requestId,
    required String source,
  }) {
    lastPrepareRequestId = requestId;
    final snap = ChatOpenPrepareWorkSnapshot(
      requestId: requestId,
      source: source,
      trace: captureCurrent(requestId: requestId),
    );
    _prepareSnaps.add(snap);
    while (_prepareSnaps.length > 8) {
      _prepareSnaps.removeAt(0);
    }
    return snap;
  }

  static ChatOpenPrepareWorkSnapshot? snapshotFor(int requestId) {
    for (var i = _prepareSnaps.length - 1; i >= 0; i--) {
      if (_prepareSnaps[i].requestId == requestId) {
        return _prepareSnaps[i];
      }
    }
    return null;
  }

  static int _ownedRequestId(ChatOpenTraceContext? trace, int? fallback) {
    if (trace != null && trace.requestId != 0) {
      return trace.requestId;
    }
    return fallback ?? 0;
  }

  static void markHydrateOwner(int requestId, {ChatOpenTraceContext? trace}) {
    final id = _ownedRequestId(trace, requestId);
    _hydrateOwnerRequestId = id;
    snapshotFor(id)?.owned = true;
  }

  static void markHydrateJoined(int requestId, {ChatOpenTraceContext? trace}) {
    final id = _ownedRequestId(trace, requestId);
    snapshotFor(id)?.joined = true;
  }

  static void markOwnedDbRead({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.dbRead = true;
  }

  static void markOwnedSdkRead({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.sdkRead = true;
  }

  static void markOwnedCommit({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.committed = true;
  }

  static int? get hydrateOwnerRequestId => _hydrateOwnerRequestId;

  static void _tally(
    _ChatOpenTraceLedger ledger,
    String event,
    Map<String, Object?> extras,
  ) {
    switch (event) {
      case 'viewport_prepare_start':
        ledger.prepareCount += 1;
        break;
      case 'app_hydrate_registered':
        ledger.actualHydrateCount += 1;
        break;
      case 'app_hydrate_join':
        ledger.hydrateJoinCount += 1;
        break;
      case 'app_hydrate_reuse':
        ledger.hydrateReuseCount += 1;
        break;
      case 'app_hydrate_started':
        ledger.hydrateStartedCount += 1;
        break;
      case 'app_hydrate_commit':
        ledger.hydrateCommitCount += 1;
        break;
      case 'app_hydrate_aborted':
        ledger.hydrateAbortedCount += 1;
        break;
      case 'viewport_prepare_ignored':
        ledger.ignoredPrepareCount += 1;
        ledger.lastIgnoredReason = '${extras['ignoredReason'] ?? ''}';
        final owned = extras['owned'] == true;
        if (owned && extras['dbRead'] == true) {
          ledger.ignoredAfterDbRead += 1;
        }
        if (owned && extras['sdkRead'] == true) {
          ledger.ignoredAfterSdkRead += 1;
        }
        if (owned && extras['committed'] == true) {
          ledger.ignoredAfterCommit += 1;
        }
        break;
      case 'viewport_attach_skip':
        ledger.attachCount += 1;
        ledger.attachSkipCount += 1;
        break;
      case 'viewport_attach_bump':
        ledger.attachCount += 1;
        ledger.attachBumpCount += 1;
        break;
      case 'viewport_ticket_rejected':
        ledger.generationRejectCount += 1;
        ledger.lastRejectReason = '${extras['ticketRejectedReason'] ?? ''}';
        break;
      case 'app_bootstrap_commit':
        ledger.appBootstrapProducerCount += 1;
        break;
      case 'chat_reload_if_empty_load':
        ledger.reloadIfEmptyCount += 1;
        break;
      case 'uikit_loadChatRecord_local_started':
        ledger.uikitProducerCount += 1;
        break;
    }
  }

  static _ChatOpenTraceLedger? _findLedger(String chatOpenTraceId) {
    final id = chatOpenTraceId.trim();
    if (id.isEmpty || id == '-') {
      return null;
    }
    for (final ledger in _ledgers) {
      if (ledger.sessionId == id) {
        return ledger;
      }
    }
    return null;
  }

  static _ChatOpenTraceLedger _ledgerFor(ChatOpenTraceContext ctx) {
    final id = ctx.chatOpenTraceId.trim();
    if (id.isEmpty || id == '-') {
      return _detached;
    }
    final existing = _findLedger(id);
    if (existing != null) {
      return existing;
    }
    final rebuilt = _ChatOpenTraceLedger(
      sessionId: id,
      convId: ctx.conversationKey,
      t0Ms: ctx.t0Ms,
    );
    _ledgers.add(rebuilt);
    _pruneLedgers(keep: rebuilt);
    return rebuilt;
  }

  static void _pruneLedgers({_ChatOpenTraceLedger? keep}) {
    while (_ledgers.length > _maxLedgers) {
      var dropIndex = 0;
      if (identical(_ledgers[dropIndex], _current) ||
          identical(_ledgers[dropIndex], keep)) {
        dropIndex = 1;
      }
      if (dropIndex >= _ledgers.length) {
        break;
      }
      _ledgers.removeAt(dropIndex).settleTimer?.cancel();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    for (final ledger in _ledgers) {
      ledger.settleTimer?.cancel();
    }
    _ledgers.clear();
    _detached.settleTimer?.cancel();
    _detached.lastMarkMs = 0;
    _detached.lastEvent = '';
    _current = null;
    _hydrateOwnerRequestId = null;
    lastPrepareRequestId = 0;
    _prepareSnaps.clear();
    settleSummaryDelay = const Duration(milliseconds: 2000);
  }

  /// 阶段中文名，方便在 logcat 里扫。
  static String regionOf(String event) {
    switch (event) {
      case 'session_begin':
        return '①点击会话';
      case 'bootstrap_before_await':
        return '②进页前bootstrap开始';
      case 'bootstrap_peek_start':
        return '②peek拉历史开始';
      case 'bootstrap_peek_done':
        return '②peek拉历史结束';
      case 'bootstrap_url_resolve_done':
        return '②图片URL补全';
      case 'bootstrap_warm_skip':
        return '②暖窗已就绪跳过重灌';
      case 'bootstrap_after_await':
        return '②进页前bootstrap结束';
      case 'cold_bootstrap_timeout_before_push':
        return '②冷开push前bootstrap超时';
      case 'page_bootstrap_warm_skip':
        return '②页内bootstrap暖跳过';
      case 'navigator_push_begin':
        return '③开始push路由';
      case 'navigator_pop_back':
        return '③从聊天返回';
      case 'embedded_chat_switch':
        return '③嵌入态切换会话';
      case 'chat_init_state':
        return '④Chat页initState';
      case 'chat_first_frame':
        return '④Chat页首帧';
      case 'history_gate_warm_shell':
        return '⑤历史gate暖壳';
      case 'history_gate_cold_shell':
        return '⑤历史gate冷壳';
      case 'history_gate_thin_window':
        return '⑤历史gate薄窗';
      case 'history_gate_timeout_1_2s':
        return '⑤历史gate冷开超时1.2s';
      case 'history_gate_thin_timeout_1_2s':
        return '⑤历史gate薄窗超时1.2s';
      case 'history_gate_tips_merge_timeout':
        return '⑤历史gate tip合并超时';
      case 'history_gate_content_ready_skip':
        return '⑤有内容跳过整页gate';
      case 'prepare_gate_after_inflight_wait':
        return '⑤等待inflight结束';
      case 'prepare_gate_complete':
        return '⑤prepareGate完成';
      case 'history_list_first_build':
        return '⑥消息列表首次build';
      case 'opening_placeholder_first_paint':
        return '⑥冷开气泡占位首帧';
      case 'opening_placeholder_removed':
        return '⑦冷开气泡占位移除';
      case 'messages_first_visible':
        return '⑦消息首次可见';
      case 'open_summary':
        return '⑧打开汇总';
      case 'open_trace_summary':
        return '⑧打开链路计数';
      case 'group_member_open_shell':
        return '群成员开页壳';
      case 'group_member_full_load_start':
        return '群成员全量开始';
      case 'avatar_warm_done':
        return '头像预热完成';
      case 'mute_network_fetch_start':
        return '禁言网络拉取开始';
      case 'viewport_prepare_start':
        return '②prepare开始';
      case 'viewport_prepare_cache_hit':
        return '②prepare缓存命中';
      case 'viewport_prepare_local_begin':
        return '②prepare本地开始';
      case 'viewport_prepare_local_end':
        return '②prepare本地结束';
      case 'viewport_prepare_h0_begin':
        return '②prepare H0开始';
      case 'viewport_prepare_h0_commit':
        return '②prepare H0结果';
      case 'viewport_prepare_end':
        return '②prepare结束';
      case 'viewport_prepare_ignored':
        return '②prepare被作废';
      case 'viewport_attach_skip':
        return '④viewport attach跳过';
      case 'viewport_attach_bump':
        return '④viewport attach bump';
      case 'viewport_ticket_accepted':
        return '②H0 ticket接受';
      case 'viewport_ticket_rejected':
        return '②H0 ticket拒收';
      case 'app_hydrate_join':
        return '②hydrate join';
      case 'app_hydrate_reuse':
        return '②hydrate reuse';
      case 'app_hydrate_registered':
        return '②hydrate 注册';
      case 'app_hydrate_started':
        return '②hydrate 开始load';
      case 'app_hydrate_commit':
        return '②hydrate commit';
      case 'app_hydrate_aborted':
        return '②hydrate aborted';
      case 'peek_apply_join':
        return '②peek join';
      case 'peek_apply_local_join':
        return '②peek 本地join';
      case 'peek_apply_local_real':
        return '②peek 本地实读';
      case 'peek_apply_sdk_real':
        return '②peek SDK实读';
      case 'app_bootstrap_commit':
        return '②app写窗';
      case 'uikit_initForEachConversation':
        return '④UIKit init会话';
      case 'uikit_loadData_started':
        return '④UIKit _loadData';
      case 'uikit_hydrate_wait_result':
        return '④UIKit 等hydrate';
      case 'uikit_hydrate_deferred':
        return '④UIKit hydrate延期';
      case 'uikit_loadChatRecord_local_started':
        return '④UIKit LOCAL load';
      case 'uikit_loadChatRecord_local_done':
        return '④UIKit LOCAL 完成';
      case 'uikit_removeMessageList':
        return '④UIKit 清暖窗';
      case 'chat_reload_if_empty_load':
        return '⑤空窗补拉';
      default:
        if (event.startsWith('c2c_')) {
          return '⑤单聊历史/$event';
        }
        if (event.startsWith('bootstrap_')) {
          return '②bootstrap/$event';
        }
        if (event.startsWith('prepare_') || event.startsWith('history_')) {
          return '⑤历史/$event';
        }
        if (event.startsWith('chat_')) {
          return '④Chat/$event';
        }
        if (event.startsWith('viewport_') || event.startsWith('app_hydrate_')) {
          return '②viewport/$event';
        }
        if (event.startsWith('uikit_')) {
          return '④UIKit/$event';
        }
        return event;
    }
  }

  static void _print(
    String event, {
    String? conversationID,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    final buffer = StringBuffer('[ChatOpenPerf] event=$event');
    final id = (conversationID ?? '').trim();
    if (id.isNotEmpty) {
      buffer.write(' convHash=${_hashId(id)}');
    }
    for (final entry in extras.entries) {
      final value = _formatExtra(entry.key, entry.value);
      if (value == null) {
        continue;
      }
      buffer.write(' ${entry.key}=$value');
    }
    final line = buffer.toString();
    final sink = debugSink;
    if (sink != null) {
      sink(line);
    }
    if (consoleOutputEnabled && isEnabled) {
      // ignore: avoid_print
      print(line);
    }
  }

  static String _hashId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }
    // Stable, short process-independent fingerprint; raw IDs never enter logs.
    var hash = 0x811c9dc5;
    for (final codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String? _formatExtra(String key, Object? value) {
    if (value == null) {
      return null;
    }
    final normalizedKey = key.toLowerCase().replaceAll('_', '');
    if (_plaintextKeys.contains(normalizedKey)) {
      return _singleLine(value.toString());
    }
    if (_isSensitiveIdentifierKey(normalizedKey)) {
      return _hashId(value.toString());
    }
    if (_isSensitiveContentKey(normalizedKey)) {
      return '<redacted>';
    }
    return _singleLine(value.toString());
  }

  static bool _isSensitiveIdentifierKey(String key) {
    return key == 'key' ||
        key == 'conversationkey' ||
        key.endsWith('id') ||
        key.contains('convid') ||
        key.contains('conversationid') ||
        key.contains('msgid') ||
        key.contains('messageid') ||
        key.contains('anchor');
  }

  static bool _isSensitiveContentKey(String key) {
    return key == 'lastmessage' ||
        key == 'messagebody' ||
        key == 'content' ||
        key == 'text';
  }

  static String _singleLine(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) {
      return normalized;
    }
    return '${normalized.substring(0, 157)}...';
  }
}

class ChatOpenTraceContext {
  const ChatOpenTraceContext({
    required this.session,
    required this.chatOpenTraceId,
    required this.requestId,
    required this.conversationKey,
    required this.t0Ms,
  });

  final String session;
  final String chatOpenTraceId;
  final int requestId;
  final String conversationKey;
  final int t0Ms;
}

class ChatOpenPrepareWorkSnapshot {
  ChatOpenPrepareWorkSnapshot({
    required this.requestId,
    required this.source,
    this.trace,
  });

  final int requestId;
  final String source;
  final ChatOpenTraceContext? trace;
  bool owned = false;
  bool joined = false;
  bool dbRead = false;
  bool sdkRead = false;
  bool committed = false;
}

class _ChatOpenTraceLedger {
  _ChatOpenTraceLedger({
    required this.sessionId,
    required this.convId,
    required this.t0Ms,
  }) : lastMarkMs = t0Ms;

  final String sessionId;
  final String convId;
  final int t0Ms;
  int lastMarkMs;
  String lastEvent = 'session_begin';
  Timer? settleTimer;
  bool firstMessagesVisibleLogged = false;
  bool historyListBuiltLogged = false;

  int prepareCount = 0;
  int actualHydrateCount = 0;
  int hydrateJoinCount = 0;
  int hydrateReuseCount = 0;
  int hydrateStartedCount = 0;
  int hydrateCommitCount = 0;
  int hydrateAbortedCount = 0;
  int ignoredPrepareCount = 0;
  int ignoredAfterDbRead = 0;
  int ignoredAfterSdkRead = 0;
  int ignoredAfterCommit = 0;
  int attachCount = 0;
  int attachBumpCount = 0;
  int attachSkipCount = 0;
  int generationRejectCount = 0;
  int appBootstrapProducerCount = 0;
  int reloadIfEmptyCount = 0;
  int uikitProducerCount = 0;
  String lastIgnoredReason = '';
  String lastRejectReason = '';

  ChatOpenTraceContext toContext() {
    return ChatOpenTraceContext(
      session: sessionId,
      chatOpenTraceId: sessionId,
      requestId: 0,
      conversationKey: convId,
      t0Ms: t0Ms,
    );
  }
}

~~~

12. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/chat_pipeline_clock.dart:1>)，原文件 lib/src/services/chat_pipeline_clock.dart，1–134 行。

~~~dart
// 一次性诊断工具：跨页面跟踪"点击会话 → 首帧可见"全链路时延。
// 仅用于性能诊断，不参与业务逻辑。默认关闭控制台输出。
import 'package:flutter/foundation.dart';

class ChatPipelineClock {
  static final ChatPipelineClock instance = ChatPipelineClock._();
  ChatPipelineClock._();

  static const bool enabled = false;

  final Map<String, Stopwatch> _clocks = <String, Stopwatch>{};

  /// 把任意形式的会话 ID 归一化成 Stopwatch 主键（c2c_xxx / group_xxx）。
  /// 优先 groupID / userID（来自 V2TimConversation），其次回退到 raw conversationID。
  /// 若 raw 已经带 c2c_/group_ 前缀则直接返回；否则按 ChatIdFormat 推断类型补前缀。
  static String normalizeKey({
    String? rawConversationId,
    String? userId,
    String? groupId,
  }) {
    final g = groupId?.trim() ?? '';
    if (g.isNotEmpty) {
      if (g.startsWith('group_')) return g;
      if (g.startsWith('@TGS#')) return g;
      return 'group_$g';
    }
    final u = userId?.trim() ?? '';
    if (u.isNotEmpty) {
      if (u.startsWith('c2c_')) return u;
      return 'c2c_$u';
    }
    final r = rawConversationId?.trim() ?? '';
    if (r.isEmpty) return '';
    if (r.startsWith('c2c_') || r.startsWith('group_')) return r;
    if (r.startsWith('@TGS#')) return r;
    return r;
  }

  /// 在 conv_item_tap 内调用，建立 t0 锚点。
  void start(String convId) {
    final sw = _clocks.putIfAbsent(convId, () => Stopwatch());
    sw
      ..reset()
      ..start();
  }

  /// 取从 start 起算的总偏移（毫秒）。未 start 返回 -1。
  /// 兼容 `group_xxx` / 裸 `xxx`、`c2c_xxx` / 裸 userId。
  int offsetMs(String convId) {
    final sw = _runningClock(convId);
    if (sw == null) return -1;
    return sw.elapsedMilliseconds;
  }

  /// 取从 start 起算的总偏移（微秒）。未 start 返回 -1。
  int offsetMicros(String convId) {
    final sw = _runningClock(convId);
    if (sw == null) return -1;
    return sw.elapsedMicroseconds;
  }

  /// 取得 sw 用于逐段 delta 计算。
  Stopwatch? stopwatch(String convId) => _runningClock(convId);

  Stopwatch? _runningClock(String convId) {
    for (final key in _aliasKeys(convId)) {
      final sw = _clocks[key];
      if (sw != null && sw.isRunning) {
        return sw;
      }
    }
    return null;
  }

  Iterable<String> _aliasKeys(String convId) sync* {
    final raw = convId.trim();
    if (raw.isEmpty) {
      return;
    }
    yield raw;
    final normalized = normalizeKey(rawConversationId: raw);
    if (normalized.isNotEmpty && normalized != raw) {
      yield normalized;
    }
    if (raw.startsWith('group_') && raw.length > 6) {
      yield raw.substring(6);
    } else if (raw.startsWith('c2c_') && raw.length > 4) {
      yield raw.substring(4);
    } else if (!raw.startsWith('group_') && !raw.startsWith('c2c_')) {
      yield 'group_$raw';
      yield 'c2c_$raw';
    }
  }

  /// 在 pipeline 末端释放资源。
  void clear(String convId) {
    _clocks.remove(convId);
  }

  /// 统一格式输出。
  void trace(
    String convId,
    String stage, {
    int? elapsedMs,
    Map<String, Object?>? extras,
  }) {
    if (!enabled) {
      return;
    }
    final offset = offsetMs(convId);
    final buf = StringBuffer()
      ..write('[Pipeline] stage=')
      ..write(stage)
      ..write(' conv=')
      ..write(convId)
      ..write(' offset=')
      ..write(offset)
      ..write('ms');
    if (elapsedMs != null) {
      buf
        ..write(' elapsed=')
        ..write(elapsedMs)
        ..write('ms');
    }
    if (extras != null && extras.isNotEmpty) {
      buf
        ..write(' ')
        ..write(extras.entries.map((e) => '${e.key}=${e.value}').join(' '));
    }
    // ignore: avoid_print
    debugPrint(buf.toString());
  }
}

~~~

13. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_history_open_layout_ready.dart:1>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/utils/chat_history_open_layout_ready.dart，1–113 行。

~~~dart
import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges HistoryMessageList layout-ready → Chat page open gate.
///
/// Call [begin] when starting an open, [signal] when list geometry is ready,
/// and [wait] from the page gate Future.
class ChatHistoryOpenLayoutReady {
  ChatHistoryOpenLayoutReady._();

  static final Map<String, Completer<void>> _pending =
      <String, Completer<void>>{};
  static final Set<String> _signaled = <String>{};
  static final Map<String, int> _epoch = <String, int>{};

  /// Bumps on every [begin] so lists can invalidate stale ready state.
  static final ValueNotifier<int> epochRevision = ValueNotifier<int>(0);

  static String _key(String conversationID) => conversationID.trim();

  /// Current begin-generation for [conversationID] (0 if never begun).
  static int epochOf(String conversationID) {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return 0;
    }
    return _epoch[id] ?? 0;
  }

  /// Reset for a new open / wait-phase of [conversationID]. Bumps epoch.
  static void begin(String conversationID) {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return;
    }
    _signaled.remove(id);
    _epoch[id] = (_epoch[id] ?? 0) + 1;
    final existing = _pending.remove(id);
    if (existing != null && !existing.isCompleted) {
      existing.complete();
    }
    epochRevision.value++;
  }

  /// Completes waiters when geometry is ready for the current [epoch].
  /// If [epoch] is non-null and stale, the signal is ignored.
  static void signal(String conversationID, {int? epoch}) {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return;
    }
    final current = _epoch[id] ?? 0;
    if (epoch != null && epoch != current) {
      return;
    }
    _signaled.add(id);
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  static void cancel(String conversationID) {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return;
    }
    _signaled.remove(id);
    final pending = _pending.remove(id);
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  /// Whether [signal] has fired for the current [begin] generation.
  /// Unlike a one-shot consume, this stays true until next [begin]/[cancel]
  /// so multiple waiters (chat gate + warm reconcile) can observe ready.
  static bool isReady(String conversationID) {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return false;
    }
    return _signaled.contains(id);
  }

  /// Resolves when [signal] fires, or after [timeout].
  /// Returns `true` if layout signaled; `false` on timeout / empty id.
  ///
  /// Ready state is **not** consumed: later waiters still see [isReady].
  static Future<bool> wait(
    String conversationID, {
    Duration timeout = const Duration(milliseconds: 1000),
  }) async {
    final id = _key(conversationID);
    if (id.isEmpty) {
      return false;
    }
    if (_signaled.contains(id)) {
      return true;
    }
    final completer = _pending.putIfAbsent(id, Completer<void>.new);
    try {
      await completer.future.timeout(timeout);
      // [cancel]/[begin] complete waiters without signaling ready.
      return _signaled.contains(id);
    } on TimeoutException {
      _pending.remove(id);
      return _signaled.contains(id);
    }
  }
}

~~~

14. [_ChatState._draft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:371>)，原文件 lib/src/chat.dart，371–371 行。

~~~dart
final ChatDraftController _draft = ChatDraftController();
~~~

15. [_ChatState._draftWrites](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:372>)，原文件 lib/src/chat.dart，372–372 行。

~~~dart
final ChatDraftWriteQueue _draftWrites = ChatDraftWriteQueue();
~~~

16. [_ChatState._beginChatOpenGeneration](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:490>)，原文件 lib/src/chat.dart，490–490 行。

~~~dart
int _beginChatOpenGeneration() => ++_chatOpenGeneration;
~~~

17. [_ChatState._isChatOpenGenerationCurrent](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:492>)，原文件 lib/src/chat.dart，492–503 行。

~~~dart
bool _isChatOpenGenerationCurrent(int generation, String conversationID) {
    return mounted &&
        generation == _chatOpenGeneration &&
        ChatPageScope.instance.allowsProjection(
          token: _pageScope,
          conversationId: conversationID,
        ) &&
        MessageConversationId.sameConversation(
          _resolvedConversationID(),
          conversationID,
        );
  }
~~~

18. [_ChatState._scheduleReconnectHistoryRecovery](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:911>)，原文件 lib/src/chat.dart，911–943 行。

~~~dart
void _scheduleReconnectHistoryRecovery() {
    final generation = _chatOpenGeneration;
    final scheduledConversationID = _resolvedConversationID();
    _reconnectRecoveryTimer?.cancel();
    _reconnectRecoveryTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_isChatOpenGenerationCurrent(generation, scheduledConversationID)) {
        return;
      }
      final conversationId = _resolvedConversationID();
      if (conversationId.isEmpty) {
        return;
      }
      if (_latestWindowResetNeeded()) {
        // Real reconnect while the page is open: the latest-window reset owns
        // recovery. It repairs immediately when the user is at the bottom and
        // defers (polling) while history is being read. The anchor-based
        // catch-up must not compete for the same recovery.
        _armLatestWindowResetWhenAtBottom(reason: 'im_reconnected');
        return;
      }
      unawaited(
        ConversationHistorySyncCoordinator.instance.reconcileConversation(
          conversationID: conversationId,
          conversation: _conversation,
          reason: 'im_reconnected',
        ),
      );
      ChatHistoryRefreshBus.instance.requestRefresh(
        conversationId: conversationId,
        reason: 'im_reconnected',
      );
    });
  }
~~~

19. [_ChatState._loadChatLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1306>)，原文件 lib/src/chat.dart，1306–1351 行。

~~~dart
Future<void> _loadChatLocalDraft() async {
    final conversationId = _resolvedConversationID();
    if (conversationId.isEmpty) {
      return;
    }
    final loadRevision = _draft.stateRevision;
    final text = await ConversationDraftService.instance.loadDraftText(
      conversationID: conversationId,
    );
    if (!mounted ||
        !_isCurrentConversation(conversationId) ||
        !_draft.canApplyLoadedDraft(loadRevision)) {
      return;
    }
    _draft.setTextImmediate(text);
    final loaded = text?.trim() ?? '';
    if (loaded.isEmpty) {
      return;
    }

    void applyToInputIfReady() {
      if (!mounted ||
          !_isCurrentConversation(conversationId) ||
          !_draft.canApplyLoadedDraft(loadRevision)) {
        return;
      }
      final inputController = _chatController.textFieldController;
      final editingController = inputController?.textEditingController;
      if (inputController == null || editingController == null) {
        return;
      }
      if (editingController.text.trim().isEmpty) {
        inputController.setTextField(text!, notifyChanged: false);
      }
    }

    // The outer controller owns a TextEditingController before the actual
    // input widget has attached its listener. A draft loaded in that window
    // makes setTextField() notify nobody. Rebuild with draftText for initState,
    // then retry after the frame for an already-created input widget.
    applyToInputIfReady();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyToInputIfReady();
    });
  }
~~~

20. [_ChatState._persistChatLocalDraftText](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1353>)，原文件 lib/src/chat.dart，1353–1405 行。

~~~dart
Future<void> _persistChatLocalDraftText(
    String text,
    int generation, {
    String? conversationID,
    bool enforceCurrentGeneration = true,
  }) async {
    final conversationId = (conversationID ?? _resolvedConversationID()).trim();
    if (conversationId.isEmpty) {
      return;
    }
    await _draftWrites.enqueue(
      () async {
        if (enforceCurrentGeneration && _draft.shouldSuppressLifecyclePersist) {
          ConversationDraftLeaveTrace.stage(
            'draft_persist_skipped',
            conversationId: conversationId,
            extras: const <String, Object?>{'reason': 'suppress'},
          );
          return;
        }
        if (enforceCurrentGeneration && generation != _draft.writeGeneration) {
          ConversationDraftLeaveTrace.stage(
            'draft_persist_skipped',
            conversationId: conversationId,
            extras: const <String, Object?>{'reason': 'generation'},
          );
          return;
        }
        if (_isCurrentConversation(conversationId)) {
          _draft.text = text.trim().isEmpty ? null : text;
        }
        ConversationDraftLeaveTrace.stage(
          'draft_persist_enqueue_run',
          conversationId: conversationId,
          draftText: text,
          extras: <String, Object?>{
            'generation': generation,
            'suppress': _draft.shouldSuppressLifecyclePersist,
          },
        );
        await ConversationDraftService.instance.persistDraft(
          conversationID: conversationId,
          rawInputText: text,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          '[ChatDraft] persist failed conv=$conversationId error=$error\n'
          '$stackTrace',
        );
      },
    );
  }
~~~

21. [_ChatState._onChatDraftTextChanged](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1407>)，原文件 lib/src/chat.dart，1407–1422 行。

~~~dart
void _onChatDraftTextChanged(String text) {
    final conversationId = _resolvedConversationID();
    if (text.trim().isNotEmpty) {
      ConversationDraftLeaveTrace.focus(conversationId);
    }
    ConversationDraftLeaveTrace.stage(
      'draft_input_changed',
      conversationId: conversationId,
      draftText: text,
    );
    _draft.onChanged(
      text,
      persist: (raw, generation) =>
          unawaited(_persistChatLocalDraftText(raw, generation)),
    );
  }
~~~

22. [_ChatState._persistChatLocalDraft](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1424>)，原文件 lib/src/chat.dart，1424–1444 行。

~~~dart
Future<void> _persistChatLocalDraft() async {
    if (_draft.shouldSuppressLifecyclePersist) {
      return;
    }
    _draft.cancelDebounce();
    final text =
        _chatController.textFieldController?.textEditingController?.text ?? '';
    final conversationId = _resolvedConversationID();
    ConversationDraftLeaveTrace.focus(conversationId);
    ConversationDraftLeaveTrace.stage(
      'draft_leave_persist_start',
      conversationId: conversationId,
      draftText: text,
      extras: const <String, Object?>{'source': 'lifecycle'},
    );
    await _persistChatLocalDraftText(
      text,
      _draft.writeGeneration,
      conversationID: conversationId,
    );
  }
~~~

23. [_ChatState._clearChatLocalDraftAfterSend](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:1446>)，原文件 lib/src/chat.dart，1446–1476 行。

~~~dart
Future<void> _clearChatLocalDraftAfterSend(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    // 发送成功后使发送前排队的 debounce 保存失效，否则旧草稿可能在清理后
    // 又被异步写回本地库，表现为“消息已发出但草稿仍出现”。
    _draft.markSendCompleted();
    if (mounted) {
      _draft.text = null;
    }
    final ids = <String>{id, _conversation.conversationID.trim()};
    final groupId = _conversation.groupID?.trim() ?? '';
    if (_getConvType() == ConvType.group && groupId.isNotEmpty) {
      ids.add(groupId);
      ids.add('group_$groupId');
    }
    await _draftWrites.enqueue(
      () async {
        await ConversationDraftService.instance.clearDraftForConversationIds(
          ids,
        );
      },
      onError: (error, stackTrace) {
        debugPrint(
          '[ChatDraft] clear-after-send failed conv=$id error=$error\n'
          '$stackTrace',
        );
      },
    );
  }
~~~

24. [_ChatState._seedCachedHistoryOnOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4135>)，原文件 lib/src/chat.dart，4135–4159 行。

~~~dart
void _seedCachedHistoryOnOpen(String convKey) {
    if (convKey.isEmpty) {
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    globalModel.setMessageListPosition(
      convKey,
      HistoryMessagePosition.bottom,
      notify: false,
    );

    final rawCount = globalModel.rawMessageCount(convKey);
    if (rawCount > 0) {
      final list = globalModel.getMessageList(convKey);
      if (list != null) {
        _normalizeSelfMessageAvatars(list);
      }
      if (globalModel.hasInitialHistoryLoaded(convKey)) {
        return;
      }
      if (rawCount >= HistoryMessageDartConstant.initialOpenFetchCount) {
        globalModel.markInitialHistoryLoaded(convKey);
      }
    }
  }
~~~

25. [_ChatState._isOpenHistoryWarm](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4161>)，原文件 lib/src/chat.dart，4161–4184 行。

~~~dart
bool _isOpenHistoryWarm(String convKey) {
    if (convKey.isEmpty) {
      return false;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (!globalModel.hasInitialHistoryLoaded(convKey)) {
      return false;
    }
    // removeMessageList 会删掉 map 条目；若只剩残留 loaded 别名，不能当暖窗，
    // 否则跳过 gate 又无消息 → 整页空灰。
    final raw = globalModel.rawMessageList(convKey);
    if (raw == null) {
      return false;
    }
    if (raw.isNotEmpty) {
      return true;
    }
    // 空 list：仅在「会话确实像空」且没有并行 peek 时算 warm。
    // 冷开并行期间禁止把空占位当成暖窗，否则会跳过 gate + hydrate_keep_empty。
    if (globalModel.hasOpenHydrateInFlight(convKey)) {
      return false;
    }
    return _conversationLooksEmptyForOpen(convKey);
  }
~~~

26. [_ChatState._conversationLooksEmptyForOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4186>)，原文件 lib/src/chat.dart，4186–4209 行。

~~~dart
/// 列表侧已无真实历史证据时，进页应直接空态，而不是先转圈拉历史。
  bool _conversationLooksEmptyForOpen(String convKey) {
    if (convKey.isEmpty) {
      return false;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (globalModel.rawMessageCount(convKey) > 0) {
      return false;
    }
    final conv = widget.selectedConversation;
    if ((conv.unreadCount ?? 0) > 0) {
      return false;
    }
    final last = conv.lastMessage;
    // 仅 lastMessage 缺失才预判空。最新一条是 tip/灰字不代表 SDK 无历史；
    // 冷开并行 peek 前误标 empty-loaded 会 hydrate_keep_empty → 灰屏。
    //
    // 社群：列表预览因 ID/落库失败暂时为 null 时，禁止预判空——否则再进页
    // 会 clearLocalHistoryAsEmptyLoaded，跳过云端拉历史，聊天记录整页空白。
    if (last == null && _getConvType() == ConvType.group) {
      return false;
    }
    return last == null;
  }
~~~

27. [_ChatState._ensureEmptyConversationReadyForOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4211>)，原文件 lib/src/chat.dart，4211–4225 行。

~~~dart
void _ensureEmptyConversationReadyForOpen(String convKey) {
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // 冷开并行 peek 未完成：禁止预判 empty-loaded。
    if (globalModel.hasOpenHydrateInFlight(convKey)) {
      return;
    }
    if (!_conversationLooksEmptyForOpen(convKey)) {
      return;
    }
    if (globalModel.hasInitialHistoryLoaded(convKey) &&
        globalModel.rawMessageCount(convKey) == 0) {
      return;
    }
    globalModel.clearLocalHistoryAsEmptyLoaded(convKey);
  }
~~~

28. [_ChatState._startOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4227>)，原文件 lib/src/chat.dart，4227–4301 行。

~~~dart
void _startOpenHistoryGate(String convKey) {
    _openLifecycle.openHistoryGateConvKey = convKey;
    _openLifecycle.openHistoryPreparationGate = null;
    if (convKey.isEmpty ||
        widget.initFindingMsg != null ||
        widget.searchJumpAnchor != null ||
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          _getConvType(),
          widget.entryUnreadCount ?? 0,
        )) {
      _openLifecycle.openHistoryGate = null;
      if (convKey.isNotEmpty) {
        ChatHistoryOpenLayoutReady.cancel(convKey);
      }
      return;
    }
    // 先同步灌入缓存；只有完整首屏（或确认空）才跳过 gate。
    // 列表 LOCAL 预热常常只有几条：立刻上屏会在反转列表底部露出大片空白。
    _seedCachedHistoryOnOpen(convKey);
    _ensureEmptyConversationReadyForOpen(convKey);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final rawCount = globalModel.rawMessageCount(convKey);
    final emptyConfirmed =
        globalModel.hasInitialHistoryLoaded(convKey) && rawCount == 0;
    final completeWindow =
        ConversationPreviewHistorySync.isCompleteOpenHistoryWindow(
      globalModel: globalModel,
      conversationKey: convKey,
    );
    // 完整首屏或确认空：无需等待可交互 gate。
    if (completeWindow || emptyConfirmed) {
      ChatHistoryOpenLayoutReady.cancel(convKey);
      ChatOpenPerfLog.mark(
        'history_gate_content_ready_skip',
        conversationID: convKey,
        extras: <String, Object?>{
          'rawCount': rawCount,
          'emptyConfirmed': emptyConfirmed,
          'completeWindow': completeWindow,
          'initialLoaded': globalModel.hasInitialHistoryLoaded(convKey),
        },
      );
      _openLifecycle.openHistoryGate = null;
      final preparation = _prepareOpenHistoryGate(
        convKey,
        cachedHistorySeeded: true,
      );
      _openLifecycle.openHistoryPreparationGate = preparation;
      unawaited(preparation);
      if (_getConvType() == ConvType.group) {
        unawaited(_ensureGroupLocalTipsMergedOnOpen(convKey));
      }
      return;
    }
    ChatHistoryOpenLayoutReady.begin(convKey);
    // 未灌满的预热窗也走 prepare + layout，避免先亮底部几条。
    // 真冷零消息仍串行；事件名保留 cold_shell，兼容既有性能日志。
    final thinWindow = rawCount > 0;
    ChatOpenPerfLog.mark(
      thinWindow ? 'history_gate_thin_window' : 'history_gate_cold_shell',
      conversationID: convKey,
      extras: <String, Object?>{'rawCount': rawCount},
    );
    final preparation = _prepareOpenHistoryGate(
      convKey,
      cachedHistorySeeded: true,
      coldOpen: !thinWindow,
    );
    _openLifecycle.openHistoryPreparationGate = preparation;
    _openLifecycle.openHistoryGate = _runOpenHistoryGateWithTipsMerge(
      convKey,
      coldOpen: !thinWindow,
      preparation: preparation,
    );
  }
~~~

29. [_ChatState._runOpenHistoryGateWithTipsMerge](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4303>)，原文件 lib/src/chat.dart，4303–4350 行。

~~~dart
/// 先权威历史（冷开 / 薄窗均可 soft-timeout），再合本地 tip，
  /// 再等几何 ready。preparation 绝不能无限挂起，否则 AbsorbPointer 锁死滚动。
  Future<void> _runOpenHistoryGateWithTipsMerge(
    String convKey, {
    required bool coldOpen,
    required Future<void> preparation,
  }) async {
    if (convKey.isEmpty) {
      return;
    }
    // 薄窗与真冷共用硬超时：薄窗原先无超时，云端慢时门永不关 → 能返回不能滑。
    await preparation.timeout(
      const Duration(milliseconds: 1200),
      onTimeout: () {
        ChatOpenPerfLog.mark(
          coldOpen
              ? 'history_gate_timeout_1_2s'
              : 'history_gate_thin_timeout_1_2s',
          conversationID: convKey,
        );
      },
    );
    if (!mounted) {
      return;
    }
    try {
      await _ensureGroupLocalTipsMergedOnOpen(
        convKey,
      ).timeout(const Duration(milliseconds: 400));
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'history_gate_tips_merge_timeout',
        conversationID: convKey,
      );
    } catch (_) {
      // tip 合并失败不挡揭开门。
    }
    if (!mounted) {
      return;
    }
    // 列表已经揭开并 signal 过：不要二次 begin 抬 epoch，否则会把已亮的历史闪没。
    if (ChatHistoryOpenLayoutReady.isReady(convKey)) {
      return;
    }
    // 作废 prepare/tip 期间可能发出的假 signal，再等几何 ready。
    ChatHistoryOpenLayoutReady.begin(convKey);
    await _waitOpenHistoryLayoutReady(convKey);
  }
~~~

30. [_ChatState._waitOpenHistoryLayoutReady](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4352>)，原文件 lib/src/chat.dart，4352–4365 行。

~~~dart
Future<void> _waitOpenHistoryLayoutReady(String convKey) async {
    // History preparation already has a 1.2s soft timeout. Do not add another
    // full second of shell time when hidden-list geometry cannot settle yet.
    final ready = await ChatHistoryOpenLayoutReady.wait(
      convKey,
      timeout: const Duration(milliseconds: 300),
    );
    if (!ready) {
      ChatOpenPerfLog.mark(
        'history_open_ready_timeout',
        conversationID: convKey,
      );
    }
  }
~~~

31. [_ChatState._prepareOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4367>)，原文件 lib/src/chat.dart，4367–4416 行。

~~~dart
Future<void> _prepareOpenHistoryGate(
    String convKey, {
    bool cachedHistorySeeded = false,
    bool coldOpen = false,
  }) async {
    if (convKey.isEmpty) {
      return;
    }
    if (!cachedHistorySeeded) {
      _seedCachedHistoryOnOpen(convKey);
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    ChatOpenPerfLog.mark(
      'prepare_gate_start',
      conversationID: convKey,
      extras: <String, Object?>{'coldOpen': coldOpen},
    );
    // Reuse the local-only snapshot started at tap time. Direct entry paths
    // that do not pass through the conversation list start the same bounded
    // local task here. Cloud verification remains outside this gate.
    final loaded =
        await ChatOpenViewportCoordinator.instance.ensureLocalSnapshotForOpen(
      conversation: _conversation,
      timeout: const Duration(milliseconds: 900),
    );
    if (!mounted) return;
    if (loaded) {
      _chatController.model?.syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(convKey),
      );
      ChatOpenPerfLog.mark('prepare_gate_local_snapshot_reused',
          conversationID: convKey);
    }
    ChatOpenPerfLog.mark(
      'prepare_gate_bootstrap_done',
      conversationID: convKey,
      extras: <String, Object?>{
        'loaded': loaded,
        'rawCount': globalModel.rawMessageCount(convKey),
      },
    );
    if (!mounted) {
      return;
    }
    if (loaded) {
      _clearMountedDisplayListCache();
    }
    _markChatOpenHistoryReady();
    ChatOpenPerfLog.mark('prepare_gate_complete', conversationID: convKey);
  }
~~~

32. [_ChatState._ensureGroupLocalTipsMergedOnOpen](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4504>)，原文件 lib/src/chat.dart，4504–4522 行。

~~~dart
/// 进聊首屏前合并本地群灰字并过滤占位 IM tip（设/取消管理员等）。
  Future<void> _ensureGroupLocalTipsMergedOnOpen(String convKey) async {
    if (!mounted || convKey.isEmpty) {
      return;
    }
    if (_getConvType() != ConvType.group || !SelfHostedGroupBridge.enabled) {
      return;
    }
    final groupId =
        widget.selectedConversation.groupID?.trim().isNotEmpty == true
            ? widget.selectedConversation.groupID!.trim()
            : convKey;
    if (groupId.isEmpty) {
      return;
    }
    await GroupTipsOperatorPatchService.instance.applyPatchesForVisibleGroup(
      groupId,
    );
  }
~~~

33. [_ChatState._wrapChatWithOpenHistoryGate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:4536>)，原文件 lib/src/chat.dart，4536–4541 行。

~~~dart
Widget _wrapChatWithOpenHistoryGate(Widget chatWidget) {
    // History readiness remains a lifecycle/scheduling gate, not a page-wide
    // interaction gate. The stable TIMUIKitChat tree owns its loading state,
    // while the app bar and input stay responsive during a cold history load.
    return chatWidget;
  }
~~~

34. [_ChatState._reloadChatHistoryIfEmpty](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7379>)，原文件 lib/src/chat.dart，7379–7573 行。

~~~dart
Future<void> _reloadChatHistoryIfEmpty({required String reason}) async {
    if (!mounted) {
      return;
    }
    if (_hasVisibleHistoryMessages()) {
      return;
    }
    final convId = _resolvedConversationID();
    final convKey = _getConvID()?.trim() ?? '';
    final reloadTrace = ChatOpenPerfLog.captureCurrent(conversationKey: convKey);
    if (convId.isEmpty ||
        !MessageConversationId.sameConversation(
          ActiveChatRegistry.instance.activeConversationId,
          convId,
        )) {
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final initialLoaded = globalModel.hasInitialHistoryLoaded(convKey);
    final model = _chatController.model;
    // 冷启动首屏由 UIKit hydrate 独占；post_open 不要抢先塞预览消息造成 1→30 抖动。
    if (!initialLoaded) {
      if (model?.isLoadingChatHistory == true) {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_skip_hydrating',
          conversationID: convId,
          extras: <String, Object?>{'reason': reason},
        );
        return;
      }
      if (reason == 'post_open') {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_skip_post_open_cold',
          conversationID: convId,
        );
        return;
      }
    }
    final preview = await _fetchConversationPreviewLastMessage();
    final previewMsgId = preview?.msgID?.trim() ?? '';
    // 已确认空会话（清空记录后标了 empty-loaded、且不再可能有更早历史）
    // 且预览也无消息：没有任何可补拉的内容，跳过 local/cloud 双拉，
    // 避免清空后进页对同一空会话反复 setMessageList 的加载风暴。
    if (preview == null &&
        globalModel.hasInitialHistoryLoaded(convKey) &&
        globalModel.rawMessageCount(convKey) == 0 &&
        !globalModel.mayHaveOlderHistory(convKey)) {
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_skip_confirmed_empty',
        conversationID: convId,
        extras: <String, Object?>{'reason': reason},
      );
      return;
    }
    ChatDiagLog.log(
      'ChatHistory',
      'reload_if_empty_start',
      conversationID: convId,
      extras: <String, Object?>{
        'reason': reason,
        'convKey': convKey,
        'type': _getConvType().name,
        'hasPreviewLastMessage': preview != null,
        'previewMsgId': previewMsgId,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'cachedRaw': serviceLocator<TUIChatGlobalModel>().rawMessageCount(
          convKey,
        ),
        'initialLoaded': serviceLocator<TUIChatGlobalModel>()
            .hasInitialHistoryLoaded(convKey),
      },
    );
    try {
      if (model == null) {
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_no_model',
          conversationID: convId,
          extras: <String, Object?>{'reason': reason},
        );
        await _chatController.refreshCurrentHistoryList();
        return;
      }
      // 仅在首屏已加载完成时补预览，避免冷启动先显示 1 条再 hydrate 整页抖动。
      if (preview != null && initialLoaded) {
        final merged = await _mergePreviewMessageIfMissing();
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_preview_merge',
          conversationID: convId,
          extras: <String, Object?>{
            'merged': merged,
            'hasMessages': _hasVisibleHistoryMessages(),
          },
        );
      }
      ChatOpenPerfLog.mark(
        'chat_reload_if_empty_load',
        conversationID: convId,
        extras: <String, Object?>{
          'reason': reason,
          'producer': 'reload_if_empty',
        },
        trace: reloadTrace,
      );
      await model.loadChatRecord(
        count: 20,
        getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      );
      var hasMessages = _hasVisibleHistoryMessages();
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_local_done',
        conversationID: convId,
        extras: <String, Object?>{
          'hasMessages': hasMessages,
          'listLen': model.globalModel.rawMessageCount(convKey),
        },
      );
      if (!hasMessages) {
        // Cloud recovery is owned by ConversationHistorySyncCoordinator.
        // Keep this legacy empty-page hook local-only so it cannot create a
        // second cloud pagination owner beside the open/reconnect pipeline.
        await ConversationHistorySyncCoordinator.instance.verifyAfterFirstFrame(
          conversation: _conversation,
          reason: 'reload_if_empty_$reason',
          delay: Duration.zero,
          logTrace: reloadTrace,
        );
        hasMessages = _hasVisibleHistoryMessages();
        ChatDiagLog.log(
          'ChatHistory',
          'reload_if_empty_coordinator_done',
          conversationID: convId,
          extras: <String, Object?>{
            'hasMessages': hasMessages,
            'listLen': model.globalModel.rawMessageCount(convKey),
          },
        );
      }
      if (hasMessages) {
        serviceLocator<TUIChatGlobalModel>().markInitialHistoryLoaded(convKey);
      }
      // 清空后确实无消息：标记 empty-loaded，避免一直 bootstrapping 转圈。
      if (!hasMessages && !globalModel.hasInitialHistoryLoaded(convKey)) {
        final clearedAt =
            await ChatSessionController.instance.historyClearedAtMs(convKey);
        final inGrace = ArchiveHistoryProvider.isInHistoryClearGrace(convKey);
        if (clearedAt > 0 ||
            inGrace ||
            reason == 'return_from_profile' ||
            reason == 'return_from_settings') {
          globalModel.clearLocalHistoryAsEmptyLoaded(convKey);
          if (convId.isNotEmpty && convId != convKey) {
            globalModel.clearLocalHistoryAsEmptyLoaded(convId);
          }
          ChatDiagLog.log(
            'ChatHistory',
            'reload_if_empty_mark_empty_loaded',
            conversationID: convId,
            extras: <String, Object?>{
              'reason': reason,
              'clearedAt': clearedAt,
              'inGrace': inGrace,
            },
          );
        }
      }
    } catch (e) {
      ChatDiagLog.log(
        'ChatHistory',
        'reload_if_empty_error',
        conversationID: convId,
        extras: <String, Object?>{'reason': reason, 'error': e.toString()},
      );
      try {
        await _chatController.refreshCurrentHistoryList();
      } catch (_) {}
    }
    ChatDiagLog.log(
      'ChatHistory',
      'reload_if_empty_end',
      conversationID: convId,
      extras: <String, Object?>{
        'reason': reason,
        'hasMessages': _hasVisibleHistoryMessages(),
      },
    );
    if (mounted) {
      setState(() {});
    }
  }
~~~

35. [_ChatState._markChatOpenHistoryReady](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7872>)，原文件 lib/src/chat.dart，7872–7898 行。

~~~dart
void _markChatOpenHistoryReady() {
    if (!_openLifecycle.markHistoryReady(_chatOpenPhaseGeneration)) {
      return;
    }
    ChatOpenPerfLog.mark(
      'chat_open_phase_history_ready_ms',
      extras: <String, Object?>{
        'durationMs': _chatOpenInitStopwatch.elapsedMilliseconds,
        'count': 1,
      },
    );
    final generation = _chatOpenPhaseGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _chatOpenPhaseGeneration) return;
      if (_openLifecycle.markInteractive(generation)) {
        ChatOpenPerfLog.mark(
          'chat_open_phase_interactive_ms',
          extras: <String, Object?>{
            'durationMs': _chatOpenInitStopwatch.elapsedMilliseconds,
            'count': 1,
          },
        );
        _tryMarkChatOpenEnriched();
      }
    });
    _scheduleDeferredHistoryVerification(generation);
  }
~~~

36. [_ChatState._scheduleDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:7900>)，原文件 lib/src/chat.dart，7900–7983 行。

~~~dart
/// 首帧前只展示本地 SDK 快照。首帧稳定后由统一 Coordinator 负责云端
  /// 校验、重试和 gap repair；这里不再根据会话预览决定是否同步。
  void _scheduleDeferredHistoryVerification(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _chatOpenPhaseGeneration ||
          !_isCurrentConversation(_resolvedConversationID())) {
        return;
      }
      // DIAG: 首帧稳定后 dump 当前会话元信息 + IM06 scope 状态。
      // 目的：让日志能精准关联到用户看到的会话（如"无边心是岸"）。
      try {
        final convID = _getConvID()?.trim() ?? '';
        final convType = _getConvType();
        final peerID = convType == ConvType.group
            ? (_conversation.groupID?.trim() ?? '')
            : (_conversation.userID?.trim() ?? '');
        final displayName = _conversation.showName?.trim() ??
            widget.selectedConversation.showName?.trim() ??
            '';
        final globalModel = serviceLocator<TUIChatGlobalModel>();
        ChatHistoryTrace.log(
          'diag_chat_open',
          conversationID: convID,
          extras: <String, Object?>{
            'convType': convType.name,
            'peerID': peerID,
            'displayName': displayName,
            'openGeneration': generation,
            'im06ScopeConfigured': globalModel.im06WriterScopeConfigured,
            'im06ScopeOwnerUserID': globalModel.im06WriterOwnerUserID ?? '',
            'im06AccountGen': globalModel.im06WriterAccountGeneration ?? -1,
            'im06DomainGen': globalModel.im06WriterDomainGeneration ?? -1,
          },
        );
      } catch (_) {
        // 诊断日志失败不影响主链路。
      }
      // The remote gate protects only the route's first frame. Release it
      // independently from scroll position so an early upward gesture can
      // always fall through from the local SDK cache to cloud pagination.
      _chatController.model?.allowRemoteHistoryAfterFirstFrame();
      // History verification is the only automatic cloud history task after
      // the first frame. Older group history is loaded only when the user
      // scrolls upward; do not proactively backfill a time window.
      final conversationKey = _getConvID()?.trim() ?? '';
      if (conversationKey.isEmpty) {
        return;
      }
      final globalModel = serviceLocator<TUIChatGlobalModel>();
      final completeLocalWindow =
          ConversationPreviewHistorySync.isCompleteOpenHistoryWindow(
        globalModel: globalModel,
        conversationKey: conversationKey,
      );
      // Thin snapshots need history just as urgently as empty ones. Only a
      // complete first window can defer verification without delaying reveal.
      final previewAhead = ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
        preview: _conversation.lastMessage,
        cached: globalModel.rawMessageList(conversationKey) ?? const <V2TimMessage>[],
      );
      final delay = completeLocalWindow && !previewAhead
          ? const Duration(milliseconds: 700)
          : Duration.zero;
      final verification = _runDeferredHistoryVerification(
        generation: generation,
        conversationKey: conversationKey,
        delay: delay,
        logTrace: ChatOpenPerfLog.captureCurrent(
          conversationKey: conversationKey,
        ),
      );
      // Media prefetch runs after history verification so it cannot compete
      // with the first cloud recovery request for the same conversation.
      unawaited(verification.whenComplete(() {
        if (!mounted ||
            generation != _chatOpenPhaseGeneration ||
            !_isCurrentConversation(_resolvedConversationID())) {
          return;
        }
        unawaited(_prefetchMediaByType());
      }));
    });
  }
~~~

37. [_ChatState._runDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8023>)，原文件 lib/src/chat.dart，8023–8041 行。

~~~dart
Future<void> _runDeferredHistoryVerification({
    required int generation,
    required String conversationKey,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
  }) async {
    final key = '$generation|$conversationKey';
    if (!_pendingDeferredHistoryVerifications.add(key)) return;
    try {
      await _performDeferredHistoryVerification(
        generation: generation,
        conversationKey: conversationKey,
        delay: delay,
        logTrace: logTrace,
      );
    } finally {
      _pendingDeferredHistoryVerifications.remove(key);
    }
  }
~~~

38. [_ChatState._performDeferredHistoryVerification](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8043>)，原文件 lib/src/chat.dart，8043–8160 行。

~~~dart
Future<void> _performDeferredHistoryVerification({
    required int generation,
    required String conversationKey,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted ||
        generation != _chatOpenPhaseGeneration ||
        !_isCurrentConversation(_resolvedConversationID())) {
      return;
    }
    // P1-1: 软 TTL — 同会话 N 秒内已 verify 过 → 直接 outcome=verified 跳过。
    // 不影响切到其它会话再切回来的场景（TTL 过期后重新 verify）。
    // 使用开区间：now - lastAt ≤ ttlMs 时跳过。
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAt = _lastCloudVerifyAtMs[conversationKey] ?? 0;
    final previewAhead = await _conversationPreviewAheadOfHistory();
    if (!mounted || generation != _chatOpenPhaseGeneration) return;
    final resetService = ChatLatestWindowResetService.instance;
    if (resetService.needsLatestWindowReset(conversationKey) ||
        resetService.isResetInFlight(conversationKey)) {
      // A real reconnect invalidated this conversation's latest window. The
      // reset service owns the cloud request; neither the stale verify TTL
      // nor an ordinary verify pass may run alongside it.
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_deferred_done',
        conversationID: conversationKey,
        extras: <String, Object?>{'outcome': 'latest_window_reset_owner'},
      );
      return;
    }
    if (!previewAhead && lastAt > 0 && now - lastAt <= _cloudVerifySoftTtlMs) {
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_soft_skip',
        conversationID: conversationKey,
        extras: <String, Object?>{
          'ageMs': now - lastAt,
          'ttlMs': _cloudVerifySoftTtlMs,
        },
      );
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_deferred_done',
        conversationID: conversationKey,
        extras: <String, Object?>{'outcome': 'soft_ttl_skip'},
      );
      return;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    while (globalModel.isChatListUserScrolling ||
        globalModel.getMessageListPosition(_resolvedConversationID()) !=
            HistoryMessagePosition.bottom) {
      ChatHistoryTrace.log(
        'chat_open_cloud_verify_requeued_by_user_state',
        conversationID: conversationKey,
      );
      // Keep exactly one bounded retry alive while this route is current.
      // Returning to the newest edge will eventually run verification; if the
      // user keeps reading older history, explicit pagination remains enabled.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted ||
          generation != _chatOpenPhaseGeneration ||
          !_isCurrentConversation(_resolvedConversationID())) return;
    }
    ChatOpenPerfLog.mark(
      'chat_open_cloud_verify_deferred_start',
      conversationID: conversationKey,
      extras: <String, Object?>{
        'rawCount': globalModel.rawMessageCount(conversationKey),
        'mayHaveOlder': globalModel.mayHaveOlderHistory(conversationKey),
      },
      trace: logTrace,
    );
    final verificationIdentity = SessionIdentityService.instance.capture();
    final latestPreview = await _fetchConversationPreviewLastMessage();
    if (!mounted ||
        generation != _chatOpenPhaseGeneration ||
        !SessionIdentityService.instance.isCurrent(verificationIdentity)) return;
    final verificationConversation =
        V2TimConversation.fromJson(_conversation.toJson())
          ..lastMessage = latestPreview;
    final outcome =
        await ConversationHistorySyncCoordinator.instance.verifyAfterFirstFrame(
      conversation: verificationConversation,
      reason: 'chat_open',
      delay: Duration.zero,
      logTrace: logTrace,
      boundOpenGeneration: _viewportOpenGeneration,
    );
    // P1-1: 验证完成 → 记 lastAt，下一次进入走软 TTL。
    // 只有 server sync 已完成且传输在线时，这次 verified 才有资格写 TTL；
    // 握手/漫游同步期间的 CLOUD 结果可能是本地降级，不能补发认证。
    if (mounted &&
        generation == _chatOpenPhaseGeneration &&
        outcome == ConversationHistorySyncOutcome.verified &&
        ChatHistoryVerificationGate.canMarkCloudVerifiedNow()) {
      _lastCloudVerifyAtMs[conversationKey] =
          DateTime.now().millisecondsSinceEpoch;
    }
    // DIAG: 校验出口 — 记录 outcome / SDK commit 后是否真的写入了 messageList。
    ChatHistoryTrace.log(
      'diag_verify_outcome',
      conversationID: conversationKey,
      extras: <String, Object?>{
        'outcome': outcome.name,
        'rawCountAfter': globalModel.rawMessageCount(conversationKey),
        'mayHaveOlderAfter': globalModel.mayHaveOlderHistory(conversationKey),
        'haveMoreData': _chatController.model?.haveMoreData ?? false,
      },
    );
    ChatHistoryTrace.log(
      'chat_open_cloud_verify_deferred_done',
      conversationID: conversationKey,
      extras: <String, Object?>{'outcome': outcome.name},
    );
  }
~~~

39. [_ChatState._schedulePostOpenTasks](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:8242>)，原文件 lib/src/chat.dart，8242–8443 行。

~~~dart
void _schedulePostOpenTasks() {
    if (_openLifecycle.postOpenTasksScheduled) return;
    final taskGeneration = _openLifecycle.beginPostOpenTasks();
    final schedulerGeneration = _postOpenScheduler.beginRun();
    final scheduledConversationId = _resolvedConversationID();
    final scheduledConvKey = _getConvID()?.trim() ?? scheduledConversationId;

    bool canRun() {
      return taskGeneration == _openLifecycle.postOpenTasksGeneration &&
          _isCurrentConversation(scheduledConversationId);
    }

    Future<void> runTasks() async {
      if (!canRun()) return;
      await _openLifecycle.waitForOpenHistoryPreparationGate();
      if (!canRun()) return;
      ChatOpenPerfLog.mark(
        'post_open_tasks_run',
        extras: <String, Object?>{'isGroup': _getConvType() == ConvType.group},
      );
      ChatJitterDiag.log(
        'post_open_tasks',
        extras: const <String, Object?>{'source': 'route_animation_or_delay'},
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'local_foundation',
        delay: Duration.zero,
        canRun: canRun,
        task: () async {
          await Future.wait<void>(<Future<void>>[
            _loadChatBackground(),
            _loadChatLocalDraft(),
            _hydrateGroupDisplayForOpen(),
            _resolveImGroupIdAfterOpen(),
          ]);
          if (canRun()) {
            await _prepareOfficialAccountChat();
          }
          if (canRun() && _getConvType() == ConvType.c2c) {
            await Future.wait<void>(<Future<void>>[
              _loadPeerFaceUrl(),
              _loadPeerLocalProfile(),
            ]);
            if (canRun()) {
              _schedulePeerMessagePermissionSync(forceNetwork: true);
            }
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'history_enrichment',
        delay: ChatPostOpenScheduler.p1Delay,
        canRun: canRun,
        task: () => _runOpenHistoryEnrichment(scheduledConvKey, canRun: canRun),
      );
      if (_getConvType() == ConvType.group) {
        final groupId = ChatIdFormat.normalizeGroupId(
          widget.selectedConversation.groupID,
        );
        if (groupId.isNotEmpty) {
          // 与进页成员最小集错峰；本地已 seed 时只做权威补证。
          final muteGeneration = _openLifecycle.muteFetchGeneration;
          _postOpenScheduler.schedule(
            generation: schedulerGeneration,
            key: 'mute_status',
            delay: ChatPostOpenScheduler.muteNetworkDelay,
            canRun: canRun,
            task: () async {
              if (!mounted ||
                  muteGeneration != _openLifecycle.muteFetchGeneration) {
                return;
              }
              ChatOpenPerfLog.mark('mute_network_fetch_start');
              await _fetchAndStoreBackendMuteStatus(groupId);
              if (canRun()) {
                _markChatOpenBackgroundPart(
                  part: 'mute',
                  generation: taskGeneration,
                );
              }
            },
          );
        } else {
          _markChatOpenBackgroundPart(part: 'mute', generation: taskGeneration);
        }
      }
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'group_metadata',
        // Group metadata is enrichment, never a chat first-frame dependency.
        delay: ChatPostOpenScheduler.idleDelay,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          if (_getConvType() != ConvType.group) {
            _markChatOpenBackgroundPart(
              part: 'c2c',
              generation: taskGeneration,
            );
            return;
          }
          await _runOpenGroupMetadataEnrichment(
            generation: taskGeneration,
            canRun: canRun,
          );
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'business_enrichment',
        delay: const Duration(milliseconds: 650),
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          await Future.wait<void>(<Future<void>>[
            _loadGroupGameStatus(),
            _loadAgentRebateIdentity(),
            _loadSangongAgentEntry(),
            _loadGroupLiveCurrent(),
          ]);
          if (canRun()) {
            _markChatOpenBackgroundPart(
              part: 'group_game',
              generation: taskGeneration,
            );
            if (_getConvType() == ConvType.group) {
              _startGroupLiveCurrentPoll();
            }
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'idle_enrichment',
        delay: ChatPostOpenScheduler.idleDelay,
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun()) return;
          final idleTasks = <Future<void>>[
            DiceAssetWarmup.warm(context),
            _retryWalletCardsForConversation(
              source: WalletCardSendSource.autoRetry,
            ),
            if (!CallLifecycleService.instance.isInActiveCall)
              SoundPlayer.ensurePlaybackReady(),
          ];
          await Future.wait<void>(idleTasks);
          if (!canRun()) return;
          if (!_hasVisibleHistoryMessages()) {
            await _reloadChatHistoryIfEmpty(reason: 'post_open');
          }
        },
      );
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'group_feature_idle',
        delay: const Duration(milliseconds: 900),
        priority: ChatTaskPriority.background,
        canRun: canRun,
        task: () async {
          if (!canRun() || _getConvType() != ConvType.group) return;
          // Member verification and feature APIs share an idle lane and are
          // intentionally independent of chat history/readback. Their
          // failures must not delay the message list or trigger a reload.
          if (canRun()) {
            await _verifyGroupMembershipOnOpen();
          }
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation != null && !animation.isCompleted) {
        void listener(AnimationStatus status) {
          if (status != AnimationStatus.completed &&
              status != AnimationStatus.dismissed) {
            return;
          }
          _removeRouteTransitionListener(animation, listener);
          if (status == AnimationStatus.completed) {
            unawaited(runTasks());
          }
        }

        _addRouteTransitionListener(animation, listener);
        return;
      }
      _postOpenScheduler.schedule(
        generation: schedulerGeneration,
        key: 'route_fallback',
        delay: ChatPostOpenScheduler.routeFallbackDelay,
        canRun: canRun,
        task: runTasks,
      );
    });
  }
~~~

40. [_ChatState.initState](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9199>)，原文件 lib/src/chat.dart，9199–9614 行。

~~~dart
@override
  void initState() {
    super.initState();
    // The resolved SDK conversation id can become available after the first
    // history frame. Keep the widget identity tied to the route entry so that
    // that metadata update does not remount the entire message surface.
    final entryConversationId = _getConvID()?.trim() ?? '';
    _stableChatWidgetKey = entryConversationId.isNotEmpty
        ? entryConversationId
        : 'chat_${widget.selectedConversation.type}_'
            '${widget.selectedConversation.userID ?? widget.selectedConversation.groupID ?? widget.selectedConversation.conversationID}';
    PerfTimeline.instant('chat_page_open', arguments: {
      'conversationId': widget.selectedConversation.conversationID,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PerfTimeline.instant('chat_page_first_frame', arguments: {
          'conversationId': _resolvedConversationID(),
        });
      }
    });
    // Pipeline [4] - init_begin：ChatState initState 入口（用 widget 原 conv 拼 key）
    final initPipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: widget.selectedConversation.conversationID,
      userId: widget.selectedConversation.userID,
      groupId: widget.selectedConversation.groupID,
    );
    ChatPipelineClock.instance.trace(initPipelineKey, 'init_begin');
    WidgetsBinding.instance.addObserver(this);
    _chatOpenInitStopwatch.start();
    _c2cPermission.onTransitionToBlocked = _syncInFlightOutgoingOnC2cBlocked;
    _groupLiveState.addListener(_onGroupLiveStateChanged);
    GroupLiveIndexStore.instance.addListener(_onGroupLiveIndexStoreChanged);
    GroupLocalStore.instance.commitListenable.addListener(_onGroupStoreCommit);
    GroupLocalStore.instance.cacheHydration.addListener(_onGroupCacheHydrated);
    GroupMemberLocalStore.instance.commitListenable
        .addListener(_onGroupMemberStoreCommit);
    _openLifecycle.clearedExternalEntryOnDeactivate = false;
    ConversationDeletedBus.instance.revision.addListener(
      _onConversationDeletedBus,
    );
    _conversation = _normalizedConversationForChat(widget.selectedConversation);
    _applyCachedAgentRebateIdentityForCurrentGroup();
    _applyCachedGroupGameForCurrentGroup();
    _beginChatOpenGeneration();
    _firstViewportWindowLogged = false;
    _chatOpenPhaseGeneration = _openLifecycle.beginConversation();

    if (_getConvType() == ConvType.c2c) {
      final peerId = widget.selectedConversation.userID?.trim() ?? '';
      if (peerId.isNotEmpty) {
        _peerLocalProfile = UserProfileLocalService.instance.readCached(peerId);
        final cachedFace = UserAvatarHelper.usableAvatarOrEmpty(
          _peerLocalProfile?.avatarUrl,
        );
        if (cachedFace.isNotEmpty) {
          _resolvedPeerFaceUrl = cachedFace;
          _resolvedPeerFaceUrlForId = peerId;
          _conversation.faceUrl = cachedFace;
          widget.selectedConversation.faceUrl = cachedFace;
        }
      }
    }
    final openedConversationId = _resolvedConversationID();
    _pageScope = ChatPageScope.instance.attach(
      conversationId: openedConversationId,
      accountGeneration: SessionIdentityService.instance.generation,
    );
    final viewportKey = _getConvID()?.trim().isNotEmpty == true
        ? _getConvID()!.trim()
        : openedConversationId;
    if (viewportKey.isNotEmpty) {
      ChatViewportCollection.instance.attach(
        conversationKey: viewportKey,
        identity: SessionIdentityService.instance.capture(),
        attachSource: 'chat_init',
      );
      _viewportConversationKey = viewportKey;
      _viewportOpenGeneration = ChatViewportCollection.instance.openGeneration;
    }
    ChatImageMessagePrefetch.bindPageScope(_pageScope);
    final openConvKey = _getConvID()?.trim() ?? '';
    final openPreview = widget.selectedConversation.lastMessage;
    final openGlobal = serviceLocator<TUIChatGlobalModel>();
    final openWarm = openConvKey.isEmpty
        ? const <V2TimMessage>[]
        : (openGlobal.messageListMap[openConvKey] ?? const <V2TimMessage>[]);
    final openWarmNewest =
        openWarm.isEmpty ? 0 : (openWarm.first.timestamp ?? 0);
    final openWarmOldest =
        openWarm.isEmpty ? 0 : (openWarm.last.timestamp ?? 0);
    ChatDiagLog.log(
      'ChatHistory',
      'chat_open',
      conversationID: openedConversationId,
      extras: <String, Object?>{
        'convKey': openConvKey,
        'type': _getConvType().name,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'hasLastMessage': openPreview != null,
        'lastMsgId': openPreview?.msgID?.trim() ?? '',
        'cachedRaw':
            openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
        'initialLoaded': openConvKey.isEmpty
            ? false
            : openGlobal.hasInitialHistoryLoaded(openConvKey),
        'warmNewestTs': openWarmNewest,
        'warmOldestTs': openWarmOldest,
        'warmNewestId':
            openWarm.isEmpty ? '' : (openWarm.first.msgID?.trim() ?? ''),
        'rawAlsoCached':
            openedConversationId.isEmpty || openedConversationId == openConvKey
                ? 0
                : openGlobal.rawMessageCount(openedConversationId),
      },
    );
    ChatOpenPerfLog.mark(
      'chat_init_state',
      conversationID:
          openConvKey.isNotEmpty ? openConvKey : openedConversationId,
      extras: <String, Object?>{
        'type': _getConvType().name,
        'entryUnread': widget.entryUnreadCount ?? 0,
        'cachedRaw':
            openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
        'initialLoaded': openConvKey.isEmpty
            ? false
            : openGlobal.hasInitialHistoryLoaded(openConvKey),
        'warmNewestTs': openWarmNewest,
        'isGroup': _getConvType() == ConvType.group,
      },
    );
    ChatJitterDiag.markChatOpen(
      openConvKey.isNotEmpty ? openConvKey : openedConversationId,
    );
    ChatResourceSample.resetForChatOpen(
      openConvKey.isNotEmpty ? openConvKey : openedConversationId,
    );
    // 首屏窗口已在内存时立刻尝试 100/500/1000 节点（不等上翻）。
    final openCount =
        openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey);
    if (openCount > 0) {
      ChatResourceSample.onRawMessageCount(openCount);
    }
    ConversationUnreadClearService.beginConversationChatSession(
      openedConversationId,
    );
    // Deep link / push / restart 这类入口绕过了会话列表点击预热；
    // 在 initState 同步注册同样的 in-flight 任务，让首帧尽量命中本地缓存。
    // in-flight 由 ChatOpenViewportCoordinator 保证去重，与 app_chat_route
    // 的 await 预热天然合并。搜索/找消息场景走的是另一个特殊路径，跳过。
    if (widget.initFindingMsg == null &&
        widget.searchJumpAnchor == null &&
        openedConversationId.isNotEmpty &&
        ConversationPeekService.canPeek(_conversation)) {
      unawaited((() async {
        await ChatOpenViewportCoordinator.instance.prepareOpenViewport(
          conversation: _conversation,
          source: 'chat_init',
        );
        if (!mounted) {
          return;
        }
        _onChatGlobalModelChanged();
      })());
    }
    if (openedConversationId.isNotEmpty) {
      ActiveChatRegistry.instance.enter(
        openedConversationId,
        conversationType: _getConvType(),
      );
      ExternalChatEntryService.instance.claimActiveChatSource(
        _externalEntrySourceToken,
      );
    }
    DeviceSyncService.instance.prepareForChatNavigation();
    DeviceSyncService.instance.beginForegroundMediaWork(
      reason: 'chat_open',
      duration: const Duration(seconds: 3),
    );
    _cachedHeaderFaceUrl = _conversation.faceUrl;
    _cachedHeaderShowName = _conversation.showName;
    if (_getConvType() == ConvType.group) {
      _logGroupHeaderAvatarSource(
        source: 'selected_conversation',
        currentFaceUrl: '',
        candidateFaceUrl: _conversation.faceUrl ?? '',
        applied: true,
      );
    }
    _applyInitialC2cPermissionHint(resetIfMissing: true);
    _seedGroupDisplayFromMemory();
    _armOpenGroupNoticeAfterTransition();
    _syncChatHeaderState(notify: false);
    _seedGroupLiveFromIndex();
    _syncChatTopFixState(notify: false);
    _stopGroupLiveCurrentPoll();
    _clearMountedDisplayListCache();
    if (openedConversationId.isNotEmpty) {
      unawaited(
        ImChatNotificationClearService.instance
            .clearChatNotificationsForConversation(
          openedConversationId,
          reason: 'chat_open',
        ),
      );
    }
    _schedulePostOpenFailedMessageRetry();
    final convId = _getConvID()?.trim() ?? '';
    if (convId.isNotEmpty) {
      PushFocusService.instance.enterChat(
        conversationType: _getConvType(),
        peerOrGroupId: convId,
      );
    }
    // Pipeline [5] - init_done：ChatState initState 同步段结束
    ChatPipelineClock.instance.trace(
      _resolvedConversationID(),
      'init_done',
      elapsedMs: _chatOpenInitStopwatch.elapsedMilliseconds,
    );
    // 生命周期回调可能在路由切换后才返回；草稿清理必须绑定本次打开的
    // 会话，不能在回调时重新取“当前会话”，否则 A 发送成功会清掉 B 草稿。
    final lifecycleConversationId = _resolvedConversationID();
    _chatLifeCycle = ChatLifeCycle(
      newMessageWillMount: (V2TimMessage message) async {
        _handleGroupLiveIncomingMessage(message);
        unawaited(
          MessageMediaMetadataStore.instance.upsertFromMessage(message),
        );
        if (_getConvType() == ConvType.c2c) {
          ChatImageMessagePrefetch.prefetchThumbnailForMessage(message);
        }
        if (ChatImageMessagePrefetch.needsOnlineUrlResolution(
          message,
          includeSelf: true,
        )) {
          unawaited(
            ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(
              <V2TimMessage>[message],
              includeSelf: true,
            ),
          );
        }
        return message;
      },
      didGetHistoricalMessageList: (List<V2TimMessage> messageList) async {
        _completeChatOpenInitStage(
          _ChatOpenInitStage.sdkReady,
          count: messageList.length,
          source: 'sdk_history_callback',
        );
        // Media metadata, sticker scans and image prefetch are enrichment.
        // Keep the history callback limited to the authoritative list commit.
        _pendingOpenHistoryMediaEnrichment = messageList;
        // C2C/group histories can contain both the server lk_call terminal
        // message and our local terminal projection for the same callId.
        // Normalize call candidates on every conversation type so those two
        // sources converge before the first history frame is mounted.
        final normalized = CallBubbleDedupe.normalizeCallHistoryMessages(
          messageList,
          preserveTipIdentity: true,
        );
        final deduped = TUIChatGlobalModel.dedupeMessages(normalized);
        _completeChatOpenInitStage(
          _ChatOpenInitStage.historyReady,
          count: deduped.length,
          source: 'sdk_history_commit',
        );
        _markChatOpenHistoryReady();
        RegExpProbe.dump(reason: 'didGetHistoricalMessageList');
        return deduped;
      },
      messageShouldMount: _messageShouldMountInHistory,
      messageListShouldMount: _normalizeMessageListForMount,
      messageDidSend: (sendMsgRes) {
        final conversationId = lifecycleConversationId.isNotEmpty
            ? lifecycleConversationId
            : _resolvedConversationID();
        if (sendMsgRes.code == 0 && conversationId.isNotEmpty) {
          unawaited(_clearChatLocalDraftAfterSend(conversationId));
        }
        // 己方发送不走通知侧 patch；SDK onConversationChanged 若因群 ID
        // 形态/非成员门禁落库失败，列表预览会空，再进页会误标 empty-loaded。
        if (sendMsgRes.code == 0 && conversationId.isNotEmpty) {
          final sent = sendMsgRes.data;
          OutgoingVisibleProbe.log(
            'send_preview_patch_start',
            conversationID: conversationId,
            message: sent,
            extras: <String, Object?>{
              'hasData': sent != null,
              'code': sendMsgRes.code,
            },
          );
          unawaited(
            () async {
              // 好友刚通过时，本地乐观会话与 SDK 建会话存在竞态。己方首条
              // 消息又不会走 onRecvNewMessage，因此不能只等待 SDK 的
              // onConversationChanged；否则返回列表后可能一直没有该会话。
              if (sent != null) {
                unawaited(
                  MessageMediaMetadataStore.instance.upsertFromMessage(sent),
                );
                if (ChatImageMessagePrefetch.needsOnlineUrlResolution(
                  sent,
                  includeSelf: true,
                )) {
                  unawaited(
                    ChatImageMessagePrefetch.resolveOnlineUrlsForMessages(
                      <V2TimMessage>[sent],
                      includeSelf: true,
                    ),
                  );
                }
                await ChatSessionController.instance
                    .patchConversationLastMessage(
                  conversationID: conversationId,
                  message: sent,
                );
                OutgoingVisibleProbe.log(
                  'send_preview_patch_done',
                  conversationID: conversationId,
                  message: sent,
                );
              } else {
                // Rare SDK success responses without message data cannot be
                // patched optimistically. Use one authoritative fallback.
                await ChatSessionController.instance.refreshConversationItem(
                  conversationId,
                );
              }
              // The optimistic preview patch already queries the SDK once
              // and can create a local shell when the SDK conversation is
              // still racing the first send. The ordinary SDK conversation
              // callback supplies the later authoritative metadata; issuing
              // another query plus RefreshBus query here tripled the work for
              // every successful send.
            }()
                .catchError((Object error, StackTrace stack) {
              OutgoingVisibleProbe.log(
                'send_preview_patch_error',
                conversationID: conversationId,
                extras: <String, Object?>{'error': '$error'},
              );
            }),
          );
        }
      },
    );
    // Telegram-style stable surface: the real chat tree exists on the first
    // route frame. History readiness is represented inside that tree.
    _mountStableChatBody(openConvKey: openConvKey);
    _ensureMessageItemBuilder();
    _chatGlobalModel = serviceLocator<TUIChatGlobalModel>();
    _chatGlobalModel!.addListener(_onChatGlobalModelChanged);
    _conversationViewModel.addListener(_onConversationViewModelChanged);
    PeerProfileRefreshBus.instance.revision.addListener(_onPeerProfileRefresh);
    serviceLocator<TUIFriendShipViewModel>().addListener(
      _onFriendshipModelChanged,
    );
    GroupMemberStore.instance.addListener(_onGroupMemberStoreChanged);
    unawaited(_loadPeerFaceUrl());
    unawaited(_loadPeerLocalProfile());
    WalletOrderEvents.chatCardPayload.addListener(_onWalletChatCard);
    WalletOrderEvents.chatCardSendFailedPayload.addListener(
      _onWalletChatCardSendFailed,
    );
    CallResultRepository.instance.revision.addListener(
      _onCallResultRepositoryChanged,
    );
    ChatHistoryRefreshBus.instance.revision.addListener(
      _onExternalChatHistoryRefreshRequested,
    );
    GroupNoticeRefreshBus.instance.lastRefresh.addListener(
      _onGroupNoticeRefreshRequested,
    );
    GroupSyncService.instance.lastChanged.addListener(_onGroupRealtimeChanged);
    ConversationHistoryWarmScheduler.instance.pauseForActiveChat(
      reason: 'chat_open',
    );
    // 轻壳首帧就尽量带上真实聊天背景，避免转场结束后再换底。
    unawaited(_prefetchShellBackground());
    _schedulePostOpenTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ChatOpenPerfLog.mark(
        'chat_first_frame',
        conversationID:
            openConvKey.isNotEmpty ? openConvKey : openedConversationId,
        extras: <String, Object?>{
          'rawCount':
              openConvKey.isEmpty ? 0 : openGlobal.rawMessageCount(openConvKey),
          'gateActive': _openLifecycle.openHistoryGate != null,
        },
      );
      _attachLocalSettingListener();
      _publishExternalEntryState();
      unawaited(_activatePendingExternalEntryOnInit());
      final openConvResolved = _resolvedConversationID();
      if (openConvResolved.isNotEmpty) {
        CallBubbleInsertService.instance.ensureConversationBubbles(
          openConvResolved,
          reason: 'chat_open',
        );
      }
      _schedulePeerMessagePermissionSync(
        forceNetwork: _c2cPermission.trustedInitialCanMessage,
      );
    });
    // if (IMDemoConfig.customerServiceUserList.contains(widget.selectedConversation.userID)) {
    //   TencentCloudChatCustomerServicePlugin.sendCustomerServiceStartMessage(_chatController.sendMessage);
    // }
  }
~~~

41. [_ChatState.deactivate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9674>)，原文件 lib/src/chat.dart，9674–9703 行。

~~~dart
@override
  void deactivate() {
    final route = ModalRoute.of(context);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final leaveId = _resolvedConversationID();
    OutgoingVisibleProbe.log(
      'chat_deactivate',
      conversationID: leaveId,
      extras: <String, Object?>{
        'routeCurrent': route?.isCurrent,
        'mediaPreview': globalModel.isMediaPreviewOverlayOpen,
        'walletOverlay': globalModel.isWalletOverlayOpen,
        'pickerOverlay': globalModel.isMediaPickerOverlayOpen,
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(leaveId),
        ),
      },
    );
    if (route != null &&
        !route.isCurrent &&
        !globalModel.isMediaPreviewOverlayOpen &&
        !globalModel.isWalletOverlayOpen &&
        !globalModel.isMediaPickerOverlayOpen) {
      // 被资料/代理页盖住：栈内仍开着 Chat，只标不可见，不 leave、不清未读、不交还列表。
      ActiveChatRegistry.instance.updateRouteVisible(false);
      _dismissChatInput();
      unawaited(_persistChatLocalDraft());
    }
    super.deactivate();
  }
~~~

42. [_ChatState.dispose](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:9779>)，原文件 lib/src/chat.dart，9779–9947 行。

~~~dart
@override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _mobileCommitGuard.advancePage();
    _chatOpenGeneration++;
    ChatImageMessagePrefetch.cancelForPageDispose();
    ChatPageScope.instance.invalidate(_pageScope);
    _pageScope = null;
    final viewportKey = _viewportConversationKey;
    if (viewportKey != null && viewportKey.isNotEmpty) {
      ChatViewportCollection.instance.detachUi(
        conversationKey: viewportKey,
        openGeneration: _viewportOpenGeneration,
      );
    }
    _pendingOpenHistoryMediaEnrichment = null;
    ConversationDeletedBus.instance.revision.removeListener(
      _onConversationDeletedBus,
    );
    // 真正离页时再腾出气泡位图并预热列表头像（勿放 deactivate：进资料页也会覆盖路由）。
    _cancelChatOpenSideEffects(reason: 'chat_dispose');
    _clearRouteTransitionListeners();
    final gateConv = _openLifecycle.openHistoryGateConvKey;
    if (gateConv.isNotEmpty) {
      ChatHistoryOpenLayoutReady.cancel(gateConv);
    }
    _openLifecycle.resetForDispose();
    _releaseBubbleCacheAndWarmListAvatar();
    ChatJitterDiag.logImageCache('chat_dispose');
    // Persist the draft before handing the conversation back to the list.
    // The old fire-and-forget ordering let the list refresh against the
    // previous snapshot, so the draft disappeared until the chat was opened
    // again and loaded directly from the draft store.
    final draftPersist = _persistChatLocalDraft();
    _draft.dispose();
    _headerState.dispose();
    _groupLiveState.removeListener(_onGroupLiveStateChanged);
    GroupLiveIndexStore.instance.removeListener(_onGroupLiveIndexStoreChanged);
    GroupLocalStore.instance.commitListenable.removeListener(
      _onGroupStoreCommit,
    );
    GroupLocalStore.instance.cacheHydration.removeListener(
      _onGroupCacheHydrated,
    );
    GroupMemberLocalStore.instance.commitListenable
        .removeListener(_onGroupMemberStoreCommit);
    _stopGroupLiveCurrentPoll();
    _groupLiveState.dispose();
    _topFixState.dispose();
    _peerPermissionSyncDebounce?.cancel();
    _c2cPermission.nextRequestSeq();
    _c2cPermission.dispose();
    _lastCloudVerifyAtMs.clear();
    final convType = _getConvType();
    final convId = _getConvID()?.trim() ?? '';
    final leaveConversationId = _resolvedConversationID();
    ConversationHistorySyncCoordinator.instance.cancelConversation(
      leaveConversationId,
    );
    OutgoingVisibleProbe.log(
      'chat_dispose',
      conversationID: leaveConversationId,
      extras: OutgoingVisibleProbe.trackedInList(
        serviceLocator<TUIChatGlobalModel>().rawMessageList(
          leaveConversationId.isNotEmpty ? leaveConversationId : convId,
        ),
      ),
    );
    if (leaveConversationId.isNotEmpty) {
      unawaited(
        ConversationUnreadClearService.finalizeConversationLeaveOnce(
          conversationID: leaveConversationId,
          lastMessageId: _lastVisibleMessageIdForLeave(),
          entryUnreadCount: widget.entryUnreadCount ?? 0,
          markViewModelReadLocally:
              _conversationViewModel.markConversationReadLocally,
        ),
      );
    }
    if (convId.isNotEmpty) {
      PushFocusService.instance.leaveChat(
        chatType: convType == ConvType.group ? 'group' : 'c2c',
        peerOrGroupId: convId,
      );
    }
    // Fix unread-list-doesnt-update-on-return: ensure the registry flushes
    // before any later dispose step can throw and orphan _conversationId.
    // When the route leaves, downstream UI projection would otherwise stay
    // stuck behind `deferTabStoreProjectionWhileActiveChat` until the next
    // chat_leave flush, but that flush never comes when dispose itself is
    // the only signal that the chat is gone.
    if (leaveConversationId.isNotEmpty) {
      ConversationDraftLeaveTrace.focus(leaveConversationId);
      ConversationDraftLeaveTrace.stage(
        'chat_pop',
        conversationId: leaveConversationId,
        extras: const <String, Object?>{'hasOpenChat': true},
      );
      ActiveChatRegistry.instance.leave(leaveConversationId);
      unawaited(
        draftPersist.whenComplete(() {
          _flushConversationListUiAfterChatLeave(
            reason: 'chat_dispose_leave_after_draft',
            leftConversationId: leaveConversationId,
          );
        }),
      );
    }
    _chatGlobalModel?.removeListener(_onChatGlobalModelChanged);
    _chatGlobalModel = null;
    _clearMountedDisplayListCache();
    if (!_openLifecycle.clearedExternalEntryOnDeactivate) {
      _clearExternalEntryState();
    }
    DeviceSyncService.instance.onChatClosed();
    DeviceSyncService.instance.endForegroundMediaWork(
      reason: 'chat_open_dispose',
      cooldown: const Duration(seconds: 3),
    );
    _dismissChatInput();
    _conversationViewModel.removeListener(_onConversationViewModelChanged);
    PeerProfileRefreshBus.instance.revision.removeListener(
      _onPeerProfileRefresh,
    );
    serviceLocator<TUIFriendShipViewModel>().removeListener(
      _onFriendshipModelChanged,
    );
    GroupMemberStore.instance.removeListener(_onGroupMemberStoreChanged);
    WalletOrderEvents.chatCardPayload.removeListener(_onWalletChatCard);
    WalletOrderEvents.chatCardSendFailedPayload.removeListener(
      _onWalletChatCardSendFailed,
    );
    CallResultRepository.instance.revision.removeListener(
      _onCallResultRepositoryChanged,
    );
    ChatHistoryRefreshBus.instance.revision.removeListener(
      _onExternalChatHistoryRefreshRequested,
    );
    GroupNoticeRefreshBus.instance.lastRefresh.removeListener(
      _onGroupNoticeRefreshRequested,
    );
    GroupSyncService.instance.lastChanged.removeListener(
      _onGroupRealtimeChanged,
    );
    _reconnectRecoveryTimer?.cancel();
    _groupMemberAvatarRefreshDebounce?.cancel();
    _postOpenScheduler.dispose();
    _releaseSangongRealtimeSubscription();
    _localSetting?.removeListener(_onLocalSettingChanged);
    // registry leave + UI flush already ran earlier (chat_dispose_leave_early);
    // the release handle here only schedules background post-pop work.
    final releaseConvId = leaveConversationId;
    if (releaseConvId.isNotEmpty) {
      ChatSessionController.instance.schedulePostPopCoalesceWindow(
        conversationID: releaseConvId,
      );
      ConversationHistoryWarmScheduler.instance.scheduleReleaseAfterChatLeave(
        releaseConvId,
      );
    }
    _chatController.model?.disableVoiceAutoPlayChain();
    unawaited(SoundPlayer.stop());
    OrphanOverlayGuard.scheduleCleanup(
      reason: 'chat_leave_dispose',
      hideLoading: true,
    );
    super.dispose();
  }
~~~

43. [_ChatState.didUpdateWidget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/chat.dart:10653>)，原文件 lib/src/chat.dart，10653–10781 行。

~~~dart
@override
  void didUpdateWidget(Chat oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConversationID = _resolvedConversationID(
      oldWidget.selectedConversation,
    );
    final newConversationID = _resolvedConversationID(
      widget.selectedConversation,
    );
    if (oldConversationID != newConversationID) {
      final oldInputText =
          _chatController.textFieldController?.textEditingController?.text ??
              '';
      if (!_draft.shouldSuppressLifecyclePersist &&
          oldConversationID.isNotEmpty) {
        _draft.cancelDebounce();
        unawaited(
          _persistChatLocalDraftText(
            oldInputText,
            _draft.writeGeneration,
            conversationID: oldConversationID,
            enforceCurrentGeneration: false,
          ),
        );
      }
      _draft.beginConversation();
      _mobileCommitGuard.advanceConversation();
      _beginChatOpenGeneration();
      _chatOpenPhaseGeneration = _openLifecycle.beginConversation();
      _chatOpenCompletedStages.clear();
      _chatOpenBackgroundParts.clear();
      _pendingOpenHistoryMediaEnrichment = null;
      _chatOpenInitStopwatch
        ..reset()
        ..start();
      final oldGroupId = oldWidget.selectedConversation.groupID?.trim() ?? '';
      ConversationHistorySyncCoordinator.instance.cancelConversation(
        oldConversationID,
      );
      if (oldGroupId.isNotEmpty) {
        GroupMetadataRefreshCoordinator.instance.invalidate(oldGroupId);
      }
      _groupMemberCountGeneration++;
      _lastGroupMetadataRefreshAt = null;
      _clearExternalEntryState(oldConversationID);
      _openLifecycle.cancelPendingMuteFetch();
      _openLifecycle.scheduledVisibleSdkUnreadClean = false;
      _lastPublishedExternalEntryState = null;
      _chatController.model?.disableVoiceAutoPlayChain();
      unawaited(SoundPlayer.stop());
      ActiveChatRegistry.instance.enter(
        _resolvedConversationID(),
        conversationType: _getConvType(),
      );
      ConversationHistoryWarmScheduler.instance.pauseForActiveChat(
        reason: 'chat_switch',
      );
      _conversation = _normalizedConversationForChat(
        widget.selectedConversation,
      );
      _cachedHeaderFaceUrl = _conversation.faceUrl;
      _cachedHeaderShowName = _conversation.showName;
      _groupMemberCount = null;
      _groupMemberCountPinnedToLocalSnapshot = false;
      // 首屏同步：用本地缓存喂 _groupSide，避免首屏不显浮窗。
      final newGroupIdForRebate =
          widget.selectedConversation.groupID?.trim() ?? '';
      if (newGroupIdForRebate.isNotEmpty) {
        final rebateCached = AgentRebateEntryLocalStore.instance.readCachedSync(
          ownerUserId: ContactSocialCacheStore.safeLoginUserId(),
          groupId: newGroupIdForRebate,
        );
        if (rebateCached != null) {
          _groupSide.agentRebateGroupBound = rebateCached.bound;
          _groupSide.agentRebateGroupEnabled = rebateCached.enabled;
          _groupSide.agentRebateIdentityEnabled = rebateCached.isAgent;
        } else {
          _groupSide.agentRebateGroupBound = false;
          _groupSide.agentRebateGroupEnabled = false;
          _groupSide.agentRebateIdentityEnabled = false;
        }
      } else {
        _groupSide.agentRebateGroupBound = false;
        _groupSide.agentRebateGroupEnabled = false;
        _groupSide.agentRebateIdentityEnabled = false;
      }
      _groupSide.groupNoticeBanner = '';
      _openGroupNoticeAfterTransitionInFlight = null;
      // Plan 095：切会话时清空旧群的三公/游戏状态，防止旧群的网络结果
      // 晚到后把 sangongTenantId / canEditConfig 等写入新会话。
      _groupSide.clearSangongAccess();
      _groupSide.disableGroupGame();
      _applyCachedGroupGameForCurrentGroup();
      _watchingGroupLive = false;
      _groupLiveIndexFingerprint = null;
      _seedGroupDisplayFromMemory();
      _armOpenGroupNoticeAfterTransition();
      _seedGroupLiveFromIndex();
      _syncChatTopFixState();
      _stopGroupLiveCurrentPoll();
      _resolvedPeerFaceUrl = null;
      _resolvedPeerFaceUrlForId = null;
      _peerLocalProfile = null;
      _c2cPermission.canMessage = null;
      _c2cPermission.trustedInitialCanMessage = false;
      _c2cPermission.requestSeq++;
      _applyInitialC2cPermissionHint(resetIfMissing: true);
      final peer = _c2cPeerUserId();
      if (peer != null && !_c2cPermission.trustedInitialCanMessage) {
        C2cFriendMessageGuard.invalidate(peer);
      }
      _syncChatHeaderState();
      // Peer/network enrichment is restarted by the bounded post-open queue.
      _resetWalletCardState();
      _ensureMessageItemBuilder();
      _invalidateChatConfigCache();
      final newConvKey = _getConvID()?.trim() ?? '';
      _startOpenHistoryGate(newConvKey);
    }
    if (oldConversationID != newConversationID ||
        oldWidget.selectedConversation.groupID !=
            widget.selectedConversation.groupID ||
        oldWidget.selectedConversation.type !=
            widget.selectedConversation.type) {
      _openLifecycle.cancelPendingPostOpenTasks();
      _postOpenScheduler.cancelPending();
      _schedulePostOpenTasks();
    }
  }
~~~

44. [_ConversationState._scheduleViewportWarmAfterSettle](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/conversation.dart:2165>)，原文件 lib/src/conversation.dart，2165–2177 行。

~~~dart
void _scheduleViewportWarmAfterSettle({required String reason}) {
    _viewportWarmSettleTimer?.cancel();
    _viewportWarmSettleTimer = Timer(_viewportWarmSettleDelay, () {
      if (!mounted) {
        return;
      }
      if (_feedScrollController.hasClients &&
          _feedScrollController.position.isScrollingNotifier.value) {
        return;
      }
      _runViewportWarmNow(reason: reason);
    });
  }
~~~

45. [_ConversationState._runViewportWarmNow](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/conversation.dart:2179>)，原文件 lib/src/conversation.dart，2179–2259 行。

~~~dart
void _runViewportWarmNow({required String reason}) {
    if (!mounted) {
      return;
    }
    if (!_feedScrollController.hasClients) {
      return;
    }
    final position = _feedScrollController.position;
    final visible = _getVisibleConversations();
    ChatCoverageRepairScheduler.instance.resume();
    final rows = buildConversationFeedRows(
      conversations: visible,
      includeArchivedEntry: _selectedFolderId == null &&
          ArchivedConversationEntryVisibility.instance
              .shouldShow(_archiveScope),
      includeGroupNoticeEntry: _selectedFolderId == null &&
          widget.listScope == ConversationListScope.group,
      applications: GroupJoinApplicationService.instance.applications,
      notices: GroupSystemNoticeService.instance.notices,
      conversationTimestampMs: _getConversationTimestampMs,
      groupNoticePinned: GroupNoticeEntrySettingsService.instance.isPinned,
      groupNoticeDismissWatermarkMs:
          GroupNoticeEntrySettingsService.instance.dismissWatermarkMs,
    );
    final rowConversations = <V2TimConversation?>[
      for (final row in rows)
        row.kind == ConversationFeedRowKind.conversation
            ? row.conversation
            : null,
    ];
    if (widget.listScope == ConversationListScope.group) {
      final candidate =
          ConversationHistoryWarmScheduler.selectViewportCenterCandidate(
        rowConversations: rowConversations,
        scrollOffset: position.pixels,
        viewportHeight: position.viewportDimension,
      );
      if (candidate == null) {
        return;
      }
      ConversationHistoryWarmScheduler.instance.scheduleViewportWarm(
        visibleOrdered: <V2TimConversation>[candidate],
        reason: '${reason}_${widget.listScope.name}_center_one',
      );
      ChatCoverageRepairScheduler.instance.schedule(
        <V2TimConversation>[candidate],
        reason: '${reason}_${widget.listScope.name}_center_one',
        currentVisible: _getVisibleConversations,
      );
      unawaited(
        OpenViewportCache.instance.prepareVisible(
          visible: <V2TimConversation>[candidate],
          viewportHeight: position.viewportDimension,
          reason: '${reason}_${widget.listScope.name}_center_one',
        ),
      );
      return;
    }
    final candidates =
        ConversationHistoryWarmScheduler.selectViewportCandidates(
      rowConversations: rowConversations,
      scrollOffset: position.pixels,
      viewportHeight: position.viewportDimension,
    );
    ConversationHistoryWarmScheduler.instance.scheduleViewportWarm(
      visibleOrdered: candidates,
      reason: '${reason}_${widget.listScope.name}',
    );
    ChatCoverageRepairScheduler.instance.schedule(
      candidates,
      reason: '${reason}_${widget.listScope.name}',
      currentVisible: _getVisibleConversations,
    );
    unawaited(
      OpenViewportCache.instance.prepareVisible(
        visible: candidates,
        viewportHeight: position.viewportDimension,
        reason: '${reason}_${widget.listScope.name}',
      ),
    );
  }
~~~

46. [_ConversationState._warmConversationOnPress](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/conversation.dart:2261>)，原文件 lib/src/conversation.dart，2261–2282 行。

~~~dart
void _warmConversationOnPress(V2TimConversation conversation) {
    final isGroup = conversationMatchesScope(
      conversation,
      ConversationListScope.group,
    );
    if (isGroup) {
      if (!ConversationPerfFlags.groupPressWarmOnTapDownEnabled) {
        return;
      }
    } else if (!ConversationPerfFlags.pressWarmOnTapDownEnabled) {
      return;
    }
    if (_isEditing || !ConversationHistoryWarmScheduler.viewportWarmEnabled) {
      return;
    }
    // User-directed reads share the navigation/page flight and are independent
    // of background viewport warm pauses. This path stays local-only.
    unawaited(ChatOpenViewportCoordinator.instance.ensureLocalSnapshotForOpen(
      conversation: conversation,
    ));
    ChatImageMessagePrefetch.prefetchForConversation(conversation);
  }
~~~

47. [_ConversationState._handleOnConvItemTaped](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/conversation.dart:3242>)，原文件 lib/src/conversation.dart，3242–3482 行。

~~~dart
void _handleOnConvItemTaped(V2TimConversation? selectedConv) async {
    if (selectedConv == null) {
      return;
    }
    _lockEntryUnreadIfNeeded(selectedConv);
    final conversationID = selectedConv.conversationID;
    if (conversationID.isEmpty) {
      return;
    }
    // 移动端一次只允许一个 chat open 进入导航栈。旧实现只拦同一会话，
    // 冷开 prepare 期间快速点另一行可能产生两条竞争的 Chat route。
    if (_openingConversationID != null) {
      return;
    }
    _openingConversationID = conversationID;
    unawaited(
      ConversationSyncService.instance.retainOpenedGroupConversation(
        selectedConv,
      ),
    );

    final pushChatRoute = widget.onConversationChanged == null;
    ChatCoverageRepairScheduler.instance.pause(reason: 'conv_item_tap');
    OpenViewportCache.instance.pause(reason: 'conv_item_tap');
    if (pushChatRoute) {
      ConversationSyncService.instance.beginChatTransition();
    }

    final entryUnreadCount = selectedConv.unreadCount ?? 0;
    // Pipeline [1] - conv_item_tap：建立 t0 锚点（跨页面跨文件）
    final pipelineKey = ChatPipelineClock.normalizeKey(
      rawConversationId: selectedConv.conversationID,
      userId: selectedConv.userID,
      groupId: selectedConv.groupID,
    );
    ChatPipelineClock.instance
      ..start(pipelineKey)
      ..trace(pipelineKey, 'conv_item_tap',
          elapsedMs: 0,
          extras: <String, Object?>{
            'entryUnread': entryUnreadCount,
            'embedded': widget.onConversationChanged != null,
          });
    ConversationUnreadTrace.log(
      'conv_item_tap',
      conversationID: conversationID,
      unreadBefore: entryUnreadCount,
      extras: <String, Object?>{
        'embedded': widget.onConversationChanged != null,
      },
    );
    await ConversationUnreadClearService.clearLocalForOpenFast(
      conversation: selectedConv,
      markViewModelReadLocally: _controller.model.markConversationReadLocally,
    );

    final openCacheKey =
        _chatCacheConversationKey(selectedConv) ?? conversationID;
    ConversationHistoryWarmScheduler.instance.touchMemoryWarm(openCacheKey);
    final isGroup = selectedConv.type == 2 ||
        (selectedConv.groupID?.trim().isNotEmpty ?? false);
    ChatOpenPerfLog.beginOpen(
      conversationID: openCacheKey,
      phase: 'conv_item_tap',
      extras: <String, Object?>{
        'rawConvID': conversationID,
        'isGroup': isGroup,
        'entryUnread': entryUnreadCount,
        'pushRoute': pushChatRoute,
        'warmReady': ConversationPreviewHistorySync.isWarmWindowReadyForOpen(
          globalModel: serviceLocator<TUIChatGlobalModel>(),
          conversationKey: openCacheKey,
          preview: selectedConv.lastMessage,
        ),
        'rawCount': serviceLocator<TUIChatGlobalModel>().rawMessageCount(
          openCacheKey,
        ),
        'initialLoaded': serviceLocator<TUIChatGlobalModel>()
            .hasInitialHistoryLoaded(openCacheKey),
      },
    );
    final openTrace = ChatOpenPerfLog.captureCurrent(
      conversationKey: openCacheKey,
    );

    final embeddedChat = widget.onConversationChanged != null;
    if (embeddedChat) {
      final previous = _embeddedActiveConversationID;
      if (previous != null &&
          !MessageConversationId.sameConversation(previous, conversationID)) {
        final previousUnread = _embeddedEntryUnreadById[previous] ?? 0;
        unawaited(
          _finalizeConversationLeave(
            previous,
            entryUnreadCount: previousUnread,
          ),
        );
      }
      _embeddedActiveConversationID = conversationID;
      _embeddedEntryUnreadById[conversationID] = entryUnreadCount;
    }
    _controller.model.assignSelectedConversation(
      selectedConv,
      notify: embeddedChat,
    );

    if (!mounted) {
      if (pushChatRoute) {
        ConversationSyncService.instance.cancelChatTransition();
      }
      _openingConversationID = null;
      return;
    }
    DeviceSyncService.instance.prepareForChatNavigation();
    try {
      if (mounted) {
        unawaited(
          AvatarImageWarm.warmSources(
            <AvatarImageWarmSource>[
              _conversationAvatarWarmSource(selectedConv),
            ],
            context: context,
            logicalSize: 40,
          ),
        );
      }
      if (widget.onConversationChanged != null) {
        ChatOpenPerfLog.mark('embedded_chat_switch');
        widget.onConversationChanged!(selectedConv);
      } else {
        ChatOpenPerfLog.mark('open_prewarm_begin');
        // Telegram-style open: start the local-only snapshot, but never make
        // the route transition wait for a native SDK/database read. The Chat
        // page reuses this flight after mounting and renders the result when
        // it arrives.
        unawaited(() async {
          try {
            final coordinator = ChatOpenViewportCoordinator.instance;
            final prepareTask = coordinator.prepareOpenViewport(
              conversation: selectedConv,
              source: 'list',
            );
            final listRequestId = coordinator.currentRequestId;
            final snap = await prepareTask;
            if (!coordinator.isCurrent(
              listRequestId,
              snap.conversationKey,
            )) {
              final work = coordinator.snapshotFor(listRequestId);
              ChatOpenPerfLog.mark(
                'viewport_prepare_ignored',
                extras: <String, Object?>{
                  'key': snap.conversationKey,
                  'coverage': snap.coverageState.name,
                  'requestId': listRequestId,
                  'prepareId': listRequestId,
                  'currentRequestId': coordinator.currentRequestId,
                  'source': 'list',
                  'owned': work?.owned ?? false,
                  'joined': work?.joined ?? false,
                  'dbRead': work?.dbRead ?? false,
                  'sdkRead': work?.sdkRead ?? false,
                  'committed': work?.committed ?? false,
                  'ignoredReason': 'requestIdMismatch',
                },
                trace: openTrace,
              );
              return;
            }
            ChatOpenPerfLog.mark(
              'open_prewarm_end',
              extras: <String, Object?>{
                'complete': snap.isViewportReady,
                'rawCount': snap.continuousCount,
                'coverage': snap.coverageState.name,
                'source': snap.source.name,
                'requestId': listRequestId,
                'localReadyBeforePush': false,
                'background': false,
              },
              trace: openTrace,
            );
          } catch (error) {
            ChatOpenPerfLog.mark(
              'open_prewarm_error',
              extras: <String, Object?>{'error': '$error'},
              trace: openTrace,
            );
          }
        }());
        ChatOpenViewportCoordinator.instance.markTransitioning(
          openCacheKey,
        );
        ChatOpenPerfLog.mark('navigator_push_begin', trace: openTrace);
        await openOrReuseAppChat(
          context,
          selectedConv,
          entryUnreadCount: entryUnreadCount,
        );
        ChatOpenPerfLog.mark('navigator_pop_back', trace: openTrace);
        ConversationDraftLeaveTrace.stage(
          'conversation_list_resume',
          conversationId: conversationID,
          draftText: ConversationTabStore.instance
              .conversationForId(conversationID)
              ?.draftText,
        );
        ChatOpenPerfLog.emitOpenTraceSummary(phase: 'pop', trace: openTrace);
        if (!mounted) {
          return;
        }
        // Chat.dispose 也会启动同一 finalize。这里必须等待它的 single-flight
        // 本地提交完成后再强制 hydrate，否则会从 SQLite 读回旧 unread。
        await _finalizeConversationLeave(
          conversationID,
          entryUnreadCount: entryUnreadCount,
        );
        if (!mounted) {
          return;
        }
        // 从聊天返回：预热当前会话头像，降低列表行闪动。
        unawaited(
          AvatarImageWarm.warmSources(
            <AvatarImageWarmSource>[
              _conversationAvatarWarmSource(selectedConv),
            ],
            context: context,
            logicalSize: 52,
          ),
        );
      }
    } finally {
      if (_openingConversationID == conversationID) {
        _openingConversationID = null;
      }
      if (pushChatRoute &&
          ConversationSyncService.instance.hasActiveChatTransition) {
        ConversationSyncService.instance.cancelChatTransition();
      }
    }
  }
~~~

48. [TUIChatGlobalModel.messageStatusInConversation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3627>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3627–3644 行。

~~~dart
int messageStatusInConversation(
    String conversationID, {
    String? clientId,
    String? msgID,
    int? fallback,
    int? elemType,
  }) {
    final list = rawMessageList(conversationID);
    if (list == null || list.isEmpty) {
      return OutgoingSendStatus.normalize(status: fallback);
    }
    final current = _messageInConversation(conversationID,
        clientId: clientId, msgID: msgID);
    if (current != null) {
      return _normalizedOutgoingStatus(current, fallback);
    }
    return OutgoingSendStatus.normalize(status: fallback);
  }
~~~

49. [TUIChatGlobalModel.abandonOutcomeUnknownMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3646>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3646–3669 行。

~~~dart
Future<bool> abandonOutcomeUnknownMessage({
    required String conversationID,
    required ConvType conversationType,
    required String sdkLocalId,
    String? msgID,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty || conversationType == ConvType.none) return false;
    final abandoned =
        await ImOutgoingSendCoordinator.instance.abandonOutcomeUnknown(
      sdkLocalId: localId,
      conversationId: conversationID,
      conversationType: conversationType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
    );
    if (!abandoned) return false;
    return markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: localId,
      msgID: msgID,
      reason: 'outcome_unknown_abandoned_by_user',
    );
  }
~~~

50. [TUIChatGlobalModel.applyOutgoingSendResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:3671>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，3671–3716 行。

~~~dart
bool applyOutgoingSendResult(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String clientId,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
  ) {
    final dataMsgID = sendMsgRes.data?.msgID;
    if (isOutgoingMediaCancelled(clientId) ||
        isOutgoingMediaCancelled(dataMsgID)) {
      return false;
    }
    try {
      updateMessage(
        sendMsgRes,
        convID,
        clientId,
        convType,
        groupType,
        setInputField,
      );
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return true;
    } catch (e) {
      outputLogger.i('updateMessage error: $e');
      if (sendMsgRes.code != 0) {
        markOutgoingSendFailedByIdentity(
          conversationID: convID,
          clientId: clientId,
          msgID: dataMsgID,
          sendFailCode: sendMsgRes.code,
          reason: 'sdk_send_failed',
        );
      }
      return false;
    }
  }
~~~

51. [TUIChatGlobalModel.hasOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6455>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6455–6458 行。

~~~dart
/// 是否仍有进页 hydrate / 冷开并行 peek 在飞（别名感知）。
  bool hasOpenHydrateInFlight(String conversationID) {
    return _findOpenHydrateInFlight(conversationID) != null;
  }
~~~

52. [TUIChatGlobalModel.openHydrateResultFor](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6460>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6460–6477 行。

~~~dart
/// Last terminal result for the app-owned first-window bootstrap. This is
  /// separate from the in-flight map so a caller arriving just after
  /// completion can consume the same result without issuing LOCAL/CLOUD again.
  OpenHydrateResult? openHydrateResultFor(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) return null;
    final direct = _openHydrateResultByConv[trimmed];
    if (direct != null) return direct;
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateResultByConv[normalized];
      if (byNorm != null) return byNorm;
    }
    for (final entry in _openHydrateResultByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) return entry.value;
    }
    return null;
  }
~~~

53. [TUIChatGlobalModel.publishOpenHydrateResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6487>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6487–6496 行。

~~~dart
void publishOpenHydrateResult(
    String conversationID,
    OpenHydrateResult result,
  ) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateResultByConv[alias] = result;
    }
  }
~~~

54. [TUIChatGlobalModel.clearOpenHydrateResult](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6498>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6498–6504 行。

~~~dart
void clearOpenHydrateResult(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) return;
    _openHydrateResultByConv.removeWhere(
      (alias, _) => _isSameConversationID(alias, key),
    );
  }
~~~

55. [TUIChatGlobalModel._findOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6506>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6506–6528 行。

~~~dart
Future<OpenHydrateResult>? _findOpenHydrateInFlight(String conversationID) {
    final trimmed = conversationID.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final direct = _openHydrateInFlightByConv[trimmed];
    if (direct != null) {
      return direct;
    }
    final normalized = _normalizeConversationID(trimmed);
    if (normalized.isNotEmpty) {
      final byNorm = _openHydrateInFlightByConv[normalized];
      if (byNorm != null) {
        return byNorm;
      }
    }
    for (final entry in _openHydrateInFlightByConv.entries) {
      if (_isSameConversationID(entry.key, trimmed)) {
        return entry.value;
      }
    }
    return null;
  }
~~~

56. [TUIChatGlobalModel.ensureOpenHydrate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6530>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6530–6671 行。

~~~dart
/// The route, page and UIKit share one task and its terminal result.
  /// A caller timing out does not remove the underlying task.
  Future<OpenHydrateResult> ensureOpenHydrate(
    String conversationID, {
    required String requestSignature,
    required Future<bool> Function() load,
    required bool Function() canPublish,
  }) {
    final key = conversationID.trim();
    final existing = _findOpenHydrateInFlight(key);
    if (existing != null && (_openHydrateCanPublish[existing]?.call() ?? true)) {
      final joinTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.markHydrateJoined(
        ChatOpenPerfLog.lastPrepareRequestId,
        trace: joinTrace,
      );
      ChatOpenPerfLog.mark(
        'app_hydrate_join',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': joinTrace.requestId,
          'prepareId': joinTrace.requestId,
        },
        trace: joinTrace,
      );
      if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
        _openBottomCapsuleHydrateSettled = false;
      }
      return existing;
    }
    final previous = openHydrateResultFor(key);
    if (previous != null &&
        previous.requestSignature == requestSignature &&
        previous.shouldSuppressOrdinaryLoad &&
        hasInitialHistoryLoaded(key)) {
      final reuseTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
      ChatOpenPerfLog.mark(
        'app_hydrate_reuse',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': reuseTrace.requestId,
          'prepareId': reuseTrace.requestId,
          'hydrateKind': previous.kind.name,
        },
        trace: reuseTrace,
      );
      markOpenChatHydrateSettled(key);
      return Future.value(previous);
    }
    clearOpenHydrateResult(key);
    final generation = _messageHistoryCoverageSessionGeneration;
    final clearEpoch = messageDeltaClearEpochFor(key);
    final ownerTrace = ChatOpenPerfLog.captureCurrent(conversationKey: key);
    final ownerRequestId = ownerTrace.requestId;
    ChatOpenPerfLog.markHydrateOwner(ownerRequestId, trace: ownerTrace);
    ChatOpenPerfLog.mark(
      'app_hydrate_registered',
      conversationID: key,
      extras: <String, Object?>{
        'requestId': ownerRequestId,
        'prepareId': ownerRequestId,
      },
      trace: ownerTrace,
    );
    late final Future<OpenHydrateResult> task;
    task = Future<OpenHydrateResult>.microtask(() async {
      var kind = OpenHydrateResultKind.aborted;
      ChatOpenPerfLog.mark(
        'app_hydrate_started',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': ownerRequestId,
          'prepareId': ownerRequestId,
        },
        trace: ownerTrace,
      );
      try {
        if (canPublish() && await load()) {
          kind = rawMessageCount(key) > 0
              ? OpenHydrateResultKind.committedMessages
              : OpenHydrateResultKind.committedEmpty;
        }
      } catch (_) {
        kind = OpenHydrateResultKind.failed;
      }
      final current = generation == _messageHistoryCoverageSessionGeneration &&
          clearEpoch == messageDeltaClearEpochFor(key) &&
          identical(_findOpenHydrateInFlight(key), task) &&
          canPublish();
      if (!current) kind = OpenHydrateResultKind.aborted;
      final result = OpenHydrateResult(
        kind: kind,
        conversationKey: key,
        resultCount: current ? rawMessageCount(key) : 0,
        firstWindowCommitted: current &&
            (kind == OpenHydrateResultKind.committedMessages ||
                kind == OpenHydrateResultKind.committedEmpty),
        generation: generation,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
        requestSignature: requestSignature,
      );
      if (current) {
        publishOpenHydrateResult(key, result);
        ChatOpenPerfLog.mark(
          'app_hydrate_commit',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
          },
          trace: ownerTrace,
        );
      } else {
        ChatOpenPerfLog.mark(
          'app_hydrate_aborted',
          conversationID: key,
          extras: <String, Object?>{
            'requestId': ownerRequestId,
            'prepareId': ownerRequestId,
            'hydrateKind': kind.name,
            'staleReason': 'hydrateAborted',
          },
          trace: ownerTrace,
        );
      }
      return result;
    }).whenComplete(() {
      final stillOwner = identical(_findOpenHydrateInFlight(key), task);
      _openHydrateInFlightByConv
          .removeWhere((_, value) => identical(value, task));
      if (stillOwner) markOpenChatHydrateSettled(key);
    });
    _openHydrateCanPublish[task] = canPublish;
    for (final alias in _historyFlagKeys(key)) {
      _openHydrateInFlightByConv[alias] = task;
    }
    if (_isSameConversationID(_openBottomCapsuleLockConvId, key)) {
      _openBottomCapsuleHydrateSettled = false;
    }
    return task;
  }
~~~

57. [TUIChatGlobalModel.awaitOpenHydrateInFlight](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:6673>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，6673–6686 行。

~~~dart
Future<void> awaitOpenHydrateInFlight(
    String conversationID, {
    Duration timeout = const Duration(milliseconds: 450),
  }) async {
    final inFlight = _findOpenHydrateInFlight(conversationID);
    if (inFlight == null) {
      return;
    }
    try {
      await inFlight.timeout(timeout);
    } on TimeoutException {
      // hydrate 自行兜底。
    }
  }
~~~

58. [TUIChatGlobalModel.bindOutgoingSyncMsgId](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:8235>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，8235–8297 行。

~~~dart
/// Binds SDK-assigned [msgID] to a sending placeholder before send completes.
  void bindOutgoingSyncMsgId(
    String conversationID,
    String clientId,
    String msgID,
  ) {
    final id = clientId.trim();
    final serverMsgID = msgID.trim();
    if (id.isEmpty || serverMsgID.isEmpty) {
      return;
    }
    final storageKey = _resolveMessageListStorageKey(conversationID);
    if (storageKey.isEmpty) {
      return;
    }

    final current = _mergedAliasMessageList(storageKey);
    final index = current.indexWhere(
      (item) =>
          item.isSelf == true &&
          item.id == id &&
          (item.msgID == null || item.msgID!.isEmpty || item.msgID == id),
    );
    if (index < 0) {
      return;
    }

    final previous = current[index];
    final updated = _cloneMessage(previous);
    updated.msgID = serverMsgID;
    final stableIdentity = readOutgoingStableId(previous) ?? id;
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageKey,
        eventID: 'send_bind:$id:$serverMsgID',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageKey),
        clearEpoch: messageDeltaClearEpochFor(storageKey),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: updated,
            msgID: updated.msgID,
            localID: updated.id,
            outgoingStableID: stableIdentity,
            seq: updated.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      // Rejected/stale/active-history binds must not mutate the formal list.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageKey,
      id,
      ChatUiStateStore.messageKeyOf(updated),
    );
    ChatMessageHeightCache.instance.rememberAlias(id, serverMsgID);
    _markMessageRowChanged(storageKey, updated, extraKey: id);
    _markNeedsNotify();
  }
~~~

59. [TUIChatGlobalModel._sendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:10767>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，10767–10874 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    bool? isEditStatusMessage = false,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    V2TimMessage? messageInfo,
    bool isExcludedFromContentModeration = false,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    ValueChanged<ImCoordinatedSendResult>? onCoordinatedResult,
  }) async {
    String receiver = convType == ConvType.c2c ? convID : '';
    String groupID = convType == ConvType.group ? convID : '';
    // 历史桶 key 常带 `c2c_` / `group_` 前缀；IM sendMessage 必须用裸 userID / groupID。
    if (receiver.toLowerCase().startsWith('c2c_') && receiver.length > 4) {
      receiver = receiver.substring(4);
    }
    if (groupID.toLowerCase().startsWith('group_') && groupID.length > 6) {
      groupID = groupID.substring(6);
    }
    final receiptGroupType = groupType ??
        (convType == ConvType.group
            ? await _loadGroupReceiptType(groupID)
            : null);
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group ||
                _isReadReceiptAllowedGroup(receiptGroupType)) &&
            !_looksLikeCommunityGroupId(groupID);
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      sdkLocalId: id,
      conversationId: convID,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
      onlineUserOnly: onlineUserOnly ?? false,
      businessCloudCustomData: cloudCustomData ??
          json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          }),
      persistOutbox: isEditStatusMessage != true,
      recoverPreparedOutbox: recoverPreparedOutbox,
      operationIdOverride: operationIdOverride,
      clientCorrelationIdOverride: clientCorrelationIdOverride,
      onSyncMsgID: (syncMsgID) {
        bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    onCoordinatedResult?.call(coordinatedSend);
    final sendMsgRes = coordinatedSend.sdkResult;
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {
      projectionCommitted = applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        receiptGroupType,
        setInputField,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (!coordinatedSend.outcomeUnknown) {
      insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    if (_lifeCycle?.messageDidSend != null) {
      _lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }
~~~

60. [TUIChatGlobalModel._findMessageIndexForUpdate](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12161>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12161–12172 行。

~~~dart
int _findMessageIndexForUpdate(
    List<V2TimMessage> messageList,
    String id,
    V2TimMessage sentMessage,
  ) {
    return findReplaceableOutgoingIndex(
      '',
      sentMessage,
      priorTempId: id,
      listOverride: messageList,
    );
  }
~~~

61. [TUIChatGlobalModel.updateMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12192>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12192–12414 行。

~~~dart
updateMessage(
    V2TimValueCallback<V2TimMessage> sendMsgRes,
    String convID,
    String id,
    ConvType convType,
    GroupReceiptAllowType? groupType,
    ValueChanged<String>? setInputField,
  ) {
    final storageConvID = _resolveMessageListStorageKey(convID);
    List<V2TimMessage> currentHistoryMsgList =
        _messageListMap[storageConvID] ?? _collectAuthoritativeMessages(convID);
    final V2TimMessage sendMsgResData = sendMsgRes.data as V2TimMessage;
    final resolvedMessage = _cloneMessage(sendMsgResData);

    // Always set the correct status based on send result
    if (sendMsgRes.code == 0) {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
      _setUploadProgressSilently(id, 100);
      final resolvedMsgID = resolvedMessage.msgID?.trim();
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _setUploadProgressSilently(resolvedMsgID, 100);
      }
    } else {
      resolvedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (resolvedMessage.id == null || resolvedMessage.id!.isEmpty) {
      resolvedMessage.id = id;
    }
    final targetIndex = _findMessageIndexForUpdate(
      currentHistoryMsgList,
      id,
      resolvedMessage,
    );
    final originalRowCount = currentHistoryMsgList.length;
    if (sendMsgRes.code != 0 &&
        resolvedMessage.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      ErrorMessageConverter.attachSendFailCode(
        resolvedMessage,
        sendMsgRes.code,
      );
      final msgID = resolvedMessage.msgID;
      if (msgID != null &&
          msgID.isNotEmpty &&
          resolvedMessage.localCustomData != null) {
        _messageService.setLocalCustomData(
          msgID: msgID,
          localCustomData: resolvedMessage.localCustomData!,
        );
      }
    }
    V2TimMessage? previousForMerge;
    if (targetIndex != -1) {
      currentHistoryMsgList = [...currentHistoryMsgList];
      previousForMerge = currentHistoryMsgList[targetIndex];
      if (sendMsgRes.code != 0) {
        final boundMsgID = previousForMerge.msgID?.trim();
        if (boundMsgID != null && boundMsgID.isNotEmpty) {
          resolvedMessage.msgID = boundMsgID;
        }
      }
      _preserveSoundLocalPath(previousForMerge, resolvedMessage);
      _preserveImageLocalPath(previousForMerge, resolvedMessage);
      _preserveImageDisplaySize(resolvedMessage, id);
      _preserveOutgoingLocalOrderData(previousForMerge, resolvedMessage);
      currentHistoryMsgList[targetIndex] = resolvedMessage;
    } else {
      currentHistoryMsgList = [resolvedMessage, ...currentHistoryMsgList];
    }
    final resolvedId = resolvedMessage.id ?? id;
    final resolvedMsgID = resolvedMessage.msgID;
    if (sendMsgRes.code == 0) {
      final hadFailCode =
          ErrorMessageConverter.getSendFailCode(resolvedMessage) != null;
      ErrorMessageConverter.clearSendFailCode(resolvedMessage);
      if (hadFailCode && resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _messageService.setLocalCustomData(
          msgID: resolvedMsgID,
          localCustomData: resolvedMessage.localCustomData ?? '',
        );
      }
      _clearUploadProgressSilently(resolvedId);
      if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
        _clearUploadProgressSilently(resolvedMsgID);
      }
      _migrateFileMessageMetadata(id, resolvedMsgID);
      if (resolvedMessage.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        final layoutSize = _fileMessageSizeMap[id] ??
            ((resolvedMsgID?.isNotEmpty ?? false)
                ? _fileMessageSizeMap[resolvedMsgID!]
                : null);
        if (layoutSize != null &&
            layoutSize.width > 0 &&
            layoutSize.height > 0) {
          applyImageLayoutToMessage(resolvedMessage, layoutSize);
          if (resolvedMsgID != null && resolvedMsgID.isNotEmpty) {
            _messageService.setLocalCustomData(
              msgID: resolvedMsgID,
              localCustomData: resolvedMessage.localCustomData ?? '',
            );
          }
        }
      }
    }
    if (resolvedId.isNotEmpty || (resolvedMsgID?.isNotEmpty ?? false)) {
      currentHistoryMsgList = currentHistoryMsgList.where((element) {
        if (identical(element, resolvedMessage)) {
          return true;
        }
        final sameId = resolvedId.isNotEmpty && element.id == resolvedId;
        final sameMsgID = resolvedMsgID != null &&
            resolvedMsgID.isNotEmpty &&
            element.msgID == resolvedMsgID;
        if (!sameId && !sameMsgID) {
          return true;
        }
        return false;
      }).toList();
    }
    final collapsedDuplicate = currentHistoryMsgList.length < originalRowCount;
    if (loadingMessage[storageConvID] != null &&
        loadingMessage[storageConvID]!.isNotEmpty) {
      loadingMessage[storageConvID]!.removeWhere((element) => element.id == id);
    }
    if (chatConfig.isShowReadingStatus &&
        groupType != GroupReceiptAllowType.community &&
        sendMsgRes.data?.msgID != null) {
      _messageReadReceiptMap[sendMsgRes.data!.msgID!] = V2TimMessageReceipt(
        timestamp: 0,
        userID: "",
        readCount: 0,
      );
    }
    _registerSoundLocalPath(resolvedMessage);
    final stableIdentity =
        readOutgoingStableId(previousForMerge)?.trim().isNotEmpty == true
            ? readOutgoingStableId(previousForMerge)!.trim()
            : readOutgoingStableId(resolvedMessage)?.trim().isNotEmpty == true
                ? readOutgoingStableId(resolvedMessage)!.trim()
                : id.trim();
    final adoptionRecord = MessageReconciliationRecord<V2TimMessage>(
      value: resolvedMessage,
      msgID: resolvedMessage.msgID,
      localID: resolvedMessage.id,
      outgoingStableID: stableIdentity,
      seq: resolvedMessage.seq,
    );
    final authoritativeSendCommit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID: 'send_adoption:$stableIdentity:${resolvedMessage.msgID ?? ''}',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: [adoptionRecord],
      ),
    );
    if (authoritativeSendCommit == null) {
      // A queued, stale, or rejected receipt cannot use the old row-local or
      // full-list fallback. History completion or a later valid receipt owns
      // the next formal publication.
      // `send_done_row_local_fallback` is intentionally retired as a formal
      // list path; keep the diagnostic term for compatibility with probes.
      return;
    }
    _chatUiStateStore.bindMessageAlias(
      storageConvID,
      id,
      ChatUiStateStore.messageKeyOf(resolvedMessage),
    );
    // temp id 上已测到的行高迁到正式 msgID，避免 send_done 后失缓存再估高抖动。
    ChatMessageHeightCache.instance.rememberAlias(id, resolvedMessage.msgID);
    final knownHeight = ChatMessageHeightCache.instance.heightFor(
      resolvedMessage,
    );
    if (knownHeight != null && knownHeight > 0) {
      ChatMessageHeightCache.instance.remember(resolvedMessage, knownHeight);
    }
    _markMessageRowChanged(storageConvID, resolvedMessage, extraKey: id);
    final insertedRow = targetIndex == -1;
    final reordered = !isNewestFirstStorageOrderValid(currentHistoryMsgList);
    final isRowLocalMediaReceipt = targetIndex != -1 &&
        !collapsedDuplicate &&
        stableIdentity.isNotEmpty &&
        _isRowLocalOutgoingMediaReceipt(previousForMerge, resolvedMessage);
    final structuralChange = insertedRow || collapsedDuplicate || reordered;
    if (structuralChange) {
      _bumpMessageListRevisionFor(
        storageConvID,
        reason: insertedRow
            ? 'send_done_insert_sort'
            : collapsedDuplicate
                ? 'send_done_duplicate_collapse'
                : 'send_done_reorder',
      );
    }
    _logOutgoingSendOrder(
      event: 'send_done',
      convID: storageConvID,
      message: resolvedMessage,
      clientId: id,
      mergePath: isRowLocalMediaReceipt
          ? 'row_local_stable_identity'
          : targetIndex != -1
              ? 'update_replace'
              : 'update_insert',
      existingIndex: targetIndex,
      reordered: reordered,
    );
    // 同位回执只由 ChatUiStateStore 通知该行；不发全局 notify，
    // 也不请求贴底，避免用户正在上滑时被拉回底部。
    if (!structuralChange) {
      return;
    }
    // 发送后 350ms suppress 窗口内推迟整表 notify，让 list-push 先播完。
    if (targetIndex != -1 && shouldSuppressOutgoingPinScroll()) {
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        _markNeedsNotify();
      });
    } else {
      _markNeedsNotify();
    }
  }
~~~

62. [TUIChatGlobalModel.markOutgoingSendFailedByIdentity](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12416>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12416–12500 行。

~~~dart
bool markOutgoingSendFailedByIdentity({
    required String conversationID,
    String? clientId,
    String? msgID,
    String? localCustomData,
    int? sendFailCode,
    String reason = 'send_failed',
  }) {
    final storageConvID = _resolveMessageListStorageKey(conversationID);
    final cid = clientId?.trim() ?? '';
    final mid = msgID?.trim() ?? '';
    if (storageConvID.isEmpty || (cid.isEmpty && mid.isEmpty)) {
      return false;
    }
    final list = _mergedAliasMessageList(storageConvID);
    if (list.isEmpty) {
      return false;
    }
    final index = list.indexWhere((item) {
      final stable = readOutgoingStableId(item)?.trim() ?? '';
      if (cid.isNotEmpty && (item.id == cid || stable == cid)) {
        return true;
      }
      if (mid.isNotEmpty && (item.msgID == mid || stable == mid)) {
        return true;
      }
      return false;
    });
    if (index < 0) {
      return false;
    }
    final previous = list[index];
    final failed = _cloneMessage(previous);
    failed.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    if (localCustomData != null) {
      failed.localCustomData = localCustomData;
    }
    if (sendFailCode != null) {
      ErrorMessageConverter.attachSendFailCode(failed, sendFailCode);
    }
    final stableIdentity = readOutgoingStableId(previous) ??
        readOutgoingStableId(failed) ??
        (cid.isNotEmpty ? cid : mid);
    final safeReason = reason.trim().isEmpty
        ? 'send_failed'
        : reason.trim().replaceAll(':', '_');
    final commit = commitMessageDelta(
      MessageDelta<V2TimMessage>(
        conversationKey: storageConvID,
        eventID: 'send_fail:$storageConvID:$safeReason:$stableIdentity:$mid',
        kind: MessageDeltaKind.optimisticAdoption,
        source: MessageDeltaSource.sendPipeline,
        generation: messageDeltaGenerationFor(storageConvID),
        clearEpoch: messageDeltaClearEpochFor(storageConvID),
        upserts: <MessageReconciliationRecord<V2TimMessage>>[
          MessageReconciliationRecord<V2TimMessage>(
            value: failed,
            msgID: failed.msgID,
            localID: failed.id,
            outgoingStableID: stableIdentity,
            seq: failed.seq,
          ),
        ],
      ),
    );
    if (commit == null) {
      return false;
    }
    final failedKey = ChatUiStateStore.messageKeyOf(failed);
    for (final alias in <String>{cid, mid, stableIdentity}..remove('')) {
      if (alias != failedKey) {
        _chatUiStateStore.bindMessageAlias(storageConvID, alias, failedKey);
      }
    }
    _markMessageRowChanged(
      storageConvID,
      failed,
      extraKey: cid.isNotEmpty ? cid : mid,
      mutationType: MessageMutationType.statusOrProgress,
    );
    if (_isSameConversationID(storageConvID, currentSelectedConv)) {
      _markNeedsNotify();
    }
    return true;
  }
~~~

63. [TUIChatGlobalModel.markOutgoingGuardDropped](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:12502>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，12502–12517 行。

~~~dart
/// Marks an optimistic outgoing message as SEND_FAIL when the commit guard
  /// rejected the send (e.g. conversation switched during async media prep).
  /// Finds the message by temporary client [id], updates its status, and
  /// stamps [localCustomData] with guard_dropped so the UI can show a retry.
  void markOutgoingGuardDropped({
    required String conversationID,
    required String clientId,
    String? localCustomData,
  }) {
    markOutgoingSendFailedByIdentity(
      conversationID: conversationID,
      clientId: clientId,
      localCustomData: localCustomData,
      reason: 'guard_dropped',
    );
  }
~~~

64. [TUIChatGlobalModel.applyAppRealtimeMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:10234>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，10234–10251 行。

~~~dart
/// Application-layer compatibility bridge for the single IM ingress.
  ///
  /// The SDK listener is owned by the app MessageCore. These methods preserve
  /// the existing UIKit projection behavior without registering another SDK
  /// listener inside the view model.
  Future<void> applyAppRealtimeMessage(
    V2TimMessage message, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    await _onReceiveNewMsg(
      message,
      ingressEventID: ingressEventID,
      ingressSequence: ingressSequence,
      projectMessageList: projectMessageList,
    );
  }
~~~

65. [TUIChatGlobalModel._onReceiveNewMsg](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:9250>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，9250–9384 行。

~~~dart
Future<void> _onReceiveNewMsg(
    V2TimMessage msgComing, {
    String? ingressEventID,
    int? ingressSequence,
    bool projectMessageList = true,
  }) async {
    final lifecycleGeneration = _messageHistoryCoverageSessionGeneration;
    final writerScope = _messageReconciliationWriter.configuredScope;
    final initialConvID = _messageConversationID(msgComing);
    if (initialConvID == null || initialConvID.isEmpty) {
      return;
    }

    final capturedClearEpoch = messageDeltaClearEpochFor(initialConvID);
    V2TimMessage? mountedMessage = msgComing;
    if (_lifeCycle?.newMessageWillMount != null) {
      try {
        mountedMessage = await _lifeCycle!.newMessageWillMount(msgComing);
      } catch (e) {
        outputLogger.i('newMessageWillMount error: $e');
        mountedMessage = msgComing;
      }
    }
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope ||
        messageDeltaClearEpochFor(initialConvID) != capturedClearEpoch) {
      ChatJitterDiag.log(
        'message_inbound_drop_stale_lifecycle',
        conv: initialConvID,
        extras: <String, Object?>{
          'generation': lifecycleGeneration,
          'currentGeneration': _messageHistoryCoverageSessionGeneration,
        },
      );
      return;
    }
    if (mountedMessage == null) {
      return;
    }
    mountedMessage = _normalizeInboundC2cDirection(mountedMessage);

    final rawConvID = _messageConversationID(mountedMessage) ?? initialConvID;
    final convID = _resolveMessageListStorageKey(rawConvID);
    _syncGroupMemberFromMessage(mountedMessage);
    final senderId = TencentUtils.checkString(mountedMessage.sender) ??
        TencentUtils.checkString(mountedMessage.userID);
    if (mountedMessage.isSelf != true && senderId != null) {
      unawaited(
        UserProfileLocalBridge.upsertPublicProfileFromSnapshot(
          userId: senderId,
          nickName: mountedMessage.nickName,
          faceUrl: mountedMessage.faceUrl,
        ),
      );
    }

    // Typing/status custom messages should update typing state only. They must not
    // enter the visible message list, but they also must not stop normal message
    // events in other conversations.
    final bool isEditMessage = _editStatusCheck(mountedMessage);
    if (isEditMessage) {
      return;
    }

    if (!projectMessageList) {
      if (HistoryWindowRepositoryProvider.repository != null) {
        await _admitBoundedHistoryIncoming(
          mountedMessage,
          eventID: ingressEventID,
          ingressSequence: ingressSequence,
          allowLatestReveal: false,
        );
      }
      return;
    }

    if (!_isSameConversationID(convID, currentSelectedConv) &&
        !_messageListMap.containsKey(convID)) {
      // Notifications and business signaling run outside this display model.
      // Opening this conversation will read the SDK's persisted recent page.
      return;
    }

    if (HistoryWindowRepositoryProvider.repository != null &&
        await _admitBoundedHistoryIncoming(mountedMessage,
            eventID: ingressEventID, ingressSequence: ingressSequence)) return;
    if (!_isMessageLifecycleCurrent(lifecycleGeneration) ||
        _messageReconciliationWriter.configuredScope != writerScope) return;

    _checkFromUserisActive(mountedMessage);
    final convType = TencentUtils.checkString(mountedMessage.groupID) != null
        ? ConvType.group
        : ConvType.c2c;
    final isActiveConversation = _isSameConversationID(
      convID,
      currentSelectedConv,
    );

    if (isActiveConversation &&
        chatConfig.isAutoReportRead &&
        lockedEntryUnreadCountFor(convID) == 0) {
      _scheduleActiveReadReport(convID: convID, convType: convType);
    }

    // Self-sent sync on the active chat must stay immediate for send UX.
    if (isActiveConversation && mountedMessage.isSelf == true) {
      _syncSelfSentMessage(convID, mountedMessage, forceSuccess: false);
      _markNeedsNotify();
      return;
    }

    // Group seq gap detection: if the reorder buffer is active for this
    // conversation, route through it so out-of-order messages are buffered
    // and missing messages trigger a cloud catch-up. C2C seq has no global
    // continuity so the buffer is never active for C2C.
    final buffer = _reorderBuffersByConv[convID];
    if (buffer != null && buffer.isActivated && convType == ConvType.group) {
      final result = buffer.accept(mountedMessage);
      if (result == null) {
        // Buffered: out-of-order or gap detected, will be flushed later.
        return;
      }
      if (result.isEmpty) {
        // Duplicate (seq <= expected), silently dropped.
        return;
      }
      // Contiguous: upsert immediately (may include drained buffer messages).
      for (final msg in result) {
        _inboundBatchCoalescer.enqueue(convID, msg);
      }
      return;
    }

    _inboundBatchCoalescer.enqueue(convID, mountedMessage);
  }
~~~

66. [TUIChatGlobalModel.completeHistoryReconciliation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart:1279>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart，1279–1400 行。

~~~dart
MessageCommitResult? completeHistoryReconciliation({
    required MessageReconciliationRequest request,
    required Iterable<V2TimMessage> history,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    bool applyMemoryWindow = true,
    bool memoryWindowPreferLatest = false,
    String historyCommitSource = 'reconciliation',
    bool cloudHasMoreNewer = false,
    MessageHistoryBatchKind batchKind = MessageHistoryBatchKind.olderPage,
    bool? historyIsFinished,
    int? clearEpoch,
    MessageHistoryCursor? requestedCursor,
    MessageHistoryBounds? returnedBounds,
    MessageHistoryProofKind? proofKind,
    bool? cloudResponseProven,
    Iterable<String> explicitDeletes = const <String>[],
    Iterable<String> tombstones = const <String>[],
    bool skipEquivalentHistoryWindow = false,

    /// Already canonical window captured by the pagination caller. Reusing it
    /// avoids a second alias merge/dedupe while committing an older page.
    List<V2TimMessage>? currentWindowOverride,
  }) {
    // Include direct row-local/self-send commits made while the request was in
    // flight. Inbound callbacks are already held in pendingRealtime.
    final historyList = history.toList(growable: false);
    final effectiveClearEpoch =
        clearEpoch ?? messageDeltaClearEpochFor(request.conversationKey);
    final current = currentWindowOverride ??
        _mergedAliasMessageList(request.conversationKey);
    final authoritativeBase =
        batchKind == MessageHistoryBatchKind.latestWindow &&
                actualSource == MessageReconciliationSource.cloud
            ? _authoritativeBaseForCloudLatestWindow(
                conversationID: request.conversationKey,
                current: current,
                cloudWindow: historyList,
              )
            : current;
    final resolvedProofKind = proofKind ??
        (cloudResponseProven != null
            ? (cloudResponseProven
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none)
            : actualSource == MessageReconciliationSource.cloud &&
                    networkState == MessageReconciliationNetworkState.online
                ? MessageHistoryProofKind.transportObserved
                : MessageHistoryProofKind.none);
    final commit = _messageReconciliationWriter.completeHistory(
      request: request,
      history: _reconciliationRecords(historyList),
      authoritativeBase: _reconciliationRecords(authoritativeBase),
      actualSource: actualSource,
      networkState: networkState,
      clearEpoch: effectiveClearEpoch,
      cloudHasMoreNewer: cloudHasMoreNewer,
      batchKind: batchKind,
      proofKind: resolvedProofKind,
      historyIsFinished: historyIsFinished,
      explicitDeletes: explicitDeletes,
      tombstones: tombstones,
    );
    if (commit == null) {
      return null;
    }
    final result = setMessageList(
      commit.conversationKey,
      _messageReconciliationWriter.valuesFor(commit.conversationKey),
      needResetNewMessageCount: false,
      replace: true,
      applyMemoryWindow: applyMemoryWindow,
      memoryWindowPreferLatest: memoryWindowPreferLatest,
      skipEquivalentHistoryWindow: true,
      writerCommit: commit,
      historyCommitSource: skipEquivalentHistoryWindow
          ? historyCommitSource
          : '$historyCommitSource:r${commit.revision}',
    );
    final resolvedMetadataKey = _resolveMessageListStorageKey(
      commit.conversationKey,
    );
    final metadataKey = resolvedMetadataKey.isEmpty
        ? commit.conversationKey.trim()
        : resolvedMetadataKey;
    _lastHistoryCommitMetadataByConv[metadataKey] =
        MessageHistoryCommitMetadata(
      conversationKey: metadataKey,
      source: actualSource,
      batchKind: batchKind,
      generation: request.generation,
      revision: commit.revision,
      resultCount: result.rawCount,
      proofKind: resolvedProofKind,
      clearEpoch: effectiveClearEpoch,
    );
    _recordMessageHistoryCoverageAfterCommit(
      request: request,
      batchKind: batchKind,
      actualSource: actualSource,
      networkState: networkState,
      history: historyList,
      historyIsFinished: historyIsFinished,
      cloudHasMoreNewer: cloudHasMoreNewer,
      clearEpoch: effectiveClearEpoch,
      requestedCursor: requestedCursor,
      returnedBounds: returnedBounds,
      proofKind: resolvedProofKind,
    );
    unawaited(
      ImOutgoingSendCoordinator.instance
          .adoptProviderHistory(historyList)
          .catchError((Object error) {
        debugPrint(
          'OUTBOX_HISTORY_ADOPTION_FAILURE '
          'errorType=${error.runtimeType}',
        );
        return 0;
      }),
    );
    return result;
  }
~~~

67. [TUIChatSeparateViewModel.initForEachConversation](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:857>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，857–1047 行。

~~~dart
void initForEachConversation(
    ConvType convType,
    String convID,
    ValueChanged<String>? onChangeInputField, {
    String? groupID,
    String? groupType,
    List<V2TimGroupMemberFullInfo?>? preGroupMemberList,
  }) async {
    if (_isInit) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID),
      );
      return;
    }
    setInputField = onChangeInputField;
    conversationType = convType;
    _groupType = null;
    if (convType == ConvType.group) {
      final normalizedGroupType = groupType?.trim().toLowerCase();
      _groupType = switch (normalizedGroupType) {
        'meeting' => GroupReceiptAllowType.meeting,
        'public' => GroupReceiptAllowType.public,
        'work' => GroupReceiptAllowType.work,
        'community' => GroupReceiptAllowType.community,
        _ => null,
      };
    }
    // 消息列表 / hydrate / 归档一律用裸会话 ID（@TGS#…），勿带 group_。
    final previousConversationID = conversationID;
    conversationID = _storageConversationId(convID);
    if (previousConversationID != conversationID) {
      _mediaCommitGuard.advanceConversation();
    }
    _disposed = false;
    final initGeneration = ++_chatOpenGeneration;
    final initConversationID = conversationID;
    // Establish the visit boundary before the first await or incoming callback.
    // Failure keeps the baseline pending; admission/return retries it in order.
    unawaited(globalModel.beginHistoryUnreadVisit(conversationID).catchError(
      (Object error, StackTrace stack) {
        ChatHistoryTrace.log('unread_visit_baseline_retry_required',
            conversationID: initConversationID);
      },
    ));
    _preGroupMemberListForOpen = preGroupMemberList;
    _openProfileEnrichmentInFlight = null;
    _pagination.resetForConversationInit();

    var warmOnStorage = globalModel.rawMessageCount(conversationID);
    final warmOnRaw = globalModel.rawMessageCount(convID);
    final idMismatchRisk = warmOnStorage == 0 && warmOnRaw > 0;
    ChatHistoryTrace.log(
      'init_conv',
      conversationID: conversationID,
      extras: <String, Object?>{
        'rawConvID': convID,
        'warmOnStorage': warmOnStorage,
        'warmOnRaw': warmOnRaw,
        'loadedStorage': globalModel.hasInitialHistoryLoaded(conversationID),
        'loadedRaw': globalModel.hasInitialHistoryLoaded(convID),
        'idMismatchRisk': idMismatchRisk,
      },
    );

    // 暖窗写在 raw/group_ 桶、页面已收成裸 storageId：迁到 storage，避免假空。
    if (idMismatchRisk) {
      final aliasWindow = globalModel.rawMessageList(convID);
      if (aliasWindow != null && aliasWindow.isNotEmpty) {
        final historyIsCurrent = _historyPublicationFence();
        final authoritative = await globalModel.applyHistoryWindowMutations(
            conversationID, List<V2TimMessage>.from(aliasWindow));
        if (!historyIsCurrent()) return;
        final commit = globalModel.setMessageList(
          conversationID,
          authoritative,
          needResetNewMessageCount: false,
          replace: true,
        );
        globalModel.markInitialHistoryLoaded(conversationID);
        final mayOlder = globalModel.mayHaveOlderHistory(convID) ||
            aliasWindow.length >=
                HistoryMessageDartConstant.initialOpenFetchCount;
        globalModel.markInitialHistoryMayHaveOlder(
          conversationID,
          mayHaveOlder: mayOlder,
        );
        warmOnStorage = commit.rawCount;
        ChatHistoryTrace.log(
          'init_conv_migrate_alias_window',
          conversationID: conversationID,
          extras: <String, Object?>{
            'fromKey': convID,
            'toKey': conversationID,
            'count': aliasWindow.length,
            'mayHaveOlder': mayOlder,
            'warmOnStorageAfter': warmOnStorage,
          },
        );
      }
    }

    if (globalModel.hasInitialHistoryLoaded(conversationID) &&
        globalModel.rawMessageCount(conversationID) > 0) {
      final mayOlder = globalModel.mayHaveOlderHistory(conversationID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(conversationID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      // 兼容进页瞬间仍用旧 key（group_）写暖窗的情况。
      final mayOlder = globalModel.mayHaveOlderHistory(convID);
      haveMoreData = mayOlder ||
          globalModel.rawMessageCount(convID) >=
              HistoryMessageDartConstant.initialOpenFetchCount;
    } else {
      _pagination.markHistoryUnknown();
    }
    haveMoreLatestData = false;

    isGroupExist = true;
    _groupInfo = null;
    groupMemberList = null;
    selfMemberInfo = null;
    groupMemberListComplete = false;
    _idleFullMemberLoadGeneration++;
    _fullMemberLoadInFlight = null;
    _openShellGeneration++;
    _openShellInFlight = null;
    _openShellCompletedGid = null;
    _warmOpenHistoryReconcileScheduled = false;
    _warmOpenTowardLocalScheduled = false;
    _fillTowardOlderHistoryResumeTimer?.cancel();
    _fillTowardOlderHistoryResumeTimer = null;
    _lastPeekIsFinished = false;
    _sdkOlderPageTail = null;

    globalModel.setCurrentConversation(
      CurrentConversation(conversationID, conversationType ?? ConvType.c2c),
      notify: false,
    );
    globalModel.lifeCycle = lifeCycle;
    if (globalModel.hasPendingScrollRestore(conversationID)) {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.notShowLatest,
        notify: false,
      );
    } else {
      globalModel.setMessageListPosition(
        conversationID,
        HistoryMessagePosition.bottom,
        notify: false,
      );
    }
    globalModel.setChatConfig(chatConfig);

    if (globalModel.hasInitialHistoryLoaded(convID) &&
        globalModel.rawMessageCount(convID) > 0) {
      syncHaveMoreDataFromCachedHistory(
        mayHaveOlder: globalModel.mayHaveOlderHistory(convID),
      );
    }

    if (conversationType == ConvType.group) {
      _groupID = groupID;
      final resolvedGroupId = groupID ?? convID;
      final selfId = selfModel.loginInfo?.userID?.trim() ?? '';
      if (selfId.isNotEmpty) {
        final cachedSelf = GroupMemberStore.instance.memberOf(
          resolvedGroupId,
          selfId,
        );
        if (cachedSelf != null) {
          selfMemberInfo = cachedSelf;
        }
      }
      final skipOpenNotify = globalModel.hasInitialHistoryLoaded(convID) &&
          globalModel.rawMessageCount(convID) > 0;
      if (!skipOpenNotify) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isChatGenerationCurrent(initGeneration, initConversationID)) {
            _notify();
          }
        });
      }
    }

    globalModel.removeRoamingSyncListener(_onRoamingSyncFinished);
    globalModel.addRoamingSyncListener(_onRoamingSyncFinished);
    _isInit = true;
  }
~~~

68. [TUIChatSeparateViewModel.loadChatRecord](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:1822>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，1822–1852 行。

~~~dart
Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,

    /// true：忽略「内存已有足够条数」短路，强制重拉最新一页（回底用）。
    bool forceReloadNewest = false,
  }) {
    // A retained outgoing/live row is not the edge of this history segment.
    if (direction == LoadDirection.latest &&
        !forceReloadNewest &&
        historyNewerPageCursor != null) {
      lastMsg = historyNewerPageCursor;
      lastMsgID = TencentUtils.checkString(lastMsg?.msgID);
      lastMsgSeq = int.tryParse(lastMsg?.seq ?? '') ?? -1;
    }
    // Ensure runner is initialized (binds into _pagination) before delegating.
    final runner = _historyLoadRunner;
    return runner.pagination.loadChatRecord(
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      direction: direction,
      lastMsg: lastMsg,
      forceReloadNewest: forceReloadNewest,
    );
  }
~~~

69. [TUIChatSeparateViewModel._sendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:5409>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，5409–5683 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>> _sendMessage({
    required String id,
    required String convID,
    required ConvType convType,
    V2TimMessage? messageInfo,
    OfflinePushInfo? offlinePushInfo,
    bool? onlineUserOnly = false,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool? isExcludedFromUnreadCount,
    bool? needReadReceipt,
    String? cloudCustomData,
    String? localCustomData,
    bool? isEditStatusMessage = false,
    bool? isExcludedFromContentModeration,
    bool preserveTargetGroupID = false,
  }) async {
    debugPrint(
      '[IM_SEND_INTENT] conv=$convID type=${convType.name} clientId=$id',
    );
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    final target = _resolveSendTarget(
      convID: convID,
      convType: convType,
      messageID: id,
    );
    if (target == null) {
      debugPrint(
        '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=invalid_target',
      );
      removeSendingMessageID(id);
      final invalidResult = _buildInvalidTargetResult(
        id: id,
        convID: convID,
        convType: convType,
        messageInfo: messageInfo,
      );
      if (messageInfo != null) {
        messageInfo.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        globalModel.updateMessage(
          invalidResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
      }
      return invalidResult;
    }
    String receiver = target.receiver;
    String groupID = target.groupID;
    // IM peer-blacklist is sendMessage code (20007 if console fails closed).
    // App POST /me/blocks does not produce 20007. This gate only reads
    // confirmed relation canMessage=false.
    if (convType == ConvType.c2c) {
      final snapshot = C2cFriendMessageGuard.cachedUiSnapshot(receiver);
      if (snapshot != null &&
          snapshot.decision == C2cSendPermissionDecision.blocked &&
          snapshot.relationConfirmed) {
        debugPrint(
          '[IM_SEND_BLOCKED] conv=$convID clientId=$id reason=relation_blocked',
        );
        removeSendingMessageID(id);
        final failedMessage = messageInfo ??
            V2TimMessage(
              id: id,
              msgID: id,
              elemType: MessageElemType.V2TIM_ELEM_TYPE_NONE,
            );
        failedMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        final blockedResult = V2TimValueCallback<V2TimMessage>(
          code: C2cBlockedOutgoingMessageSync.blockedCode,
          desc: 'friend relation blocked',
          data: failedMessage,
        );
        globalModel.applyOutgoingSendResult(
          blockedResult,
          convID,
          id,
          convType,
          groupType,
          setInputField,
        );
        return blockedResult;
      }
    }
    // Dispatch C2C messages without a blocking friend-relation HTTP lookup.
    // Provider send results own rejection; UI relation refresh runs separately.
    if (convType == ConvType.group &&
        _groupType == null &&
        !preserveTargetGroupID) {
      await loadGroupInfo(groupID);
    }
    // SelfHosted 拉到的真源 groupID（如 @TGS#_mc…）优先于会话里错误加成的 ID。
    final infoGroupId = _groupInfo?.groupID?.trim() ?? '';
    if (convType == ConvType.group &&
        !preserveTargetGroupID &&
        infoGroupId.isNotEmpty &&
        infoGroupId != groupID &&
        (_looksLikeCommunityGroupId(infoGroupId) ||
            !_looksLikeCommunityGroupId(groupID))) {
      groupID = infoGroupId;
      if (_groupID != infoGroupId) {
        _groupID = infoGroupId;
      }
    }
    final useReadReceipt =
        (needReadReceipt ?? chatConfig.isShowReadingStatus) &&
            (convType != ConvType.group || _isReadReceiptAllowedGroup) &&
            !_looksLikeCommunityGroupId(groupID);
    if (!canSendCapturedMedia) {
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'media session changed',
        data: messageInfo,
      );
    }
    if (messageInfo != null) {
      setLoadingMessageMap(convID, messageInfo);
    }
    final mediaKind = switch (messageInfo?.elemType) {
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE => 'image',
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO => 'video',
      MessageElemType.V2TIM_ELEM_TYPE_FILE => 'file',
      _ => null,
    };
    if (mediaKind != null) {
      final raw = localCustomData ?? messageInfo?.localCustomData;
      try {
        final decoded = raw == null || raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
        if (decoded is Map) {
          localCustomData = jsonEncode({...decoded, 'mediaSendKind': mediaKind});
          messageInfo?.localCustomData = localCustomData;
        }
      } catch (_) {
        // Preserve opaque metadata; it keeps the legacy serial admission.
      }
    }
    final coordinatedSend = await ImOutgoingSendCoordinator.instance.send(
      messageService: _messageService,
      sdkLocalId: id,
      conversationId: convType == ConvType.group ? groupID : receiver,
      conversationType: convType == ConvType.group
          ? ImConversationType.group
          : ImConversationType.c2c,
      receiver: receiver,
      groupID: groupID,
      fallbackMessage: messageInfo,
      needReadReceipt: useReadReceipt,
      priority: priority,
      localCustomData: localCustomData ?? messageInfo?.localCustomData,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount ?? false,
      offlinePushInfo: offlinePushInfo,
      onlineUserOnly: onlineUserOnly ?? false,
      isExcludedFromContentModeration: isExcludedFromContentModeration ?? false,
      businessCloudCustomData: cloudCustomData ??
          (showC2cMessageEditStatus == true
              ? json.encode({
                  "messageFeature": {"needTyping": 1, "version": 1},
                })
              : ""),
      persistOutbox: isEditStatusMessage != true,
      expectedSessionIdentity: _outgoingMediaIdentity,
      onSyncMsgID: (syncMsgID) {
        globalModel.bindOutgoingSyncMsgId(convID, id, syncMsgID);
      },
    );
    final sendMsgRes = coordinatedSend.sdkResult;
    if (!canSendCapturedMedia) return sendMsgRes;
    debugPrint(
      '[IM_SEND_COORDINATOR_RESULT] conv=$convID clientId=$id '
      'code=${sendMsgRes.code} desc=${sendMsgRes.desc} '
      'outcomeUnknown=${coordinatedSend.outcomeUnknown}',
    );
    if (_isOutgoingMediaCancelled(id) ||
        _isOutgoingMediaCancelled(messageInfo?.msgID) ||
        _isOutgoingMediaCancelled(sendMsgRes.data?.msgID)) {
      removeSendingMessageID(id);
      final sdkMsgID = TencentUtils.checkString(sendMsgRes.data?.msgID);
      if (sendMsgRes.code == 0 && sdkMsgID != null) {
        try {
          await _messageService.revokeMessage(
            msgID: sdkMsgID,
            webMessageInstance: sendMsgRes.data?.messageFromWeb,
          );
        } catch (_) {}
        await _messageService.deleteMessageFromLocalStorage(
          msgID: sdkMsgID,
          webMessageInstance: sendMsgRes.data?.messageFromWeb,
        );
      }
      globalModel.markOutgoingSendFailedByIdentity(
        conversationID: convID,
        clientId: id,
        msgID: sdkMsgID ?? messageInfo?.msgID,
        reason: 'cancelled',
      );
      globalModel.clearMessageProgress(id);
      globalModel.clearMessageProgress(messageInfo?.msgID);
      globalModel.clearMessageProgress(sendMsgRes.data?.msgID);
      _clearOutgoingMediaCancelled(id);
      _clearOutgoingMediaCancelled(messageInfo?.msgID);
      _clearOutgoingMediaCancelled(sendMsgRes.data?.msgID);
      return V2TimValueCallback<V2TimMessage>(
        code: -1,
        desc: 'cancelled',
        data: messageInfo,
      );
    }
    removeSendingMessageID(id);
    OutgoingVisibleProbe.log(
      'send_sdk_result',
      conversationID: convID,
      message: sendMsgRes.data ?? messageInfo,
      extras: <String, Object?>{
        'code': sendMsgRes.code,
        'desc': sendMsgRes.desc,
        'clientId': id,
        'hasData': sendMsgRes.data != null,
        'dataMsgID': sendMsgRes.data?.msgID ?? '',
        ...OutgoingVisibleProbe.trackedInList(
          globalModel.rawMessageList(convID),
        ),
      },
    );
    if (sendMsgRes.data != null) {
      OutgoingVisibleProbe.rememberSent(
        conversationID: convID,
        message: sendMsgRes.data!,
      );
    }
    // IM-08: when the SDK Future resolves OutcomeUnknown, the dispatch path
    // cannot prove the provider accepted or rejected the operation. The
    // Outbox main + recovery copy already record OutcomeUnknown; the
    // single Writer must keep the optimistic bubble in SENDING and wait
    // for history/realtime to claim it. Auto-committing a success/failed
    // projection here would resurrect an in-flight message or flash a
    // red retry icon on a still-pending send.
    var projectionCommitted = true;
    if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {
      projectionCommitted = globalModel.applyOutgoingSendResult(
        sendMsgRes,
        convID,
        id,
        convType,
        groupType,
        setInputField,
      );
    } else if (coordinatedSend.outcomeUnknown) {
      projectionCommitted = false;
    }
    if (!coordinatedSend.outcomeUnknown) {
      globalModel.insertPeerRejectedLocalTip(
        convID,
        sendMsgRes.code,
        clientId: id,
      );
    }
    if (projectionCommitted && coordinatedSend.canCompleteProjection) {
      await ImOutgoingSendCoordinator.instance.completeSuccessfulProjection(
        coordinatedSend,
      );
    }
    if (lifeCycle?.messageDidSend != null) {
      lifeCycle!.messageDidSend(sendMsgRes);
    }

    return sendMsgRes;
  }
~~~

70. [TUIChatSeparateViewModel.sendTextAtMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:5938>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，5938–6001 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> sendTextAtMessage({
    required String text,
    required String convID,
    required ConvType convType,
    required List<String> atUserList,
    List<GroupMentionOccurrence> mentionOccurrences = const [],
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final typingBase = showC2cMessageEditStatus == true
        ? json.encode({
            "messageFeature": {"needTyping": 1, "version": 1},
          })
        : null;
    final cloudCustomData = mentionOccurrences.isEmpty
        ? null
        : GroupMentionOccurrenceCodec.mergeIntoCloudCustomData(
            typingBase,
            mentionOccurrences,
          );
    final optimisticId = _prependOptimisticTextPlaceholder(
      text: text,
      cloudCustomData: cloudCustomData,
      groupAtUserList: atUserList,
    );
    final textATMessageInfo = await _messageService.createTextAtMessage(
      text: text,
      atUserList: atUserList,
    );
    final messageInfo = textATMessageInfo?.messageInfo;
    if (textATMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textATMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    if (cloudCustomData != null) {
      messageInfoWithSender.cloudCustomData = cloudCustomData;
    }
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textATMessageInfo.id as String,
      convType: ConvType.group,
      messageInfo: messageInfoWithSender,
      cloudCustomData: cloudCustomData,
      offlinePushInfo: tools.buildMessagePushInfo(
        textATMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }
~~~

71. [TUIChatSeparateViewModel._currentResendMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7488>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7488–7499 行。

~~~dart
V2TimMessage? _currentResendMessage(String convID, V2TimMessage original) {
    final clientId = original.id?.trim() ?? '';
    final msgID = original.msgID?.trim() ?? '';
    for (final current in globalModel.rawMessageList(convID) ??
        const <V2TimMessage>[]) {
      if ((clientId.isNotEmpty && current.id == clientId) ||
          (msgID.isNotEmpty && current.msgID == msgID)) {
        return current;
      }
    }
    return null;
  }
~~~

72. [TUIChatSeparateViewModel.reSendFailMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7501>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7501–7542 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> reSendFailMessage({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
  }) {
    final identity = SessionIdentityService.instance.capture();
    final current = _currentResendMessage(convID, message);
    if (current == null) return Future.value(null);
    final key = json.encode([
      identity.ownerUserId, identity.generation, convType.name,
      ArchiveHistoryProvider.normalizeConversationKey(convID),
      current.id?.isNotEmpty == true ? current.id : current.msgID,
    ]);
    final existing = _resendTasks[key];
    if (existing != null) return existing;
    bool canResend() {
      if (!SessionIdentityService.instance.isCurrent(identity) ||
          !canSendCapturedMedia) {
        return false;
      }
      final live = _currentResendMessage(convID, current);
      return live != null && live.isSelf != false &&
          globalModel.messageStatusInConversation(
            convID, clientId: live.id, msgID: live.msgID,
            fallback: OutgoingSendStatus.unconfirmed,
            elemType: live.elemType,
          ) == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (!canResend()) return Future.value(null);
    late final Future<V2TimValueCallback<V2TimMessage>?> task;
    task = Future<V2TimValueCallback<V2TimMessage>?>.microtask(() {
      if (!canResend()) return null;
      return _performFailedMessageResend(
        message: current, convID: convID, convType: convType,
        canResend: canResend,
      );
    }).whenComplete(() {
      if (identical(_resendTasks[key], task)) _resendTasks.remove(key);
    });
    _resendTasks[key] = task;
    return task;
  }
~~~

73. [TUIChatSeparateViewModel._performFailedMessageResend](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7544>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7544–7620 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> _performFailedMessageResend({
    required V2TimMessage message,
    required String convID,
    required ConvType convType,
    required bool Function() canResend,
  }) async {

    if (isWalletCardMessage(message)) {
      serviceLocator<CoreServicesImpl>().callOnCallback(
        TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("钱包消息不可转发"),
        ),
      );
      return null;
    }
    final clientId = message.id?.trim() ?? '';
    final msgID = message.msgID?.trim() ?? '';
    _clearOutgoingMediaCancelled(clientId);
    _clearOutgoingMediaCancelled(msgID);
    final localPath = TencentUtils.checkString(
          globalModel.getFileMessageLocation(clientId),
        ) ??
        TencentUtils.checkString(globalModel.getFileMessageLocation(msgID));
    if (localPath != null) {
      switch (message.elemType) {
        case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
          message.imageElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
          message.videoElem?.videoPath = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
          message.soundElem?.path = localPath;
          break;
        case MessageElemType.V2TIM_ELEM_TYPE_FILE:
          message.fileElem?.path = localPath;
          break;
      }
    }
    final recreated = await recreateOutgoingMessage(_messageService, message);
    final recreatedId = recreated?.id?.trim() ?? '';
    final recreatedMessage = recreated?.messageInfo;
    if (recreatedId.isEmpty || recreatedMessage == null || !canResend()) {
      return null;
    }
    _removeOutgoingMessage(
      convID: convID,
      clientId: clientId.isEmpty ? null : clientId,
      msgID: msgID.isEmpty ? null : msgID,
    );
    if (msgID.isNotEmpty) {
      try {
        await _messageService.deleteMessageFromLocalStorage(
          msgID: msgID,
          webMessageInstance: message.messageFromWeb,
        );
      } catch (_) {}
    }
    final outgoing = tools.setUserInfoForMessage(recreatedMessage, recreatedId);
    applyOutgoingStableIdToMessage(outgoing, recreatedId);
    outgoing.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    addSendingMessageID(recreatedId);
    _prependOutgoingMessageForConversation(
      convID,
      outgoing,
      skipEnterAnimation: true,
    );
    return _sendMessage(
      id: recreatedId,
      convID: convID,
      convType: convType,
      messageInfo: outgoing,
      cloudCustomData: TencentUtils.checkString(outgoing.cloudCustomData),
      offlinePushInfo: tools.buildMessagePushInfo(outgoing, convID, convType),
    );
  }
~~~

74. [TUIChatSeparateViewModel.sendTextMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:7622>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，7622–7661 行。

~~~dart
Future<V2TimValueCallback<V2TimMessage>?> sendTextMessage({
    required String text,
    required String convID,
    required ConvType convType,
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final optimisticId = _prependOptimisticTextPlaceholder(text: text);
    final textMessageInfo = await _messageService.createTextMessage(text: text);
    final messageInfo = textMessageInfo?.messageInfo;
    if (textMessageInfo == null || messageInfo == null) {
      _markOutgoingMediaSendFailed(
        convID: conversationID,
        clientId: optimisticId,
      );
      _notifyCreateMessageFailed(TIM_t('消息创建失败，请重试'));
      return null;
    }
    final messageInfoWithSender = tools.setUserInfoForMessage(
      messageInfo,
      textMessageInfo.id!,
    );
    messageInfoWithSender.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    _adoptOptimisticOutgoingTextMessage(
      optimisticId: optimisticId,
      newMessage: messageInfoWithSender,
    );
    return _sendMessage(
      convID: convID,
      id: textMessageInfo.id as String,
      convType: convType,
      messageInfo: messageInfoWithSender,
      offlinePushInfo: tools.buildMessagePushInfo(
        textMessageInfo.messageInfo!,
        convID,
        convType,
      ),
    );
  }
~~~

75. [TUIChatSeparateViewModel._markOutgoingMediaSendFailed](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8585>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8585–8596 行。

~~~dart
void _markOutgoingMediaSendFailed({
    required String convID,
    String? clientId,
    String? msgID,
  }) {
    globalModel.markOutgoingSendFailedByIdentity(
      conversationID: convID,
      clientId: clientId,
      msgID: msgID,
      reason: 'media_failed',
    );
  }
~~~

76. [TUIChatSeparateViewModel._prependOptimisticTextPlaceholder](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8602>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8602–8623 行。

~~~dart
/// 点发送立刻上屏，不必等原生 createTextMessage。
  String _prependOptimisticTextPlaceholder({
    required String text,
    String? cloudCustomData,
    List<String>? groupAtUserList,
  }) {
    final optimisticId = _nextOptimisticClientId();
    final optimistic = tools.setUserInfoForMessage(
      V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: text),
        cloudCustomData: cloudCustomData,
        groupAtUserList: groupAtUserList,
      ),
      optimisticId,
    );
    optimistic.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    applyOutgoingStableIdToMessage(optimistic, optimisticId);
    addSendingMessageID(optimisticId);
    _prependOutgoingMessage(optimistic);
    return optimisticId;
  }
~~~

77. [TUIChatSeparateViewModel._adoptOptimisticOutgoingTextMessage](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart:8625>)，原文件 third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart，8625–8644 行。

~~~dart
void _adoptOptimisticOutgoingTextMessage({
    required String optimisticId,
    required V2TimMessage newMessage,
  }) {
    final convID = conversationID;
    _swapOutgoingMessage(
      convID: convID,
      oldClientId: optimisticId,
      newMessage: newMessage,
    );
    final clientId = newMessage.id;
    if (clientId != null && clientId.isNotEmpty) {
      chatUiStateStore.bindMessageAlias(
        convID,
        optimisticId,
        ChatUiStateStore.messageKeyOf(newMessage),
      );
      addSendingMessageID(clientId);
    }
  }
~~~

78. [_TIMUIKitHistoryMessageListState._scheduleMessagesFirstVisibleAfterReveal](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:798>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart，798–841 行。

~~~dart
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
~~~

79. [_HeadMessageLayoutReporter](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:15256>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart，15256–15273 行。

~~~dart
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
~~~

80. [_HeadMessageLayoutReporterState](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart:15275>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart，15275–15313 行。

~~~dart
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
~~~

81. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_peek_service.dart:1>)，原文件 lib/src/services/conversation_peek_service.dart，1–393 行。

~~~dart
import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/message_media_metadata_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_batch.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_history_peek_loader.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

class ConversationPeekLoadResult {
  const ConversationPeekLoadResult({
    required this.messages,
    required this.hasMoreOlder,
    required this.isFinished,
    this.receivedCloudResponse = false,
    this.requestedCursor,
    this.returnedBounds = const MessageHistoryBounds.empty(),
    this.batchKind = MessageHistoryBatchKind.olderPage,
  });

  final List<V2TimMessage> messages;
  final bool hasMoreOlder;
  final bool isFinished;

  /// Distinguishes a successful empty SDK page from a missing/error response.
  /// This is transport metadata, not proof that history is complete.
  final bool receivedCloudResponse;
  final MessageHistoryCursor? requestedCursor;
  final MessageHistoryBounds returnedBounds;
  final MessageHistoryBatchKind batchKind;

  /// Converts the legacy peek result into the typed history envelope used by
  /// reconciliation. Generation and clear epoch belong to the caller because
  /// they are allocated around the actual async request.
  MessageHistoryBatch<V2TimMessage> toBatch({
    required String conversationKey,
    required MessageReconciliationSource requestedSource,
    required MessageReconciliationSource actualSource,
    required int requestGeneration,
    required int clearEpoch,
    required bool cloudResponseProven,
    MessageHistoryBatchKind? batchKind,
    Iterable<V2TimMessage>? messages,
  }) {
    final effectiveMessages =
        messages?.toList(growable: false) ?? this.messages;
    return MessageHistoryBatch<V2TimMessage>(
      conversationKey: conversationKey,
      requestedSource: requestedSource,
      actualSource: actualSource,
      batchKind: batchKind ?? this.batchKind,
      requestGeneration: requestGeneration,
      clearEpoch: clearEpoch,
      requestedCursor: requestedCursor,
      returnedBounds: messages == null && !returnedBounds.isEmpty
          ? returnedBounds
          : _boundsForMessages(effectiveMessages),
      isFinished: isFinished,
      hasMoreOlder: hasMoreOlder,
      cloudHasMoreNewer: false,
      cloudResponseProven: cloudResponseProven,
      messages: effectiveMessages,
    );
  }

  static MessageHistoryBounds _boundsForMessages(
    Iterable<V2TimMessage> messages,
  ) {
    V2TimMessage? oldest;
    V2TimMessage? newest;
    for (final message in messages) {
      if ((message.msgID?.trim() ?? '').isEmpty) continue;
      if (oldest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, oldest) <
              0) {
        oldest = message;
      }
      if (newest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, newest) >
              0) {
        newest = message;
      }
    }
    return MessageHistoryBounds(
      oldestMsgID: oldest?.msgID,
      newestMsgID: newest?.msgID,
      oldestSeq: int.tryParse(oldest?.seq?.trim() ?? ''),
      newestSeq: int.tryParse(newest?.seq?.trim() ?? ''),
    );
  }
}

class ConversationPeekService {
  ConversationPeekService._();

  static const int peekMessageCount = 15;

  static final MessageService _messageService =
      serviceLocator<MessageService>();

  static bool canPeek(V2TimConversation conversation) {
    if ((conversation.userID ?? '').trim() == '10000') {
      return false;
    }
    return _isGroup(conversation)
        ? (conversation.groupID?.trim().isNotEmpty ?? false)
        : (conversation.userID?.trim().isNotEmpty ?? false);
  }

  static Future<ConversationPeekLoadResult> loadInitial(
    V2TimConversation conversation,
  ) {
    return _loadOlder(
      conversation: conversation,
      anchor: null,
      count: peekMessageCount,
    );
  }

  /// 进入聊天页首屏：C2C / 群聊只打 IM 云端最新一页。
  static Future<ConversationPeekLoadResult> loadForChatEntry(
    V2TimConversation conversation,
  ) {
    return _loadCloudOnlyForChatEntry(conversation);
  }

  /// C2C / 群聊进页只打 IM 云端最新一页，不和本地库/归档焊在一起。
  static Future<ConversationPeekLoadResult> _loadCloudOnlyForChatEntry(
    V2TimConversation conversation,
  ) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: <V2TimMessage>[],
        hasMoreOlder: false,
        isFinished: true,
      );
    }
    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    // Route the warm cloud read through IM-06 as well. This keeps chat-entry
    // verification in the same per-conversation priority queue as a user's
    // upward pagination request, so a warm read cannot sit ahead of a real
    // user action or hide the native SDK error metadata.
    final result = await serviceLocator<TUIChatGlobalModel>()
        .getHistoryMessageListThroughIm06(
      count: HistoryMessageDartConstant.initialOpenFetchCount,
      getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      userID: userID,
      groupID: groupID,
    );
    final rawMessages = result?.messageList ?? const <V2TimMessage>[];
    var messages = _dedupeMessages(rawMessages);
    messages = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: messages,
    );
    await MessageMediaMetadataStore.instance.hydrateMessages(messages);
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(messages));
    return ConversationPeekLoadResult(
      messages: messages,
      hasMoreOlder:
          messages.length >= HistoryMessageDartConstant.initialOpenFetchCount ||
              result == null ||
              !result.isFinished,
      isFinished: result?.isFinished ?? false,
      receivedCloudResponse: result != null,
      batchKind: MessageHistoryBatchKind.latestWindow,
      requestedCursor: const MessageHistoryCursor(
        direction: MessageHistoryCursorDirection.latest,
      ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(messages),
    );
  }

  static Future<void> _hydrateLocalMessageMetadata(
    List<V2TimMessage> messages,
  ) async {
    try {
      await MessageMediaMetadataStore.instance.hydrateMessages(messages);
      unawaited(
        MessageMediaMetadataStore.instance.persistFromMessages(messages),
      );
    } catch (_) {
      // A media metadata miss cannot invalidate the local history snapshot.
    }
  }

  /// 冷启动聊天首屏快路径：只读 IM SDK 本地库，不等待云端或归档。
  /// 查到的消息应立即上屏；完整窗口随后由 [loadForChatEntry] 异步校对。
  static Future<ConversationPeekLoadResult> loadLocalForChatEntry(
    V2TimConversation conversation,
  ) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: <V2TimMessage>[],
        hasMoreOlder: false,
        isFinished: true,
      );
    }
    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    final result = await MessageHistoryPeekLoader.loadOlderLocalOnlyResult(
      messageService: _messageService,
      count: HistoryMessageDartConstant.initialOpenFetchCount,
      userID: userID,
      groupID: groupID,
    );
    var messages = _dedupeMessages(result.messageList);
    messages = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: messages,
    );
    // Text and message identity are ready after the SDK local query. Media
    // metadata is enrichment and must not delay the local first frame.
    unawaited(_hydrateLocalMessageMetadata(messages));
    return ConversationPeekLoadResult(
      messages: messages,
      hasMoreOlder:
          messages.length >= HistoryMessageDartConstant.initialOpenFetchCount ||
              !result.isFinished,
      isFinished: result.isFinished,
      batchKind: MessageHistoryBatchKind.localSnapshot,
      requestedCursor: const MessageHistoryCursor(
        direction: MessageHistoryCursorDirection.latest,
      ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(messages),
    );
  }

  static Future<ConversationPeekLoadResult> loadOlder({
    required V2TimConversation conversation,
    required V2TimMessage anchor,
  }) {
    return _loadOlder(
      conversation: conversation,
      anchor: anchor,
      count: peekMessageCount,
    );
  }

  static Future<ConversationPeekLoadResult> _loadOlder({
    required V2TimConversation conversation,
    required V2TimMessage? anchor,
    required int count,
  }) async {
    if (!canPeek(conversation)) {
      return const ConversationPeekLoadResult(
        messages: [],
        hasMoreOlder: false,
        isFinished: true,
      );
    }

    final isGroup = _isGroup(conversation);
    final userID = isGroup ? null : conversation.userID?.trim();
    // SDK / 归档一律裸群 ID（@TGS#…），禁止 group_ 前缀。
    final rawGroupID = conversation.groupID?.trim();
    final groupID = isGroup && rawGroupID != null && rawGroupID.isNotEmpty
        ? ChatIdFormat.canonicalGroupStorageId(rawGroupID)
        : null;
    final lastMsgID = anchor?.msgID;
    final lastMsgSeq = int.tryParse(anchor?.seq?.toString() ?? '') ?? -1;

    final peekConvKey = isGroup ? (groupID ?? '') : (userID ?? '');
    ChatHistoryTrace.log(
      'peek_load_start',
      conversationID: peekConvKey,
      extras: <String, Object?>{
        'rawGroupID': rawGroupID ?? '',
        'isGroup': isGroup,
        'count': count,
        'hasAnchor': anchor != null,
        'anchorId': anchor?.msgID ?? '',
        'anchorTs': anchor?.timestamp ?? 0,
      },
    );

    final peekResult =
        await MessageHistoryPeekLoader.loadOlderLocalThenCloudResult(
      messageService: _messageService,
      count: count,
      userID: userID,
      groupID: groupID,
      lastMsgID: lastMsgID,
      lastMsgSeq: lastMsgSeq,
    );
    final sdkMessages = peekResult.messageList;

    var merged = _dedupeMessages(sdkMessages);
    merged = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: merged,
    );
    final sdkPageFull = merged.length >= count;
    final hasMoreOlder = sdkPageFull || !peekResult.isFinished;

    merged = await _dropMessagesAtOrBeforeHistoryClear(
      conversation: conversation,
      messages: merged,
    );

    if (anchor == null && merged.length > count) {
      merged = merged.sublist(merged.length - count);
    }

    var sorted = _sortChronologically(merged);
    sorted = GroupTipsMessageHelper.applyPostMergeFilters(sorted);
    await MessageMediaMetadataStore.instance.hydrateMessages(sorted);
    unawaited(MessageMediaMetadataStore.instance.persistFromMessages(sorted));
    return ConversationPeekLoadResult(
      messages: sorted,
      hasMoreOlder: hasMoreOlder,
      isFinished: !hasMoreOlder,
      batchKind: MessageHistoryBatchKind.olderPage,
      requestedCursor: anchor == null
          ? const MessageHistoryCursor(
              direction: MessageHistoryCursorDirection.latest,
            )
          : MessageHistoryCursor(
              direction: MessageHistoryCursorDirection.older,
              lastMsgID: lastMsgID,
              lastMsgSeq: lastMsgSeq > 0 ? lastMsgSeq : null,
            ),
      returnedBounds: ConversationPeekLoadResult._boundsForMessages(sorted),
    );
  }

  static Future<List<V2TimMessage>> _dropMessagesAtOrBeforeHistoryClear({
    required V2TimConversation conversation,
    required List<V2TimMessage> messages,
  }) async {
    if (messages.isEmpty) {
      return messages;
    }
    final conversationID = conversation.conversationID.trim().isNotEmpty
        ? conversation.conversationID.trim()
        : (_isGroup(conversation)
            ? (conversation.groupID?.trim() ?? '')
            : (conversation.userID?.trim() ?? ''));
    if (conversationID.isEmpty) {
      return messages;
    }
    final clearedAt = await ConversationLocalStore.instance.historyClearedAtMs(
      conversationID,
    );
    if (clearedAt <= 0) {
      return messages;
    }
    return messages
        .where(
          (message) =>
              ConversationLocalStore.messageTimestampMs(message) > clearedAt,
        )
        .toList(growable: false);
  }

  static bool _isGroup(V2TimConversation conversation) {
    return conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
  }

  static List<V2TimMessage> _dedupeMessages(List<V2TimMessage> messages) {
    if (messages.isEmpty) {
      return const [];
    }
    return TUIChatGlobalModel.dedupeMessages(messages);
  }

  static List<V2TimMessage> _sortChronologically(List<V2TimMessage> messages) {
    return TUIChatGlobalModel.sortMessagesChronologicallyAsc(messages);
  }
}

~~~

82. [@file](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/perf_timeline.dart:1>)，原文件 lib/src/services/perf_timeline.dart，1–10 行。

~~~dart
import 'dart:developer' as developer;

class PerfTimeline {
  PerfTimeline._();

  static void instant(String name, {Map<String, Object?> arguments = const {}}) {
    developer.Timeline.instantSync(name, arguments: arguments);
  }
}

~~~

83. [ConversationUnreadClearService.clearLocalForOpenFast](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_unread_clear_service.dart:651>)，原文件 lib/src/services/conversation_unread_clear_service.dart，651–707 行。

~~~dart
/// 进聊天前快速清零未读：内存同帧清零，持久化完成后立即上报 SDK。
  static Future<void> clearLocalForOpenFast({
    required V2TimConversation conversation,
    void Function(String conversationID)? markViewModelReadLocally,
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final conversationID = conversation.conversationID.trim();
    if (conversationID.isEmpty) {
      return;
    }
    final unreadBefore = conversation.unreadCount ?? 0;
    final aggregate = ConversationUnreadAggregate.instance;
    final aggregateBefore =
        '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}';
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    final watermark = _watermarkFor(conversation);
    beginConversationChatSession(conversationID);
    aggregate.clearSdkTotalForLocalProjection();
    ChatSessionController.instance.zeroUnreadLocally(conversationID);
    conversation.unreadCount = 0;
    ConversationLocalStore.instance.recordReadClearedAnchor(
      conversationID,
      lastMessageId: conversation.lastMessage?.msgID,
    );
    markViewModelReadLocally?.call(conversationID);
    ConversationUnreadTrace.log(
      'clear_local_open_fast',
      conversationID: conversationID,
      unreadBefore: unreadBefore,
      unreadAfter: 0,
      extras: <String, Object?>{
        'path': 'fast',
        'scope': isGroupConversation(conversation) ? 'group' : 'c2c',
        'aggregateBefore': aggregateBefore,
        'aggregateAfter':
            '${aggregate.c2cNotifiableUnreadSum}/${aggregate.groupNotifiableUnreadSum}',
      },
    );
    unawaited(
      ConversationSyncService.instance.markConversationReadLocally(
        conversationID,
        forceImmediateUi: true,
      ),
    );
    if (owner.isEmpty || unreadBefore <= 0) {
      return;
    }
    unawaited(
      _persistOpenReadIntentAndDispatch(
        ownerUserId: owner,
        conversationID: conversationID,
        lastReadMessageId: conversation.lastMessage?.msgID ?? '',
        watermark: watermark,
        sessionGeneration: sessionGeneration,
      ),
    );
  }
~~~

84. [ConversationUnreadClearService._persistOpenReadIntentAndDispatch](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/src/services/conversation_unread_clear_service.dart:709>)，原文件 lib/src/services/conversation_unread_clear_service.dart，709–735 行。

~~~dart
static Future<void> _persistOpenReadIntentAndDispatch({
    required String ownerUserId,
    required String conversationID,
    required String lastReadMessageId,
    required _ConversationReadWatermark watermark,
    required int sessionGeneration,
  }) async {
    try {
      await ConversationReadOutboxStore.instance.enqueue(
        ownerUserId: ownerUserId,
        conversationId: conversationID,
        lastReadMessageId: lastReadMessageId,
        cleanTimestamp: watermark.timestamp,
        cleanSequence: watermark.sequence,
      );
      _recordReadIntent(conversationID);
      if (!_isCurrentSession(sessionGeneration)) return;
      await scheduleSdkUnreadClean(
        conversationID: conversationID,
        trigger: SdkUnreadCleanTrigger.open,
        hadUnread: true,
      );
    } catch (e) {
      debugPrint('persist open read outbox failed errorType=${e.runtimeType}');
      await _armReadOutboxRetryTimer();
    }
  }
~~~

85. [ChatImageMessagePrefetch.prepareFirstWindowMedia](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:770>)，原文件 lib/utils/chat_image_message_prefetch.dart，770–836 行。

~~~dart
/// Resolves only the newest image rows that can be visible at the bottom of
  /// the initial window, then warms their bubble thumbnail cache. The caller
  /// returns immediately by default; callers that opt into [awaitNetwork] get a
  /// bounded wait. URL/image work continues in the background and the same
  /// message objects are updated in place.
  static Future<void> prepareFirstWindowMedia(
    Iterable<V2TimMessage?> messages, {
    Duration budget = initialMediaBudget,
    bool awaitNetwork = false,
    void Function(V2TimMessage message)? onMessageResolved,
  }) async {
    if (budget <= Duration.zero) {
      return;
    }
    final selected = _selectInitialMediaMessages(messages);
    if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
      ChatCoverDiag.log('prepare', '-', 'selected=${selected.length} budgetMs=${budget.inMilliseconds} awaitNetwork=$awaitNetwork');
      for (final message in selected) {
        ChatCoverDiag.log('selected', message.msgID ?? message.id ?? '-',
            'type=${message.elemType} ts=${message.timestamp} image=${message.imageElem != null} video=${message.videoElem != null}');
      }
    }
    if (selected.isEmpty) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    // Only a very small local-cache warm is allowed to delay the first frame.
    // Remote covers must never hold chat navigation, even when awaitNetwork is
    // false: network warming continues after the route can render.
    final localSelected = selected
        .where((message) => _resolveLocalBubblePath(message) != null)
        .toList(growable: false);
    if (localSelected.isNotEmpty) {
      await warmWithBudget(
        localSelected,
        _shorterDuration(budget, initialLocalMediaBudget),
      );
    }
    if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
      ChatCoverDiag.log('prepare_warm_return', '-', 'elapsedMs=${stopwatch.elapsedMilliseconds}');
    }
    final resolveBudget = _shorterDuration(budget, initialMediaUrlBudget);
    final resolveTask = resolveOnlineUrlsForMessages(
      selected,
      budget: resolveBudget,
      includeSelf: true,
      onMessageResolved: onMessageResolved,
    );
    if (!awaitNetwork) {
      // Metadata hydration remains in the task, but URL lookup and image
      // decode must never hold the history commit or route transition.
      unawaited(
        resolveTask.then((_) async {
          final remaining = budget - stopwatch.elapsed;
          if (remaining > Duration.zero) {
            await warmWithBudget(selected, remaining);
          }
        }).catchError((_) {}),
      );
      return;
    }
    await resolveTask;
    final remaining = budget - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await warmWithBudget(selected, remaining);
    }
  }
~~~

86. [ChatImageMessagePrefetch.warmWithBudget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:1023>)，原文件 lib/utils/chat_image_message_prefetch.dart，1023–1074 行。

~~~dart
static Future<void> warmWithBudget(
    Iterable<V2TimMessage?> messages,
    Duration budget,
  ) async {
    final jobs = <Future<void>>[];
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    for (var index = list.length - 1; index >= 0; index--) {
      if (jobs.length >= 4) {
        break;
      }
      final message = list[index];
      if (message.videoElem != null) {
        final cover = chatVideoCoverProvider(message.videoElem!);
        if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
          ChatCoverDiag.log('warm_video', message.msgID ?? '-', 'provider=${cover?.runtimeType}');
        }
        if (cover != null) jobs.add(_warmProvider(cover));
        continue;
      }
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null) {
        continue;
      }
      final url = resolveBubbleThumbUrl(message);
      final localPath = _resolveLocalBubblePath(message);
      if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
        ChatCoverDiag.log('warm_image', message.msgID ?? '-', 'local=${localPath != null} url=${url != null}');
      }
      if (url == null && localPath == null) {
        continue;
      }
      jobs.add(
        localPath != null
            ? _warmLocalImage(
                localPath,
                chatBubbleImageCacheKey(message.msgID, url: localPath),
                decodeByWidth: _decodeBubbleImageByWidth(message),
              )
            : _warmNetworkImage(
                url!,
                chatBubbleImageCacheKey(message.msgID, url: url),
                decodeByWidth: _decodeBubbleImageByWidth(message),
              ),
      );
    }
    if (jobs.isEmpty) {
      return;
    }
    try {
      await Future.wait(jobs).timeout(budget);
    } catch (_) {}
  }
~~~

87. [ChatImageMessagePrefetch._selectInitialMediaMessages](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:848>)，原文件 lib/utils/chat_image_message_prefetch.dart，848–868 行。

~~~dart
static List<V2TimMessage> _selectInitialMediaMessages(
    Iterable<V2TimMessage?> messages,
  ) {
    final list = messages.whereType<V2TimMessage>().toList(growable: false);
    final selected = <V2TimMessage>[];
    // History windows are chronological here; walk from newest to oldest so
    // the bottom viewport gets first access to both URL and image cache.
    for (var index = list.length - 1;
        index >= 0 && selected.length < _maxInitialMediaMessages;
        index--) {
      final message = list[index];
      if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE &&
          message.imageElem == null && message.videoElem == null) {
        continue;
      }
      selected.add(message);
    }
    // Keep the public list chronological so the existing reverse walkers in
    // URL resolution and image warming still prioritize the newest row.
    return selected.reversed.toList(growable: false);
  }
~~~

88. [ChatImageMessagePrefetch.initialMediaBudget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:78>)，原文件 lib/utils/chat_image_message_prefetch.dart，78–81 行。

~~~dart
/// Media is allowed to use a small, bounded part of the chat-open budget.
  /// URL lookup is intentionally shorter than image warming so a slow IM
  /// endpoint can never hold the history gate for the whole route transition.
  static const Duration initialMediaBudget = Duration(milliseconds: 220);
~~~

89. [ChatImageMessagePrefetch.initialLocalMediaBudget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:82>)，原文件 lib/utils/chat_image_message_prefetch.dart，82–82 行。

~~~dart
static const Duration initialLocalMediaBudget = Duration(milliseconds: 24);
~~~

90. [ChatImageMessagePrefetch.initialMediaUrlBudget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/lib/utils/chat_image_message_prefetch.dart:83>)，原文件 lib/utils/chat_image_message_prefetch.dart，83–83 行。

~~~dart
static const Duration initialMediaUrlBudget = Duration(milliseconds: 140);
~~~

91. [_TUIChatState.initState](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart:456>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart，456–510 行。

~~~dart
@override
  void initState() {
    super.initState();
    ChatJitterDiag.logWidgetLifecycle(
      widget: 'TIMUIKitChat',
      phase: 'initState',
      stateHash: identityHashCode(this),
      conv: _getConvID(),
    );
    final settingModel = serviceLocator<TUISettingModel>();
    _keyboardCoordinator = KeyboardViewportTransitionCoordinator(
      onBegin: _onKeyboardTransitionBegin,
      onEnd: _onKeyboardTransitionEnd,
      persistTrustedHeight: (height) {
        settingModel.keyboardHeight = height;
      },
    );
    _keyboardCoordinator.seedCachedHeight(settingModel.keyboardHeight);
    KeyboardViewportTransitionCoordinator.active = _keyboardCoordinator;
    _imeInsetsBridge.start(_keyboardCoordinator);
    WidgetsBinding.instance.addObserver(this);
    chatGlobalModel.setChatAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    TIMUIKitChatBackgroundRegistry.instance.addListener(
      _onChatBackgroundRegistryChanged,
    );
    GroupMemberStore.instance.addListener(_onGroupMemberStoreChanged);
    DisplayNameStore.instance.addListener(_onDisplayNameStoreChanged);
    if (kProfileMode) {
      Frame.init();
    }
    ChatMainThreadPerf.retainFrameTimingProbe();
    _addGroupListener();
    model.abstractMessageBuilder = widget.abstractMessageBuilder;
    model.onTapAvatar = widget.onTapAvatar;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final view = _flutterView;
      if (view != null) {
        _keyboardCoordinator.applyFromView(view);
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) {
        return;
      }
      _updateJoinInGroupCallWidget();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      updateDraft();
    });
  }
~~~

92. [_TUIChatState.didUpdateWidget](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart:629>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart，629–684 行。

~~~dart
@override
  void didUpdateWidget(TIMUIKitChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchTargetKey(widget) != _searchTargetKey(oldWidget)) {
      // A desktop pane may reuse this State for another result in the same chat.
      isInit = false;
    }
    if (widget.conversationID != oldWidget.conversationID) {
      model.stopVoiceAutoPlay();
      _keyboardCoordinator.reset();
      serviceLocator<ChatUiStateStore>().clearConversationState(
        oldWidget.conversationID ?? '',
      );
      isInit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
      chatGlobalModel.clearCurrentConversation();
      _updateJoinInGroupCallWidget();
      final existing = widget.controller?.model;
      if (existing != null &&
          existing.conversationID == widget.conversationID) {
        model = existing;
      } else {
        model = TUIChatSeparateViewModel();
      }
      model.abstractMessageBuilder = widget.abstractMessageBuilder;
      model.onTapAvatar = widget.onTapAvatar;
      Future.delayed(const Duration(milliseconds: 50), () {
        updateDraft();
        try {
          if (autoController.hasClients &&
              !chatGlobalModel.hasPendingScrollRestore(widget.conversationID)) {
            autoController.jumpTo(autoController.position.minScrollExtent);
          }
          // ignore: empty_catches
        } catch (e) {}
      });
    }
    if (oldWidget.textFieldBuilder != null && widget.textFieldBuilder == null) {
      textFieldController = TIMUIKitInputTextFieldController();
    }
    if (oldWidget.groupMemberList != widget.groupMemberList) {
      model.groupMemberList = widget.groupMemberList == null
          ? null
          : List<V2TimGroupMemberFullInfo?>.from(widget.groupMemberList!);
    }
    if (oldWidget.config?.stickerPanelConfig?.customStickerPackages !=
            widget.config?.stickerPanelConfig?.customStickerPackages ||
        oldWidget.customEmojiStickerList != widget.customEmojiStickerList) {
      _cachedEmojiPackages = null;
      _cachedEmojiConfigKey = null;
    }
  }
~~~

93. [TIMUIKitChatProviderScope._loadData](<C:/Users/ASUS/Downloads/Telegram Desktop/99999999/third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart:1827>)，原文件 third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/tim_uikit_chat.dart，1827–2380 行。

~~~dart
void _loadData({
    V2TimMessage? initFindingMsg,
    MessageAnchor? searchJumpAnchor,
  }) {
    final count = HistoryMessageDartConstant.getCount;
    searchJumpAnchor ??= initFindingMsg == null
        ? null
        : MessageAnchor(
            conversationID: conversationID,
            convType: conversationType.index,
            msgID: initFindingMsg.msgID,
            localID: initFindingMsg.id,
            seq: initFindingMsg.seq,
            timestamp: initFindingMsg.timestamp,
            sender: initFindingMsg.sender,
            elemType: initFindingMsg.elemType);
    final isSearchJump = searchJumpAnchor != null;
    final searchRequest =
        isSearchJump ? globalModel.beginSearchJump(conversationID) : null;
    bool isCurrentSearch() =>
        searchRequest == null ||
        globalModel.isCurrentSearchJumpRequest(conversationID, searchRequest);
    final localOnlyPlainOpen =
        model!.localOnlyInitialOpen && !isSearchJump && initFindingMsg == null;
    if (!isSearchJump) {
      globalModel.clearSearchJumpStatus(conversationID);
    }
    final needUnreadSync = !localOnlyPlainOpen &&
        !isSearchJump &&
        initFindingMsg == null &&
        UnreadTonguePolicy.isEntryUnreadEnabledForConvType(
          conversationType,
          initialUnreadCount,
        );
    Future<void>(() async {
      final loadTrace = ChatOpenPerfLog.captureCurrent(
        conversationKey: conversationID,
      );
      if (!isCurrentSearch()) return;
      final initialLoadGeneration =
          ChatHistoryRecoveryCoordinator.instance.beginInitialLoad(
        conversationID,
      );
      var shouldMarkRead = false;
      String messageListSignature(List<V2TimMessage>? messages) {
        if (messages == null || messages.isEmpty) {
          return 'empty';
        }
        return messages.map((message) {
          final msgID = message.msgID?.trim() ?? '';
          if (msgID.isNotEmpty) return msgID;
          final id = message.id?.trim() ?? '';
          if (id.isNotEmpty) return id;
          final seq = message.seq?.trim() ?? '';
          if (seq.isNotEmpty) return 'seq_$seq';
          return message.timestamp?.toString() ?? '';
        }).join('|');
      }

      try {
        final target = initFindingMsg;
        if (!isSearchJump && target == null) {
          if (needUnreadSync && initialUnreadCount > 0) {
            await _ensureInitialUnreadWindowLoaded(initialUnreadCount);
            final loadedMessages = globalModel.getMessageList(conversationID);
            if (loadedMessages != null && loadedMessages.isNotEmpty) {
              // 大量未读入口先展示提示条，等用户主动查看后再上报已读。
              _lockEntryUnreadWithFrozenSeq(
                conversationID: conversationID,
                unreadCount: initialUnreadCount,
              );
              globalModel.setMessageListPosition(
                conversationID,
                HistoryMessagePosition.bottom,
                notify: true,
              );
              return;
            }
          }

          final rawCount = globalModel.rawMessageCount(conversationID);
          final currentPosition = globalModel.getMessageListPosition(
            conversationID,
          );
          if (rawCount > 0 &&
              currentPosition == HistoryMessagePosition.notShowLatest) {
            OutgoingVisibleProbe.log(
              'load_not_show_latest_wipe',
              conversationID: conversationID,
              extras: <String, Object?>{'rawCount': rawCount},
            );
            ChatOpenPerfLog.mark(
              'uikit_removeMessageList',
              conversationID: conversationID,
              extras: <String, Object?>{
                'reason': 'not_show_latest_wipe',
                'rawCount': rawCount,
              },
              trace: loadTrace,
            );
            // 搜索定位后若仍停留在历史窗口缓存，普通进入应回到最新。
            globalModel.removeMessageList(conversationID);
            globalModel.setMessageListPosition(
              conversationID,
              HistoryMessagePosition.bottom,
              notify: true,
            );
            model!.haveMoreData = false;
            model!.haveMoreLatestData = false;
          }

          if (localOnlyPlainOpen) {
            // The app-owned bootstrap is the only first-window owner. Give it
            // a tiny coalescing window, then let the page mount immediately.
            // A native SDK read can be slow on some conversations; waiting
            // 900ms and then another 3s here made route entry look frozen.
            await globalModel.awaitOpenHydrateInFlight(
              conversationID,
              timeout: const Duration(milliseconds: 80),
            );
            ChatOpenPerfLog.mark(
              'uikit_hydrate_wait_result',
              conversationID: conversationID,
              extras: <String, Object?>{
                'waitMs': 80,
                'hasInFlight':
                    globalModel.hasOpenHydrateInFlight(conversationID),
              },
              trace: loadTrace,
            );
            if (globalModel.hasOpenHydrateInFlight(conversationID)) {
              model!.syncHaveMoreDataFromCachedHistory(mayHaveOlder: true);
              ChatHistoryTrace.log(
                'chat_page_defer_open_hydrate_inflight',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'needUnreadSync': needUnreadSync,
                  'waitMs': 80,
                },
              );
              ChatOpenPerfLog.mark(
                'uikit_hydrate_deferred',
                conversationID: conversationID,
                extras: <String, Object?>{'waitMs': 80},
                trace: loadTrace,
              );
              return;
            }

            // App-owned ChatHistoryPeekBootstrap normally has already placed
            // the local snapshot into the global model. If this widget wins a
            // race before that task starts, perform one local SDK read here.
            // Never fall through to hydrateInitialHistoryPeekStyle or the
            // cloud branches below during the initial route open.
            var localMessages = globalModel.getMessageList(conversationID);
            final openResult = globalModel.openHydrateResultFor(conversationID);
            if ((localMessages == null || localMessages.isEmpty) &&
                openResult?.shouldSuppressOrdinaryLoad != true) {
              ChatOpenPerfLog.mark(
                'uikit_loadChatRecord_local_started',
                conversationID: conversationID,
                trace: loadTrace,
              );
              await model!.loadChatRecord(
                count: HistoryMessageDartConstant.initialOpenFetchCount,
                getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
              );
              localMessages = globalModel.getMessageList(conversationID);
              ChatOpenPerfLog.mark(
                'uikit_loadChatRecord_local_done',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'localCount': localMessages?.length ?? 0,
                },
                trace: loadTrace,
              );
            }
            final localCount = localMessages?.length ?? 0;
            // Local SDK is not proof of cloud continuity. Keep pagination
            // armed until the deferred cloud verification or an explicit
            // user pagination receives a terminal cloud result.
            // D-fix：若 warm scheduler 已经标 mayHaveOlder=false（SDK isFinished），
            // 沿用 false；否则保持原行为 true。
            final mayHaveOlder =
                globalModel.mayHaveOlderHistory(conversationID);
            globalModel.markLocalInitialHistoryVisible(conversationID);
            globalModel.markInitialHistoryMayHaveOlder(
              conversationID,
              mayHaveOlder: mayHaveOlder,
            );
            model!.syncHaveMoreDataFromCachedHistory(
              mayHaveOlder: mayHaveOlder,
            );
            globalModel.setMessageListPosition(
              conversationID,
              HistoryMessagePosition.bottom,
              notify: true,
            );
            shouldMarkRead = localCount > 0 && initialUnreadCount <= 0;
            ChatHistoryTrace.log(
              'chat_page_local_only_initial_done',
              conversationID: conversationID,
              extras: <String, Object?>{
                'localCount': localCount,
                'mayHaveOlder': mayHaveOlder,
              },
            );
            return;
          }

          // Non-local/search/unread entry paths retain their existing bounded
          // coordination because they have explicit positioning semantics.
          await globalModel.awaitOpenHydrateInFlight(
            conversationID,
            timeout: const Duration(milliseconds: 900),
          );
          if (globalModel.hasOpenHydrateInFlight(conversationID)) {
            // A Dart timeout does not cancel the native SDK request. Do not
            // create a second logical first-window owner after the bounded
            // wait; the app bootstrap will publish its result and the normal
            // post-open recovery path may retry only after the flight ends.
            await globalModel.awaitOpenHydrateInFlight(
              conversationID,
              timeout: const Duration(milliseconds: 3000),
            );
            if (globalModel.hasOpenHydrateInFlight(conversationID)) {
              ChatHistoryTrace.log(
                'chat_page_defer_open_hydrate_inflight',
                conversationID: conversationID,
                extras: <String, Object?>{'needUnreadSync': needUnreadSync},
              );
              return;
            }
          }

          model!.haveMoreData = false;
          model!.haveMoreLatestData = false;

          final fetchCount = HistoryMessageDartConstant.initialOpenFetchCount;
          if (_reusePreparedInitialHistory(fetchCount)) {
            ChatHistoryTrace.log(
              'chat_page_reuse_prepared_window',
              conversationID: conversationID,
              extras: <String, Object?>{
                'rawCount': globalModel.rawMessageCount(conversationID),
                'mayHaveOlder': globalModel.mayHaveOlderHistory(conversationID),
              },
            );
            shouldMarkRead = true;
            return;
          }

          ChatHistoryTrace.log(
            'chat_page_hydrate_begin',
            conversationID: conversationID,
            extras: <String, Object?>{
              'modelConv': model!.conversationID,
              'needUnreadSync': needUnreadSync,
              'entryUnread': initialUnreadCount,
              'rawCount': globalModel.rawMessageCount(conversationID),
              'modelRawCount': globalModel.rawMessageCount(
                model!.conversationID,
              ),
              ...ChatHistoryTrace.windowSummary(
                globalModel.messageListMap[conversationID] ??
                    globalModel.messageListMap[model!.conversationID],
                prefix: 'before',
              ),
            },
          );

          // 与会话 Peek 相同：每次进页按预览窗口 replace 首屏（不信任旧暖缓存）。
          final peekRefreshed = await model!.hydrateInitialHistoryPeekStyle(
            count: fetchCount,
            plainOpen: true,
          );
          final afterPeekCount = globalModel.rawMessageCount(conversationID);
          ChatHistoryTrace.log(
            'chat_page_hydrate_end',
            conversationID: conversationID,
            extras: <String, Object?>{
              'peekRefreshed': peekRefreshed,
              'afterPeekCount': afterPeekCount,
              'willFallthroughLoad': peekRefreshed && afterPeekCount == 0,
              'modelAfterCount': globalModel.rawMessageCount(
                model!.conversationID,
              ),
              ...ChatHistoryTrace.windowSummary(
                globalModel.messageListMap[conversationID] ??
                    globalModel.messageListMap[model!.conversationID],
                prefix: 'after',
              ),
            },
          );
          if (peekRefreshed && afterPeekCount > 0) {
            // 首屏 replace 后务必恢复上拉开关，避免 haveMoreData 被误留 false。
            model!.syncHaveMoreDataFromCachedHistory(
              mayHaveOlder: globalModel.mayHaveOlderHistory(conversationID) ||
                  afterPeekCount >=
                      HistoryMessageDartConstant.initialOpenFetchCount ||
                  model!.haveMoreData,
            );
            shouldMarkRead = true;
            return;
          }
        }
        if (isSearchJump && searchJumpAnchor != null) {
          // Keep a local non-null reference across the await below. Dart
          // cannot promote the captured variable after an async suspension.
          final anchor = searchJumpAnchor;
          globalModel.setSearchJumpStatus(
            conversationID,
            SearchJumpStatus.loading,
            requestID: searchRequest,
            notify: true,
          );
          OutgoingVisibleProbe.log(
            'search_jump_preserve_window',
            conversationID: conversationID,
          );
          globalModel.setMessageListPosition(
            conversationID,
            HistoryMessagePosition.notShowLatest,
            notify: false,
          );
          final loaded = await model!
              .loadListForSpecificMessage(
                anchor: anchor,
                targetMessage: target,
                searchJumpRequest: searchRequest,
              )
              .timeout(const Duration(seconds: 12));
          if (!isCurrentSearch()) return;
          final messages = globalModel.getMessageList(conversationID);
          if (loaded && messages != null && anchor.isPresentIn(messages)) {
            globalModel.setSearchJumpStatus(
              conversationID,
              SearchJumpStatus.positioning,
              requestID: searchRequest,
              notify: true,
            );
            shouldMarkRead = false;
            return;
          }
          globalModel.setSearchJumpStatus(
              conversationID, SearchJumpStatus.failed,
              requestID: searchRequest, notify: true);
          TIMUIKitClass.onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t("无法定位到原消息，请重试"),
            infoCode: 6660401,
          ));
          return;
        } else if (target != null) {
          final fallbackAnchor = MessageAnchor(
            conversationID: conversationID,
            convType: conversationType.index,
            msgID: target.msgID?.trim().isEmpty ?? true
                ? null
                : target.msgID?.trim(),
            localID:
                target.id?.trim().isEmpty ?? true ? null : target.id?.trim(),
            seq: target.seq?.trim().isEmpty ?? true ? null : target.seq?.trim(),
            timestamp: target.timestamp,
            sender: target.sender ?? target.userID,
            elemType: target.elemType,
          );
          final loaded = await model!.loadListForSpecificMessage(
            anchor: fallbackAnchor,
            targetMessage: target,
          );
          final messages = globalModel.getMessageList(conversationID);
          if (loaded && messages != null && messages.isNotEmpty) {
            shouldMarkRead = true;
            return;
          }
        }
        final fetchCount = needUnreadSync && initialUnreadCount > 0
            ? math.min(
                math.max(
                  initialUnreadCount + 12,
                  HistoryMessageDartConstant.initialOpenFetchCount,
                ),
                80,
              )
            : globalModel.hasInitialHistoryLoaded(conversationID)
                ? count
                : HistoryMessageDartConstant.initialOpenFetchCount;
        final beforeLocalSignature = messageListSignature(
          globalModel.getMessageList(conversationID),
        );
        final localLoaded = await model!.loadChatRecord(
          count: fetchCount,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
        );
        final localMessages = globalModel.getMessageList(conversationID);
        final afterLocalSignature = messageListSignature(localMessages);
        final localChanged = afterLocalSignature != beforeLocalSignature;
        final localCount = localMessages?.length ?? 0;
        final localWindowComplete = localLoaded &&
            localMessages != null &&
            localMessages.isNotEmpty &&
            localCount >= fetchCount;
        final memoryWindowNeedsReconciliation =
            globalModel.memoryWindowNeedsReconciliation(conversationID);
        if (localWindowComplete &&
            localChanged &&
            !memoryWindowNeedsReconciliation) {
          globalModel.markInitialHistoryLoaded(conversationID);
          shouldMarkRead = true;
          return;
        }
        if (localMessages != null && localMessages.isNotEmpty) {
          final cloudLoaded = await model!.loadChatRecord(
            count: fetchCount,
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          );
          final cloudMessages = globalModel.getMessageList(conversationID);
          if (cloudLoaded &&
              (!globalModel.memoryWindowNeedsReconciliation(conversationID) ||
                  globalModel.memoryWindowReconciliationCovered(
                    conversationID,
                    cloudMessages,
                  ))) {
            globalModel.markInitialHistoryLoaded(conversationID);
            globalModel.clearMemoryWindowReconciliation(conversationID);
          }
          shouldMarkRead = cloudMessages != null && cloudMessages.isNotEmpty;
          return;
        }
        final cloudLoaded = await model!.loadChatRecord(
          count: fetchCount,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
        );
        final cloudMessages = globalModel.getMessageList(conversationID);
        if (cloudLoaded &&
            (!globalModel.memoryWindowNeedsReconciliation(conversationID) ||
                globalModel.memoryWindowReconciliationCovered(
                  conversationID,
                  cloudMessages,
                ))) {
          globalModel.markInitialHistoryLoaded(conversationID);
          globalModel.clearMemoryWindowReconciliation(conversationID);
        }
        if (cloudLoaded && cloudMessages != null && cloudMessages.isNotEmpty) {
          shouldMarkRead = true;
        } else if (!isSearchJump &&
            target == null &&
            !needUnreadSync &&
            (cloudMessages == null || cloudMessages.isEmpty) &&
            !model!.haveMoreData) {
          final selected = model!.conversationViewModel.selectedConversation;
          final selectedMatches = selected != null &&
              TUIChatSeparateViewModel.selectedConversationMatchesChatId(
                conversationID: conversationID,
                selectedUserID: selected.userID,
                selectedGroupID: selected.groupID,
                selectedConversationID: selected.conversationID,
              );
          final previewLast = selectedMatches ? selected.lastMessage : null;
          final previewMsgId = previewLast?.msgID?.trim() ?? '';
          final hasListSideEvidence =
              initialUnreadCount > 0 || previewLast != null;
          // 列表侧有 lastMessage/未读时勿误标空历史，留给 Chat post-open 补拉。
          if (hasListSideEvidence) {
            // 本地 tip（ce_/localGroupTips）不能当作历史种子，否则会触发 tip
            // 整库回灌，把空会话铺满入退群灰字。
            final previewIsLocalTip = previewLast != null &&
                HistoryPaginationAnchor.isLocalInjectedMessage(previewLast);
            if (previewLast != null &&
                !previewIsLocalTip &&
                globalModel.rawMessageCount(conversationID) == 0) {
              globalModel.setMessageList(
                conversationID,
                TUIChatGlobalModel.mergeHistoricalWithInMemory(
                  existing: globalModel.messageListMap[conversationID],
                  fetched: <V2TimMessage>[previewLast],
                ),
                needResetNewMessageCount: false,
                replace: true,
              );
              globalModel.markInitialHistoryLoaded(conversationID);
              shouldMarkRead = true;
              ChatHistoryTrace.log(
                'seed_preview_last_message',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'previewMsgId': previewMsgId,
                  'entryUnread': initialUnreadCount,
                },
              );
            } else if (previewIsLocalTip &&
                globalModel.rawMessageCount(conversationID) == 0) {
              globalModel.markInitialHistoryLoaded(conversationID);
              ChatHistoryTrace.log(
                'skip_seed_preview_local_tip',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'previewMsgId': previewMsgId,
                  'entryUnread': initialUnreadCount,
                },
              );
            } else {
              ChatHistoryTrace.log(
                'skip_mark_empty_loaded_has_preview',
                conversationID: conversationID,
                extras: <String, Object?>{
                  'entryUnread': initialUnreadCount,
                  'previewMsgId': previewMsgId,
                  'localCount': localCount,
                  'cloudLoaded': cloudLoaded,
                },
              );
            }
          } else {
            // 空会话也必须结束首轮历史加载，否则消息区会一直显示 loading。
            globalModel.markInitialHistoryLoaded(conversationID);
            ChatHistoryTrace.log(
              'mark_empty_history_loaded',
              conversationID: conversationID,
              extras: <String, Object?>{
                'localCount': localCount,
                'cloudLoaded': cloudLoaded,
              },
            );
          }
        }
      } catch (error) {
        if (!isSearchJump) rethrow;
        if (!isCurrentSearch()) return;
        // This also invalidates late around-window completions in the model.
        globalModel.setSearchJumpStatus(conversationID, SearchJumpStatus.failed,
            requestID: searchRequest, notify: true);
        ChatHistoryTrace.log('search_jump_load_failed',
            conversationID: conversationID,
            extras: {'request': searchRequest, 'error': error.toString()});
        TIMUIKitClass.onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t("消息定位加载失败，请重试"),
          infoCode: 6660401,
        ));
      } finally {
        ChatHistoryRecoveryCoordinator.instance.markInitialLoadComplete(
          conversationID,
          generation: initialLoadGeneration,
        );
        if (shouldMarkRead &&
            !needUnreadSync &&
            !globalModel.hasLockedEntryUnread) {
          await model!.markMessageAsRead(force: true);
        }
      }
    });
  }
~~~

