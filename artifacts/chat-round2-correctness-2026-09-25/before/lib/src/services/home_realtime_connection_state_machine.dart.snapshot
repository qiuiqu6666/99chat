import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/platform/listener_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/session/auth_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

enum HomeRealtimeConnectionPhase {
  idle,
  starting,
  retrying,
  ready,
  failed,
  stopped,
}

class HomeRealtimeConnectionState {
  const HomeRealtimeConnectionState({
    required this.phase,
    this.identity,
    this.attempt = 0,
    this.error,
  });

  const HomeRealtimeConnectionState.idle()
      : this(phase: HomeRealtimeConnectionPhase.idle);

  final HomeRealtimeConnectionPhase phase;
  final SessionIdentity? identity;
  final int attempt;
  final Object? error;
}

/// Owns the post-frame realtime connection lifecycle independently from the
/// local conversation projection and the rest of HomeBootstrap.
///
/// A failed transport setup is retried in the background. A stale session or
/// terminal auth error stops the state machine without allowing a previous
/// account to install listeners for the next account.
class HomeRealtimeConnectionStateMachine {
  HomeRealtimeConnectionStateMachine._();

  static final instance = HomeRealtimeConnectionStateMachine._();

  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final ValueNotifier<HomeRealtimeConnectionState> state =
      ValueNotifier<HomeRealtimeConnectionState>(
    const HomeRealtimeConnectionState.idle(),
  );

  SessionIdentity? _identity;
  Future<void>? _attemptInFlight;
  Timer? _retryTimer;
  int _generation = 0;
  FutureOr<void> Function(SessionIdentity identity)? _onReady;
  bool _readyCallbackDelivered = false;

  bool get isRunning => _attemptInFlight != null || _retryTimer != null;

  bool isReadyFor(SessionIdentity identity) {
    final current = state.value;
    return current.phase == HomeRealtimeConnectionPhase.ready &&
        current.identity == identity;
  }

  /// Starts or joins the connection operation for [identity]. This method is
  /// deliberately non-blocking; callers must not await it on the home path.
  void start({
    required SessionIdentity identity,
    FutureOr<void> Function(SessionIdentity identity)? onReady,
  }) {
    if (identity.ownerUserId.isEmpty ||
        !SessionIdentityService.instance.isCurrent(identity)) {
      return;
    }
    _onReady = onReady;
    if (_identity == identity &&
        state.value.phase == HomeRealtimeConnectionPhase.ready) {
      if (!_readyCallbackDelivered && onReady != null) {
        _readyCallbackDelivered = true;
        unawaited(Future<void>.sync(() => onReady(identity)));
      }
      return;
    }
    if (_identity == identity && isRunning) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;
    final generation = ++_generation;
    _identity = identity;
    _readyCallbackDelivered = false;
    _scheduleAttempt(identity, generation, attempt: 0, delay: Duration.zero);
  }

  void reset({String reason = 'reset'}) {
    _generation++;
    // The old Future cannot be cancelled, but it is stale by generation and
    // must not prevent the next account from starting a fresh attempt.
    _attemptInFlight = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _identity = null;
    _onReady = null;
    _readyCallbackDelivered = false;
    _setState(
      const HomeRealtimeConnectionState(
        phase: HomeRealtimeConnectionPhase.stopped,
      ),
    );
    if (StartupPerfLog.consoleLoggingEnabled) {
      debugPrint('HomeRealtimeConnection: stopped reason=$reason');
    }
  }

