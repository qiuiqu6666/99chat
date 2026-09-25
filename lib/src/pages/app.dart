// ignore_for_file: avoid_print, prefer_typing_uninitialized_variables, unused_import,  prefer_final_fields, unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_chat_i18n_tool/tools/i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/chat.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/launch_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/home_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/login.dart';
import 'package:tencent_cloud_chat_demo/src/api/presence_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/home_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/session/im_event_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/session/uikit_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lock_profile_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/account_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_outbox_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/location_upload_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_request_notice_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/resume_foreground_policy.dart';
import 'package:tencent_cloud_chat_demo/src/ui/components/app_search_bar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/forward_pick_pages.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_mutual_utils.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/listener_store.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_avatar_preview_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/platform/web_im_realtime_watchdog.dart';
import 'package:tencent_cloud_chat_demo/src/provider/custom_sticker_package.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/language_switch_sheet.dart';
import 'package:tencent_cloud_chat_demo/src/provider/login_user_Info.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/routes.dart';
import 'package:tencent_cloud_chat_demo/utils/constant.dart';
import 'package:tencent_cloud_chat_demo/utils/init_step.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/models/common_utils.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/error_message_converter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/emoji.dart';
import 'package:audio_session/audio_session.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_record.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/sound_player_voice_route_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/voice_output_route_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_media_helpers.dart';

bool isInitScreenUtils = false;

class TencentChatApp extends StatefulWidget {
  const TencentChatApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _TencentChatAppState();
}

