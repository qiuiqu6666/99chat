import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  test('settings hides the test page entry while retaining lottery page', () {
    final settingsSource =
        File('lib/src/pages/settings/settings_page.dart').readAsStringSync();
    final testPageSource =
        File('lib/src/pages/settings/test_page.dart').readAsStringSync();

    expect(
        settingsSource,
        isNot(contains(
            "import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';")));
    expect(settingsSource, isNot(contains("zhHans: '测试页面'")));
    expect(settingsSource,
        isNot(contains('onTap: () => _open(const TestPage())')));
    expect(testPageSource, contains('class TestPage extends StatelessWidget'));
    expect(testPageSource, contains('class _MarkSixResult'));
    expect(testPageSource, contains('class _ResultTable'));
    expect(testPageSource, contains('required this.specialNumber'));
    expect(testPageSource, contains('required this.zodiac'));
    for (final label in [
      '时间',
      '期号',
      '特',
      '单双',
      '大小',
      '头',
      '尾',
      '合',
      '五行',
      '波色'
    ]) {
      expect(testPageSource, contains("'$label'"));
    }
    expect(testPageSource, isNot(contains('下一期开奖时间')));
    expect(testPageSource, isNot(contains('09月22日 21点33分')));
    expect(testPageSource, isNot(contains('加拿大28')));
    expect(testPageSource, isNot(contains('香港六合彩')));
    expect(testPageSource, isNot(contains('智能预测')));
    expect(testPageSource, isNot(contains('遗漏查询')));
  });

  testWidgets('test page renders at a compact phone width without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: TestPage()));
    await tester.pump();

    expect(find.text('京东微信红包'), findsOneWidget);
    expect(find.text('极速六合彩'), findsOneWidget);
    expect(find.text('开奖记录'), findsNothing);
    expect(find.text('期号'), findsOneWidget);
    final tabLabels = ['开奖历史', '预测', '遗漏', '冷热'];
    for (var i = 0; i < tabLabels.length - 1; i++) {
      expect(tester.getCenter(find.text(tabLabels[i])).dx,
          lessThan(tester.getCenter(find.text(tabLabels[i + 1])).dx));
    }
    expect(find.text('演示数据 · 未接入实时开奖'), findsNothing);
    await tester.tap(find.text('遗漏'));
    await tester.pump();
    expect(find.text('当前遗漏'), findsOneWidget);
    expect(find.text('实际样本'), findsNothing);
    expect(find.text('当前最大遗漏'), findsNothing);
    expect(find.text('样本内未开'), findsNothing);
    expect(find.text('长龙排行'), findsOneWidget);
    await tester.tap(find.text('冷热'));
    await tester.pump();
    expect(find.text('冷热分布'), findsOneWidget);
    expect(find.text('最高频次'), findsNothing);
    expect(find.text('最低频次'), findsNothing);
    expect(find.text('样本内未开'), findsNothing);
    expect(find.text('热号优先'), findsOneWidget);
    expect(find.text('冷号优先'), findsOneWidget);
    await tester.tap(find.text('开奖历史'));
    await tester.pump();
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('期号'), findsOneWidget);
    expect(find.text('特'), findsOneWidget);
    expect(find.text('单双'), findsWidgets);
    expect(find.text('大小'), findsWidgets);
    expect(find.text('头'), findsWidgets);
    expect(find.text('尾'), findsWidgets);
    expect(find.text('合'), findsWidgets);
    expect(find.text('波色'), findsWidgets);
    expect(find.text('五行'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('test page uses the standard settings back button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TestPage()),
          ),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('dragon groups separate opened and missing streaks',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: TestPage()));
    await tester.tap(find.text('遗漏'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '长龙排行'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dragon-special-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('dragon-special-48')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '已开'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dragon-special-48')), findsOneWidget);
    expect(find.byKey(const ValueKey('dragon-special-01')), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '其他属性长龙'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dragon-special-48')), findsNothing);
    expect(find.text('生肖 羊'), findsOneWidget);
    expect(find.text('生肖 鼠'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '未开'));
    await tester.pump();
    expect(find.text('生肖 羊'), findsNothing);
    expect(find.text('生肖 鼠'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting an attribute exits combined prediction',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TestPage()));
    await tester.tap(find.text('智能预测'));
    await tester.pump();
    expect(find.text('每期同时预测 9 项，分别核对开奖结果'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '单双'));
    await tester.pump();
    expect(find.text('单双 · 每期以前 40 期的最高频项作为预测'), findsOneWidget);
    expect(find.text('每期同时预测 9 项，分别核对开奖结果'), findsNothing);
    await tester.tap(find.text('综合预测 · 全部属性'));
    await tester.pump();
    expect(find.text('每期同时预测 9 项，分别核对开奖结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
