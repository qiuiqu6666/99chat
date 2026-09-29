import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

const _owner = 'preview_monotonic_owner';
const _conversationId = 'c2c_preview_peer';

V2TimMessage _message({
  required String id,
  required int timestamp,
  String seq = '',
  int status = 2,
  bool isSelf = false,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': id,
    'message_server_time': timestamp,
    'message_seq': seq,
    'message_status': status,
    'message_is_from_self': isSelf,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
    'message_conv_type': 1,
    'message_conv_id': 'preview_peer',
    'message_elem_array': const <dynamic>[],
  });
  message
    ..timestamp = timestamp
    ..seq = seq
    ..status = status
    ..isSelf = isSelf
    ..elemType = 1;
  return message;
}

V2TimConversation _conversation({
  required String messageId,
  required int timestamp,
  int? orderkey,
  int unread = 0,
  String seq = '',
}) {
  return V2TimConversation(
    conversationID: _conversationId,
    type: 1,
    userID: 'preview_peer',
    unreadCount: unread,
    orderkey: orderkey ?? timestamp,
    lastMessage: _message(id: messageId, timestamp: timestamp, seq: seq),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    ConversationLocalStore.bypassUpsertCoalesceForTest = true;
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    ConversationSyncService.instance.resetChatTransitionStateForTesting();
    ConversationSyncService.instance.debugOwnerUserId = _owner;
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    ChatSessionController.instance.clearSessionProjection();
    await ConversationLocalStore.instance.clearForOwner(_owner);
  });

  tearDown(() async {
    ConversationSyncService.instance.resetChatTransitionStateForTesting();
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    ChatSessionController.instance.clearSessionProjection();
    await ConversationLocalStore.instance.clearForOwner(_owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
    ConversationLocalStore.bypassUpsertCoalesceForTest = false;

    ConversationTabStore.instance.clear();
  });

  test('realtime preview survives an older page in the same persist window',
      () async {
    final storedOld =
        _conversation(messageId: 'old', timestamp: 100, unread: 0);
    final liveOld = _conversation(messageId: 'old', timestamp: 100, unread: 0);
    final lateOld = _conversation(messageId: 'old', timestamp: 100, unread: 0);
    final fresh = _conversation(messageId: 'new', timestamp: 200, unread: 1);
    await ConversationLocalStore.instance.upsertBatch(
      ownerUserId: _owner,
      conversations: <V2TimConversation>[storedOld],
    );
    ChatSessionController.instance
        .replaceProjectionForTest(<V2TimConversation>[liveOld]);
    ChatSessionController.instance.applyLastMessageLocally(
      conversationID: _conversationId,
      message: fresh.lastMessage!,
      bumpUnread: true,
    );

    ConversationSyncService.instance.enqueuePersistChangedForTest(
      <V2TimConversation>[fresh],
      reason: 'changed',
    );
    ConversationSyncService.instance.enqueuePersistChangedForTest(
      <V2TimConversation>[lateOld],
      reason: 'view_model_page',
    );
    await ConversationSyncService.instance
        .flushPersistChangedForTest(reason: 'view_model_page');

    final stored = await ConversationLocalStore.instance.conversationById(
      _conversationId,
      ownerUserId: _owner,
    );
    expect(stored?.lastMessage?.msgID, 'new');
    expect(
      ChatSessionController.instance.conversations.single.lastMessage?.msgID,
      'new',
    );

    await ChatSessionController.instance.refreshTypeTotals();
    await ChatSessionController.instance.ensureTypeIndexHydrated(
      convType: 1,
      centerIndex: 0,
      forceReload: true,
      allowWindowJump: true,
    );
    expect(
      ChatSessionController.instance
          .conversationAtTypeIndex(1, 0)
          ?.lastMessage
          ?.msgID,
      'new',
    );
  });

  test('two inbound preview patches increment unread exactly once each',
      () async {
    final old = _conversation(messageId: 'old', timestamp: 100, unread: 0);
    await ConversationLocalStore.instance.upsertBatch(
      ownerUserId: _owner,
      conversations: <V2TimConversation>[old],
    );
    ChatSessionController.instance.replaceProjectionForTest(
      <V2TimConversation>[old],
    );

    var sdkSnapshot = old;
    ConversationSyncService.instance.debugGetConversationOverride = (_) async {
      return _conversation(
        messageId: sdkSnapshot.lastMessage?.msgID ?? 'old',
        timestamp: sdkSnapshot.lastMessage?.timestamp ?? 100,
        unread: sdkSnapshot.unreadCount ?? 0,
      );
    };

    final first = _message(id: 'in-1', timestamp: 200);
    await ConversationSyncService.instance.patchConversationLastMessage(
      conversationID: _conversationId,
      message: first,
    );
    await ConversationSyncService.instance.flushPersistChangedForTest(
      reason: 'inbound_first',
    );

    expect(
      ChatSessionController.instance.conversations.single.unreadCount,
      1,
    );
    expect(
      ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum,
      1,
    );

    sdkSnapshot = _conversation(messageId: 'in-1', timestamp: 200, unread: 1);
    final second = _message(id: 'in-2', timestamp: 300);
    await ConversationSyncService.instance.patchConversationLastMessage(
      conversationID: _conversationId,
      message: second,
    );
    await ConversationSyncService.instance.flushPersistChangedForTest(
      reason: 'inbound_second',
    );

    expect(
      ChatSessionController.instance.conversations.single.unreadCount,
      2,
    );
    expect(
      ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum,
      2,
    );
    final stored = await ConversationLocalStore.instance.conversationById(
      _conversationId,
      ownerUserId: _owner,
    );
    expect(stored?.unreadCount, 2);
    expect(stored?.lastMessage?.msgID, 'in-2');
  });

  for (final sdkPrimary in <bool>[true]) {
    test('group commit updates tab immediately with sdkPrimary=$sdkPrimary',
        () async {
      const groupId = '@TGS#badge_realtime';
      const conversationId = 'group_$groupId';
      V2TimConversation snapshot(int unread) => V2TimConversation(
            conversationID: conversationId,
            type: 2,
            groupID: groupId,
            groupType: 'Public',
            unreadCount: unread,
            recvOpt: 0,
            lastMessage: _message(id: 'group-$unread', timestamp: 100 + unread),
          );
      await ConversationLocalStore.instance.upsertBatch(
        ownerUserId: _owner,
        conversations: [snapshot(0)],
      );
      ChatSessionController.instance.replaceProjectionForTest([snapshot(0)]);
      ConversationTabStore.instance.notifyColdStartEnded();
      for (var count = 1; count <= 3; count++) {
        // Match inbound preview: the row moves ahead before its DB commit,
        // while aggregate updates are intentionally left to the commit.
        ChatSessionController.instance.applyLastMessageLocally(
          conversationID: conversationId,
          message: snapshot(count).lastMessage!,
          bumpUnread: true,
          updateUnreadAggregate: false,
        );
        ConversationSyncService.instance.enqueuePersistChangedForTest(
          [snapshot(count)],
          reason: 'changed',
        );
        await ConversationSyncService.instance
            .flushPersistChangedForTest(reason: 'changed');
        expect(ConversationUnreadAggregate.instance.groupNotifiableUnreadSum,
            count);
        expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 0);
      }
    });
  }

  test('a huge old orderkey cannot roll back coordinator lastMessage',
      () async {
    final bridge = ConversationMutationShadowBridge.instance;
    await bridge.prepareSdkConversationCommits(
      ownerUserId: _owner,
      conversations: <V2TimConversation>[
        _conversation(messageId: 'new', timestamp: 200, orderkey: 200),
      ],
      source: ConversationMutationSource.sdkRealtime,
    );
    await bridge.prepareSdkConversationCommits(
      ownerUserId: _owner,
      conversations: <V2TimConversation>[
        _conversation(
          messageId: 'old',
          timestamp: 100,
          orderkey: 999999999,
        ),
      ],
      source: ConversationMutationSource.sdkPage,
    );

    final snapshot = bridge.coordinator.snapshot(
      ownerUserId: _owner,
      conversationId: _conversationId,
      conversationType: ConversationMutationConversationType.c2c,
    );
    final last = snapshot?.values[ConversationMutationField.lastMessage]
        as ConversationShadowLastMessage?;
    expect(last?.messageId, 'new');
    expect(last?.timestamp, 200);
  });

  test('delete reconciles a stale visible preview from committed store',
      () async {
    final committedPrevious =
        _conversation(messageId: 'previous', timestamp: 100);
    await ConversationLocalStore.instance.upsertBatch(
      ownerUserId: _owner,
      conversations: <V2TimConversation>[committedPrevious],
    );
    final staleVisible = _conversation(messageId: 'deleted', timestamp: 200);
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: <V2TimConversation>[staleVisible],
      finished: true,
    );

    await ConversationSyncService.instance.onConversationMessagesDeleted(
      conversationID: _conversationId,
      deletedMsgIDs: const <String>['deleted'],
      fallbackLastMessage: committedPrevious.lastMessage,
    );

    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage?.msgID,
      'previous',
    );
    final stored = await ConversationLocalStore.instance.conversationById(
      _conversationId,
      ownerUserId: _owner,
    );
    expect(stored?.lastMessage?.msgID, 'previous');
  });
}
