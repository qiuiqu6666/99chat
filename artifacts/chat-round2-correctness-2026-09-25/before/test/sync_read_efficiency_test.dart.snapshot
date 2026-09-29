import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/network/scoped_read_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/network/no_change_sync_gate.dart';
import 'package:tencent_cloud_chat_demo/src/services/network/offset_page_reader.dart';

void main() {
  test(
      'parallel reads share one request, successful reads expire and force refreshes',
      () async {
    var now = DateTime(2026);
    final cache =
        ScopedReadCache<int>(ttl: const Duration(seconds: 30), now: () => now);
    final reply = Completer<int>();
    var calls = 0;
    Future<int> read({bool force = false}) => cache.read(
        scope: 'owner|1',
        key: 'peer',
        force: force,
        load: () {
          calls++;
          return reply.future;
        });
    final first = read();
    final second = read();
    expect(calls, 1);
    reply.complete(7);
    expect(await first, 7);
    expect(await second, 7);
    await read();
    expect(calls, 1);
    await read(force: true);
    expect(calls, 2);
    now = now.add(const Duration(seconds: 31));
    await read();
    expect(calls, 3);
  });

  test('account switch and same-owner relogin cannot seed a new cache',
      () async {
    final cache = ScopedReadCache<int>(ttl: const Duration(seconds: 30));
    final old = Completer<int>();
    final first =
        cache.read(scope: 'owner|1', key: 'peer', load: () => old.future);
    expect(await cache.read(scope: 'owner|2', key: 'peer', load: () async => 2),
        2);
    old.complete(1);
    await first;
    expect(await cache.read(scope: 'owner|2', key: 'peer', load: () async => 3),
        2);
    expect(await cache.read(scope: 'other|2', key: 'peer', load: () async => 4),
        4);
  });

  test('failed requests and null profiles do not poison the retry cache',
      () async {
    final cache = ScopedReadCache<int?>(ttl: const Duration(seconds: 30));
    await expectLater(
        cache.read(
            scope: 'a',
            key: 'k',
            load: () async => throw StateError('offline')),
        throwsStateError);
    await cache.read(
        scope: 'a',
        key: 'k',
        load: () async => null,
        cacheIf: (v) => v != null);
    expect(await cache.read(scope: 'a', key: 'k', load: () async => 9), 9);
  });

  test(
      'empty checkpoint expires, changed cursor bypasses and realtime invalidates old replies',
      () {
    var now = DateTime(2026);
    final gate = NoChangeSyncGate(now: () => now);
    final request = gate.generation;
    gate.recordEmpty('owner|revision|cursor', request);
    expect(gate.shouldSkip('owner|revision|cursor'), isTrue);
    expect(gate.shouldSkip('owner|new-revision|cursor'), isFalse);
    now = now.add(const Duration(seconds: 30));
    expect(gate.shouldSkip('owner|revision|cursor'), isFalse);
    gate.invalidate();
    gate.recordEmpty('owner|revision|cursor', request);
    expect(gate.shouldSkip('owner|revision|cursor'), isFalse);
  });

  for (final count in [0, 3, 100, 701]) {
    test(
        'join application pagination loads exactly $count records without speculative pages',
        () async {
      var calls = 0;
      final all = List.generate(count, (i) => i);
      final result = await readAllOffsetPages<int>(
        identity: (id) => id,
        load: (offset, limit) async {
          calls++;
          return all.skip(offset).take(limit).toList();
        },
      );
      expect(result, all);
      expect(calls, count ~/ 100 + 1);
    });
  }

  test(
      'failed or repeating full page never becomes a completed partial snapshot',
      () async {
    await expectLater(
        readAllOffsetPages<int>(
            identity: (id) => id,
            load: (offset, limit) async {
              if (offset > 0) throw StateError('offline');
              return List.generate(limit, (i) => i);
            }),
        throwsStateError);
    await expectLater(
        readAllOffsetPages<int>(
            identity: (id) => id,
            load: (_, limit) async => List.generate(limit, (i) => i)),
        throwsStateError);
  });
}
