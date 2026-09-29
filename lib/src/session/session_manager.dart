import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'auth_repository.dart';
import 'im_client.dart';
import 'im_event_bridge.dart';
import 'session_state.dart';
import 'session_store.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_bootstrap_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/platform/listener_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_reconcile_service.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

class _SessionOperationSuperseded implements Exception {
  const _SessionOperationSuperseded();
}

class SessionManager extends ChangeNotifier {
  static final SessionManager instance = SessionManager();
  SessionManager({
    SessionStore? store,
    AuthRepository? auth,
    ImClient? im,
    this.restoreWaitBudget = const Duration(seconds: 8),
    this.imOperationWaitBudget = const Duration(seconds: 20),
    this.signOutWaitBudget = const Duration(seconds: 8),
    this.onSessionInvalidated,
  })  : _store = store ?? SessionStore(),
        _auth = auth ?? AuthRepository(),
        _im = im ?? ImClient() {
    _im.setEventBridge(ImEventBridge(
      onConnecting: () {
        // IM SDK 进入握手期：通知 UI 状态机，避免「真实状态已变但 UI 没变」。
        ImConnectStatusService.onSdkConnecting();
      },
      onConnected: () {
        // 修复标题 stuck failed：之前这个回调是空函数体，IM SDK
        // 真正连上后 ImConnectStatusService 不知道，标题一直停在 failed。
        ImConnectStatusService.markSocketConnected();
      },
      onDisconnected: (code, message) {
        // 先通知 UI 状态机，再走 SessionManager 自有的重连/状态变更逻辑。
        ImConnectStatusService.markSocketDisconnected();
        final userId = _state.userId;
        if (userId != null &&
            userId.isNotEmpty &&
            !_state.isLoggedOut &&
            !_signingOut) {
          _set(SessionState(
            phase: SessionPhase.offline,
            userId: userId,
            error: '$code: $message',
          ));
          scheduleReconnect(userId);
        }
      },
      onKickedOffline: () {
        if (_state.isLoggedOut || _signingOut) return;
        // A kick is an account/session terminal event, unlike a transport
        // disconnect. Clear the owner before any reconnect can be scheduled.
        unawaited(_handleSessionInvalidated(
          SessionInvalidationReason.kickedOffline,
        ));
      },
      onUserSigExpired: () {
        final userId = _state.userId;
        if (userId != null && userId.isNotEmpty) {
          unawaited(_refreshCredential(userId, reconnect: true));
        }
      },
    ));
  }

  final SessionStore _store;
  final AuthRepository _auth;
  final ImClient _im;
  final Duration restoreWaitBudget;
  final Duration imOperationWaitBudget;
  final Duration signOutWaitBudget;

  /// App-level cleanup, user feedback and navigation for terminal IM events.
  Future<void> Function(SessionInvalidationReason reason)? onSessionInvalidated;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  int _sessionGeneration = 0;
  Future<void>? _activeOperation;
  Future<void>? _credentialRefreshInFlight;
  Future<void> _imLoginTail = Future<void>.value();
  int _imLoginRevision = 0;
  int? _credentialRefreshGeneration;
  bool _credentialReconnectRequested = false;
  Future<void>? _signOutInFlight;
  Completer<void>? _invalidationDone;
  bool _signingOut = false;
  SessionState _state = const SessionState.unknown();

  SessionState get state => _state;

  /// Monotonic identity for the current login lifecycle. Consumers that
  /// schedule work after login must fence both userId and this generation;
  /// the same user can log out and log in again before an old Future settles.
  int get sessionGeneration => _sessionGeneration;

  bool get isOnline => _state.phase == SessionPhase.ready;

