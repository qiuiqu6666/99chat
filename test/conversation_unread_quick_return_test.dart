import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation _row(String peer, String messageId, int unread,
    {int timestamp = 100, int? seq, bool group = false}) {
  final id = '${group ? 'group' : 'c2c'}_$peer';
  final message = V2TimMessage.fromJson({
    'message_msg_id': messageId,
    'message_server_time': timestamp,
    'message_is_from_self': false,
    'message_risk_type_identified': 0,
  })
    ..userID = group ? null : peer
    ..groupID = group ? peer : null
    ..timestamp = timestamp
    ..seq = seq?.toString()
    ..isSelf = false;
  return V2TimConversation(
    conversationID: id,
    type: group ? 2 : 1,
    userID: group ? null : peer,
    groupID: group ? peer : null,
    unreadCount: unread,
    lastMessage: message,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controller = ChatSessionController.instance;
  final tabs = ConversationTabStore.instance;
  final aggregate = ConversationUnreadAggregate.instance;
  final store = ConversationLocalStore.instance;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    store.debugOwnerUserId = 'quick_return_owner';
    tabs.clear();
    tabs.notifyColdStartEnded();
    aggregate.resetForTest();
  });
  tearDown(() {
    ActiveChatRegistry.instance.reset();
    controller.clearSessionProjection();
    aggregate.resetForTest();
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = null;
  });

  for (final flushBeforePop in [true, false]) {
    test(
        'unseen arrival keeps row and tab unread; flush before pop=$flushBeforePop',
        () async {
      controller.applyPendingRealtimeProjection([
        _row('autumn', 'old', 0),
        _row('winter', 'other', 2),
      ], reason: 'sdk_realtime');
      tabs.flushRealtimePatches();
      ActiveChatRegistry.instance.enter('c2c_autumn');
      ActiveChatRegistry.instance.updateHasVisibleMessages(true);
      // Existing bubbles are visible; the newly received bubble is not.
      controller.applyPendingRealtimeProjection(
          [_row('autumn', 'unseen', 1, timestamp: 101)],
          reason: 'sdk_realtime');
      if (flushBeforePop) tabs.flushRealtimePatches();
      // The preview/persistence callback can complete before route disposal,
      // after the independent SDK unread callback has already run.
      final persisted = _row('autumn', 'unseen', 1, timestamp: 101);
      ConversationUnreadGuard.resolveForPersist(
          conversation: persisted,
          uiUnread: 1,
          suppressStaleForRecentlyLeft: false);
      await controller.applyProjectionBatch(
          reason: 'committed_batch', upserted: [persisted]);
      ActiveChatRegistry.instance.updateRouteVisible(false);
      controller.flushDeferredListUiBeforeChatLeave(
          conversationId: 'c2c_autumn');
      ActiveChatRegistry.instance.leave('c2c_autumn');

      // The tab independently refreshes authoritative SDK unread snapshots.
      aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
            conversationList: [
              _row('autumn', 'unseen', 1, timestamp: 101),
              _row('winter', 'other', 2),
            ],
            isFinished: true,
          );
      await aggregate.refreshFromStore();
      expect(aggregate.c2cNotifiableUnreadSum, 3);
      expect(tabs.conversationForId('c2c_autumn')?.unreadCount, 1);
      expect(tabs.conversationForId('c2c_winter')?.unreadCount, 2);

      controller.applyPendingRealtimeProjection(
          [_row('autumn', 'unseen', 0, timestamp: 101)],
          reason: 'sdk_read_ack');
      tabs.flushRealtimePatches();
      expect(tabs.conversationForId('c2c_autumn')?.unreadCount, 0);
      expect(aggregate.c2cNotifiableUnreadSum, 2);
    });
  }

  test('different C2C message in the read anchor second remains unread', () {
    store.recordReadClearedAnchor('c2c_autumn',
        lastMessageId: 'seen', lastMessageTimestamp: 100);
    final incoming = _row('autumn', 'unseen', 1);
    store.resolveSdkUnreadAgainstReadBarrier(incoming);
    expect(incoming.unreadCount, 1);
    expect(store.readBarrierFor('c2c_autumn'), isNotNull,
        reason:
            'ambiguous ordering must retain protection against exact replay');
    final replay = _row('autumn', 'seen', 4);
    store.resolveSdkUnreadAgainstReadBarrier(replay);
    expect(replay.unreadCount, 0);
  });

  test('read grace does not consume a different unseen message on list apply',
      () {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    store.recordReadClearedAnchor('c2c_autumn',
        lastMessageId: 'seen', lastMessageTimestamp: now);
    final incoming = _row('autumn', 'unseen', 1, timestamp: now);
    expect(
        ConversationUnreadGuard.resolveForListApply(
            conversationId: 'c2c_autumn',
            existingUnread: 0,
            incoming: incoming),
        1);
  });

  test('durable merge keeps an unseen message while chat is still foreground',
      () {
    ActiveChatRegistry.instance.enter('c2c_autumn');
    final incoming = _row('autumn', 'unseen', 1, timestamp: 101);
    store.mergeConversationUnreadForTest(
        existing: _row('autumn', 'seen', 0),
        incoming: incoming,
        owner: 'quick_return_owner',
        conversationId: 'c2c_autumn',
        readClearedAtMs: 0);
    expect(incoming.unreadCount, 1);
  });

  test('a new message older than read action wall clock survives durable merge',
      () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    store.recordReadClearedAnchor('c2c_autumn',
        lastMessageId: 'seen', lastMessageTimestamp: nowMs ~/ 1000 - 2);
    final incoming = _row('autumn', 'unseen', 1, timestamp: nowMs ~/ 1000 - 1);
    store.mergeConversationUnreadForTest(
        existing: _row('autumn', 'seen', 0, timestamp: nowMs ~/ 1000 - 2),
        incoming: incoming,
        owner: 'quick_return_owner',
        conversationId: 'c2c_autumn',
        readClearedAtMs: nowMs);
    expect(incoming.unreadCount, 1);
  });

  test('group sequence distinguishes unread from read messages within a second',
      () {
    store.recordReadClearedAnchor('group_room',
        lastMessageId: 'seen', lastMessageTimestamp: 100, lastMessageSeq: 10);
    final replay =
        _row('room', 'older', 4, timestamp: 101, seq: 9, group: true);
    store.resolveSdkUnreadAgainstReadBarrier(replay);
    expect(replay.unreadCount, 0,
        reason: 'group sequence takes precedence over its timestamp');
    final unseen = _row('room', 'unseen', 1, seq: 11, group: true);
    store.resolveSdkUnreadAgainstReadBarrier(unseen);
    expect(unseen.unreadCount, 1);
    expect(store.readBarrierFor('group_room'), isNull);
  });

  test('C2C sender sequence cannot turn an older read message into new unread',
      () {
    store.recordReadClearedAnchor('c2c_autumn',
        lastMessageId: 'seen', lastMessageTimestamp: 100, lastMessageSeq: 10);
    final replay = _row('autumn', 'older', 4, timestamp: 99, seq: 999);
    store.resolveSdkUnreadAgainstReadBarrier(replay);
    expect(replay.unreadCount, 0);
    expect(store.readBarrierFor('c2c_autumn'), isNotNull);
  });
}
