import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

void main() {
  for (final total in [0, 35, 100]) {
    testWidgets('automatically shows all $total predictions without scrolling',
        (tester) async {
      final previous = lotteryLiveApi;
      final api = FakeLotteryApi();
      final pages = <int>[];
      lotteryLiveApi = api;
      addTearDown(() {
        lotteryLiveApi = previous;
        api.dio.close();
      });
      api.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) {
        final prediction = options.path.endsWith('/predictions');
        final page = options.queryParameters['page'] as int? ?? 1;
        if (prediction) pages.add(page);
        handler.resolve(Response(
            requestOptions: options,
            data: prediction
                ? predictionPageFixture(page: page, totalCount: total)
                : liveFixture(options.path)));
      }));
      final machine = 'all-predictions-$total';
      await tester.pumpWidget(MaterialApp(home: TestPage(gameId: machine)));
      await tester.pumpAndSettle();
      expect(lotteryLiveSession(machine).predictions, hasLength(total));
      expect(lotteryLiveSession(machine).predictionsHasMore, isFalse);
      expect(pages.where((page) => page > 1),
          [for (var page = 2; page <= (total / 20).ceil(); page++) page]);
      await tester.tap(find.text('智能预测'));
      await tester.pumpAndSettle();
      if (total > 0) {
        expect(find.text('第 ${total.toString().padLeft(3, '0')} 期'),
            findsOneWidget);
      }
      expect(find.text('继续滑动加载更多'), findsNothing);
      final requests = pages.length;
      await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(pages.length, requests);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('automatic loading keeps failed page and retries to the end',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    final pageTwo = <RequestOptions>[];
    final handlers = <RequestInterceptorHandler>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final prediction = options.path.endsWith('/predictions');
      final page = options.queryParameters['page'] as int? ?? 1;
      if (prediction && page == 2) {
        pageTwo.add(options);
        handlers.add(handler);
        return;
      }
      handler.resolve(Response(
          requestOptions: options,
          data: prediction
              ? predictionPageFixture(page: page, totalCount: 35)
              : liveFixture(options.path)));
    }));
    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'paging-retry')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('智能预测'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.byKey(const ValueKey('prediction-page-loading')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(handlers, hasLength(1));
    handlers.single.reject(DioError(
        requestOptions: pageTwo.single,
        response: Response(requestOptions: pageTwo.single, statusCode: 503),
        type: DioErrorType.response));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prediction-page-error')), findsOneWidget);
    expect(lotteryLiveSession('paging-retry').predictions, hasLength(20));
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(handlers, hasLength(1));
    final retry = find.byKey(const ValueKey('prediction-page-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump(const Duration(milliseconds: 100));
    expect(handlers, hasLength(2));
    handlers.last.resolve(Response(
        requestOptions: pageTwo.last,
        data: predictionPageFixture(page: 2, totalCount: 35)));
    await tester.pumpAndSettle();
    expect(lotteryLiveSession('paging-retry').predictions, hasLength(35));
    expect(find.byKey(const ValueKey('prediction-page-error')), findsNothing);
    expect(find.byKey(const ValueKey('prediction-page-end')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching instance discards the old pending page',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    late RequestOptions oldRequest;
    late RequestInterceptorHandler oldHandler;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final prediction = options.path.endsWith('/predictions');
      final page = options.queryParameters['page'] as int? ?? 1;
      final newInstance =
          options.queryParameters['machineCode'] == 'paging-new';
      if (prediction && page == 2 && !newInstance) {
        oldRequest = options;
        oldHandler = handler;
        return;
      }
      final body = prediction
          ? predictionPageFixture(page: page, generation: newInstance ? 1 : 0)
          : liveFixture(options.path);
      body['groupUid'] = newInstance ? 'new-group' : 'old-group';
      handler.resolve(Response(requestOptions: options, data: body));
    }));
    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'paging-old')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('智能预测'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(lotteryLiveSession('paging-old').predictionsLoadingMore, isTrue);
    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'paging-new')));
    await tester.pumpAndSettle();
    final oldBody = predictionPageFixture(page: 2);
    oldBody['groupUid'] = 'old-group';
    oldHandler.resolve(Response(requestOptions: oldRequest, data: oldBody));
    await tester.pumpAndSettle();
    final current = lotteryLiveSession('paging-new');
    expect(current.groupUid, 'new-group');
    expect(current.predictions, hasLength(45));
    expect(current.predictionPage, 3);
    expect(current.predictions.first['predictionId'], 'prediction-1-1');
    expect(lotteryLiveSession('paging-old').active, isFalse);
    expect(lotteryLiveSession('paging-old').predictions, hasLength(20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
