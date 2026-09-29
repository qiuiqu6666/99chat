// Audit-only: real service + real loopback socket, synthetic credentials only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A04 auth failure rejects force with fresh token; stop-start recovers', () async {
    final endpoint = Uri.parse(IMDemoConfig.realtimeTcpBase);
    expect(endpoint.host, '127.0.0.1', reason: 'never contact a production TCP endpoint');
    expect(ApiNodeService.instance.isHydrated, isFalse);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, endpoint.port);
    final sockets = <Socket>[];
    final firstClosed = Completer<void>();
    final ready = Completer<void>();
    final service = FriendRealtimeService.instance;
    var accepts = 0;
    var authFrames = 0;
    service.onAuthOk = () { if (!ready.isCompleted) ready.complete(); };
    server.listen((socket) {
      sockets.add(socket);
      final index = ++accepts;
      socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())
          .listen((line) {
        final frame = jsonDecode(line) as Map;
        if (frame['type'] == 'auth') {
          authFrames++;
          socket.add(utf8.encode(index == 1
              ? '{"type":"auth_fail","reason":"audit expired token"}\n'
              : '{"type":"auth_ok"}\n'));
        }
      }, onDone: () {
        if (index == 1 && !firstClosed.isCompleted) firstClosed.complete();
      });
    });
    try {
      await ApiClient.instance.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', userId: 'audit');
      service.start();
      await firstClosed.future.timeout(const Duration(seconds: 5));
      await ApiClient.instance.saveToken('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', userId: 'audit');
      await service.ensureConnected(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(accepts, 1);
      expect(authFrames, 1);
      expect(service.isRealtimeReady, isFalse);
      print('AUDIT A04 after fresh token + force: connections=$accepts; authFrames=$authFrames; ready=${service.isRealtimeReady}');
      await service.stop();
      service.start();
      await ready.future.timeout(const Duration(seconds: 5));
      expect(accepts, 2);
      expect(service.isRealtimeReady, isTrue);
      print('AUDIT A04 after stop/start: connections=$accepts; authFrames=$authFrames; ready=${service.isRealtimeReady}');
    } finally {
      service.onAuthOk = null;
      await service.stop();
      for (final socket in sockets) { socket.destroy(); }
      await server.close();
      await ApiClient.instance.clearToken();
    }
  });
}
