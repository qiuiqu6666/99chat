import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

const _owner = 'friend_accept_c2c_owner';

V2TimConversation _c2c(
  String id, {
  int unread = 0,
  int orderkey = 0,
}) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
    unreadCount: unread,
    orderkey: orderkey,
    showName: id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    ConversationLocalStore.bypassUpsertCoalesceForTest = true;
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    ConversationSyncService.instance.resetChatTransitionStateForTesting();
    ConversationSyncService.instance.debugOwnerUserId = _owner;
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    ChatSessionController.instance.clearSessionProjection();
    ConversationTabStore.instance.clear();
    ConversationTabStore.instance.notifyColdStartEnded();
    await ConversationLocalStore.instance.clearForOwner(_owner);
  });

  tearDown(() async {
    ConversationSyncService.instance.resetChatTransitionStateForTesting();
    ConversationMutationShadowBridge.instance.resetForTest();
    ConversationUnreadAggregate.instance.resetForTest();
    ChatSessionController.instance.clearSessionProjection();
    await ConversationLocalStore.instance.clearForOwner(_owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
    ConversationLocalStore.bypassUpsertCoalesceForTest = false;
    ConversationTabStore.instance.clear();
  });

  test(
    'refreshConversationItem creates missing C2C when SDK getConversation is null',
    () async {
      ConversationSyncService.instance.debugGetConversationOverride =
          (_) async => null;

      await ConversationSyncService.instance.refreshConversationItem(
        'c2c_new_peer',
      );

      expect(
        ConversationTabStore.instance
            .itemsForType(1)
            .map((row) => row.conversationID),
        contains('c2c_new_peer'),
      );
    },
  );

  test(
    'refreshConversationItem does not create a row when group getConversation is null',
    () async {
      ConversationSyncService.instance.debugGetConversationOverride =
          (_) async => null;

      await ConversationSyncService.instance.refreshConversationItem(
        'group_missing_room',
      );

      expect(ConversationTabStore.instance.itemsForType(1), isEmpty);
      expect(ConversationTabStore.instance.itemsForType(2), isEmpty);
    },
  );

  test(
    'forceAdmit inserts zero-unread C2C that is colder than the window head',
    () {
      ConversationTabStore.instance.setItemsForTest(
        convType: 1,
        items: [_c2c('c2c_hot_existing', orderkey: 9000)],
        finished: true,
      );

      ConversationTabStore.instance.applyPatches(
        [_c2c('c2c_new_friend', unread: 0, orderkey: 1)],
        reason: 'friend_list_changed',
        forceAdmitIds: const <String>{'c2c_new_friend'},
      );

      expect(
        ConversationTabStore.instance
            .itemsForType(1)
            .map((row) => row.conversationID),
        contains('c2c_new_friend'),
      );
    },
  );

  test(
    'forceAdmit keeps a new C2C in the type window when already at cap',
    () {
      final cap = ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
      final existing = List<V2TimConversation>.generate(
        cap,
        (index) => _c2c('c2c_cap_$index', orderkey: cap - index),
      );
      ConversationTabStore.instance.setItemsForTest(
        convType: 1,
        items: existing,
        finished: true,
      );

      ConversationTabStore.instance.applyPatches(
        [_c2c('c2c_force_admit', unread: 0, orderkey: 0)],
        reason: 'friend_list_changed',
        forceAdmitIds: const <String>{'c2c_force_admit'},
      );

      expect(
        ConversationTabStore.instance
            .itemsForType(1)
            .map((row) => row.conversationID),
        contains('c2c_force_admit'),
      );
      expect(
        ConversationTabStore.instance.detachedHeadIdsForTest(1),
        isNot(contains('c2c_force_admit')),
      );
    },
  );
}
