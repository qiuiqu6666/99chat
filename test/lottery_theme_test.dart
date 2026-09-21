import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_drawer.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';

void main() {
  testWidgets('lottery page follows theme and preserves balls and wave colors',
      (tester) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, value, __) => MaterialApp(
        theme: value ? ThemeData.dark() : ThemeData.light(),
        home: const TestPage(),
      ),
    ));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFFF2F5F9));
    dark.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppTokens.backgroundDark);
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        AppTokens.surfaceDark);
    expect(tester.widget<Text>(find.text('京东六合彩')).style!.color,
        AppTokens.textPrimaryDark);
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(decorations.where((d) => d.color == Colors.white), isEmpty);
    for (final color in [0xFFEF2F4E, 0xFF007AFF, 0xFF00B25E]) {
      expect(decorations.any((d) => d.color == Color(color)), isTrue);
    }
    expect(decorations.any((d) => d.image?.image is AssetImage), isTrue);
    expect(
        tester
            .widgetList<Text>(find.text('48'))
            .any((t) => t.style?.color == Colors.black),
        isTrue);
    expect(find.text('遗漏'), findsNothing);
    expect(find.text('冷热'), findsNothing);
    for (final tab in ['智能预测', '已开统计']) {
      await tester.ensureVisible(find.text(tab).first);
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          tester
              .widgetList<Container>(find.byType(Container))
              .map((w) => w.decoration)
              .whereType<BoxDecoration>()
              .where((d) => d.color == Colors.white),
          isEmpty);
    }
    dark.value = false;
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        Colors.white);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dark preview shell and expansion stay dark', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () =>
                        showLotteryDrawer(context, groupUid: 'group'),
                    child: const Text('打开'),
                  ))),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final shell = tester.widget<Container>(
        find.byKey(const ValueKey('lottery-preview-card-shell')));
    expect((shell.decoration as BoxDecoration).color, AppTokens.surfaceDark);
    expect(tester.widget<Text>(find.text('点击卡片 · 全屏查看开奖记录')).style!.color,
        AppTokens.textSecondaryDark);
    await tester.tap(find.byKey(const ValueKey('lottery-preview-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final expansion = find.byKey(const ValueKey('lottery-card-expansion'));
    final material = tester.widget<Material>(
        find.descendant(of: expansion, matching: find.byType(Material)).first);
    expect(material.color, AppTokens.surfaceDark);
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        AppTokens.backgroundDark);
    await tester.pumpWidget(const SizedBox());
  });
}
