import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

const _owner = 'stage117_commit_owner';

V2TimConversation _row(int index) => V2TimConversation(
      conversationID: 'group_stage117_$index',
      type: 2,
      groupID: 'stage117_$index',
      unreadCount: index,
      orderkey: index,
    );

ConversationDatabaseCommitPlan<V2TimConversation> _plan(int index) =>
    ConversationDatabaseCommitPlan<V2TimConversation>(
      ownerUserId: _owner,
      canonicalConversationId: 'group_stage117_$index',
      conversationType: ConversationMutationConversationType.group,
      changeType: ConversationDatabaseChangeType.upsert,
      generation: 1,
      tombstone: false,
      idempotencyKey: 'stage117-$index',
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

  test('one page is one atomic transaction and one durable batch', () async {
    final result = await ConversationLocalStore.instance
        .commitCoordinatorSdkUpsertPlansBatchResult(
      plans: List.generate(100, _plan),
    );

    expect(result.upserted, hasLength(100));
    expect(
        ConversationLocalStore
            .instance.batchProfileForTest.atomicSdkTransactions,
        1);
    expect(await ConversationLocalStore.instance.countRows(ownerUserId: _owner),
        100);
  });

  test('same idempotency key is committed only once', () async {
    final first = await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(1),
    );
    final second = await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(1),
    );

    expect(first.disposition, ConversationDatabaseCommitDisposition.applied);
    expect(second.disposition,
        ConversationDatabaseCommitDisposition.ignoredDuplicate);
    expect(await ConversationLocalStore.instance.countRows(ownerUserId: _owner),
        1);
  });
}