  Future<void> restore() async {
    await _waitForTeardown();
    final generation = _sessionGeneration;
    var active = _activeOperation;
    if (active == null) {
      late final Future<void> operation;
      operation =
          (_state.isReady ? _validateReadySession() : _restoreInternal())
              .whenComplete(() {
        if (identical(_activeOperation, operation)) _activeOperation = null;
      });
      _activeOperation = operation;
      active = operation;
    }
    // Budget only the UI wait. Keep the actual operation single-flight until
    // it settles: timeout cannot cancel an SDK login or suppress a late 401.
    await active.timeout(restoreWaitBudget, onTimeout: () {
      final storedOwner = _state.userId?.trim() ?? '';
      final fallbackOwner = ApiClient.instance.authenticatedUserId.trim();
      final owner = storedOwner.isNotEmpty ? storedOwner : fallbackOwner;
      final businessToken = ApiClient.instance.token;
      if (generation != _sessionGeneration ||
          _state.isLoggedOut ||
          _state.isReady ||
          owner.isEmpty ||
          !ApiClient.isValidJwt(businessToken)) {
        return;
      }
      // A slow secure-store read is not evidence that credentials are absent.
      // Keep a confirmed local business session in its account and let the
      // single-flight restore continue in the background.
      _set(SessionState(
          phase: SessionPhase.offline,
          userId: owner,
          error: TimeoutException('Session credentials are still restoring')));
    });
  }

  Future<void> _validateReadySession() async {
    final generation = _sessionGeneration;
    final owner = _state.userId;
    if (owner == null || owner.isEmpty) return;
    try {
      final token = await _store.readBusinessToken();
      if (generation != _sessionGeneration) return;
      if (ApiClient.isJwtExpired(token ?? ApiClient.instance.token)) {
        await _handleSessionInvalidated(
            SessionInvalidationReason.credentialsExpired);
        return;
      }
      final me = await _auth.fetchMe();
      if (generation != _sessionGeneration) return;
      if (me.userId != owner) throw const SessionAuthExpiredException();
    } on SessionAuthExpiredException {
      if (generation == _sessionGeneration) {
        await _handleSessionInvalidated(
            SessionInvalidationReason.credentialsExpired);
      }
    } catch (_) {
      // A business health probe cannot invalidate an otherwise connected SDK.
      // SDK disconnection remains the owner of transport recovery.
    }
  }

  Future<void> _connectIm(
      {required String userId,
      required int sdkAppId,
      required String userSig,
      required int generation}) {
    final previous = _imLoginTail;
    final operation = () async {
      await previous;
      if (generation != _sessionGeneration || _signingOut) {
        throw const _SessionOperationSuperseded();
      }
      final watch = Stopwatch()..start();
      StartupPerfLog.markTagged('im_login_start',
          category: 'session',
          details: {'generation': generation, 'active': 1});
      try {
        await _im.initialize(sdkAppId);
        if (generation != _sessionGeneration || _signingOut) {
          throw const _SessionOperationSuperseded();
        }
        await _im.connect(userId: userId, userSig: userSig);
        if (generation != _sessionGeneration || _signingOut) {
          throw const _SessionOperationSuperseded();
        }
        _imLoginRevision++;
      } finally {
        StartupPerfLog.markTagged('im_login_end',
            category: 'session',
            details: {
              'generation': generation,
              'elapsedMs': watch.elapsedMilliseconds,
              'active': 0
            });
      }
    }();
    // Errors reach the caller; the physical SDK lane itself remains usable.
    _imLoginTail =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    // Bound the caller's wait without replacing the physical SDK lane. A
    // timeout cannot cancel the native login, so logout and later logins must
    // still serialize behind [operation] until it really settles.
    return operation.timeout(imOperationWaitBudget);
  }

