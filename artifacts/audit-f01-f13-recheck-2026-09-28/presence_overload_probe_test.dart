// Audit-only fault injection: passing means the current defect was reproduced.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/api_node_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/presence_last_seen_codec.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F05 overload resets per-attempt timeout beyond original eight seconds',
      () async {
    final endpoint = Uri.parse(IMDemoConfig.realtimeTcpBase);
    expect(endpoint.host, '127.0.0.1');
    expect(ApiNodeService.instance.isHydrated, isFalse);
    expect(PresenceLastSeenCodec.normalizeUserIds(['10001']), ['10001']);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      endpoint.port,
    );
    final sockets = <Socket>[];
    final ready = Completer<void>();
    final firstQuery = Completer<void>();
    final service = FriendRealtimeService.instance;
    var overload = true;
    var requests = 0;
    var settled = false;
    Object? queryError;
    service.onAuthOk = () {
      if (!ready.isCompleted) ready.complete();
    };
    server.listen((socket) {
      sockets.add(socket);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final frame = jsonDecode(line) as Map;
        if (frame['type'] == 'auth') {
          socket.add(utf8.encode('{"type":"auth_ok"}\n'));
        } else if (frame['type'] == 'presence_last_seen') {
          requests++;
          final response = overload
              ? <String, Object?>{
                  'type': 'presence_last_seen_fail',
                  'requestId': frame['requestId'],
                  'code': 'TOO_MANY_INFLIGHT',
                }
              : <String, Object?>{
                  'type': 'presence_last_seen_ok',
                  'requestId': frame['requestId'],
                  'lastSeen': {'10001': 123},
                  'lastActiveVisibility': {'10001': 'everyone'},
                };
          socket.add(utf8.encode('${jsonEncode(response)}\n'));
          if (!firstQuery.isCompleted) firstQuery.complete();
        }
      });
    });
    try {
      await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        userId: 'audit',
      );
      service.start();
      await ready.future.timeout(const Duration(seconds: 5));
      // Isolate retry-budget behavior from the initial fire-and-forget ping.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.isRealtimeReady, isTrue);
      final outcome = service.fetchPresenceLastSeen(['10001']).then((batch) {
        settled = true;
        return batch.lastSeen['10001'];
      }, onError: (Object error, StackTrace stack) {
        settled = true;
        queryError = error;
        return null;
      });
      await firstQuery.future.timeout(const Duration(seconds: 3), onTimeout: () {
        throw StateError('No query received: settled=$settled error=$queryError');
      });
      final watch = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 9200));
      expect(requests, greaterThan(5));
      expect(settled, isFalse);
      print('AUDIT F05 elapsedMs=${watch.elapsedMilliseconds}; '
          'overloadReplies=$requests; settled=$settled; '
          'nominalAttemptTimeoutMs=8000');
      overload = false;
      expect(await outcome.timeout(const Duration(seconds: 3)), 123);
      expect(queryError, isNull);
      final next = await service
          .fetchPresenceLastSeen(['10001'])
          .timeout(const Duration(seconds: 3));
      expect(next.lastSeen['10001'], 123);
      print('AUDIT F05 after overload stops: originalCompletes=true; '
          'subsequentQueryCompletes=true');
    } finally {
      service.onAuthOk = null;
      await service.stop();
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
      await ApiClient.instance.clearToken();
    }
  });
}
