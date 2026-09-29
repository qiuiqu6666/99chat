import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_session_guard.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_admin_realtime_state.dart';
import 'package:tencent_cloud_chat_demo/src/utils/sangong_sse_parser.dart';

/// 三公管理端实时状态：快照 + SSE 推送。
class SangongAdminRealtimeService with WidgetsBindingObserver {
  SangongAdminRealtimeService._();

  static final SangongAdminRealtimeService instance =
      SangongAdminRealtimeService._();

  static const List<Duration> _reconnectBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final StreamController<SangongAdminRealtimeState> _statesController =
      StreamController<SangongAdminRealtimeState>.broadcast();

  SangongAdminRealtimeState? _latestState;
  int _listeners = 0;
  bool _starting = false;
  bool _foreground = true;
  int _generation = 0;
  int _connectionSequence = 0;
  int _stateRevision = 0;
  Future<void>? _snapshotInFlight;
  int _reconnectAttempt = 0;
  CancelToken? _streamCancelToken;
  StreamSubscription<String>? _streamSubscription;
  Timer? _reconnectTimer;
  Timer? _recoveryTimer;
  Timer? _streamIdleTimer;
  VoidCallback? _tenantListener;
  final SangongSseParser _sseParser = SangongSseParser();

  Stream<SangongAdminRealtimeState> get states => _statesController.stream;

  SangongAdminRealtimeState? get latestState => _latestState;

  bool get isActive => _listeners > 0;

