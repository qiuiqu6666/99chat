import 'dart:async';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_lifecycle_service.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_demo/src/services/call_lifecycle_service_web.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_session_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_coordinator.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_error.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_registration_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/services/notification_settings_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/platform_official_account_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/interaction_idle_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/utils/push_identity_cache.dart';
import 'package:tencent_cloud_chat_demo/src/platform/listener_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/archived_conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_notify_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_notice_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/ios_apns_push_service.dart';
import 'package:tencent_cloud_chat_demo/src/bootstrap/home_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/starred_friend_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/user_sticker_provider.dart';
import 'package:tencent_cloud_chat_demo/utils/init_step.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/utils/user_avatar.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

class AuthBootstrapService {
  AuthBootstrapService._();

  /// Debug 构建打开；关键失败路径另走 [_diag] 始终打印。
  static bool get _traceEnabled => kDebugMode;

  void _trace(String message) {
    if (!_traceEnabled) return;
    SessionDiagnostics.log(message);
  }

  /// 始终打到控制台（Xcode/rizhi 可看见），用于会话同步失败取证。
  void _diag(String message) {
    SessionDiagnostics.log(message);
  }

  Future<UserSigResult> _fetchUserSigWithPerf({required String reason}) async {
    final startedAt = DateTime.now();
    StartupPerfLog.markTagged(
      'user_sig_wait_start',
      category: 'cold_start',
      details: <String, Object>{'reason': reason},
    );
    try {
      return await AuthApi.instance.fetchUserSig();
    } finally {
      StartupPerfLog.markTagged(
        'user_sig_wait_end',
        category: 'cold_start',
        details: <String, Object>{
          'reason': reason,
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    }
  }

  static final AuthBootstrapService instance = AuthBootstrapService._();

  /// UserSig 刷新失败不等于业务账号失效。
  bool lastUserSigRefreshWasAuthFailure = false;
  final ValueNotifier<bool> backgroundSyncing = ValueNotifier<bool>(false);

  /// Set when [TencentChatApp.initIMSDKAndAddIMListeners] completes.
  static bool imSdkInitialized = false;

  /// 当前已成功 init 的 sdkAppId（来自后端 UserSig / 缓存解析结果）。
  static int? initializedSdkAppId;

  Future<void> Function({int? sdkAppId})? _imSdkInitializer;
  Future<bool>? _ensureImSdkReadyTask;
  int? _ensureImSdkDesiredAppId;

  Future<bool>? _refreshUserSigTask;
  int _loginGeneration = 0;

  /// 与登录世代对齐：登出 / 清会话 / post-home reset 时递增并清 Done 标记。
  int _bootstrapGeneration = 0;
  bool _conversationListBootstrapDone = false;
  bool get conversationListBootstrapDone => _conversationListBootstrapDone;
  Future<int>? _imLoginTask;
  String? _imLoginTaskKey;
  String? _lastImLoginKey;
  DateTime? _lastImLoginAt;
  final Set<Future<void>> _pendingImOperations = <Future<void>>{};
  int _imListenerEpoch = 0;

  int get bootstrapGeneration => _bootstrapGeneration;

  /// SDK listeners are process-wide. A callback from an uninitialized SDK
  /// instance must never be interpreted as an event for the next account.
  int registerImListenerEpoch() {
    final epoch = ++_imListenerEpoch;
    ConversationSyncService.instance.setMessageDomainGeneration(epoch);
    return epoch;
  }

  int invalidateImListenerEpoch() {
    final epoch = ++_imListenerEpoch;
    ConversationSyncService.instance.setMessageDomainGeneration(epoch);
    LocalMessageOverlayStore.instance.invalidateScope();
    return epoch;
  }

  bool isImListenerEpochCurrent(int epoch) => epoch == _imListenerEpoch;

  /// Installs the host-owned account and IM-session scope before SDK login.
  ///
  /// The advanced message listener is registered before login completes, so
  /// the Writer must already know which account/domain may accept an early
  /// callback. The UIKit model deliberately does not infer this scope.
  void configureMessageWriterScopeForSession({
    required String ownerUserId,
    required int accountGeneration,
  }) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty || accountGeneration < 0) {
      _diag(
        'AuthBootstrap: skip Message Writer scope with invalid session '
        'owner=${owner.isEmpty ? '<empty>' : '<present>'} '
        'accountGeneration=$accountGeneration',
      );
      return;
    }
    try {
      serviceLocator<TUIChatGlobalModel>().configureMessageWriterScope(
        ownerUserID: owner,
        accountGeneration: accountGeneration,
        domainGeneration: _imListenerEpoch,
      );
      MessagePersistCoordinator.instance.bindAccountGeneration(
        accountGeneration,
      );
      LocalMessageOverlayStore.instance.configureScope(
        ownerUserId: owner,
        domainGeneration: _imListenerEpoch,
      );
      _trace(
        'AuthBootstrap: Message Writer scope configured '
        'accountGeneration=$accountGeneration '
        'domainGeneration=$_imListenerEpoch',
      );
    } catch (e) {
      // A missing UIKit locator is a real integration failure. Keep login
      // behavior unchanged, but leave evidence instead of silently claiming
      // that the Writer is scoped.
      _diag('AuthBootstrap: Message Writer scope configure failed: $e');
    }
  }

  void bumpBootstrapGeneration({String reason = 'manual'}) {
    _bootstrapGeneration++;
    _conversationListBootstrapDone = false;
    _trace(
      'AuthBootstrap: bumpBootstrapGeneration reason=$reason '
      'gen=$_bootstrapGeneration',
    );
  }

  void setImSdkInitializer(Future<void> Function({int? sdkAppId}) initializer) {
    _imSdkInitializer = initializer;
  }

