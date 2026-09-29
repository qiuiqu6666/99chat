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
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    ChatSessionController.instance.isFeedScrolling = () => scrolling;
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
    ActiveChatRegistry.instance.setListVisibleAlongsideChat(false);
  });

  test('realtime flags: scrolling defers feed ui apply/notify', () {
    expect(ConversationPerfFlags.deferUiNotifyWhileFeedScrolling, isTrue);
    expect(ConversationPerfFlags.deferUiNotifyWhileActiveChat, isTrue);
    expect(ConversationPerfFlags.persistUiApplyWhileFeedScrolling, isFalse);
    expect(
      ConversationPerfFlags.feedScrollUiNotifyMaxDefer.inMilliseconds,
      1200,
    );
    expect(
      ConversationPerfFlags.pendingPreviewPatchMaxWait.inMilliseconds,
      1200,
    );
  });

  test('chat leave still patches left conversation', () async {
    scrolling = false;
    ActiveChatRegistry.instance.enter(
      'c2c_active_2',
      conversationType: ConvType.c2c,
    );
    final notifier = ChatSessionController.instance;
    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [
        V2TimConversation(
          conversationID: 'c2c_active_2',
          type: 1,
          userID: 'u2',
          unreadCount: 1,
          showName: 'b',
        ),
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    ActiveChatRegistry.instance.leave('c2c_active_2');
    ConversationPerfGateLog.resetCountsForTest();
    final patched =
        await ChatSessionController.instance.patchConversationAfterChatLeave(
      'c2c_active_2',
      reason: 'chat_leave',
    );
    expect(patched, isTrue);
    expect(
      ConversationPerfGateLog.eventCountsForTest['chat_leave_patch_left'] ?? 0,
      greaterThan(0),
    );
  });

  test('scrolling holds notifications while SDK projection stays current',
      () async {
    final controller = ChatSessionController.instance;
    controller.setConversationsForTest([
      V2TimConversation(
          conversationID: 'c2c_scroll',
          userID: 'scroll',
          type: 1,
          unreadCount: 0),
    ]);
    var notifications = 0;
    void listener() => notifications++;
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));
    scrolling = true;
    controller.isFeedScrolling = () => scrolling;
    await sync.notifyUiAfterLocalWriteForTest(upserted: [
      V2TimConversation(
          conversationID: 'c2c_scroll',
          userID: 'scroll',
          type: 1,
          unreadCount: 2),
    ]);
    expect(controller.conversations.single.unreadCount, 2);
    expect(sync.pendingUiApplyCountForTest, 0);
    expect(notifications, 0);
    scrolling = false;
    controller.flushDeferredUiNotifyIfNeeded(reason: 'scroll_end');
    expect(notifications, 1);
  });

  test('chat structure changes wait in TabStore and appear on leave', () async {
    final controller = ChatSessionController.instance;
    controller.setConversationsForTest([
      V2TimConversation(conversationID: 'c2c_open', userID: 'open', type: 1),
    ]);
    ActiveChatRegistry.instance
        .enter('c2c_open', conversationType: ConvType.c2c);
    await controller.applyConversationsFromStoreForTest(upserted: [
      V2TimConversation(
          conversationID: 'c2c_new', userID: 'new', type: 1, unreadCount: 1),
    ], forceAdmitIds: {
      'c2c_new'
    });
    expect(sync.pendingUiApplyCountForTest, 0);
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 1);
    expect(
        controller.conversations.any((row) => row.conversationID == 'c2c_new'),
        isFalse);
    ActiveChatRegistry.instance.leave('c2c_open');
    await controller.patchConversationAfterChatLeave('c2c_open');
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 0);
    expect(
        controller.conversations.any((row) => row.conversationID == 'c2c_new'),
        isTrue);
  });

  test('desktop split pane publishes list updates while chat stays open',
      () async {
    final controller = ChatSessionController.instance;
    controller.setConversationsForTest([
      V2TimConversation(conversationID: 'c2c_open', userID: 'open', type: 1),
    ]);
    ActiveChatRegistry.instance.setListVisibleAlongsideChat(true);
    ActiveChatRegistry.instance
        .enter('c2c_open', conversationType: ConvType.c2c);
    await controller.applyConversationsFromStoreForTest(upserted: [
      V2TimConversation(
          conversationID: 'c2c_new', userID: 'new', type: 1, unreadCount: 1),
    ], forceAdmitIds: {
      'c2c_new'
    });
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 0);
    expect(
        controller.conversations.any((row) => row.conversationID == 'c2c_new'),
        isTrue);
  });
}
