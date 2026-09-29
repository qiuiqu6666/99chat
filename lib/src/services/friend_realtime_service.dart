import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_connection.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_endpoint.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/presence_last_seen_codec.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

typedef FriendRealtimeEventHandler = void Function(FriendRealtimeEvent event);
typedef FriendRealtimeAuthOkHandler = void Function();
typedef FriendRealtimeReadyHandler = void Function(bool ready);

class FriendRealtimeService {
  FriendRealtimeService._({
    this.authenticationTimeout = const Duration(seconds: 10),
    this.heartbeatTimeout = const Duration(seconds: 15),
    this.presenceRequestTimeout = const Duration(seconds: 12),
    this.endpointOverride,
  });

  @visibleForTesting
  factory FriendRealtimeService.forTesting(
          {required String endpoint,
          Duration authenticationTimeout = const Duration(seconds: 10),
          Duration heartbeatTimeout = const Duration(seconds: 15),
          Duration presenceRequestTimeout = const Duration(seconds: 12)}) =>
      FriendRealtimeService._(
          endpointOverride: endpoint,
          authenticationTimeout: authenticationTimeout,
          heartbeatTimeout: heartbeatTimeout,
          presenceRequestTimeout: presenceRequestTimeout);

  final Duration authenticationTimeout;
  final Duration heartbeatTimeout;
  final Duration presenceRequestTimeout;
  final String? endpointOverride;

  static final FriendRealtimeService instance = FriendRealtimeService._();

  FriendRealtimeEventHandler? onEvent;
  FriendRealtimeAuthOkHandler? onAuthOk;
  final List<FriendRealtimeAuthOkHandler> _authOkListeners =
      <FriendRealtimeAuthOkHandler>[];
  final List<FriendRealtimeReadyHandler> _readyListeners =
      <FriendRealtimeReadyHandler>[];

  FriendRealtimeConnection? _connection;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _deadlineTimer;
  bool _foreground = true;
  int? _rejectedCredentialGeneration;
  int? _connectionCredentialGeneration;
  Future<void>? _connectInFlight;
  bool _forceConnectPending = false;
  bool _running = false;
  bool _authFailed = false;
  bool _authOk = false;
  bool _lastEmittedReady = false;
  int _reconnectAttempt = 0;
  int _connectGeneration = 0;
  int _lastSeenSeq = 0;
  final Map<String, Completer<PresenceLastSeenBatch>> _lastSeenWaiters =
      <String, Completer<PresenceLastSeenBatch>>{};
  final Map<String, List<String>> _lastSeenUserIds = <String, List<String>>{};
  final Map<String, Timer> _lastSeenTimeouts = <String, Timer>{};
  final List<_QueuedPresenceLastSeen> _lastSeenQueue =
      <_QueuedPresenceLastSeen>[];
  final Map<Completer<PresenceLastSeenBatch>, _QueuedPresenceLastSeen>
      _lastSeenOperations = {};

  static const Duration _lastSeenTimeout = Duration(seconds: 8);
  static const Duration _internalRetryDelay = Duration(milliseconds: 300);

  /// TCP 已认证且连接仍在；好友申请轮询在此为 true 时应跳过。
  bool get isRealtimeReady =>
      _running && _authOk && !_authFailed && _connection != null;

  void addAuthOkListener(FriendRealtimeAuthOkHandler listener) {
    if (!_authOkListeners.contains(listener)) {
      _authOkListeners.add(listener);
    }
  }

  void removeAuthOkListener(FriendRealtimeAuthOkHandler listener) {
    _authOkListeners.remove(listener);
  }

  void addReadyListener(FriendRealtimeReadyHandler listener) {
    if (!_readyListeners.contains(listener)) {
      _readyListeners.add(listener);
    }
  }

  void removeReadyListener(FriendRealtimeReadyHandler listener) {
    _readyListeners.remove(listener);
  }