class _TencentChatAppState extends State<TencentChatApp>
    with WidgetsBindingObserver {
  void _sessionLog(String message) {
    SessionDiagnostics.log(message);
  }

  var subscription;
  final V2TIMManager _sdkInstance = TIMUIKitCore.getSDKInstance();
  bool _initialURILinkHandled = false;
  BuildContext? cachedBuildContext;
  VoidCallback? _routeListener;
  PresenceProvider? _presence;
  Timer? _resumeTimer;
  Timer? _resumePhase1Timer;
  Timer? _resumePhase2Timer;
  Future<void>? _resumeTask;
  DateTime? _lastResumeCheckAt;
  DateTime? _lastLoggedInSideEffectAt;
  DateTime? _lastEnteredBackgroundAt;
  Future<bool>? _officialAccountTask;
  Timer? _splashWatchdog;
  int _startupAttempt = 0;
  bool _startupSettled = false;

  static const Duration _resumeCheckDelay = Duration(milliseconds: 200);
  static const Duration _loggedInSideEffectMinInterval = Duration(seconds: 12);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _presence = Provider.of<PresenceProvider>(context, listen: false);
    } catch (_) {
      _presence = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    scheduleSqfliteLifecycle(state);
    ChatImageMessagePrefetch.handleAppLifecycleState(state);
    SqfliteLockProfileLog.lifecycle(state);
    NotificationSettingsService.instance.setLifecycle(state);
    DeviceSyncService.instance.setAppLifecycle(state);
    FriendRequestNoticeService.instance.onAppLifecycleChanged(state);
    ConversationSyncService.instance.setInboxRecoveryForeground(
      state == AppLifecycleState.resumed,
    );

    if (state == AppLifecycleState.resumed) {
      if (ImConnectStatusService.isTransportReady) {
        unawaited(OutgoingOutboxRecoveryService.instance
            .recoverPending()
            .catchError((Object error) => debugPrint(
                'resume outgoing outbox failed errorType=${error.runtimeType}')));
      }
      if (kIsWeb) {
        unawaited(
            WebImRealtimeWatchdog.catchUpNow(reason: 'lifecycle_resumed'));
      }
      _scheduleResumeCheck();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ChatHistoryRecoveryCoordinator.instance.invalidateLifecycle();
      ConversationSyncService.instance.invalidateLifecycle();
      _lastEnteredBackgroundAt = DateTime.now();
      _resumeTimer?.cancel();
      _resumePhase1Timer?.cancel();
      _resumePhase2Timer?.cancel();
      _presence?.stopHeartbeat();
      unawaited(SoundPlayer.stop());
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (kIsWeb) {
      WebImRealtimeWatchdog.start();
      unawaited(WebImRealtimeWatchdog.catchUpNow(reason: 'reassemble'));
    }
  }

  void _scheduleResumeCheck() {
    final now = DateTime.now();
    final last = _lastResumeCheckAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }

    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeCheckDelay, () {
      if (!mounted) return;
      _lastResumeCheckAt = DateTime.now();
      _resumeTask ??= _checkIfConnected().whenComplete(() {
        _resumeTask = null;
      });
    });
  }

  Future<void> _checkIfConnected() async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final recovery = await LoginCoordinator.instance.recoverOnForeground();
    if (!mounted ||
        !SessionIdentityService.instance
            .isGenerationCurrent(sessionGeneration)) {
      return;
    }

    switch (recovery.action) {
      case LoginRecoveryAction.goLogin:
        if (AuthSessionService.instance.isInAuthFlow) return;
        InitStep.directToLogin(cachedBuildContext ?? context);
        return;
      case LoginRecoveryAction.stayOnHome:
      case LoginRecoveryAction.goHome:
        if (NetworkStatusService.instance.status.value !=
            NetworkReachability.offline) {
          ImConnectStatusService.refreshSocketStatus(
            context: cachedBuildContext ?? context,
          );
          unawaited(
            ImConnectStatusService.reconcileAfterNetworkOnline(
              cachedBuildContext ?? context,
              gracePeriod: const Duration(seconds: 12),
            ),
          );
        }
        _onImLoggedInForSession(
          runForegroundRecovery: true,
          expectedIdentity: SessionIdentityService.instance.capture(
            ownerUserId: recovery.userId,
          ),
        );
        return;
      case LoginRecoveryAction.restartColdStart:
        await initIMSDKAndAddIMListeners();
        if (!mounted) return;
        unawaited(
          InitStep.checkLogin(
            cachedBuildContext ?? context,
            initIMSDKAndAddIMListeners,
          ),
        );
        return;
    }
  }

  void _onImLoggedInForSession({
    required bool runForegroundRecovery,
    required SessionIdentity expectedIdentity,
    int? listenerEpoch,
  }) {
    bool isCurrent() =>
        _isListenerSessionCurrent(expectedIdentity, listenerEpoch);
    if (!isCurrent()) {
      return;
    }
    _presence?.startHeartbeat();
    unawaited(
        NotificationSettingsService.instance.consumePendingConversationOpen());
    if (runForegroundRecovery) {
      _runLoggedInSideEffects(
        expectedIdentity: expectedIdentity,
        listenerEpoch: listenerEpoch,
      );
    }
  }

  bool _isListenerSessionCurrent(
    SessionIdentity identity,
    int? listenerEpoch,
  ) {
    return SessionIdentityService.instance.isCurrent(identity);
  }

  void _runLoggedInSideEffects({
    required SessionIdentity expectedIdentity,
    int? listenerEpoch,
  }) {
    bool isCurrent() =>
        _isListenerSessionCurrent(expectedIdentity, listenerEpoch);
    if (!isCurrent()) {
      return;
    }
    // ListenerStore.attachRealtimeBindings is owned by the login/connect path. Recovery
    // only performs data reconciliation; registering listeners again here
    // races with the connect-success path and can duplicate SDK callbacks.
    final backgroundAt = _lastEnteredBackgroundAt;
    _lastEnteredBackgroundAt = null;
    final background =
        backgroundAt == null ? null : DateTime.now().difference(backgroundAt);
    final intensity = ResumeForegroundPolicy.intensityFor(background);

    final now = DateTime.now();
    final last = _lastLoggedInSideEffectAt;
    if (last != null && now.difference(last) < _loggedInSideEffectMinInterval) {
      return;
    }
    _lastLoggedInSideEffectAt = now;

    unawaited(PresenceApi.instance.heartbeat().catchError((_) {}));

    _resumePhase1Timer?.cancel();
    _resumePhase2Timer?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isCurrent()) return;
      _resumePhase1Timer = Timer(ResumeForegroundPolicy.phase1Delay, () {
        if (!mounted || !isCurrent()) return;
        unawaited(() async {
          if (!isCurrent()) return;
          await NotificationSettingsService.instance.applyFromSettings();
          if (!isCurrent()) return;
          await NotificationSettingsService.instance
              .consumePendingConversationOpen();
          if (!isCurrent()) return;
          // 跳过 cold_start 还在跑的 app_resumed reconcile。
          // login_coordinator 已经做了完整的 bootstrap（pin_hydrate +
          // restoreStoreProjection + coldStartPrime），重复跑
          // bootstrapTypedFirstScreen(reset:true) 会拉 ByFilter × 2 +
          // attachRealtimeBindings 重新注册 + drain queue 重复跑。
          if (HomeBootstrap.instance.isRunningForCurrentSession) {
            if (kDebugMode) {
              debugPrint(
                '[App] skip afterOnline reason=cold_start_in_flight',
              );
            }
            return;
          }
          await ImRecoveryService.instance.afterOnline(
            reason: 'app_resumed',
            intensity: intensity,
          );
          if (!isCurrent()) return;
        }()
            .catchError((_) {}));
      });

      _resumePhase2Timer = Timer(ResumeForegroundPolicy.phase2Delay, () {
        if (!mounted || !isCurrent()) return;
        DeviceSyncService.instance.onAppResumed();
        if (isCurrent() &&
            ResumeForegroundPolicy.shouldRunHeavySideEffects(intensity)) {
          unawaited(
            LocationUploadService.instance.maybeUpload(reason: 'app_resumed'),
          );
          _scheduleOfficialAccountEnsure();
        }
      });
    });
  }

  void _scheduleOfficialAccountEnsure() {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    _officialAccountTask ??= Future<void>.delayed(
      Duration.zero,
    )
        .then((_) async {
          if (!SessionIdentityService.instance.isCurrent(identity)) {
            return false;
          }
          final login = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
          final userId = login.data?.trim() ?? '';
          if (userId.isEmpty ||
              userId != identity.ownerUserId ||
              !SessionIdentityService.instance.isCurrent(identity)) {
            return false;
          }
          await PlatformOfficialAccountService.loadDismissedState();
          if (!SessionIdentityService.instance.isCurrent(identity)) {
            return false;
          }
          return PlatformOfficialAccountService.ensureSubscribed();
        })
        .catchError((_) => false)
        .whenComplete(() {
          _officialAccountTask = null;
        });
  }

  Future<void> onKickedOffline({
    bool updateLoginState = true,
    SessionIdentity? expectedIdentity,
  }) async {
    try {
      if (expectedIdentity == null &&
          AuthSessionService.instance.isInAuthFlow) {
        return;
      }
      final identity =
          expectedIdentity ?? SessionIdentityService.instance.capture();
      if (identity.ownerUserId.isEmpty ||
          !SessionIdentityService.instance.isCurrent(identity)) {
        return;
      }
      if (updateLoginState) {
        LoginCoordinator.instance.markKickedOffline(
          message: TIM_t("您的账号已在其它终端登录"),
        );
      }
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        return;
      }
      await AccountSessionService.instance.clearForLogout(
        reason: 'kicked_offline',
        expectedIdentity: identity,
      );
      if (mounted) {
        InitStep.directToLogin(cachedBuildContext ?? context);
      }
      InitStep.removeLocalSetting();
    } catch (_) {}
  }

  Future<String> getLanguage() async {
    return "zh-Hans";
  }

  Future<void> getLoginUserInfo() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    final res = await _sdkInstance.getLoginUser();
    final nativeUserId = ChatIdFormat.rawUserUid(res.data);
    if (res.code == 0 &&
        nativeUserId == identity.ownerUserId &&
        SessionIdentityService.instance.isCurrent(identity)) {
      final result = await _sdkInstance.getUsersInfo(userIDList: [res.data!]);

      if (result.code == 0 &&
          result.data != null &&
          result.data!.isNotEmpty &&
          ChatIdFormat.rawUserUid(result.data!.first.userID) ==
              identity.ownerUserId &&
          SessionIdentityService.instance.isCurrent(identity)) {
        Provider.of<LoginUserInfo>(context, listen: false)
            .setLoginUserInfo(result.data![0]);
      }
    }
  }

  Future<void> initIMSDKAndAddIMListeners({int? sdkAppId}) async {
    await SessionManager.instance.restore();
  }

  void initApp() {
    final attempt = ++_startupAttempt;
    _startupSettled = false;
    _splashWatchdog?.cancel();
    _splashWatchdog = Timer(const Duration(seconds: 12), () {
      unawaited(_escalateIfStillOnSplash(attempt));
    });
    final startup = InitStep.checkLogin(context, initIMSDKAndAddIMListeners);
    unawaited(startup.whenComplete(() {
      if (!mounted || attempt != _startupAttempt) return;
      _startupSettled = true;
      _splashWatchdog?.cancel();
      _splashWatchdog = null;
      _sessionLog('SESSION_LOG startup settled attempt=$attempt');
    }));
  }

  initScreenUtils() {
    if (isInitScreenUtils) return;

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    ScreenUtil.init(
      context,
      designSize: const Size(750, 1624),
      minTextAdapt: true,
      fontSizeResolver: isDesktop ? (fontSize, _) => fontSize * 0.5 : null,
    );
    isInitScreenUtils = true;
  }

  initRouteListener() {
    if (_routeListener != null) return;
    final routes = Routes();
    void listener() {
      final pageType = routes.pageType;
      if (pageType == "loginPage") {
        InitStep.directToLogin(cachedBuildContext ?? context);
      }

      if (pageType == "homePage") {
        InitStep.directToHomePage(cachedBuildContext ?? context);
      }
    }

    _routeListener = listener;
    routes.addListener(listener);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _installVoiceRouteBridge();
    unawaited(VoiceOutputRouteService.ensureImPreferenceLoaded());
    if (kIsWeb) {
      WebImRealtimeWatchdog.start();
    }
    initApp();
    initRouteListener();
  }

  /// 注入 UIKit 的语音路由桥接——app 层 VoiceOutputRouteService 的适配器。
  void _installVoiceRouteBridge() {
    SoundPlayerVoiceRouteBridge.install(_AppVoiceRouteBridge());
  }

  Future<void> _escalateIfStillOnSplash(int attempt) async {
    if (!mounted || attempt != _startupAttempt || _startupSettled) return;
    // The watchdog is observational. The restore task owns navigation and
    // credential deletion; a slow network/IM response must never be mistaken
    // for an invalid account and clear a valid token.
    final token = ApiClient.instance.token;
    _sessionLog(
      'SESSION_LOG startup watchdog pending attempt=$attempt '
      'tokenValid=${ApiClient.isValidJwt(token)} '
      'hasOwner=${ApiClient.instance.authenticatedUserId.isNotEmpty} '
      'route=${AppNavigator.currentRouteName ?? 'root'}',
    );
  }

  @override
  dispose() {
    _splashWatchdog?.cancel();
    _resumeTimer?.cancel();
    _resumePhase1Timer?.cancel();
    _resumePhase2Timer?.cancel();
    if (kIsWeb) {
      WebImRealtimeWatchdog.stop();
    }
    WidgetsBinding.instance.removeObserver(this);
    final listener = _routeListener;
    if (listener != null) {
      Routes().removeListener(listener);
      _routeListener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    cachedBuildContext ??= context;
    initScreenUtils();
    ToastUtils.init(context);
    // Web 跳过全屏启动图，鉴权完成后直接进入登录/首页。
    if (PlatformUtils().isWeb) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: 0.85,
                  ),
            ),
          ),
        ),
      );
    }
    return const LaunchPage();
  }
}

