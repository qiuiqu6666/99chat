import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_shadow_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_unread_clear_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_conversation_read_service.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

const _owner = 'read_restart_owner';
const _id = 'group_@TGS#_mc2SX4NMM62CZ';

V2TimConversation _row(int unread, int seq) => V2TimConversation(
      conversationID: _id,
      type: 2,
      groupID: '@TGS#_mc2SX4NMM62CZ',
      unreadCount: unread,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': 'm$seq',
        'message_server_time': 1790401192 + seq - 2743454,
        'message_is_from_self': false,
        'message_risk_type_identified': 0,
      })
        ..seq = '$seq',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationLocalStore.instance;
  final bridge = ConversationMutationShadowBridge.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store.debugOwnerUserId = _owner;
    ConversationSyncService.instance.debugOwnerUserId = _owner;
    await store.clearForOwner(_owner);
    await ConversationReadOutboxStore.instance.clearOwner(_owner);
    bridge.resetForTest();
  });
  tearDown(() async {
    ConversationUnreadClearService.resetCoordinatorStateForTesting();
    ConversationSyncService.instance.resetChatTransitionStateForTesting();
    TencentConversationReadService.cleanUnreadForTesting = null;
    ChatSessionController.instance.clearSessionProjection();
    await ConversationReadOutboxStore.instance.clearOwner(_owner);
    await store.clearForOwner(_owner);
    await store.flushReadBarrierWritesForTest();
    store.resetAnchorStateForTest();
    store.debugOwnerUserId = null;
    bridge.resetForTest();
  });

  test('opening chat after restart respects persisted SDK frequency cooldown',
      () async {
    final outbox = ConversationReadOutboxStore.instance;
    await outbox.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        cleanSequence: 2743454,
        lastReadAtMs: 1);
    final cooldown = DateTime.now().millisecondsSinceEpoch + 60000;
    await outbox.markRetry(
        (await outbox.find(ownerUserId: _owner, conversationId: _id))!,
        sdkCode: -10113,
        notBeforeAtMs: cooldown);
    var calls = 0;
    TencentConversationReadService.cleanUnreadForTesting = ({
      required conversationID,
      required cleanTimestamp,
      required cleanSequence,
    }) async {
      calls++;
      return V2TimCallback(code: 0, desc: 'ok');
    };
    await ConversationUnreadClearService.clearLocalForOpen(
        conversation: _row(6321, 2743458));
    await ConversationUnreadClearService.scheduleSdkUnreadClean(
        conversationID: _id, trigger: SdkUnreadCleanTrigger.open);
    expect(calls, 0);
    expect(
        (await outbox.find(ownerUserId: _owner, conversationId: _id))!
            .nextRetryAtMs,
        greaterThanOrEqualTo(cooldown));
  });

  for (final fast in [false, true]) {
    test('opening paused group really dispatches bounded SDK clear; fast=$fast',
        () async {
      final outbox = ConversationReadOutboxStore.instance;
      await outbox.enqueue(
          ownerUserId: _owner,
          conversationId: _id,
          cleanSequence: 2743454,
          lastReadMessageId: 'old',
          lastReadAtMs: 1);
      await outbox.markRetry(
          (await outbox.find(ownerUserId: _owner, conversationId: _id))!,
          sdkCode: 6017);
      final requests = <(String, int, int)>[];
      final dispatched = Completer<void>();
      TencentConversationReadService.cleanUnreadForTesting = ({
        required conversationID,
        required cleanTimestamp,
        required cleanSequence,
      }) async {
        requests.add((conversationID, cleanTimestamp, cleanSequence));
        if (!dispatched.isCompleted) dispatched.complete();
        return V2TimCallback(code: 0, desc: 'ok');
      };
      await ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: _id, trigger: SdkUnreadCleanTrigger.leave);
      expect(requests, isEmpty,
          reason: 'passive leave must not restart paused work');
      final conversation = _row(6321, 2743458);
      await store
          .upsertBatch(conversations: [conversation], ownerUserId: _owner);
      if (fast) {
        await ConversationUnreadClearService.clearLocalForOpenFast(
            conversation: conversation);
        await dispatched.future.timeout(const Duration(seconds: 5));
      } else {
        await ConversationUnreadClearService.clearLocalForOpen(
            conversation: conversation);
      }
      await ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: _id, trigger: SdkUnreadCleanTrigger.open);
      expect(requests, [(_id, 0, 2743458)]);
      expect(
          await outbox.find(ownerUserId: _owner, conversationId: _id), isNull);
      // The fast path commits local projection independently from SDK dispatch.
      await ConversationSyncService.instance
          .markConversationReadLocally(_id, forceImmediateUi: true);
      expect(
          (await store.conversationById(_id, ownerUserId: _owner))?.unreadCount,
          0);
      expect(
          ConversationTabStore.instance.conversationForId(_id)?.unreadCount, 0);
    });
  }

  test('restart does not mistake a new read for an old durable commit',
      () async {
    await store
        .upsertBatch(conversations: [_row(6321, 2743454)], ownerUserId: _owner);
    Future<ConversationDatabaseCommitPlan<V2TimConversation>> read() async =>
        (await bridge.prepareLocalIntentCommit(
          ownerUserId: _owner,
          conversationId: _id,
          fieldPatch: const {ConversationMutationField.unread: 0},
          sourceVersion: 1800000000,
        ))!;
    final first = await read();
    expect((await store.commitCoordinatorPlan(plan: first)).disposition,
        ConversationDatabaseCommitDisposition.applied);
    // A subsequent message is still unread when the next process opens chat.
    store.resetAnchorStateForTest();
    await store
        .upsertBatch(conversations: [_row(4, 2743458)], ownerUserId: _owner);
    await store.clearSession(ownerUserId: _owner);
    await store.closeDatabaseForTest();
    bridge.resetForTest(); // Reopen SQLite with only the durable keys retained.
    final reopened = await read();
    final result = await store.commitCoordinatorPlan(plan: reopened);
    expect(result.disposition, ConversationDatabaseCommitDisposition.applied);
    expect(
        (await store.conversationById(_id, ownerUserId: _owner))?.unreadCount,
        0);
    // Replaying the identical plan must still be idempotent.
    expect((await store.commitCoordinatorPlan(plan: reopened)).disposition,
        ConversationDatabaseCommitDisposition.ignoredDuplicate);
  });

  test('SDK updates after restart do not collide with old SDK commit IDs',
      () async {
    Future<ConversationDatabaseCommitPlan<V2TimConversation>> sdk(
            int unread, int seq) async =>
        (await bridge.prepareSdkConversationCommits(
          ownerUserId: _owner,
          conversations: [_row(unread, seq)],
          source: ConversationMutationSource.sdkRealtime,
        ))
            .single
            .plan;
    final first = await sdk(6321, 2743454);
    await store.commitCoordinatorPlan(plan: first);
    await store.clearSession(ownerUserId: _owner);
    await store.closeDatabaseForTest();
    bridge.resetForTest();
    final second = await sdk(6325, 2743458);
    expect((await store.commitCoordinatorPlan(plan: second)).disposition,
        ConversationDatabaseCommitDisposition.applied);
    expect(
        (await store.conversationById(_id, ownerUserId: _owner))
            ?.lastMessage
            ?.seq,
        '2743458');
  });
}
