import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/conversation_projection_reason.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

V2TimConversation _c2c(String id, {int orderkey = 0, int unread = 0}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    orderkey: orderkey,
    unreadCount: unread,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const owner = 'chat_session_business_projection_owner';
  final store = ConversationLocalStore.instance;
  final controller = ChatSessionController.instance;

  setUp(() async {
    store.debugOwnerUserId = owner;
    await store.clearForOwner(owner);
    ConversationTabStore.instance.clear();
    controller.clearSessionProjection();
  });

  tearDown(() async {
    ConversationTabStore.instance.clear();
    controller.clearSessionProjection();
    await store.clearForOwner(owner);
    store.debugOwnerUserId = null;
  });

  test('business patch publishes through the SDK adapter', () async {
    final row = _c2c('c2c_controller_writer', orderkey: 9, unread: 2);

    await controller.applyProjectionBatch(
      reason: 'test_business_writer',
      upserted: [row],
      forceAdmitIds: {row.conversationID},
    );

    expect(
      controller.conversations
          .map((conversation) => conversation.conversationID),
      ['c2c_controller_writer'],
    );
    expect(
      controller.conversations
          .map((conversation) => conversation.conversationID),
      ['c2c_controller_writer'],
    );
    expect(ConversationTabStore.instance.countForType(1), 1);
  });

  test('SQLite mirror cannot replace the SDK window', () async {
    await store.upsertBatch(
      conversations: [_c2c('c2c_local_authority', orderkey: 20)],
      ownerUserId: owner,
    );
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_stale_sdk_row', orderkey: 100)],
      finished: true,
    );

    await controller.restoreProjection(
      reason: ConversationStoreProjectionReason.coldStart,
      visibleConvType: 1,
    );

    expect(
      controller.conversationAtTypeIndex(1, 0)?.conversationID,
      'c2c_stale_sdk_row',
    );
    expect(
        controller.typeIndexOfConversationId(1, 'c2c_local_authority'), isNull);
    expect(controller.totalCountForType(1), 1);
  });
}
