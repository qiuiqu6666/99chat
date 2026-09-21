// ignore_for_file: avoid_print

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/auth_localizations.dart';
import 'package:tencent_cloud_chat_demo/src/services/account_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_session_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_session_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_chat_notification_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_error.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/login_credential_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_diagnostics.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_state.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_service.dart';
import 'package:tencent_cloud_chat_demo/utils/auth_error_codes.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/init_step.dart';
import 'package:tencent_cloud_chat_demo/utils/phone_format.dart';

class LoginCoordinator extends ChangeNotifier {
  LoginCoordinator._();
  void _sessionLog(String message) {
    SessionDiagnostics.log(message);
  }

  static final LoginCoordinator instance = LoginCoordinator._();

  LoginState _state = LoginState.initial();

  LoginState get state => _state;

  /// 当前会话是否用了 offline cached user_sig（没走 /im/user-sig）。
  /// app.dart 用此标记判断是否跳过冷启动后的 app_resumed reconcile。
  bool _usedOfflineCachedSig = false;

  bool get usedOfflineCachedSig => _usedOfflineCachedSig;

  Future<void> loginWithSmsCode({
    required BuildContext context,
    required String phoneE164,
    required String phone,
    required String smsCode,
    required String countryCode,
    required String countryIso,
  }) async {
    final strings = AuthLocalizations.of(context);
    markBusinessAuthenticating();
    try {
      await AuthSessionService.instance.beginLogin();
      final tr = await AuthApi.instance.loginSms(
        phone: phoneE164,
        smsCode: smsCode,
        phoneCountry: countryIso,
      );
      await AuthSessionService.instance.applyTokenResult(tr);
      markBusinessAuthenticated(userId: tr.userId);
      await LoginCredentialStore.instance.saveSmsLogin(
        phone: phone,
        countryCode: countryCode,
        countryIso: countryIso,
      );
      await _completeForegroundLoginAndEnterHome(context: context);
    } on DioError catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromAuth(e, strings),
        error: e,
      );
    } on AuthApiBusinessException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: AuthErrorCodes.map(e.code, strings),
        error: e,
      );
    } on AuthSessionException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: e.message,
        error: e,
      );
    } catch (e, st) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromThrowable(e, strings),
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<PasswordLoginCoordinatorResult> loginWithPassword({
    required BuildContext context,
    required String rawAccount,
    required String account,
    required String password,
    required bool rememberPassword,
    required String phoneCountryIso,
    required String countryCode,
    required String phoneInput,
  }) async {
    final strings = AuthLocalizations.of(context);
    final phoneInputE164 = PhoneFormat.tryE164(
      countryCode: countryCode,
      countryIso: phoneCountryIso,
      nationalNumber: phoneInput,
    );
    markBusinessAuthenticating(userId: account);
    try {
      await AuthSessionService.instance.beginLogin();
      final res = await AuthApi.instance.loginPassword(
        account: account,
        password: password,
        phoneCountry: phoneCountryIso,
      );
      if (res.isLoginOk) {
        await AuthSessionService.instance.applyPasswordLoginOk(res);
        markBusinessAuthenticated(userId: res.userId ?? account);
        await LoginCredentialStore.instance.savePasswordLogin(
          account: rawAccount,
          password: password,
          rememberPassword: rememberPassword,
          phoneCountryIso: phoneCountryIso,
          countryCode: countryCode,
          phone: phoneInputE164 != null ? phoneInput : null,
        );
        await _completeForegroundLoginAndEnterHome(context: context);
        return const PasswordLoginCoordinatorResult.completed();
      }
      if (res.needSms) {
        final devicePhone = PhoneFormat.resolveForDeviceChallenge(
          account: account,
          defaultCountryCode: countryCode,
          defaultCountryIso: phoneCountryIso,
          phoneFromServer: res.phone,
          phoneFromLoginField: phoneInputE164,
        );
        if (!PhoneFormat.isValidE164(devicePhone) ||
            PhoneFormat.isMaskedPhone(devicePhone)) {
          throw _handleFailure(
            LoginErrorType.deviceVerificationFailed,
            message: strings.deviceVerifyPhoneUnavailable,
          );
        }
        final challengeId = res.challengeId?.trim() ?? '';
        if (challengeId.isEmpty) {
          throw _handleFailure(
            LoginErrorType.deviceVerificationFailed,
            message: strings.requestFailed,
          );
        }
        markDeviceVerifying(userId: res.userId ?? account);
        return PasswordLoginCoordinatorResult.deviceChallenge(
          challengeId: challengeId,
          phone: devicePhone!,
          phoneMasked: res.phoneMasked ?? '',
        );
      }
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: strings.requestFailed,
      );
    } on DioError catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromAuth(e, strings),
        error: e,
      );
    } on AuthApiBusinessException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: AuthErrorCodes.map(e.code, strings),
        error: e,
      );
    } on AuthSessionException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: e.message,
        error: e,
      );
    } on FormatException catch (e, st) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: strings.requestFailed,
        error: e,
        stackTrace: st,
      );
    } catch (e) {
      if (e is LoginCoordinatorException) {
        rethrow;
      }
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromThrowable(e, strings),
        error: e,
      );
    }
  }

  Future<void> loginWithQrTokenResult({
    required BuildContext context,
    required TokenResult tokenResult,
  }) async {
    final strings = AuthLocalizations.of(context);
    markBusinessAuthenticating();
    try {
      await AuthSessionService.instance.beginLogin();
      await AuthSessionService.instance.applyTokenResult(tokenResult);
      markBusinessAuthenticated(userId: tokenResult.userId);
      await _completeForegroundLoginAndEnterHome(context: context);
    } on DioError catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromAuth(e, strings),
        error: e,
      );
    } on AuthApiBusinessException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: AuthErrorCodes.map(e.code, strings),
        error: e,
      );
    } on AuthSessionException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: e.message,
        error: e,
      );
    } catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: strings.requestFailed,
        error: e,
      );
    }
  }

  Future<void> completePasswordLoginAfterDeviceChallenge({
    required BuildContext context,
    required String rawAccount,
    required String password,
    required bool rememberPassword,
    required String phoneCountryIso,
    required String countryCode,
    required String phoneInput,
  }) async {
    final phoneInputE164 = PhoneFormat.tryE164(
      countryCode: countryCode,
      countryIso: phoneCountryIso,
      nationalNumber: phoneInput,
    );
    await LoginCredentialStore.instance.savePasswordLogin(
      account: rawAccount,
      password: password,
      rememberPassword: rememberPassword,
      phoneCountryIso: phoneCountryIso,
      countryCode: countryCode,
      phone: phoneInputE164 != null ? phoneInput : null,
    );
    await _completeForegroundLoginAndEnterHome(context: context);
  }

  Future<void> registerAccount({
    required BuildContext context,
    required String phoneE164,
    required String phone,
    required String smsCode,
    required String nickname,
    required String password,
    required String countryCode,
    required String countryIso,
  }) async {
    final strings = AuthLocalizations.of(context);
    markBusinessAuthenticating();
    try {
      await AuthSessionService.instance.beginLogin();
      final tr = await AuthApi.instance.register(
        phone: phoneE164,
        smsCode: smsCode,
        nickname: nickname,
        password: password,
        phoneCountry: countryIso,
        avatarUrl: IMDemoConfig.defaultRegisterAvatarUrl,
      );
      await AuthSessionService.instance.applyTokenResult(tr);
      markBusinessAuthenticated(userId: tr.userId);
      await LoginCredentialStore.instance.saveSmsLogin(
        phone: phone,
        countryCode: countryCode,
        countryIso: countryIso,
      );
      await _completeForegroundLoginAndEnterHome(
        context: context,
        nickname: nickname,
      );
    } on DioError catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromAuth(e, strings),
        error: e,
      );
    } on AuthApiBusinessException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: AuthErrorCodes.map(e.code, strings),
        error: e,
      );
    } on AuthSessionException catch (e) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: e.message,
        error: e,
      );
    } catch (e, st) {
      throw _handleFailure(
        LoginErrorType.businessAuthFailed,
        message: DioErrorMessage.fromThrowable(e, strings),
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> verifyDeviceChallenge({
    required BuildContext context,
    required String challengeId,
    required String smsCode,
  }) async {
    final strings = AuthLocalizations.of(context);
    markDeviceVerifying();
    try {
      final tr = await AuthApi.instance.loginPasswordVerify(
        challengeId: challengeId,
        smsCode: smsCode,
      );
      await AuthSessionService.instance.applyTokenResult(tr);
      markBusinessAuthenticated(userId: tr.userId);
    } on DioError catch (e) {
      throw _handleFailure(
        LoginErrorType.deviceVerificationFailed,
        message: DioErrorMessage.fromAuth(e, strings),
        error: e,
      );
    } on AuthApiBusinessException catch (e) {
      throw _handleFailure(
        LoginErrorType.deviceVerificationFailed,
        message: AuthErrorCodes.map(e.code, strings),
        error: e,
      );
    } on AuthSessionException catch (e) {
      throw _handleFailure(
        LoginErrorType.deviceVerificationFailed,
        message: e.message,
        error: e,
      );
    } catch (e, st) {
      throw _handleFailure(
        LoginErrorType.deviceVerificationFailed,
        message: DioErrorMessage.fromThrowable(e, strings),
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<LoginRecoveryResult> restoreColdStartSession() async {
    final sessionGeneration = SessionIdentityService.instance.generation;
    _sessionLog(
      '>>>> COLD_START restoreColdStartSession BEGIN <<<<',
    );
    final token = ApiClient.instance.token;
    _sessionLog(
      'SESSION_LOG coldStart start '
      'tokenValid=${ApiClient.isValidJwt(token)} '
      'hasToken=${token != null && token.trim().isNotEmpty}',
    );
    if (!ApiClient.isValidJwt(token)) {
      _sessionLog('SESSION_LOG coldStart -> goLogin reason=invalid_token');
      markLoggedOut();
      return const LoginRecoveryResult.goLogin();
    }

    markSessionRefreshing();
    MeResult? me;
    UserSigResult? sig;
    var usedOfflineCachedSig = false;

    try {
      StartupPerfLog.mark('cold_profile_fetch_start');
      final userSigStartedAt = DateTime.now();
      StartupPerfLog.markTagged(
        'user_sig_wait_start',
        category: 'cold_start',
        details: <String, Object>{'reason': 'cold_start_restore'},
      );
      Future<UserSigResult> fetchUserSig() async {
        try {
          return await AuthApi.instance
              .fetchUserSig()
              .timeout(const Duration(seconds: 4));
        } finally {
          StartupPerfLog.markTagged(
            'user_sig_wait_end',
            category: 'cold_start',
            details: <String, Object>{
              'reason': 'cold_start_restore',
              'elapsedMs':
                  DateTime.now().difference(userSigStartedAt).inMilliseconds,
            },
          );
        }
      }
      final results = await Future.wait<Object>([
        AuthApi.instance.fetchMe().timeout(const Duration(seconds: 4)),
        fetchUserSig(),
      ]);
      me = results[0] as MeResult;
      sig = results[1] as UserSigResult;
      StartupPerfLog.mark('cold_profile_fetch_done', <String, Object>{
        'sameUser': _isSameUserId(me.userId, sig.userId),
      });
      if (!SessionIdentityService.instance
          .isGenerationCurrent(sessionGeneration)) {
        _sessionLog('SESSION_LOG coldStart abort stale profile response');
        return const LoginRecoveryResult.restartColdStart();
      }
      if (!_isSameUserId(me.userId, sig.userId)) {
        // UserSig 为 IM 真源；与 /me 暂不一致时仍继续冷启，避免直接踢回登录页。
        _sessionLog(
          'SESSION_LOG coldStart WARN identity_mismatch '
          'me=${me.userId} sig=${sig.userId}; proceed with userSig',
        );
        debugPrint(
          'AuthBootstrap: coldStart WARN me/sig mismatch '
          'me=${me.userId} sig=${sig.userId}; proceed with userSig',
        );
      }
      StartupPerfLog.mark('cold_session_cache_start');
      final ownerSaved =
          await ApiClient.instance.saveAuthenticatedUserIdIfCurrent(
        expectedToken: token,
        userId: sig.userId,
      );
      if (!ownerSaved ||
          !SessionIdentityService.instance.isGenerationCurrent(
            sessionGeneration,
          ) ||
          !await ImSessionCache.instance.saveIfCurrent(
            sig,
            () => SessionIdentityService.instance.isGenerationCurrent(
              sessionGeneration,
            ),
          )) {
        _sessionLog('SESSION_LOG coldStart abort stale credential response');
        return const LoginRecoveryResult.restartColdStart();
      }
    } on DioError catch (e) {
      if (DioErrorMessage.isAuthFailure(e)) {
        _sessionLog(
          'SESSION_LOG coldStart -> goLogin '
          'reason=auth_failure status=${e.response?.statusCode}',
        );
        markSessionExpired(
          message: 'Session expired during cold start restore',
        );
        await _clearSessionForLogout(reason: 'auth_state_invalid');
        return const LoginRecoveryResult.goLogin();
      }
      _sessionLog(
        'SESSION_LOG coldStart network profile failed, try offline cache '
        'type=${e.type} status=${e.response?.statusCode}',
      );
    } catch (e) {
      // TimeoutException / 其它瞬时失败：未鉴权失败时走离线缓存。
      _sessionLog(
        'SESSION_LOG coldStart profile error, try offline cache error=$e',
      );
    }

    if (me == null || sig == null) {
      final cachedOwner = ApiClient.instance.authenticatedUserId;
      final cached = await ImSessionCache.instance.loadIfValidForUser(
        cachedOwner,
      );
      if (cached == null) {
        final owner = cachedOwner;
        if (shouldEnterDegradedHomeWithoutUserSig(
          hasValidJwt: ApiClient.isValidJwt(token),
          authenticatedUserId: owner,
        )) {
          _sessionLog(
            'SESSION_LOG coldStart -> goHome '
            'reason=no_usersig_cache_retry owner=$owner',
          );
          markFailed(
            LoginErrorType.restoreFailed,
            message: 'Cold start IM credential temporarily unavailable',
            userId: owner,
            isBusinessAuthenticated: true,
            isHomeEntered: true,
            isImReady: false,
            isRecovering: true,
          );
          unawaited(
            AuthBootstrapService.instance.syncImSessionAfterBusinessLogin(),
          );
          return LoginRecoveryResult.goHome(
            userId: owner,
            me: _meStubFromUserId(owner),
          );
        }
        _sessionLog(
          'SESSION_LOG coldStart -> goLogin reason=no_offline_usersig_cache',
        );
        markFailed(
          LoginErrorType.restoreFailed,
          message: 'Cold start offline restore missing UserSig cache',
          isRecovering: true,
        );
        return const LoginRecoveryResult.goLogin();
      }
      sig = cached;
      me = _meStubFromCachedSig(cached);
      final ownerSaved =
          await ApiClient.instance.saveAuthenticatedUserIdIfCurrent(
        expectedToken: token,
        userId: cached.userId,
      );
      if (!ownerSaved ||
          !SessionIdentityService.instance.isGenerationCurrent(
            sessionGeneration,
          )) {
        return const LoginRecoveryResult.restartColdStart();
      }
      usedOfflineCachedSig = true;
      StartupPerfLog.mark('cold_profile_offline_cache_hit');
      _sessionLog(
        'SESSION_LOG coldStart offline cache hit userId=${cached.userId}',
      );
    }

    markImConnecting(
      userId: sig.userId,
      isRecovering: true,
    );

    _sessionLog(
      '>>>> COLD_START loginImStack START userId=${sig.userId} '
      'offline=$usedOfflineCachedSig <<<<',
    );
    _sessionLog(
      'SESSION_LOG coldStart loginImStack START '
      'userId=${sig.userId} forceLogin=true offline=$usedOfflineCachedSig',
    );
    StartupPerfLog.mark('cold_im_login_start');
    var imCode = await AuthBootstrapService.instance.loginImStack(
      sig,
      forceLogin: true,
      expectedSessionGeneration: sessionGeneration,
    );
    StartupPerfLog.mark('cold_im_login_done', <String, Object>{'code': imCode});
    _sessionLog(
      'SESSION_LOG coldStart loginImStack DONE code=$imCode '
      'userId=${sig.userId}',
    );
    imCode = await AuthBootstrapService.instance.resolveImLoginCode(
      sig,
      imCode,
    );
    final imLoginReady = imCode == 0;
    StartupPerfLog.mark('cold_im_state_resolved', <String, Object>{
      'ready': imLoginReady,
    });
    if (imCode != 0) {
      // A valid business token remains authenticated when IM is temporarily
      // unavailable. Enter the local home and retry IM in the background.
      _sessionLog(
        'SESSION_LOG coldStart IM login failed code=$imCode '
        'continue_degraded_home userId=${sig.userId} '
        'offline=$usedOfflineCachedSig',
      );
      AuthBootstrapService.instance.resetImLoginState();
    }

    // Web：IM 已登录即先进首页，列表/通讯录后台补齐，避免首屏长时间白屏。
    if (kIsWeb) {
      _applyColdStartImState(
        userId: sig.userId,
        imLoginReady: imLoginReady,
      );
      if (!imLoginReady) {
        unawaited(
          AuthBootstrapService.instance.syncImSessionAfterBusinessLogin(),
        );
      }
      unawaited(_finishWebColdStartBackground(sig: sig, me: me));
      _sessionLog(
        'SESSION_LOG coldStart -> goHome(web_fast) userId=${sig.userId}',
      );
      StartupPerfLog.markTagged(
        'auth_route_wait_start',
        category: 'cold_start',
        details: <String, Object>{'target': 'home', 'reason': 'cold_start'},
      );
      return LoginRecoveryResult.goHome(
        userId: sig.userId,
        me: me,
      );
    }

    return _finishNativeColdStartGoHome(
      sig: sig,
      me: me,
      usedOfflineCachedSig: usedOfflineCachedSig,
      imLoginReady: imLoginReady,
    );
  }

  /// 迁移期原生冷启动：IM 就绪后直接进入首页，业务预热由首页负责。
  Future<LoginRecoveryResult> _finishNativeColdStartGoHome({
    required UserSigResult sig,
    required MeResult me,
    required bool usedOfflineCachedSig,
    required bool imLoginReady,
  }) async {
    _usedOfflineCachedSig = usedOfflineCachedSig;
    if (!AuthBootstrapService.instance.isCoreServicesUserReady()) {
      await AuthBootstrapService.instance.primeUIKitSession(sig);
    }
    _applyColdStartImState(
      userId: sig.userId,
      imLoginReady: imLoginReady,
    );
    if (!imLoginReady) {
      unawaited(
        AuthBootstrapService.instance.syncImSessionAfterBusinessLogin(),
      );
    }
    unawaited(
      PrivilegedGameUserService.instance.activateSession(
        userId: sig.userId,
      ),
    );
    unawaited(
      SangongMyConfigService.instance.activateSession(
        userId: sig.userId,
      ),
    );
    unawaited(
      ImChatNotificationClearService.instance.clearAllImChatNotifications(
        reason: usedOfflineCachedSig
            ? 'cold_start_offline_im_ready'
            : 'cold_start_im_ready',
      ),
    );
    _sessionLog(
      'SESSION_LOG coldStart -> goHome('
      '${usedOfflineCachedSig ? 'offline_local' : 'local_hot_window'}) '
      'userId=${sig.userId}',
    );
    StartupPerfLog.markTagged(
      'auth_route_wait_start',
      category: 'cold_start',
      details: <String, Object>{'target': 'home', 'reason': 'cold_start'},
    );
    return LoginRecoveryResult.goHome(
      userId: sig.userId,
      me: me,
    );
  }

  void _applyColdStartImState({
    required String userId,
    required bool imLoginReady,
  }) {
    if (imLoginReady) {
      markImReady(
        userId: userId,
        isHomeEntered: true,
      );
      return;
    }
    markFailed(
      LoginErrorType.imLoginFailed,
      message: 'Cold start IM restore temporarily unavailable',
      userId: userId,
      isBusinessAuthenticated: true,
      isHomeEntered: true,
      isImReady: false,
      isRecovering: true,
    );
  }

  @visibleForTesting
  static MeResult meStubFromCachedSig(UserSigResult sig) {
    return _meStubFromCachedSig(sig);
  }

  static MeResult _meStubFromCachedSig(UserSigResult sig) {
    return _meStubFromUserId(sig.userId);
  }

  static MeResult _meStubFromUserId(String userId) {
    final id = userId.trim();
    return MeResult(
      userId: id,
      phone: '',
      phoneMasked: '',
      nickname: id,
    );
  }

  /// 网络拉 me/sig 失败且非鉴权错误、本地仍有未过期 UserSig 时，允许离线进首页。
  @visibleForTesting
  static bool shouldUseOfflineColdStartCache({
    required bool hasValidJwt,
    required bool networkProfileOk,
    required bool isAuthFailure,
    required bool hasCachedUserSig,
  }) {
    return hasValidJwt &&
        !networkProfileOk &&
        !isAuthFailure &&
        hasCachedUserSig;
  }

  @visibleForTesting
  static bool shouldEnterDegradedHomeWithoutUserSig({
    required bool hasValidJwt,
    required String authenticatedUserId,
  }) {
    return hasValidJwt && authenticatedUserId.trim().isNotEmpty;
  }

  /// IM failure does not invalidate an otherwise valid business session.
  @visibleForTesting
  static bool shouldEnterHomeDespiteImLoginFailure({
    required bool hasValidJwt,
    required int imCode,
  }) {
    return hasValidJwt && imCode != 0;
  }

  Future<LoginRecoveryResult> recoverOnForeground() async {
    final token = ApiClient.instance.token;
    _sessionLog(
      'SESSION_LOG foreground start '
      'tokenValid=${ApiClient.isValidJwt(token)} '
      'hasToken=${token != null && token.trim().isNotEmpty}',
    );
    if (!ApiClient.isValidJwt(token)) {
      _sessionLog(
        'SESSION_LOG foreground -> goLogin '
        'reason=invalid_token',
      );
      markLoggedOut();
      await _clearSessionForLogout(reason: 'resume_without_token');
      return const LoginRecoveryResult.goLogin();
    }

    // Foreground recovery shares the same business-token gate and IM owner as
    // cold start. This removes the old native-user verification path, which
    // could report success while SessionManager had already moved to another
    // account generation.
    await SessionManager.instance.restore();
    final session = SessionManager.instance.state;
    final userId = session.userId?.trim() ?? '';
    if (session.isLoggedOut || userId.isEmpty) {
      _sessionLog(
          'SESSION_LOG foreground -> goLogin reason=session_logged_out');
      markLoggedOut();
      return const LoginRecoveryResult.goLogin();
    }
    if (session.isReady) {
      _sessionLog('SESSION_LOG foreground -> stayOnHome userId=$userId');
      markImReady(userId: userId);
      return LoginRecoveryResult.stayOnHome(userId: userId);
    }
    if (session.phase == SessionPhase.offline) {
      _sessionLog(
        'SESSION_LOG foreground -> stayOnHome '
        'reason=im_or_network_unavailable userId=$userId',
      );
      markFailed(
        LoginErrorType.imLoginFailed,
        message: 'IM temporarily unavailable',
        userId: userId,
        isBusinessAuthenticated: true,
        isHomeEntered: true,
        isImReady: false,
        isRecovering: true,
      );
      return LoginRecoveryResult.stayOnHome(userId: userId);
    }
    _sessionLog(
        'SESSION_LOG foreground -> restartColdStart phase=${session.phase}');
    markSessionRefreshing(userId: userId);
    return const LoginRecoveryResult.restartColdStart();
  }

  void markLoggedOut({String? userId}) {
    _setState(
      LoginState(
        phase: LoginPhase.loggedOut,
        isBusinessAuthenticated: false,
        isHomeEntered: false,
        isImReady: false,
        isRecovering: false,
        currentUserId: userId,
      ),
    );
  }

  void markBusinessAuthenticating({String? userId}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.businessAuthenticating,
        isBusinessAuthenticated: false,
        isHomeEntered: false,
        isImReady: false,
        isRecovering: false,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markDeviceVerifying({String? userId}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.deviceVerifying,
        isRecovering: false,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markBusinessAuthenticated({String? userId}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.businessAuthenticated,
        isBusinessAuthenticated: true,
        isHomeEntered: false,
        isImReady: false,
        isRecovering: false,
        currentUserId: userId,
        lastError: null,
      ),
    );
    if (userId != null && userId.trim().isNotEmpty) {
      unawaited(
        PrivilegedGameUserService.instance.activateSession(userId: userId),
      );
      unawaited(
        SangongMyConfigService.instance.activateSession(userId: userId),
      );
    }
  }

  void markHomeEnteredSyncingIm({String? userId}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.homeEnteredSyncingIm,
        isBusinessAuthenticated: true,
        isHomeEntered: true,
        isImReady: false,
        isRecovering: false,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markImConnecting({
    String? userId,
    bool isRecovering = false,
  }) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.imConnecting,
        isBusinessAuthenticated: true,
        isHomeEntered: _state.isHomeEntered,
        isImReady: false,
        isRecovering: isRecovering,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markImReady({
    String? userId,
    bool? isHomeEntered,
  }) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.imReady,
        isBusinessAuthenticated: true,
        isHomeEntered: isHomeEntered ?? _state.isHomeEntered,
        isImReady: true,
        isRecovering: false,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markSessionRefreshing({String? userId}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.sessionRefreshing,
        isBusinessAuthenticated:
            _state.isBusinessAuthenticated || _state.currentUserId != null,
        isHomeEntered: _state.isHomeEntered,
        isImReady: false,
        isRecovering: true,
        currentUserId: userId,
        lastError: null,
      ),
    );
  }

  void markSessionExpired({String? message}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.sessionExpired,
        isRecovering: false,
        isImReady: false,
        lastError: LoginError(
          type: LoginErrorType.sessionExpired,
          message: message,
        ),
      ),
    );
  }

  void markKickedOffline({String? message}) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.kickedOffline,
        isRecovering: false,
        isImReady: false,
        lastError: LoginError(
          type: LoginErrorType.kickedOffline,
          message: message,
        ),
      ),
    );
  }

  void markFailed(
    LoginErrorType type, {
    String? message,
    Object? cause,
    StackTrace? stackTrace,
    String? userId,
    bool? isBusinessAuthenticated,
    bool? isHomeEntered,
    bool? isImReady,
    bool? isRecovering,
  }) {
    _setState(
      _state.copyWith(
        phase: LoginPhase.failed,
        isBusinessAuthenticated:
            isBusinessAuthenticated ?? _state.isBusinessAuthenticated,
        isHomeEntered: isHomeEntered ?? _state.isHomeEntered,
        isImReady: isImReady ?? _state.isImReady,
        isRecovering: isRecovering ?? false,
        currentUserId: userId,
        lastError: LoginError(
          type: type,
          message: message,
          cause: cause,
          stackTrace: stackTrace,
        ),
      ),
    );
  }

  void _setState(LoginState next) {
    final changed = _state.phase != next.phase ||
        _state.isBusinessAuthenticated != next.isBusinessAuthenticated ||
        _state.isHomeEntered != next.isHomeEntered ||
        _state.isImReady != next.isImReady ||
        _state.isRecovering != next.isRecovering ||
        _state.currentUserId != next.currentUserId ||
        _state.lastError?.type != next.lastError?.type ||
        _state.lastError?.message != next.lastError?.message;
    if (!changed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  Future<void> _completeForegroundLoginAndEnterHome({
    required BuildContext context,
    String? nickname,
  }) async {
    _sessionLog('new SessionManager login start nickname=$nickname');
    _sessionLog(
      'SESSION_LOG PWD_LOGIN _completeForegroundLoginAndEnterHome START '
      'nickname=$nickname',
    );
    final token = ApiClient.instance.token;
    final userId = ApiClient.instance.authenticatedUserId;
    if (token == null || token.isEmpty || userId.isEmpty) {
      throw _handleFailure(LoginErrorType.restoreFailed, message: '登录凭证不存在');
    }
    await SessionManager.instance.establishFromSavedBusinessSession(
      token: token,
      userId: userId,
    );
    if (!context.mounted) {
      throw _handleFailure(
        LoginErrorType.restoreFailed,
        message: '登录页面已关闭，请重试',
      );
    }
    InitStep.directToHomePage(context);
    markImReady(isHomeEntered: true);
    _sessionLog(
      'new SessionManager login done',
    );
  }

  /// Web 冷启动：进首页后再补 listener / 列表 / 游戏会话态。
  Future<void> _finishWebColdStartBackground({
    required UserSigResult sig,
    required MeResult me,
  }) async {
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: sig.userId,
    );
    if (!AuthBootstrapService.instance.isCoreServicesUserReady()) {
      await AuthBootstrapService.instance.primeUIKitSession(sig);
    }
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    try {
      await PrivilegedGameUserService.instance.activateSession(
        userId: sig.userId,
      );
      await SangongMyConfigService.instance.activateSession(
        userId: sig.userId,
      );
    } catch (_) {}
    unawaited(
      ImChatNotificationClearService.instance.clearAllImChatNotifications(
        reason: 'cold_start_im_ready',
      ),
    );
  }

  LoginCoordinatorException _handleFailure(
    LoginErrorType type, {
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    markFailed(
      type,
      message: message,
      cause: error,
      stackTrace: stackTrace,
    );
    return LoginCoordinatorException(message);
  }

  Future<void> _clearSessionForLogout({required String reason}) async {
    await AccountSessionService.instance.clearForLogout(reason: reason);
  }

  bool _isSameUserId(String? left, String? right) {
    final a = left?.trim() ?? '';
    final b = right?.trim() ?? '';
    return a.isNotEmpty && b.isNotEmpty && a == b;
  }
}

class LoginCoordinatorException implements Exception {
  const LoginCoordinatorException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PasswordLoginCoordinatorResult {
  const PasswordLoginCoordinatorResult._({
    required this.requiresDeviceChallenge,
    this.challengeId,
    this.phone,
    this.phoneMasked,
  });

  const PasswordLoginCoordinatorResult.completed()
      : this._(requiresDeviceChallenge: false);

  const PasswordLoginCoordinatorResult.deviceChallenge({
    required String challengeId,
    required String phone,
    required String phoneMasked,
  }) : this._(
          requiresDeviceChallenge: true,
          challengeId: challengeId,
          phone: phone,
          phoneMasked: phoneMasked,
        );

  final bool requiresDeviceChallenge;
  final String? challengeId;
  final String? phone;
  final String? phoneMasked;
}

enum LoginRecoveryAction {
  goLogin,
  goHome,
  stayOnHome,
  restartColdStart,
}

class LoginRecoveryResult {
  const LoginRecoveryResult._({
    required this.action,
    this.userId,
    this.me,
  });

  const LoginRecoveryResult.goLogin()
      : this._(action: LoginRecoveryAction.goLogin);

  const LoginRecoveryResult.goHome({
    required String userId,
    required MeResult me,
  }) : this._(
          action: LoginRecoveryAction.goHome,
          userId: userId,
          me: me,
        );

  const LoginRecoveryResult.stayOnHome({required String userId})
      : this._(
          action: LoginRecoveryAction.stayOnHome,
          userId: userId,
        );

  const LoginRecoveryResult.restartColdStart()
      : this._(action: LoginRecoveryAction.restartColdStart);

  final LoginRecoveryAction action;
  final String? userId;
  final MeResult? me;
}
