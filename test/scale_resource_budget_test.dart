import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/bounded_file_loader.dart';
import 'package:tencent_cloud_chat_demo/src/services/request_retry_backoff.dart';

void main() {
  test('downloads deduplicate, bound actual concurrency and evict by bytes',
      () async {
    final pending = <String, Completer<Uint8List>>{};
    final loader = BoundedFileLoader((id) {
      final task = Completer<Uint8List>();
      pending[id] = task;
      return task.future;
    }, maxBytes: 8);
    final a = loader.load('a');
    expect(identical(a, loader.load('a')), isTrue);
    final b = loader.load('b');
    final c = loader.load('c');
    expect(pending.keys, ['a', 'b']);
    pending['a']!.complete(Uint8List(6));
    await a;
    await Future<void>.delayed(Duration.zero);
    expect(pending.keys, ['a', 'b', 'c']);
    pending['b']!.complete(Uint8List(6));
    await b;
    pending['c']!.complete(Uint8List(3));
    await c;
    expect(loader.cachedBytes, lessThanOrEqualTo(8));
    expect(loader.cache.containsKey('a'), isFalse);
    loader.dispose();
  });
  test('dispose drops queued work and ignores running download completion',
      () async {
    final pending = Completer<Uint8List>();
    var calls = 0;
    final loader = BoundedFileLoader((_) {
      calls++;
      return pending.future;
    }, maxConcurrent: 1);
    final a = loader.load('a');
    final b = loader.load('b');
    loader.dispose();
    expect(await b, isNull);
    pending.complete(Uint8List(5));
    expect(await a, isNull);
    expect(calls, 1);
    expect(loader.cachedBytes, 0);
  });
  test('retry deadline increases, honors server hint and resets on success',
      () {
    final backoff = RequestRetryBackoff(random: Random(7));
    var now = DateTime.utc(2026, 9, 25);
    final request = RequestOptions(path: '/presence/last-seen');
    final unavailable = DioError(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 503));
    backoff.failed(unavailable, now);
    final first = backoff.remaining(now);
    expect(first.inMilliseconds, inInclusiveRange(1000, 1500));
    now = now.add(first);
    backoff.failed(unavailable, now);
    expect(backoff.remaining(now).inMilliseconds, inInclusiveRange(2000, 3000));
    backoff.failed(
        DioError(
            requestOptions: request,
            response: Response(
                requestOptions: request,
                statusCode: 429,
                headers: Headers.fromMap({
                  'retry-after': ['120']
                }))),
        now);
    expect(backoff.remaining(now), const Duration(seconds: 120));
    backoff.reset();
    expect(backoff.remaining(now), Duration.zero);
    expect(
        backoff.failed(
            DioError(
                requestOptions: request,
                response: Response(requestOptions: request, statusCode: 401)),
            now),
        isFalse);
  });
}
