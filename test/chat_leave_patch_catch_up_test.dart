import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConversationSyncService sync;
  var scrolling = false;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    ConversationPerfGateLog.resetCountsForTest();
    ConversationPerfGateLog.skipUnreadAggregateScheduleForTest = true;
    sync = ConversationSyncService.instance;
    scrolling = false;
    ChatSessionController.instance.isFeedScrolling = () => scrolling;
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync.resetChatTransitionStateForTesting();
    ActiveChatRegistry.instance.reset();
  });

  tearDown(() {
    ConversationPerfGateLog.skipUnreadAggregateScheduleForTest = false;
    ChatSessionController.instance.isFeedScrolling = null;
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync.resetChatTransitionStateForTesting();
    ActiveChatRegistry.instance.reset();
  });

  test('active chat apply records dirty and leave patch dedupes', () async {
    expect(ConversationPerfFlags.chatLeavePatchLeftOnlyEnabled, isTrue);
    expect(ConversationPerfFlags.chatLeaveFlushDedupeEnabled, isTrue);

    ActiveChatRegistry.instance.enter(
      'c2c_leave_1',
      conversationType: ConvType.c2c,
    );
    final notifier = ChatSessionController.instance;
    var notifyCount = 0;
    void onNotify() => notifyCount++;
    notifier.addListener(onNotify);
    addTearDown(() => notifier.removeListener(onNotify));

    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [
        V2TimConversation(
          conversationID: 'c2c_leave_1',
          type: 1,
          userID: 'u1',
          unreadCount: 2,
          showName: 'a',
        ),
        V2TimConversation(
          conversationID: 'c2c_leave_other',
          type: 1,
          userID: 'u2',
          unreadCount: 1,
          showName: 'b',
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount,
        greaterThan(0));

    final notifyBeforeLeave = notifyCount;
    ActiveChatRegistry.instance.leave('c2c_leave_1');
    ConversationPerfGateLog.resetCountsForTest();

    final first =
        await ChatSessionController.instance.patchConversationAfterChatLeave(
      'c2c_leave_1',
      reason: 'chat_leave_deactivate',
    );
    final second =
        await ChatSessionController.instance.patchConversationAfterChatLeave(
      'c2c_leave_1',
      reason: 'chat_leave_dispose',
    );
    expect(first, isTrue);
    expect(second, isFalse);
    expect(
      ConversationPerfGateLog.eventCountsForTest['chat_leave_patch_left'] ?? 0,
      1,
    );
    expect(
      ConversationPerfGateLog
              .eventCountsForTest['chat_leave_flush_skipped_dedupe'] ??
          0,
      1,
    );
    expect(
      ConversationPerfGateLog.eventCountsForTest['ui_notify_flush'] ?? 0,
      0,
      reason: 'leave 不应走整表 deferred flush，只刷挂起的 pending notify',
    );
    expect(
      ConversationPerfGateLog
              .eventCountsForTest['chat_leave_flush_pending_notify'] ??
          0,
      1,
    );
    expect(notifyCount, greaterThan(notifyBeforeLeave));
    expect(notifier.isPostChatLeaveQuiet, isTrue);
  });

  test('leave flushes deferred notify so in-chat new conversation appears',
      () async {
    ActiveChatRegistry.instance.enter(
      'c2c_leave_current',
      conversationType: ConvType.c2c,
    );
    final notifier = ChatSessionController.instance;
    var notifyCount = 0;
    void onNotify() => notifyCount++;
    notifier.addListener(onNotify);
    addTearDown(() => notifier.removeListener(onNotify));

    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [
        V2TimConversation(
          conversationID: 'c2c_leave_current',
          type: 1,
          userID: 'current',
          unreadCount: 0,
          showName: 'current',
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final notifyAfterSeed = notifyCount;

    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [
        V2TimConversation(
          conversationID: 'c2c_new_during_chat',
          type: 1,
          userID: 'peer',
          unreadCount: 1,
          showName: 'peer',
          orderkey: 999,
        ),
      ],
      forceAdmitIds: const {'c2c_new_during_chat'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(notifyCount, notifyAfterSeed, reason: '聊中 Feed notify 应被 defer');
    expect(
      notifier.conversations.any(
        (c) => c.conversationID == 'c2c_new_during_chat',
      ),
      isFalse,
    );

    ActiveChatRegistry.instance.leave('c2c_leave_current');
    await ChatSessionController.instance.patchConversationAfterChatLeave(
      'c2c_leave_current',
      reason: 'chat_leave_deactivate',
    );
    expect(notifyCount, greaterThan(notifyAfterSeed));
    expect(
      ConversationPerfGateLog
              .eventCountsForTest['chat_leave_flush_pending_notify'] ??
          0,
      greaterThan(0),
    );
    expect(
      notifier.conversations.any(
        (c) => c.conversationID == 'c2c_new_during_chat',
      ),
      isTrue,
    );
  });

  test('flushDeferred chat_leave redirects when left-only enabled', () async {
    ActiveChatRegistry.instance.enter(
      'c2c_redirect_1',
      conversationType: ConvType.c2c,
    );
    final notifier = ChatSessionController.instance;
    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [
        V2TimConversation(
          conversationID: 'c2c_redirect_1',
          type: 1,
          userID: 'u1',
          unreadCount: 1,
          showName: 'a',
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    ActiveChatRegistry.instance.leave('c2c_redirect_1');
    ConversationPerfGateLog.resetCountsForTest();
    ChatSessionController.instance.flushDeferredUiNotifyIfNeeded(
      reason: 'chat_leave_dispose',
    );
    expect(
      ConversationPerfGateLog
              .eventCountsForTest['ui_notify_flush_redirect_leave'] ??
          0,
      greaterThan(0),
    );
    expect(
      ConversationPerfGateLog.eventCountsForTest['ui_notify_flush'] ?? 0,
      0,
    );
  });

  test('leave overlay copies persisted draft onto an empty projection row', () {
    final projected = V2TimConversation(
      conversationID: 'c2c_leave_draft',
      type: 1,
      userID: 'leave_draft',
      showName: 'peer',
      unreadCount: 3,
    );
    final persisted = V2TimConversation(
      conversationID: 'c2c_leave_draft',
      type: 1,
      userID: 'leave_draft',
    )..draftText = 'typed draft';

    final overlay = ChatSessionController.overlayDraftForChatLeave(
      projected: projected,
      persisted: persisted,
    );
    expect(overlay?.draftText, 'typed draft');
    expect(overlay?.showName, 'peer');
    expect(overlay?.unreadCount, 3);
    expect(
      ChatSessionController.explicitDraftIdsForChatLeave(
        conversationId: 'c2c_leave_draft',
        snapshot: overlay!,
      ),
      {'c2c_leave_draft'},
    );
  });

  test('leave overlay does not explicit-commit an empty draft', () {
    final projected = V2TimConversation(
      conversationID: 'c2c_leave_empty',
      type: 1,
      userID: 'leave_empty',
    );
    final overlay = ChatSessionController.overlayDraftForChatLeave(
      projected: projected,
      persisted: V2TimConversation(
        conversationID: 'c2c_leave_empty',
        type: 1,
        userID: 'leave_empty',
      ),
    );
    expect(overlay?.draftText, isNull);
    expect(
      ChatSessionController.explicitDraftIdsForChatLeave(
        conversationId: 'c2c_leave_empty',
        snapshot: overlay!,
      ),
      isEmpty,
    );
  });
}