/// app 层 VoiceOutputRouteService 的 UIKit bridge 适配器。
class _AppVoiceRouteBridge implements SoundPlayerVoiceRouteBridge {
  @override
  SoundPlayerVoiceRoute get currentRoute =>
      VoiceOutputRouteService.imVoiceRoute == VoiceOutputRoute.speaker
          ? SoundPlayerVoiceRoute.speaker
          : SoundPlayerVoiceRoute.earpiece;

  @override
  bool get isSpeaker =>
      VoiceOutputRouteService.imVoiceRoute == VoiceOutputRoute.speaker;

  @override
  ValueListenable<SoundPlayerVoiceRoute> get routeNotifier {
    return _RouteNotifierAdapter(VoiceOutputRouteService.imVoiceRouteNotifier);
  }

  @override
  Future<void> ensureReady() {
    return VoiceOutputRouteService.ensureImPreferenceLoaded();
  }

  @override
  AudioSessionConfiguration playbackConfigFor(SoundPlayerVoiceRoute route) {
    final mapped = _mapRoute(route);
    return VoiceOutputRouteService.playbackConfigFor(mapped);
  }

  @override
  AudioSessionConfiguration voiceChatConfigFor(SoundPlayerVoiceRoute route) {
    final mapped = _mapRoute(route);
    return VoiceOutputRouteService.voiceChatConfigFor(mapped);
  }

