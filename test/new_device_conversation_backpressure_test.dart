import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

const _owner = 'stage117_new_device_owner';

V2TimConversation _row(int index) => V2TimConversation(
      conversationID: 'c2c_stage117_$index',
      type: 1,
      userID: 'stage117_$index',
      orderkey: 3000 - index,
    );

ConversationDatabaseCommitPlan<V2TimConversation> _plan(int index) =>
    ConversationDatabaseCommitPlan<V2TimConversation>(
      ownerUserId: _owner,
      canonicalConversationId: 'c2c_stage117_$index',
      conversationType: ConversationMutationConversationType.c2c,
      changeType: ConversationDatabaseChangeType.upsert,
      generation: 1,
      tombstone: false,
      idempotencyKey: 'new-device-$index',
      recreatesDeletedConversation: false,
      fullSnapshot: _row(index),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    ConversationLocalStore.instance.resetBatchProfileForTest();
    await ConversationLocalStore.instance.clearForOwner(_owner);
  });

  tearDown(() async {
    await ConversationLocalStore.instance.clearForOwner(_owner);
    ConversationLocalStore.instance.resetBatchProfileForTest();
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('large account is committed by bounded pages, not row transactions',
      () async {
    for (var page = 0; page < 3; page++) {
      await ConversationLocalStore.instance
          .commitCoordinatorSdkUpsertPlansBatch(
        plans: [for (var i = page * 100; i < (page + 1) * 100; i++) _plan(i)],
      );
      if (page == 0) {
        expect(
            await ConversationLocalStore.instance
                .countRows(ownerUserId: _owner),
            100);
      }
    }

    final profile = ConversationLocalStore.instance.batchProfileForTest;
    expect(profile.atomicSdkTransactions, 3);
    expect(await ConversationLocalStore.instance.countRows(ownerUserId: _owner),
        300);
  });
}
