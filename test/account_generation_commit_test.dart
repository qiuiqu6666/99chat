import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

V2TimConversation _row(int unread) => V2TimConversation(
      conversationID: 'c2c_shared_identity',
      type: 1,
      userID: 'shared_identity',
      unreadCount: unread,
      orderkey: unread,
    );

ConversationDatabaseCommitPlan<V2TimConversation> _plan({
  required String owner,
  required String key,
  required int generation,
  required int unread,
}) =>
    ConversationDatabaseCommitPlan<V2TimConversation>(
      ownerUserId: owner,
      canonicalConversationId: 'c2c_shared_identity',
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    ConversationLocalStore.instance.debugOwnerUserId = 'stage117_account_a';
    await ConversationLocalStore.instance.clearForOwner('stage117_account_a');
    await ConversationLocalStore.instance.clearForOwner('stage117_account_b');
  });

  tearDown(() async {
    await ConversationLocalStore.instance.clearForOwner('stage117_account_a');
    await ConversationLocalStore.instance.clearForOwner('stage117_account_b');
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('same conversation id remains isolated across account scopes', () async {
    await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(
        owner: 'stage117_account_a',
        key: 'a-1',
        generation: 1,
        unread: 2,
      ),
    );
    await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(
        owner: 'stage117_account_b',
        key: 'b-1',
        generation: 1,
        unread: 8,
      ),
    );

    expect(
      (await ConversationLocalStore.instance.conversationById(
        'c2c_shared_identity',
        ownerUserId: 'stage117_account_a',
      ))
          ?.unreadCount,
      2,
    );
    expect(
      (await ConversationLocalStore.instance.conversationById(
        'c2c_shared_identity',
        ownerUserId: 'stage117_account_b',
      ))
          ?.unreadCount,
      8,
    );
  });

  test('older generation cannot overwrite the active account scope', () async {
    await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(
        owner: 'stage117_account_a',
        key: 'a-new',
        generation: 3,
        unread: 9,
      ),
    );
    final stale = await ConversationLocalStore.instance.commitCoordinatorPlan(
      plan: _plan(
        owner: 'stage117_account_a',
        key: 'a-old',
        generation: 2,
        unread: 1,
      ),
    );

    expect(stale.disposition,
        ConversationDatabaseCommitDisposition.rejectedStaleGeneration);
    expect(
      (await ConversationLocalStore.instance.conversationById(
        'c2c_shared_identity',
        ownerUserId: 'stage117_account_a',
      ))
          ?.unreadCount,
      9,
    );
  });
}