  @override
  bool get callOwnsAudioSession =>
      LiveKitCallSession.instance.isInCall ||
      (iosCallKitOwnsAudioSession?.call() ?? false);

  @override
  Future<bool> applyCurrentRoute({
    bool configureSession = false,
    bool forRecording = false,
    bool activate = false,
  }) {
    return VoiceOutputRouteService.reapplyImVoiceRouteToLive(
      configureSession: configureSession,
      forRecording: forRecording,
      activate: activate,
    );
  }

  @override
  Future<bool> setRoute(
    SoundPlayerVoiceRoute target, {
    bool configureSession = true,
    bool forRecording = false,
    bool activate = true,
    bool forceApply = false,
  }) {
    return VoiceOutputRouteService.setImVoiceRoute(
      _mapRoute(target),
      configureSession: configureSession,
      forRecording: forRecording,
      activate: activate,
      forceApply: forceApply,
    );
  }

  static VoiceOutputRoute _mapRoute(SoundPlayerVoiceRoute route) {
    return route == SoundPlayerVoiceRoute.speaker
        ? VoiceOutputRoute.speaker
        : VoiceOutputRoute.earpiece;
  }
}

class _RouteNotifierAdapter extends ValueNotifier<SoundPlayerVoiceRoute> {
  _RouteNotifierAdapter(ValueListenable<VoiceOutputRoute> source)
      : super(_map(source.value)) {
    source.addListener(_onChanged);
    _source = source;
  }

  ValueListenable<VoiceOutputRoute>? _source;

  void _onChanged() {
    final source = _source;
    if (source != null) {
      value = _map(source.value);
    }
  }

  static SoundPlayerVoiceRoute _map(VoiceOutputRoute route) {
    return route == VoiceOutputRoute.speaker
        ? SoundPlayerVoiceRoute.speaker
        : SoundPlayerVoiceRoute.earpiece;
  }
}
