// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/home_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/home_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/login.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_sticker_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/home_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/account_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

class InitStep {
  static void _sessionLog(String message) {
    SessionDiagnostics.log(message);
  }

  static Future<void>? _activeCheckLogin;

  static setTheme(String themeTypeString, BuildContext context) {
    final CoreServicesImpl _coreInstance = TIMUIKitCore.getInstance();
    ThemeType themeType = DefTheme.themeTypeFromString(themeTypeString);
    Provider.of<DefaultThemeData>(context, listen: false).currentThemeType =
        themeType;
    Provider.of<DefaultThemeData>(context, listen: false).theme =
        DefTheme.getTheme(themeType);
    _coreInstance.setTheme(theme: DefTheme.getTheme(themeType));
  }

  static Future<void> publishStickerPackages(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    final target = Provider.of<CustomStickerPackageData>(
      context,
      listen: false,
    );
    // InitStep can run from a widget's initState/mount path. Publishing here
    // synchronously calls notifyListeners and triggers the Flutter
    // "markNeedsBuild during build" exception. Defer the notification until
    // the current frame has completed.
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) {
      return;
    }
    UserStickerProvider.shared.publishTo(target);
  }

  static setCustomSticker(BuildContext context) async {
    await publishStickerPackages(context);
  }

  static void removeLocalSetting() async {}

  static bool _isAlreadyOnLoginPage() {
    final ctx = AppNavigator.context;
    if (ctx == null) return false;
    final route = ModalRoute.of(ctx);
    return route?.settings.name == '/login';
  }

  static void _safeDirectToLogin(
    BuildContext context, [
    Future<void> Function()? initIMSDKAndAddIMListeners,
  ]) {
    if (AuthSessionService.instance.isInAuthFlow) {
      _sessionLog('InitStep: skip directToLogin (auth flow active)');
      return;
    }
    directToLogin(context, initIMSDKAndAddIMListeners);
  }

  static void directToLogin(
    BuildContext context, [
    Future<void> Function()? initIMSDKAndAddIMListeners,
  ]) {
    if (_isAlreadyOnLoginPage()) {
      _sessionLog('InitStep: already on login, skip navigate');
      return;
    }
    _setConnectStatus(context, ConnectStatus.success);
    leaveLaunchScreen(
      toHome: false,
      context: context,
      initIMSDK: initIMSDKAndAddIMListeners,
    );
  }

  static void directToHomePage(BuildContext context) {
    StartupPerfLog.markTagged(
      'auth_route_wait_start',
      category: 'cold_start',
      details: <String, Object>{'target': 'home'},
    );
    leaveLaunchScreen(toHome: true, context: context);
  }

  static void leaveLaunchScreen({
    required bool toHome,
    required BuildContext context,
    Future<void> Function()? initIMSDK,
  }) {
    if (toHome) {
      NotificationSettingsService.instance.endColdStartBannerSuppression();
    }
    void navigate() {
      if (toHome) {
        _pushAndRemoveUntil(
          context,
          _homeRoute(context),
          debugLabel: 'home',
        );
      } else {
        _pushAndRemoveUntil(
          context,
          AppMaterialPageRoute(
            settings: const RouteSettings(name: '/login'),
            enableFullScreenBackGesture: false,
            transitionDuration:
                kIsWeb ? Duration.zero : const Duration(milliseconds: 300),
            routeVisibilityDeferredFrames: kIsWeb ? 0 : 1,
            builder: (_) => LoginPage(initIMSDK: initIMSDK),
          ),
          debugLabel: 'login',
        );
      }
    }

    if (AppNavigator.key.currentState != null) {
      navigate();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppNavigator.key.currentState != null) {
        navigate();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    });
  }

  static AppMaterialPageRoute<void> _homeRoute(BuildContext context) {
    final navContext = AppNavigator.context;
    final routeContext = context.mounted ? context : (navContext ?? context);
    final isWideScreen = routeContext.mounted &&
        TUIKitScreenUtils.getFormFactor(routeContext) == DeviceType.Desktop;
    return AppMaterialPageRoute(
      settings: const RouteSettings(name: '/homePage'),
      enableFullScreenBackGesture: false,
      transitionDuration:
          kIsWeb ? Duration.zero : const Duration(milliseconds: 300),
      routeVisibilityDeferredFrames: kIsWeb ? 0 : 1,
      builder: (_) =>
          isWideScreen ? const HomePageWideScreen() : const HomePage(),
    );
  }

  static void _pushAndRemoveUntil(
    BuildContext context,
    Route<void> route, {
    required String debugLabel,
  }) {
    NotificationSettingsService.instance.markHomeRouteNotReady();
    final nav = AppNavigator.key.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(route, (_) => false);
      _sessionLog('InitStep: navigated to $debugLabel (AppNavigator)');
      return;
    }
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(route, (_) => false);
      _sessionLog('InitStep: navigated to $debugLabel (context)');
      return;
    }
    _sessionLog('InitStep: navigate $debugLabel skipped (no navigator)');
  }

  /// Cold start: online auth + IM login before home (same order as password login).
  static Future<void> checkLogin(
    BuildContext context,
    Future<void> Function() initIMSDKAndAddIMListeners,
  ) {
    return _checkLoginGuarded(context, initIMSDKAndAddIMListeners);
  }

  static Future<void> _checkLoginGuarded(
    BuildContext context,
    Future<void> Function() initIMSDKAndAddIMListeners,
  ) async {
    if (_activeCheckLogin != null) {
      _sessionLog('InitStep: awaiting in-flight checkLogin');
      return _activeCheckLogin!;
    }

    _activeCheckLogin = _runCheckLogin(context, initIMSDKAndAddIMListeners);
    try {
      await _activeCheckLogin!;
    } finally {
      _activeCheckLogin = null;
    }
  }

  static Future<void> _runCheckLogin(
    BuildContext context,
    Future<void> Function() initIMSDKAndAddIMListeners,
  ) async {
    try {
      await _checkLoginCore(context, initIMSDKAndAddIMListeners);
    } catch (e, st) {
      _sessionLog('InitStep.checkLogin error: $e\n$st');
      final navContext = AppNavigator.context ?? context;
      if (!navContext.mounted && AppNavigator.key.currentState == null) {
        return;
      }
      _safeDirectToLogin(navContext, initIMSDKAndAddIMListeners);
    }
  }

  static Future<void> _checkLoginCore(
    BuildContext context,
    Future<void> Function() initIMSDKAndAddIMListeners,
  ) async {
    final token = ApiClient.instance.token;
    _sessionLog(
      'SESSION_LOG InitStep checkLogin start '
      'tokenValid=${ApiClient.isValidJwt(token)} '
      'hasToken=${token != null && token.trim().isNotEmpty} '
      'authFlow=${AuthSessionService.instance.isInAuthFlow}',
    );
    if (!ApiClient.isValidJwt(token)) {
      LoginCoordinator.instance.markLoggedOut();
      if (AuthSessionService.instance.isInAuthFlow) {
        _sessionLog('InitStep: skip checkLogin (no valid token, auth flow)');
        return;
      }
      _sessionLog(
          'SESSION_LOG InitStep checkLogin -> clearSessionAndGoLogin reason=invalid_token');
      await _clearSessionAndGoLogin(context, initIMSDKAndAddIMListeners);
      return;
    }

    // 先确认业务会话，再初始化 IM。未登录用户不应付出 UIKit/IM 初始化成本。
    // SessionManager 是唯一的业务会话入口；不要先调用旧的 IM 兼容回调，
    // 否则会在下面再次 restore，造成双重初始化/登录。
    if (!context.mounted) return;
    unawaited(setCustomSticker(context));

    // 新登录链路优先：业务 Session → IM 凭证 → IM SDK → 首页。
    // 唯一冷启动链路：业务 Session → IM 凭证 → IM SDK → 首页。
    _setConnectStatus(context, ConnectStatus.connecting);
    try {
      await SessionManager.instance.restore();
      if (!context.mounted) return;
      final navContext = AppNavigator.context ?? context;
      if (SessionManager.instance.state.isReady ||
          SessionManager.instance.state.phase == SessionPhase.offline) {
        unawaited(HomeBootstrap.instance.start(
          settings: Provider.of<LocalSetting>(context, listen: false),
        ));
        NotificationSettingsService.instance.endColdStartBannerSuppression();
        leaveLaunchScreen(toHome: true, context: navContext);
      } else {
        _safeDirectToLogin(context, initIMSDKAndAddIMListeners);
      }
    } catch (error, stack) {
      _sessionLog('SessionManager cold start failed: $error\n$stack');
      if (context.mounted) {
        _safeDirectToLogin(context, initIMSDKAndAddIMListeners);
      }
    }
  }

  static void _setConnectStatus(BuildContext context, ConnectStatus status) {
    if (!context.mounted) return;
    try {
      Provider.of<LocalSetting>(context, listen: false).connectStatus = status;
    } catch (_) {}
  }

  static Future<void> _clearSessionAndGoLogin(
    BuildContext context,
    Future<void> Function()? initIMSDKAndAddIMListeners,
  ) async {
    await AccountSessionService.instance.clearForLogout(
      reason: 'auth_state_invalid',
    );
    if (context.mounted) {
      directToLogin(context, initIMSDKAndAddIMListeners);
    }
  }
}
