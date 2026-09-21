import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation _row(String id,
        {int type = 1, int unread = 0, int order = 1700000000000}) =>
    V2TimConversation(
      conversationID: id,
      type: type,
      userID: type == 1 ? id.replaceFirst('c2c_', '') : null,
      groupID: type == 2 ? id.replaceFirst('group_', '') : null,
      showName: 'row $id',
      isPinned: false,
      unreadCount: unread,
      orderkey: order,
    );

class _CountedRow extends V2TimConversation {
  _CountedRow(String id, int type)
      : super(
          conversationID: id,
          type: type,
          userID: type == 1 ? id.replaceFirst('c2c_', '') : null,
          groupID: type == 2 ? id.replaceFirst('group_', '') : null,
          showName: 'row $id',
          isPinned: false,
          unreadCount: 0,
          orderkey: 1700000000000,
        );

  static int idReads = 0;
  @override
  String get conversationID {
    idReads++;
    return super.conversationID;
  }
}

typedef _Page = ({
  List<V2TimConversation> conversationList,
  String nextSeq,
  bool isFinished,
  int code,
  String desc
});
_Page _page(List<V2TimConversation> rows, {String next = '0'}) => (
      conversationList: rows,
      nextSeq: next,
      isFinished: next == '0',
      code: 0,
      desc: ''
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationTabStore.instance;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    ChatSessionController.instance.clearSessionProjection();
    ActiveChatRegistry.instance.reset();
    ConversationUnreadAggregate.instance.clearSession();
    ConversationPinSyncService.instance.debugReplacePinnedIdsForTest({});
    archivedConversationC2cIDsNotifier.value = {};
    archivedConversationGroupIDsNotifier.value = {};
    store.clear();
    store.notifyColdStartEnded();
  });
  tearDown(() {
    ConversationTabStore.debugFetchOverride = null;

    ConversationLocalStore.instance.debugOwnerUserId = null;
    archivedConversationC2cIDsNotifier.value = {};
    archivedConversationGroupIDsNotifier.value = {};
    store.clear();
    ChatSessionController.instance.clearSessionProjection();
  });

  for (final type in [1, 2]) {
    for (final size in [500, 1000, 2000]) {
      test(
          '$size type-$type rows: 100 existing single-row patches do not walk the window',
          () {
        String id(int i) => type == 1 ? 'c2c_index$i' : 'group_@TGS#9index$i';
        store.setItemsForTest(
            convType: type,
            items: List.generate(size, (i) => _CountedRow(id(i), type)));
        _CountedRow.idReads = 0;
        for (var i = 0; i < 100; i++) {
          final target = (i * 37) % size;
          store.applyPatches([_row(id(target), type: type)], notify: false);
          expect(store.typeIndexOf(type, id(target)), target);
        }
        final noOpReads = _CountedRow.idReads;
        // Count SDK property reads, not elapsed time: the old per-batch ID
        // table alone reads 50k/100k/200k rows in these same 100 patches.
        expect(noOpReads, lessThan(2000));
        _CountedRow.idReads = 0;
        for (var i = 0; i < 100; i++) {
          final target = (i * 37) % size;
          store.applyPatches([_row(id(target), type: type, unread: i + 1)],
              explicitUnreadIds: {id(target)},
              preserveOrder: true,
              notify: false);
          expect(store.typeIndexOf(type, id(target)), target);
          expect(store.atTypeIndex(type, target)!.unreadCount, i + 1);
        }
        final contentReads = _CountedRow.idReads;
        expect(contentReads, lessThan(3000));
        // ignore: avoid_print
        print(
            'TabStore index: type=$type size=$size patches=100 noOpIdReads=$noOpReads contentIdReads=$contentReads');
      });
    }
  }

  test('group display refresh does not rescan the C2C window per visible row',
      () {
    store.setItemsForTest(
        convType: 1,
        items: List.generate(425, (i) => _CountedRow('c2c_display$i', 1)));
    final groups =
        List.generate(480, (i) => _CountedRow('group_@TGS#9display$i', 2));
    store.setItemsForTest(convType: 2, items: groups);
    final view = store.conversations;
    expect(view.length, 905);

    _CountedRow.idReads = 0;
    for (var i = 0; i < 20; i++) {
      expect(store.conversationForId('group_@TGS#9display$i'), same(groups[i]));
    }
    final compatibilityReads = _CountedRow.idReads;
    expect(compatibilityReads, greaterThan(425 * 20));

    _CountedRow.idReads = 0;
    for (var i = 0; i < 480; i++) {
      expect(store.displayConversationForId('group_@TGS#9display$i'),
          same(groups[i]));
    }
    expect(_CountedRow.idReads, lessThan(480));
    // ignore: avoid_print
    print('Visible refresh: legacy 20 lookups=$compatibilityReads ID reads; '
        'display 480 lookups=${_CountedRow.idReads} ID reads');
  });

  test('display identity follows content, delete and session changes', () {
    store.setItemsForTest(convType: 1, items: [_row('c2c_same', unread: 2)]);
    store.setItemsForTest(
        convType: 2, items: [_row('group_same', type: 2, unread: 3)]);
    expect(store.displayConversationForId('c2c_same')!.unreadCount, 2);
    expect(store.displayConversationForId('group_same')!.unreadCount, 3);
    expect(store.displayConversationForId('same'), isNull);
    store.applyPatches([_row('group_same', type: 2, unread: 9)],
        preserveOrder: true, explicitUnreadIds: {'group_same'}, notify: false);
    expect(store.displayConversationForId('group_same')!.unreadCount, 9);
    expect(store.displayConversationForId('c2c_same')!.unreadCount, 2);
    store.applyDeleted(['group_same'], notify: false);
    expect(store.displayConversationForId('group_same'), isNull);
    store.clear();
    expect(store.displayConversationForId('c2c_same'), isNull);
  });

  test(
      'candidate aliases exactly agree with the existing conversation predicate',
      () {
    final ids = [
      'group_@TGS#9index',
      '9index',
      '@TGS#9index',
      'group_9index',
      'group_@TGS#_@TGS#cJSFLQIM62CX',
      'cJSFLQIM62CX',
      'group_cJSFLQIM62CX',
      'group_c2c_alice',
      'c2c_alice',
      'alice',
      'C2Calice',
      'GROUPalice',
      'group_alice',
      'c2c_Alice',
      ' group_@TGS#9index ',
      '',
      'c2c_missing',
    ];
    // Each row stands alone so duplicate aliases cannot hide a missing bucket.
    for (final existingId in ids.where((id) => id.trim().isNotEmpty)) {
      store.setItemsForTest(convType: 2, items: [_row(existingId, type: 2)]);
      for (final query in ids) {
        expect(
            store.typeIndexOf(2, query),
            MessageConversationId.sameConversation(existingId, query)
                ? 0
                : null,
            reason: '$existingId <- $query');
      }
    }
  });

  test(
      'read returns the first duplicate; patch retains last comparable-row behavior',
      () {
    store.setItemsForTest(
        convType: 1, items: [_row('c2c_dup'), _row('c2c_dup')]);
    store.applyPatches([_row('c2c_dup', unread: 8)],
        notify: false, preserveOrder: true);
    expect(store.typeIndexOf(1, 'c2c_dup'), 0);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 0);
    expect(store.atTypeIndex(1, 1)!.unreadCount, 8);
  });

  test(
      'append, delete and content replacement keep subsequent positions current',
      () {
    store.setItemsForTest(convType: 1, items: [_row('c2c_a'), _row('c2c_b')]);
    store.applyPatches([_row('c2c_c')],
        forceAdmitIds: {'c2c_c'}, preserveOrder: true, notify: false);
    expect(store.typeIndexOf(1, 'c2c_c'), 2);
    store.applyDeleted(['c2c_a'], notify: false);
    expect(store.typeIndexOf(1, 'c2c_a'), isNull);
    expect(store.typeIndexOf(1, 'c2c_b'), 0);
    expect(store.typeIndexOf(1, 'c2c_c'), 1);
    store.applyPatches([_row('c2c_c', unread: 7)],
        preserveOrder: true, notify: false);
    expect(store.atTypeIndex(1, 1)!.unreadCount, 7);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 0);
  });

  test(
      'sorting and scroll-unfreeze publish the new index before listeners read',
      () {
    store.setItemsForTest(convType: 1, items: [
      _row('c2c_a', order: 1700000000020),
      _row('c2c_b', order: 1700000000010)
    ]);
    store.setSortFrozenByScroll(true);
    store.applyPatches([_row('c2c_b', order: 1700000000030)], notify: false);
    expect(store.typeIndexOf(1, 'c2c_b'), 1);
    void listen() => expect(store.typeIndexOf(1, 'c2c_b'), 0);
    store.addListener(listen);
    store.setSortFrozenByScroll(false);
    store.removeListener(listen);
    store.applyPatches([_row('c2c_a', order: 1700000000040)], notify: false);
    expect(store.typeIndexOf(1, 'c2c_a'), 0);
    expect(store.typeIndexOf(1, 'c2c_b'), 1);
  });

  test('committed explicit move updates following row lookups', () {
    store.setItemsForTest(
        convType: 1, items: [_row('c2c_a'), _row('c2c_b'), _row('c2c_c')]);
    store
        .applyCommittedViewBatch(ConversationUiSnapshotBatch<V2TimConversation>(
      upsertedSnapshots: [_row('c2c_c')],
      deletedCanonicalIds: const [],
      structureChanged: true,
      changedFieldMasks: const {},
      commitGeneration: 1,
      moves: const [
        ConversationUiMove(
            conversationID: 'c2c_c',
            convType: 1,
            oldIndex: 2,
            newIndex: 0,
            reason: 'index_test')
      ],
    ));
    expect(store.typeIndexOf(1, 'c2c_c'), 0);
    expect(store.typeIndexOf(1, 'c2c_a'), 1);
    store.applyPatches([_row('c2c_a', unread: 4)],
        preserveOrder: true, notify: false);
    expect(store.atTypeIndex(1, 1)!.unreadCount, 4);
  });

  test('archive purge and archive patch removal keep the surviving indices',
      () {
    store.setItemsForTest(
        convType: 1, items: [_row('c2c_a'), _row('c2c_b'), _row('c2c_c')]);
    archivedConversationC2cIDsNotifier.value = {'c2c_a'};
    store.purgeArchived(notify: false);
    expect(store.typeIndexOf(1, 'c2c_b'), 0);
    archivedConversationC2cIDsNotifier.value = {'c2c_a', 'c2c_b'};
    store.applyPatches([_row('c2c_b')], notify: false);
    expect(store.typeIndexOf(1, 'c2c_c'), 0);
    expect(store.countForType(1), 1);
    store.applyPatches([_row('c2c_c', unread: 9)], notify: false);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 9);
  });

  test('in-place SDK changes preserve ID repair and accepted unread snapshots',
      () {
    final shared = _row('c2c_before', unread: 3);
    store.setItemsForTest(convType: 1, items: [shared]);
    store.zeroUnreadLocallyMany(['c2c_before']);
    store.applyPatches([_row('c2c_before', unread: 3)],
        explicitUnreadIds: {'c2c_before'}, notify: false);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 3);
    final current = store.atTypeIndex(1, 0)!;
    current.conversationID = 'c2c_after';
    current.userID = 'after';
    current.unreadCount = 5;
    store.applyPatches([current],
        explicitUnreadIds: {'c2c_after'}, notify: false);
    expect(store.countForType(1), 1);
    expect(store.typeIndexOf(1, 'c2c_before'), isNull);
    expect(store.typeIndexOf(1, 'c2c_after'), 0);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 5);
    // A different callback object after an unannounced ID mutation still
    // takes the compatibility miss path and patches the retained row.
    store.atTypeIndex(1, 0)!.conversationID = 'c2c_final';
    store.applyPatches([_row('c2c_final', unread: 7)], notify: false);
    expect(store.countForType(1), 1);
    expect(store.typeIndexOf(1, 'c2c_final'), 0);
    expect(store.atTypeIndex(1, 0)!.unreadCount, 7);
  });

  test(
      'SDK pages, reset and late old-account response do not leave stale indices',
      () async {
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) async =>
        nextSeq == '0'
            ? _page([_row('c2c_a')], next: 'older')
            : _page([_row('c2c_b')]);
    await store.loadFirstPage(convType: 1, count: 1);
    await store.loadMore(convType: 1, count: 1);
    expect(store.typeIndexOf(1, 'c2c_a'), 0);
    expect(store.typeIndexOf(1, 'c2c_b'), 1);
    final pending = Completer<_Page>();
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) =>
        pending.future;
    final oldRequest = store.loadFirstPage(convType: 1, count: 1);
    await Future<void>.delayed(Duration.zero);
    store.clear();
    store.notifyColdStartEnded();
    store.setItemsForTest(convType: 1, items: [_row('c2c_new_account')]);
    pending.complete(_page([_row('c2c_old_account')]));
    await oldRequest;
    expect(store.typeIndexOf(1, 'c2c_a'), isNull);
    expect(store.typeIndexOf(1, 'c2c_old_account'), isNull);
    expect(store.typeIndexOf(1, 'c2c_new_account'), 0);
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) async =>
        _page([_row('c2c_reset')]);
    await store.loadFirstPage(convType: 1, count: 1);
    expect(store.typeIndexOf(1, 'c2c_new_account'), isNull);
    expect(store.typeIndexOf(1, 'c2c_reset'), 0);
  });

  test('SDK page replacement and pagination populate indices', () async {
    ConversationTabStore.debugFetchOverride = (
            {required convType, required nextSeq, required count}) async =>
        nextSeq == '0'
            ? (
                conversationList: [
                  _row('c2c_sql_a', order: 1700000000030),
                  _row('c2c_sql_b', order: 1700000000020)
                ],
                nextSeq: '2',
                isFinished: false,
                code: 0,
                desc: ''
              )
            : _page([_row('c2c_sql_c', order: 1700000000010)]);
    await store.loadFirstPage(convType: 1, count: 2);
    expect(store.typeIndexOf(1, 'c2c_sql_a'), 0);
    expect(store.typeIndexOf(1, 'c2c_sql_b'), 1);
    await store.loadMore(convType: 1, count: 2);
    expect(store.typeIndexOf(1, 'c2c_sql_c'), 2);
    store.applyPatches([_row('c2c_sql_c', unread: 5, order: 1700000000010)],
        preserveOrder: true, notify: false);
    expect(store.atTypeIndex(1, 2)!.unreadCount, 5);
  });
}
