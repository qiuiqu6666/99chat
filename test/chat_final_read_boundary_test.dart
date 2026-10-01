import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationLocalStore.instance;
  final aggregate = ConversationUnreadAggregate.instance;

  V2TimConversation row(String conversation, String id, int count,
          {int time = 100, int seq = 10}) =>
      V2TimConversation(
        conversationID: conversation,
        groupID: conversation.startsWith('group_') ? conversation.substring(6) : null,
        userID: conversation.startsWith('c2c_') ? 'peer' : null,
        type: conversation.startsWith('group_') ? 2 : 1,
        unreadCount: count,
        lastMessage: V2TimMessage.fromJson({
          'message_msg_id': id,
          'message_server_time': time,
          'message_is_from_self': false,
          'message_risk_type_identified': 0,
        })
          ..timestamp = time
          ..seq = '$seq',
      );

  setUp(() async {
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
    SharedPreferences.setMockInitialValues({});
    store.debugOwnerUserId = 'final-boundary-owner';
    aggregate.resetForTest();
  });
  tearDown(() async {
    await store.flushReadBarrierWritesForTest();
    aggregate.resetForTest();
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = null;
  });

  for (final (conversation, nextTime) in [
    ('group_@TGS#final_peer', 101),
    ('c2c_peer', 100),
    ('c2c_peer', 101),
  ]) {
    test('$conversation new unread survives old zero at time=$nextTime', () {
      store.recordReadClearedAnchor(conversation,
          reliableReadTarget: true,
          lastMessageId: 'read-a',
          lastMessageTimestamp: 100,
          lastMessageSeq: 10);
      aggregate.applySdkConversations([row(conversation, 'read-a', 0)]);
      aggregate.applySdkConversations([
        row(conversation, 'new-b', 1, time: nextTime, seq: 11)
      ]);
      expect(aggregate.projectedUnreadCountFor(conversation), 1);
      aggregate.applySdkConversations([row(conversation, 'read-a', 0)]);
      expect(aggregate.sdkUnreadCountFor(conversation), 0,
          reason: 'the raw SDK snapshot stays independent');
      expect(aggregate.projectedUnreadCountFor(conversation), 1,
          reason: 'an older target snapshot cannot cover the newer identity');
      aggregate.applySdkConversations([
        row(conversation, 'new-b', 0, time: nextTime, seq: 11)
      ]);
      expect(aggregate.projectedUnreadCountFor(conversation), 0);
    });
  }

  for (final conversation in ['group_@TGS#final_peer', 'c2c_peer']) {
    test('$conversation authoritative read fence can cover the newer identity',
        () {
      store.recordReadClearedAnchor(conversation,
          reliableReadTarget: true,
          lastMessageId: 'read-a',
          lastMessageTimestamp: 100,
          lastMessageSeq: 10);
      aggregate.applySdkConversations([row(conversation, 'read-a', 0)]);
      aggregate.applySdkConversations([
        row(conversation, 'new-b', 1, time: 101, seq: 11)
      ]);
      final covering = row(conversation, 'read-a', 0)
        ..groupReadSequence = 11
        ..c2cReadTimestamp = 102;
      aggregate.applySdkConversations([covering]);
      expect(aggregate.projectedUnreadCountFor(conversation), 0);
    });
  }

  test('confirmed same-second IDs survive restart and do not cover a new ID',
      () async {
    const id = 'c2c_peer';
    store.recordReadClearedAnchor(id,
        reliableReadTarget: true,
        lastMessageId: 'read-a',
        lastMessageTimestamp: 100);
    aggregate.applySdkConversations([row(id, 'read-a', 0)]);
    store.recordReadClearedAnchor(id,
        reliableReadTarget: true,
        lastMessageId: 'read-b',
        lastMessageTimestamp: 100);
    aggregate.applySdkConversations([row(id, 'read-b', 0)]);
    await store.flushReadBarrierWritesForTest();
    final prefs = await SharedPreferences.getInstance();
    final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    store.resetAnchorStateForTest();
    aggregate.resetForTest();
    SharedPreferences.setMockInitialValues(disk);
    await store.restoreReadBarriers();
    store.debugOwnerUserId = 'final-boundary-owner';
    final target = store.readBarrierFor(id)!;
    expect(target.confirmedReadMessageIds, containsAll(['read-a', 'read-b']));
    aggregate.applySdkConversations([row(id, 'read-a', 4)]);
    expect(aggregate.projectedUnreadCountFor(id), 0);
    aggregate.applySdkConversations([row(id, 'new-c', 1)]);
    expect(aggregate.projectedUnreadCountFor(id), 1);
  });
}
