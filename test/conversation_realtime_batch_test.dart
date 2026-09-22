import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation row(int id, {int unread = 0, int order = 0, String? text}) =>
    V2TimConversation(
      conversationID: 'c2c_batch$id',
      type: 1,
      userID: 'batch$id',
      showName: 'batch $id',
      unreadCount: unread,
      orderkey: 1700000000000 + order,
      lastMessage: text == null
          ? null
          : (V2TimMessage.fromJson({
              'message_msg_id': 'message$id',
              'message_server_time': 1700000000,
              'message_risk_type_identified': 0,
            })
            ..elemType = 1
            ..textElem = V2TimTextElem(text: text)),
    );

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
  void receive(V2TimConversation value) =>
      session.applyPendingRealtimeProjection(
        [value],
        reason: 'sdk_realtime_authoritative',
      );

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    ActiveChatRegistry.instance.reset();
    session.clearSessionProjection();
    session.isFeedScrolling = () => false;
    session.ensureTabStoreBridgeAttached();
    store.notifyColdStartEnded();
  });
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.debugFetchByIdsOverride = null;
    session.clearSessionProjection();
    session.isFeedScrolling = null;
    ActiveChatRegistry.instance.reset();
  });

  testWidgets('100 SDK updates project and sort one final conversation',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1), row(2)]);
    store.resetWorkCounters();
    for (var i = 1; i <= 100; i++) {
      receive(row(2, unread: i, order: i));
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(store.workRowProjectedCount, 1);
    expect(store.workFullSortCount, 1);
    expect(store.workStructureNotifyCount, 1);
    expect(store.itemsForType(1).first.conversationID, 'c2c_batch2');
    expect(store.itemsForType(1).first.unreadCount, 100);
  });

  testWidgets('synchronous reads see pending SDK content immediately',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    receive(row(1, unread: 7, text: 'new text'));
    expect(session.currentConversationById('c2c_batch1')!.unreadCount, 7);
    expect(store.rowViewOf('c2c_batch1')!.lastMessagePreview, 'new text');
    receive(row(2, unread: 2, order: 10));
    expect(session.hydratedLengthForType(1), 2);
    expect(store.atTypeIndex(1, 0)!.conversationID, 'c2c_batch2');
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('local read and delete win over earlier buffered callbacks',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1), row(2)]);
    receive(row(1, unread: 9));
    store.zeroUnreadLocallyMany(['c2c_batch1']);
    receive(row(2, unread: 4));
    session.applyPendingRealtimeDeletion(['c2c_batch2']);
    await tester.pump(const Duration(milliseconds: 60));
    expect(store.conversationForId('c2c_batch1')!.unreadCount, 0);
    expect(store.conversationForId('c2c_batch2'), isNull);
    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 0);
    receive(row(1, unread: 2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(store.conversationForId('c2c_batch1')!.unreadCount, 2);
  });

  testWidgets('metadata callbacks retain the latest buffered message',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    receive(row(1, unread: 1, text: 'new message'));
    receive(row(1, unread: 2)..recvOpt = 2);
    await tester.pump(const Duration(milliseconds: 60));
    final current = store.conversationForId('c2c_batch1')!;
    expect(current.lastMessage!.textElem!.text, 'new message');
    expect(current.unreadCount, 2);
    expect(current.recvOpt, 2);
  });

  testWidgets('SDK wrapper reuse cannot erase a preceding buffered message',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    final reused = row(1, unread: 1, text: 'keep this message');
    receive(reused);
    reused.lastMessage = null;
    reused.unreadCount = 2;
    receive(reused);
    await tester.pump(const Duration(milliseconds: 60));
    final current = store.conversationForId('c2c_batch1')!;
    expect(current.lastMessage!.textElem!.text, 'keep this message');
    expect(current.unreadCount, 2);
  });

  testWidgets('scroll end publishes the final order once', (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1, order: 20), row(2)]);
    store.setSortFrozenByScroll(true);
    session.isFeedScrolling = () => true;
    for (var i = 1; i <= 10; i++) {
      receive(row(2, unread: i, order: 100 + i));
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(store.itemsForType(1).first.conversationID, 'c2c_batch1');
    store.setSortFrozenByScroll(false);
    session.isFeedScrolling = () => false;
    session.flushDeferredUiNotifyIfNeeded();
    expect(store.itemsForType(1).first.conversationID, 'c2c_batch2');
    final settled = session.feedRevision.value;
    session.flushDeferredUiNotifyIfNeeded();
    expect(session.feedRevision.value, settled);
  });

  testWidgets('local pin preserves pending content and remains immediate',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1, order: 20), row(2)]);
    receive(row(2, unread: 4, text: 'latest'));
    store.applyPatches([row(2)..isPinned = true], reason: 'pin_local');
    final pinned = store.itemsForType(1).first;
    expect(pinned.conversationID, 'c2c_batch2');
    expect(pinned.isPinned, isTrue);
    expect(pinned.unreadCount, 4);
    expect(pinned.lastMessage!.textElem!.text, 'latest');
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('ByIDs restore incorporates a callback before its timer fires',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    final reply =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    ConversationTabStore.debugFetchByIdsOverride = (_) => reply.future;
    final restore = store.restoreSdkConversationsByIds(['c2c_batch1']);
    receive(row(1, unread: 8, text: 'new message'));
    reply.complete(
        (conversationList: [row(1, unread: 1, text: 'old message')], code: 0));
    await restore;
    final current = store.conversationForId('c2c_batch1')!;
    expect(current.unreadCount, 8);
    expect(current.lastMessage!.textElem!.text, 'new message');
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('account reset discards pending SDK work', (tester) async {
    receive(row(1, unread: 5));
    session.clearSessionProjection();
    await tester.pump(const Duration(milliseconds: 80));
    expect(store.conversations, isEmpty);
    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 0);
  });

  testWidgets(
      'account reset does not publish buffered rows while unsubscribing',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    final revision = session.rowRevisionOf('c2c_batch1');
    var updates = 0;
    revision.addListener(() => updates++);
    receive(row(1, unread: 5));
    session.clearSessionProjection();
    expect(updates, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(store.conversations, isEmpty);
  });

  testWidgets('late SDK page cannot overwrite a buffered callback',
      (tester) async {
    final page = Completer<
        ({
          List<V2TimConversation> conversationList,
          String nextSeq,
          bool isFinished,
          int code,
          String desc
        })>();
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) => page.future;
    final load = store.loadFirstPage(convType: 1);
    receive(row(1, unread: 8, text: 'new message'));
    page.complete((
      conversationList: [row(1, unread: 1, text: 'old message')],
      nextSeq: '0',
      isFinished: true,
      code: 0,
      desc: ''
    ));
    await load;
    await tester.pump(const Duration(milliseconds: 60));
    final current = store.conversationForId('c2c_batch1')!;
    expect(current.unreadCount, 8);
    expect(current.lastMessage!.textElem!.text, 'new message');
  });

  testWidgets('continuous callbacks publish without waiting for quiet',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    var updates = 0;
    final listenable = store.rowViewListenable('c2c_batch1');
    void listen() => updates++;
    listenable.addListener(listen);
    for (var i = 1; i <= 15; i++) {
      receive(row(1, unread: i));
      await tester.pump(const Duration(milliseconds: 10));
      if (i == 6) expect(updates, greaterThan(0));
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(listenable.value!.unreadCount, 15);
    expect(updates, lessThan(15));
    listenable.removeListener(listen);
  });

  testWidgets('pop-start flush includes callbacks still inside batch interval',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [row(1)]);
    ActiveChatRegistry.instance
        .enter('c2c_batch1', conversationType: ConvType.c2c);
    final before = session.feedRevision.value;
    receive(row(2, unread: 1));
    session.flushDeferredListUiBeforeChatLeave(conversationId: 'c2c_batch1');
    expect(session.feedRevision.value, greaterThan(before));
    expect(store.conversationForId('c2c_batch2'), isNotNull);
    await tester.pump(const Duration(milliseconds: 60));
  });
}
