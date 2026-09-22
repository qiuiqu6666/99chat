import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'lottery_live_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'mismatched instance is rejected and permission loss clears cache',
      (tester) async {
    final api = FakeLotteryApi();
    var mismatch = true;
    var forbidden = false;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (forbidden) {
        h.reject(DioError(
            requestOptions: o,
            response: Response(requestOptions: o, statusCode: 403),
            type: DioErrorType.response));
        return;
      }
      final body = liveFixture(o.path);
      if (mismatch && o.path.endsWith('/draws')) {
        body['groupUid'] = 'different-group';
      }
      h.resolve(Response(requestOptions: o, data: body));
    }));
    final session = LotteryLiveSession(api, 'machine');
    session.attach();
    await tester.pumpAndSettle();
    expect(session.ready, false);
    expect(session.error, isNotNull);
    mismatch = false;
    session.refresh();
    await tester.pumpAndSettle();
    expect(session.ready, true);
    forbidden = true;
    session.refresh();
    await tester.pumpAndSettle();
    expect(session.ready, false);
    expect(session.draws, isEmpty);
    expect(session.predictions, isEmpty);
    session.detach();
    await tester.pump();
  });
  testWidgets('invalid push preserves prior data and triggers reconnect state',
      (tester) async {
    final api = FakeLotteryApi();
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) =>
            h.resolve(Response(requestOptions: o, data: liveFixture(o.path)))));
    final session = LotteryLiveSession(api, 'machine');
    session.attach();
    await tester.pumpAndSettle();
    final bad = liveFixture('/draws');
    bad['data']['items'][1]['drawAt'] = '1790005751631';
    api.sockets.last.send('draws', bad);
    await tester.pump();
    expect(session.draws[1]['drawAt'], 1790005751631);
    expect(session.connected, false);
    session.detach();
    await tester.pump();
  });
  test('public HTTP and socket use fixed lottery and encode raw machine once',
      () async {
    final api = LotteryLiveApi();
    const machine = '@x#%23+a/b';
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/api/v1/lotteries/mark-six-demo/predictions');
      expect(options.uri.queryParameters['machineCode'], machine);
      expect(options.queryParameters,
          {'machineCode': machine, 'window': 12, 'page': 1, 'pageSize': 20});
      expect(options.headers.keys.map((v) => v.toLowerCase()),
          isNot(contains('authorization')));
      expect(options.headers.keys.map((v) => v.toLowerCase()),
          isNot(contains('x-group-id')));
      expect(options.headers.keys.map((v) => v.toLowerCase()),
          isNot(contains('cookie')));
      handler.resolve(Response(
          requestOptions: options,
          data: liveFixture(options.path, window: 12)));
    }));
    await api.get('predictions', machine, window: 12);
    expect(api.socketUri(machine, 12).queryParameters['machineCode'], machine);
    api.dio.options.baseUrl = 'https://example.test';
    expect(api.socketUri(machine, 40).scheme, 'wss');
  });
  testWidgets(
      'HTTP initialization, push, heartbeat, window switch and lifecycle',
      (tester) async {
    final api = FakeLotteryApi();
    final calls = <RequestOptions>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls.add(options);
      handler.resolve(Response(
          requestOptions: options,
          data: liveFixture(options.path,
              window: options.queryParameters['window'] as int? ?? 40)));
    }));
    final session = LotteryLiveSession(api, 'game1');
    session.attach();
    await tester.pumpAndSettle();
    expect(session.ready, true);
    expect(calls.length, 3);
    expect(session.draws.length, 2);
    expect(session.draws.first['status'], 'closed');
    expect(session.mappings!.colors.length, 49);
    expect(session.timeAt(0).hour, 8);
    expect(session.connected, true);
    final changed = liveFixture('/draws');
    (changed['data']['items'][1]['attributes'] as Map)['special'] = '09';
    api.sockets.last.send('draws', changed);
    await tester.pump();
    expect(session.draws[1]['attributes']['special'], '09');
    api.sockets.last.send('heartbeat', {
      'groupUid': 'resolved-player-group',
      'serverTime': 1790005752631,
      'data': {}
    });
    await tester.pump();
    expect(session.draws[1]['attributes']['special'], '09');
    session.selectWindow(12);
    await tester.pumpAndSettle();
    expect(calls.last.queryParameters['window'], 12);
    expect(api.sockets.length, 2);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(calls.length, 6);
    session.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.length, 9);
    session.detach();
    await tester.pump();
  });
  testWidgets('late requests after detach cannot fill session cache',
      (tester) async {
    final api = FakeLotteryApi();
    final pending = <void Function()>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      pending.add(() =>
          h.resolve(Response(requestOptions: o, data: liveFixture(o.path))));
    }));
    final session = LotteryLiveSession(api, 'game2');
    session.attach();
    await tester.pump();
    session.detach();
    for (final finish in pending) {
      finish();
    }
    await tester.pumpAndSettle();
    expect(session.ready, false);
    expect(api.sockets, isEmpty);
  });
  testWidgets('socket failure falls back to HTTP and reconnects',
      (tester) async {
    final api = FakeLotteryApi();
    var count = 0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      count++;
      h.resolve(Response(requestOptions: o, data: liveFixture(o.path)));
    }));
    final session = LotteryLiveSession(api, 'game1');
    session.attach();
    await tester.pumpAndSettle();
    api.sockets.last.incoming.addError(StateError('offline'));
    await tester.pump();
    expect(session.connected, false);
    expect(session.ready, true);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(count, 6);
    expect(session.connected, true);
    session.detach();
    await tester.pump();
  });
}
