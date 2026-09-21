import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets('status below issue updates with socket in preview and full page',
      (tester) async {
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) =>
            h.resolve(Response(requestOptions: o, data: liveFixture(o.path)))));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                child: LotteryLatestPreview(gameId: 'status-machine')))));
    await tester.pumpAndSettle();
    expect(find.text('已封盘'), findsOneWidget);
    final issue = tester.getRect(find.text('第 003 期'));
    final status =
        tester.getRect(find.byKey(const ValueKey('lottery-current-status')));
    expect(status.top, greaterThanOrEqualTo(issue.bottom));
    expect(status.right, closeTo(issue.right, .1));
    final update = liveFixture('/draws');
    update['data']['items'][0]['status'] = 'open';
    api.sockets.last.send('draws', update);
    await tester.pump();
    await tester.pump();
    expect(find.text('开盘中'), findsOneWidget);
    expect(find.text('已封盘'), findsNothing);
    update['data']['items'][0]['closeAt'] =
        (update['serverTime'] as int) + 35000;
    api.sockets.last.send('draws', update);
    await tester.pump();
    await tester.pump();
    expect(find.text('距封盘 00:35'), findsOneWidget);
    update['serverTime'] = (update['serverTime'] as int) + 1000;
    api.sockets.last.send('heartbeat', update);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('距封盘 00:34'), findsOneWidget);
    update['serverTime'] = update['data']['items'][0]['closeAt'];
    api.sockets.last.send('heartbeat', update);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('封盘待确认'), findsOneWidget);
    await tester.pumpWidget(
        const MaterialApp(home: TestPage(gameId: 'status-machine')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('lottery-current-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