  void _scheduleAttempt(
    SessionIdentity identity,
    int generation, {
    required int attempt,
    required Duration delay,
  }) {
    if (!_isCurrent(identity, generation)) return;
    if (delay <= Duration.zero) {
      unawaited(_attempt(identity, generation, attempt));
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_attempt(identity, generation, attempt));
    });
  }

  Future<void> _attempt(
    SessionIdentity identity,
    int generation,
    int attempt,
  ) async {
    if (!_isCurrent(identity, generation) || _attemptInFlight != null) return;
    _setState(
      HomeRealtimeConnectionState(
        phase: attempt == 0
            ? HomeRealtimeConnectionPhase.starting
            : HomeRealtimeConnectionPhase.retrying,
        identity: identity,
        attempt: attempt,
      ),
    );
    final startedAt = DateTime.now();
    late final Future<void> task;
    task = _attach(identity);
    _attemptInFlight = task;
    try {
      await task;
      if (!_isCurrent(identity, generation)) return;
      if (!ConversationSyncService.instance.isRealtimeActiveFor(identity)) {
        throw StateError('realtime bindings returned before becoming active');
      }
      await _waitForSocketHandshake(identity, generation);
      if (!_isCurrent(identity, generation)) return;
      _setState(
        HomeRealtimeConnectionState(
          phase: HomeRealtimeConnectionPhase.ready,
          identity: identity,
          attempt: attempt,
        ),
      );
      StartupPerfLog.markTagged(
        'home_realtime_ready',
        category: 'post_home',
        details: <String, Object>{
          'owner': identity.ownerUserId,
          'generation': identity.generation,
          'attempt': attempt,
          'socketReady': ImConnectStatusService.isSocketReady,
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!_readyCallbackDelivered) {
        _readyCallbackDelivered = true;
        final callback = _onReady;
        if (callback != null) {
          unawaited(Future<void>.sync(() => callback(identity)));
        }
      }
    } catch (error) {
      if (!_isCurrent(identity, generation)) return;
      StartupPerfLog.markTagged(
        'home_realtime_attempt_failed',
        category: 'post_home',
        details: <String, Object>{
          'attempt': attempt,
          'error': error.toString(),
          'socketConnected': ImConnectStatusService.socketConnectedThisLaunch,
          'handshakePending': ImConnectStatusService.isHandshakePending,
        },
      );
      if (_isTerminalAuthError(error)) {
        _setState(
          HomeRealtimeConnectionState(
            phase: HomeRealtimeConnectionPhase.failed,
            identity: identity,
            attempt: attempt,
            error: error,
          ),
        );
        return;
      }
      final nextAttempt = attempt + 1;
      _setState(
        HomeRealtimeConnectionState(
          phase: HomeRealtimeConnectionPhase.retrying,
          identity: identity,
          attempt: nextAttempt,
          error: error,
        ),
      );
      final delay =
          _retryDelays[(nextAttempt - 1).clamp(0, _retryDelays.length - 1)];
      _scheduleAttempt(
        identity,
        generation,
        attempt: nextAttempt,
        delay: delay,
      );
    } finally {
      if (identical(_attemptInFlight, task)) {
        _attemptInFlight = null;
      }
    }
  }

  Future<void> _attach(SessionIdentity identity) {
    return ListenerStore.attachRealtimeBindings(expectedIdentity: identity);
  }

  Future<void> _waitForSocketHandshake(
    SessionIdentity identity,
    int generation,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 13));
    while (_isCurrent(identity, generation) &&
        !ImConnectStatusService.isSocketReady &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!_isCurrent(identity, generation)) return;
    if (!ImConnectStatusService.isSocketReady) {
      StartupPerfLog.markTagged(
        'home_realtime_handshake_timeout',
        category: 'post_home',
        details: <String, Object>{
          'socketConnected': ImConnectStatusService.socketConnectedThisLaunch,
          'handshakePending': ImConnectStatusService.isHandshakePending,
        },
      );
      throw StateError('IM socket handshake not ready');
    }
  }

  bool _isCurrent(SessionIdentity identity, int generation) {
    return generation == _generation &&
        _identity == identity &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  bool _isTerminalAuthError(Object error) {
    if (error is SessionAuthExpiredException) return true;
    if (error is DioError) {
      return error.response?.statusCode == 401;
    }
    return false;
  }

  void _setState(HomeRealtimeConnectionState next) {
    state.value = next;
  }
}