  /// Wait for a previous login wrapper before crossing an account boundary.
  /// A UIKit login Future may outlive its timeout, so it must remain tracked.
  Future<void> waitForImLoginIdle({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final waits = <Future<void>>[];
    final running = _imLoginTask;
    if (running != null) {
      waits.add(running.then<void>((_) {}, onError: (_, __) {}));
    }
    waits.addAll(_pendingImOperations);
    if (waits.isEmpty) return;
    try {
      await Future.wait(waits).timeout(timeout);
    } catch (_) {
      _diag('AuthBootstrap: waitForImLoginIdle timed out');
    }
  }

  /// Clears only the compatibility bookkeeping that is still read by legacy
  /// callers. The actual IM disconnect/dispose is owned by SessionManager;
  /// this method must not touch the SDK or UIKit instance.
  void resetCompatibilityStateForAccountBoundary({
    String reason = 'account_boundary',
  }) {
    resetImLoginState();
    invalidateImListenerEpoch();
    HomeBootstrap.instance.reset(reason: reason);
    ConversationTabStore.instance.reopenColdStartWindow();
    _setBackgroundSyncing(false);
    resetImSdkInitializationState(reason: reason);
  }

  Future<T> _trackImOperation<T>(Future<T> operation) {
    late final Future<void> completion;
    completion = operation.then<void>((_) {}, onError: (_, __) {});
    _pendingImOperations.add(completion);
    completion.whenComplete(() {
      _pendingImOperations.remove(completion);
    });
    return operation;
  }

  void resetImSdkInitializationState({String reason = 'unknown'}) {
    _trace('AuthBootstrap: resetImSdkInitializationState reason=$reason');
    imSdkInitialized = false;
    initializedSdkAppId = null;
    _ensureImSdkReadyTask = null;
    _ensureImSdkDesiredAppId = null;
  }

  /// 确保 IM SDK 已按 [sdkAppId] 初始化。
  ///
  /// [sdkAppId] 通常取后端 UserSig；为空时走缓存/配置兜底。
  /// 若已 init 但 AppID 不一致，会触发拆掉重装。
  Future<bool> ensureImSdkInitialized({int? sdkAppId}) async {
    final desired = (sdkAppId != null && sdkAppId > 0) ? sdkAppId : null;
    if (imSdkInitialized &&
        desired != null &&
        initializedSdkAppId != null &&
        initializedSdkAppId == desired) {
      return true;
    }
    if (imSdkInitialized && desired == null) {
      return true;
    }
    if (imSdkInitialized &&
        desired != null &&
        initializedSdkAppId != null &&
        initializedSdkAppId != desired) {
      _trace(
        'AuthBootstrap: ensureImSdkInitialized sdkAppId mismatch '
        'current=$initializedSdkAppId desired=$desired → reinit',
      );
      // 放开门闩，交给 initializer 执行 unInit + 新 AppID init。
      imSdkInitialized = false;
    }
    final running = _ensureImSdkReadyTask;
    if (running != null) {
      if (_ensureImSdkDesiredAppId == desired ||
          (desired == null && _ensureImSdkDesiredAppId == null)) {
        return running;
      }
      // 目标 AppID 变了：等旧任务结束后再按新 ID 初始化。
      await running;
      return ensureImSdkInitialized(sdkAppId: desired);
    }
    final initializer = _imSdkInitializer;
    if (initializer == null) {
      _trace('AuthBootstrap: IM SDK initializer missing');
      return false;
    }
    _ensureImSdkDesiredAppId = desired;
    final task = _ensureImSdkInitializedCore(initializer, sdkAppId: desired);
    _ensureImSdkReadyTask = task.whenComplete(() {
      if (identical(_ensureImSdkReadyTask, task)) {
        _ensureImSdkReadyTask = null;
        _ensureImSdkDesiredAppId = null;
      }
    });
    return _ensureImSdkReadyTask!;
  }

  Future<bool> _ensureImSdkInitializedCore(
    Future<void> Function({int? sdkAppId}) initializer, {
    int? sdkAppId,
  }) async {
    final startedAt = DateTime.now();
    StartupPerfLog.markTagged(
      'im_sdk_db_ready_start',
      category: 'cold_start',
      details: <String, Object>{'sdkAppId': sdkAppId ?? 0},
    );
    _trace(
      'AuthBootstrap: ensureImSdkInitialized START sdkAppId=${sdkAppId ?? '-'}',
    );
    try {
      await initializer(sdkAppId: sdkAppId);
    } catch (e, st) {
      _trace('AuthBootstrap: ensureImSdkInitialized failed: $e\n$st');
      StartupPerfLog.markTagged(
        'im_sdk_db_ready_end',
        category: 'cold_start',
        details: <String, Object>{
          'sdkAppId': sdkAppId ?? 0,
          'ready': false,
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return false;
    }
    final ready = imSdkInitialized &&
        (sdkAppId == null || sdkAppId <= 0 || initializedSdkAppId == sdkAppId);
    _trace(
      'AuthBootstrap: ensureImSdkInitialized DONE ready=$ready '
      'initializedSdkAppId=${initializedSdkAppId ?? '-'}',
    );
    StartupPerfLog.markTagged(
      'im_sdk_db_ready_end',
      category: 'cold_start',
      details: <String, Object>{
        'sdkAppId': sdkAppId ?? 0,
        'ready': ready,
        'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
    return ready;
  }

  Future<void> bootstrapLoggedInSession(BuildContext context) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final me = await AuthApi.instance.fetchMe();
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    await UserAvatarHelper.syncSelfAvatarFromBackend(me.avatarUrl);
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    await PushIdentityCache.instance.refreshSelf();
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    final sig = await _fetchUserSigWithPerf(reason: 'bootstrap_logged_in');
    if (!SessionIdentityService.instance.isCurrent(identity) ||
        sig.userId.trim() != identity.ownerUserId) {
      return;
    }
    final cacheSaved = await ImSessionCache.instance.saveIfCurrent(
      sig,
      () => SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      ),
    );
    if (!cacheSaved) return;

    final imCode = await loginImStack(
      sig,
      expectedSessionGeneration: sessionGeneration,
    );
    if (imCode != 0) {
      resetImLoginState();
      await ListenerStore.beforeLogout();
      // IM being temporarily unavailable does not prove that the business
      // token is invalid. Keep the durable account session and let the normal
      // foreground recovery retry it instead of forcing a false logout.
      LoginCoordinator.instance.markFailed(
        LoginErrorType.imLoginFailed,
        message: 'IM login temporarily unavailable',
        isBusinessAuthenticated: true,
        isHomeEntered: true,
        isRecovering: true,
      );
      return;
    }

    // Realtime bindings are attached by HomeBootstrap after HomePage's first
    // frame. Keeping this auth helper free of a second attach prevents a
    // successful login from installing duplicate SDK callbacks.
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    if (context.mounted) {
      InitStep.directToHomePage(context);
      await ImConnectStatusService.syncToLocalSetting(context);
    }

    // 所有登录后的域同步统一由 HomeBootstrap 调度。这里仅完成 IM
    // 登录与路由切换，避免旧登录入口和首页入口同时触发 notify/pin/
    // folder/archive 等副作用。
  }

  static const int imKickedOfflineCode = 6208;

  static const Duration _imLoginTimeout = Duration(seconds: 25);
  static const Duration _uikitLoginWait = Duration(seconds: 8);
  static const List<Duration> _kickRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// 业务 token 已写入：先完成 IM/UIKit 与会话/通讯录模型，再进首页（避免 Tab 空白）。
  Future<bool> ensureImReadyForHome({
    String? registerNickname,
    Duration timeout = const Duration(seconds: 25),
    int? expectedGeneration,
  }) async {
    final generation =
        expectedGeneration ?? SessionIdentityService.instance.generation;
    try {
      return await _ensureImReadyForHomeCore(
        registerNickname: registerNickname,
        expectedGeneration: generation,
      ).timeout(
        timeout,
        onTimeout: () {
          _diag('AuthBootstrap: ensureImReadyForHome timed out');
          return false;
        },
      );
    } catch (e, st) {
      _diag('AuthBootstrap: ensureImReadyForHome failed: $e\n$st');
      return false;
    }
  }

  Future<bool> prepareReadySessionForHome({
    String? registerNickname,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final generation = SessionIdentityService.instance.generation;
    _setBackgroundSyncing(true);
    _setConnectStatus(ConnectStatus.connecting);
    var deferredOwnsSyncing = false;
    try {
      final sdkReady = await ensureImSdkInitialized();
      if (!sdkReady ||
          !SessionIdentityService.instance.isGenerationCurrent(generation)) {
        _trace(
          'AuthBootstrap: prepareReadySessionForHome abort '
          '(IM SDK not initialized)',
        );
        if (SessionIdentityService.instance.isGenerationCurrent(generation)) {
          _setConnectStatus(ConnectStatus.failed);
        }
        return false;
      }
      final ready = await _ensureImReadyWithRetry(
        registerNickname: registerNickname,
        timeout: timeout,
        expectedGeneration: generation,
      );
      if (!ready) {
        _diag('AuthBootstrap: prepareReadySessionForHome IM not ready');
        if (SessionIdentityService.instance.isGenerationCurrent(generation)) {
          _setConnectStatus(ConnectStatus.failed);
        }
        return false;
      }
      if (kIsWeb) {
        await runPostLoginSideEffects();
        if (!SessionIdentityService.instance.isGenerationCurrent(generation)) {
          return false;
        }
        _setConnectStatus(ConnectStatus.success);
        return true;
      }
      if (!SessionIdentityService.instance.isGenerationCurrent(generation)) {
        return false;
      }
      // 原生：IM 就绪即返回；列表/好友/群/副作用由进门后串行队列补全。
      _diag('AuthBootstrap: prepareReady OK → schedule post-home bootstrap');
      deferredOwnsSyncing = true;
      return true;
    } catch (e, st) {
      _diag('AuthBootstrap: prepareReadySessionForHome failed: $e\n$st');
      if (SessionIdentityService.instance.isGenerationCurrent(generation)) {
        _setConnectStatus(ConnectStatus.failed);
      }
      return false;
    } finally {
      if (!deferredOwnsSyncing &&
          SessionIdentityService.instance.isGenerationCurrent(generation)) {
        _setBackgroundSyncing(false);
      }
    }
  }

  void markConversationListBootstrapReady() {
    _conversationListBootstrapDone = true;
  }

  /// 原生 IM transport 已就绪；会话首屏完成态由结构化结果独立推进。
  void applyNativePostHomeStage1Finished({required bool conversationReady}) {
    StartupPerfLog.markTagged(
      'stage1_state_applied',
      category: 'post_home',
      details: <String, Object>{'conversationReady': conversationReady},
    );
    if (conversationReady) {
      markConversationListBootstrapReady();
    }
    _setBackgroundSyncing(false);
    _setConnectStatus(ConnectStatus.success);
    LoginCoordinator.instance.markImReady(isHomeEntered: true);
  }

  Future<bool> _ensureImReadyWithRetry({
    String? registerNickname,
    Duration timeout = const Duration(seconds: 20),
    required int expectedGeneration,
  }) async {
    final ready = await ensureImReadyForHome(
      registerNickname: registerNickname,
      timeout: timeout,
      expectedGeneration: expectedGeneration,
    );
    if (ready) {
      return true;
    }
    _diag(
      'AuthBootstrap: foreground prepare first attempt failed, '
      'soft-retry login (no generation bump / no session wipe)',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!SessionIdentityService.instance.isGenerationCurrent(
      expectedGeneration,
    )) {
      return false;
    }
    // 软重试：只 logout，不 bump _loginGeneration，避免掐死仍在飞的登录。
    try {
      await TencentImSDKPlugin.v2TIMManager.logout().timeout(
            const Duration(seconds: 3),
          );
    } catch (_) {}
    final sdkReady = await ensureImSdkInitialized();
    if (!sdkReady) {
      _diag(
        'AuthBootstrap: foreground prepare retry abort '
        '(IM SDK not initialized)',
      );
      return false;
    }
    return ensureImReadyForHome(
      registerNickname: registerNickname,
      timeout: timeout,
      expectedGeneration: expectedGeneration,
    );
  }

  Future<bool> _ensureImReadyForHomeCore({
    String? registerNickname,
    required int expectedGeneration,
  }) async {
    bool isCurrent() =>
        SessionIdentityService.instance.isGenerationCurrent(expectedGeneration);
    if (!isCurrent()) {
      return false;
    }
    _diag('AuthBootstrap: ensure IM ready for home');
    LoginCoordinator.instance.markImConnecting();
    final results = await Future.wait<Object>([
      AuthApi.instance.fetchMe().timeout(const Duration(seconds: 10)),
      _fetchUserSigWithPerf(reason: 'ensure_im_ready')
          .timeout(const Duration(seconds: 10)),
    ]);
    final me = results[0] as MeResult;
    var sig = results[1] as UserSigResult;
    if (!isCurrent()) {
      return false;
    }
    _diag(
      'AuthBootstrap: got me=${me.userId} sig=${sig.userId} '
      'sdkAppId=${sig.sdkAppId} sigLen=${sig.userSig.length}',
    );
    if (sig.userId.trim().isEmpty || sig.userSig.trim().isEmpty) {
      _diag('AuthBootstrap: abort empty userSig payload');
      return false;
    }
    // UserSig 是 IM 登录真源。/me 与 /im/user-sig 的 userId 若暂不一致，
    // 绝不能硬失败清会话——否则永远看不到 Login，首页会话/群/通讯录全空。
    if (!_isSameUserId(me.userId, sig.userId)) {
      _diag(
        'AuthBootstrap: WARN me/sig userId mismatch '
        '(me=${me.userId} sig=${sig.userId}); proceed with userSig',
      );
    }
    sig = _normalizeUserSig(sig);
    LoginCoordinator.instance.markImConnecting(userId: sig.userId);
    if (!isCurrent()) {
      return false;
    }
    final cacheSaved = await ImSessionCache.instance.saveIfCurrent(
      sig,
      isCurrent,
    );
    if (!cacheSaved || !isCurrent()) {
      return false;
    }

    _trace(
      'AuthBootstrap: _ensureImReadyForHomeCore calling completeImSessionAfterAuth '
      'userId=${sig.userId}',
    );
    var imCode = await completeImSessionAfterAuth(sig);
    if (!isCurrent()) {
      return false;
    }
    _diag(
      'AuthBootstrap: completeImSessionAfterAuth code=$imCode '
      'userId=${sig.userId}',
    );
    imCode = await resolveImLoginCode(sig, imCode);
    _diag(
      'AuthBootstrap: resolveImLoginCode finalCode=$imCode '
      'userId=${sig.userId}',
    );
    if (imCode != 0) {
      _trace(
        'AuthBootstrap: ensureImReadyForHome imCode=$imCode, '
        'calling _recoverImReadyAfterTransientFailure',
      );
      final recovered = await _recoverImReadyAfterTransientFailure(sig);
      _trace('AuthBootstrap: ensureImReadyForHome recovered=$recovered');
      if (!recovered) {
        return false;
      }
    }

    if (!isCoreServicesUserReady()) {
      await primeUIKitSession(sig);
      if (!isCoreServicesUserReady()) {
        _trace(
          'AuthBootstrap: UIKit still not ready after prime userId=${sig.userId}',
        );
        return false;
      }
    }

    if (registerNickname != null && registerNickname.isNotEmpty) {
      try {
        await TIMUIKitCore.getInstance().setSelfInfo(
          userFullInfo: V2TimUserFullInfo(
            nickName: registerNickname,
            faceUrl: IMDemoConfig.defaultRegisterAvatarUrl,
          ),
        );
      } catch (_) {}
    }

    if (kIsWeb) {
      unawaited(_runWebPostImReadySideEffects(me: me));
      _trace('AuthBootstrap: IM ready for home (web deferred lists)');
      LoginCoordinator.instance.markImReady(userId: sig.userId);
      unawaited(NotificationSettingsService.instance.ensureListenersAttached());
      unawaited(
        NotificationSettingsService.instance.syncRemotePreferencesFromServer(),
      );
      return true;
    }

    // 原生：门禁只等到 IM/UIKit 可收发；列表与副作用由 HomeBootstrap 串行补。
    _trace('AuthBootstrap: IM ready for home (native deferred lists)');
    LoginCoordinator.instance.markImReady(userId: sig.userId);
    unawaited(NotificationSettingsService.instance.ensureListenersAttached());
    unawaited(
      NotificationSettingsService.instance.syncRemotePreferencesFromServer(),
    );
    return true;
  }

  Future<void> _runWebPostImReadySideEffects({required MeResult me}) async {
    try {
      await ConversationNotifySyncService.instance.syncAllOnLogin();
    } catch (_) {}
    try {
      await ArchivedConversationSyncService.instance.syncOnLogin();
    } catch (_) {}
    try {
      await ConversationFolderSyncService.instance.syncOnLogin();
    } catch (_) {}
    try {
      await ConversationPinSyncService.instance.syncOnLogin();
    } catch (_) {}
    try {
      await UserAvatarHelper.syncSelfAvatarFromBackend(me.avatarUrl);
      await PushIdentityCache.instance.refreshSelf();
    } catch (_) {}
  }

  Future<bool> _recoverImReadyAfterTransientFailure(UserSigResult sig) async {
    const retryDelays = <Duration>[
      Duration(milliseconds: 200),
      Duration(milliseconds: 500),
      Duration(milliseconds: 900),
    ];
    _trace(
      'AuthBootstrap: recoverImReadyAfterTransientFailure START '
      '(sig userId=${sig.userId})',
    );
    for (var i = 0; i < retryDelays.length; i++) {
      await Future<void>.delayed(retryDelays[i]);
      final nativeReady = await isNativeLoggedIn(sig);
      _trace(
        'AuthBootstrap: recover attempt $i nativeReady=$nativeReady '
        '(${retryDelays[i].inMilliseconds}ms elapsed)',
      );
      if (!nativeReady) {
        _trace('AuthBootstrap: recover attempt $i not ready, continue');
        continue;
      }
      _trace('AuthBootstrap: recover attempt $i native=READY, priming UIKit');
      await primeUIKitSession(sig);
      final uikitReady = isCoreServicesUserReady();
      _trace(
        'AuthBootstrap: recover attempt $i prime done uikitReady=$uikitReady',
      );
      if (uikitReady) {
        _trace(
          'AuthBootstrap: IM transient failure recovered '
          '(attempt=$i native=true uikit=true)',
        );
        return true;
      }
    }

    final nativeReady = await isNativeLoggedIn(sig);
    _trace('AuthBootstrap: recover FINAL check nativeReady=$nativeReady');
    if (!nativeReady) {
      _trace('AuthBootstrap: recover giving up — native still not ready');
      return false;
    }

    _trace('AuthBootstrap: recover final fallback — priming UIKit');
    await primeUIKitSession(sig);
    final uikitReady = isCoreServicesUserReady();
    _trace(
      'AuthBootstrap: IM transient failure fallback '
      '(native=true uikit=$uikitReady)',
    );
    return uikitReady;
  }

  void enterHomeAfterBusinessAuth(
    BuildContext context, {
    bool syncingIm = true,
  }) {
    final ctx = AppNavigator.context ?? context;
    if (syncingIm) {
      LoginCoordinator.instance.markHomeEnteredSyncingIm();
    } else {
      LoginCoordinator.instance.markImReady(isHomeEntered: true);
    }
    try {
      Provider.of<LocalSetting>(ctx, listen: false).connectStatus =
          syncingIm ? ConnectStatus.connecting : ConnectStatus.success;
    } catch (_) {}
    _trace(
      'AuthBootstrap: enter home after business auth '
      '(syncingIm=$syncingIm)',
    );
    NotificationSettingsService.instance.endColdStartBannerSuppression();
    InitStep.leaveLaunchScreen(toHome: true, context: ctx);
  }

  Future<void> runPostLoginSideEffects() async {
    await _runPostLoginSideEffectsCore();
  }

  Future<void> _runPostLoginSideEffectsCore() async {
    StartupPerfLog.markTagged(
      'post_login_side_effects_start',
      category: 'post_home',
    );
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) {
      StartupPerfLog.markTagged(
        'post_login_side_effects_skipped_no_identity',
        category: 'post_home',
      );
      return;
    }
    bool isCurrent() => SessionIdentityService.instance.isCurrent(identity);
    // Listener attachment belongs to HomeBootstrap. This legacy side-effect
    // runner only performs its remaining domain work after the session is
    // already bound to the home route.
    if (!isCurrent()) return;

    final navContext = AppNavigator.context;
    if (navContext != null && navContext.mounted) {
      await ImConnectStatusService.syncToLocalSetting(navContext);
    }
    if (!isCurrent()) return;

    PlatformOfficialAccountService.resetSessionState();
    unawaited(
      PlatformOfficialAccountService.ensureSubscribed()
          .timeout(const Duration(seconds: 8), onTimeout: () => false)
          .catchError((_) => false),
    );
    DeviceSyncService.instance.scheduleSyncAfterLogin();
    if (ChatAttachmentService.mobileSupported) {
      unawaited(ChatAttachmentService.instance.refreshPolicy(force: true)
          .then<void>((_) {}).catchError((_) {}));
      unawaited(ChatAttachmentService.instance.load().catchError((_) {}));
    }
    if (!isCurrent()) return;
    try {
      // Starred friends 列表不是冷启动必需的——用户没主动点星标场景下
      // 拉到 idle 阶段，避免阻塞 cold_start post_home bootstrap。
      InteractionIdleScheduler.instance.schedule(
        'starred_friends_initial_refresh_relogin',
        delay: const Duration(seconds: 5),
        isCurrent: isCurrent,
        task: () async {
          try {
            await StarredFriendProvider.shared.refresh(force: false);
          } catch (_) {}
        },
      );
    } catch (_) {}
    try {
      await UserStickerProvider.shared.refresh(force: true);
      if (!isCurrent()) return;
      if (navContext != null && navContext.mounted) {
        await InitStep.publishStickerPackages(navContext);
      }
    } catch (_) {}
    try {
      await GroupNoticeBootstrap.install(
        refreshApplications: false,
        startFallbackPolling: false,
      );
    } catch (_) {}
    if (!isCurrent()) return;
    try {
      await ConversationNotifySyncService.instance.syncAllOnLogin();
    } catch (_) {}
    if (!isCurrent()) return;
    unawaited(PrivilegedGameUserService.instance.activateSession());
    unawaited(SangongMyConfigService.instance.activateSession());

    // Notification permission is user-intent driven. Do not request system
    // permission as an automatic login/cold-start side effect; the first
    // notification-related interaction owns that prompt.
    StartupPerfLog.markTagged(
      'post_login_side_effects_done',
      category: 'post_home',
    );
  }

  Future<void> syncImSessionAfterBusinessLogin({
    String? registerNickname,
  }) async {
    final ready = await prepareReadySessionForHome(
      registerNickname: registerNickname,
      timeout: const Duration(seconds: 20),
    );
    if (ready) {
      LoginCoordinator.instance.markImReady(isHomeEntered: true);
      _trace('AuthBootstrap: background IM sync done');
      return;
    }
    _trace('AuthBootstrap: background IM sync incomplete (IM not ready)');
    LoginCoordinator.instance.markFailed(
      LoginErrorType.imLoginFailed,
      message: 'IM not ready after business login',
      isBusinessAuthenticated: true,
      isHomeEntered: true,
    );
  }

  void _setBackgroundSyncing(bool value) {
    if (backgroundSyncing.value == value) {
      return;
    }
    backgroundSyncing.value = value;
  }

  void _setConnectStatus(ConnectStatus status) {
    final navContext = AppNavigator.context;
    if (navContext == null || !navContext.mounted) {
      return;
    }
    try {
      Provider.of<LocalSetting>(navContext, listen: false).connectStatus =
          status;
    } catch (_) {}
  }

  /// Password/SMS login: native IM 已匹配则不再走会挂死的 [loginImStack] 全量重登。
  Future<int> completeImSessionAfterAuth(UserSigResult sig) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    _diag('AuthBootstrap: completeImSessionAfterAuth ENTER userId=${sig.userId} '
        'sdkAppId=${sig.sdkAppId} sessionGen=$sessionGeneration');
    // FIX(im06-scope): 配置 scope 在 FAST PATH 之前，确保 native 已登录场景
    // （密码/短信登录后 native 仍在）也能配置 IM06 scope，否则走 FAST PATH
    // 会绕过 loginImStack，scope 永远不配置，聊天页云端历史无法加载。
    // 幂等安全：TUIChatGlobalModel.configureMessageWriterScope 在 scope 实际
    // 变化时才重置 coordinator（global_model.dart:663-666）。
    if (sig.sdkAppId > 0 &&
        sig.userId.trim().isNotEmpty &&
        sessionGeneration >= 0) {
      _diag('AuthBootstrap: completeImSessionAfterAuth CALL configureScope '
          'userId=${sig.userId} sessionGen=$sessionGeneration');
      configureMessageWriterScopeForSession(
        ownerUserId: sig.userId,
        accountGeneration: sessionGeneration,
      );
    } else {
      _diag('AuthBootstrap: completeImSessionAfterAuth SKIP configureScope '
          'sdkAppId<=0 OR userId empty OR sessionGen<0');
    }
    final nativeUserId = await getNativeLoginUserId();
    if (nativeUserId != null && !_isSameUserId(nativeUserId, sig.userId)) {
      _trace(
        'AuthBootstrap: completeImSessionAfterAuth clearing stale native user '
        'native=$nativeUserId target=${sig.userId}',
      );
      await clearLocalImSession(
        reason: 'foreground_identity_mismatch',
        clearCachedSession: false,
        expectedUserId: nativeUserId,
        expectedSessionGeneration: sessionGeneration,
      );
    }
    if (await isNativeLoggedIn(sig)) {
      _trace(
        'AuthBootstrap: completeImSessionAfterAuth FAST PATH (native already logged in)',
      );
      await primeUIKitSession(sig);
      _markImLoginSuccess(
        '${sig.sdkAppId}:${sig.userId}:${sig.userSig}',
        skipNetworkSideEffects: false,
      );
      unawaited(_refreshCallStack(sig));
      _trace('AuthBootstrap: completeImSessionAfterAuth FAST PATH DONE code=0');
      return 0;
    }

    _trace(
      'AuthBootstrap: completeImSessionAfterAuth SLOW PATH — calling loginImStack '
      'userId=${sig.userId}',
    );
    final code = await loginImStack(
      sig,
      forceLogin: true,
      expectedSessionGeneration: sessionGeneration,
    );
    _trace(
      'AuthBootstrap: completeImSessionAfterAuth loginImStack DONE code=$code',
    );
    return resolveImLoginCode(sig, code);
  }

  /// Native IM logged in as [sig.userId] (UIKit may still be initializing).
  Future<bool> isNativeLoggedIn(UserSigResult sig) async {
    return _isSameUserId(await getNativeLoginUserId(), sig.userId);
  }

  Future<String?> getNativeLoginUserId() async {
    final loginRes = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
    final userId = loginRes.data?.trim() ?? '';
    return userId.isEmpty ? null : userId;
  }

  Future<UserSigResult?> verifyBusinessImIdentity({
    String reason = 'identity_check',
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    final results = await Future.wait<Object>([
      AuthApi.instance.fetchMe().timeout(timeout),
      AuthApi.instance.fetchUserSig().timeout(timeout),
    ]);
    final me = results[0] as MeResult;
    var sig = results[1] as UserSigResult;
    if (!SessionIdentityService.instance.isGenerationCurrent(
      sessionGeneration,
    )) {
      return null;
    }
    if (sig.userId.trim().isEmpty || sig.userSig.trim().isEmpty) {
      _diag('AuthBootstrap: identity check empty sig reason=$reason');
      return null;
    }
    if (!_isSameUserId(me.userId, sig.userId)) {
      _diag(
        'AuthBootstrap: identity WARN reason=$reason '
        'me=${me.userId} sig=${sig.userId}; keep userSig',
      );
    }
    sig = _normalizeUserSig(sig);
    final nativeUserId = await getNativeLoginUserId();
    if (nativeUserId != null && !_isSameUserId(nativeUserId, sig.userId)) {
      _diag(
        'AuthBootstrap: native identity mismatch reason=$reason '
        'native=$nativeUserId expected=${sig.userId}',
      );
      await clearLocalImSession(
        reason: '${reason}_native_mismatch',
        clearCachedSession: true,
        expectedUserId: nativeUserId,
        expectedSessionGeneration: sessionGeneration,
      );
      return null;
    }
    final saved = await ImSessionCache.instance.saveIfCurrent(
      sig,
      () => SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      ),
    );
    return saved ? sig : null;
  }

  Future<void> clearLocalImSession({
    required String reason,
    bool clearCachedSession = false,
    String? expectedUserId,
    int? expectedSessionGeneration,
  }) async {
    final sessionGeneration =
        expectedSessionGeneration ?? SessionIdentityService.instance.generation;
    if (expectedSessionGeneration != null &&
        !SessionIdentityService.instance.isGenerationCurrent(
          expectedSessionGeneration,
        )) {
      return;
    }
    _trace('AuthBootstrap: clear local IM session ($reason)');
    HomeBootstrap.instance.reset(reason: reason);
    _setBackgroundSyncing(false);
    resetImLoginState();
    // 只 logout，不要清 imSdkInitialized：否则下次 ensureImSdkInitialized
    // 会误判并 UnInit 仍在运行的 SDK，导致「会话同步失败」且日志无 Login。
    try {
      await TIMUIKitCore.getInstance().logout().timeout(
            const Duration(seconds: 3),
          );
    } catch (_) {}
    try {
      await TencentImSDKPlugin.v2TIMManager.logout().timeout(
            const Duration(seconds: 3),
          );
    } catch (_) {}
    if (!SessionIdentityService.instance.isGenerationCurrent(
      sessionGeneration,
    )) {
      return;
    }
    try {
      await CallLifecycleService.instance.teardown();
    } catch (_) {}
    if (clearCachedSession) {
      final cacheOwner = (expectedUserId?.trim().isNotEmpty == true
                  ? expectedUserId
                  : await ImSessionCache.instance.readCachedUserId())
              ?.trim() ??
          '';
      if (cacheOwner.isNotEmpty &&
          SessionIdentityService.instance.isGenerationCurrent(
            sessionGeneration,
          )) {
        await ImSessionCache.instance.clearForUser(cacheOwner);
        await AgentRebateEntryLocalStore.instance.clearForOwner(cacheOwner);
      }
    }
  }

  bool _isSameUserId(String? left, String? right) {
    final a = left?.trim() ?? '';
    final b = right?.trim() ?? '';
    return a.isNotEmpty && b.isNotEmpty && a == b;
  }

  /// If UIKit login returned non-zero but native IM is ready, treat as success.
  Future<int> resolveImLoginCode(UserSigResult sig, int imCode) async {
    _trace(
      'AuthBootstrap: resolveImLoginCode START imCode=$imCode userId=${sig.userId}',
    );
    if (imCode == 0) {
      _trace('AuthBootstrap: resolveImLoginCode imCode=0, returning 0');
      return 0;
    }
    final nativeReady = await isNativeLoggedIn(sig);
    _trace(
      'AuthBootstrap: resolveImLoginCode imCode=$imCode nativeReady=$nativeReady',
    );
    if (nativeReady) {
      _trace(
        'AuthBootstrap: resolveImLoginCode accept native session (code=$imCode)',
      );
      resetImLoginState();
      return 0;
    }
    _trace('AuthBootstrap: resolveImLoginCode returning original code=$imCode');
    return imCode;
  }

  Future<int> loginImStack(
    UserSigResult sig, {
    bool skipNetworkSideEffects = false,
    bool forceLogin = false,
    int? expectedSessionGeneration,
  }) async {
    final sessionGeneration =
        expectedSessionGeneration ?? SessionIdentityService.instance.generation;
    if (expectedSessionGeneration != null &&
        !SessionIdentityService.instance.isGenerationCurrent(
          expectedSessionGeneration,
        )) {
      return -1;
    }
    try {
      return await _loginImStack(
        sig,
        skipNetworkSideEffects: skipNetworkSideEffects,
        forceLogin: forceLogin,
        sessionGeneration: sessionGeneration,
      ).timeout(
        _imLoginTimeout,
        onTimeout: () => _recoverImLoginAfterTimeout(
          sig,
          expectedSessionGeneration: sessionGeneration,
        ),
      );
    } catch (_) {
      return _recoverImLoginAfterTimeout(
        sig,
        expectedSessionGeneration: sessionGeneration,
      );
    }
  }

  /// 后端偶发漏带 sdkAppId 时回退到已 init / 配置值，避免直接 abort 永不 Login。
  UserSigResult _normalizeUserSig(UserSigResult sig) {
    if (sig.sdkAppId > 0) {
      return sig;
    }
    final fallback = initializedSdkAppId ?? IMDemoConfig.sdkAppID;
    _diag('AuthBootstrap: userSig sdkAppId missing, fallback=$fallback');
    return UserSigResult(
      sdkAppId: fallback,
      userId: sig.userId,
      userSig: sig.userSig,
      expiresIn: sig.expiresIn,
    );
  }

  Future<int> _loginImStack(
    UserSigResult sig, {
    bool skipNetworkSideEffects = false,
    bool forceLogin = false,
    required int sessionGeneration,
  }) async {
    sig = _normalizeUserSig(sig);
    _diag('AuthBootstrap: _loginImStack ENTER userId=${sig.userId} '
        'sdkAppId=${sig.sdkAppId} sessionGen=$sessionGeneration forceLogin=$forceLogin');
    // FIX(im06-scope): 把 scope 配置从 _doLoginImStack 顶部移到 _loginImStack 顶部。
    // 原因：_loginImStack 在 dup-login 早返回（native 已登录且 20s 内重复 login）
    // 时会绕过 _doLoginImStack，导致 configureMessageWriterScopeForSession
    // 从未被调用，聊天页 IM06 scope 永远为 null，云端历史拉取失败。
    // 幂等安全：TUIChatGlobalModel.configureMessageWriterScope 仅在 scope 实际变化
    // 时才重置 _im06HistorySearchCoordinator（global_model.dart:663-666）。
    if (sig.sdkAppId > 0 &&
        sig.userId.trim().isNotEmpty &&
        sessionGeneration >= 0) {
      _diag('AuthBootstrap: _loginImStack CALL configureScope '
          'userId=${sig.userId} sessionGen=$sessionGeneration');
      configureMessageWriterScopeForSession(
        ownerUserId: sig.userId,
        accountGeneration: sessionGeneration,
      );
    } else {
      _diag('AuthBootstrap: _loginImStack SKIP configureScope '
          'sdkAppId<=0 OR userId empty OR sessionGen<0 '
          'sdkAppId=${sig.sdkAppId} userId="${sig.userId}" sessionGen=$sessionGeneration');
    }
    if (sig.sdkAppId <= 0) {
      _diag('AuthBootstrap: _loginImStack abort invalid sdkAppId');
      return -1;
    }
    final sdkReady = await ensureImSdkInitialized(sdkAppId: sig.sdkAppId);
    if (!sdkReady ||
        !SessionIdentityService.instance.isGenerationCurrent(
          sessionGeneration,
        )) {
      _diag(
        'AuthBootstrap: _loginImStack abort IM SDK not ready '
        'for sdkAppId=${sig.sdkAppId}',
      );
      return -1;
    }

    final loginKey = '${sig.sdkAppId}:${sig.userId}:${sig.userSig}';

    final runningTask = _imLoginTask;
    if (runningTask != null) {
      // During iOS network switching the SDK and app can both trigger relogin.
      // Reuse the in-flight login instead of starting another one, otherwise the
      // SDK reports: send packet interrupt because of relogin, login ticket has changed.
      final runningKey = _imLoginTaskKey;
      if (runningKey == loginKey) {
        try {
          return await runningTask.timeout(
            _imLoginTimeout,
            onTimeout: () => _recoverImLoginAfterTimeout(sig),
          );
        } catch (_) {
          return _recoverImLoginAfterTimeout(sig);
        }
      }
      try {
        await runningTask.timeout(_imLoginTimeout);
      } catch (_) {
        _diag('AuthBootstrap: old IM login still active for new account');
        return -1;
      }
      if (_imLoginTask != null) return -1;
      return _loginImStack(
        sig,
        skipNetworkSideEffects: skipNetworkSideEffects,
        forceLogin: forceLogin,
        sessionGeneration: sessionGeneration,
      );
    }

    final currentUser = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
    final currentUserId = currentUser.data?.trim() ?? '';
    if (currentUser.code == 0 &&
        currentUserId.isNotEmpty &&
        currentUserId != sig.userId) {
      await clearLocalImSession(
        reason: 'native_user_mismatch_before_login',
        clearCachedSession: false,
        expectedUserId: currentUserId,
        expectedSessionGeneration: sessionGeneration,
      );
    }
    final now = DateTime.now();
    final lastLoginAt = _lastImLoginAt;
    final recentlyLoggedIn = lastLoginAt != null &&
        now.difference(lastLoginAt) < const Duration(seconds: 20);

    if (!forceLogin &&
        currentUser.code == 0 &&
        currentUser.data == sig.userId &&
        _lastImLoginKey != null &&
        recentlyLoggedIn) {
      // Only suppress a true duplicate login inside the same app runtime.
      // Do not use getLoginUser() alone as a reason to skip TIMUIKitCore.login:
      // after a cold start the native SDK may still know the user, while the
      // UIKit conversation/group models are not initialized yet. Skipping login
      // in that state makes the conversation list and group list look empty.
      await _refreshCallStack(sig);
      return 0;
    }

    _imLoginTaskKey = loginKey;
    _imLoginTask = _doLoginImStack(
      sig,
      loginKey: loginKey,
      skipNetworkSideEffects: skipNetworkSideEffects,
      sessionGeneration: sessionGeneration,
    );
    try {
      return await _imLoginTask!;
    } finally {
      if (_imLoginTaskKey == loginKey) {
        _imLoginTask = null;
        _imLoginTaskKey = null;
      }
    }
  }

  Future<int> _doLoginImStack(
    UserSigResult sig, {
    required String loginKey,
    required bool skipNetworkSideEffects,
    required int sessionGeneration,
  }) async {
    final gen = _loginGeneration;
    // NOTE: scope 配置已前移到 _loginImStack 顶部（保证 dup-login 早返回路径也生效）。
    // 此处删除重复调用，幂等性由 TUIChatGlobalModel.configureMessageWriterScope
    // 通过 previousScope != configuredScope 判断保证。
    _trace('AuthBootstrap: _doLoginImStack START gen=$gen loginKey=$loginKey');

    final nativeOk = await isNativeLoggedIn(sig);
    if (!SessionIdentityService.instance.isGenerationCurrent(
      sessionGeneration,
    )) {
      return -1;
    }
    _trace('AuthBootstrap: _doLoginImStack nativeOk=$nativeOk gen=$gen');

    if (nativeOk) {
      if (gen != _loginGeneration) {
        _trace('AuthBootstrap: _doLoginImStack gen changed, abort');
        return -1;
      }
      _trace('AuthBootstrap: _doLoginImStack FAST: native ok, priming UIKit');
      await primeUIKitSession(sig);
      if (gen != _loginGeneration) {
        _trace('AuthBootstrap: _doLoginImStack gen changed after prime, abort');
        return -1;
      }
      if (!SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      )) {
        return -1;
      }
      if (kDebugMode) {
        _trace(
          'AuthBootstrap: native IM ok, uikit primed=${isCoreServicesUserReady()}',
        );
      }
      unawaited(_refreshCallStack(sig));
      _markImLoginSuccess(
        loginKey,
        skipNetworkSideEffects: skipNetworkSideEffects,
      );
      _trace('AuthBootstrap: _doLoginImStack FAST path done, returning 0');
      return 0;
    }

    if (gen != _loginGeneration) {
      _trace(
        'AuthBootstrap: _doLoginImStack gen changed before slow path, abort',
      );
      return -1;
    }

    _trace(
      'AuthBootstrap: _doLoginImStack SLOW: calling _loginImWithKickRetry',
    );
    var code = await _loginImWithKickRetry(
      sig,
      sessionGeneration: sessionGeneration,
    );
    _trace('AuthBootstrap: _doLoginImStack _loginImWithKickRetry code=$code');
    if (code != 0) {
      _trace('AuthBootstrap: _doLoginImStack kickRetry failed, recover');
      code = await _recoverImLoginAfterTimeout(
        sig,
        expectedSessionGeneration: sessionGeneration,
      );
      _trace(
        'AuthBootstrap: _doLoginImStack _recoverImLoginAfterTimeout code=$code',
      );
    }
    if (code == 0) {
      await _refreshCallStack(sig);
      if (gen != _loginGeneration) {
        _trace(
          'AuthBootstrap: _doLoginImStack gen changed after refresh, abort',
        );
        return -1;
      }
      if (!SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      )) {
        return -1;
      }
      _markImLoginSuccess(
        loginKey,
        skipNetworkSideEffects: skipNetworkSideEffects,
      );
    }
    _trace('AuthBootstrap: _doLoginImStack DONE code=$code gen=$gen');
    return code;
  }

