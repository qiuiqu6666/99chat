import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/group_settings_tile.dart';
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
    expect(find.text('数据分析 · 智能推荐'), findsOneWidget);
    expect(find.text('基于历史数据，AI智能分析仅供参考'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('prediction-combined-panel')))
            .height,
        lessThan(62));
    await tester.tap(find.byType(GroupSettingsSwitch));
    await tester.pumpAndSettle();
    expect(find.text('已关闭'), findsOneWidget);
    await tester.tap(find.byType(GroupSettingsSwitch));
    await tester.pumpAndSettle();
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('开奖时间：09-21 23:49'), findsOneWidget);
    expect(find.textContaining('预计开盘时间：'), findsNothing);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '特码'))
            .selectedColor,
        const Color(0xFF328BFA));
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
