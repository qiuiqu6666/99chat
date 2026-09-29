import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'liveness-owner');
  });
  tearDown(() => ApiClient.instance.clearToken());

  for (final silentAuth in [true, false]) {
    test(
        '${silentAuth ? 'auth silence' : 'lost pong'} closes stale readiness and healthy reconnect succeeds',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final expired = Completer<void>();
      final recovered = Completer<void>();
      var healthy = false;
      final service = FriendRealtimeService.forTesting(
        endpoint: 'http://127.0.0.1:${server.port}',
        authenticationTimeout: const Duration(milliseconds: 80),
        heartbeatTimeout: const Duration(milliseconds: 80),
      );
      service.onAuthOk = () {
        if (healthy && !recovered.isCompleted) recovered.complete();
      };
      void reply(Socket peer, Map<String, dynamic> frame) =>
          peer.add(utf8.encode('${jsonEncode(frame)}\n'));
      server.listen((peer) {
        peers.add(peer);
        peer
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
                (line) {
                  final frame = jsonDecode(line) as Map;
                  if (frame['type'] == 'auth' && (!silentAuth || healthy)) {
                    reply(peer, {'type': 'auth_ok'});
                  } else if (frame['type'] == 'ping' && healthy) {
                    reply(peer, {'type': 'pong'});
                  } else if (frame['type'] == 'presence_last_seen' && healthy) {
                    reply(peer, {
                      'type': 'presence_last_seen_ok',
                      'requestId': frame['requestId'],
                      'lastSeen': {'10001': 456}
                    });
                  }
                },
                onError: (_) {},
                onDone: () {
                  if (!healthy && !expired.isCompleted) expired.complete();
                });
      });
      try {
        service.start();
        await expired.future.timeout(const Duration(seconds: 3));
        expect(service.isRealtimeReady, isFalse);
        healthy = true;
        await service.ensureConnected(force: true);
        await recovered.future.timeout(const Duration(seconds: 3));
        expect(service.isRealtimeReady, isTrue);
        expect(
            (await service.fetchPresenceLastSeen(['10001'])).lastSeen['10001'],
            456);
        expect(peers, hasLength(2));
      } finally {
        await service.stop();
        for (final peer in peers) {
          peer.destroy();
        }
        await server.close();
      }
    });
  }
}
