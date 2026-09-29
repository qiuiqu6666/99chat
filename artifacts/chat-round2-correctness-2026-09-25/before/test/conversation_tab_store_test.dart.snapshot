import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/friend_became_friends_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';

V2TimConversation _c2c(String id, {int unread = 0, bool pinned = false}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    isPinned: pinned,
    orderkey: unread + (pinned ? 1000 : 0),
    showName: id,
  );
}

V2TimConversation _group(String id, {int unread = 0}) {
  return V2TimConversation(
    conversationID: 'group_$id',
    type: 2,
    groupID: id,
    unreadCount: unread,
    orderkey: unread,
    showName: id,
  );
}

V2TimMessage _textMessage(
  String text, {
  String msgID = 'msg_preview',
  int timestamp = 1700000000,
  int status = MessageStatus.V2TIM_MSG_STATUS_SENDING,
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': msgID,
    'message_server_time': timestamp,
    'message_is_from_self': true,
    'message_status': status,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.msgID = msgID;
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
  message.textElem = V2TimTextElem(text: text);
  return message;
}

V2TimMessage _friendTipMessage({String msgID = 'tip_preview'}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': msgID,
    'message_server_time': 1700001000,
    'message_is_from_self': true,
    'message_status': 1,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.msgID = msgID;
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
  message.userID = 'peer';
  message.customElem = V2TimCustomElem(
    data:
        '{"businessID":"$kFriendBecameFriendsBusinessID","text":"你们已成为好友，现在可以开始聊天了"}',
  );
  return message;
}

void main() {
  test('settling an unchanged feed does not reorder or notify', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_b'), _c2c('c2c_a')]);
    var notifications = 0;
    void listener() => notifications++;
    tab.addListener(listener);
    try {
      tab.setSortFrozenByScroll(true);
      tab.setSortFrozenByScroll(false);
      expect(notifications, 0);
      expect(
          tab.itemsForType(1).map((c) => c.conversationID), ['c2c_b', 'c2c_a']);
    } finally {
      tab.removeListener(listener);
    }
  });

  test('content-only patch during scrolling does not cause a settle refresh',
      () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_a'), _c2c('c2c_b')]);
    tab.setSortFrozenByScroll(true);
    tab.applyPatches(
        [_c2c('c2c_a')..faceUrl = 'https://example.com/updated.png'],
        notify: false);
    var notifications = 0;
    void listener() => notifications++;
    tab.addListener(listener);
    try {
      tab.setSortFrozenByScroll(false);
      expect(notifications, 0);
      expect(
          tab.itemsForType(1).first.faceUrl, 'https://example.com/updated.png');
    } finally {
      tab.removeListener(listener);
    }
  });

  test('settle reorders only dirty type and publishes once', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_z'), _c2c('c2c_a')]);
    tab.setItemsForTest(convType: 2, items: [_group('a'), _group('b')]);
    tab.setSortFrozenByScroll(true);
    tab.applyPatches([_group('b')..orderkey = 100], notify: false);
    expect(tab.itemsForType(2).first.conversationID, 'group_a');
    var notifications = 0;
    void listener() => notifications++;
    tab.addListener(listener);
    try {
      tab.setSortFrozenByScroll(false);
      expect(tab.itemsForType(2).first.conversationID, 'group_b');
      expect(tab.itemsForType(1).first.conversationID, 'c2c_z');
      expect(notifications, 1);
      tab.setSortFrozenByScroll(true);
      tab.setSortFrozenByScroll(false);
      expect(notifications, 1);
    } finally {
      tab.removeListener(listener);
    }
  });

  test('equal unread changes in separate conversations both reach the badge',
      () {
    final tab = ConversationTabStore.instance;
    final aggregate = ConversationUnreadAggregate.instance;
    tab.notifyColdStartEnded();
    void apply(int oldValue, int newValue, int generation) {
      tab.applyCommittedViewBatch(
        ConversationUiSnapshotBatch<V2TimConversation>(
          upsertedSnapshots: [
            _c2c('c2c_badge_a', unread: newValue),
            _c2c('c2c_badge_b', unread: newValue),
          ],
          deletedCanonicalIds: const [],
          structureChanged: true,
          changedFieldMasks: const {},
          commitGeneration: generation,
          unreadDeltas: [
            for (final id in ['c2c_badge_a', 'c2c_badge_b'])
              ConversationUiUnreadDelta(
                conversationKey: id,
                isGroup: false,
                oldNotifiable: oldValue,
                newNotifiable: newValue,
              ),
          ],
        ),
      );
    }

    apply(0, 1, 1);
    expect(aggregate.c2cNotifiableUnreadSum, 2);
    expect(
        tab
            .itemsForType(1)
            .fold<int>(0, (sum, row) => sum + (row.unreadCount ?? 0)),
        2);
    apply(0, 1, 2);
    expect(aggregate.c2cNotifiableUnreadSum, 2);
    apply(1, 0, 3);
    expect(aggregate.c2cNotifiableUnreadSum, 0);
    apply(0, 1, 4);
    expect(aggregate.c2cNotifiableUnreadSum, 2);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
    ActiveChatRegistry.instance.reset();
    ConversationUnreadAggregate.instance.clearSession();
    ChatSessionController.instance.clearSessionProjection();
  });

  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;
    ConversationTabStore.instance.clear();
    ActiveChatRegistry.instance.reset();
    ConversationUnreadAggregate.instance.clearSession();
    ChatSessionController.instance.clearSessionProjection();
    ConversationPinSyncService.instance.debugReplacePinnedIdsForTest(const {});
  });

  test('reset keeps realtime rows that arrived while the SDK page was loading',
      () async {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(
      convType: 1,
      items: <V2TimConversation>[
        _c2c('c2c_existing', unread: 3)
          ..lastMessage = _textMessage(
            'realtime',
            msgID: 'realtime_new',
            timestamp: 200,
          ),
        _c2c('c2c_hot_only', unread: 1)
          ..lastMessage = _textMessage(
            'hot only',
            msgID: 'hot_only',
            timestamp: 190,
          ),
      ],
    );
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async =>
        (
          conversationList: <V2TimConversation>[
            _c2c('c2c_existing')
              ..lastMessage = _textMessage(
                'stale page',
                msgID: 'stale_page',
                timestamp: 100,
              ),
            _c2c('c2c_page_only'),
          ],
          nextSeq: '0',
          isFinished: true,
          code: 0,
          desc: '',
        );

    await tab.loadFirstPage(convType: 1);

    final rows = <String, V2TimConversation>{
      for (final row in tab.itemsForType(1)) row.conversationID: row,
    };
    expect(
        rows.keys,
        containsAll(<String>[
          'c2c_existing',
          'c2c_hot_only',
          'c2c_page_only',
        ]));
    expect(rows['c2c_existing']?.lastMessage?.msgID, 'realtime_new');
    expect(rows['c2c_existing']?.unreadCount, 3);
  });

  test('controller and SDK store share one immutable cached display', () {
    final tab = ConversationTabStore.instance;
    final controller = ChatSessionController.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_a')]);
    final before = tab.conversations;
    expect(controller.conversations, same(before));
    expect(tab.conversations, same(before));
    expect(() => before.clear(), throwsUnsupportedError);
    tab.applyPatches([_c2c('c2c_a')..faceUrl = 'updated'],
        reason: 'silent_test', notify: false, preserveOrder: true);
    expect(controller.conversations, same(tab.conversations));
    expect(controller.conversations.single.faceUrl, 'updated');
    expect(before.single.faceUrl, isNull);
    tab.applyDeleted(['c2c_a'], notify: false);
    expect(controller.conversations, isEmpty);
  });

  test('combined order changes even if neither typed order changes', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_a')..orderkey = 100]);
    tab.setItemsForTest(convType: 2, items: [_group('b')..orderkey = 90]);
    expect(tab.conversations.first.conversationID, 'c2c_a');
    tab.applyPatches([_group('b')..orderkey = 110], reason: 'test_order');
    expect(tab.lastNotificationStructureChanged, isTrue);
    expect(tab.conversations.first.conversationID, 'group_b');
  });

  test('scroll settle does not end an outstanding pin reorder delay', () {
    final tab = ConversationTabStore.instance;
    tab.setItemsForTest(convType: 1, items: [_c2c('c2c_a'), _c2c('c2c_b')]);
    expect(tab.conversations.first.conversationID, 'c2c_a');
    tab.setPinReorderDeferred(true);
    tab.setSortFrozenByScroll(true);
    tab.applyPatches([_c2c('c2c_b', pinned: true)], reason: 'pin_test');
    tab.setSortFrozenByScroll(false);
    expect(tab.itemsForType(1).first.conversationID, 'c2c_a');
    expect(tab.conversations.first.conversationID, 'c2c_a');
    tab.setPinReorderDeferred(false);
    expect(tab.conversations.first.conversationID, 'c2c_b');
  });

  test('late reset page cannot resurrect an explicitly cleared preview',
      () async {
    final tab = ConversationTabStore.instance;
    final entered = Completer<void>();
    final release = Completer<void>();
    tab.setItemsForTest(convType: 1, items: [
      _c2c('c2c_clear')..lastMessage = _textMessage('old', msgID: 'old')
    ]);
    ConversationTabStore.debugFetchOverride = (
        {required int convType,
        required String nextSeq,
        required int count}) async {
      entered.complete();
      await release.future;
      return (
        conversationList: [
          _c2c('c2c_clear')..lastMessage = _textMessage('old', msgID: 'old')
        ],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    final load = tab.loadFirstPage(convType: 1);
    await entered.future;
    ChatSessionController.instance.clearLastMessageLocally('c2c_clear');
    expect(tab.conversations.single.lastMessage, isNull);
    release.complete();
    await load;
    expect(tab.conversations.single.lastMessage, isNull);
  });

  test('ensurePrimed fetches SDK once', () async {
    var fetches = 0;
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      fetches++;
      return (
        conversationList: <V2TimConversation>[_c2c('c2c_a')],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: '',
      );
    };
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    expect(fetches, 1);
    expect(ConversationTabStore.instance.countForType(1), 1);
  });

  test('business SQLite first screen reads only the visible type', () async {
    final owner = 'local_first_screen_owner';
    final store = ConversationLocalStore.instance;
    store.debugOwnerUserId = owner;
    addTearDown(() async {
      await store.clearForOwner(owner);
      store.debugOwnerUserId = null;
    });
    await store.upsertBatch(
      conversations: <V2TimConversation>[
        _c2c('c2c_local_1'),
        _c2c('c2c_local_2'),
        _c2c('c2c_local_3'),
        _group('group_local_1'),
      ],
      ownerUserId: owner,
    );

    var sdkFetches = 0;
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      sdkFetches++;
      throw StateError('cold start must not call SDK conversation paging');
    };

    final firstScreen = await store.loadLocalFirstScreen(
      ownerUserId: owner,
      convType: 1,
      limit: 2,
    );
    expect(firstScreen, hasLength(2));
    expect(firstScreen.every((conversation) => conversation.type == 1), isTrue);
    expect(sdkFetches, 0);
  });

  test('business SQLite first screen restores the persisted preview shell',
      () async {
    final owner = 'local_first_screen_preview_owner';
    final store = ConversationLocalStore.instance;
    store.debugOwnerUserId = owner;
    addTearDown(() async {
      await store.clearForOwner(owner);
      store.debugOwnerUserId = null;
    });

    final conversation = _c2c('c2c_preview_shell');
    conversation.lastMessage = _textMessage(
      '本地预览无需解析 raw_json',
      msgID: 'preview_shell_message',
    );
    await store.upsertBatch(
      conversations: <V2TimConversation>[conversation],
      ownerUserId: owner,
    );
    store.resetBatchProfileForTest();

    final firstScreen = await store.loadLocalFirstScreen(
      ownerUserId: owner,
      convType: 1,
      limit: 1,
    );
    expect(firstScreen, hasLength(1));
    expect(
      firstScreen.single.lastMessage?.textElem?.text,
      '本地预览无需解析 raw_json',
    );
    expect(
      firstScreen.single.lastMessage?.localCustomData,
      isNotNull,
    );
    expect(store.batchProfileForTest.rawJsonDecodes, 0);

    final byId = await store.conversationsByIds(
      <String>['c2c_preview_shell'],
      ownerUserId: owner,
    );
    expect(byId.single.lastMessage?.textElem?.text, '本地预览无需解析 raw_json');
  });

  test(
      'preview projection preserves outgoing status and client identity after reload',
      () async {
    final owner = 'preview_status_reload_owner';
    final store = ConversationLocalStore.instance;
    store.debugOwnerUserId = owner;
    addTearDown(() async {
      await store.clearForOwner(owner);
      store.debugOwnerUserId = null;
    });

    final cases = <int, String>{
      MessageStatus.V2TIM_MSG_STATUS_SENDING: 'sending',
      MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC: 'success',
      MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL: 'failed',
    };
    await store.upsertBatch(
      conversations: <V2TimConversation>[
        for (final entry in cases.entries)
          _c2c('c2c_status_${entry.value}', unread: entry.key)
            ..lastMessage = (_textMessage(
              entry.value,
              msgID: 'server_${entry.value}',
              timestamp: 1700000000 + entry.key,
              status: entry.key,
            )
              ..id = 'client_${entry.value}'
              ..isSelf = true
              ..isPeerRead = true),
      ],
      ownerUserId: owner,
    );

    final rows = await store.loadLocalFirstScreen(
      ownerUserId: owner,
      convType: 1,
      limit: 10,
    );
    expect(rows, hasLength(3));
    for (final entry in cases.entries) {
      final message = rows
          .singleWhere(
              (row) => row.conversationID == 'c2c_status_${entry.value}')
          .lastMessage;
      expect(message?.textElem?.text, entry.value);
      expect(message?.status, entry.key);
      expect(message?.isSelf, isTrue);
      expect(message?.id, 'client_${entry.value}');
      expect(message?.isPeerRead, isTrue);
    }
  });

  test('local keyset page keeps preview available while scrolling older',
      () async {
    final owner = 'preview_scroll_owner';
    final store = ConversationLocalStore.instance;
    store.debugOwnerUserId = owner;
    addTearDown(() async {
      await store.clearForOwner(owner);
      store.debugOwnerUserId = null;
    });

    await store.upsertBatch(
      conversations: <V2TimConversation>[
        for (var i = 0; i < 80; i++)
          (_c2c('c2c_scroll_$i')..orderkey = 1000 - i)
            ..lastMessage = _textMessage(
              '预览 $i',
              msgID: 'scroll_msg_$i',
              timestamp: 1700000000 + i,
            ),
      ],
      ownerUserId: owner,
    );
    final firstPage = await store.loadLocalFirstScreen(
      ownerUserId: owner,
      convType: 1,
      limit: 30,
    );
    final cursorConversation =
        ConversationLocalStore.oldestPagingCursor(firstPage);
    expect(cursorConversation, isNotNull);
    final cursor = ConversationTypePageCursor(
      pinned: cursorConversation!.isPinned == true,
      activeTime: ConversationLocalStore.pagingAnchorMs(cursorConversation),
      orderKey: cursorConversation.orderkey ?? 0,
      conversationID: cursorConversation.conversationID,
    );
    final older = await store.loadConvTypePageAfterCursor(
      convType: 1,
      cursor: cursor,
      ownerUserId: owner,
      limit: 30,
    );
    expect(older, isNotEmpty);
    expect(
        older.every(
            (row) => row.lastMessage?.textElem?.text?.isNotEmpty == true),
        isTrue);
  });

  test('flag on: loadFirstPage + loadMore via filter override', () async {
    final pages = <String, List<V2TimConversation>>{
      '0': [_c2c('c2c_1'), _c2c('c2c_2')],
      '2': [_c2c('c2c_3')],
    };
    ConversationTabStore.debugFetchOverride = ({
      required int convType,
      required String nextSeq,
      required int count,
    }) async {
      expect(convType, 1);
      final page = pages[nextSeq] ?? const <V2TimConversation>[];
      final finished = nextSeq != '0';
      return (
        conversationList: page,
        nextSeq: finished ? '0' : '2',
        isFinished: finished,
        code: 0,
        desc: '',
      );
    };

    await ConversationTabStore.instance.loadFirstPage(convType: 1, count: 2);
    expect(ConversationTabStore.instance.countForType(1), 2);
    expect(ConversationTabStore.instance.finishedForType(1), isFalse);

    await ConversationTabStore.instance.loadMore(convType: 1, count: 2);
    expect(ConversationTabStore.instance.countForType(1), 3);
    expect(ConversationTabStore.instance.finishedForType(1), isTrue);
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((c) => c.conversationID),
      ['c2c_1', 'c2c_2', 'c2c_3'],
    );
  });

  test('first SDK page works before the business owner is bound', () async {
    ConversationLocalStore.instance.debugOwnerUserId = '';
    addTearDown(() => ConversationLocalStore.instance.debugOwnerUserId = null);
    ConversationTabStore.debugFetchOverride = (
            {required int convType,
            required String nextSeq,
            required int count}) async =>
        (
          conversationList: [_c2c('c2c_sdk')],
          nextSeq: '19',
          isFinished: false,
          code: 0,
          desc: ''
        );
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    expect(ConversationTabStore.instance.atTypeIndex(1, 0)?.conversationID,
        'c2c_sdk');
    expect(ConversationTabStore.instance.nextSeqForType(1), '19');
  });

  test('terminal SDK page stays primed until an explicit refresh', () async {
    var calls = 0;
    ConversationTabStore.debugFetchOverride = (
        {required int convType,
        required String nextSeq,
        required int count}) async {
      calls++;
      return (
        conversationList:
            calls == 1 ? <V2TimConversation>[] : [_c2c('c2c_new')],
        nextSeq: '0',
        isFinished: true,
        code: 0,
        desc: ''
      );
    };
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    expect(calls, 1);
    await ConversationTabStore.instance.loadFirstPage(convType: 1);
    expect(ConversationTabStore.instance.atTypeIndex(1, 0)?.conversationID,
        'c2c_new');
  });

  test('failed SDK page does not mark the type primed', () async {
    var calls = 0;
    ConversationTabStore.debugFetchOverride = (
        {required int convType,
        required String nextSeq,
        required int count}) async {
      calls++;
      return (
        conversationList: <V2TimConversation>[],
        nextSeq: '0',
        isFinished: true,
        code: calls == 1 ? 1 : 0,
        desc: ''
      );
    };
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    await ConversationTabStore.instance.ensurePrimed(convType: 1);
    expect(calls, 2);
    expect(ConversationTabStore.instance.finishedForType(1), isTrue);
  });

  test('view invalidation clears affected type cursor', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_invalidate')],
      finished: false,
    );
    expect(ConversationTabStore.instance.pageCursorForType(1), isNotNull);
    ConversationTabStore.instance.invalidateViewPages(
      conversationID: 'c2c_invalidate',
      convType: 1,
    );
    expect(ConversationTabStore.instance.pageCursorForType(1), isNull);
  });

  test('applyPatches preserves preview and unread on pin metadata patch', () {
    final lastMessage = _textMessage('你好');
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [
        V2TimConversation(
          conversationID: 'c2c_peer',
          type: 1,
          userID: 'peer',
          unreadCount: 2,
          isPinned: false,
          orderkey: 1700000000,
          showName: '阿阳',
          lastMessage: lastMessage,
        ),
      ],
      finished: true,
    );
    ConversationPinSyncService.instance
        .debugReplacePinnedIdsForTest(const {'c2c_peer'});
    ConversationTabStore.instance.applyPatches([
      V2TimConversation(
        conversationID: 'c2c_peer',
        type: 1,
        userID: 'peer',
        unreadCount: 0,
        isPinned: true,
        orderkey: 1700000100,
        showName: '阿阳',
      ),
    ], reason: 'pin_sdk_changed');
    final row = ConversationTabStore.instance
        .itemsForType(1)
        .firstWhere((c) => c.conversationID == 'c2c_peer');
    expect(row.isPinned, isTrue);
    expect(row.lastMessage?.msgID, 'msg_preview');
    expect(row.unreadCount, 2);
  });

  test('applyPatches marks last-message content changes as non-structural', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [
        _c2c('c2c_preview')..lastMessage = _textMessage('旧预览'),
      ],
      finished: true,
    );

    ConversationTabStore.instance.applyPatches([
      _c2c('c2c_preview')..lastMessage = _textMessage('新预览'),
    ], reason: 'last_message_content');

    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .single
          .lastMessage
          ?.textElem
          ?.text,
      '新预览',
    );
    expect(
      ConversationTabStore.instance.lastNotificationStructureChanged,
      isFalse,
    );
  });

  test('applyPatches marks admitted and deleted rows as structural', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_existing')],
      finished: true,
    );

    ConversationTabStore.instance.applyPatches(
      [_c2c('c2c_admitted')],
      reason: 'admit_row',
      forceAdmitIds: const {'c2c_admitted'},
    );
    expect(
      ConversationTabStore.instance.lastNotificationStructureChanged,
      isTrue,
    );

    ConversationTabStore.instance.applyDeleted(['c2c_admitted']);
    expect(
      ConversationTabStore.instance.lastNotificationStructureChanged,
      isTrue,
    );
  });

  test('zeroUnreadLocallyMany clears rows in sdk primary store', () {
    ConversationUnreadAggregate.instance.setSumsForTest(c2c: 6, group: 3);
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [
        _c2c('c2c_peer', unread: 4),
        _c2c('c2c_other', unread: 2),
      ],
      finished: true,
    );

    ChatSessionController.instance.zeroUnreadLocallyMany(['c2c_peer']);

    final rows = ConversationTabStore.instance.itemsForType(1);
    expect(
        rows.firstWhere((c) => c.conversationID == 'c2c_peer').unreadCount, 0);
    expect(
        rows.firstWhere((c) => c.conversationID == 'c2c_other').unreadCount, 2);
    expect(
      ConversationTabStore.instance.lastNotificationStructureChanged,
      isFalse,
    );
    expect(
      ConversationTabStore.instance.rowViewOf('c2c_peer')?.unreadCount,
      0,
    );
    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 2);
    expect(ConversationUnreadAggregate.instance.groupNotifiableUnreadSum, 3);
  });

  test('zeroUnreadLocallyMany clears group delta without touching c2c', () {
    ConversationUnreadAggregate.instance.setSumsForTest(c2c: 5, group: 7);
    ConversationTabStore.instance.setItemsForTest(
      convType: 2,
      items: [_c2c('group_room', unread: 4)],
      finished: true,
    );

    ChatSessionController.instance.zeroUnreadLocallyMany(['group_room']);

    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 5);
    expect(ConversationUnreadAggregate.instance.groupNotifiableUnreadSum, 3);
  });

  test('applyPatches keeps chat preview over newer friend became friends tip',
      () {
    final chatPreview = _textMessage('最近聊的内容');
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [
        V2TimConversation(
          conversationID: 'c2c_peer',
          type: 1,
          userID: 'peer',
          unreadCount: 0,
          isPinned: false,
          orderkey: 1700000000,
          showName: '秋',
          lastMessage: chatPreview,
        ),
      ],
      finished: true,
    );
    ConversationTabStore.instance.applyPatches([
      V2TimConversation(
        conversationID: 'c2c_peer',
        type: 1,
        userID: 'peer',
        unreadCount: 0,
        isPinned: false,
        orderkey: 1700001000,
        showName: '秋',
        lastMessage: _friendTipMessage(),
      ),
    ], reason: 'friend_became_friends_sent');
    final row = ConversationTabStore.instance
        .itemsForType(1)
        .firstWhere((c) => c.conversationID == 'c2c_peer');
    expect(row.lastMessage?.msgID, 'msg_preview');
    expect(row.lastMessage?.textElem?.text, '最近聊的内容');
  });

  test('applyPatches updates in-window row and admits hot unread', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_old', unread: 0)],
      finished: true,
    );
    ConversationTabStore.instance.applyPatches([
      _c2c('c2c_old', unread: 3),
      _c2c('c2c_hot', unread: 1),
    ], reason: 'test');
    expect(ConversationTabStore.instance.countForType(1), 2);
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((c) => c.conversationID)
          .toSet(),
      {'c2c_old', 'c2c_hot'},
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .firstWhere((c) => c.conversationID == 'c2c_old')
          .unreadCount,
      3,
    );
  });

  test('applyPatches keeps batched inserts in UI order', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: const [],
      finished: true,
    );
    ConversationTabStore.instance.applyPatches(
      [
        _c2c('c2c_low', unread: 1),
        _c2c('c2c_high', unread: 5),
      ],
      reason: 'test',
      forceAdmitIds: {'c2c_low', 'c2c_high'},
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((c) => c.conversationID),
      ['c2c_high', 'c2c_low'],
    );
  });

  test('cold-start realtime batch is bounded to the first-screen window', () {
    final batch = List<V2TimConversation>.generate(
      ConversationTabStore.coldStartFirstPageSize * 3,
      (index) => _c2c('c2c_cold_$index'),
    );

    ConversationTabStore.instance.applyPatches(batch, reason: 'sdk_realtime');

    expect(
      ConversationTabStore.instance.countForType(1),
      ConversationTabStore.coldStartFirstPageSize,
    );
  });

  test('clear reopens the cold-start projection window for a new session', () {
    ConversationTabStore.instance.notifyColdStartEnded();
    ConversationTabStore.instance.clear();

    final batch = List<V2TimConversation>.generate(
      ConversationTabStore.coldStartFirstPageSize + 5,
      (index) => _c2c('c2c_new_session_$index'),
    );
    ConversationTabStore.instance.applyPatches(batch, reason: 'sdk_realtime');

    expect(
      ConversationTabStore.instance.countForType(1),
      ConversationTabStore.coldStartFirstPageSize,
    );
  });

  test(
      'active chat defers non-visible committed projection without replaying unread',
      () {
    ActiveChatRegistry.instance.enter('c2c_active');
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[
          _c2c('c2c_active', unread: 5),
          _c2c('c2c_background', unread: 4),
        ],
        deletedCanonicalIds: const <String>[],
        structureChanged: true,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{},
        commitGeneration: 41,
        unreadDeltas: const <ConversationUiUnreadDelta>[
          ConversationUiUnreadDelta(
            isGroup: false,
            oldNotifiable: 0,
            newNotifiable: 5,
          ),
        ],
      ),
    );

    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((row) => row.conversationID),
      contains('c2c_active'),
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((row) => row.conversationID),
      isNot(contains('c2c_background')),
    );
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 1);
    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 5);

    ActiveChatRegistry.instance.leave('c2c_active');
    ConversationTabStore.instance.flushDeferredCommittedProjection();

    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((row) => row.conversationID),
      containsAll(<String>['c2c_active', 'c2c_background']),
    );
    expect(ConversationUnreadAggregate.instance.c2cNotifiableUnreadSum, 5);
  });

  test('explicit draft commit replaces and clears an existing draft', () {
    final seeded = _c2c('c2c_draft')..draftText = 'old draft';
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[seeded],
      reason: 'seed_draft',
      forceAdmitIds: const <String>{'c2c_draft'},
    );

    final updated = _c2c('c2c_draft')..draftText = 'new draft';
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[updated],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_draft': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 50,
      ),
    );
    expect(
      ConversationTabStore.instance.itemsForType(1).single.draftText,
      'new draft',
    );

    final cleared = _c2c('c2c_draft');
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[cleared],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_draft': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 51,
      ),
    );
    expect(
      ConversationTabStore.instance.itemsForType(1).single.draftText,
      isNull,
    );
  });

  test('ordinary sdk patch does not erase a local draft', () {
    final seeded = _c2c('c2c_sdk_patch')..draftText = 'keep me';
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[seeded],
      reason: 'seed_draft',
      forceAdmitIds: const <String>{'c2c_sdk_patch'},
    );

    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_sdk_patch', unread: 3)],
      reason: 'sdk_patch',
    );

    expect(
      ConversationTabStore.instance.itemsForType(1).single.draftText,
      'keep me',
    );
  });

  test(
      'deferred last-message snapshot keeps a previously committed draft',
      () {
    ActiveChatRegistry.instance.enter('c2c_active');
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_active')],
      reason: 'seed_active',
      forceAdmitIds: const <String>{'c2c_active'},
    );

    final drafted = _c2c('c2c_peer')..draftText = 'leave draft';
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[drafted],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 60,
      ),
      forceAdmitIds: const <String>{'c2c_peer'},
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((row) => row.conversationID),
      isNot(contains('c2c_peer')),
    );

    final sdkRow = _c2c('c2c_peer')
      ..lastMessage = _textMessage('sdk last', msgID: 'msg_sdk');
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[sdkRow],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.lastMessage,
          },
        },
        commitGeneration: 61,
      ),
      forceAdmitIds: const <String>{'c2c_peer'},
    );

    ActiveChatRegistry.instance.leave('c2c_active');
    ConversationTabStore.instance.flushDeferredCommittedProjection();

    final row = ConversationTabStore.instance.itemsForType(1).firstWhere(
          (item) => item.conversationID == 'c2c_peer',
        );
    expect(row.draftText, 'leave draft');
    expect(row.lastMessage?.msgID, 'msg_sdk');
  });

  test('deferred explicit draft clear still replaces a preserved draft', () {
    ActiveChatRegistry.instance.enter('c2c_active');
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_active')],
      reason: 'seed_active',
      forceAdmitIds: const <String>{'c2c_active'},
    );

    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[
          _c2c('c2c_peer')..draftText = 'leave draft',
        ],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 62,
      ),
      forceAdmitIds: const <String>{'c2c_peer'},
    );
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[_c2c('c2c_peer')],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 63,
      ),
      forceAdmitIds: const <String>{'c2c_peer'},
    );

    ActiveChatRegistry.instance.leave('c2c_active');
    ConversationTabStore.instance.flushDeferredCommittedProjection();

    final row = ConversationTabStore.instance.itemsForType(1).firstWhere(
          (item) => item.conversationID == 'c2c_peer',
        );
    expect(row.draftText, isNull);
  });

  test('explicit last-message commit rolls preview back and clears it', () {
    final newest = _textMessage(
      'deleted message',
      msgID: 'msg_deleted',
      timestamp: 1700000200,
    );
    final seeded = _c2c('c2c_peer')..lastMessage = newest;
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[seeded],
      reason: 'seed_preview',
      forceAdmitIds: const <String>{'c2c_peer'},
    );

    final previous = _textMessage(
      'previous message',
      msgID: 'msg_previous',
      timestamp: 1700000100,
    );
    final rolledBack = _c2c('c2c_peer')..lastMessage = previous;
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[rolledBack],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.lastMessage,
          },
        },
        commitGeneration: 53,
      ),
    );
    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage?.msgID,
      'msg_previous',
    );

    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[_c2c('c2c_peer')],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.lastMessage,
          },
        },
        commitGeneration: 54,
      ),
    );
    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage,
      isNull,
    );
  });

  test('ordinary sdk patch cannot roll conversation preview backwards', () {
    final newest = _textMessage(
      'newest message',
      msgID: 'msg_newest',
      timestamp: 1700000200,
    );
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_peer')..lastMessage = newest],
      reason: 'seed_preview',
      forceAdmitIds: const <String>{'c2c_peer'},
    );

    final older = _textMessage(
      'older sdk snapshot',
      msgID: 'msg_older',
      timestamp: 1700000100,
    );
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_peer')..lastMessage = older],
      reason: 'sdk_patch',
    );

    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage?.msgID,
      'msg_newest',
    );
  });

  test('optimistic delete preview matches a message local id', () {
    final deleted = _textMessage(
      'deleted local message',
      msgID: 'msg_sdk_id',
      timestamp: 1700000200,
    )..id = 'msg_local_id';
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[_c2c('c2c_peer')..lastMessage = deleted],
      reason: 'seed_preview',
      forceAdmitIds: const <String>{'c2c_peer'},
    );
    final previous = _textMessage(
      'previous message',
      msgID: 'msg_previous_local_id',
      timestamp: 1700000100,
    );

    final applied =
        ChatSessionController.instance.replaceLastMessageAfterDeleteLocally(
      conversationID: 'c2c_peer',
      deletedMessageIds: const <String>{'msg_local_id'},
      replacement: previous,
    );

    expect(applied, isTrue);
    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage?.msgID,
      'msg_previous_local_id',
    );
  });

  test('clear drops deferred projection from the previous chat session', () {
    ActiveChatRegistry.instance.enter('c2c_active');
    ConversationTabStore.instance.applyCommittedViewBatch(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[_c2c('c2c_background')],
        deletedCanonicalIds: const <String>[],
        structureChanged: true,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{},
        commitGeneration: 42,
      ),
    );
    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 1);

    ConversationTabStore.instance.clear();
    ActiveChatRegistry.instance.leave('c2c_active');
    ConversationTabStore.instance.flushDeferredCommittedProjection();

    expect(ConversationTabStore.instance.deferredCommittedProjectionCount, 0);
    expect(ConversationTabStore.instance.countForType(1), 0);
  });

  test('notifier sdk-primary: applyConversationsFromStore goes to TabStore',
      () async {
    final notifier = ChatSessionController.instance;
    notifier.ensureTabStoreBridgeAttached();
    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [_c2c('c2c_bridge', unread: 2)],
    );
    expect(ConversationTabStore.instance.countForType(1), 1);
    expect(
      notifier.conversations.any((c) => c.conversationID == 'c2c_bridge'),
      isTrue,
    );
    expect(
        notifier.conversationAtTypeIndex(1, 0)?.conversationID, 'c2c_bridge');
  });

  test('notifier preserves explicit draft clear semantics for TabStore',
      () async {
    final seeded = _c2c('c2c_draft_bridge')..draftText = 'sent text';
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[seeded],
      reason: 'seed_draft',
      forceAdmitIds: const <String>{'c2c_draft_bridge'},
    );

    await ChatSessionController.instance.applyCommittedBatchForTest(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[_c2c('c2c_draft_bridge')],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_draft_bridge': <ConversationMutationField>{
            ConversationMutationField.draft,
          },
        },
        commitGeneration: 52,
      ),
    );

    expect(
      ConversationTabStore.instance.itemsForType(1).single.draftText,
      isNull,
    );
  });

  test('notifier preserves explicit last-message rollback for TabStore',
      () async {
    final newest = _textMessage(
      'deleted message',
      msgID: 'msg_deleted_bridge',
      timestamp: 1700000200,
    );
    ConversationTabStore.instance.applyPatches(
      <V2TimConversation>[
        _c2c('c2c_peer')..lastMessage = newest,
      ],
      reason: 'seed_preview',
      forceAdmitIds: const <String>{'c2c_peer'},
    );

    final previous = _textMessage(
      'previous message',
      msgID: 'msg_previous_bridge',
      timestamp: 1700000100,
    );
    await ChatSessionController.instance.applyCommittedBatchForTest(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[
          _c2c('c2c_peer')..lastMessage = previous,
        ],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.lastMessage,
          },
        },
        commitGeneration: 55,
      ),
    );

    expect(
      ConversationTabStore.instance.itemsForType(1).single.lastMessage?.msgID,
      'msg_previous_bridge',
    );
  });

  test('business patches flow through TabStore', () async {
    final notifier = ChatSessionController.instance;
    await ChatSessionController.instance.applyConversationsFromStoreForTest(
      upserted: [_c2c('c2c_legacy', unread: 1)],
    );
    expect(ConversationTabStore.instance.countForType(1), 1);
    expect(
      notifier.conversations.any((c) => c.conversationID == 'c2c_legacy'),
      isTrue,
    );
  });

  test('SDK adapter applies explicit last-message rollback', () async {
    final notifier = ChatSessionController.instance;
    final newest = _textMessage(
      'deleted message',
      msgID: 'msg_legacy_deleted',
      timestamp: 1700000200,
    );
    notifier.setConversationsForTest(<V2TimConversation>[
      _c2c('c2c_peer')..lastMessage = newest,
    ]);

    final previous = _textMessage(
      'previous message',
      msgID: 'msg_legacy_previous',
      timestamp: 1700000100,
    );
    await ChatSessionController.instance.applyCommittedBatchForTest(
      ConversationUiSnapshotBatch<V2TimConversation>(
        upsertedSnapshots: <V2TimConversation>[
          _c2c('c2c_peer')..lastMessage = previous,
        ],
        deletedCanonicalIds: const <String>[],
        structureChanged: false,
        changedFieldMasks: const <String, Set<ConversationMutationField>>{
          'c2c_peer': <ConversationMutationField>{
            ConversationMutationField.lastMessage,
          },
        },
        commitGeneration: 56,
      ),
    );

    expect(
      notifier.conversations.single.lastMessage?.msgID,
      'msg_legacy_previous',
    );
  });

  test('mergePatchRow keeps existing draft when lastMessage updates', () {
    final existing = _c2c('c2c_peer')
      ..draftText = 'hello draft'
      ..draftTimestamp = 99
      ..lastMessage = _textMessage('old');
    final incoming = _c2c('c2c_peer')
      ..lastMessage = V2TimMessage.fromJson(<String, dynamic>{
        'message_msg_id': 'local_call_bubble_x',
        'message_server_time': 1800000000,
        'message_is_from_self': true,
        'message_status': 2,
        'message_custom_str': '{"businessID":"lk_call","action":"cancel"}',
        'message_risk_type_identified': 0,
        'message_sender_group_member_info': <String, dynamic>{},
        'message_group_at_user_array': <String>[],
      });
    incoming.lastMessage!
      ..msgID = 'local_call_bubble_x'
      ..elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM
      ..customElem = V2TimCustomElem(
        data: '{"businessID":"lk_call","action":"cancel"}',
      )
      ..timestamp = 1800000000
      ..userID = 'peer';
    incoming.draftText = null;
    incoming.draftTimestamp = null;

    final merged = ConversationTabStore.mergePatchRow(
      existing: existing,
      incoming: incoming,
      useIncomingDraft: false,
      useIncomingLastMessage: true,
    );
    expect(merged.draftText, 'hello draft');
    expect(merged.draftTimestamp, 99);
    expect(merged.lastMessage?.msgID, 'local_call_bubble_x');
  });
}
