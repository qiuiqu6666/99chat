import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'lottery_live_fixture.dart';

void main() {
  for (final total in [0, 7, 20, 35, 100, 120]) {
    testWidgets('loads all $total available draws up to 100', (tester) async {
      final api = FakeLotteryApi();
      final limits = <int>[];
      api.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) {
        final body = liveFixture(options.path);
        if (options.path.endsWith('/draws')) {
          final limit = options.queryParameters['limit'] as int;
          limits.add(limit);
          expectSync(options.queryParameters.containsKey('page'), isFalse);
          final source = body['data']['items'] as List;
          final count = total < limit ? total : limit;
          body['data'] = {
            'items': [
              {...source[0] as Map, 'issue': 'current', 'sequence': 1000},
              for (var i = 0; i < count; i++)
                {
                  ...source[1] as Map,
                  'issue': 'history-$i',
                  'sequence': 999 - i
                },
            ]
          };
        }
        handler.resolve(Response(requestOptions: options, data: body));
      }));
      final session = LotteryLiveSession(api, 'history-$total');
      session.attach();
      try {
        await tester.pumpAndSettle();
        expect(session.ready, isTrue);
        expect(session.draws.where((r) => r['status'] == 'drawn'),
            hasLength(total > 100 ? 100 : total));
        expect(session.draws.first['issue'], 'current');
        expect(limits, [
          for (var limit = 20; limit <= 100; limit += 20)
            if (limit == 20 || total >= limit - 20) limit
        ]);
        if (total == 100) {
          final publishedCounts = <int>[];
          void recordCount() => publishedCounts.add(
              session.draws.where((row) => row['status'] == 'drawn').length);
          session.addListener(recordCount);
          api.sockets.last.send('draws', {
            ...liveFixture('/draws'),
            'data': {'items': session.draws.take(21).toList()},
          });
          await tester.pumpAndSettle();
          expect(session.draws.where((r) => r['status'] == 'drawn'),
              hasLength(100));
          expect(limits, [20, 40, 60, 80, 100, 40, 60, 80, 100]);
          session.removeListener(recordCount);
          expect(publishedCounts, isNotEmpty);
          expect(publishedCounts, everyElement(100));
        }
      } finally {
        session.detach();
        api.dio.close();
        await tester.pump();
      }
    });
  }

  testWidgets('clear during loading replaces the earlier cycle',
      (tester) async {
    final api = FakeLotteryApi();
    final limits = <int>[];
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final body = liveFixture(options.path);
      if (options.path.endsWith('/draws')) {
        final limit = options.queryParameters['limit'] as int;
        limits.add(limit);
        final template = (body['data']['items'] as List)[1] as Map;
        body['data'] = {
          'items': [
            for (var i = 0; i < (limit == 20 ? 20 : 3); i++)
              {
                ...template,
                'issue': '${limit == 20 ? 'old' : 'new'}-$i',
                'sequence': 100 - i
              },
          ]
        };
      }
      handler.resolve(Response(requestOptions: options, data: body));
    }));
    final session = LotteryLiveSession(api, 'clear-history');
    session.attach();
    try {
      await tester.pumpAndSettle();
      expect(limits, [20, 40]);
      expect(session.draws, hasLength(3));
      expect(
          session.draws.every((r) => (r['issue'] as String).startsWith('new-')),
          isTrue);
    } finally {
      session.detach();
      api.dio.close();
      await tester.pump();
    }
  });
}
