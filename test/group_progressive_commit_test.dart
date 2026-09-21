import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

const _owner = 'stage117_group_owner';

ConversationDatabaseCommitPlan<V2TimConversation> _plan(
        String id, int generation) =>
    ConversationDatabaseCommitPlan<V2TimConversation>(
      ownerUserId: _owner,
      canonicalConversationId: 'group_$id',
      conversationType: ConversationMutationConversationType.group,
      changeType: ConversationDatabaseChangeType.upsert,
      generation: generation,
      tombstone: false,
      idempotencyKey: '$id-$generation',
      recreatesDeletedConversation: false,
      fullSnapshot: V2TimConversation(
        conversationID: 'group_$id',
        type: 2,
        groupID: id,
        orderkey: generation,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    await ConversationLocalStore.instance.clearForOwner(_owner);
  });

  tearDown(() async {
    await ConversationLocalStore.instance.clearForOwner(_owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('failed later page keeps the already committed first page', () async {
    await ConversationLocalStore.instance.commitCoordinatorSdkUpsertPlansBatch(
      plans: [_plan('first', 1)],
    );
    // A failed page produces no commit and must not be represented by a
    // replaceAll/delete operation.
    expect(await ConversationLocalStore.instance.countRows(ownerUserId: _owner),
        1);
    expect(
      (await ConversationLocalStore.instance.conversationById(
        'group_first',
        ownerUserId: _owner,
      ))
          ?.groupID,
      'first',
    );
  });
}
