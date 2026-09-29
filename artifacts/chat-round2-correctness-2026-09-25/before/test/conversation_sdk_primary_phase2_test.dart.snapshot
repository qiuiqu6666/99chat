import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

V2TimConversation _c2c(String id, {int unread = 0}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    showName: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConversationSyncService sync;
  const owner = 'sdk_primary_phase2_owner';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    ConversationPerfGateLog.resetCountsForTest();
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync = ConversationSyncService.instance;
    sync.resetChatTransitionStateForTesting();
    sync.debugOwnerUserId = owner;
    ConversationLocalStore.instance.debugOwnerUserId = owner;
    await ConversationLocalStore.instance.clearForOwner(owner);
    sync.upsertBatchOverride = (rows) async => rows;
  });

  tearDown(() async {
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    sync.upsertBatchOverride = null;
    sync.resetChatTransitionStateForTesting();
    await ConversationLocalStore.instance.clearForOwner(owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('Phase2: paced sync does not drive UI when sdk-primary', () async {
    ChatSessionController.instance.ensureTabStoreBridgeAttached();

    await sync.applyPacedSyncPageToUiForTest(
      [_c2c('c2c_paced', unread: 2)],
      reason: 'typed_sync_db_only',
    );

    expect(ConversationTabStore.instance.countForType(1), 0);
    expect(
      ConversationPerfGateLog.eventCountsForTest['mirror_skip_ui'] ?? 0,
      greaterThan(0),
    );
  });

  test('Phase2: quiet does not defer UI apply when sdk-primary', () async {
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    sync.beginResumeQuietWindow(duration: const Duration(seconds: 30));

    await sync.notifyUiAfterLocalWriteForTest(
      upserted: [_c2c('c2c_quiet', unread: 1)],
    );

    expect(sync.pendingUiApplyCountForTest, 0);
    expect(ConversationTabStore.instance.countForType(1), 1);
  });

  test('listener commit projects the committed row to TabStore', () async {
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    sync.upsertBatchOverride = null;

    await sync.persistChangedForTest(
      [_c2c('c2c_listener', unread: 5)],
      reason: 'changed',
    );

    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .any((c) => c.conversationID == 'c2c_listener'),
      isTrue,
    );
    expect(
      ChatSessionController.instance.conversations
          .any((c) => c.conversationID == 'c2c_listener'),
      isTrue,
    );
  });
}