  void _emitAuthOk() {
    onAuthOk?.call();
    for (final listener in List<FriendRealtimeAuthOkHandler>.from(
      _authOkListeners,
    )) {
      listener();
    }
  }

  void _emitReadyIfChanged() {
    final ready = isRealtimeReady;
    if (ready == _lastEmittedReady) {
      return;
    }
    _lastEmittedReady = ready;
    for (final listener in List<FriendRealtimeReadyHandler>.from(
      _readyListeners,
    )) {
      listener(ready);
    }
  }

  static const bool _logEnabled = kDebugMode;

  static void _log(String message) {
    if (!_logEnabled) return;
    debugPrint('FriendRealtime: $message');
  }

  void start() {
    final wasRunning = _running;
    _running = true;
    if (!wasRunning) {
      _reconnectAttempt = 0;
    }
    _log('start wasRunning=$wasRunning authFailed=$_authFailed');
    unawaited(ensureConnected(force: true));
  }

  Future<void> ensureConnected({bool force = false}) async {
    if (!_running) {
      _log('ensureConnected skipped: not running');
      return;
    }
    if (_authFailed &&
        _rejectedCredentialGeneration !=
            ApiClient.instance.credentialGeneration) {
      _authFailed = false;
      _rejectedCredentialGeneration = null;
    }
    if (_authFailed) {
      _log('ensureConnected skipped authFailed=$_authFailed');
      return;
    }
    if (!force && _connection != null) {
      return;
    }
    if (_connectInFlight != null) {
      _forceConnectPending |= force;
      await _connectInFlight;
      return;
    }
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connect();
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    if (!_running) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _deadlineTimer?.cancel();
        _deadlineTimer = null;
        _log('background: keep realtime tcp connected');
        unawaited(ensureConnected());
        return;
      case AppLifecycleState.resumed:
        _foreground = true;
        if (isRealtimeReady) {
          unawaited(_sendPing());
        } else if (_connection != null) {
          _armDeadline(_connection!, _connectGeneration, authenticationTimeout);
        }
        _log('foreground: ensure realtime tcp connected');
        unawaited(ensureConnected(force: _connection == null));
        return;
      default:
        return;
    }
  }

  Future<void> stop() async {
    _log('stop: disconnect realtime tcp');
    _running = false;
    _authFailed = false;
    _rejectedCredentialGeneration = null;
    _authOk = false;
    _reconnectAttempt = 0;
    _connectGeneration++;
    _forceConnectPending = false;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failAllLastSeen(PresenceLastSeenFailCode.disconnected);
    final connection = _connection;
    _connection = null;
    _emitReadyIfChanged();
    if (connection != null) {
      await connection.close();
    }
    _log('stop: realtime tcp disconnected');
  }

  Future<void> _connect() {
    final running = _connectInFlight;
    if (running != null) return running;
    late final Future<void> operation;
    operation = _connectInternal().whenComplete(() {
      if (!identical(_connectInFlight, operation)) return;
      _connectInFlight = null;
      final force = _forceConnectPending;
      _forceConnectPending = false;
      if (force && _running) unawaited(ensureConnected(force: true));
    });
    _connectInFlight = operation;
    return operation;
  }

  Future<void> _connectInternal() async {
    if (!_running || _authFailed) {
      return;
    }
    _authOk = false;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _emitReadyIfChanged();
    final connectGeneration = ++_connectGeneration;
    _failAllLastSeen(PresenceLastSeenFailCode.disconnected);
    final token = ApiClient.instance.token;
    final credentialGeneration = ApiClient.instance.credentialGeneration;
    if (!ApiClient.isValidJwt(token)) {
      _scheduleReconnect();
      return;
    }

    final tcpBase = endpointOverride ??
        (ApiNodeService.instance.isHydrated
            ? ApiNodeService.instance.currentRealtimeTcpBase
            : IMDemoConfig.realtimeTcpBase);
    final endpoint = FriendRealtimeEndpoint.parse(tcpBase);
    if (endpoint == null) {
      _scheduleReconnect();
      return;
    }

    await _connection?.close();
    if (!_running || connectGeneration != _connectGeneration) return;
    late final FriendRealtimeConnection connection;
    connection = FriendRealtimeConnection(
      onLine: (line) => _handleLine(
        line,
        connection: connection,
        connectGeneration: connectGeneration,
      ),
      onDisconnected: () => _handleDisconnected(
        connection: connection,
        connectGeneration: connectGeneration,
      ),
    );
    _connection = connection;
    _connectionCredentialGeneration = credentialGeneration;

    try {
      _log(
        'connecting to ${endpoint.host}:${endpoint.port} '
        'tls=${endpoint.useTls}',
      );
      await connection.connect(
        host: endpoint.host,
        port: endpoint.port,
        useTls: endpoint.useTls,
        connectTimeout: const Duration(seconds: 3),
      );
      if (!_running || _authFailed || connectGeneration != _connectGeneration) {
        await connection.close();
        if (identical(_connection, connection)) {
          _connection = null;
        }
        return;
      }
      _armDeadline(connection, connectGeneration, authenticationTimeout);
      await ApiClient.instance.ensureDeviceIdReady();
      if (!_running ||
          connectGeneration != _connectGeneration ||
          !identical(_connection, connection)) return;
      await connection.send(<String, dynamic>{
        'type': 'auth',
        'token': token,
        'deviceId': ApiClient.instance.deviceId,
      });
      if (!_running || _authFailed || connectGeneration != _connectGeneration) {
        await connection.close();
        if (identical(_connection, connection)) {
          _connection = null;
        }
        return;
      }
      _log('connected, auth sent');
    } catch (e, st) {
      _log('connect failed: $e');
      _log('connect failed stack: $st');
      await connection.close();
      if (identical(_connection, connection)) {
        _connection = null;
      }
      if (_running && connectGeneration == _connectGeneration) {
        _scheduleReconnect();
      }
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    unawaited(_sendPing());
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_sendPing());
    });
  }

  Future<void> _sendPing() async {
    if (!isRealtimeReady || !_foreground) {
      return;
    }
    final connection = _connection!;
    final generation = _connectGeneration;
    try {
      await ApiClient.instance.ensureDeviceIdReady();
      if (!isRealtimeReady ||
          generation != _connectGeneration ||
          !identical(_connection, connection) ||
          !_foreground) return;
      _armDeadline(connection, generation, heartbeatTimeout);
      await connection.send(
        PresenceLastSeenCodec.pingFrame(ApiClient.instance.deviceId),
      );
    } catch (_) {
      _expireConnection(connection, generation);
    }
  }

  void _armDeadline(
      FriendRealtimeConnection connection, int generation, Duration timeout) {
    _deadlineTimer?.cancel();
    if (!_foreground) return;
    _deadlineTimer =
        Timer(timeout, () => _expireConnection(connection, generation));
  }

  void _expireConnection(FriendRealtimeConnection connection, int generation) {
    if (!_running ||
        generation != _connectGeneration ||
        !identical(_connection, connection)) return;
    _handleDisconnected(connection: connection, connectGeneration: generation);
    unawaited(connection.close());
  }

  void _handleLine(
    String line, {
    required FriendRealtimeConnection connection,
    required int connectGeneration,
  }) {
    if (!_running ||
        connectGeneration != _connectGeneration ||
        !identical(_connection, connection)) {
      return;
    }
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return;
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (e) {
      _log('invalid realtime frame');
      return;
    }

    final type = map['type']?.toString().trim() ?? '';
    final eventName = map['event']?.toString().trim() ?? '';
    _log('recv frame type=$type event=$eventName');

    switch (type) {
      case 'auth_ok':
        _deadlineTimer?.cancel();
        _deadlineTimer = null;
        _reconnectAttempt = 0;
        _authOk = true;
        _log('auth ok');
        _startPing();
        _emitReadyIfChanged();
        _emitAuthOk();
        return;
      case 'auth_fail':
        _rejectedCredentialGeneration = _connectionCredentialGeneration;
        _deadlineTimer?.cancel();
        _deadlineTimer = null;
        _authFailed = true;
        _authOk = false;
        _pingTimer?.cancel();
        _pingTimer = null;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _failAllLastSeen(PresenceLastSeenFailCode.disconnected);
        unawaited(_connection?.close());
        _connection = null;
        _emitReadyIfChanged();
        _log('auth failed: $map');
        return;
      case 'pong':
        _deadlineTimer?.cancel();
        _deadlineTimer = null;
        return;
      case 'presence_last_seen_ok':
        _completeLastSeenOk(map);
        return;
      case 'presence_last_seen_fail':
        unawaited(_completeLastSeenFail(map));
        return;
      case 'event':
        if (eventName.isNotEmpty) {
          _log('event frame: $eventName');
          onEvent?.call(FriendRealtimeEvent.fromJson(map));
        }
        return;
      case 'error':
        _log('error frame: $map');
        return;
    }

    if (_isRealtimeEventName(eventName)) {
      _log('direct event: $eventName');
      onEvent?.call(FriendRealtimeEvent.fromJson(map));
      return;
    }
    if (_isRealtimeEventName(type)) {
      _log('typed event: $type');
      onEvent?.call(FriendRealtimeEvent.fromJson(<String, dynamic>{
        ...map,
        'event': type,
      }));
      return;
    }

    if (type.isNotEmpty) {
      _log('unknown frame type: $type');
    }
  }

  bool _isRealtimeEventName(String name) {
    switch (name) {
      case 'friend_request_received':
      case 'friend_request_accepted':
      case 'friend_request_rejected':
      case 'friend_request_auto_accepted':
      case 'friend_restored':
      case 'friend_list_changed':
      case 'group_changed':
      case 'call_recent_changed':
      case 'presence_changed':
      case 'red_packet_changed':
        return true;
      case 'moment_changed':
        return true;
      case 'conversation_archive_changed':
        return true;
      case 'conversation_folder_changed':
        return true;
      default:
        return false;
    }
  }

  void _handleDisconnected({
    required FriendRealtimeConnection connection,
    required int connectGeneration,
  }) {
    if (!_running ||
        _authFailed ||
        connectGeneration != _connectGeneration ||
        !identical(_connection, connection)) {
      return;
    }
    _authOk = false;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _failAllLastSeen(PresenceLastSeenFailCode.disconnected);
    _connection = null;
    _emitReadyIfChanged();
    _scheduleReconnect();
  }

  /// 冷启动 / 视口补拉：TCP 主路径；未就绪时由调用方回退 HTTP。
  Future<PresenceLastSeenBatch> fetchPresenceLastSeen(
    List<String> userIds,
  ) async {
    final ids = PresenceLastSeenCodec.normalizeUserIds(userIds);
    if (ids.isEmpty) {
      return const PresenceLastSeenBatch(
        lastSeen: {},
        lastActiveVisibility: {},
      );
    }
    if (!isRealtimeReady) {
      throw const PresenceLastSeenTcpException(
        PresenceLastSeenFailCode.notConnected,
      );
    }
    final chunks = PresenceLastSeenCodec.chunkUserIds(ids);
    // One budget includes queueing, every chunk and the internal-error retry.
    final budget = Stopwatch()..start();
    final generation = _connectGeneration;
    if (chunks.length == 1) {
      return _fetchPresenceLastSeenChunk(chunks.first,
          budget: budget, generation: generation);
    }
    final lastSeen = <String, int>{};
    final visibility = <String, String>{};
    for (final chunk in chunks) {
      final part = await _fetchPresenceLastSeenChunk(chunk,
          budget: budget, generation: generation);
      lastSeen.addAll(part.lastSeen);
      visibility.addAll(part.lastActiveVisibility);
    }
    return PresenceLastSeenBatch(
      lastSeen: lastSeen,
      lastActiveVisibility: visibility,
    );
  }

  Future<PresenceLastSeenBatch> _fetchPresenceLastSeenChunk(
    List<String> userIds, {
    required Stopwatch budget,
    required int generation,
    int attempt = 0,
  }) async {
    if (generation != _connectGeneration || !isRealtimeReady) {
      throw const PresenceLastSeenTcpException(
          PresenceLastSeenFailCode.disconnected);
    }
    final remaining = presenceRequestTimeout - budget.elapsed;
    if (remaining <= Duration.zero) {
      throw const PresenceLastSeenTcpException(
          PresenceLastSeenFailCode.timeout);
    }
    try {
      return await _enqueueLastSeen(userIds, remaining: remaining);
    } on PresenceLastSeenTcpException catch (e) {
      if (e.code == PresenceLastSeenFailCode.internal && attempt < 1) {
        if (presenceRequestTimeout - budget.elapsed <= _internalRetryDelay) {
          throw const PresenceLastSeenTcpException(
              PresenceLastSeenFailCode.timeout);
        }
        await Future<void>.delayed(_internalRetryDelay);
        return _fetchPresenceLastSeenChunk(userIds,
            budget: budget, generation: generation, attempt: attempt + 1);
      }
      rethrow;
    }
  }

  Future<PresenceLastSeenBatch> _enqueueLastSeen(List<String> userIds,
      {required Duration remaining}) {
    if (_lastSeenOperations.length >= 64) {
      return Future.error(const PresenceLastSeenTcpException(
          PresenceLastSeenFailCode.tooManyInflight));
    }
    final completer = Completer<PresenceLastSeenBatch>();
    final queued = _QueuedPresenceLastSeen(
      userIds: userIds,
      completer: completer,
    );
    _lastSeenOperations[completer] = queued;
    queued.deadline = Timer(remaining, () {
      final id = queued.requestId;
      if (id != null) {
        _finishLastSeen(id,
            error: PresenceLastSeenTcpException(
                PresenceLastSeenFailCode.timeout,
                requestId: id));
      } else if (_lastSeenOperations.remove(completer) != null) {
        _lastSeenQueue.remove(queued);
        ChatRecoveryTrace.log('presence_queue_timeout',
            conversationID: '', fields: {'queueDepth': _lastSeenQueue.length});
        completer.completeError(const PresenceLastSeenTcpException(
            PresenceLastSeenFailCode.timeout));
        _drainLastSeenQueue();
      }
    });
    _lastSeenQueue.add(queued);
    _drainLastSeenQueue();
    return completer.future;
  }

  String _nextLastSeenRequestId() {
    _lastSeenSeq++;
    return 'pls-$_lastSeenSeq-${DateTime.now().microsecondsSinceEpoch}';
  }

  void _drainLastSeenQueue() {
    while (_lastSeenWaiters.length < PresenceLastSeenCodec.maxInflight &&
        _lastSeenQueue.isNotEmpty) {
      if (!isRealtimeReady) {
        _failAllLastSeen(PresenceLastSeenFailCode.notConnected);
        return;
      }
      final next = _lastSeenQueue.removeAt(0);
      if (next.completer.isCompleted) {
        continue;
      }
      final requestId = _nextLastSeenRequestId();
      next.requestId = requestId;
      _lastSeenWaiters[requestId] = next.completer;
      _lastSeenUserIds[requestId] = next.userIds;
      _lastSeenTimeouts[requestId]?.cancel();
      _lastSeenTimeouts[requestId] = Timer(_lastSeenTimeout, () {
        _finishLastSeen(
          requestId,
          error: PresenceLastSeenTcpException(
            PresenceLastSeenFailCode.timeout,
            requestId: requestId,
          ),
        );
      });
      unawaited(() async {
        try {
          await _connection?.send(
            PresenceLastSeenCodec.lastSeenRequestFrame(
              requestId: requestId,
              userIds: next.userIds,
            ),
          );
        } catch (_) {
          _finishLastSeen(
            requestId,
            error: PresenceLastSeenTcpException(
              PresenceLastSeenFailCode.disconnected,
              requestId: requestId,
            ),
          );
        }
      }());
    }
  }

  void _completeLastSeenOk(Map<String, dynamic> map) {
    final requestId = PresenceLastSeenCodec.requestIdOf(map);
    if (requestId == null) {
      return;
    }
    _finishLastSeen(
      requestId,
      batch: PresenceLastSeenCodec.parseBatch(map),
    );
  }

  Future<void> _completeLastSeenFail(Map<String, dynamic> map) async {
    final requestId = PresenceLastSeenCodec.requestIdOf(map);
    final code = PresenceLastSeenCodec.failCodeOf(map) ??
        PresenceLastSeenFailCode.internal;
    if (requestId == null) {
      return;
    }
    // Overload is a terminal TCP result. PresenceProvider already has a bounded
    // HTTP fallback; replaying here hid overload and held its flush forever.
    _finishLastSeen(
      requestId,
      error: PresenceLastSeenTcpException(code, requestId: requestId),
    );
  }

  void _finishLastSeen(
    String requestId, {
    PresenceLastSeenBatch? batch,
    PresenceLastSeenTcpException? error,
  }) {
    _lastSeenTimeouts.remove(requestId)?.cancel();
    _lastSeenUserIds.remove(requestId);
    final waiter = _lastSeenWaiters.remove(requestId);
    _lastSeenOperations.remove(waiter)?.deadline?.cancel();
    if (waiter == null || waiter.isCompleted) {
      _drainLastSeenQueue();
      return;
    }
    if (batch != null) {
      waiter.complete(batch);
    } else {
      ChatRecoveryTrace.log('presence_request_failed',
          conversationID: '',
          operation: requestId,
          fields: {
            'code': error?.code ?? PresenceLastSeenFailCode.internal,
            'queueDepth': _lastSeenQueue.length,
          });
      waiter.completeError(
        error ??
            PresenceLastSeenTcpException(
              PresenceLastSeenFailCode.internal,
              requestId: requestId,
            ),
      );
    }
    _drainLastSeenQueue();
  }

  void _failAllLastSeen(String code) {
    for (final operation in _lastSeenOperations.values) {
      operation.deadline?.cancel();
    }
    _lastSeenOperations.clear();
    final queued = List<_QueuedPresenceLastSeen>.from(_lastSeenQueue);
    _lastSeenQueue.clear();
    final waiters = Map<String, Completer<PresenceLastSeenBatch>>.from(
      _lastSeenWaiters,
    );
    _lastSeenWaiters.clear();
    _lastSeenUserIds.clear();
    for (final timer in _lastSeenTimeouts.values) {
      timer.cancel();
    }
    _lastSeenTimeouts.clear();
    final error = PresenceLastSeenTcpException(code);
    for (final item in queued) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(error);
      }
    }
    for (final waiter in waiters.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }

  void _scheduleReconnect() {
    if (!_running || _authFailed) {
      return;
    }
    _reconnectTimer?.cancel();
    final seconds = _reconnectDelaySeconds(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_connect());
    });
  }

  int _reconnectDelaySeconds(int attempt) {
    if (attempt <= 0) {
      return 1;
    }
    final delay = 1 << attempt.clamp(0, 6);
    return delay > 60 ? 60 : delay;
  }
}

class _QueuedPresenceLastSeen {
  _QueuedPresenceLastSeen({
    required this.userIds,
    required this.completer,
  });

  final List<String> userIds;
  final Completer<PresenceLastSeenBatch> completer;
  Timer? deadline;
  String? requestId;
}
