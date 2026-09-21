import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_statistics.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'lottery_live_fixture.dart';

Map<String, dynamic> stats(String attribute,
        {String snapshot = 's1', int window = 40}) =>
    {
      'snapshotId': snapshot,
      'window': window,
      'sampleCount': 0,
      'sampleComplete': true,
      'basisIssue': null,
      'items': List.generate(
          LotteryStatistics.candidateCounts[attribute]!,
          (i) => {
                'value':
                    attribute == 'special' ? '${i + 1}'.padLeft(2, '0') : '$i',
                'order': i,
                'count': 0,
                'ratio': 0.0,
                'temperature': 'unknown',
                'omission': {'periods': 0, 'isLowerBound': true},
              }),
    };
Map<String, dynamic> envelope(dynamic data) => {
      'code': 'OK',
      'groupUid': 'resolved-player-group',
      'serverTime': 1790005751631,
      'data': data
    };
void main() {
  test('empty samples preserve all candidates; partial collections rejected',
      () {
    expect(
        LotteryStatistics.parse(stats('special'), 'special', 40).items.length,
        49);
    expect(() => LotteryStatistics.parse(stats('wave'), 'special', 40),
        throwsFormatException);
  });
  test('snapshot expiry retries overview once and websocket wins late HTTP',
      () async {
    final api = FakeLotteryApi();
    var overviews = 0;
    var requests = 0;
    RequestInterceptorHandler? pending;
    RequestOptions? pendingOptions;
    final pendingStarted = Completer<void>();
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.path.endsWith('/overview')) {
        overviews++;
        h.resolve(
            Response(requestOptions: o, data: envelope({'snapshotId': 's1'})));
      } else if (o.path.endsWith('/statistics')) {
        requests++;
        expect(o.queryParameters['machineCode'], 'machine');
        expect(o.queryParameters['snapshotId'], 's1');
        if (requests == 1) {
          h.reject(DioError(
              requestOptions: o,
              response: Response(
                  requestOptions: o,
                  statusCode: 409,
                  data: {'code': 'SNAPSHOT_EXPIRED'}),
              type: DioErrorType.response));
        } else if (requests == 2) {
          h.resolve(
              Response(requestOptions: o, data: envelope(stats('special'))));
        } else {
          pending = h;
          pendingOptions = o;
          pendingStarted.complete();
        }
      } else {
        h.resolve(Response(requestOptions: o, data: liveFixture(o.path)));
      }
    }));
    final session = LotteryLiveSession(api, 'machine');
    final ready = Completer<void>();
    session.addListener(() {
      if (session.ready && !ready.isCompleted) ready.complete();
    });
    session.attach();
    addTearDown(session.detach);
    await ready.future;
    await session.loadStatistics('special');
    expect(overviews, 2);
    expect(requests, 2);
    expect(session.statistics['special']!.items.length, 49);
    final lateRequest = session.loadStatistics('special', force: true);
    await pendingStarted.future;
    api.sockets.last.send(
        'statistics',
        envelope({
          'snapshotId': 's2',
          'window': 40,
          'attributes': {
            for (final key in LotteryStatistics.candidateCounts.keys)
              key: stats(key, snapshot: 's2'),
          }
        }));
    await Future<void>.delayed(Duration.zero);
    pending!.resolve(Response(
        requestOptions: pendingOptions!, data: envelope(stats('special'))));
    await lateRequest;
    expect(session.statistics.length, 9);
    expect(session.statistics['special']!.snapshotId, 's2');
  });
  testWidgets(
      'no draws still allows statistics tabs and full zero-sample candidates',
      (tester) async {
    final api = FakeLotteryApi();
    lotteryLiveApi = api;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final body = liveFixture(o.path);
      if (o.path.endsWith('/draws')) body['data'] = {'items': []};
      h.resolve(Response(requestOptions: o, data: body));
    }));
    await tester.pumpWidget(const MaterialApp(home: TestPage(gameId: 'empty')));
    await tester.pumpAndSettle();
    api.sockets.last.send(
        'statistics',
        envelope({
          'snapshotId': 's2',
          'window': 40,
          'attributes': {
            for (final key in LotteryStatistics.candidateCounts.keys)
              key: stats(key, snapshot: 's2'),
          }
        }));
    await tester.pump();
    await tester.tap(find.text('遗漏'));
    await tester.pumpAndSettle();
    expect(find.text('暂无样本'), findsNWidgets(49));
    expect(find.text('≥0期'), findsNothing);
    await tester.tap(find.text('冷热'));
    await tester.pumpAndSettle();
    expect(find.text('暂无样本'), findsNWidgets(49));
    await tester.pumpWidget(const SizedBox());
  });
}
