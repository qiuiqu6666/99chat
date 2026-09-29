// Diagnostic regression: run explicitly; failures document the current bug.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/conversation_read_policy.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation row(String message, int unread,
    {int timestamp = 100, bool group = false, int seq = 10, bool self = false}) {
  return V2TimConversation(
    conversationID: group ? 'group_rebound' : 'c2c_rebound',
    type: group ? 2 : 1,
    userID: group ? null : 'rebound',
    groupID: group ? 'rebound' : null,
    unreadCount: unread,
    lastMessage: V2TimMessage.fromJson({
      'message_msg_id': message,
      'message_server_time': timestamp,
      'message_risk_type_identified': 0,
      'message_is_from_self': self,
    })
      ..timestamp = timestamp
      ..seq = seq.toString()
      ..userID = group ? null : 'rebound'
      ..groupID = group ? 'rebound' : null
      ..isSelf = self,
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
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = 'unread_rebound_diagnostic';
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

  void receive(V2TimConversation snapshot) {
    controller.applyPendingRealtimeProjection([snapshot], reason: 'sdk_realtime');
    tabs.flushRealtimePatches();
  }

  void readAndLeave({bool group = false}) {
    final id = group ? 'group_rebound' : 'c2c_rebound';
    receive(row('seen', 5, group: group));
    ActiveChatRegistry.instance.enter(id);
    store.recordReadClearedAnchor(id,
        lastMessageId: 'seen', lastMessageTimestamp: 100,
        lastMessageSeq: group ? 10 : 0);
    controller.zeroUnreadLocally(id);
    ActiveChatRegistry.instance.updateRouteVisible(false);
    controller.flushDeferredListUiBeforeChatLeave(conversationId: id);
    ActiveChatRegistry.instance.leave(id);
    expect(tabs.conversationForId(id)?.unreadCount, 0);
    expect(group ? aggregate.groupNotifiableUnreadSum
        : aggregate.c2cNotifiableUnreadSum, 0);
  }

  test('control: exact old snapshot remains zero before a new message', () {
    readAndLeave();
    receive(row('seen', 5));
    expect(tabs.conversationForId('c2c_rebound')?.unreadCount, 0);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
  });

  test('control: SDK already excludes old read messages', () {
    readAndLeave();
    receive(row('new', 1, timestamp: 101));
    expect(tabs.conversationForId('c2c_rebound')?.unreadCount, 1);
    expect(aggregate.c2cNotifiableUnreadSum, 1);
  });

  for (final sameSecond in [false, true]) {
    test('C2C one new arrival excludes five read messages; sameSecond=$sameSecond', () {
      readAndLeave();
      // SDK still counts five messages at T because the real policy clears T-1.
      expect(ConversationReadPolicy.conservativeTimestamp(100), 99);
      receive(row('new', 6, timestamp: sameSecond ? 100 : 101));
      expect({
        'row': tabs.conversationForId('c2c_rebound')?.unreadCount,
        'tab': aggregate.c2cNotifiableUnreadSum,
      }, {'row': 1, 'tab': 1});
    });
  }

  test('late self-message snapshot then peer arrival excludes the old count', () {
    readAndLeave();
    receive(row('my-reply', 5, timestamp: 101, self: true));
    expect(tabs.conversationForId('c2c_rebound')?.unreadCount, 0);
    receive(row('new', 6, timestamp: 102));
    expect({
      'row': tabs.conversationForId('c2c_rebound')?.unreadCount,
      'tab': aggregate.c2cNotifiableUnreadSum,
    }, {'row': 1, 'tab': 1});
  });

  test('group pending read ACK: newer sequence excludes the old count', () {
    readAndLeave(group: true);
    receive(row('new', 6, group: true, seq: 11));
    expect({
      'row': tabs.conversationForId('group_rebound')?.unreadCount,
      'tab': aggregate.groupNotifiableUnreadSum,
    }, {'row': 1, 'tab': 1});
  });

  test('independent SDK calibration excludes residual old unread', () async {
    readAndLeave();
    aggregate.sdkPageForTest = (_) async => V2TimConversationResult(
      conversationList: [row('new', 6, timestamp: 101)], isFinished: true);
    await aggregate.refreshFromStore(reason: 'diagnostic_rebound');
    expect(aggregate.c2cNotifiableUnreadSum, 1);
  });
}
