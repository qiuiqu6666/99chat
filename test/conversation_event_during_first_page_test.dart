import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

const _owner = 'stage117_realtime_page_owner';

V2TimConversation _row(int unread) => V2TimConversation(
      conversationID: 'c2c_stage117_live',
      type: 1,
      userID: 'stage117_live',
      unreadCount: unread,
      orderkey: unread,
    );

ConversationDatabaseCommitPlan<V2TimConversation> _plan({
  required String key,
  required int generation,
  required int unread,
}) =>
    ConversationDatabaseCommitPlan<V2TimConversation>(
      ownerUserId: _owner,
      canonicalConversationId: 'c2c_stage117_live',
      conversationType: ConversationMutationConversationType.c2c,
      changeType: ConversationDatabaseChangeType.upsert,
      generation: generation,
      tombstone: false,
      idempotencyKey: key,
      recreatesDeletedConversation: false,
      fullSnapshot: _row(unread),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    await ConversationLocalStore.instance.clearForOwner(_owner);
  });

  tearDown(() async {
    await ConversationLocalStore.instance.clearForOwner(_owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('realtime event wins over a late older first-page snapshot', () async {
    await ConversationLocalStore.instance.commitCoordinatorSdkUpsertPlansBatch(
      plans: [_plan(key: 'page', generation: 1, unread: 1)],
    );
    await ConversationLocalStore.instance.commitCoordinatorSdkUpsertPlansBatch(
      plans: [_plan(key: 'live', generation: 2, unread: 9)],
    );
    final stale = await ConversationLocalStore.instance
        .commitCoordinatorSdkUpsertPlansBatchResult(
      plans: [_plan(key: 'late-page', generation: 1, unread: 2)],
    );

    expect(stale.upserted, isEmpty);
    expect(
      (await ConversationLocalStore.instance.conversationById(
        'c2c_stage117_live',
        ownerUserId: _owner,
      ))
          ?.unreadCount,
      9,
    );
  });
}
