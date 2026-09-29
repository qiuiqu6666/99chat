import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_page.dart';

void main() {
  Future<void> showPage(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool dark = false,
    bool embedded = false,
    Locale locale = const Locale('zh'),
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FeedbackPage(embedded: embedded),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('feedback can be selected and submit requires meaningful text',
      (tester) async {
    await showPage(tester);
    expect(find.byKey(const ValueKey('feedback-hero')), findsOneWidget);
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('feedback-submit')))
            .onPressed,
        isNull);
    await tester.tap(find.text('错误'));
    await tester.pumpAndSettle();
    final selected = tester
        .widget<Semantics>(find.byKey(const ValueKey('feedback-type-bug')));
    expect(selected.properties.selected, isTrue);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('feedback-submit')))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '希望能增加消息搜索筛选');
    await tester.pump();
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('feedback-submit')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets(
        'feedback fits width $width with large English text and dark theme',
        (tester) async {
      await showPage(tester,
          width: width,
          scale: 2,
          dark: true,
          embedded: true,
          locale: const Locale('en'));
      expect(find.byType(AppBar), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('feedback-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
