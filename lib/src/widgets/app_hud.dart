import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/app_hud_indicator.dart';

/// 屏幕居中的灰底白圈 HUD（无文字），用于「点击 → 异步等待 → 提示/跳转」。
///
/// 会话模型：
/// - [begin] 立刻挂上透明触摸屏障（防止重复点击），[AppHud.defaultShowDelay]
///   之后才显示转圈，本地极快返回时不会闪一下。
/// - 任何 toast / push 之前先 `await AppHud.settleActive()`，没有活跃会话时是
///   同步 no-op；调用方用 `finally { await hud.end(); }` 兜底。
/// - 一旦显示，至少停留 [AppHud.defaultMinVisible]；[AppHud.defaultTimeout]
///   后自动收起，避免请求挂死锁住界面。
class AppHud {
  AppHud._();

  static const Duration defaultShowDelay = Duration(milliseconds: 150);
  static const Duration defaultMinVisible = Duration(milliseconds: 300);
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration _fadeDuration = Duration(milliseconds: 120);

  static AppHudSession? _active;

  static bool get isActive => _active != null;

  /// 开始一个会话；已有活跃会话时先 [forceDismiss] 再新建（后者覆盖前者）。
  static AppHudSession begin({
    Duration showDelay = defaultShowDelay,
    Duration minVisible = defaultMinVisible,
    Duration timeout = defaultTimeout,
  }) {
    if (_active != null) {
      forceDismiss();
    }
    final overlay = AppNavigator.overlay;
    if (overlay == null) {
      return AppHudSession._empty();
    }
    final session = AppHudSession._(
      minVisible: minVisible,
      fadeDuration: _fadeDuration,
    );
    final entry = OverlayEntry(
      builder: (_) => _AppHudOverlay(
        visible: session._visible,
        fadeDuration: _fadeDuration,
      ),
    );
    session._entry = entry;
    overlay.insert(entry);
    session._showTimer = Timer(showDelay, () {
      if (session.isEnded) return;
      session._shownAt = DateTime.now();
      session._visible.value = true;
    });
    session._timeoutTimer = Timer(timeout, () {
      if (session.isEnded) return;
      forceDismiss();
    });
    _active = session;
    return session;
  }

  /// 结算当前活跃会话（遵守最短停留后隐藏并移除）；无会话时立即返回。
  static Future<void> settleActive() async {
    final session = _active;
    if (session == null) return;
    await session.end();
  }

  /// 立即移除 Overlay，不等待最短停留；供路由清理与测试使用。
  static void forceDismiss() {
    final session = _active;
    _active = null;
    session?._dispose();
  }
}

class AppHudSession {
  AppHudSession._({
    required Duration minVisible,
    required Duration fadeDuration,
  })  : _minVisible = minVisible,
        _fadeDuration = fadeDuration,
        _isEmpty = false;

  AppHudSession._empty()
      : _minVisible = Duration.zero,
        _fadeDuration = Duration.zero,
        _isEmpty = true,
        _ended = true;

  final Duration _minVisible;
  final Duration _fadeDuration;
  final bool _isEmpty;
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);

  OverlayEntry? _entry;
  Timer? _showTimer;
  Timer? _timeoutTimer;
  DateTime? _shownAt;
  bool _ended = false;
  Future<void>? _ending;

  bool get isEnded => _ended;

  /// 幂等：多次调用只生效一次。
  Future<void> end() {
    if (_isEmpty) return Future<void>.value();
    final pending = _ending;
    if (pending != null) return pending;
    if (_ended) return Future<void>.value();
    _ended = true;
    return _ending = _endInternal();
  }

  Future<void> _endInternal() async {
    _showTimer?.cancel();
    _showTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final shownAt = _shownAt;
    if (shownAt != null) {
      final remaining = _minVisible - DateTime.now().difference(shownAt);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      _visible.value = false;
      await Future<void>.delayed(_fadeDuration);
    }
    _removeEntry();
    if (identical(AppHud._active, this)) {
      AppHud._active = null;
    }
  }

  void _dispose() {
    _ended = true;
    _showTimer?.cancel();
    _showTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _removeEntry();
  }

  void _removeEntry() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // Entry 可能已随 Overlay 一起销毁。
    }
  }
}

class _AppHudOverlay extends StatelessWidget {
  const _AppHudOverlay({
    required this.visible,
    required this.fadeDuration,
  });

  final ValueListenable<bool> visible;
  final Duration fadeDuration;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(
            key: ValueKey('app_hud_barrier'),
            dismissible: false,
            color: Colors.transparent,
          ),
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, isVisible, child) {
                return AnimatedOpacity(
                  duration: fadeDuration,
                  opacity: isVisible ? 1 : 0,
                  child: child,
                );
              },
              child: const IgnorePointer(
                child: AppHudIndicator(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
