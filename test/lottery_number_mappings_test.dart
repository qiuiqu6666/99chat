import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_number_mappings.dart';

Map<String, dynamic> fixture(String machine) {
  Map<String, List<int>> groups(List<String> labels) => {
        for (var i = 0; i < labels.length; i++)
          labels[i]: [
            for (var n = 1; n <= 49; n++)
              if ((n - 1) % labels.length == i) n,
          ],
      };
  return {
    'code': 0,
    'data': {
      'machineCode': machine,
      'databaseGeneration': '1789419463_4566',
      'zodiacNumbers':
          groups(['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪']),
      'colorNumbers': groups(['红', '蓝', '绿色']),
      'fiveElementNumbers': groups(['金', '木', '水', '火', '土']),
    }
  };
}

void main() {
  test(
      'cache coalesces requests, separates machines and retains stale data on failure',
      () async {
    var now = DateTime(2026);
    var calls = 0;
    var fail = false;
    final first = Completer<LotteryNumberMappings>();
    final cache = LotteryNumberMappingsCache(
        now: () => now,
        loader: (machine) async {
          calls++;
          if (calls == 1) return first.future;
          if (fail) throw StateError('offline');
          return LotteryNumberMappings.parse(fixture(machine), machine);
        });
    final a = cache.refresh('a');
    final duplicate = cache.refresh('a');
    expect(identical(a, duplicate), true);
    first.complete(LotteryNumberMappings.parse(fixture('a'), 'a'));
    await a;
    await cache.refresh('a');
    expect(calls, 1);
    expect(cache.peek('b'), isNull);
    await cache.refresh('b');
    expect(cache.peek('b')!.machineCode, 'b');
    now = now.add(const Duration(seconds: 31));
    fail = true;
    await expectLater(cache.refresh('a'), throwsStateError);
    expect(cache.peek('a')!.machineCode, 'a');
    fail = false;
    await cache.refresh('a');
    expect(calls, 4);
  });
  test('scope change discards cache and old in-flight response', () async {
    var scope = 'account-A';
    final pending = Completer<LotteryNumberMappings>();
    final cache = LotteryNumberMappingsCache(
        scope: () => scope, loader: (_) => pending.future);
    final request = cache.refresh('a');
    scope = 'account-B';
    expect(cache.peek('a'), isNull);
    pending.complete(LotteryNumberMappings.parse(fixture('a'), 'a'));
    await request;
    expect(cache.peek('a'), isNull);
  });
  test('parses all numbers, green alias, and generation', () {
    final mappings = LotteryNumberMappings.parse(fixture('abc'), 'abc');
    expect(mappings.colors[3], '绿');
    expect(mappings.zodiacs.length, 49);
    expect(mappings.elements.length, 49);
    expect(mappings.databaseGeneration, '1789419463_4566');
    expect(() => LotteryNumberMappings.parse(fixture('other'), 'abc'),
        throwsFormatException);
    final invalid = fixture('abc');
    invalid['data']['colorNumbers']['红'].add(3);
    expect(() => LotteryNumberMappings.parse(invalid, 'abc'),
        throwsFormatException);
  });
  test('requests direct endpoint with raw machine code encoded once', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://47.242.90.129'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.uri.host, '47.242.90.129');
      expect(options.uri.path, '/api/admin/robot-desk/number-mappings');
      expect(options.uri.queryParameters['machineCode'], '@machine#1');
      handler.resolve(
          Response(requestOptions: options, data: fixture('@machine#1')));
    }));
    final result = await fetchLotteryNumberMappings('@machine#1', dio: dio);
    expect(result.machineCode, '@machine#1');
  });
}
