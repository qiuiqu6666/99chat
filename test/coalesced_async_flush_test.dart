import 'dart:async';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/coalesced_async_flush.dart';

void main() {
  test('serial ingress does not acquire a fixed per-message delay', () {
    fakeAsync((clock) {
      var writes = 0;
      var acknowledged = false;
      final lane = CoalescedAsyncFlush(() async {
        writes++;
      });
      Future<void> receive() async {
        for (var i = 0; i < 100; i++) {
          await lane.request();
        }
        acknowledged = true;
      }

      receive();
      clock.flushMicrotasks();
      expect(writes, 100);
      expect(acknowledged, isTrue);
      expect(clock.elapsed, Duration.zero);
    });
  });

  test('a burst shares one flush and acknowledgements wait for storage', () {
    fakeAsync((clock) {
      final write = Completer<void>();
      var flushes = 0, acks = 0;
      final lane = CoalescedAsyncFlush(() {
        flushes++;
        return write.future;
      });
      for (var i = 0; i < 100; i++) {
        lane.request().then((_) => acks++);
      }
      clock.flushMicrotasks();
      expect(flushes, 1);
      expect(acks, 0);
      write.complete();
      clock.flushMicrotasks();
      expect(acks, 100);
    });
  });

  test('arrivals during a running write wait for a subsequent serial flush',
      () {
    fakeAsync((clock) {
      final first = Completer<void>(), second = Completer<void>();
      var flushes = 0;
      var secondAck = false;
      final lane = CoalescedAsyncFlush(
          () => ++flushes == 1 ? first.future : second.future);
      lane.request();
      clock.flushMicrotasks();
      lane.request().then((_) => secondAck = true);
      clock.flushMicrotasks();
      for (var i = 0; i < 100; i++) {
        lane.request();
        clock.flushMicrotasks();
      }
      expect(flushes, 1);
      first.complete();
      clock.flushMicrotasks();
      expect(flushes, 2);
      expect(secondAck, isFalse);
      second.complete();
      clock.flushMicrotasks();
      expect(secondAck, isTrue);
      expect(flushes, 2);
    });
  });

  test('failed writes are reported and do not poison the next flush', () {
    fakeAsync((clock) {
      var count = 0, failures = 0, successes = 0;
      final lane = CoalescedAsyncFlush(() async {
        if (++count == 1) throw StateError('storage unavailable');
      });
      lane.request().then((_) {}, onError: (Object _) {
        failures++;
      });
      clock.flushMicrotasks();
      lane.request().then((_) => successes++);
      clock.flushMicrotasks();
      expect(failures, 1);
      expect(successes, 1);
    });
  });
}
