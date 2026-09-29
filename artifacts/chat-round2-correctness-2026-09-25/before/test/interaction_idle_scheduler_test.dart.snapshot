import 'dart:async';
// fake_async is supplied by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/interaction_idle_scheduler.dart';

void main() {
  test('cancel after posting to Flutter prevents execution', () {
    fakeAsync((clock) {
      final posted = <void Function()>[];
      var runs = 0;
      final scheduler = InteractionIdleScheduler(
        canStart: () => true,
        postIdle: posted.add,
      );
      scheduler.schedule('a', delay: Duration.zero, task: () => runs++);
      clock.elapse(Duration.zero);
      expect(posted, hasLength(1));
      scheduler.cancel('a');
      posted.removeAt(0)();
      clock.flushMicrotasks();
      expect(runs, 0);
      scheduler.cancelAll();
    });
  });

  test('latest same-key job survives an older posted callback', () {
    fakeAsync((clock) {
      final posted = <void Function()>[];
      final runs = <String>[];
      final scheduler = InteractionIdleScheduler(
        canStart: () => true,
        postIdle: posted.add,
      );
      scheduler.schedule('a',
          delay: Duration.zero, task: () => runs.add('old'));
      clock.elapse(Duration.zero);
      scheduler.schedule('a',
          delay: const Duration(milliseconds: 50), task: () => runs.add('new'));
      posted.removeAt(0)();
      expect(runs, isEmpty);
      clock.elapse(const Duration(milliseconds: 50));
      posted.removeAt(0)();
      clock.flushMicrotasks();
      expect(runs, ['new']);
      scheduler.cancelAll();
    });
  });

  test('interaction is rechecked after posting and recovery is serial/spaced',
      () {
    fakeAsync((clock) {
      var idle = true;
      final posted = <void Function()>[];
      final runs = <String>[];
      final first = Completer<void>();
      final scheduler = InteractionIdleScheduler(
        canStart: () => idle,
        postIdle: posted.add,
      );
      scheduler.schedule('a', delay: Duration.zero, task: () {
        runs.add('a');
        return first.future;
      });
      scheduler.schedule('b', delay: Duration.zero, task: () => runs.add('b'));
      clock.elapse(Duration.zero);
      idle = false;
      posted.removeAt(0)();
      clock.elapse(const Duration(milliseconds: 200));
      expect(runs, isEmpty);
      idle = true;
      clock.elapse(const Duration(milliseconds: 100));
      posted.removeAt(0)();
      clock.elapse(const Duration(seconds: 1));
      expect(runs, ['a']);
      expect(posted, isEmpty);
      first.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 31));
      expect(posted, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      posted.removeAt(0)();
      clock.flushMicrotasks();
      expect(runs, ['a', 'b']);
      scheduler.cancelAll();
    });
  });

  test('running task stops at checkpoint after cancellation', () {
    fakeAsync((clock) {
      final started = Completer<void>();
      final runs = <int>[];
      final scheduler = InteractionIdleScheduler(
        canStart: () => true,
        postIdle: (callback) => callback(),
      );
      scheduler.scheduleCooperative('a', delay: Duration.zero,
          task: (work) async {
        runs.add(1);
        await started.future;
        if (!await work.checkpoint()) return;
        runs.add(2);
      });
      clock.elapse(Duration.zero);
      scheduler.cancelAll();
      started.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(runs, [1]);
    });
  });

  test('checkpoint pauses the next operation until interaction ends', () {
    fakeAsync((clock) {
      var idle = true;
      final runs = <int>[];
      final scheduler = InteractionIdleScheduler(
        canStart: () => idle,
        postIdle: (callback) => callback(),
      );
      scheduler.scheduleCooperative('a', delay: Duration.zero,
          task: (work) async {
        runs.add(1);
        idle = false;
        if (!await work.checkpoint()) return;
        runs.add(2);
      });
      clock.elapse(const Duration(seconds: 1));
      expect(runs, [1]);
      idle = true;
      clock.elapse(const Duration(milliseconds: 100));
      expect(runs, [1, 2]);
      scheduler.cancelAll();
    });
  });

  test('session invalidated while callback queued cannot start work', () {
    fakeAsync((clock) {
      var current = true;
      var runs = 0;
      final posted = <void Function()>[];
      final scheduler = InteractionIdleScheduler(
        canStart: () => true,
        postIdle: posted.add,
      );
      scheduler.schedule('a',
          delay: Duration.zero, isCurrent: () => current, task: () => runs++);
      clock.elapse(Duration.zero);
      current = false;
      posted.removeAt(0)();
      expect(runs, 0);
      scheduler.cancelAll();
    });
  });
}