  Future<void> _restoreInternal() async {
    final generation = _sessionGeneration;
    final token = await _store.readBusinessToken();
    final userId = await _store.readUserId();
    if (generation != _sessionGeneration) return;
    // 迁移期兼容旧 ApiClient 的凭证存储；成功建立新 Session 后会写入新 Store。
    final effectiveToken = token ?? ApiClient.instance.token;
    final effectiveUserId = userId ?? ApiClient.instance.authenticatedUserId;
    if (effectiveToken == null ||
        effectiveToken.isEmpty ||
        effectiveUserId.isEmpty) {
      _set(const SessionState(phase: SessionPhase.loggedOut));
      return;
    }
    if (ApiClient.isJwtExpired(effectiveToken)) {
      await _handleSessionInvalidated(
        SessionInvalidationReason.credentialsExpired,
      );
      return;
    }
    await _store.saveBusinessSession(
      token: effectiveToken,
      userId: effectiveUserId,
    );
    if (generation != _sessionGeneration) return;
    _set(SessionState(phase: SessionPhase.restoring, userId: effectiveUserId));
    final cached = await _store.readImCredential();
    if (cached != null) {
      // The IM credential is not proof that the business session is still
      // valid. Validate the business owner before initializing the SDK so a
      // revoked account cannot enter the offline home through a cached
      // UserSig. A transport failure is intentionally different: when the
      // auth service is unreachable, a still-valid local session may restore
      // its local IM cache and reconnect in the background.
      var businessSessionValidated = false;
      try {
        final me = await _auth.fetchMe();
        if (generation != _sessionGeneration) return;
        if (me.userId != effectiveUserId) {
          throw const SessionAuthExpiredException();
        }
        businessSessionValidated = true;
      } on SessionAuthExpiredException {
        if (generation == _sessionGeneration) {
          await _handleSessionInvalidated(
            SessionInvalidationReason.credentialsExpired,
          );
        }
        return;
      } catch (_) {
        // No response/auth failure means transport is unavailable. Preserve
        // the local-first behavior, but the state remains fenced by the
        // current generation and the normal reconnect path will retry auth.
      }
      if (generation != _sessionGeneration) return;
      try {
        _set(SessionState(
            phase: SessionPhase.connectingIm, userId: effectiveUserId));
        await _connectIm(
            userId: effectiveUserId,
            sdkAppId: cached.$1,
            userSig: cached.$2,
            generation: generation);
        if (generation != _sessionGeneration) return;
        _retryTimer?.cancel();
        _retryAttempt = 0;
        _set(SessionState(phase: SessionPhase.ready, userId: effectiveUserId));
        // IMP(M.1): IM 登录成功后立刻配置 IM06 scope。
        // 修复：之前冷启动 IM 登录走的是 SessionManager → ImClient.connect
        // 直接调用 TencentImSDKPlugin.v2TIMManager.login，绕过了
        // AuthBootstrapService.primeUIKitSession，导致 configureMessageWriterScope
        // 永远未被调用、im06ScopeConfigured 永远 false、聊天页云端历史
        // IM06 永远 scope_not_configured。
        // 幂等安全：configureMessageWriterScopeForSession 内部已对重复调用
        // 做了 owner/generation 校验，并捕获所有异常不影响主流程。
        _configureIm06ScopeAfterImLogin(
          ownerUserId: effectiveUserId,
          sessionGeneration: generation,
        );
        _startAccountRealtime(ownerUserId: effectiveUserId);
        // 缓存可用时不阻塞首屏，后台刷新下一张 UserSig。
        unawaited(_refreshCredential(effectiveUserId));
        return;
      } catch (_) {
        // 缓存连接失败，继续走一次在线凭证获取。
      }
      // If business auth was confirmed, _establish only needs to refresh the
      // IM credential. Keeping this branch explicit documents that a cached
      // UserSig failure must not be treated as a business logout.
      if (businessSessionValidated) {
        await _establish(userId: effectiveUserId, generation: generation);
        return;
      }
    }
    await _establish(userId: effectiveUserId, generation: generation);
  }

