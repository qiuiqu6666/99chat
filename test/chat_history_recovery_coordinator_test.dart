import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

void main() {
  tearDown(() {
    ChatHistoryRecoveryCoordinator.instance.resetForTest();
  });

  group('ChatHistoryRecoveryCoordinator.shouldSkipForegroundRecovery', () {
    test('skips sync_server_finish when recently recovered with messages', () {
      const key = 'alice';
      ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: false,
          reason: 'sync_server_finish',
        ),
        isTrue,
      );
    });

    test('does not skip when preview is ahead for sync reasons', () {
      const key = 'alice';
      ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: true,
          reason: 'sync_server_finish',
        ),
        isFalse,
      );
    });

    test('skips conversation_open_preview_ahead when recently recovered', () {
      const key = 'alice';
      ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: true,
          reason: 'conversation_open_preview_ahead',
        ),
        isTrue,
      );
    });

    test('does not skip first warm app_resumed without a prior recovery', () {
      const key = 'alice';

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: false,
          reason: 'app_resumed',
        ),
        isFalse,
      );
    });

    test('does not skip app_resumed when preview is ahead', () {
      const key = 'alice';
      ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: true,
          reason: 'app_resumed',
        ),
        isFalse,
      );
    });

    test('does not skip app_resumed when deferred incoming remains', () {
      const key = 'alice';
      ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldSkipForegroundRecovery(
          conversationKey: key,
          hasVisibleMessages: true,
          previewAhead: false,
          reason: 'app_resumed',
          hasDeferredIncoming: true,
        ),
        isFalse,
      );
    });
  });

  group('ChatHistoryRecoveryCoordinator foreground request coalescing', () {
    test('prior lifecycle success and coalescing do not suppress resume', () {
      final coordinator = ChatHistoryRecoveryCoordinator.instance;
      const key = 'resume-chat';
      coordinator.recordSuccessfulRecovery(key);
      expect(
          coordinator.shouldCoalesceForegroundRequest(
              conversationKey: key, reason: 'app_resumed'),
          isFalse);
      coordinator.invalidateLifecycle();

      expect(
          coordinator.shouldCoalesceForegroundRequest(
              conversationKey: key, reason: 'app_resumed'),
          isFalse);
      expect(
          coordinator.shouldSkipForegroundRecovery(
            conversationKey: key,
            hasVisibleMessages: true,
            previewAhead: false,
            reason: 'app_resumed',
          ),
          isFalse);
    });

    test('coalesces resume and reconnect signals from the same unlock', () {
      const key = 'unlock-chat';

      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldCoalesceForegroundRequest(
          conversationKey: key,
          reason: 'app_resumed',
        ),
        isFalse,
      );
      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldCoalesceForegroundRequest(
          conversationKey: key,
          reason: 'im_reconnected',
        ),
        isTrue,
      );
    });

    test('does not coalesce unrelated recovery reasons', () {
      expect(
        ChatHistoryRecoveryCoordinator.instance.shouldCoalesceForegroundRequest(
          conversationKey: 'sync-chat',
          reason: 'sync_server_finish',
        ),
        isFalse,
      );
    });
  });

  group('ChatHistoryRecoveryCoordinator.runExclusive', () {
    test('resume recovery starts while pre-background recovery is stalled',
        () async {
      final coordinator = ChatHistoryRecoveryCoordinator.instance;
      final oldGate = Completer<void>();
      final oldStarted = Completer<void>();
      final old = coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'external_entry',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          oldStarted.complete();
          await oldGate.future;
        },
      );
      await oldStarted.future;
      coordinator.invalidateLifecycle();

      var resumed = false;
      await coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'app_resumed',
        priority: ChatHistoryRecoveryCoordinator.priorityForeground,
        task: () async => resumed = true,
      );
      // Complete the abandoned request even when the assertion below fails.
      oldGate.complete();
      await old;
      expect(resumed, isTrue);
    });

    test('late old recovery cannot release or drain the new lifecycle lane',
        () async {
      final coordinator = ChatHistoryRecoveryCoordinator.instance;
      final oldGate = Completer<void>();
      final oldStarted = Completer<void>();
      final newGate = Completer<void>();
      final order = <String>[];
      final old = coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'old',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          oldStarted.complete();
          await oldGate.future;
        },
      );
      await oldStarted.future;
      coordinator.invalidateLifecycle();
      final current = coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'new',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          order.add('new');
          await newGate.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      final startedBeforeOldFinished = order.contains('new');
      oldGate.complete();
      await Future<void>.delayed(Duration.zero);
      final pending = coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'new-pending',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async => order.add('pending'),
      );
      await coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'background',
        priority: ChatHistoryRecoveryCoordinator.priorityBackground,
        task: () async => order.add('background'),
      );
      await Future<void>.delayed(Duration.zero);
      final orderWhileCurrentRunning = List<String>.of(order);
      newGate.complete();
      await Future.wait([old, current, pending]);

      expect(startedBeforeOldFinished, isTrue);
      expect(orderWhileCurrentRunning, ['new']);
      expect(order, ['new', 'pending']);
    });

    test('runs tasks for the same key sequentially', () async {
      const key = 'bob';
      final order = <int>[];

      await Future.wait<void>([
        ChatHistoryRecoveryCoordinator.instance.runExclusive(
          conversationKey: key,
          reason: 'first',
          priority: ChatHistoryRecoveryCoordinator.priorityUser,
          task: () async {
            order.add(1);
            await Future<void>.delayed(const Duration(milliseconds: 40));
            order.add(2);
          },
        ),
        ChatHistoryRecoveryCoordinator.instance.runExclusive(
          conversationKey: key,
          reason: 'second',
          priority: ChatHistoryRecoveryCoordinator.priorityUser,
          task: () async {
            order.add(3);
          },
        ),
      ]);

      expect(order, <int>[1, 2, 3]);
    });

    test('keeps only the latest trigger while a task is active', () async {
      const key = 'latest-chat';
      final gate = Completer<void>();
      final order = <int>[];

      final first = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'first',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          order.add(1);
          await gate.future;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final stale = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'stale',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async => order.add(2),
      );
      final latest = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'latest',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async => order.add(3),
      );

      gate.complete();
      await Future.wait<void>(<Future<void>>[first, stale, latest]);
      expect(order, <int>[1, 3]);
    });

    test('lifecycle invalidation drops pending recovery without running it',
        () async {
      const key = 'lifecycle-chat';
      final gate = Completer<void>();
      var runs = 0;
      final first = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'first',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          runs++;
          await gate.future;
        },
      );
      for (var i = 0; i < 20 && runs == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final pending = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'pending',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async => runs++,
      );
      ChatHistoryRecoveryCoordinator.instance.invalidateLifecycle();
      gate.complete();
      await Future.wait<void>(<Future<void>>[first, pending]);
      expect(runs, 1);
    });
  });

  group('ChatHistoryRecoveryCoordinator initial load gate', () {
    test('pre-background initial completion cannot open a new initial gate',
        () async {
      final coordinator = ChatHistoryRecoveryCoordinator.instance;
      final oldGeneration = coordinator.beginInitialLoad('resume-chat');
      coordinator.invalidateLifecycle();
      final newGeneration = coordinator.beginInitialLoad('resume-chat');
      var ran = false;
      final pending = coordinator.runExclusive(
        conversationKey: 'resume-chat',
        reason: 'app_resumed',
        priority: ChatHistoryRecoveryCoordinator.priorityForeground,
        task: () async => ran = true,
      );
      coordinator.markInitialLoadComplete('resume-chat',
          generation: oldGeneration);
      await Future<void>.delayed(Duration.zero);
      final ranBeforeNewInitialLoad = ran;
      coordinator.markInitialLoadComplete('resume-chat',
          generation: newGeneration);
      await pending;
      expect(newGeneration, greaterThan(oldGeneration));
      expect(ranBeforeNewInitialLoad, isFalse);
      expect(ran, isTrue);
    });

    test('waits for initial load completion before lower priority work',
        () async {
      const key = 'carol';
      ChatHistoryRecoveryCoordinator.instance.beginInitialLoad(key);

      var ran = false;
      final pending = ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'user',
        priority: ChatHistoryRecoveryCoordinator.priorityUser,
        task: () async {
          ran = true;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ran, isFalse);

      ChatHistoryRecoveryCoordinator.instance.markInitialLoadComplete(key);
      await pending;
      expect(ran, isTrue);
    });
  });

  group('ChatHistoryRecoveryCoordinator post-open retry', () {
    test('allows scheduling again after previous retry finishes', () async {
      const key = 'erin';
      var runs = 0;

      void schedule() {
        ChatHistoryRecoveryCoordinator.instance.schedulePostOpenRetry(
          conversationKey: key,
          conversationID: key,
          conversationType: ConvType.c2c,
          delay: Duration.zero,
          retry: ({
            required String conversationID,
            ConvType? conversationType,
          }) async {
            runs += 1;
          },
        );
      }

      schedule();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      schedule();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(runs, 2);
    });
  });

  group('ChatHistoryRecoveryCoordinator priority drop', () {
    test('drops lower-priority task while higher-priority task is active',
        () async {
      const key = 'dave';
      final gate = Completer<void>();
      var backgroundRan = false;

      unawaited(
        ChatHistoryRecoveryCoordinator.instance.runExclusive(
          conversationKey: key,
          reason: 'user',
          priority: ChatHistoryRecoveryCoordinator.priorityUser,
          task: () async {
            await gate.future;
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      await ChatHistoryRecoveryCoordinator.instance.runExclusive(
        conversationKey: key,
        reason: 'background',
        priority: ChatHistoryRecoveryCoordinator.priorityBackground,
        task: () async {
          backgroundRan = true;
        },
      );

      expect(backgroundRan, isFalse);
      gate.complete();
    });
  });
}
