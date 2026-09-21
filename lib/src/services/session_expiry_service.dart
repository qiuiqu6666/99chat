import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/account_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/init_step.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

class SessionExpiryService {
  SessionExpiryService({
    Future<void> Function(String reason)? clearSession,
    void Function(String message)? showMessage,
    void Function()? navigateToLogin,
    void Function(SessionInvalidationReason reason, String message)?
        markInvalidated,
  })  : _clearSession = clearSession ??
            ((reason) => AccountSessionService.instance.clearForLogout(
                  reason: reason,
                )),
        _showMessage = showMessage ?? ((message) => ToastUtils.toast(message)),
        _navigateToLogin = navigateToLogin ?? _openLogin,
        _markInvalidated = markInvalidated ?? _markLoginInvalidated;

  static final SessionExpiryService instance = SessionExpiryService();

  final Future<void> Function(String reason) _clearSession;
  final void Function(String message) _showMessage;
  final void Function() _navigateToLogin;
  final void Function(SessionInvalidationReason reason, String message)
      _markInvalidated;

  bool _handling = false;

  Future<void> handleExpired() async {
    final token = ApiClient.instance.token;
    if (token == null || token.isEmpty) {
      return;
    }
    await _handle(SessionInvalidationReason.credentialsExpired);
  }

  // IM can be kicked even when its cached business token is already absent.
  // The SessionManager fences duplicate/stale events before reaching here.
  Future<void> handleImSessionInvalidated(SessionInvalidationReason reason) =>
      _handle(reason);

  Future<void> handleAccountDisabled(String message) => _handle(
        SessionInvalidationReason.credentialsExpired,
        message: message,
        clearReason: 'account_disabled',
      );

  Future<void> _handle(SessionInvalidationReason reason,
      {String? message, String? clearReason}) async {
    if (_handling) return;
    _handling = true;
    try {
      final kicked = reason == SessionInvalidationReason.kickedOffline;
      final expiredMessage = message ??
          (kicked
              ? AppI18n.current.t(
                  zhHans: '您的账号已在其他设备登录，请重新登录',
                  zhHant: '您的帳號已在其他裝置登入，請重新登入',
                  en: 'Your account signed in on another device. Please sign in again.',
                  ja: '別の端末でログインされました。再度ログインしてください。',
                  ko: '다른 기기에서 로그인되었습니다. 다시 로그인해 주세요.',
                )
              : AppI18n.current.t(
                  zhHans: '登录状态已过期，请重新登录',
                  zhHant: '登入狀態已過期，請重新登入',
                  en: 'Session expired. Please sign in again.',
                  ja: 'ログインの有効期限が切れました。再度ログインしてください。',
                  ko: '로그인 상태가 만료되었습니다. 다시 로그인해 주세요.',
                ));
      _markInvalidated(reason, expiredMessage);
      try {
        await _clearSession(
            clearReason ?? (kicked ? 'kicked_offline' : 'session_expired'));
      } finally {
        // SDK teardown failures must not strand a logged-out user in chat.
        _showMessage(expiredMessage);
        _navigateToLogin();
      }
    } finally {
      // Do not suppress a terminal event belonging to a newly logged-in user.
      _handling = false;
    }
  }

  static void _markLoginInvalidated(
      SessionInvalidationReason reason, String message) {
    if (reason == SessionInvalidationReason.kickedOffline) {
      LoginCoordinator.instance.markKickedOffline(message: message);
    } else {
      LoginCoordinator.instance.markSessionExpired(message: message);
    }
  }

  static void _openLogin() {
    scheduleMicrotask(() {
      final context = AppNavigator.context;
      if (context != null && context.mounted) {
        InitStep.directToLogin(context);
      }
    });
  }
}
