import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets('predictions show 20 first and append more at the bottom',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final response = liveFixture(options.path);
      if (options.path.endsWith('/predictions')) {
        response['data']['items'] = [
          for (var index = 1; index <= 45; index++)
            {
              'issue': '20260923${index.toString().padLeft(3, '0')}',
              'issueLabel': index.toString().padLeft(3, '0'),
              'predictionState': 'published',
              'drawState': 'pending',
              'actual': null,
              'items': [
                {
                  'attribute': 'special',
                  'values': ['01'],
                  'result': 'pending',
                }
              ],
            },
        ];
      }
      handler.resolve(Response(requestOptions: options, data: response));
    }));

    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'paging-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能预测'));
    await tester.pumpAndSettle();
    expect(find.text('最近 40 期'), findsNothing);
    expect(find.text('第 020 期'), findsOneWidget);
    expect(find.text('第 021 期'), findsNothing);
    expect(find.text('开奖时间：待公布'), findsWidgets);

    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('第 021 期'), findsOneWidget);
    expect(find.text('第 041 期'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('第 041 期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
