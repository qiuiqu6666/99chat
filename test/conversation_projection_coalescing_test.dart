import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

V2TimConversation _row(int id,
        {int type = 1,
        int unread = 0,
        int order = 1700000000000,
        bool pinned = false,
        String? draft,
        V2TimMessage? message}) =>
    V2TimConversation(
      conversationID: type == 1 ? 'c2c_coalesce$id' : 'group_@TGS#coalesce$id',
      type: type,
      userID: type == 1 ? 'coalesce$id' : null,
      groupID: type == 2 ? '@TGS#coalesce$id' : null,
      showName: 'row $id',
      unreadCount: unread,
      orderkey: order,
      isPinned: pinned,
      draftText: draft,
      lastMessage: message,
    );
V2TimMessage _message(String text) => V2TimMessage.fromJson({
      'message_msg_id': 'preview',
      'message_server_time': 1700000000,
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..textElem = V2TimTextElem(text: text);

void main() {
  final session = ChatSessionController.instance;
  final store = ConversationTabStore.instance;
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
    session.clearSessionProjection();
    session.isFeedScrolling = null;
  });

  testWidgets('100 real SDK row patches avoid full projection adoption',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [_row(1)]);
    final revision = session.contentRevision;
    final before = session.tabStoreProjectionAdoptionsForTest;
    for (var i = 1; i <= 100; i++) {
      session.applyPendingRealtimeProjection([_row(1, unread: i)],
          reason: 'sdk_realtime');
    }
    expect(session.tabStoreProjectionAdoptionsForTest, before);
    await tester.pump(const Duration(milliseconds: 60));
    expect(session.tabStoreProjectionAdoptionsForTest, before);
    expect(session.contentRevision, revision + 1);
    expect(session.currentConversationById('c2c_coalesce1')!.unreadCount, 100);
  });

  testWidgets(
      'duplicate SDK plus committed snapshots do not publish a revision',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [_row(1, order: 10)]);
    final revision = session.contentRevision;
    final before = session.tabStoreProjectionAdoptionsForTest;
    var notifications = 0;
    void listen() => notifications++;
    store.addListener(listen);
    try {
      for (var i = 0; i < 20; i++) {
        store.applyPatches([_row(1, order: 10)], reason: 'sdk_realtime');
        store.applyCommittedViewBatch(
            ConversationUiSnapshotBatch<V2TimConversation>(
          upsertedSnapshots: [_row(1, order: 10)],
          deletedCanonicalIds: const [],
          structureChanged: false,
          changedFieldMasks: const {},
          commitGeneration: i + 1,
        ));
      }
      await tester.pump(const Duration(milliseconds: 60));
      expect(notifications, 0);
      expect(session.tabStoreProjectionAdoptionsForTest, before);
      expect(session.contentRevision, revision);
    } finally {
      store.removeListener(listen);
    }
  });

  testWidgets('synchronous row and typed-window reads flush pending content',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [_row(1)]);
    store.applyPatches([_row(1, unread: 8)], reason: 'sdk_realtime');
    expect(session.currentConversationById('c2c_coalesce1')!.unreadCount, 8);
    store.applyPatches([_row(1, unread: 9)], reason: 'sdk_realtime');
    expect(session.conversationAtTypeIndex(1, 0)!.unreadCount, 9);
    store.applyPatches([_row(2)],
        reason: 'sdk_realtime', forceAdmitIds: {'c2c_coalesce2'});
    expect(session.hydratedLengthForType(1), 2);
    expect(session.typeIndexOfConversationId(1, 'c2c_coalesce2'), isNotNull);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('scroll freeze survives mixed singleton types then settles',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [_row(1, order: 1700000000200)]);
    store.setItemsForTest(
        convType: 2, items: [_row(2, type: 2, order: 1700000000100)]);
    final before = session.conversations.map((r) => r.conversationID).toList();
    store.setSortFrozenByScroll(true);
    store.applyPatches([_row(2, type: 2, unread: 1, order: 1700000000300)],
        reason: 'sdk_realtime');
    expect(session.conversations.map((r) => r.conversationID), before);
    expect(session.conversations.last.unreadCount, 1);
    store.setSortFrozenByScroll(false);
    expect(session.conversations.first.type, 2);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('pin and draft changes stay immediate and repeated values no-op',
      (tester) async {
    store.setItemsForTest(convType: 1, items: [_row(1), _row(2)]);
    store.applyPatches([_row(2, pinned: true, draft: 'draft')],
        reason: 'pin_local', explicitDraftIds: {'c2c_coalesce2'});
    final updated = session.currentConversationById('c2c_coalesce2')!;
    expect(updated.isPinned, isTrue);
    expect(updated.draftText, 'draft');
    final revision = session.contentRevision;
    store.applyPatches([_row(2, pinned: true, draft: 'draft')],
        reason: 'pin_local', explicitDraftIds: {'c2c_coalesce2'});
    expect(session.contentRevision, revision);
    store.applyPatches([_row(2, pinned: true)],
        reason: 'draft_local', explicitDraftIds: {'c2c_coalesce2'});
    expect(session.currentConversationById('c2c_coalesce2')!.draftText, isNull);
  });

  testWidgets('in-place typed preview text edit is not lost to no-op detection',
      (tester) async {
    final shared = _row(1, message: _message('before'));
    store.setItemsForTest(convType: 1, items: [shared]);
    final revision = session.contentRevision;
    shared.lastMessage!.textElem!.text = 'after';
    store.applyPatches([shared],
        reason: 'sdk_realtime', explicitLastMessageIds: {'c2c_coalesce1'});
    expect(session.contentRevision, revision + 1);
    expect(
        session
            .currentConversationById('c2c_coalesce1')!
            .lastMessage!
            .textElem!
            .text,
        'after');
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('in-place order change remains frozen until settle',
      (tester) async {
    final first = _row(1, order: 1700000000200);
    final second = _row(2, order: 1700000000100);
    store.setItemsForTest(convType: 1, items: [first, second]);
    store.setSortFrozenByScroll(true);
    second.orderkey = 1700000000300;
    store.applyPatches([second], reason: 'sdk_realtime');
    expect(session.conversations.first.conversationID, 'c2c_coalesce1');
    store.setSortFrozenByScroll(false);
    expect(session.conversations.first.conversationID, 'c2c_coalesce2');
    await tester.pump(const Duration(milliseconds: 60));
  });

  test('mixed merge keeps overlapping aliases and orders changed patch keys',
      () {
    final a = _row(1, order: 1700000000300);
    final b = _row(2, order: 1700000000100);
    final patch = _row(2, order: 1700000000500);
    final group = _row(2, type: 2, order: 1700000000200);
    final merged =
        ConversationLocalStore.mergeConversationsForUi([a, b], [patch, group]);
    expect(merged.map((r) => r.conversationID),
        ['c2c_coalesce2', 'c2c_coalesce1', 'group_@TGS#coalesce2']);
  });
  for (final type in [1, 2]) {
    testWidgets(
        'local unread clear accepts later same authoritative count: type=$type',
        (tester) async {
      final original = _row(1, type: type, unread: 3);
      final id = original.conversationID;
      store.setItemsForTest(convType: type, items: [original]);
      store.zeroUnreadLocallyMany([id]);
      expect(store.itemsForType(type).single.unreadCount, 0);
      final clearedRevision = session.contentRevision;
      store.applyPatches([_row(1, type: type, unread: 3)],
          reason: 'sdk_realtime', explicitUnreadIds: {id});
      expect(store.itemsForType(type).single.unreadCount, 3);
      expect(session.contentRevision, clearedRevision + 1);
      final restoredRevision = session.contentRevision;
      store.applyPatches([_row(1, type: type, unread: 3)],
          reason: 'sdk_realtime', explicitUnreadIds: {id});
      expect(session.contentRevision, restoredRevision);
      await tester.pump(const Duration(milliseconds: 60));
    });
  }

  testWidgets('read path retains detection of SDK mutation after local clear',
      (tester) async {
    final shared = _row(1, unread: 3);
    store.setItemsForTest(convType: 1, items: [shared]);
    store.zeroUnreadLocallyMany([shared.conversationID]);
    final clearedRevision = session.contentRevision;
    shared.unreadCount = 3;
    store.applyPatches([shared],
        reason: 'sdk_realtime', explicitUnreadIds: {shared.conversationID});
    expect(session.contentRevision, clearedRevision + 1);
    expect(
        session.currentConversationById(shared.conversationID)!.unreadCount, 3);
    await tester.pump(const Duration(milliseconds: 60));
  });
  testWidgets(
      'fresh authoritative patch repairs a shared object changed since its snapshot',
      (tester) async {
    final shared = _row(1, unread: 3);
    store.setItemsForTest(convType: 1, items: [shared]);
    final originalRevision = session.contentRevision;
    shared.unreadCount = 0;
    store.applyPatches([_row(1, unread: 3)],
        reason: 'sdk_realtime', explicitUnreadIds: {shared.conversationID});
    expect(store.itemsForType(1).single.unreadCount, 3);
    expect(session.contentRevision, originalRevision + 1);
    await tester.pump(const Duration(milliseconds: 60));
  });
}
