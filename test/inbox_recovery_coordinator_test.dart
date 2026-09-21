import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

void main() {
  late InboxRecoveryCoordinator coordinator;
  late MessagePersistCoordinator persist;

  setUp(() {
    persist = MessagePersistCoordinator();
    persist.bindAccountGeneration(1);
    coordinator = InboxRecoveryCoordinator(
      persist: persist,
      fallbackInterval: const Duration(days: 1),
    );
    InboxRecoveryCoordinator.instance.resetForTest();
  });

  tearDown(() {
    coordinator.resetForTest();
    persist.resetForTest();
    InboxRecoveryCoordinator.instance.resetForTest();
  });

  test('timer + reconnect + resume join one in-flight pass', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var runs = 0;
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        runs += 1;
        if (!started.isCompleted) started.complete();
        await release.future;
        return const InboxRecoveryBatchResult(dueCount: 1, scanned: 1);
      },
    );
    coordinator.request(trigger: InboxRecoveryTrigger.timerFallback);
    await started.future;
    coordinator.request(trigger: InboxRecoveryTrigger.reconnect);
    coordinator.request(trigger: InboxRecoveryTrigger.resume);
    expect(runs, 1);
    expect(coordinator.state, InboxRecoveryState.rerunRequested);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 2);
    expect(
      coordinator.metricsSnapshot.any((row) => row.joinInflight > 0),
      isTrue,
    );
  });

  test('new pending during a run is not dropped', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var runs = 0;
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        runs += 1;
        if (runs == 1) {
          started.complete();
          await release.future;
        }
        return InboxRecoveryBatchResult(
          dueCount: runs == 1 ? 1 : 2,
          scanned: runs == 1 ? 1 : 2,
        );
      },
    );
    coordinator.request(trigger: InboxRecoveryTrigger.pendingWrite);
    await started.future;
    coordinator.request(trigger: InboxRecoveryTrigger.pendingWrite);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 2);
  });

  test('old account generation does not run against the new account', () async {
    var ranFor = <int>[];
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        ranFor.add(request.accountGeneration);
        return const InboxRecoveryBatchResult();
      },
    );
    coordinator.bindAccountGeneration(2);
    coordinator.request(
      trigger: InboxRecoveryTrigger.pendingWrite,
      accountGeneration: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ranFor, isEmpty);
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 2,
      runner: (request) async {
        ranFor.add(request.accountGeneration);
        return const InboxRecoveryBatchResult();
      },
    );
    coordinator.request(trigger: InboxRecoveryTrigger.resume);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ranFor, [2]);
  });

  test('realtime backlog stops background inbox production', () async {
    persist.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      itemCount: 1,
      run: () => Completer<void>().future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(persist.hasRealtimeBacklog, isTrue);
    var runs = 0;
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        runs += 1;
        return const InboxRecoveryBatchResult(scanned: 4, deferred: 4);
      },
    );
    coordinator.markRealtimeLinkReady();
    coordinator.request(trigger: InboxRecoveryTrigger.timerFallback);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 0);
  });

  test('background coordinator does not scan on the fallback timer', () async {
    var runs = 0;
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        runs += 1;
        return const InboxRecoveryBatchResult();
      },
    );
    coordinator.setForeground(false);
    coordinator.request(trigger: InboxRecoveryTrigger.timerFallback);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(runs, 0);
  });

  test('reconnect starts the scheduler instead of dumping every pending',
      () async {
    final phases = <ReconnectRecoveryPhase>[];
    final sizes = <int>[];
    coordinator.bind(
      ownerUserId: 'alice',
      accountGeneration: 1,
      runner: (request) async {
        phases.add(request.phase);
        sizes.add(request.batchSize);
        return InboxRecoveryBatchResult(
          scanned: request.batchSize,
          dueCount: 3000,
          pendingCount: 3000,
          moreDue: request.phase != ReconnectRecoveryPhase.backgroundHistory,
        );
      },
    );
    coordinator.request(trigger: InboxRecoveryTrigger.reconnect);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinator.lastMetrics?.reconnectStarted, isTrue);
    expect(phases, isNotEmpty);
    expect(phases.first, isNot(ReconnectRecoveryPhase.backgroundHistory));
    expect(sizes.first, lessThanOrEqualTo(InboxRecoveryPolicy.minBatchSize));
  });
}