  void acquire() {
    _listeners++;
    _log('acquire listeners=$_listeners tenant=${SangongGameHttp.tenantId} '
        'canCall=${SangongGameHttp.canCallAdmin}');
    if (_listeners == 1) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
      WidgetsBinding.instance.addObserver(this);
      _tenantListener ??= () {
        _onTenantChanged();
      };
      SangongGameHttp.tenantIdListenable.addListener(_tenantListener!);
      unawaited(_start());
    }
  }

  void release() {
    if (_listeners <= 0) {
      return;
    }
    _listeners--;
    _log('release listeners=$_listeners');
    if (_listeners <= 0) {
      _listeners = 0;
      WidgetsBinding.instance.removeObserver(this);
      if (_tenantListener != null) {
        SangongGameHttp.tenantIdListenable.removeListener(_tenantListener!);
      }
      _stop();
      _latestState = null;
    }
  }

  void _onTenantChanged() {
    if (_listeners <= 0) {
      return;
    }
    _stop();
    _latestState = null;
    _reconnectAttempt = 0;
    unawaited(_start());
  }

  Future<void> refreshSnapshot() {
    if (!_canRun) return Future<void>.value();
    final active = _snapshotInFlight;
    if (active != null) return active;
    late final Future<void> task;
    task = _fetchSnapshot().whenComplete(() {
      if (identical(_snapshotInFlight, task)) _snapshotInFlight = null;
    });
    _snapshotInFlight = task;
    return task;
  }

  bool get _canRun =>
      _listeners > 0 && _foreground && SangongGameHttp.canCallAdmin;

  Future<void> _fetchSnapshot() async {
    final generation = _generation;
    final tenant = SangongGameHttp.tenantId;
    final session = AgentSessionSnapshot();
    final revision = _stateRevision;
    try {
      _log('snapshot request tenant=${SangongGameHttp.tenantId}');
      final state = await SangongAdminApi.instance.fetchEventsSnapshot();
      if (!_canRun ||
          generation != _generation ||
          !session.isCurrent ||
          tenant != SangongGameHttp.tenantId) {
        return;
      }
      // SSE can overtake HTTP. Unknown/equal/older versions must not roll it back.
      if (revision != _stateRevision &&
          (state.version <= 0 || state.version <= (_latestState?.version ?? 0))) {
        return;
      }
      _log('snapshot received version=${state.version} status=${state.status}');
      _emit(state);
    } catch (error) {
      _log('snapshot refresh failed: $error');
    }
  }

  void _emit(SangongAdminRealtimeState state) {
    _latestState = state;
    _stateRevision++;
    _armRecovery();
    if (!_statesController.isClosed) {
      _statesController.add(state);
    }
  }

  Future<void> _start() async {
    if (_starting || !_canRun) {
      return;
    }
    _starting = true;
    final generation = _generation;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _armRecovery();
    try {
      // Recover missed state on every reconnect; a slow snapshot cannot block SSE.
      await Future.wait([refreshSnapshot(), _connectStream()]);
    } finally {
      if (generation == _generation) {
        _starting = false;
        // A retry timer may have fired while the initial snapshot was pending.
        if (_canRun && _streamSubscription == null) _scheduleReconnect();
      }
    }
  }

  void _stop() {
    _generation++;
    _connectionSequence++;
    _starting = false;
    _snapshotInFlight = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _streamIdleTimer?.cancel();
    _streamIdleTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamCancelToken?.cancel('realtime stopped');
    _streamCancelToken = null;
    _sseParser.reset();
  }

  Future<void> _connectStream() async {
    if (!_canRun) {
      return;
    }
    final generation = _generation;
    final sequence = ++_connectionSequence;
    final session = AgentSessionSnapshot();
    final tenant = SangongGameHttp.tenantId;
    bool current() =>
        _canRun &&
        generation == _generation &&
        sequence == _connectionSequence &&
        session.isCurrent &&
        tenant == SangongGameHttp.tenantId;
    // Cancelling an idle HTTP body may wait for transport cleanup. Invalidate
    // its callbacks and close the request without blocking the replacement.
    final previousSubscription = _streamSubscription;
    _streamSubscription = null;
    _streamCancelToken?.cancel('reconnect');
    unawaited(previousSubscription?.cancel());
    _sseParser.reset();
    _streamCancelToken = CancelToken();
    final cancelToken = _streamCancelToken!;

    try {
      final response = await SangongGameHttp.adminClient
          .get<ResponseBody>(
            '/api/v1/admin/events/stream',
            options: Options(
              headers: const {
                'Accept': 'text/event-stream',
                'Cache-Control': 'no-cache',
              },
              responseType: ResponseType.stream,
              receiveTimeout: 0,
            ),
            cancelToken: cancelToken,
          )
          .timeout(const Duration(seconds: 20));
      final body = response.data;
      if (!current()) {
        cancelToken.cancel('stale connection');
        return;
      }
      _log('stream connected status=${response.statusCode} '
          'contentType=${response.headers.value(Headers.contentTypeHeader)} '
          'tenant=${SangongGameHttp.tenantId}');
      if (body == null) {
        _scheduleReconnect();
        return;
      }
      _reconnectAttempt = 0;
      _armStreamIdleRecovery();
      // SSE data may split a UTF-8 multibyte character across network chunks.
      // A streaming decoder preserves the partial bytes between chunks;
      // decoding every chunk independently can terminate delivery on Chinese
      // names or status text split at a packet boundary.
      _streamSubscription = body.stream
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .listen(
        (chunk) {
          if (!current()) return;
          _armStreamIdleRecovery();
          _sseParser.feed(chunk, _onSseEvent);
        },
        onError: (Object error) {
          if (!current()) return;
          _streamSubscription = null;
          _log('stream error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          if (!current()) return;
          _streamSubscription = null;
          _log('stream closed');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } on DioError catch (error) {
      if (CancelToken.isCancel(error) || !current()) {
        return;
      }
      _log('stream connect failed: $error');
      _scheduleReconnect();
    } catch (error) {
      if (!current()) return;
      cancelToken.cancel('stream setup failed');
      _log('stream connect failed: $error');
      _scheduleReconnect();
    }
  }

  void _onSseEvent(String event, String data) {
    if (event != 'state' && event != 'message') {
      return;
    }
    final state = SangongAdminRealtimeState.tryParseEventData(data);
    if (state != null) {
      _log('event received name=$event version=${state.version} '
          'status=${state.status}');
      _emit(state);
    } else {
      _log('event parse failed name=$event bytes=${data.length}');
    }
  }

  void _scheduleReconnect() {
    if (!_canRun || _reconnectTimer != null) {
      return;
    }
    final index = _reconnectAttempt.clamp(0, _reconnectBackoff.length - 1);
    final delay = _reconnectBackoff[index];
    if (_reconnectAttempt < _reconnectBackoff.length - 1) {
      _reconnectAttempt++;
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_canRun) {
        unawaited(_start());
      }
    });
  }

  // Healthy state pushes reset this timer. A quiet/broken stream still gets a
  // snapshot every 15 seconds while the foreground has a subscriber.
  void _armRecovery() {
    _recoveryTimer?.cancel();
    if (!_canRun) return;
    _recoveryTimer = Timer(const Duration(seconds: 15), () {
      if (!_canRun) return;
      unawaited(refreshSnapshot());
      _armRecovery();
    });
  }

  void _armStreamIdleRecovery() {
    _streamIdleTimer?.cancel();
    if (!_canRun) return;
    _streamIdleTimer = Timer(const Duration(seconds: 45), () {
      if (_canRun) unawaited(_start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _stop();
    if (foreground && _listeners > 0) unawaited(_start());
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[SangongRealtime] $message');
    }
  }
}
