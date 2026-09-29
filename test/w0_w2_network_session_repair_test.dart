import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_connection_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/session/session_manager.dart';
import 'session_manager_test.dart' as fixtures;

class _Adapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions, Future?)? handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future? cancelFuture) =>
      handler!(options, cancelFuture);
  @override
  void close({bool force = false}) {}
}

class _SlowIm extends fixtures.FakeImClient {
  Completer<void>? block;
  int active = 0;
  int maxActive = 0;
  @override
  Future<void> connect(
      {required String userId, required String userSig}) async {
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await super.connect(userId: userId, userSig: userSig);
      await block?.future;
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'realtime authentication has a deadline without accumulating connections',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final disconnected = Completer<void>();
    Socket? peer;
    final service = FriendRealtimeService.forTesting(
        endpoint: 'http://127.0.0.1:${server.port}',
        authenticationTimeout: const Duration(milliseconds: 60));
    server.listen((socket) {
      peer = socket;
      socket.listen((_) {}, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      });
    });
    try {
      await ApiClient.instance.saveToken(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          userId: 'deadline');
      service.start();
      await disconnected.future.timeout(const Duration(seconds: 3));
      expect(service.isRealtimeReady, isFalse);
    } finally {
      await service.stop();
      peer?.destroy();
      await server.close();
      await ApiClient.instance.clearToken();
    }
  });

  test('heartbeat deadline suspends in background and rearms on foreground',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final disconnected = Completer<void>();
    final ready = Completer<void>();
    Socket? peer;
    final service = FriendRealtimeService.forTesting(
        endpoint: 'http://127.0.0.1:${server.port}',
        heartbeatTimeout: const Duration(milliseconds: 60));
    service.onAuthOk = () {
      if (!ready.isCompleted) ready.complete();
    };
    server.listen((socket) {
      peer = socket;
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if ((jsonDecode(line) as Map)['type'] == 'auth') {
          socket.add(utf8.encode('{"type":"auth_ok"}\n'));
        }
      }, onDone: () {
        if (!disconnected.isCompleted) disconnected.complete();
      });
    });
    try {
      await ApiClient.instance.saveToken(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          userId: 'heartbeat');
      service.start();
      await ready.future.timeout(const Duration(seconds: 3));
      service.onAppLifecycleChanged(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(disconnected.isCompleted, isFalse);
      service.onAppLifecycleChanged(AppLifecycleState.resumed);
      await disconnected.future.timeout(const Duration(seconds: 3));
      expect(service.isRealtimeReady, isFalse);
    } finally {
      await service.stop();
      peer?.destroy();
      await server.close();
      await ApiClient.instance.clearToken();
    }
  });

  test('compact startup diagnostics are available in development', () {
    expect(StartupPerfLog.consoleLoggingEnabled, isTrue);
  });

  test('TCP preserves every split of Chinese and emoji without callback errors',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final frames = <String>[];
    final delivered = Completer<void>();
    const frame = '{"type":"event","text":"中文🙂"}';
    final bytes = utf8.encode('$frame\n');
    final connection = FriendRealtimeConnection(
        onLine: (line) {
          frames.add(line);
          if (frames.length == bytes.length - 1) delivered.complete();
        },
        onDisconnected: () {});
    Socket? peer;
    try {
      await connection.connect(host: '127.0.0.1', port: server.port);
      peer = await accepted;
      for (var split = 1; split < bytes.length; split++) {
        peer.add(bytes.sublist(0, split));
        await peer.flush();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        peer.add(bytes.sublist(split));
        await peer.flush();
      }
      await delivered.future.timeout(const Duration(seconds: 3));
      expect(frames, everyElement(frame));
    } finally {
      await connection.close();
      peer?.destroy();
      await server.close();
    }
  });

  test('invalid and incomplete UTF8 close the TCP stream once', () async {
    for (final bytes in [
      [0xff],
      [0xe4, 0xb8]
    ]) {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      final done = Completer<void>();
      var closes = 0;
      final connection = FriendRealtimeConnection(
          onLine: (_) => fail('invalid frame delivered'),
          onDisconnected: () {
            closes++;
            if (!done.isCompleted) done.complete();
          });
      await connection.connect(host: '127.0.0.1', port: server.port);
      final peer = await accepted;
      peer.add(bytes);
      await peer.flush();
      await peer.close();
      await done.future.timeout(const Duration(seconds: 3));
      expect(closes, 1);
      await connection.close();
      peer.destroy();
      await server.close();
    }
  });

  test('cancel and stale-node completions never affect current-node health',
      () async {
    final client = ApiClient.instance;
    final original = client.dio.httpClientAdapter;
    final oldSuccess = ApiClient.onTransportSuccess;
    final oldFailure = ApiClient.onTransportFailure;
    final base = ApiClient.resolveBaseUrl();
    final adapter = _Adapter();
    var failures = 0;
    var successes = 0;
    client.dio.httpClientAdapter = adapter;
    ApiClient.onTransportSuccess = () => successes++;
    ApiClient.onTransportFailure = () => failures++;
    try {
      for (var i = 0; i < 3; i++) {
        final entered = Completer<void>();
        adapter.handler = (_, cancel) async {
          entered.complete();
          throw await cancel!;
        };
        final cancel = CancelToken();
        final result = expectLater(
            client.dio.get('/api/v1/platform/splash', cancelToken: cancel),
            throwsA(isA<DioError>()));
        await entered.future;
        cancel.cancel();
        await result;
      }
      final response = Completer<ResponseBody>();
      final entered = Completer<void>();
      adapter.handler = (_, __) {
        entered.complete();
        return response.future;
      };
      final old = client.dio.get('/api/v1/platform/splash');
      await entered.future;
      ApiClient.applyRuntimeBaseUrl('https://next.invalid');
      response.complete(ResponseBody.fromString('{}', 200));
      await old;
      expect(failures, 0);
      expect(successes, 0);
      adapter.handler = (_, __) async => ResponseBody.fromString('{}', 503);
      await expectLater(
          client.dio.get('/api/v1/platform/splash'), throwsA(isA<DioError>()));
      expect(failures, 1);
    } finally {
      ApiClient.applyRuntimeBaseUrl(base);
      client.dio.httpClientAdapter = original;
      ApiClient.onTransportSuccess = oldSuccess;
      ApiClient.onTransportFailure = oldFailure;
    }
  });

  test('reachable 401/403/503 never beat a healthy public probe', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 200;
    server.listen((request) async {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"enabled":false}');
      await request.response.close();
    });
    final node = ApiNodeDefinition(
        id: 'cn',
        name: 'loopback',
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
        realtimeTcpBase: '');
    try {
      for (final code in [401, 403, 502, 503, 504]) {
        status = code;
        final bad = await ApiNodeService.instance.probeNode(node);
        expect(bad.status, ApiNodeProbeStatus.abnormal);
        expect(bad.reachable, isTrue);
        expect(
            ApiNodeService.pickFastestNormal(probes: {
              'cn': bad,
              'apiios': const ApiNodeProbeResult(
                  status: ApiNodeProbeStatus.normal, latencyMs: 999)
            })?.id,
            'apiios');
      }
      status = 200;
      expect((await ApiNodeService.instance.probeNode(node)).status,
          ApiNodeProbeStatus.normal);
    } finally {
      await server.close(force: true);
      HttpOverrides.global = overrides;
    }
  });

  test('probe callers join one actual round and wait for its results',
      () async {
    final service = ApiNodeService.instance;
    final gate = Completer<ApiNodeProbeResult>();
    var calls = 0;
    service.probeOverride = (_) {
      calls++;
      return gate.future;
    };
    try {
      final first = service.probeAll();
      final second = service.probeAll();
      expect(identical(first, second), isTrue);
      expect(calls, 2);
      gate.complete(const ApiNodeProbeResult(
          status: ApiNodeProbeStatus.normal, latencyMs: 10));
      await second;
      await first;
      expect(service.isProbing, isFalse);
    } finally {
      service.probeOverride = null;
    }
  });

  test('ready foreground validates business owner without repeating SDK login',
      () async {
    final store = fixtures.FakeSessionStore()
      ..token = 'token'
      ..userId = 'a'
      ..credential = (1, 'cached');
    final auth = fixtures.FakeAuthRepository()
      ..meCall = (() async => fixtures.me('a'))
      ..sigCall = (() async => fixtures.sig('a'));
    final im = _SlowIm();
    final session = SessionManager(store: store, auth: auth, im: im);
    await session.restore();
    await Future<void>.delayed(Duration.zero);
    await Future.wait([session.restore(), session.restore()]);
    expect(im.connectCalls, 1);
    expect(im.initializeCalls, 1);
    expect(session.state.isReady, isTrue);
  });

  testWidgets('timer reconnect occupies the same flight as foreground restore',
      (tester) async {
    final store = fixtures.FakeSessionStore();
    final auth = fixtures.FakeAuthRepository()
      ..meCall = (() async => fixtures.me('a'))
      ..sigCall = (() async => fixtures.sig('a'));
    final im = _SlowIm()..failConnect = true;
    final session = SessionManager(store: store, auth: auth, im: im);
    await session.establishFromSavedBusinessSession(
        token: 'token', userId: 'a');
    im.failConnect = false;
    final gate = Completer<void>();
    im.block = gate;
    await tester.pump(const Duration(seconds: 2));
    final foreground = session.restore();
    await tester.pump();
    expect(im.connectCalls, 2);
    expect(im.maxActive, 1);
    gate.complete();
    await tester.pump();
    await foreground;
    expect(session.state.isReady, isTrue);
  });

  test(
      'new credentials recover rejected realtime auth; unchanged credentials do not loop',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    var attempts = 0;
    final rejected = Completer<void>();
    final ready = Completer<void>();
    final service = FriendRealtimeService.forTesting(
        endpoint: 'http://127.0.0.1:${server.port}');
    service.onAuthOk = () {
      if (!ready.isCompleted) ready.complete();
    };
    server.listen((socket) {
      peers.add(socket);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final frame = jsonDecode(line) as Map;
        if (frame['type'] == 'auth') {
          attempts++;
          socket.add(utf8.encode(attempts == 1
              ? '{"type":"auth_fail"}\n'
              : '{"type":"auth_ok"}\n'));
        } else if (frame['type'] == 'ping') {
          socket.add(utf8.encode('{"type":"pong"}\n'));
        }
      }, onDone: () {
        if (!rejected.isCompleted) rejected.complete();
      });
    });
    try {
      await ApiClient.instance.saveToken(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          userId: 'repair');
      service.start();
      await rejected.future.timeout(const Duration(seconds: 3));
      await service.ensureConnected(force: true);
      expect(attempts, 1);
      await ApiClient.instance.saveToken(
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          userId: 'repair');
      await service.ensureConnected(force: true);
      await ready.future.timeout(const Duration(seconds: 3));
      expect(attempts, 2);
      expect(service.isRealtimeReady, isTrue);
    } finally {
      await service.stop();
      for (final peer in peers) {
        peer.destroy();
      }
      await server.close();
      await ApiClient.instance.clearToken();
    }
  });
}
