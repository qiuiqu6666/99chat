import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_drawer.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  var requests = 0;
  testWidgets('preview follows anchor and stays inside screen', (tester) async {
    var anchor = 400.0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () =>
              showLotteryDrawer(context, groupUid: 'group', anchorY: anchor),
          child: const Text('打开')),
    ))));
    for (final y in [400.0, 20.0, 590.0]) {
      anchor = y;
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final rect =
          tester.getRect(find.byKey(const ValueKey('lottery-latest-preview')));
      expect(rect.right, 800);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(600));
      if (y == 400) expect(rect.center.dy, 400);
      await tester.tapAt(const Offset(5, 300));
      await tester.pumpAndSettle();
    }
  });
  setUp(() {
    lotteryLiveApi = FakeLotteryApi();
    requests = 0;
    lotteryLiveApi.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(
          Response(requestOptions: options, data: liveFixture(options.path)));
    }));
  });
  tearDown(() => lotteryLiveApi.dio.interceptors.clear());
  testWidgets('white card appears while request is pending', (tester) async {
    RequestOptions? pendingOptions;
    RequestInterceptorHandler? pendingHandler;
    final delay = InterceptorsWrapper(onRequest: (options, handler) {
      if (!options.path.endsWith('/config')) {
        handler.next(options);
        return;
      }
      pendingOptions = options;
      pendingHandler = handler;
    });
    lotteryLiveApi.dio.interceptors.insert(0, delay);
    addTearDown(() => lotteryLiveApi.dio.interceptors.remove(delay));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () =>
              showLotteryDrawer(context, groupUid: '@group#1', gameId: 'game1'),
          child: const Text('打开')),
    ))));
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final shell = find.byKey(const ValueKey('lottery-preview-card-shell'));
    expect(
        (tester.widget<Container>(shell).decoration as BoxDecoration).gradient,
        isA<LinearGradient>());
    final loadingSize = tester.getSize(shell);
    expect(loadingSize.height, 160);
    final paintedTop = tester.getTopLeft(shell);
    final paintedBottom = tester.getBottomRight(shell);
    expect(paintedBottom.dy - paintedTop.dy, 160);
    expect(find.descendant(of: shell, matching: find.byType(FittedBox)),
        findsNothing);
    expect(find.descendant(of: shell, matching: find.text('点击卡片 · 全屏查看开奖记录')),
        findsOneWidget);
    expect(
        find.descendant(
            of: shell, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(find.text('最新开奖'), findsNothing);
    pendingHandler!.resolve(Response(
        requestOptions: pendingOptions!,
        data: liveFixture(pendingOptions!.path)));
    await tester.pumpAndSettle();
    expect(find.text('最新开奖'), findsOneWidget);
    final latestCard = tester
        .widget<Container>(find.byKey(const ValueKey('lottery-latest-card')));
    expect(latestCard.decoration, isNull, reason: '弹窗预览内容不应再形成第二层卡片');
    final watermark = find.byKey(const ValueKey('lottery-latest-watermark'));
    expect(watermark, findsOneWidget);
    expect(tester.widget<Image>(watermark).image,
        const AssetImage('assets/lhc/latest_card_watermark.png'));
    expect(tester.getSize(watermark), const Size(96, 96));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(shell), loadingSize);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });
  testWidgets('drawer preserves chat and passes raw group identifiers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            showLotteryDrawer(context, groupUid: '@group#1', gameId: 'game1'),
        child: const Text('聊天'),
      ),
    ))));
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('lottery-latest-preview')), findsOneWidget);
    expect(find.byType(TestPage), findsNothing);
    expect(find.text('最新开奖'), findsOneWidget);
    expect(find.text('开奖历史'), findsNothing);
    expect(find.textContaining('等待开奖'), findsNothing);
    expect(find.textContaining('距封盘'), findsNothing);
    expect(find.textContaining('开盘中'), findsNothing);
    expect(
        tester
            .getRect(find.byKey(const ValueKey('lottery-preview-open')))
            .right,
        800);
    final cardRect =
        tester.getRect(find.byKey(const ValueKey('lottery-preview-open')));
    await tester.tap(find.byKey(const ValueKey('lottery-preview-open')));
    await tester.pump();
    final expansion = find.byKey(const ValueKey('lottery-card-expansion'));
    expect(tester.getRect(expansion), cardRect);
    await tester.pump(const Duration(milliseconds: 190));
    final midway = tester.getRect(expansion);
    expect(midway.width, greaterThan(cardRect.width));
    expect(midway.width, lessThan(800));
    expect(midway.height, greaterThan(cardRect.height));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lottery-latest-preview')), findsNothing);
    final rect = tester.getRect(find.byType(TestPage));
    expect(rect.width, 800);
    expect(rect.height, 600);
    expect(find.textContaining('等待开奖'), findsNothing);
    expect(find.textContaining('距封盘'), findsNothing);
    expect(
        ModalRoute.of(tester.element(find.byType(TestPage)))!
            .reverseTransitionDuration,
        Duration.zero);
    expect(requests, 3,
        reason: 'preview and full screen share initialization and socket');
    expect(tester.widget<TestPage>(find.byType(TestPage)).groupUid, '@group#1');
    expect(tester.widget<TestPage>(find.byType(TestPage)).gameId, 'game1');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsNothing);
    expect(find.text('聊天'), findsOneWidget);
  });
}
