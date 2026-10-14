import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/chat.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_viewport_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
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
class _PendingChatOpen {
  _PendingChatOpen(BuildContext context) : callers = [context];
  final List<BuildContext> callers;
  final Completer<Object?> result = Completer<Object?>();
}

String _accountRouteKey(String key) {
  final session = SessionIdentityService.instance.capture();
  return session.ownerUserId + '|' + session.generation.toString() + '|' + key;
}

class AppChatRouteRegistry {
  AppChatRouteRegistry._();

  static final AppChatRouteRegistry instance = AppChatRouteRegistry._();

  final Map<NavigatorState, Map<String, List<Route<dynamic>>>> _routes =
      <NavigatorState, Map<String, List<Route<dynamic>>>>{};

  final Map<NavigatorState, Map<String, _PendingChatOpen>> _pending = {};
  @visibleForTesting
  Future<void> Function()? prepareForTest;
  @visibleForTesting
  Route<dynamic> Function()? routeForTest;

  void register({
    required NavigatorState navigator,
    required String sessionKey,
    required Route<dynamic> route,
  }) {
    final key = _accountRouteKey(sessionKey.trim());
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

  void unregister(
      {required NavigatorState navigator,
      required String sessionKey,
      required Route<dynamic> route}) {
    final routes = _routes[navigator];
    if (routes == null) return;
    for (final list in routes.values) {
      list.removeWhere((candidate) => identical(candidate, route));
    }
    routes.removeWhere((_, list) => list.isEmpty);
    if (routes.isEmpty) _routes.remove(navigator);
  }

  Route<dynamic>? activeRoute(
    NavigatorState navigator,
    String sessionKey,
  ) {
    final key = _accountRouteKey(sessionKey.trim());
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
  void reset() {
    _routes.clear();
    _pending.clear();
    prepareForTest = null;
    routeForTest = null;
  }

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
      this,
      moving(_primaryAnimation) || moving(_secondaryAnimation),
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
  final sessionKey = appChatSessionKey(conversation) +
      (resolvedAnchor == null ? '' : '|anchor:' + resolvedAnchor.stableKey);
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
  ChatOpenTraceContext? openTrace,
  String openSource = 'route',
}) async {
  if (!context.mounted) {
    return Future<T?>.value();
  }
  final navigator = Navigator.of(context);
  final sessionKey = appChatSessionKey(conversation);
  if (openTrace == null) {
    ChatOpenPerfLog.beginOpen(
        conversationID: conversation.conversationID,
        phase: 'route_request',
        extras: <String, Object?>{'source': openSource});
    openTrace = ChatOpenPerfLog.captureCurrent(
        conversationKey: conversation.conversationID);
  }
  ChatOpenPerfLog.mark('route_requested',
      trace: openTrace, extras: <String, Object?>{'source': openSource});
  // Pipeline [2] - push_begin：进入 openOrReuseAppChat 主流程
  // 用 normalizeKey 与 conversation.dart / chat.dart / UIKit 内的 key 保持一致。
  final pipelineKey = ChatPipelineClock.normalizeKey(
    rawConversationId: conversation.conversationID,
    userId: conversation.userID,
    groupId: conversation.groupID,
  );
  ChatPipelineClock.instance.trace(pipelineKey, 'push_begin',
      extras: <String, Object?>{
        'canReuse': initFindingMsg == null && searchJumpAnchor == null
      });
  // Search/anchor opens carry a new navigation subject. Until the existing
  // Chat State exposes an in-place target-message activation API, preserve the
  // established dedicated route semantics instead of silently dropping it.
  final canReuse = initFindingMsg == null && searchJumpAnchor == null;
  final existing = canReuse
      ? AppChatRouteRegistry.instance.activeRoute(navigator, sessionKey)
      : null;
  if (existing != null) {
    ChatOpenPerfLog.mark('route_reused', trace: openTrace);
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
  final registry = AppChatRouteRegistry.instance;
  final identity = SessionIdentityService.instance.capture();
  final anchor = searchJumpAnchor ??
      (initFindingMsg == null
          ? null
          : MessageAnchor.fromConversationMessage(
              conversation, initFindingMsg));
  final reservationKey = _accountRouteKey(
      sessionKey + (anchor == null ? '' : '|anchor:' + anchor.stableKey));
  final reservations = registry._pending[navigator] ??= {};
  final pending = reservations[reservationKey];
  if (pending != null) {
    pending.callers.add(context);
    ChatOpenPerfLog.mark('route_open_shared', trace: openTrace);
    final value = await pending.result.future;
    return value is T ? value : null;
  }
  final reservation = _PendingChatOpen(context);
  reservations[reservationKey] = reservation;
  Future<Object?> openReserved() async {
    // 只等本地 fast classify。H0 由 prepareOpenViewport 并行启动，不阻塞 push。
    final waitStart = DateTime.now();
    try {
      final media = MediaQuery.maybeOf(context);
      final viewportHeight = (media?.size.height ?? 640) -
          (media?.padding.top ?? 0) -
          kToolbarHeight -
          56;
      await ChatOpenPerfLog.measure(
              'route_prepare',
              () =>
                  registry.prepareForTest?.call() ??
                  ChatOpenViewportCoordinator.instance.prepareOpenViewport(
                    conversation: conversation,
                    viewportHeight: viewportHeight,
                    source: 'route',
                  ),
              trace: openTrace,
              source: openSource)
          .timeout(ChatOpenViewportCoordinator.localBudget);
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
    if (!navigator.mounted ||
        !reservation.callers.any((caller) => caller.mounted) ||
        SessionIdentityService.instance.capture() != identity) {
      ChatOpenPerfLog.mark('route_cancelled', trace: openTrace);
      return null;
    }
    ChatOpenPerfLog.mark('route_push', trace: openTrace);
    return navigator.push<dynamic>(
      registry.routeForTest?.call() ??
          appChatRoute<dynamic>(
            conversation,
            entryUnreadCount: entryUnreadCount,
            initFindingMsg: initFindingMsg,
            searchJumpAnchor: searchJumpAnchor,
            initialC2cCanMessage: initialC2cCanMessage,
            c2cPermissionHintSource: c2cPermissionHintSource,
          ),
    );
  }

  // Reserve synchronously before the first await and retain until real pop.
  unawaited(openReserved()
      .then(reservation.result.complete,
          onError: reservation.result.completeError)
      .whenComplete(() {
    if (identical(reservations[reservationKey], reservation))
      reservations.remove(reservationKey);
    if (reservations.isEmpty &&
        identical(registry._pending[navigator], reservations))
      registry._pending.remove(navigator);
  }));
  final value = await reservation.result.future;
  return value is T ? value : null;
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
