import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationSyncService reload coalesce', () {
    setUp(() {
      ConversationSyncService.instance.resetChatTransitionStateForTesting();
      ConversationSyncService.instance.debugOwnerUserId =
          'reload_coalesce_owner';
      ConversationSyncService.instance.projectionRestoreImplOverride =
          () async {};
      ConversationSyncService.instance.markReadStoreOverride =
          (conversationID) async {};
    });

    tearDown(() {
      ConversationSyncService.instance.resetChatTransitionStateForTesting();
    });

    test('immediate reload bypasses coalesce window', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection(immediate: true);

        async.elapse(const Duration(seconds: 2));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('post-pop coalesced reloads flush once', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();

        async.elapse(const Duration(seconds: 2));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('pending projection restore flushes immediately', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.restoreSdkProjection();
        async.flushMicrotasks();
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            0);

        ConversationSyncService.instance.flushPendingProjectionRestore();
        async.flushMicrotasks();
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('open transition uses debounced SDK projection restore', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();

        ConversationSyncService.instance.restoreSdkProjection();
        async.flushMicrotasks();
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            0);

        async.elapse(const Duration(milliseconds: 80));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('global debounce coalesces reloads outside post-pop', () {
      fakeAsync((async) {
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();

        async.elapse(const Duration(milliseconds: 80));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('global debounce uses trailing schedule', () {
      fakeAsync((async) {
        ConversationSyncService.instance.restoreSdkProjection();
        async.elapse(const Duration(milliseconds: 40));
        ConversationSyncService.instance.restoreSdkProjection();
        async.elapse(const Duration(milliseconds: 40));
        ConversationSyncService.instance.restoreSdkProjection();
        async.elapse(const Duration(milliseconds: 80));

        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('immediate reload bypasses global debounce', () {
      fakeAsync((async) {
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection(immediate: true);

        async.flushMicrotasks();
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('shouldMarkReadReloadImmediately before post-pop', () {
      ConversationSyncService.instance.beginChatTransition();
      expect(
        ConversationSyncService.instance.shouldMarkReadReloadImmediately(),
        isTrue,
      );
    });

    test('shouldMarkReadReloadImmediately after post-pop scheduled', () {
      ConversationSyncService.instance.beginChatTransition();
      ConversationSyncService.instance.schedulePostPopCoalesceWindow();
      expect(
        ConversationSyncService.instance.shouldMarkReadReloadImmediately(),
        isFalse,
      );
    });

    test('schedulePostPopCoalesceWindow is idempotent', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();
        ConversationSyncService.instance.restoreSdkProjection();

        async.elapse(const Duration(seconds: 2));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('clearOnLeave sequence coalesces mark read', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.markConversationReadLocally('c2c_a');
        async.flushMicrotasks();
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            0);

        // post-pop 最短 700ms，给返回后左右滑留出手势窗口。
        async.elapse(const Duration(milliseconds: 650));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            0);

        async.elapse(const Duration(milliseconds: 100));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('post-pop flush waits for route animation before reload', () {
      fakeAsync((async) {
        ConversationSyncService.instance.beginChatTransition();
        ConversationSyncService.instance.schedulePostPopCoalesceWindow();

        ConversationSyncService.instance.restoreSdkProjection();
        async.elapse(const Duration(milliseconds: 650));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            0);

        async.elapse(const Duration(milliseconds: 100));
        expect(
            ConversationSyncService.instance.projectionRestoreInvocationCount,
            1);
      });
    });

    test('persist dedupes rapid changed events for same conversation', () {
      fakeAsync((async) {
        ConversationSyncService.instance.resetChatTransitionStateForTesting();
        ConversationSyncService.instance.debugOwnerUserId =
            'reload_coalesce_owner';
        ConversationSyncService.instance.projectionRestoreImplOverride =
            () async {};
        ConversationSyncService.instance.markReadStoreOverride =
            (conversationID) async {};
        ConversationSyncService.instance.upsertBatchOverride =
            (conversations) async => conversations;

        final first = V2TimConversation(
          conversationID: 'c2c_a',
          type: 1,
          userID: 'alice',
          unreadCount: 1,
        );
        final second = V2TimConversation(
          conversationID: 'c2c_a',
          type: 1,
          userID: 'alice',
          unreadCount: 2,
        );

        ConversationSyncService.instance.enqueuePersistChangedForTest(
          [first],
          reason: 'changed',
        );
        ConversationSyncService.instance.enqueuePersistChangedForTest(
          [second],
          reason: 'view_model_changed',
        );
        expect(
          ConversationSyncService.instance.persistFlushInvocationCount,
          0,
        );

        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        expect(
          ConversationSyncService.instance.persistFlushInvocationCount,
          1,
        );
      });
    });

    test('cumulative UIKit compatibility callbacks do not persist', () {
      fakeAsync((async) {
        final persistedBatches = <List<String>>[];
        ConversationSyncService.instance.upsertBatchOverride =
            (conversations) async {
          persistedBatches.add(
            conversations.map((item) => item.conversationID).toList(),
          );
          return conversations;
        };

        final first = V2TimConversation(
          conversationID: 'c2c_first',
          type: 1,
          userID: 'first',
        );
        final second = V2TimConversation(
          conversationID: 'c2c_second',
          type: 1,
          userID: 'second',
        );
        final third = V2TimConversation(
          conversationID: 'c2c_third',
          type: 1,
          userID: 'third',
        );

        ConversationSyncService.instance.onViewModelConversationsChanged(
          [first, second],
        );
        ConversationSyncService.instance.onViewModelConversationsChanged(
          [first, second, third],
        );
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();

        expect(persistedBatches, isEmpty);
      });
    });

    test('compatibility callback cannot start a second persistence writer',
        () async {
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      final persistedBatches = <List<String>>[];
      var writeCount = 0;
      ConversationSyncService.instance.upsertBatchOverride =
          (conversations) async {
        persistedBatches.add(
          conversations.map((item) => item.conversationID).toList(),
        );
        writeCount++;
        if (writeCount == 1) {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        return conversations;
      };

      V2TimConversation conversation(String id) => V2TimConversation(
            conversationID: 'c2c_$id',
            type: 1,
            userID: id,
          );

      final first = conversation('first');
      final second = conversation('second');
      final third = conversation('third');

      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [first, second],
        reason: 'changed',
      );
      await firstWriteStarted.future.timeout(const Duration(seconds: 1));
      await ConversationSyncService.instance.onViewModelConversationsChanged(
        [first, second, third],
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(persistedBatches, hasLength(1));
      expect(persistedBatches.first, ['c2c_first', 'c2c_second']);

      releaseFirstWrite.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(persistedBatches, hasLength(1));
    });

    test(
        'suppresses stale unread for recently left conversation during post-pop',
        () {
      ConversationSyncService.instance.beginChatTransition();
      ConversationSyncService.instance.schedulePostPopCoalesceWindow(
        conversationID: 'c2c_alice',
      );
      expect(
        ConversationSyncService.instance.shouldSuppressStaleUnreadForTest(
          'c2c_alice',
        ),
        isTrue,
      );
      expect(
        ConversationSyncService.instance.shouldSuppressStaleUnreadForTest(
          'c2c_bob',
        ),
        isFalse,
      );
    });
  });
}
