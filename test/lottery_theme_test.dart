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
        const Color(0xFFF3F8FF));
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 52);
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        const Color(0xFFF4F9FF));
    expect(tester.widget<Text>(find.text('京东微信红包')).style!.fontWeight,
        FontWeight.w800);
    final watermark = find.byKey(const ValueKey('lottery-latest-watermark'));
    expect(watermark, findsOneWidget);
    expect(tester.widget<Image>(watermark).image,
        const AssetImage('assets/lhc/latest_card_watermark.png'));
    expect(tester.getSize(watermark), const Size(96, 96));
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(
                  of: watermark,
                  matching: find.byType(Opacity),
                )
                .first)
            .opacity,
        0.20);
    final latestCard = tester
        .widget<Container>(find.byKey(const ValueKey('lottery-latest-card')));
    expect((latestCard.decoration as BoxDecoration).gradient,
        isA<LinearGradient>());
    expect(
        ((latestCard.decoration as BoxDecoration).gradient! as LinearGradient)
            .colors,
        [const Color(0xFFFAFCFF), const Color(0xFFF0F6FF)]);
    dark.value = true;
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Opacity>(find
                .ancestor(
                  of: watermark,
                  matching: find.byType(Opacity),
                )
                .first)
            .opacity,
        0.14);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppTokens.backgroundDark);
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        AppTokens.surfaceDark);
    expect(tester.widget<Text>(find.text('京东微信红包')).style!.color,
        AppTokens.textPrimaryDark);
    expect(tester.widget<Text>(find.text('极速六合彩')).style!.color,
        AppTokens.textSecondaryDark);
    expect(tester.widget<Text>(find.text('京东微信红包')).style!.fontSize,
        greaterThan(tester.widget<Text>(find.text('极速六合彩')).style!.fontSize!));
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
        const Color(0xFFF4F9FF));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lottery header and latest card stay compact on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: TestPage()));

    expect(
        tester
            .getSize(find.byKey(const ValueKey('lottery-latest-card')))
            .height,
        lessThan(150));
    expect(tester.getSize(find.byKey(const ValueKey('lottery-tab-bar'))).height,
        lessThan(42));
    expect(tester.takeException(), isNull);
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
    expect(
        ((shell.decoration as BoxDecoration).gradient! as LinearGradient)
            .colors,
        [AppTokens.surfaceDark, AppTokens.surfaceDark]);
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
