import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  test('settings exposes the test page entry', () {
    final settingsSource =
        File('lib/src/pages/settings/settings_page.dart').readAsStringSync();
    final testPageSource =
        File('lib/src/pages/settings/test_page.dart').readAsStringSync();

    expect(
        settingsSource,
        contains(
            "import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';"));
    expect(settingsSource, contains("zhHans: '测试页面'"));
    expect(settingsSource, contains('onTap: () => _open(const TestPage())'));
    expect(testPageSource, contains('class TestPage extends StatelessWidget'));
    expect(testPageSource, contains('class _MarkSixResult'));
    for (final label in [
      '特码',
      '生肖',
      '单双',
      '大小',
      '头数',
      '尾数',
      '合单双',
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

    expect(find.text('西湖娱乐城'), findsOneWidget);
    expect(find.text('特码'), findsWidgets);
    expect(find.text('生肖'), findsWidgets);
    expect(find.text('单双'), findsWidgets);
    expect(find.text('大小'), findsWidgets);
    expect(find.text('头数'), findsWidgets);
    expect(find.text('尾数'), findsWidgets);
    expect(find.text('合单双'), findsWidgets);
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
}
