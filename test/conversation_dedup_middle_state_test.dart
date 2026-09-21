import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

/// Plan 093 契约测试：实时去重层不得丢失「中间状态」。
///
/// 目标行为（修复后）：
/// - 同一会话两条先后到达的事件，各自独立进入 Coordinator 字段权威裁决；
///   若后到事件来自更低权威来源（如 sdkPage），不得覆盖先到的高权威值。
/// - flush 进行中又有新事件到达，新事件必须进入下一次 flush，不得被丢弃。
/// - 切账号后尾随 flush 不写旧 owner 数据（现有 beginOwnerGeneration 防护的回归确认）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConversationSyncService persist middle-state', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      ConversationSyncService.instance.resetChatTransitionStateForTesting();
      ConversationSyncService.instance.debugOwnerUserId =
          'persist_middle_state_owner';
      ConversationSyncService.instance.projectionRestoreImplOverride =
          () async {};
      ConversationSyncService.instance.markReadStoreOverride =
          (conversationID) async {};
    });

    tearDown(() {
      ConversationSyncService.instance.resetChatTransitionStateForTesting();
    });

    test('rapid changed events preserve each non-identical state', () async {
      final persistedBatches = <List<int?>>[];
      ConversationSyncService.instance.upsertBatchOverride =
          (conversations) async {
        persistedBatches.add(
          conversations.map((item) => item.unreadCount).toList(),
        );
        return conversations;
      };

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
        reason: 'changed',
      );
      await ConversationSyncService.instance
          .flushPersistChangedForTest(reason: 'changed');

      expect(persistedBatches, hasLength(1));
      expect(persistedBatches.single, <int?>[1, 2]);
    });

    test('different sources are preserved in arrival order', () async {
      final persistedBatches = <List<int?>>[];
      ConversationSyncService.instance.upsertBatchOverride =
          (conversations) async {
        persistedBatches.add(
          conversations.map((item) => item.unreadCount).toList(),
        );
        return conversations;
      };

      final realtime = V2TimConversation(
        conversationID: 'c2c_ra',
        type: 1,
        userID: 'ra',
        unreadCount: 5,
        orderkey: 200,
      );
      final page = V2TimConversation(
        conversationID: 'c2c_ra',
        type: 1,
        userID: 'ra',
        unreadCount: 3,
        orderkey: 199,
      );

      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [realtime],
        reason: 'changed',
        source: ConversationMutationSource.sdkRealtime,
      );
      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [page],
        reason: 'view_model_page',
        source: ConversationMutationSource.sdkPage,
      );
      await ConversationSyncService.instance
          .flushPersistChangedForTest(reason: 'view_model_page');

      expect(persistedBatches, <List<int?>>[
        <int?>[5],
        <int?>[3],
      ]);
    });

    test('new event during in-flight flush enters next flush', () async {
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

      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [first, second],
        reason: 'changed',
      );
      await firstWriteStarted.future.timeout(const Duration(seconds: 1));
      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [first, second, third],
        reason: 'changed',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(persistedBatches, hasLength(1));
      expect(persistedBatches.first, ['c2c_first', 'c2c_second']);

      releaseFirstWrite.complete();
      await ConversationSyncService.instance
          .flushPersistChangedForTest(reason: 'changed');
      expect(persistedBatches, hasLength(2));
      expect(persistedBatches.last, ['c2c_third']);
    });

    test('same source keeps each distinct fingerprint', () async {
      final persistedBatches = <List<int?>>[];
      ConversationSyncService.instance.upsertBatchOverride =
          (conversations) async {
        persistedBatches.add(
          conversations.map((item) => item.unreadCount).toList(),
        );
        return conversations;
      };

      final first = V2TimConversation(
        conversationID: 'c2c_dup',
        type: 1,
        userID: 'dup',
        unreadCount: 1,
      );
      final second = V2TimConversation(
        conversationID: 'c2c_dup',
        type: 1,
        userID: 'dup',
        unreadCount: 2,
      );
      final third = V2TimConversation(
        conversationID: 'c2c_dup',
        type: 1,
        userID: 'dup',
        unreadCount: 3,
      );

      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [first],
        reason: 'changed',
      );
      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [second],
        reason: 'changed',
      );
      ConversationSyncService.instance.enqueuePersistChangedForTest(
        [third],
        reason: 'changed',
      );
      await ConversationSyncService.instance
          .flushPersistChangedForTest(reason: 'changed');

      expect(persistedBatches, hasLength(1));
      expect(persistedBatches.single, <int?>[1, 2, 3]);
    });
  });
}
