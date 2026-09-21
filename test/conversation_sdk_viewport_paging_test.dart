import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_list_sync_notifier.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_paging_policy.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation row(String id) => V2TimConversation(
    conversationID: 'group_@TGS#$id',
    groupID: '@TGS#$id',
    type: 2,
    unreadCount: 0);

V2TimConversation timedRow(String id, int orderkey) => V2TimConversation(
    conversationID: 'group_@TGS#$id',
    groupID: '@TGS#$id',
    type: 2,
    unreadCount: 0,
    orderkey: orderkey);
typedef Page = ({
  List<V2TimConversation> conversationList,
  String nextSeq,
  bool isFinished,
  int code,
  String desc
});
Page page(List<V2TimConversation> rows, String cursor,
        {bool finished = false, int code = 0}) =>
    (
      conversationList: rows,
      nextSeq: cursor,
      isFinished: finished,
      code: code,
      desc: ''
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationTabStore.instance;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    store.clear();
    store.notifyColdStartEnded();
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
  });
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationListSyncNotifier.instance.setSyncing(false);
    ChatSessionController.instance.isFeedScrolling = null;
    ChatSessionController.instance.clearSessionProjection();
    ConversationUnreadAggregate.instance.resetForTest();
    clearArchivedConversationSessionState();
  });

  test('placeholder tail cannot hide the need to fetch real rows', () {
    expect(
        conversationFeedNeedsPage(
            viewportHeight: 600,
            pixels: 1100,
            extentAfter: 4000,
            loadedContentExtent: 2100),
        isTrue);
    expect(
        conversationFeedNeedsPage(
            viewportHeight: 600,
            pixels: 0,
            extentAfter: 4000,
            loadedContentExtent: 2100),
        isFalse);
    expect(
        conversationFeedNeedsPage(
            viewportHeight: 600, pixels: 1100, extentAfter: 900),
        isFalse);
  });

  test(
      'filtered page advances to visible rows while legacy sync and scroll are active',
      () async {
    archivedConversationGroupIDsNotifier.value = {row('hidden').conversationID};
    store.setItemsForTest(convType: 2, items: [row('head')], nextSeq: '10');
    ConversationListSyncNotifier.instance.setSyncing(true);
    ChatSessionController.instance.isFeedScrolling = () => true;
    final cursors = <String>[];
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      cursors.add(nextSeq);
      return nextSeq == '10'
          ? page([row('hidden')], '20')
          : page([row('tail')], '0', finished: true);
    };
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(cursors, ['10', '20']);
    expect(store.itemsForType(2).map((e) => e.groupID), contains('@TGS#tail'));
    expect(store.finishedForType(2), isTrue);
    expect(store.lastApplyPatchesReason, 'sdk_page');
    expect(ChatSessionController.instance.conversations.map((e) => e.groupID),
        contains('@TGS#tail'));
  });

  test('concurrent viewport requests share the same page fetch', () async {
    final response = Completer<Page>();
    var calls = 0;
    store.setItemsForTest(convType: 2, items: [row('head')], nextSeq: '10');
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) {
      calls++;
      return response.future;
    };
    final a = store.loadMoreForViewport(convType: 2);
    final b = store.loadMoreForViewport(convType: 2);
    response.complete(page([row('tail')], '20'));
    await Future.wait([a, b]);
    expect(calls, 1);
    expect(store.countForType(2), 2);
  });

  test('empty/duplicate pages are bounded without falsely marking completion',
      () async {
    var calls = 0;
    store.setItemsForTest(convType: 2, items: [row('head')], nextSeq: '10');
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls++;
      return page(
          calls.isEven ? [row('head')] : [], '${int.parse(nextSeq) + 10}');
    };
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(calls, 3);
    expect(store.finishedForType(2), isFalse);
    expect(store.nextSeqForType(2), '40');
  });

  test('network failure keeps cursor available for retry', () async {
    store.setItemsForTest(convType: 2, items: [row('head')], nextSeq: '10');
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) async =>
        page([], '0', code: -1);
    expect(await store.loadMoreForViewport(convType: 2), isFalse);
    expect(store.nextSeqForType(2), '10');
    expect(store.finishedForType(2), isFalse);
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) async =>
        page([row('tail')], '0', finished: true);
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(store.countForType(2), 2);
  });

  test('clearing the session cancels a late page and subsequent fetches',
      () async {
    final response = Completer<Page>();
    var calls = 0;
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) {
      calls++;
      return response.future;
    };
    final load = store.loadMoreForViewport(convType: 2);
    store.clear();
    response.complete(page([row('old-account')], '20'));
    expect(await load, isFalse);
    expect(store.countForType(2), 0);
    expect(calls, 1);
  });

  test('strictly older pages concatenate without dropping the tail', () async {
    store.setItemsForTest(
      convType: 2,
      items: [timedRow('a', 400)],
      nextSeq: '10',
    );
    var calls = 0;
    var sawAppendOnly = false;
    void onStore() {
      if (store.lastNotificationAppendOnly) sawAppendOnly = true;
    }

    store.addListener(onStore);
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async {
      calls++;
      if (calls == 1) {
        return page([timedRow('b', 300), timedRow('c', 200)], '20');
      }
      return page([timedRow('d', 100), timedRow('e', 50)], '0', finished: true);
    };
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    store.removeListener(onStore);
    expect(
      store.itemsForType(2).map((e) => e.groupID).toList(),
      ['@TGS#a', '@TGS#b', '@TGS#c', '@TGS#d', '@TGS#e'],
    );
    expect(store.conversationForId(timedRow('e', 50).conversationID), isNotNull);
    expect(sawAppendOnly, isTrue);
    expect(store.finishedForType(2), isTrue);
  });

  test('overlapping older page drops duplicates and keeps order', () async {
    store.setItemsForTest(
      convType: 2,
      items: [timedRow('a', 300), timedRow('b', 200)],
      nextSeq: '10',
    );
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async =>
            page([timedRow('b', 200), timedRow('c', 100)], '0', finished: true);
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(
      store.itemsForType(2).map((e) => e.groupID).toList(),
      ['@TGS#a', '@TGS#b', '@TGS#c'],
    );
  });

  test('a newer overlapping row falls back to merge order', () async {
    final current = [timedRow('a', 300), timedRow('c', 100)];
    final incoming = [timedRow('b', 200)];
    store.setItemsForTest(
      convType: 2,
      items: current,
      nextSeq: '10',
    );
    ConversationTabStore.debugFetchOverride =
        ({required convType, required nextSeq, required count}) async =>
            page(incoming, '0', finished: true);
    expect(await store.loadMoreForViewport(convType: 2), isTrue);
    expect(
      store.itemsForType(2).map((e) => e.groupID).toList(),
      ConversationLocalStore.mergeConversationsForUi(current, incoming)
          .map((e) => e.groupID)
          .toList(),
    );
    expect(
      store.itemsForType(2).map((e) => e.groupID).toList(),
      ['@TGS#a', '@TGS#b', '@TGS#c'],
    );
  });
}
