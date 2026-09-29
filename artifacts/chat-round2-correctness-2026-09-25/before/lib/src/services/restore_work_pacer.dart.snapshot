import 'package:flutter/scheduler.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';

/// Cooperative page boundaries for account restoration. Never hold a database
/// transaction while waiting here. A cancelled session must not fetch a page.
class RestoreWorkPacer {
  RestoreWorkPacer({
    bool Function()? isScrolling,
    bool Function()? isForeground,
    bool Function()? canStartBackgroundWork,
    bool Function()? hasOpenChat,
    Future<void> Function(Duration)? delay,
  })  : _isScrolling = isScrolling ??
            (() => ChatSessionController.instance.isFeedScrollingNow),
        _isForeground = isForeground ?? _appIsForeground,
        _canStartBackgroundWork = canStartBackgroundWork ?? _interactionIsIdle,
        _hasOpenChat =
            hasOpenChat ?? (() => ActiveChatRegistry.instance.hasOpenChat),
        _delay = delay ?? Future<void>.delayed;

  static final instance = RestoreWorkPacer();
  final bool Function() _isScrolling;
  final bool Function() _isForeground;
  final bool Function() _canStartBackgroundWork;

  static bool _interactionIsIdle() {
    BackgroundMediaGate.instance.observeMetrics();
    return BackgroundMediaGate.instance.canStartOptionalWork;
  }

  final bool Function() _hasOpenChat;
  final Future<void> Function(Duration) _delay;

  static bool _appIsForeground() {
    final state = SchedulerBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<bool> beforePage({
    required bool Function() isCurrent,
    bool firstPage = false,
  }) async {
    if (!isCurrent()) return false;
    // The first page can paint immediately. Subsequent pages leave at least
    // two 60 Hz frame intervals, or a longer quiet window inside a chat.
    if (!firstPage) {
      await _delay(Duration(milliseconds: _hasOpenChat() ? 200 : 32));
    }
    while (isCurrent()) {
      if (_isForeground() && !_isScrolling() && _canStartBackgroundWork()) {
        return true;
      }
      await _delay(const Duration(milliseconds: 250));
    }
    return false;
  }
}
