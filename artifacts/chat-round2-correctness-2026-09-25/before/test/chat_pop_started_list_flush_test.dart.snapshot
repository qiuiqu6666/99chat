import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
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

  test('pop start flushes deferred projection and notifies before leave',
      () async {
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
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 1);
    expect(
        controller.conversations.any((row) => row.conversationID == 'c2c_new'),
        isFalse);

    var notifyCount = 0;
    void onNotify() => notifyCount++;
    controller.addListener(onNotify);
    try {
      controller.flushDeferredListUiBeforeChatLeave(conversationId: 'c2c_open');
    } finally {
      controller.removeListener(onNotify);
    }

    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 0);
    expect(
        controller.conversations.any((row) => row.conversationID == 'c2c_new'),
        isTrue);
    expect(notifyCount, greaterThanOrEqualTo(1));
    // Registry is untouched: the chat is still "open" until dispose leaves it.
    expect(ActiveChatRegistry.instance.hasOpenChat, isTrue);

    // The dispose-time leave patch must still run (no dedupe short-circuit).
    ActiveChatRegistry.instance.leave('c2c_open');
    final patched = await controller.patchConversationAfterChatLeave('c2c_open');
    expect(patched, isTrue);
  });

  test('pop start flush is a no-op without pending work', () {
    final controller = ChatSessionController.instance;
    controller.setConversationsForTest([
      V2TimConversation(conversationID: 'c2c_open', userID: 'open', type: 1),
    ]);
    ActiveChatRegistry.instance
        .enter('c2c_open', conversationType: ConvType.c2c);

    var notifyCount = 0;
    void onNotify() => notifyCount++;
    controller.addListener(onNotify);
    try {
      controller.flushDeferredListUiBeforeChatLeave(conversationId: 'c2c_open');
    } finally {
      controller.removeListener(onNotify);
    }
    expect(notifyCount, 0);
  });

  test('chat page wires the pop-started flush and keeps the dispose fallback',
      () {
    final appBar =
        File('lib/src/widgets/chat_host_app_bar.dart').readAsStringSync();
    expect(appBar, contains('onPopStarted?.call()'));

    final chat = File('lib/src/chat.dart').readAsStringSync();
    expect(chat, contains('onPopStarted: _flushConversationListUiOnPopStarted'));
    expect(chat, contains('flushDeferredListUiBeforeChatLeave('));
    expect(chat, contains("'chat_dispose_leave_after_draft'"));

    final tabStore = File(
      'lib/src/services/conversation_local/conversation_tab_store.dart',
    ).readAsStringSync();
    expect(tabStore, contains('bool get hasDeferredCommittedProjection'));

    // Production code must not lean on the @visibleForTesting counter.
    final controller = File(
      'lib/src/chat_session/chat_session_controller.dart',
    ).readAsStringSync();
    expect(controller, isNot(contains('deferredCommittedProjectionCount')));
  });
}
