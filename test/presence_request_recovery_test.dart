import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_connection_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/presence_last_seen_codec.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime_service.dart';

class _Server {
  _Server(this.server, this.service);
  final ServerSocket server;
  final FriendRealtimeService service;
  final peers = <Socket>[];
  final requests = <Map<String, dynamic>>[];
  void Function(Socket, Map<String, dynamic>)? answer;

  static Future<_Server> open({Duration budget = const Duration(seconds: 1)}) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final service = FriendRealtimeService.forTesting(
      endpoint: 'http://127.0.0.1:${socket.port}',
      presenceRequestTimeout: budget,
    );
    final fixture = _Server(socket, service);
    socket.listen((peer) {
      fixture.peers.add(peer);
      peer.cast<List<int>>().transform(utf8.decoder)
          .transform(const LineSplitter()).listen((line) {
        final frame = Map<String, dynamic>.from(jsonDecode(line) as Map);
        if (frame['type'] == 'auth') {
          fixture.reply(peer, {'type': 'auth_ok'});
        } else if (frame['type'] == 'ping') {
          fixture.reply(peer, {'type': 'pong'});
        } else if (frame['type'] == 'presence_last_seen') {
          fixture.requests.add(frame);
          fixture.answer?.call(peer, frame);
        }
      }, onError: (_) {});
    });
    await fixture.start();
    return fixture;
  }

  Future<void> start() async {
    final ready = Completer<void>();
    service.onAuthOk = () { if (!ready.isCompleted) ready.complete(); };
    service.start();
    await ready.future.timeout(const Duration(seconds: 3));
  }

  void reply(Socket socket, Map<String, dynamic> frame) =>
      socket.add(utf8.encode('${jsonEncode(frame)}\n'));

  void succeed(Socket socket, Map<String, dynamic> frame) => reply(socket, {
    'type': 'presence_last_seen_ok', 'requestId': frame['requestId'],
    'lastSeen': {'10001': 123},
  });

  Future<void> close() async {
    await service.stop();
    for (final peer in peers) { peer.destroy(); }
    await server.close();
  }
}

Matcher _fails(String code) => throwsA(isA<PresenceLastSeenTcpException>()
    .having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.saveToken(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', userId: 'test-owner');
  });
  tearDown(() => ApiClient.instance.clearToken());

  test('overload releases its waiter immediately and next query succeeds', () async {
    final fixture = await _Server.open();
    try {
      fixture.answer = (peer, frame) => fixture.reply(peer, {
        'type': 'presence_last_seen_fail', 'requestId': frame['requestId'],
        'code': PresenceLastSeenFailCode.tooManyInflight,
      });
      await expectLater(fixture.service.fetchPresenceLastSeen(['10001']),
          _fails(PresenceLastSeenFailCode.tooManyInflight));
      expect(fixture.requests, hasLength(1));
      fixture.answer = fixture.succeed;
      expect((await fixture.service.fetchPresenceLastSeen(['10001'])).lastSeen['10001'], 123);
      expect(fixture.requests, hasLength(2));
    } finally { await fixture.close(); }
  });

  test('queued and sent requests share a total deadline; late replies cannot poison retry', () async {
    final fixture = await _Server.open(budget: const Duration(milliseconds: 300));
    try {
      // Three slots are busy; later requests must expire while still queued.
      await Future.wait(List.generate(8, (_) => expectLater(
          fixture.service.fetchPresenceLastSeen(['10001']),
          _fails(PresenceLastSeenFailCode.timeout))));
      final expired = fixture.requests.toList();
      fixture.answer = fixture.succeed;
      for (final frame in expired) { fixture.succeed(fixture.peers.last, frame); }
      expect((await fixture.service.fetchPresenceLastSeen(['10001'])).lastSeen['10001'], 123);
    } finally { await fixture.close(); }
  });

  test('stop releases all pending requests and old completions do not block new connection', () async {
    final fixture = await _Server.open();
    try {
      final pending = List.generate(5, (_) => expectLater(
          fixture.service.fetchPresenceLastSeen(['10001']),
          _fails(PresenceLastSeenFailCode.disconnected)));
      await fixture.service.stop();
      await Future.wait(pending);
      fixture.answer = fixture.succeed;
      await fixture.start();
      expect((await fixture.service.fetchPresenceLastSeen(['10001'])).lastSeen['10001'], 123);
    } finally { await fixture.close(); }
  });

  test('internal retry cannot escape deadline or reappear in a new session', () async {
    final fixture = await _Server.open(budget: const Duration(milliseconds: 150));
    try {
      fixture.answer = (peer, frame) => fixture.reply(peer, {
        'type': 'presence_last_seen_fail', 'requestId': frame['requestId'],
        'code': PresenceLastSeenFailCode.internal,
      });
      await expectLater(fixture.service.fetchPresenceLastSeen(['10001']),
          _fails(PresenceLastSeenFailCode.timeout));
      expect(fixture.requests, hasLength(1));
      fixture.answer = fixture.succeed;
      expect((await fixture.service.fetchPresenceLastSeen(['10001'])).lastSeen['10001'], 123);
    } finally { await fixture.close(); }
  });

  test('oversized unterminated TCP frame closes once and can reconnect', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    final closed = Completer<void>();
    var closes = 0;
    var accepted = Completer<Socket>();
    server.listen((peer) { peers.add(peer); accepted.complete(peer); });
    final connection = FriendRealtimeConnection(onLine: (_) {}, onDisconnected: () {
      closes++;
      if (!closed.isCompleted) closed.complete();
    });
    try {
      await connection.connect(host: '127.0.0.1', port: server.port);
      final peer = await accepted.future;
      peer.add(List.filled(FriendRealtimeConnection.maxFrameBytes + 1, 65));
      await closed.future.timeout(const Duration(seconds: 3));
      expect(closes, 1);
      accepted = Completer<Socket>();
      await connection.connect(host: '127.0.0.1', port: server.port);
      await accepted.future;
      await Future.wait(List.generate(10, (i) => connection.send({'type': 'test', 'index': i})));
      expect(closes, 1);
    } finally {
      await connection.close();
      for (final peer in peers) { peer.destroy(); }
      await server.close();
    }
  });
}
