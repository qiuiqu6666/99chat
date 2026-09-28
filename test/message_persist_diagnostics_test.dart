import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

void main() {
  for (final stage in ['prepare', 'transaction', 'publish']) {
    test('pending $stage is observable and preserves writer ownership',
        () async {
      final coordinator = MessagePersistCoordinator(
          stallWarningAfter: const Duration(milliseconds: 20));
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void> hold() async {
        entered.complete();
        await release.future;
      }

      final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.userHistory,
        source: MessagePersistSource.userHistory,
        prepare: stage == 'prepare' ? hold : null,
        run: stage == 'transaction' ? hold : () async {},
        publish: stage == 'publish' ? (_) => hold() : null,
        allowProjection: true,
      );
      await entered.future;
      var secondRan = false;
      final second = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () async {
          secondRan = true;
        },
      );
      try {
        final deadline = Stopwatch()..start();
        while ((coordinator.diagnosticSnapshot['active'] as Map)['stalled'] !=
            true) {
          if (deadline.elapsed > const Duration(seconds: 2)) {
            fail('No stall diagnostic');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final snapshot = coordinator.diagnosticSnapshot;
        final active = snapshot['active'] as Map;
        expect(active['stage'], stage);
        expect(snapshot['queueDepth'], 1);
        expect(snapshot['writerHeld'], stage == 'transaction');
        expect(secondRan, isFalse);
        final operation = active['operation'];
        expect(
            ChatRecoveryTrace.recentEvents.any((line) =>
                line.contains('event=persist_stalled') &&
                line.contains('op=$operation') &&
                line.contains('stage=$stage')),
            isTrue);
      } finally {
        release.complete();
        await Future.wait([first, second]);
      }
      expect(secondRan, isTrue);
      expect(coordinator.diagnosticSnapshot['active'], isNull);
      expect(coordinator.txnInFlight, isFalse);
      expect(coordinator.diagnosticSnapshot['completedJobs'], 2);
    });

    test('$stage failure records its stage and allows the next job', () async {
      final coordinator = MessagePersistCoordinator();
      Future<void> failStage() async =>
          throw StateError('private message body');
      await expectLater(
          coordinator.enqueue<void>(
            priority: MessagePersistPriority.userHistory,
            source: MessagePersistSource.userHistory,
            prepare: stage == 'prepare' ? failStage : null,
            run: stage == 'transaction' ? failStage : () async {},
            publish: stage == 'publish' ? (_) => failStage() : null,
            allowProjection: true,
          ),
          throwsStateError);
      final failure = coordinator.diagnosticSnapshot['lastFailure'] as Map;
      expect(failure['stage'], stage);
      expect(failure['errorType'], 'StateError');
      expect(failure.toString(), isNot(contains('private message body')));
      expect(coordinator.diagnosticSnapshot['failedJobs'], 1);
      expect(coordinator.diagnosticSnapshot['active'], isNull);
      expect(coordinator.txnInFlight, isFalse);
      expect(
          await coordinator.enqueue<int>(
            priority: MessagePersistPriority.realtime,
            source: MessagePersistSource.realtime,
            run: () async => 42,
          ),
          42);
    });
  }
}