  Future<int> _loginImWithKickRetry(
    UserSigResult sig, {
    required int sessionGeneration,
  }) async {
    var lastCode = -1;
    for (var attempt = 0; attempt < _kickRetryDelays.length + 1; attempt++) {
      lastCode = await _tryTimUIKitLogin(sig);
      if (lastCode == 0 || lastCode != imKickedOfflineCode) {
        return lastCode;
      }
      if (attempt >= _kickRetryDelays.length) {
        break;
      }
      if (kDebugMode) {
        _trace('AuthBootstrap: IM login kicked offline, retry ${attempt + 1}');
      }
      await _resetLocalImSessionBeforeRetry(sig, sessionGeneration);
      await Future<void>.delayed(_kickRetryDelays[attempt]);
    }
    return await resolveImLoginCode(sig, lastCode);
  }

  Future<void> _resetLocalImSessionBeforeRetry(
    UserSigResult sig,
    int sessionGeneration,
  ) async {
    await clearLocalImSession(
      reason: 'retry_after_kick',
      clearCachedSession: false,
      expectedUserId: sig.userId,
      expectedSessionGeneration: sessionGeneration,
    );
  }

  /// Ensures [CoreServicesImpl] has [userID] set (sync prefix of [login]).
  /// Native IM may already be online while the Dart [login] Future still hangs.
  Future<void> primeUIKitSession(UserSigResult sig) async {
    final loginFuture = _trackImOperation(
      TIMUIKitCore.getInstance().login(
        userID: sig.userId,
        userSig: sig.userSig,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    try {
      final imRes = await loginFuture.timeout(_uikitLoginWait);
      if (imRes.code != 0 && kDebugMode) {
        _trace('AuthBootstrap: primeUIKitSession code=${imRes.code}');
      }
    } on TimeoutException {
      if (kDebugMode) {
        _trace('AuthBootstrap: primeUIKitSession timed out, continue');
      }
      // Dart login Future 挂起时 CoreServicesImpl.login() 不会走到
      // didLoginSuccess()，loginUserInfo / UIKit 监听永远不会被填充。
      // 原生已在线即视为登录成功，补一次幂等的 didLoginSuccess()。
      // 同级 catch 不覆盖本子句，需单独兜底，避免异常打断登录流。
      try {
        if (await isNativeLoggedIn(sig)) {
          TIMUIKitCore.getInstance().didLoginSuccess();
          _trace(
            'AuthBootstrap: primeUIKitSession timed out, native online, '
            'didLoginSuccess primed',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          _trace(
            'AuthBootstrap: primeUIKitSession didLoginSuccess prime error: $e',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _trace('AuthBootstrap: primeUIKitSession error: $e');
      }
    }
  }

  bool isCoreServicesUserReady() {
    try {
      final id = TIMUIKitCore.getInstance().loginInfo.userID.trim();
      return id.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int> _tryTimUIKitLogin(UserSigResult sig) async {
    _diag('AuthBootstrap: _tryTimUIKitLogin START userId=${sig.userId}');

    // Helper to attempt one login call.
    Future<dynamic> attemptLogin() async {
      final loginFuture = _trackImOperation(
        TIMUIKitCore.getInstance().login(
          userID: sig.userId,
          userSig: sig.userSig,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      try {
        return await loginFuture.timeout(_uikitLoginWait);
      } on TimeoutException {
        return null;
      } catch (e) {
        rethrow;
      }
    }

    final imRes = await attemptLogin();

    // Timeout: native may already be logged in — check and treat as success.
    if (imRes == null) {
      _trace('AuthBootstrap: _tryTimUIKitLogin TIMEOUT userId=${sig.userId}');
      if (await isNativeLoggedIn(sig)) {
        _trace(
          'AuthBootstrap: _tryTimUIKitLogin timeout but native ready, priming',
        );
        await primeUIKitSession(sig);
        return 0;
      }
      _trace(
        'AuthBootstrap: _tryTimUIKitLogin TIMEOUT, native not ready, returning -1',
      );
      return -1;
    }

    _trace(
      'AuthBootstrap: _tryTimUIKitLogin got result code=${imRes.code} '
      'userId=${sig.userId}',
    );

    // Code 6013 (SDK busy / still initializing after logout): retry once.
    // This is observed to succeed on immediate retry when login follows logout.
    if (imRes.code == 6013) {
      _trace('AuthBootstrap: _tryTimUIKitLogin code=6013, retrying once');
      final retryRes = await attemptLogin();
      if (retryRes != null && retryRes.code == 0) {
        _trace('AuthBootstrap: _tryTimUIKitLogin retry OK code=0');
        return 0;
      }
      // Retry also failed — return the original code to trigger kick-retry.
      if (retryRes != null) {
        _trace(
          'AuthBootstrap: _tryTimUIKitLogin retry FAIL code=${retryRes.code}',
        );
        return retryRes.code;
      }
      _trace('AuthBootstrap: _tryTimUIKitLogin retry TIMEOUT, returning -1');
      return -1;
    }

    if (imRes.code != 0) {
      _trace(
        'AuthBootstrap: _tryTimUIKitLogin FAIL code=${imRes.code} '
        'userId=${sig.userId}',
      );
      return imRes.code;
    }

    final uikitReady = isCoreServicesUserReady();
    _trace(
      'AuthBootstrap: _tryTimUIKitLogin OK code=0 uikitReady=$uikitReady '
      'userId=${sig.userId}',
    );
    return 0;
  }

  void _markImLoginSuccess(
    String loginKey, {
    required bool skipNetworkSideEffects,
  }) {
    _lastImLoginKey = loginKey;
    _lastImLoginAt = DateTime.now();
    unawaited(PushIdentityCache.instance.refreshSelf());
    if (!skipNetworkSideEffects) {
      unawaited(
        PushRegistrationService.instance.syncAfterLogin().catchError((_) {}),
      );
    }
  }

  /// TIMUIKitCore.login can outlive native IM login; clear the stuck task and
  /// accept success when the SDK already has the expected user.
  Future<int> _recoverImLoginAfterTimeout(
    UserSigResult sig, {
    int? expectedSessionGeneration,
  }) async {
    if (expectedSessionGeneration != null &&
        !SessionIdentityService.instance.isGenerationCurrent(
          expectedSessionGeneration,
        )) {
      return -1;
    }
    resetImLoginState();
    final loginRes = await TencentImSDKPlugin.v2TIMManager.getLoginUser();
    final userId = loginRes.data?.trim() ?? '';
    if (loginRes.code == 0 && userId.isNotEmpty && userId == sig.userId) {
      _lastImLoginKey = '${sig.sdkAppId}:${sig.userId}:${sig.userSig}';
      _lastImLoginAt = DateTime.now();
      await primeUIKitSession(sig);
      if (expectedSessionGeneration != null &&
          !SessionIdentityService.instance.isGenerationCurrent(
            expectedSessionGeneration,
          )) {
        return -1;
      }
      await _refreshCallStack(sig);
      return 0;
    }
    return -1;
  }

  Future<void> _refreshCallStack(UserSigResult sig) async {
    _trace('AuthBootstrap: _refreshCallStack CALLED userId=${sig.userId}');
    try {
      unawaited(IosApnsPushService.instance.syncLoginUserId(sig.userId));
      await CallLifecycleService.instance.ensureObserversAttached();
      await CallLifecycleService.instance.ensureFloatWindowEnabled();
      _trace(
        'AuthBootstrap: _refreshCallStack LiveKit signaling READY userId=${sig.userId}',
      );
    } catch (_) {}
  }

  Future<bool> refreshUserSigAndRelogin() async {
    final running = _refreshUserSigTask;
    if (running != null) {
      return running;
    }
    final task = _doRefreshUserSigAndRelogin();
    _refreshUserSigTask = task.whenComplete(() {
      if (identical(_refreshUserSigTask, task)) {
        _refreshUserSigTask = null;
      }
    });
    return _refreshUserSigTask!;
  }

  Future<bool> _doRefreshUserSigAndRelogin() async {
    lastUserSigRefreshWasAuthFailure = false;
    final sessionGeneration = SessionIdentityService.instance.generation;
    LoginCoordinator.instance.markSessionRefreshing();
    try {
      final me = await AuthApi.instance.fetchMe();
      var sig = await AuthApi.instance.fetchUserSig();
      if (!SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      )) {
        return false;
      }
      if (sig.userId.trim().isEmpty || sig.userSig.trim().isEmpty) {
        LoginCoordinator.instance.markFailed(
          LoginErrorType.fetchUserSigFailed,
          message: 'empty userSig payload',
          isBusinessAuthenticated: true,
          isHomeEntered: true,
        );
        return false;
      }
      if (!_isSameUserId(me.userId, sig.userId)) {
        _diag(
          'AuthBootstrap: refresh WARN me/sig mismatch '
          'me=${me.userId} sig=${sig.userId}; proceed with userSig',
        );
      }
      sig = _normalizeUserSig(sig);
      LoginCoordinator.instance.markImConnecting(
        userId: sig.userId,
        isRecovering: true,
      );
      final cacheSaved = await ImSessionCache.instance.saveIfCurrent(
        sig,
        () => SessionIdentityService.instance.isGenerationCurrent(
          sessionGeneration,
        ),
      );
      if (!cacheSaved) return false;
      final imCode = await loginImStack(
        sig,
        forceLogin: true,
        expectedSessionGeneration: sessionGeneration,
      );
      if (!SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      )) {
        return false;
      }
      if (imCode == 0) {
        LoginCoordinator.instance.markImReady(userId: sig.userId);
        return true;
      }
      LoginCoordinator.instance.markFailed(
        LoginErrorType.imLoginFailed,
        message: 'userSig refresh relogin failed',
        userId: sig.userId,
        isBusinessAuthenticated: true,
        isHomeEntered: true,
      );
      return false;
    } on DioError catch (error) {
      lastUserSigRefreshWasAuthFailure =
          ApiClient.isExplicitSessionExpiryError(error) ||
              (error.response?.statusCode == 401 &&
                  !DioErrorMessage.isNetworkRelated(error));
      LoginCoordinator.instance.markFailed(
        LoginErrorType.fetchUserSigFailed,
        message: 'Failed to refresh userSig',
        isBusinessAuthenticated: true,
        isHomeEntered: true,
      );
      return false;
    } catch (e, st) {
      LoginCoordinator.instance.markFailed(
        LoginErrorType.imLoginFailed,
        message: 'Unexpected error while refreshing userSig',
        cause: e,
        stackTrace: st,
        isBusinessAuthenticated: true,
        isHomeEntered: true,
      );
      return false;
    }
  }

  void resetImLoginState() {
    _loginGeneration++;
    // _loginImStack.finally owns the in-flight task. Dropping it here allowed
    // a second account to issue login while the old native call still ran.
    _lastImLoginKey = null;
    _lastImLoginAt = null;
  }

  bool _pushWakeRestoring = false;

  /// Called when Android FCM data push wakes a killed process.
  Future<bool> restoreSessionForPushWake() async {
    if (_pushWakeRestoring) return false;
    _pushWakeRestoring = true;
    final sessionGeneration = SessionIdentityService.instance.generation;
    try {
      await ApiClient.instance.loadToken();
      final token = ApiClient.instance.token;
      if (!ApiClient.isValidJwt(token)) {
        return false;
      }

      final me = await AuthApi.instance.fetchMe().timeout(
            const Duration(seconds: 4),
          );
      if (!SessionIdentityService.instance.isGenerationCurrent(
        sessionGeneration,
      )) {
        return false;
      }
      final expectedUserId = me.userId.trim();
      if (expectedUserId.isEmpty) {
        return false;
      }

      final nativeUserId = await getNativeLoginUserId();
      if (nativeUserId != null && nativeUserId != expectedUserId) {
        await clearLocalImSession(
          reason: 'push_wake_native_user_mismatch',
          clearCachedSession: true,
          expectedUserId: nativeUserId,
          expectedSessionGeneration: sessionGeneration,
        );
      }

      if (_isSameUserId(nativeUserId, expectedUserId)) {
        await _refreshCallStackForWake(
          expectedUserId: expectedUserId,
          expectedSessionGeneration: sessionGeneration,
        );
        return true;
      }

      UserSigResult sig;
      var usedCachedSig = false;
      final cached = await ImSessionCache.instance.loadIfValidForUser(
        expectedUserId,
      );
      if (cached != null) {
        sig = cached;
        usedCachedSig = true;
      } else {
        sig = await AuthApi.instance.fetchUserSig();
        if (!_isSameUserId(sig.userId, expectedUserId)) {
          await clearLocalImSession(
            reason: 'push_wake_sig_user_mismatch',
            clearCachedSession: true,
            expectedUserId: sig.userId,
            expectedSessionGeneration: sessionGeneration,
          );
          return false;
        }
        final saved = await ImSessionCache.instance.saveIfCurrent(
          sig,
          () => SessionIdentityService.instance.isGenerationCurrent(
            sessionGeneration,
          ),
        );
        if (!saved) return false;
      }

      final imCode = await loginImStack(
        sig,
        forceLogin: true,
        expectedSessionGeneration: sessionGeneration,
      );
      if (imCode == 0) {
        return true;
      }
      if (!usedCachedSig) {
        return false;
      }
      final refreshedSig = await AuthApi.instance.fetchUserSig();
      if (!_isSameUserId(refreshedSig.userId, expectedUserId)) {
        await clearLocalImSession(
          reason: 'push_wake_refresh_sig_user_mismatch',
          clearCachedSession: true,
          expectedUserId: refreshedSig.userId,
          expectedSessionGeneration: sessionGeneration,
        );
        return false;
      }
      final refreshedSaved = await ImSessionCache.instance.saveIfCurrent(
        refreshedSig,
        () => SessionIdentityService.instance.isGenerationCurrent(
          sessionGeneration,
        ),
      );
      if (!refreshedSaved) return false;
      final refreshedCode = await loginImStack(
        refreshedSig,
        forceLogin: true,
        expectedSessionGeneration: sessionGeneration,
      );
      return refreshedCode == 0;
    } catch (_) {
      return false;
    } finally {
      _pushWakeRestoring = false;
    }
  }

  Future<void> _refreshCallStackForWake({
    required String expectedUserId,
    int? expectedSessionGeneration,
  }) async {
    UserSigResult? sig = await ImSessionCache.instance.loadIfValidForUser(
      expectedUserId,
    );
    try {
      sig ??= await AuthApi.instance.fetchUserSig();
    } catch (_) {
      if (sig == null) return;
    }
    final resolvedSig = sig;
    if (!_isSameUserId(resolvedSig.userId, expectedUserId)) {
      await clearLocalImSession(
        reason: 'call_stack_wake_sig_user_mismatch',
        clearCachedSession: true,
        expectedUserId: resolvedSig.userId,
        expectedSessionGeneration: expectedSessionGeneration,
      );
      return;
    }
    if (expectedSessionGeneration != null) {
      final saved = await ImSessionCache.instance.saveIfCurrent(
        resolvedSig,
        () => SessionIdentityService.instance.isGenerationCurrent(
          expectedSessionGeneration,
        ),
      );
      if (!saved) return;
    } else {
      await ImSessionCache.instance.save(resolvedSig);
    }
    await CallLifecycleService.instance.ensureObserversAttached();
    await CallLifecycleService.instance.ensureFloatWindowEnabled();
  }
}
