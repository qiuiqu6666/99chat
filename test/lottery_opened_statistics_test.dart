import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  testWidgets('opened counts exclude closed rounds and use returned attributes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final data = liveFixture(o.path);
      if (o.path.endsWith('/draws')) {
        data['data']['items'][1]['attributes']['size'] = '大';
      }
      h.resolve(Response(requestOptions: o, data: data));
    }));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(), home: const TestPage(gameId: 'opened-test')));
    await tester.pumpAndSettle();
    expect(find.text('智能预测'), findsOneWidget);
    expect(find.text('预测'), findsNothing);
    await tester.tap(find.text('已开统计'));
    await tester.pumpAndSettle();
    expect(find.text('基本类型（1期）'), findsOneWidget);
    for (final entry in {
      '单双-单': '1',
      '单双-双': '0',
      '大小-大': '1',
      '大小-小': '0',
      '组合-大单': '1',
      '组合-小单': '0',
      '波色-蓝': '1',
      '波色-红': '0'
    }.entries) {
      final finder = find.byKey(ValueKey('opened-${entry.key}'));
      await tester.ensureVisible(finder);
      expect(tester.widget<Text>(finder).data, entry.value);
    }
    final rabbit = find.byKey(const ValueKey('opened-生肖-兔'));
    await tester.ensureVisible(rabbit);
    expect(tester.widget<Text>(rabbit).data, '1');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
