import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets('zuhe displays combination values, actual and server result',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final data = liveFixture(o.path);
      if (o.path.endsWith('/predictions')) {
        data['data']['items'] = [
          {
            'issue': '20260921003',
            'issueLabel': '003',
            'predictionState': 'published',
            'drawState': 'drawn',
            'actual': {'zuhe': '小单'},
            'items': [
              {
                'attribute': 'special',
                'values': ['03'],
                'result': 'hit'
              },
              {
                'attribute': 'zuhe',
                'values': ['小单', '大双'],
                'result': 'hit'
              },
            ],
          }
        ];
      }
      h.resolve(Response(requestOptions: o, data: data));
    }));
    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'zuhe-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能预测'));
    await tester.pumpAndSettle();
    expect(find.text('zuhe'), findsNothing);
    expect(find.text('小单 大双'), findsOneWidget);
    final choice = find.widgetWithText(ChoiceChip, '组合');
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text('小单 大双'), findsOneWidget);
    expect(find.text('小单'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
