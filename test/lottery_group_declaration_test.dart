import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  testWidgets('group declaration is readable on a narrow screen in both themes',
      (tester) async {
    const downloadUrl = 'https://example.com/download-app';
    final contactInterceptor = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/api/v1/platform/contact') {
        handler.resolve(Response(
          requestOptions: options,
          data: {'downloadUrl': downloadUrl},
        ));
        return;
      }
      handler.next(options);
    });
    ApiClient.instance.dio.interceptors.add(contactInterceptor);
    addTearDown(
        () => ApiClient.instance.dio.interceptors.remove(contactInterceptor));
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
    Color tabBarColor() => (tester
            .widget<Container>(find.byKey(const ValueKey('lottery-tab-bar')))
            .decoration as BoxDecoration)
        .color!;
    expect(tabBarColor(), const Color(0xFFF0F6FF));
    expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('lottery-tab-bar')))
            .padding,
        const EdgeInsets.all(2));

    final tab = find.text('本群宣言');
    expect(tab, findsOneWidget);
    for (final (label, icon) in [
      ('开奖历史', Icons.access_time_rounded),
      ('智能预测', Icons.auto_awesome_rounded),
      ('已开统计', Icons.bar_chart_rounded),
    ]) {
      final button = find.ancestor(
          of: find.text(label), matching: find.byType(FilledButton));
      expect(find.descendant(of: button, matching: find.byIcon(icon)),
          findsOneWidget);
    }
    final declarationTabIcon =
        find.byKey(const ValueKey('lottery-declaration-tab-icon'));
    expect(declarationTabIcon, findsOneWidget);
    expect(tester.widget<Image>(declarationTabIcon).image,
        const AssetImage('assets/lhc/declaration_megaphone.png'));
    BoxDecoration tabBackground(int index) => tester
        .widget<DecoratedBox>(
            find.byKey(ValueKey('lottery-tab-background-$index')))
        .decoration as BoxDecoration;
    expect(tabBackground(3).gradient, isA<LinearGradient>());
    expect(tabBackground(5).gradient, isNull);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(tabBackground(3).gradient, isNull);
    expect(tabBackground(5).gradient, isA<LinearGradient>());
    expect(find.textContaining('全天候直播开奖(用户实时亲眼所见)'), findsOneWidget);
    expect(find.textContaining('公开发包！无任何套路！\n杜绝一切不透明开奖！'), findsOneWidget);
    expect(find.text('十一年口碑！诚信经营！安全稳定！'), findsOneWidget);
    expect(find.text('下载 App'), findsOneWidget);
    expect(find.byKey(const ValueKey('lottery-app-download-link')),
        findsOneWidget);
    expect(find.text(downloadUrl), findsOneWidget);
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text']?.toString();
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final downloadLink =
        find.byKey(const ValueKey('lottery-app-download-link'));
    await tester.ensureVisible(downloadLink);
    await tester.tap(downloadLink);
    await tester.pump();
    expect(copiedText, downloadUrl);
    expect(find.text('真实 · 公平 · 安全 · 稳定'), findsOneWidget);
    final declarationHeaderIcon =
        find.byKey(const ValueKey('lottery-declaration-header-icon'));
    expect(declarationHeaderIcon, findsOneWidget);
    expect(tester.widget<Image>(declarationHeaderIcon).image,
        tester.widget<Image>(declarationTabIcon).image);
    final subtitleRect = tester.getRect(find.text('真实 · 公平 · 安全 · 稳定'));
    final quoteRect =
        tester.getRect(find.byKey(const ValueKey('lottery-declaration-quote')));
    expect((subtitleRect.right - quoteRect.right).abs(), lessThan(20));
    expect(find.text('公平公开 · 真实可靠'), findsOneWidget);
    final quote = tester.widget<Container>(
        find.byKey(const ValueKey('lottery-declaration-quote')));
    expect((quote.decoration as BoxDecoration).color, const Color(0xFFF2F8FF));
    expect(tester.takeException(), isNull);

    dark.value = true;
    await tester.pumpAndSettle();
    expect(tabBarColor(), isNot(const Color(0xFFF0F6FF)));
    expect(find.text('十一年口碑！诚信经营！安全稳定！'), findsOneWidget);
    final darkQuote = tester.widget<Container>(
        find.byKey(const ValueKey('lottery-declaration-quote')));
    expect((darkQuote.decoration as BoxDecoration).color,
        isNot(const Color(0xFFF2F8FF)));
    expect(tester.takeException(), isNull);
  });
}
