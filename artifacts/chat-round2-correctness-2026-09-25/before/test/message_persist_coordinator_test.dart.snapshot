import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

void main() {
  late MessagePersistCoordinator coordinator;

  setUp(() {
    coordinator = MessagePersistCoordinator(
      historyChunkSize: 80,
      backgroundQueueSoftLimit: 4,
      backgroundQueueHardLimit: 2,
    );
  });

  test('realtime cuts in between history chunks, not after the full history',
      () async {
    final order = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final history = <Future<void>>[
      coordinator.enqueue<void>(
        priority: MessagePersistPriority.userHistory,
        source: MessagePersistSource.userHistory,
        itemCount: 80,
        run: () async {
          order.add('h1');
          firstStarted.complete();
          await releaseFirst.future;
        },
      ),
      for (var i = 2; i <= 6; i++)
        coordinator.enqueue<void>(
          priority: MessagePersistPriority.userHistory,
          source: MessagePersistSource.userHistory,
          itemCount: 80,
          run: () async => order.add('h$i'),
        ),
    ];
    await firstStarted.future;
    final realtime = coordinator.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      itemCount: 1,
      run: () async => order.add('rt'),
    );
    releaseFirst.complete();
    await Future.wait<void>([...history, realtime]);
    expect(order.first, 'h1');
    expect(order[1], 'rt');
    expect(order.sublist(2), ['h2', 'h3', 'h4', 'h5', 'h6']);
  });

  test('realtime queue wait does not grow with remaining history volume',
      () async {
    Future<int> measureRealtimeWait(int historyChunks) async {
      final local = MessagePersistCoordinator();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final history = <Future<void>>[
        local.enqueue<void>(
          priority: MessagePersistPriority.userHistory,
          source: MessagePersistSource.userHistory,
          itemCount: 80,
          run: () async {
            firstStarted.complete();
            await releaseFirst.future;
            await Future<void>.delayed(const Duration(milliseconds: 12));
          },
        ),
        for (var i = 1; i < historyChunks; i++)
          local.enqueue<void>(
            priority: MessagePersistPriority.userHistory,
            source: MessagePersistSource.userHistory,
            itemCount: 80,
            run: () async {
              await Future<void>.delayed(const Duration(milliseconds: 12));
            },
          ),
      ];
      await firstStarted.future;
      final realtime = local.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () async {},
      );
      releaseFirst.complete();
      await Future.wait<void>([...history, realtime]);
      return local.metricsSnapshot
          .firstWhere((item) => item.source == MessagePersistSource.realtime)
          .queueWaitUs;
    }

    final waitForSix = await measureRealtimeWait(6);
    final waitForTwelve = await measureRealtimeWait(12);
    expect(waitForSix, lessThan(80 * 1000));
    expect(waitForTwelve, lessThan(80 * 1000));
    expect(waitForTwelve, lessThan(waitForSix * 3));
  });

  test('user history is served before background repair', () async {
    final order = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final first = coordinator.enqueue<void>(
      priority: MessagePersistPriority.backgroundRepair,
      source: MessagePersistSource.backgroundRepair,
      run: () async {
        order.add('p2-start');
        firstStarted.complete();
        await releaseFirst.future;
        order.add('p2-end');
      },
    );
    await firstStarted.future;
    final userHistory = coordinator.enqueue<void>(
      priority: MessagePersistPriority.userHistory,
      source: MessagePersistSource.userHistory,
      run: () async => order.add('p1'),
    );
    final moreBackground = coordinator.enqueue<void>(
      priority: MessagePersistPriority.backgroundRepair,
      source: MessagePersistSource.backgroundRepair,
      run: () async => order.add('p2-next'),
    );
    releaseFirst.complete();
    await Future.wait<void>([first, userHistory, moreBackground]);
    expect(order, ['p2-start', 'p2-end', 'p1', 'p2-next']);
  });

  test('late history is stale after realtime revoke authority', () {
    coordinator.rememberAuthority(
      conversationId: 'group_a',
      messageId: 'm-revoked',
      kind: MessagePersistAuthorityKind.revoke,
    );
    expect(
      coordinator.isStaleHistoryWrite(
        conversationId: 'group_a',
        messageId: 'm-revoked',
      ),
      isTrue,
    );
    expect(
      coordinator.authorityFor(
        conversationId: 'group_a',
        messageId: 'm-revoked',
      ),
      MessagePersistAuthorityKind.revoke,
    );
  });

  test('many realtime jobs complete once without dropping or reordering',
      () async {
    final seen = <int>[];
    final jobs = <Future<int>>[
      for (var i = 0; i < 40; i++)
        coordinator.enqueue<int>(
          priority: MessagePersistPriority.realtime,
          source: MessagePersistSource.realtime,
          itemCount: 1,
          run: () async {
            seen.add(i);
            return i;
          },
        ),
    ];
    expect(await Future.wait<int>(jobs), List<int>.generate(40, (i) => i));
    expect(seen, List<int>.generate(40, (i) => i));
  });

  test('P0 busy stops background production and hard-limits the P2 queue',
      () async {
    final hold = Completer<void>();
    final realtime = coordinator.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      run: () => hold.future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.hasRealtimeBacklog, isTrue);
    expect(coordinator.shouldProduceBackground, isFalse);
    final firstBackground = coordinator.enqueue<void>(
      priority: MessagePersistPriority.backgroundRepair,
      source: MessagePersistSource.backgroundRepair,
      run: () async {},
    );
    final secondBackground = coordinator.enqueue<void>(
      priority: MessagePersistPriority.backgroundRepair,
      source: MessagePersistSource.backgroundRepair,
      run: () async {},
    );
    expect(coordinator.backgroundQueueDepth, 2);
    expect(
      coordinator.enqueue<void>(
        priority: MessagePersistPriority.backgroundRepair,
        source: MessagePersistSource.backgroundRepair,
        run: () async {},
      ),
      throwsA(
        isA<MessagePersistRejected>().having(
          (error) => error.reason,
          'reason',
          'background_backpressure',
        ),
      ),
    );
    hold.complete();
    await Future.wait<void>([realtime, firstBackground, secondBackground]);
    expect(coordinator.shouldProduceBackground, isTrue);
    expect(coordinator.queueDepth, 0);
  });

  test('paused P2 can resume from the next committed chunk', () async {
    final committed = <int>[];
    var produce = true;
    Future<void> produceBackground(int cursor) async {
      if (!produce || !coordinator.shouldProduceBackground) {
        return;
      }
      await coordinator.enqueue<void>(
        priority: MessagePersistPriority.backgroundRepair,
        source: MessagePersistSource.backgroundRepair,
        run: () async => committed.add(cursor),
      );
    }

    await produceBackground(1);
    expect(committed, [1]);
    final hold = Completer<void>();
    final realtime = coordinator.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      run: () => hold.future,
    );
    await Future<void>.delayed(Duration.zero);
    produce = coordinator.shouldProduceBackground;
    await produceBackground(2);
    expect(committed, [1]);
    hold.complete();
    await realtime;
    produce = coordinator.shouldProduceBackground;
    await produceBackground(2);
    expect(committed, [1, 2]);
  });

  test('stale accountGeneration queued jobs are rejected on switch', () async {
    coordinator.bindAccountGeneration(1);
    final hold = Completer<void>();
    final current = coordinator.enqueue<void>(
      priority: MessagePersistPriority.userHistory,
      source: MessagePersistSource.userHistory,
      accountGeneration: 1,
      run: () => hold.future,
    );
    await Future<void>.delayed(Duration.zero);
    final stale = coordinator.enqueue<void>(
      priority: MessagePersistPriority.userHistory,
      source: MessagePersistSource.userHistory,
      accountGeneration: 1,
      run: () async {},
    );
    final staleRejected = expectLater(
      stale,
      throwsA(
        isA<MessagePersistRejected>().having(
          (error) => error.reason,
          'reason',
          'stale_account_generation',
        ),
      ),
    );
    coordinator.bindAccountGeneration(2);
    hold.complete();
    await current;
    await staleRejected;
    await expectLater(
      coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        accountGeneration: 1,
        run: () async {},
      ),
      throwsA(isA<MessagePersistRejected>()),
    );
  });

  test('page exit still persists but skips projection publish', () async {
    coordinator.setActiveChatConversationId('group_a');
    var published = 0;
    var persisted = 0;
    coordinator.setActiveChatConversationId(null);
    await coordinator.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      conversationId: 'group_a',
      run: () async {
        persisted++;
      },
      publish: (_) async {
        published++;
      },
    );
    expect(persisted, 1);
    expect(published, 0);
  });

  test('transaction failure does not complete successfully or publish',
      () async {
    var published = 0;
    final failed = coordinator.enqueue<void>(
      priority: MessagePersistPriority.realtime,
      source: MessagePersistSource.realtime,
      run: () async {
        throw StateError('txn_failed');
      },
      publish: (_) async {
        published++;
      },
    );
    await expectLater(failed, throwsA(isA<StateError>()));
    expect(published, 0);
    expect(coordinator.metricsSnapshot, isEmpty);
  });

  test('splitChunks keeps history commits small', () {
    final chunks = MessagePersistCoordinator.splitChunks(
      List<int>.generate(500, (i) => i),
      80,
    );
    expect(chunks.length, 7);
    expect(chunks.first.length, 80);
    expect(chunks.last.length, 20);
  });
}
