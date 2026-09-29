import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/typing_status_send_queue.dart';

void main() {
  test('a stalled notification coalesces a burst to the latest state', () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue();
      final stalled = Completer<void>();
      final sent = <int>[];
      void send(int value) => queue.runLatest(
            sessionKey: 'alice:1',
            receiver: 'bob',
            action: (_) async {
              sent.add(value);
              if (value == 0) await stalled.future;
            },
          );
      send(0);
      for (var i = 1; i <= 1000; i++) {
        send(i);
      }
      time.flushMicrotasks();
      expect(sent, [0]);
      stalled.complete();
      time.flushMicrotasks();
      expect(sent, [0, 1000]);
      send(1001);
      time.flushMicrotasks();
      expect(sent, [0, 1000, 1001]);
    });
  });

  test('expired pending state is discarded after a slow native completion', () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue(
        now: () => DateTime(2026).add(time.elapsed),
      );
      final stalled = Completer<void>();
      var pendingSent = false;
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) => stalled.future,
      );
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) async => pendingSent = true,
      );
      time.elapse(const Duration(seconds: 5));
      stalled.complete();
      time.flushMicrotasks();
      expect(pendingSent, isFalse);
    });
  });

  test('superseded creation fails its freshness check before native send', () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue();
      final creation = Completer<void>();
      final sent = <String>[];
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (isFresh) async {
          await creation.future;
          if (isFresh()) sent.add('typing');
        },
      );
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) async => sent.add('stopped'),
      );
      creation.complete();
      time.flushMicrotasks();
      expect(sent, ['stopped']);
    });
  });

  test('native failure is disposable and does not poison later notifications',
      () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue();
      final failed = Completer<void>();
      var laterSent = false;
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) => failed.future,
      );
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) async => laterSent = true,
      );
      failed.completeError(StateError('network unavailable'));
      time.flushMicrotasks();
      expect(laterSent, isTrue);
    });
  });

  test('account change invalidates old work without blocking the new session',
      () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue();
      final old = Completer<void>();
      final current = Completer<void>();
      final sent = <String>[];
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (isFresh) async {
          await old.future;
          if (isFresh()) sent.add('stale');
        },
      );
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) async => sent.add('old pending'),
      );
      queue.runLatest(
        sessionKey: 'alice:2',
        receiver: 'bob',
        action: (_) async {
          sent.add('current');
          await current.future;
        },
      );
      old.complete();
      time.flushMicrotasks();
      queue.runLatest(
        sessionKey: 'alice:2',
        receiver: 'bob',
        action: (_) async => sent.add('current pending'),
      );
      expect(sent, ['current']);
      current.complete();
      time.flushMicrotasks();
      expect(sent, ['current', 'current pending']);
    });
  });

  test('a stuck peer does not delay another peer', () {
    fakeAsync((time) {
      final queue = TypingStatusSendQueue();
      final stalled = Completer<void>();
      var otherSent = false;
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'bob',
        action: (_) => stalled.future,
      );
      queue.runLatest(
        sessionKey: 'alice:1',
        receiver: 'carol',
        action: (_) async => otherSent = true,
      );
      time.flushMicrotasks();
      expect(otherSent, isTrue);
      stalled.complete();
      time.flushMicrotasks();
    });
  });
}
