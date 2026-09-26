import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/channel_intro_page.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  EdgeInsets padding = const EdgeInsets.only(top: 59, bottom: 34),
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      platform: platform,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: padding,
        viewPadding: padding,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => ChannelIntroPage.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final screens = [
    (
      name: 'small',
      size: const Size(320, 568),
      padding: const EdgeInsets.only(top: 20),
      scale: 1.0
    ),
    (
      name: 'notch',
      size: const Size(393, 852),
      padding: const EdgeInsets.only(top: 59, bottom: 34),
      scale: 1.0
    ),
    (
      name: 'large',
      size: const Size(430, 932),
      padding: const EdgeInsets.only(top: 59, bottom: 34),
      scale: 1.0
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      padding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
      scale: 1.0
    ),
    (
      name: 'tablet',
      size: const Size(768, 1024),
      padding: const EdgeInsets.only(top: 24, bottom: 20),
      scale: 1.3
    ),
    (
      name: 'large text',
      size: const Size(320, 568),
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      scale: 2.0
    ),
  ];
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final screen in screens) {
      testWidgets(
          '${platform.name} ${screen.name}: back stays visible and tappable',
          (tester) async {
        await _openSheet(tester,
            size: screen.size,
            padding: screen.padding,
            textScale: screen.scale,
            platform: platform);
        expect(tester.takeException(), isNull);
        final sheet = tester.getRect(find.byType(ChannelIntroPage));
        final back =
            find.widgetWithIcon(TextButton, Icons.arrow_back_ios_new_rounded);
        final before = tester.getRect(back);
        expect(before.top - sheet.top, inInclusiveRange(4, 16),
            reason: 'Navigation must stay at the sheet edge on tall screens.');
        expect(before.height, greaterThanOrEqualTo(48));
        expect(before.width, greaterThanOrEqualTo(88));
        expect(before.left, greaterThanOrEqualTo(screen.padding.left + 8));

        await tester
            .ensureVisible(find.byKey(const ValueKey('channel-intro-create')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(back.hitTestable(), findsOneWidget,
            reason: 'Reading to the bottom must not scroll navigation away.');
        expect(tester.getRect(back), before);
        // Exercise the enlarged hit area, not just the visible arrow glyph.
        await tester.tapAt(before.bottomRight - const Offset(3, 3));
        await tester.pumpAndSettle();
        expect(find.byType(ChannelIntroPage), findsNothing);
        expect(find.text('open'), findsOneWidget);
      });
    }
  }

  testWidgets('system back closes the sheet and preserves the underlying page',
      (tester) async {
    await _openSheet(tester, platform: TargetPlatform.android);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChannelIntroPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('downward drag on the header still dismisses the sheet',
      (tester) async {
    await _openSheet(tester);
    final top = tester.getTopLeft(find.byType(ChannelIntroPage));
    await tester.flingFrom(
        top + const Offset(280, 28), const Offset(0, 500), 1500);
    await tester.pumpAndSettle();
    expect(find.byType(ChannelIntroPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
