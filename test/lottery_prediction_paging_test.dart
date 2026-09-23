import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

Map<String, dynamic> predictionRow(int index) => {
      'issue': '20260923${index.toString().padLeft(3, '0')}',
      'issueLabel': index.toString().padLeft(3, '0'),
      'predictionState': 'published',
      'drawState': 'pending',
      'actual': null,
      'items': [
        {
          'attribute': 'special',
          'values': ['01'],
          'result': 'pending',
        }
      ],
    };

void main() {
  testWidgets('predictions show 20 first and append more at the bottom',
      (tester) async {
    final requestedPages = <int>[];
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final response = liveFixture(options.path);
      if (options.path.endsWith('/predictions')) {
        final page = options.queryParameters['page'] as int;
        expect(options.queryParameters['pageSize'], 20);
        expect(options.queryParameters.containsKey('limit'), isFalse);
        requestedPages.add(page);
        response['data']['items'] = [
          for (var index = (page - 1) * 20 + 1;
              index <= page * 20 && index <= 45;
              index++)
            predictionRow(index),
        ];
      }
      handler.resolve(Response(requestOptions: options, data: response));
    }));

    await tester
        .pumpWidget(const MaterialApp(home: TestPage(gameId: 'paging-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能预测'));
    await tester.pumpAndSettle();
    expect(requestedPages, [1]);
    expect(find.text('最近 40 期'), findsNothing);
    expect(find.text('第 020 期'), findsOneWidget);
    expect(find.text('第 021 期'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(requestedPages, [1, 2]);
    expect(find.text('第 021 期'), findsOneWidget);
    expect(find.text('第 041 期'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(requestedPages, [1, 2, 3]);
    expect(find.text('第 041 期'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(requestedPages, [1, 2, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed prediction page preserves results and retries',
      (tester) async {
    final previous = lotteryLiveApi;
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    addTearDown(() {
      lotteryLiveApi = previous;
      api.dio.close();
    });
    var secondPageCalls = 0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final response = liveFixture(options.path);
      if (options.path.endsWith('/predictions')) {
        final page = options.queryParameters['page'] as int;
        if (page == 2 && ++secondPageCalls == 1) {
          handler.reject(DioError(
              requestOptions: options,
              type: DioErrorType.other,
              error: 'offline'));
          return;
        }
        response['data']['items'] = [
          for (var index = (page - 1) * 20 + 1;
              index <= page * 20 && index <= 25;
              index++)
            predictionRow(index),
        ];
      }
      handler.resolve(Response(requestOptions: options, data: response));
    }));

    await tester.pumpWidget(
        const MaterialApp(home: TestPage(gameId: 'paging-retry-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能预测'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('第 020 期'), findsOneWidget);
    expect(find.text('第 021 期'), findsNothing);
    await tester.tap(find.text('预测加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('第 021 期'), findsOneWidget);
    expect(secondPageCalls, 2);
    expect(find.text('预测加载失败，点击重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
