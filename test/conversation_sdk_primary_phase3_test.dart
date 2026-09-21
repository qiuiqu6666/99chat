import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

V2TimConversation _c2c(String id, {int unread = 0}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    showName: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'sdk_primary_phase3_owner';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    archivedConversationC2cIDsNotifier.value = <String>{};
    archivedConversationGroupIDsNotifier.value = <String>{};
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    ConversationLocalStore.instance.debugOwnerUserId = owner;
    await ConversationLocalStore.instance.clearForOwner(owner);
  });

  tearDown(() async {
    ConversationTabStore.debugFetchByIdsOverride = null;
    archivedConversationC2cIDsNotifier.value = <String>{};
    archivedConversationGroupIDsNotifier.value = <String>{};
    ConversationTabStore.instance.clear();
    ChatSessionController.instance.clearSessionProjection();
    await ConversationLocalStore.instance.clearForOwner(owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('Phase3: loadFirstPage skips archived ids', () async {
    archivedConversationC2cIDsNotifier.value = {'c2c_archived'};
    ConversationTabStore.debugFetchOverride = (
            {required int convType,
            required String nextSeq,
            required int count}) async =>
        (
          conversationList: [_c2c('c2c_keep'), _c2c('c2c_archived')],
          nextSeq: '0',
          isFinished: true,
          code: 0,
          desc: ''
        );
    addTearDown(() => ConversationTabStore.debugFetchOverride = null);

    await ConversationTabStore.instance.loadFirstPage(convType: 1);
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((c) => c.conversationID),
      ['c2c_keep'],
    );
  });

  test('Phase3: applyPatches removes newly archived row', () {
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_a'), _c2c('c2c_b')],
      finished: true,
    );
    archivedConversationC2cIDsNotifier.value = {'c2c_a'};
    ConversationTabStore.instance.applyPatches(
      [_c2c('c2c_a', unread: 3)],
      reason: 'test',
    );
    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .map((c) => c.conversationID),
      ['c2c_b'],
    );
  });

  test('Phase3: purgeArchived + sdk-primary archive sync', () async {
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    ConversationTabStore.instance.setItemsForTest(
      convType: 1,
      items: [_c2c('c2c_keep'), _c2c('c2c_gone')],
      finished: true,
    );
    ChatSessionController.instance.ensureTabStoreBridgeAttached();
    // Force adopt once.
    ConversationTabStore.instance.applyPatches(
      [_c2c('c2c_keep')],
      reason: 'seed',
    );

    archivedConversationC2cIDsNotifier.value = {'c2c_gone'};
    await ChatSessionController.instance.syncMainListAfterArchiveChange(
      removedIds: const ['c2c_gone'],
      reason: 'phase3_test',
    );

    expect(
      ConversationTabStore.instance
          .itemsForType(1)
          .any((c) => c.conversationID == 'c2c_gone'),
      isFalse,
    );
    expect(
      ChatSessionController.instance.conversations
          .any((c) => c.conversationID == 'c2c_gone'),
      isFalse,
    );
  });

  test('SDK restore batches at 100 and does not populate SQLite', () async {
    final batches = <int>[];
    ConversationTabStore.debugFetchByIdsOverride = (ids) async {
      batches.add(ids.length);
      return (conversationList: ids.map((id) => _c2c(id)).toList(), code: 0);
    };
    final admitted = await ConversationTabStore.instance
        .restoreSdkConversationsByIds(
            List.generate(205, (i) => 'c2c_restore$i'));
    expect(batches, [100, 100, 5]);
    expect(admitted, 205);
    expect(
        await ConversationLocalStore.instance.countByConvType(convType: 1), 0);
  });

  test('SDK restore preserves concurrent update, deletion and rearchive',
      () async {
    final response =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    ConversationTabStore.debugFetchByIdsOverride = (ids) => response.future;
    final tabs = ConversationTabStore.instance;
    final pending = tabs.restoreSdkConversationsByIds(
        ['c2c_update', 'c2c_delete', 'c2c_rearchive', 'c2c_draft']);
    tabs.applyPatches([_c2c('c2c_update', unread: 7)],
        explicitUnreadIds: {'c2c_update'});
    // Deletion must be remembered even when no row was loaded yet.
    tabs.applyDeleted(['c2c_delete']);
    archivedConversationC2cIDsNotifier.value = {'c2c_rearchive'};
    tabs.applyPatches([_c2c('c2c_draft')], explicitDraftIds: {'c2c_draft'});
    response.complete((
      conversationList: [
        _c2c('c2c_update', unread: 1),
        _c2c('c2c_delete'),
        _c2c('c2c_rearchive'),
        _c2c('c2c_draft')..draftText = 'old draft',
      ],
      code: 0
    ));
    expect(await pending, 2);
    final rows = tabs.itemsForType(1);
    expect(rows.map((row) => row.conversationID),
        unorderedEquals(['c2c_update', 'c2c_draft']));
    expect(
        rows
            .singleWhere((row) => row.conversationID == 'c2c_update')
            .unreadCount,
        7);
    expect(
        rows.singleWhere((row) => row.conversationID == 'c2c_draft').draftText,
        isNull);
  });

  test('SDK restore metadata patch preserves SDK draft', () async {
    final response =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    ConversationTabStore.debugFetchByIdsOverride = (ids) => response.future;
    final tabs = ConversationTabStore.instance;
    final pending = tabs.restoreSdkConversationsByIds(['c2c_draft']);
    tabs.applyPatches([_c2c('c2c_draft')..isPinned = true]);
    response.complete((
      conversationList: [_c2c('c2c_draft')..draftText = 'keep draft'],
      code: 0
    ));
    expect(await pending, 1);
    expect(tabs.itemsForType(1).single.draftText, 'keep draft');
    expect(tabs.itemsForType(1).single.isPinned, isTrue);
  });

  test('SDK restore explicit zero unread clears an existing hot row', () async {
    final tabs = ConversationTabStore.instance;
    tabs.setItemsForTest(convType: 1, items: [_c2c('c2c_zero', unread: 8)]);
    ConversationTabStore.debugFetchByIdsOverride = (ids) async =>
        (conversationList: [_c2c('c2c_zero', unread: 0)], code: 0);
    expect(await tabs.restoreSdkConversationsByIds(['c2c_zero']), 1);
    expect(tabs.itemsForType(1).single.unreadCount, 0);
  });

  test('local zero unread wins over pending ByIDs without reviving deletion',
      () async {
    final tabs = ConversationTabStore.instance;
    tabs.setItemsForTest(convType: 1, items: [_c2c('c2c_loaded', unread: 8)]);
    final response =
        Completer<({List<V2TimConversation> conversationList, int code})>();
    ConversationTabStore.debugFetchByIdsOverride = (ids) => response.future;
    final pending = tabs.restoreSdkConversationsByIds(
        ['c2c_loaded', 'c2c_absent', 'c2c_deleted']);
    tabs.applyDeleted(['c2c_deleted']);
    tabs.zeroUnreadLocallyMany(['c2c_loaded', 'c2c_absent', 'c2c_deleted']);
    response.complete((
      conversationList: [
        _c2c('c2c_loaded', unread: 8),
        _c2c('c2c_absent', unread: 6),
        _c2c('c2c_deleted', unread: 5),
      ],
      code: 0
    ));
    expect(await pending, 2);
    expect(tabs.itemsForType(1).map((row) => row.conversationID),
        unorderedEquals(['c2c_loaded', 'c2c_absent']));
    expect(tabs.itemsForType(1).map((row) => row.unreadCount), everyElement(0));
  });

  test('Phase3: mirror-only flag is on (UI authority documented)', () {
    expect(
        ConversationPerfFlags.conversationSqliteListFieldsMirrorOnly, isTrue);
  });
}
