import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'lottery_live_fixture.dart';

final _sessionsToDetach = <LotteryLiveSession>[];

void _pagingTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final session in _sessionsToDetach) {
        if (session.active) session.detach();
      }
      _sessionsToDetach.clear();
      await tester.pump();
    }
  });
}

class _PagingHarness {
  _PagingHarness({this.totalCount = 45, bool autoLoadPredictions = false}) {
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.endsWith('/predictions')) {
        calls.add(options);
        if (onPrediction?.call(options, handler) ?? false) return;
      }
      handler
          .resolve(Response(requestOptions: options, data: response(options)));
    }));
    session = LotteryLiveSession(api, 'machine',
        autoLoadPredictions: autoLoadPredictions);
    _sessionsToDetach.add(session);
    addTearDown(() {
      if (session.active) session.detach();
      api.dio.close();
    });
  }

  final api = FakeLotteryApi();
  late final LotteryLiveSession session;
  final calls = <RequestOptions>[];
  int totalCount;
  int generation = 0;
  String mode = 'published';
  bool Function(RequestOptions, RequestInterceptorHandler)? onPrediction;

  List<int> get subsequentPages => calls
      .map((request) => request.queryParameters['page'] as int)
      .where((page) => page > 1)
      .toList();

  Map<String, dynamic> response(RequestOptions request) =>
      request.path.endsWith('/predictions')
          ? predictionPageFixture(
              window: request.queryParameters['window'] as int? ?? 40,
              page: request.queryParameters['page'] as int? ?? 1,
              totalCount: totalCount,
              generation: generation,
              mode: mode,
            )
          : liveFixture(request.path);

  Map<String, dynamic> get firstPage => predictionPageFixture(
      window: session.window,
      totalCount: totalCount,
      generation: generation,
      mode: mode);

  Future<void> start(WidgetTester tester) async {
    session.attach();
    await tester.pumpAndSettle();
    expect(session.ready, isTrue);
  }
}

class _PendingPage {
  _PendingPage(this.options, this.handler, this.body);
  final RequestOptions options;
  final RequestInterceptorHandler handler;
  final Map<String, dynamic> body;

  void resolve() =>
      handler.resolve(Response(requestOptions: options, data: body));

  void reject() => handler.reject(DioError(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 503),
      type: DioErrorType.response));
}