  Future<void> establishFromSavedBusinessSession({
    required String token,
    required String userId,
  }) async {
    await _waitForTeardown();
    _cancelReconnect();
    final generation = ++_sessionGeneration;
    final previous = _activeOperation;
    final operation = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      if (generation != _sessionGeneration) return;
      await _store.saveBusinessSession(token: token, userId: userId);
      if (generation != _sessionGeneration) return;
      await _establish(userId: userId, generation: generation);
    }();
    _activeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    }
  }

  Future<void> _establish({
    required String userId,
    required int generation,
  }) async {
    try {
      if (generation != _sessionGeneration) return;
      _set(SessionState(phase: SessionPhase.restoring, userId: userId));
      final results =
          await Future.wait([_auth.fetchMe(), _auth.fetchImCredential()]);
      if (generation != _sessionGeneration) return;
      final me = results[0] as MeResult;
      final sig = results[1] as UserSigResult;
      if (me.userId != userId ||
          sig.userId != userId ||
          me.userId != sig.userId) {
        throw StateError('业务用户与 IM 用户不一致');
      }
      _set(
          SessionState(phase: SessionPhase.initializingIm, userId: sig.userId));
      await _store.saveImCredential(
        sdkAppId: sig.sdkAppId,
        userSig: sig.userSig,
        expiresIn: sig.expiresIn,
      );
      if (generation != _sessionGeneration) return;
      _set(SessionState(phase: SessionPhase.connectingIm, userId: sig.userId));
      await _connectIm(
          userId: sig.userId,
          sdkAppId: sig.sdkAppId,
          userSig: sig.userSig,
          generation: generation);
      if (generation != _sessionGeneration) return;
      _retryTimer?.cancel();
      _retryAttempt = 0;
      _set(SessionState(phase: SessionPhase.ready, userId: sig.userId));
      // IMP(M.2): 同上 — _establish 路径 IM 登录成功后配置 IM06 scope。
      _configureIm06ScopeAfterImLogin(
        ownerUserId: sig.userId,
        sessionGeneration: generation,
      );
      _startAccountRealtime(ownerUserId: sig.userId);
    } catch (error) {
      if ((error is SessionAuthExpiredException ||
              error is ImClientException && error.isCredentialRejected) &&
          generation == _sessionGeneration) {
        await _handleSessionInvalidated(
          SessionInvalidationReason.credentialsExpired,
        );
        return;
      }
      if (generation == _sessionGeneration) {
        _set(SessionState(
            phase: SessionPhase.offline, userId: userId, error: error));
        scheduleReconnect(userId);
      }
    }
  }

  Future<void> _refreshCredential(String userId, {bool reconnect = false}) {
    final running = _credentialRefreshInFlight;
    if (running != null && _credentialRefreshGeneration == _sessionGeneration) {
      _credentialReconnectRequested |= reconnect;
      return running;
    }
    _credentialRefreshGeneration = _sessionGeneration;
    _credentialReconnectRequested = reconnect;
    late final Future<void> operation;
    operation = _refreshCredentialInternal(userId).whenComplete(() {
      if (identical(_credentialRefreshInFlight, operation)) {
        _credentialRefreshInFlight = null;
        _credentialRefreshGeneration = null;
      }
    });
    _credentialRefreshInFlight = operation;
    return operation;
  }

  Future<void> _refreshCredentialInternal(String userId) async {
    final generation = _sessionGeneration;
    final loginRevision = _imLoginRevision;
    try {
      final sig = await _auth.fetchImCredential();
      if (generation != _sessionGeneration ||
          sig.userId != userId ||
          loginRevision != _imLoginRevision) {
        return;
      }
      await _store.saveImCredential(
        sdkAppId: sig.sdkAppId,
        userSig: sig.userSig,
        expiresIn: sig.expiresIn,
      );
      if (generation != _sessionGeneration) return;
      if (_credentialReconnectRequested &&
          generation == _sessionGeneration &&
          _state.isReady &&
          _state.userId == userId) {
        // Wait for/occupy the same operation slot as foreground and retry.
        // A cache refresh may be promoted by an expiration callback mid-flight.
        while (_activeOperation != null &&
            !identical(_activeOperation, _credentialRefreshInFlight)) {
          try {
            await _activeOperation;
          } catch (_) {}
          if (generation != _sessionGeneration ||
              loginRevision != _imLoginRevision) {
            return;
          }
        }
        final ownOperation = _credentialRefreshInFlight;
        _activeOperation = ownOperation;
        try {
          await _connectIm(
              userId: sig.userId,
              sdkAppId: sig.sdkAppId,
              userSig: sig.userSig,
              generation: generation);
        } finally {
          if (identical(_activeOperation, ownOperation)) {
            _activeOperation = null;
          }
        }
        // IMP(M.3): UserSig 刷新后的重新登录同样需要配置 IM06 scope。
        // 幂等安全：configureMessageWriterScopeForSession 对相同
        // owner/generation 不重置 coordinator。
        if (generation == _sessionGeneration) {
          _configureIm06ScopeAfterImLogin(
            ownerUserId: sig.userId,
            sessionGeneration: generation,
          );
        }
      }
    } on SessionAuthExpiredException {
      if (generation == _sessionGeneration &&
          loginRevision == _imLoginRevision) {
        await _handleSessionInvalidated(
          SessionInvalidationReason.credentialsExpired,
        );
      }
    } catch (error) {
      if (generation != _sessionGeneration ||
          _state.userId != userId ||
          loginRevision != _imLoginRevision) {
        return;
      }
      if (error is ImClientException && error.isCredentialRejected) {
        await _handleSessionInvalidated(
          SessionInvalidationReason.credentialsExpired,
        );
        return;
      }
      if (!_credentialReconnectRequested && _state.isReady) return;
      _set(SessionState(
        phase: SessionPhase.offline,
        userId: userId,
        error: error,
      ));
      scheduleReconnect(userId);
    }
  }

  Future<void> _reconnect(String userId) async {
    // A UI timeout must not create overlapping authentication/SDK logins.
    final running = _activeOperation;
    if (running != null) {
      await running;
      if (!_state.isReady && !_state.isLoggedOut && _state.userId == userId) {
        scheduleReconnect(userId);
      }
      return;
    }
    final generation = _sessionGeneration;
    if (_state.isLoggedOut || _state.userId != userId) return;
    late final Future<void> operation;
    operation =
        _establish(userId: userId, generation: generation).whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
    _activeOperation = operation;
    await operation;
  }

  void scheduleReconnect(String userId) {
    if (_retryTimer != null) return;
    final generation = _sessionGeneration;
    const delays = [2, 5, 15, 30];
    final delay = delays[_retryAttempt.clamp(0, delays.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: delay), () {
      _retryTimer = null;
      if (generation != _sessionGeneration ||
          _state.isLoggedOut ||
          _state.userId != userId) {
        return;
      }
      unawaited(_reconnect(userId));
    });
  }

  void _cancelReconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  Future<void> _handleSessionInvalidated(
    SessionInvalidationReason reason,
  ) async {
    if (_state.isLoggedOut || _signingOut) return;
    final invalidation = Completer<void>();
    _invalidationDone = invalidation;
    // Fence in-flight refresh/login work before awaiting account cleanup.
    _sessionGeneration++;
    _activeOperation = null;
    _cancelReconnect();
    _signingOut = true;
    _set(const SessionState(phase: SessionPhase.loggedOut));
    try {
      final handler = onSessionInvalidated;
      if (handler != null) {
        await handler(reason);
      } else {
        await signOut(reason: reason.name);
      }
    } catch (error) {
      // SDK callbacks have no awaiting caller. The app handler still presents
      // the login route in its finally block if teardown reports a failure.
      debugPrint(
          '[SessionManager] session invalidation cleanup failed: $error');
    } finally {
      _signingOut = false;
      if (identical(_invalidationDone, invalidation)) _invalidationDone = null;
      invalidation.complete();
    }
  }

  Future<void> _waitForTeardown() async {
    // New credentials must not be written before the old owner's cleanup.
    // Never use _activeOperation here: invalidation can originate inside it.
    while (_invalidationDone != null || _signOutInFlight != null) {
      final pending = _invalidationDone?.future ?? _signOutInFlight!;
      await pending;
    }
  }

  Future<void> signOut({
    bool invalidateIdentity = true,
    String reason = 'sign_out',
  }) {
    final running = _signOutInFlight;
    if (running != null) return running;
    _sessionGeneration++;
    // SessionManager is also used by the cold-start/foreground path directly,
    // without AccountSessionService. Keep the process-wide identity fence in
    // sync for those terminal events (especially a direct SDK kick).
    if (invalidateIdentity) {
      SessionIdentityService.instance.invalidate(reason: reason);
      ImSdkRelationshipReconcileService.instance.onSessionInvalidated();
    }
    _activeOperation = null;
    _cancelReconnect();
    _signingOut = true;
    _set(const SessionState(phase: SessionPhase.loggedOut));
    final previousLogin = _imLoginTail;
    final completion = Completer<void>();
    _signOutInFlight = completion.future;
    // Clear credentials immediately, independently from an SDK login that may
    // never return. The physical teardown must not clear them again later, or
    // a newly established account could lose its credentials after a timeout.
    final storeClear = _store.clear();
    final teardown = () async {
      try {
        await previousLogin;
        try {
          await _im.disconnect();
        } finally {
          await _im.dispose();
        }
      } finally {
        _signingOut = false;
      }
    }();
    _imLoginTail =
        teardown.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    final boundedCleanup = () async {
      // Do not let a hung native login block logout navigation indefinitely.
      // The actual teardown remains the tail above, so a future login cannot
      // overlap the still-running native operation.
      await storeClear;
      try {
        await teardown.timeout(signOutWaitBudget);
      } on TimeoutException {
        _signingOut = false;
      }
    }();
    boundedCleanup.then((_) {
      if (identical(_signOutInFlight, completion.future)) {
        _signOutInFlight = null;
      }
      completion.complete();
    }, onError: (Object error, StackTrace stack) {
      _signingOut = false;
      if (identical(_signOutInFlight, completion.future)) {
        _signOutInFlight = null;
      }
      completion.completeError(error, stack);
    });
    return completion.future;
  }

  void _set(SessionState value) {
    _state = value;
    notifyListeners();
  }

  /// IMP(M): IM 登录成功后配置 IM06 协调器的 owner/generation。
  ///
  /// 必须在 [ImClient.connect] 成功之后调用，保证聊天页 chatOpen
  /// 阶段 [MessageReconciliationWriter] 已就绪 scope，云端历史 IM06
  /// 路径才能命中。
  ///
  /// 幂等性：`configureMessageWriterScopeForSession` 内部对 owner 与
  /// generation 做相等性检查，相同入参不会触发 coordinator 重置；调用
  /// 本身使用 try/catch 保护，失败也不影响 IM 登录主流程。
  /// IM login 成功即可装轻量监听。不等 HomePage，冷启恢复同样适用。
  void _startAccountRealtime({required String ownerUserId}) {
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: ownerUserId,
    );
    if (identity.ownerUserId.isEmpty) {
      return;
    }
    // Attach only when the business owner is already installed. This matches
    // the account fence used by ListenerStore and avoids TIMUIKitCore init
    // during unit tests or mid-handoff. HomeBootstrap still joins later.
    final currentOwner = ChatIdFormat.rawUserUid(
      ApiClient.instance.authenticatedUserId,
    );
    if (currentOwner.isEmpty || currentOwner != identity.ownerUserId) {
      return;
    }
    unawaited(() async {
      try {
        await ListenerStore.attachRealtimeBindings(
          expectedIdentity: identity,
        );
        ImSdkRelationshipReconcileService.instance.onImLoginSuccess();
      } catch (error) {
        if (kDebugMode) {
          debugPrint('SessionManager: attach realtime failed: $error');
        }
      }
    }());
  }

  void _configureIm06ScopeAfterImLogin({
    required String ownerUserId,
    required int sessionGeneration,
  }) {
    // 延迟到下一 microtask，避开 IM SDK 同步 connect 的回调栈，
    // 避免与同一帧内 IM 事件回调形成 race。
    Future<void>.microtask(() {
      try {
        AuthBootstrapService.instance.configureMessageWriterScopeForSession(
          ownerUserId: ownerUserId,
          accountGeneration: sessionGeneration,
        );
      } catch (e) {
        // 不影响主流程；chat 页打开时仍有 fallback 补配置的机会。
        // ignore: avoid_print
        print(
          '[SessionManager] configureIm06Scope failed owner=$ownerUserId '
          'gen=$sessionGeneration err=$e',
        );
      }
    });
  }
}
