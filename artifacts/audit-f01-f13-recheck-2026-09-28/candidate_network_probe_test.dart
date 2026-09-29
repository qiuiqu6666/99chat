// Verification of concurrently arriving candidate fixes; asserts desired behavior.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_connection_io.dart';

class _CancelledAdapter implements HttpClientAdapter {
  Completer<void> entered = Completer<void>();
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future? cancelFuture) async {
    entered.complete();
    throw await cancelFuture!;
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F03 candidate preserves split Unicode and next frame', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final lines = <String>[];
    final errors = <Object>[];
    final firstError = Completer<void>();
    var disconnected = 0;
    late FriendRealtimeConnection connection;
    Socket? peer;
    try {
      await runZonedGuarded<Future<void>>(() async {
        connection = FriendRealtimeConnection(onLine: lines.add,
            onDisconnected: () => disconnected++);
        await connection.connect(host: '127.0.0.1', port: server.port);
        peer = await accepted;
        final payload = utf8.encode('{"type":"event","name":"中文🙂"}\n');
        final cut = payload.indexWhere((byte) => byte >= 0x80) + 1;
        peer!.add(payload.sublist(0, cut));
        await peer!.flush();
        // Wait for first real socket read before transmitting the remainder.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        peer!.add(payload.sublist(cut));
        await peer!.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        peer!.add(utf8.encode('{"type":"control"}\n'));
        await peer!.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (error, _) {
        errors.add(error);
        if (!firstError.isCompleted) firstError.complete();
      });
      expect(errors, isEmpty);
      expect(errors.every((error) => error is FormatException), isTrue);
      expect(lines, ['{"type":"event","name":"中文🙂"}', '{"type":"control"}']);
      expect(disconnected, 0);
      print('AUDIT A01 zoneErrors=${errors.length}; delivered=${lines.length}; '
          'unicodeFrameDelivered=true; disconnected=$disconnected');
    } finally {
      await connection.close();
      peer?.destroy();
      await server.close();
    }
  });

  test('F01 candidate excludes canceled requests from node health', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final client = ApiClient.instance;
    final previousAdapter = client.dio.httpClientAdapter;
    final previousFailure = ApiClient.onTransportFailure;
    final previousSuccess = ApiClient.onTransportSuccess;
    var failures = 0;
    var successes = 0;
    final classified = Completer<void>();
    var terminalErrors = 0;
    final terminal = InterceptorsWrapper(onError: (error, handler) {
      if (++terminalErrors == 3) classified.complete();
      handler.next(error);
    });
    client.dio.interceptors.add(terminal);
    final adapter = _CancelledAdapter();
    client.dio.httpClientAdapter = adapter;
    ApiClient.onTransportFailure = () {
      failures++;
    };
    ApiClient.onTransportSuccess = () => successes++;
    try {
      for (var i = 0; i < 3; i++) {
        adapter.entered = Completer<void>();
        final cancel = CancelToken();
        final result = expectLater(client.dio.get('/api/v1/platform/splash', cancelToken: cancel),
            throwsA(isA<DioError>().having((e) => e.type, 'type', DioErrorType.cancel)));
        await adapter.entered.future;
        cancel.cancel('audit deliberate cancellation');
        await result;
      }
      await classified.future.timeout(const Duration(seconds: 3));
      expect(failures, 0);
      expect(successes, 0);
      print('AUDIT A02 canceledRequests=3; transportFailures=$failures; successes=$successes');
    } finally {
      client.dio.interceptors.remove(terminal);
      client.dio.httpClientAdapter = previousAdapter;
      ApiClient.onTransportFailure = previousFailure;
      ApiClient.onTransportSuccess = previousSuccess;
    }
  });

  test('F02 candidate rejects fast 503 and selects slower healthy 200', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 503;
    var delay = Duration.zero;
    server.listen((request) async {
      final responseStatus = status;
      final responseDelay = delay;
      await Future<void>.delayed(responseDelay);
      request.response.statusCode = responseStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"audit":true}');
      await request.response.close();
    });
    ApiNodeDefinition node(String id) => ApiNodeDefinition(id: id, name: 'audit',
      apiBaseUrl: 'http://127.0.0.1:${server.port}',
      realtimeTcpBase: 'http://127.0.0.1:${server.port}');
    try {
      final unavailable = await ApiNodeService.instance.probeNode(node('cn'));
      status = 200;
      delay = const Duration(milliseconds: 400);
      final healthy = await ApiNodeService.instance.probeNode(node('apiios'));
      final picked = ApiNodeService.pickFastestNormal(probes: {
        'cn': unavailable, 'apiios': healthy,
      });
      expect(unavailable.status, ApiNodeProbeStatus.abnormal);
      expect(healthy.status, ApiNodeProbeStatus.normal);
      expect(picked!.id, 'apiios');
      print('AUDIT A03 HTTP503=${unavailable.status.name}/${unavailable.latencyMs}ms; '
          'HTTP200=${healthy.status.name}/${healthy.latencyMs}ms; selected=${picked.id}');
    } finally {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    }
  });
}
