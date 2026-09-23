import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_effect_scheduler.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

void main() {
  test('drain waits for actual in-flight completion after close', () async {
    final scheduler = RuntimeEffectScheduler(maxConcurrent: 1);
    final gate = Completer<RuntimeDocument>();
    final first = scheduler.schedule(
        lane: 'a', isCurrent: () => true, execute: () => gate.future);
    final queued = scheduler.schedule(
        lane: 'b',
        isCurrent: () => true,
        execute: () async => throw StateError('closed job executed'));
    var drained = false;
    final draining = scheduler.drain().then((_) => drained = true);
    scheduler.close();
    expect((await queued).dispatched, isFalse);
    expect(scheduler.logicalCount, 1);
    expect(scheduler.runningCount, 1);
    expect(drained, isFalse);
    gate.complete(RuntimeDocument({'confirmed': true}));
    final outcome = await first;
    await draining;
    expect(outcome.status, RuntimeEffectStatus.obsolete);
    expect(outcome.value!['confirmed'], isTrue);
    expect(scheduler.logicalCount, 0);
    expect(scheduler.runningCount, 0);
    expect(scheduler.evictionCount, 2);
  });

  test(
      'ten thousand immediate completions yield to timers and release all lanes',
      () async {
    final scheduler =
        RuntimeEffectScheduler(maxConcurrent: 2, maxQueued: 10000);
    addTearDown(scheduler.close);
    var calls = 0;
    int? callsAtTimer;
    final timer = Completer<void>();
    Timer.run(() {
      callsAtTimer = calls;
      timer.complete();
    });
    final jobs = <Future<RuntimeEffectOutcome>>[];
    for (var i = 0; i < 10000; i++) {
      jobs.add(scheduler.schedule(
          lane: 'conversation${i % 3}',
          isCurrent: () => true,
          execute: () async {
            calls++;
            return RuntimeDocument({});
          }));
    }
    await scheduler.drain();
    final results = await Future.wait(jobs);
    await timer.future;
    expect(callsAtTimer, lessThan(10000));
    expect(calls, 10000);
    expect(results.every((r) => r.status == RuntimeEffectStatus.completed),
        isTrue);
    expect(scheduler.queuedCount, 0);
    expect(scheduler.runningCount, 0);
    expect(scheduler.readyCount, 0);
    expect(scheduler.logicalCount, 0);
  });

  test('drain can be used again for a later admission batch', () async {
    final scheduler = RuntimeEffectScheduler(completionsPerTurn: 1);
    addTearDown(scheduler.close);
    await scheduler.schedule(
        lane: 'a',
        isCurrent: () => true,
        execute: () async => RuntimeDocument({}));
    await scheduler.drain();
    final gate = Completer<RuntimeDocument>();
    final second = scheduler.schedule(
        lane: 'a', isCurrent: () => true, execute: () => gate.future);
    var drained = false;
    final drain = scheduler.drain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    gate.complete(RuntimeDocument({}));
    await second;
    await drain;
    expect(drained, isTrue);
  });
}
