// P0-1: 群 SDK seq（量级 ~40）与 C2C SDK timestamp（量级 ~1.7e9）数值域混用
// 测试。修复前直接 `<` 比较会让所有群 unread 增量被判 stale 拒绝。
//
// 本测试直接走 mergeConversationUnreadForTest（@visibleForTesting 入口）。
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

V2TimConversation _build({
  required String convId,
  required int type,
  required int unread,
  required String? seq,
  required int? timestamp,
}) {
  return V2TimConversation(
    conversationID: convId,
    type: type,
    unreadCount: unread,
    lastMessage: V2TimMessage.fromJson(<String, dynamic>{
      'message_server_time': timestamp ?? 0,
      'message_msg_id': '$convId-${seq ?? timestamp}',
      'message_seq': seq ?? '',
      'message_rand': 0,
      'message_is_from_self': false,
      'message_status': 2,
      'message_custom_str': '',
      'message_risk_type_identified': 0,
      'message_sender_group_member_info': <String, dynamic>{},
      'message_group_at_user_array': <String>[],
    })..elemType = 1,
  );
}

void main() {
  test('missing group seq never poisons the watermark with timestamp', () {
    final store = ConversationLocalStore.instance;
    final existing = _build(convId: 'group_missing_seq', type: 2,
        unread: 1, seq: '5', timestamp: 1788000000);
    final missing = _build(convId: 'group_missing_seq', type: 2,
        unread: 2, seq: null, timestamp: 1788000001);
    store.mergeConversationUnreadForTest(existing: existing, incoming: missing,
        owner: 'missing_owner', conversationId: 'group_missing_seq', readClearedAtMs: 0);
    final stale = _build(convId: 'group_missing_seq', type: 2,
        unread: 9, seq: '4', timestamp: 1788000002);
    store.mergeConversationUnreadForTest(existing: missing, incoming: stale,
        owner: 'missing_owner', conversationId: 'group_missing_seq', readClearedAtMs: 0);
    expect(stale.unreadCount, missing.unreadCount,
        reason: 'unknown snapshot must not erase the last known seq');
    final next = _build(convId: 'group_missing_seq', type: 2,
        unread: 3, seq: '6', timestamp: 1788000002);
    store.mergeConversationUnreadForTest(existing: missing, incoming: next,
        owner: 'missing_owner', conversationId: 'group_missing_seq', readClearedAtMs: 0);
    expect(next.unreadCount, 3);
  });

  test('C2C missing timestamp cannot seed a sender-seq watermark', () {
    final store = ConversationLocalStore.instance;
    final existing = _build(convId: 'c2c_missing_ts', type: 1,
        unread: 1, seq: '4000000000', timestamp: null);
    final next = _build(convId: 'c2c_missing_ts', type: 1,
        unread: 2, seq: '2', timestamp: 1788000000);
    store.mergeConversationUnreadForTest(existing: existing, incoming: next,
        owner: 'missing_ts_owner', conversationId: 'c2c_missing_ts', readClearedAtMs: 0);
    expect(next.unreadCount, 2);
  });

  tearDown(() async {
    ConversationLocalStore.instance.resetAnchorStateForTest();
  });

  group('sdk unread generation domain isolation (P0-1)', () {
    test('group seq=40 is accepted when no prior watermark exists', () {
      final store = ConversationLocalStore.instance;
      final existing = _build(
        convId: 'group_m2TEST',
        type: 2,
        unread: 0,
        seq: null,
        timestamp: null,
      );
      final incoming = _build(
        convId: 'group_m2TEST',
        type: 2,
        unread: 3,
        seq: '40',
        timestamp: 0,
      );
      // P0-1: group domain watermark empty → 40 > 0 → accept.
      expect(
        () => store.mergeConversationUnreadForTest(
          existing: existing,
          incoming: incoming,
          owner: 'owner_a',
          conversationId: 'group_m2TEST',
          readClearedAtMs: 0,
        ),
        returnsNormally,
      );
      expect(incoming.unreadCount, 3,
          reason: 'accepted; unread not zeroed by stale-generation check');
    });

    test('c2c timestamp is accepted even though it is much larger than group '
        'seq — domain isolation', () {
      final store = ConversationLocalStore.instance;
      final existing = _build(
        convId: 'c2c_userA',
        type: 1,
        unread: 0,
        seq: null,
        timestamp: null,
      );
      final incoming = _build(
        convId: 'c2c_userA',
        type: 1,
        unread: 2,
        seq: null,
        timestamp: 1788000000,
      );
      expect(
        () => store.mergeConversationUnreadForTest(
          existing: existing,
          incoming: incoming,
          owner: 'owner_b',
          conversationId: 'c2c_userA',
          readClearedAtMs: 0,
        ),
        returnsNormally,
      );
      expect(incoming.unreadCount, 2);
    });

    test('newer group seq after an older c2c timestamp on the same session is '
        'accepted — was rejected by cross-domain comparison before fix', () {
      final store = ConversationLocalStore.instance;
      // Existing carries a timestamp-scale lastMessage but is a group session.
      // Before fix: committed=1788000000, incoming seq=10 → rejected. After
      // fix: group domain uses seq watermark, sees 10 vs 5 → accept.
      final existing = _build(
        convId: 'group_m2DOMAIN',
        type: 2,
        unread: 1,
        seq: '5',
        timestamp: 1788000000,
      );
      final incoming = _build(
        convId: 'group_m2DOMAIN',
        type: 2,
        unread: 3,
        seq: '10',
        timestamp: 0,
      );
      store.mergeConversationUnreadForTest(
        existing: existing,
        incoming: incoming,
        owner: 'owner_c',
        conversationId: 'group_m2DOMAIN',
        readClearedAtMs: 0,
      );
      expect(incoming.unreadCount, 3,
          reason: 'after P0-1 fix, group seq watermark accepts seq=10');
    });

    test('older group seq after a newer group seq is rejected', () {
      final store = ConversationLocalStore.instance;
      final existing = _build(
        convId: 'group_m2DOMAIN2',
        type: 2,
        unread: 5,
        seq: '100',
        timestamp: 0,
      );
      final incoming = _build(
        convId: 'group_m2DOMAIN2',
        type: 2,
        unread: 7,
        seq: '50',
        timestamp: 0,
      );
      store.mergeConversationUnreadForTest(
        existing: existing,
        incoming: incoming,
        owner: 'owner_d',
        conversationId: 'group_m2DOMAIN2',
        readClearedAtMs: 0,
      );
      // P0-1: rejected → incoming.unreadCount reverts to existing.
      expect(incoming.unreadCount, 5,
          reason: 'group seq=50 older than committed seq=100 → rejected');
    });
  });
}
