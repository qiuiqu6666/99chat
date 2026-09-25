import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

V2TimConversation row(String id, String message, int timestamp,
        {int seq = 0}) =>
    V2TimConversation(
      conversationID: id,
      type: id.startsWith('group_') ? 2 : 1,
      unreadCount: 3,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': message,
        'message_server_time': timestamp,
        'message_is_from_self': false,
        'message_risk_type_identified': 0,
      })
        ..timestamp = timestamp
        ..seq = '$seq',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationLocalStore.instance;

  setUp(() async {
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
  });

  Future<void> restart() async {
    await store.flushReadBarrierWritesForTest();
    final prefs = await SharedPreferences.getInstance();
    final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    store.resetAnchorStateForTest();
    SharedPreferences.setMockInitialValues(disk);
    await store.restoreReadBarriers();
  }

  test('own reply does not restore old unread or swallow delayed peer message', () async {
    store.recordReadClearedAnchor('c2c_peer', ownerUserId: 'alice',
        lastMessageId: 'seen', lastMessageTimestamp: 100);
    await restart();
    store.debugOwnerUserId = 'alice';
    final aggregate = ConversationUnreadAggregate.instance;
    aggregate.resetForTest();
    addTearDown(aggregate.resetForTest);
    final own = row('c2c_peer', 'reply', 102);
    own.lastMessage!.isSelf = true;
    aggregate.applySdkConversations([own]);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
    expect(store.readBarrierFor('c2c_peer')?.lastMessageId, 'seen');
    final delayed = row('c2c_peer', 'new-peer', 101);
    delayed.lastMessage!.isSelf = false;
    aggregate.applySdkConversations([delayed]);
    expect(aggregate.c2cNotifiableUnreadSum, 3);
  });

  test('own reply preserves known unread peer message in the same second', () {
    store.recordReadClearedAnchor('c2c_peer', ownerUserId: 'alice',
        lastMessageId: 'seen', lastMessageTimestamp: 100);
    final unread = row('c2c_peer', 'unseen-peer', 100);
    final own = row('c2c_peer', 'reply', 102);
    own.lastMessage!.isSelf = true;
    final count = ConversationUnreadGuard.resolveForListApply(
      conversationId: 'c2c_peer', existingUnread: 3,
      existingLastMessage: unread.lastMessage, incoming: own, ownerUserId: 'alice',
    );
    expect(count, 3);
  });

  for (final id in ['c2c_peer', 'group_peer']) {
    test('$id read survives process restart and rejects old SDK unread',
        () async {
      store.recordReadClearedAnchor(id,
          ownerUserId: 'alice',
          lastMessageId: 'seen',
          lastMessageTimestamp: 100,
          lastMessageSeq: 20);
      await restart();
      final replay = row(id, 'seen', 100, seq: 20);
      store.resolveSdkUnreadAgainstReadBarrier(replay, ownerUserId: 'alice');
      expect(replay.unreadCount, 0);
      final older = row(id, 'older', 99, seq: 19);
      store.resolveSdkUnreadAgainstReadBarrier(older, ownerUserId: 'alice');
      expect(older.unreadCount, 0);

      final anotherAccount = row(id, 'seen', 100, seq: 20);
      store.resolveSdkUnreadAgainstReadBarrier(anotherAccount,
          ownerUserId: 'bob');
      expect(anotherAccount.unreadCount, 3);

      final newer = row(id, 'new', 101, seq: 21);
      store.resolveSdkUnreadAgainstReadBarrier(newer, ownerUserId: 'alice');
      expect(newer.unreadCount, 3);
      await restart();
      expect(store.readBarrierFor(id, ownerUserId: 'alice'), isNull);
    });
  }

  test('different C2C message in same second remains unread after restart',
      () async {
    store.recordReadClearedAnchor('c2c_peer',
        ownerUserId: 'alice', lastMessageId: 'seen', lastMessageTimestamp: 100);
    await restart();
    final unseen = row('c2c_peer', 'unseen', 100);
    store.resolveSdkUnreadAgainstReadBarrier(unseen, ownerUserId: 'alice');
    expect(unseen.unreadCount, 3);
    final replay = row('c2c_peer', 'seen', 100);
    store.resolveSdkUnreadAgainstReadBarrier(replay, ownerUserId: 'alice');
    expect(replay.unreadCount, 0);
  });
}
