import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  testWidgets('group declaration is readable on a narrow screen in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, isDark, __) => MaterialApp(
        theme: isDark ? ThemeData.dark() : ThemeData.light(),
        home: const TestPage(),
      ),
    ));

    expect(find.text('京东微信红包'), findsOneWidget);
    expect(find.text('极速六合彩'), findsOneWidget);

    final tab = find.text('本群宣言');
    expect(tab, findsOneWidget);
    for (final (label, icon) in [
      ('开奖历史', Icons.history_rounded),
      ('智能预测', Icons.auto_awesome_rounded),
      ('已开统计', Icons.bar_chart_rounded),
      ('本群宣言', Icons.campaign_outlined),
    ]) {
      final button = find.ancestor(
          of: find.text(label), matching: find.byType(FilledButton));
      expect(find.descendant(of: button, matching: find.byIcon(icon)),
          findsOneWidget);
    }
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.textContaining('全天候直播开奖(用户实时亲眼所见)'), findsOneWidget);
    expect(find.text('十一年口碑！诚信经营！安全稳定！'), findsOneWidget);
    expect(tester.takeException(), isNull);

    dark.value = true;
    await tester.pumpAndSettle();
    expect(find.text('十一年口碑！诚信经营！安全稳定！'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
