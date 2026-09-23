import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets('loaded draws do not show a session error banner',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });

    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(
          Response(requestOptions: options, data: liveFixture(options.path)));
    }));

    await tester.pumpWidget(
        const MaterialApp(home: TestPage(gameId: 'error-banner-test')));
    await tester.pumpAndSettle();
    expect(find.text('最新开奖'), findsOneWidget);

    final session = lotteryLiveSession('error-banner-test');
    session.error = '开奖数据加载失败，请重试';
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(session.error, '开奖数据加载失败，请重试');
    expect(find.text('开奖数据加载失败，请重试'), findsNothing);
    expect(find.text('最新开奖'), findsOneWidget);
  });
}
