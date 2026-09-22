import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets(
      'waiting_open with null attributes loads and follows socket states',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    final envelope = liveFixture('/draws');
    final round = <String, dynamic>{
      'issue': '202609225000',
      'issueLabel': '5000',
      'sequence': 1,
      'openAt': null,
      'closeAt': 1790029864248,
      'closedAt': 1790029864248,
      'drawAt': 1790029864248,
      'updatedAt': 1790029864248,
      'revision': 1,
      'status': 'waiting_open',
      'ruleVersion': 'rules-default-v1',
      'attributes': null,
    };
    envelope['data']['items'] = [round];
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) => h.resolve(Response(
            requestOptions: o,
            data:
                o.path.endsWith('/draws') ? envelope : liveFixture(o.path)))));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LotteryLatestPreview(gameId: 'waiting-test'))));
    await tester.pumpAndSettle();
    expect(find.text('等待开盘'), findsOneWidget);
    expect(find.text('第 0 期'), findsOneWidget);
    expect(find.text('第 5000 期'), findsNothing);
    expect(find.text('开奖数据加载失败，请重试'), findsNothing);
    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'waiting-test')));
    await tester.pumpAndSettle();
    expect(find.text('等待开盘'), findsOneWidget);
    await tester.tap(find.text('已开统计'));
    await tester.pumpAndSettle();
    expect(find.text('基本类型（0期）'), findsOneWidget);
    for (final status in ['open', 'closed']) {
      round['status'] = status;
      round['closeAt'] = null;
      api.sockets.last.send('draws', envelope);
      await tester.pumpAndSettle();
      expect(find.text(status == 'open' ? '开盘中' : '已封盘'), findsOneWidget);
      expect(find.text('基本类型（0期）'), findsOneWidget);
    }
    round['status'] = 'drawn';
    round['attributes'] =
        liveFixture('/draws')['data']['items'][1]['attributes'];
    api.sockets.last.send('draws', envelope);
    await tester.pumpAndSettle();
    expect(find.text('基本类型（1期）'), findsOneWidget);
    expect(find.text('特码 03 · 兔'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
