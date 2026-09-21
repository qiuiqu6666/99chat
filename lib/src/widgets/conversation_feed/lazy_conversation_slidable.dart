import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable_plus_plus/flutter_slidable_plus_plus.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_slidable.dart';

/// 会话行侧滑：可选懒构建 ActionPane，避免列表滚动时预建全部动作按钮。
Widget lazyConversationSlidable({
  required BuildContext context,
  required Widget child,
  required List<Widget>? Function() buildStartActions,
  required List<Widget> Function() buildEndActions,
  Object groupTag = 'conversation-list',
  bool enabled = true,
}) {
  if (conversationUseDesktopContextMenu(context)) {
    return child;
  }
  if (!ConversationPerfFlags.lazyConversationSlidableActions) {
    final webFeel = conversationSlidableUseWebFeel(context);
    final start = buildStartActions();
    return conversationSlidable(
      context: context,
      child: child,
      groupTag: groupTag,
      enabled: enabled,
      startActionPane: start == null
          ? null
          : conversationActionPane(webFeel: webFeel, children: start),
      endActionPane: conversationActionPane(
        webFeel: webFeel,
        children: buildEndActions(),
      ),
    );
  }
  return _LazyConversationSlidable(
    buildStartActions: buildStartActions,
    buildEndActions: buildEndActions,
    groupTag: groupTag,
    enabled: enabled,
    child: child,
  );
}

class _LazyConversationSlidable extends StatefulWidget {
  const _LazyConversationSlidable({
    required this.child,
    required this.buildStartActions,
    required this.buildEndActions,
    required this.groupTag,
    required this.enabled,
  });

  final Widget child;
  final List<Widget>? Function() buildStartActions;
  final List<Widget> Function() buildEndActions;
  final Object groupTag;
  final bool enabled;

  @override
  State<_LazyConversationSlidable> createState() =>
      _LazyConversationSlidableState();
}

class _LazyConversationSlidableState extends State<_LazyConversationSlidable>
    with SingleTickerProviderStateMixin {
  ActionPane? _startPane;
  ActionPane? _endPane;
  bool _actionsBuilt = false;
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  late final SlidableController _slidableController;
  bool _tickerActive = true;

  @override
  void initState() {
    super.initState();
    _slidableController = SlidableController(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.of(context);
    if (conversationSlidableShouldRelease(
      wasTickerActive: _tickerActive,
      tickerActive: active,
      pointerCanceled: false,
    )) {
      _releaseGestureState();
    }
    _tickerActive = active;
  }

  void _releaseGestureState() {
    _resetPointerAccum();
    if (_slidableController.ratio != 0 && !_slidableController.closing) {
      _slidableController.close(duration: Duration.zero);
    }
  }

  @override
  void dispose() {
    _resetPointerAccum();
    _slidableController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LazyConversationSlidable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // pin/recvOpt 变化由外层 KeyedSubtree 换 key 重建 State。
    // 这里只在 enabled/groupTag 变化时丢掉面板；builder 闭包每次都是新的。
    if (conversationSlidableShouldResetLazyActions(
      oldGroupTag: oldWidget.groupTag,
      newGroupTag: widget.groupTag,
      oldEnabled: oldWidget.enabled,
      newEnabled: widget.enabled,
    )) {
      _actionsBuilt = false;
      _startPane = null;
      _endPane = null;
      return;
    }
    if (_actionsBuilt) {
      _assignPanes();
    }
  }

  void _resetPointerAccum() {
    _accumulatedDx = 0;
    _accumulatedDy = 0;
  }

  void _assignPanes() {
    final webFeel = conversationSlidableUseWebFeel(context);
    final start = widget.buildStartActions();
    _startPane = start == null
        ? null
        : conversationActionPane(webFeel: webFeel, children: start);
    _endPane = conversationActionPane(
      webFeel: webFeel,
      children: widget.buildEndActions(),
    );
  }

  void _ensureActionsBuilt() {
    if (_actionsBuilt || !mounted) {
      return;
    }
    _actionsBuilt = true;
    _assignPanes();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final webFeel = conversationSlidableUseWebFeel(context);
    return ClipRect(
      child: applyConversationSlidableTouchSlop(
        child: Listener(
          onPointerDown: (_) {
            _resetPointerAccum();
            _ensureActionsBuilt();
          },
          onPointerCancel: (_) => _releaseGestureState(),
          onPointerUp: (_) => _resetPointerAccum(),
          onPointerMove: (event) {
            if (_actionsBuilt) {
              return;
            }
            _accumulatedDx += event.delta.dx.abs();
            _accumulatedDy += event.delta.dy.abs();
            if (conversationSlidableShouldArm(
              accumulatedDx: _accumulatedDx,
              accumulatedDy: _accumulatedDy,
            )) {
              _ensureActionsBuilt();
            }
          },
          child: Slidable(
            controller: _slidableController,
            groupTag: widget.groupTag,
            enabled: widget.enabled,
            closeOnScroll: !webFeel,
            dragStartBehavior: DragStartBehavior.start,
            startActionPane: _startPane,
            endActionPane: _endPane,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