void main() {
  _pagingTest('automatic loading refills after a new published head',
      (tester) async {
    final h = _PagingHarness(totalCount: 100, autoLoadPredictions: true);
    await h.start(tester);
    expect(h.session.predictions, hasLength(100));
    expect(h.subsequentPages, [2, 3, 4, 5]);
    h.generation = 1;
    h.totalCount = 35;
    h.api.sockets.last.send('predictions', h.firstPage);
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(35));
    expect(h.session.predictionsHasMore, isFalse);
    expect(h.subsequentPages, [2, 3, 4, 5, 2]);
    h.totalCount = 100;
    h.generation = 2;
    h.session.selectWindow(12);
    await tester.pumpAndSettle();
    expect(h.session.window, 12);
    expect(h.session.predictions, hasLength(100));
    expect(h.session.predictionsHasMore, isFalse);
    expect(h.session.predictions.first['predictionId'], 'prediction-2-1');
  });

  _pagingTest('hasMore alone controls whether another page is requested',
      (tester) async {
    final h = _PagingHarness(totalCount: 35);
    h.onPrediction = (options, handler) {
      final body = h.response(options);
      body['data']['hasMore'] = false;
      handler.resolve(Response(requestOptions: options, data: body));
      return true;
    };
    await h.start(tester);
    expect(h.session.predictionTotalCount, 35);
    expect(h.session.predictions, hasLength(20));
    expect(h.session.predictionsHasMore, isFalse);
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.calls, hasLength(1));
  });

  _pagingTest('server pages append 20, 40, 45 and WS preserves terminal state',
      (tester) async {
    final h = _PagingHarness();
    await h.start(tester);
    expect(h.session.predictions, hasLength(20));
    expect(h.session.predictionPage, 1);
    expect(h.session.predictionTotalCount, 45);
    expect(h.session.predictionsHasMore, isTrue);

    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(40));
    expect(h.session.predictionPage, 2);
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(45));
    expect(h.session.predictionPage, 3);
    expect(h.session.predictionsHasMore, isFalse);
    expect(h.subsequentPages, [2, 3]);
    expect(h.session.predictions.last['sequence'], 9955);
    expect(h.session.predictions.last['issue'], '20260921045');

    final settled = h.firstPage;
    settled['data']['snapshotId'] = 'a-new-snapshot-for-the-same-predictions';
    settled['data']['items'][0]['items'][0]['result'] = 'hit';
    h.api.sockets.last.send('predictions', settled);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.session.predictions.first['items'][0]['result'], 'hit');
    expect(h.session.predictions, hasLength(45));
    expect(h.session.predictionPage, 3);
    expect(h.session.predictionsHasMore, isFalse);
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.subsequentPages, [2, 3]);
  });

  _pagingTest('duplicate loading is guarded and failures retry the same page',
      (tester) async {
    final h = _PagingHarness(totalCount: 35);
    await h.start(tester);
    final pending = <_PendingPage>[];
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 2) return false;
      pending.add(_PendingPage(options, handler, h.response(options)));
      return true;
    };
    h.session.loadMorePredictions();
    h.session.loadMorePredictions();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending, hasLength(1));
    expect(h.session.predictionsLoadingMore, isTrue);
    expect(h.session.predictionPage, 1);
    pending.single.reject();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(20));
    expect(h.session.predictionPage, 1);
    expect(h.session.predictionsLoadingMore, isFalse);
    expect(h.session.predictionsPageError, isNotNull);
    expect(h.session.error, isNull);
    h.session.loadMorePredictions();
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.session.predictionsPageError, isNull);
    expect(pending, hasLength(2));
    pending.last.resolve();
    await tester.pumpAndSettle();
    expect(h.subsequentPages, [2, 2]);
    expect(h.session.predictions, hasLength(35));
    expect(h.session.predictionPage, 2);
    expect(h.session.predictionsHasMore, isFalse);
  });

  for (final action in ['window', 'refresh', 'detach']) {
    _pagingTest('$action discards an in-flight page response', (tester) async {
      final h = _PagingHarness();
      await h.start(tester);
      late _PendingPage pending;
      h.onPrediction = (options, handler) {
        if (options.queryParameters['page'] != 2) return false;
        pending = _PendingPage(options, handler, h.response(options));
        return true;
      };
      h.session.loadMorePredictions();
      await tester.pump(const Duration(milliseconds: 100));
      switch (action) {
        case 'window':
          h.session.selectWindow(12);
        case 'refresh':
          h.session.refresh();
        case 'detach':
          h.session.detach();
      }
      await tester.pumpAndSettle();
      pending.resolve();
      await tester.pumpAndSettle();
      expect(h.session.predictions, hasLength(20));
      expect(h.session.predictionPage, 1);
      expect(h.session.predictionsLoadingMore, isFalse);
      expect(h.session.predictionsPageError, isNull);
      if (action == 'window') {
        expect(h.session.window, 12);
        expect(h.calls.last.queryParameters['window'], 12);
        expect(h.calls.last.queryParameters['page'], 1);
      }
    });
  }

  _pagingTest(
      'WS head replacement invalidates old work without clearing new loading',
      (tester) async {
    final h = _PagingHarness();
    await h.start(tester);
    final pending = <_PendingPage>[];
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 2) return false;
      pending.add(_PendingPage(options, handler, h.response(options)));
      return true;
    };
    h.session.loadMorePredictions();
    await tester.pump(const Duration(milliseconds: 100));
    h.generation++;
    h.api.sockets.last.send('predictions', h.firstPage);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.session.predictions.first['predictionId'], 'prediction-1-1');
    expect(h.session.predictionsLoadingMore, isFalse);
    h.session.loadMorePredictions();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending, hasLength(2));
    pending.first.reject();
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.session.predictionsLoadingMore, isTrue);
    expect(h.session.predictionsPageError, isNull);
    pending.last.resolve();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(40));
    expect(h.session.predictionsLoadingMore, isFalse);
    expect(h.session.predictions.last['predictionId'], 'prediction-1-40');
  });

  for (final change in ['total', 'mode']) {
    _pagingTest('WS $change changes reset previously loaded history',
        (tester) async {
      final h = _PagingHarness();
      await h.start(tester);
      h.session.loadMorePredictions();
      await tester.pumpAndSettle();
      expect(h.session.predictions, hasLength(40));
      if (change == 'total') {
        h.totalCount = 35;
      } else {
        h.mode = 'backtest';
      }
      h.api.sockets.last.send('predictions', h.firstPage);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.session.predictions, hasLength(20));
      expect(h.session.predictionPage, 1);
      expect(h.session.predictionTotalCount, h.totalCount);
      expect(h.session.predictionMode, h.mode);
    });
  }

  _pagingTest(
      'sequential first-page probe detects a new cycle with equal count',
      (tester) async {
    final h = _PagingHarness(totalCount: 100);
    await h.start(tester);
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 2) return false;
      final oldPage = h.response(options);
      h.generation++;
      handler.resolve(Response(requestOptions: options, data: oldPage));
      return true;
    };
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.calls.map((r) => r.queryParameters['page']), [1, 2, 1]);
    expect(h.session.predictions, hasLength(20));
    expect(h.session.predictionPage, 1);
    expect(h.session.predictions.first['predictionId'], 'prediction-1-1');
    expect(h.session.predictionsPageError, isNull);
    expect(h.session.predictionsLoadingMore, isFalse);
  });

  _pagingTest(
      'cleared cycle returns empty data without filling from prior cycle',
      (tester) async {
    final h = _PagingHarness();
    await h.start(tester);
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 2) return false;
      h.totalCount = 0;
      handler.resolve(
          Response(requestOptions: options, data: h.response(options)));
      return true;
    };
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.session.predictions, isEmpty);
    expect(h.session.predictionPage, 1);
    expect(h.session.predictionTotalCount, 0);
    expect(h.session.predictionsHasMore, isFalse);
    expect(h.session.predictionsLoadingMore, isFalse);
    final previousCalls = h.calls.length;
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.calls, hasLength(previousCalls));
  });

  _pagingTest(
      'first-page HTTP probe applies settlement when no WS update arrived',
      (tester) async {
    final h = _PagingHarness();
    await h.start(tester);
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 1) return false;
      final settled = h.response(options);
      settled['data']['items'][0]['items'][0]['result'] = 'hit';
      handler.resolve(Response(requestOptions: options, data: settled));
      return true;
    };
    h.session.loadMorePredictions();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(40));
    expect(h.session.predictions.first['items'][0]['result'], 'hit');
    expect(h.session.predictionPage, 2);
  });

  _pagingTest('first-page HTTP probe cannot overwrite newer WS settlement',
      (tester) async {
    final h = _PagingHarness();
    await h.start(tester);
    late _PendingPage probe;
    h.onPrediction = (options, handler) {
      if (options.queryParameters['page'] != 1) return false;
      probe = _PendingPage(options, handler, h.response(options));
      return true;
    };
    h.session.loadMorePredictions();
    await tester.pump(const Duration(milliseconds: 100));
    final settled = h.firstPage;
    settled['data']['items'][0]['items'][0]['result'] = 'hit';
    h.api.sockets.last.send('predictions', settled);
    await tester.pump(const Duration(milliseconds: 100));
    probe.resolve();
    await tester.pumpAndSettle();
    expect(h.session.predictions, hasLength(40));
    expect(h.session.predictions.first['items'][0]['result'], 'hit');
  });

  for (final invalid in ['group', 'window', 'page', 'returnedCount']) {
    _pagingTest('invalid $invalid on an appended page preserves prior data',
        (tester) async {
      final h = _PagingHarness();
      await h.start(tester);
      h.onPrediction = (options, handler) {
        if (options.queryParameters['page'] != 2) return false;
        final body = h.response(options);
        if (invalid == 'group') {
          body['groupUid'] = 'another-instance';
        } else {
          body['data'][invalid] = invalid == 'window' ? 12 : 1;
        }
        handler.resolve(Response(requestOptions: options, data: body));
        return true;
      };
      h.session.loadMorePredictions();
      await tester.pumpAndSettle();
      expect(h.session.predictions, hasLength(20));
      expect(h.session.predictionPage, 1);
      expect(h.session.predictionsHasMore, isTrue);
      expect(h.session.predictionsPageError, isNotNull);
      expect(h.session.predictionsLoadingMore, isFalse);
    });
  }
}
