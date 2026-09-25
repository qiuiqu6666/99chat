import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_retry_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.instance
        .saveAuthenticatedUserIdIfCurrent(expectedToken: null, userId: 'alice');
  });

  test(
      'two recovery coordinators invoke the SDK once; unknown outcome cannot redispatch',
      () async {
    final f = await _Fixture.create();
    await f.prepare();
    final sdk = _CountingSdk();
    Future<ImCoordinatedSendResult> send() => f.coordinator().send(
        messageService: sdk,
        sdkLocalId: 'local',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message,
        recoverPreparedOutbox: true,
        operationIdOverride: 'op',
        clientCorrelationIdOverride: 'corr');
    final first = send();
    final second = send();
    await sdk.entered.future;
    expect(sdk.calls, 1);
    sdk.result
        .completeError(StateError('transport disappeared after dispatch'));
    final outcomes = await Future.wait([first, second]);
    expect(outcomes.every((result) => result.outcomeUnknown), isTrue);
    await send();
    expect(sdk.calls, 1);
    expect((await f.read()).currentState, ImOutboxState.outcomeUnknown);
  });

  test(
      'two clicks on the same durable failure share one retry identity and SDK call',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    final sdk = _CountingSdk();
    var uiAdmissions = 0;
    Future<ImCoordinatedSendResult> retry(String localId) =>
        f.coordinator().send(
            messageService: sdk,
            sdkLocalId: localId,
            conversationId: 'c2c_bob',
            conversationType: ImConversationType.c2c,
            receiver: 'bob',
            groupID: '',
            fallbackMessage: f.message,
            retryOfSdkLocalId: 'local',
            onDispatchGranted: () => uiAdmissions++);
    final a = retry('recreated-a'), b = retry('recreated-b');
    await sdk.entered.future;
    sdk.result.complete(
        V2TimValueCallback<V2TimMessage>(code: 0, desc: '', data: f.message));
    final results = await Future.wait([a, b]);
    expect(sdk.calls, 1);
    expect(uiAdmissions, 1);
    expect(results.first.identity!.operationId,
        results.last.identity!.operationId);
  });

  test('rebuilding a failed recovery copy cannot authorize a second child',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    final sdk = _CountingSdk();
    Future<ImCoordinatedSendResult> retry(String localId) =>
        f.coordinator().send(
            messageService: sdk,
            sdkLocalId: localId,
            conversationId: 'c2c_bob',
            conversationType: ImConversationType.c2c,
            receiver: 'bob',
            groupID: '',
            fallbackMessage: f.message,
            retryOfSdkLocalId: 'local');
    final first = retry('recreated-a');
    await sdk.entered.future;
    final before = (await f.read()).stateVersion;
    await f.rebuildParentRecoveryCopy();
    final after = await f.read();
    expect(after.canRetry, isTrue);
    expect(after.stateVersion, greaterThan(before));
    final second = retry('recreated-b');
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sdk.calls, 1);
    } finally {
      sdk.result.complete(V2TimValueCallback<V2TimMessage>(
          code: 6012, desc: 'failed', data: f.message));
      final results = await Future.wait([first, second]);
      expect(results.first.identity!.operationId,
          results.last.identity!.operationId);
    }
  });

  test('legacy retry child prevents a new-format sibling from dispatching',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    final parent = (await f.read()).main!;
    final legacyId = legacyOutboxRetryOperationId(
        'alice', parent.operationId, parent.stateVersion);
    await f.store.transaction((tx) async {
      expect(
          await tx.insertOutboxIfAbsent(ImOutboxRecord(
              operationId: legacyId,
              ownerUserId: parent.ownerUserId,
              conversationId: parent.conversationId,
              clientCorrelationId: 'legacy-corr',
              messageType: parent.messageType,
              payloadReference: parent.payloadReference,
              payloadHash: parent.payloadHash,
              state: ImOutboxState.prepared,
              createdAtMs: f.now,
              updatedAtMs: f.now,
              retryOfOperationId: parent.operationId,
              retryOfStateVersion: parent.stateVersion)),
          isTrue);
      expect(
          await tx.insertOutboxRecoveryIfAbsent(ImOutboxRecoveryRecord(
              ownerUserId: parent.ownerUserId,
              operationId: legacyId,
              clientCorrelationId: 'legacy-corr',
              conversationId: parent.conversationId,
              messageType: parent.messageType,
              recoveryRevision: 1,
              state: ImOutboxCopyState.copyPrepared,
              payloadReferenceOrCiphertext: parent.payloadReference,
              payloadHash: parent.payloadHash,
              checksum: parent.payloadHash,
              updatedAtMs: f.now)),
          isTrue);
    });
    await f.rebuildParentRecoveryCopy();
    expect(
        (await f.persistence.assessOutboxForDispatch(
                ownerUserId: 'alice',
                operationId: legacyId,
                leaseOwnerId: 'writer',
                fencingToken: f.lease.fencingToken,
                nowMs: f.now))
            .canDispatch,
        isTrue);
    final sdk = _CountingSdk();
    sdk.result.complete(
        V2TimValueCallback<V2TimMessage>(code: 0, desc: '', data: f.message));
    final result = await f.coordinator().send(
        messageService: sdk,
        sdkLocalId: 'new-retry',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message,
        retryOfSdkLocalId: 'local');
    expect(result.identity?.operationId, isNot(legacyId));
    expect(result.dispatchDecision, ImOutboxDispatchDecision.recoveryConflict);
    expect(sdk.calls, 0);
  });

  test('parent copy maintenance after retry preparation preserves dispatch',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    var maintained = false;
    final hooked = _AfterTransactionStore(f.store, (result) async {
      if (!maintained &&
          result is ImOutboxDispatchAssessment &&
          result.main?.retryOfOperationId == 'op' &&
          result.canDispatch) {
        maintained = true;
        await f.rebuildParentRecoveryCopy();
      }
    });
    final sdk = _CountingSdk();
    sdk.result.complete(V2TimValueCallback<V2TimMessage>(
        code: 6012, desc: 'provider rejected', data: f.message));
    final result = await f.coordinator(storeOverride: hooked).send(
        messageService: sdk,
        sdkLocalId: 'recreated',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message,
        retryOfSdkLocalId: 'local');
    expect(maintained, isTrue);
    expect(sdk.calls, 1);
    expect(result.identity?.operationId, isNotNull);
  });

  test('SDK receives business metadata and the authoritative retry identity',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    final parentPayload = (await f.read()).main!.payloadReference;
    final sdk = _CountingSdk();
    sdk.result.complete(V2TimValueCallback<V2TimMessage>(
        code: 6012, desc: 'provider rejected', data: f.message));
    final result = await f.coordinator().send(
        messageService: sdk,
        sdkLocalId: 'recreated',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message,
        retryOfSdkLocalId: 'local',
        businessCloudCustomData: jsonEncode({
          'messageReply': {'id': 'quoted-1'},
          'operationId': 'stale-parent-id',
        }));
    expect(sdk.calls, 1);
    final cloud = jsonDecode(
        sdk.invocations.single.namedArguments[#cloudCustomData] as String);
    expect(cloud['messageReply'], {'id': 'quoted-1'});
    expect(cloud['operationId'], result.identity!.operationId);
    expect(cloud['clientCorrelationId'], result.identity!.clientCorrelationId);
    expect(cloud['payloadFingerprint'], result.identity!.payloadFingerprint);
    final child = await f.persistence.readOutboxResult(
        ownerUserId: 'alice', operationId: result.identity!.operationId);
    expect(child.main!.payloadReference, parentPayload);
    expect(child.main!.payloadHash, result.identity!.payloadFingerprint);
  });

  test('success after retry preparation prevents dispatch and UI replacement',
      () async {
    final f = await _Fixture.create();
    await f.fail();
    var corrected = false, uiAdmissions = 0;
    String? retryOperation;
    final hooked = _AfterTransactionStore(f.store, (result) async {
      if (!corrected &&
          result is ImOutboxDispatchAssessment &&
          result.main?.retryOfOperationId == 'op' &&
          result.canDispatch) {
        corrected = true;
        retryOperation = result.main!.operationId;
        await f.persistence.adoptOutboxProviderSucceeded(
            ownerUserId: 'alice',
            operationId: 'op',
            clientCorrelationId: 'corr',
            conversationId: 'alice|c2c_bob',
            payloadHash: 'hash',
            leaseOwnerId: 'writer',
            fencingToken: f.lease.fencingToken,
            nowMs: f.now,
            serverMsgId: 'confirmed-server');
      }
    });
    final coordinator = f.coordinator(storeOverride: hooked),
        sdk = _CountingSdk();
    final result = await coordinator.send(
        messageService: sdk,
        sdkLocalId: 'recreated',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message,
        retryOfSdkLocalId: 'local',
        onDispatchGranted: () => uiAdmissions++);
    expect(corrected, isTrue);
    expect(sdk.calls, 0);
    expect(uiAdmissions, 0);
    expect(result.outcomeUnknown, isTrue);
    expect((await f.read()).deliveryConfirmed, isTrue);
    final recovered = await f.persistence.assessOutboxForDispatch(
        ownerUserId: 'alice',
        operationId: retryOperation!,
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: f.now);
    expect(recovered.canDispatch, isFalse);
    expect(recovered.decision, ImOutboxDispatchDecision.recoveryConflict);
  });

  test(
      'matching local optimistic and failed SDK objects are not success evidence',
      () async {
    final f = await _Fixture.create();
    await f.prepare();
    await f.persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'attempt',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: f.now);
    final coordinator = f.coordinator();
    for (final state in [
      MessageStatus.V2TIM_MSG_STATUS_SENDING,
      MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL
    ]) {
      f.message.status = state;
      expect(
          await coordinator.adoptProviderHistory([f.message],
              source: ImProviderEvidenceSource.sdkHistory),
          0);
      expect((await f.read()).deliveryConfirmed, isFalse);
    }
    f.message.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    expect(
        await coordinator.adoptProviderHistory([f.message],
            source: ImProviderEvidenceSource.appProjection),
        0);
    expect((await f.read()).deliveryConfirmed, isFalse);
    expect(
        await coordinator.adoptProviderHistory([f.message],
            source: ImProviderEvidenceSource.sdkHistory),
        1);
    expect((await f.read()).deliveryConfirmed, isTrue);
  });

  test(
      'accepted A cannot erase a new identical-text B; old SDK write cannot restore A',
      () async {
    final f = await _Fixture.create();
    final cipher = OutboxPayloadCipher(
        readKey: () async => base64UrlEncode(List.filled(32, 7)),
        writeKey: (_) async {});
    String? sdk = 'same';
    ConversationDraftService service() => ConversationDraftService.forTesting(
        ownerForTest: () => 'alice',
        writeForTest: (_, value) async {
          sdk = value;
          return 0;
        },
        readForTest: (_) async => sdk,
        commitForTest: (_, __) async {},
        draftStoreForTest: f.store,
        draftCipherForTest: cipher);
    final drafts = service();
    var edit = drafts.beginEditing('c2c_bob');
    final a = drafts.recordEdit(edit, 'same')!;
    final acceptanceA = await drafts.submissionContext(a).prepare();
    edit = drafts.recordEdit(a, 'same')!;
    expect(edit.draftId, isNot(a.draftId));
    await drafts.persistDraft(
        conversationID: 'c2c_bob', rawInputText: 'same', expectedEdit: edit);
    await f.prepare(draft: acceptanceA);
    await f.store.transaction(
        (tx) => (tx as ImDraftTransaction).saveDraftHead(acceptanceA));
    final restarted = service();
    final reopened = restarted.beginEditing('c2c_bob');
    expect(
        await restarted.loadDraftText(
            conversationID: 'c2c_bob', expectedEdit: reopened),
        'same');
    final head = await f.store.transaction(
        (tx) => (tx as ImDraftTransaction).findDraftHead('alice', 'c2c_bob'));
    expect(head!['draft_id'], edit.draftId);
    expect(head['accepted_operation_id'], isNull);
  });

  test('a hung SDK draft write does not strand later durable edits', () async {
    final f = await _Fixture.create();
    final cipher = OutboxPayloadCipher(
        readKey: () async => base64UrlEncode(List.filled(32, 7)),
        writeKey: (_) async {});
    final first = Completer<int>(), entered = Completer<void>();
    var sdkCalls = 0;
    final drafts = ConversationDraftService.forTesting(
        ownerForTest: () => 'alice',
        writeForTest: (_, __) async {
          sdkCalls++;
          if (sdkCalls == 1) {
            entered.complete();
            await first.future;
          }
          return 0;
        },
        readForTest: (_) async => null,
        commitForTest: (_, __) async {},
        draftStoreForTest: f.store,
        draftCipherForTest: cipher);
    var edit = drafts.recordEdit(drafts.beginEditing('c2c_bob'), 'A')!;
    final a = drafts.persistDraft(
        conversationID: 'c2c_bob', rawInputText: 'A', expectedEdit: edit);
    await entered.future;
    edit = drafts.recordEdit(edit, 'B')!;
    final b = drafts.persistDraft(
        conversationID: 'c2c_bob', rawInputText: 'B', expectedEdit: edit);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final head = await f.store.transaction(
          (tx) => (tx as ImDraftTransaction).findDraftHead('alice', 'c2c_bob'));
      expect(
          await cipher.reveal(
              ownerUserId: 'alice', value: head!['protected_text'] as String),
          'B');
      expect(sdkCalls, 1);
      expect(
          await drafts.loadDraftText(
              conversationID: 'c2c_bob', expectedEdit: edit),
          'B');
      final restarted = ConversationDraftService.forTesting(
          ownerForTest: () => 'alice',
          writeForTest: (_, __) async => 0,
          readForTest: (_) async => 'A',
          commitForTest: (_, __) async {},
          draftStoreForTest: f.store,
          draftCipherForTest: cipher);
      final reopened = restarted.beginEditing('c2c_bob');
      expect(
          await restarted.loadDraftText(
              conversationID: 'c2c_bob', expectedEdit: reopened),
          'B');
    } finally {
      first.complete(0);
      await Future.wait([a, b]);
    }
    expect(sdkCalls, 2);
  });

  test(
      'one draft cannot be accepted by two operations; transaction rolls back second pair',
      () async {
    final f = await _Fixture.create();
    const draft = ImDraftAcceptance(
        ownerUserId: 'alice',
        conversationId: 'c2c_bob',
        draftId: 'draft-A',
        protectedText: 'ciphertext');
    await f.prepare(draft: draft);
    await expectLater(
        f.prepare(draft: draft, operation: 'op2'), throwsStateError);
    final second = await f.persistence
        .readOutboxResult(ownerUserId: 'alice', operationId: 'op2');
    expect(second.decision, ImOutboxResultDecision.missing);
  });

  test('rejected prepared assessment does not accept or clear a new draft',
      () async {
    final f = await _Fixture.create();
    await f.prepare();
    await f.persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'attempt',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: f.now);
    const draft = ImDraftAcceptance(
        ownerUserId: 'alice',
        conversationId: 'c2c_bob',
        draftId: 'draft-B',
        protectedText: 'ciphertext');
    await f.store
        .transaction((tx) => (tx as ImDraftTransaction).saveDraftHead(draft));
    expect((await f.prepare(draft: draft)).canDispatch, isFalse);
    final head = await f.store.transaction(
        (tx) => (tx as ImDraftTransaction).findDraftHead('alice', 'c2c_bob'));
    expect(head!['accepted_operation_id'], isNull);
  });
}

class _CountingSdk implements MessageService {
  int calls = 0;
  final List<Invocation> invocations = [];
  final entered = Completer<void>();
  final result = Completer<V2TimValueCallback<V2TimMessage>>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendMessage) {
      calls++;
      invocations.add(invocation);
      if (!entered.isCompleted) entered.complete();
      return result.future;
    }
    throw StateError('unexpected SDK ${invocation.memberName}');
  }
}

class _AfterTransactionStore implements ImIngressStore {
  _AfterTransactionStore(this.delegate, this.after);
  final ImIngressStore delegate;
  final Future<void> Function(Object?) after;
  @override
  Future<T> transaction<T>(Future<T> Function(ImIngressTransaction) action,
      {MessagePersistPriority persistPriority =
          MessagePersistPriority.realtime}) async {
    final result =
        await delegate.transaction(action, persistPriority: persistPriority);
    await after(result);
    return result;
  }
}

class _Fixture {
  final store = InMemoryImIngressStore();
  late final persistence = Im05Persistence(store: store);
  late final ImWriterLease lease;
  final now = DateTime.now().millisecondsSinceEpoch;
  late final identity = OutgoingIdentityContract(
      scope: AccountScopedConversationKey(
          ownerUserId: 'alice',
          conversationType: ImConversationType.c2c,
          conversationId: 'c2c_bob'),
      operationId: 'op',
      clientCorrelationId: 'corr',
      messageKind: OutgoingMessageKind.text,
      payloadFingerprint: 'hash',
      createdAtMs: now);
  late final message =
      V2TimMessage.fromJson({'message_risk_type_identified': 0})
        ..id = 'local'
        ..msgID = 'server'
        ..userID = 'bob'
        ..sender = 'alice'
        ..isSelf = true
        ..elemType = 1
        ..cloudCustomData = identity.encodeCloudCustomData();
  static Future<_Fixture> create() async {
    final f = _Fixture();
    f.lease = (await ImWriterLeaseService(store: f.store).acquire(
        ownerUserId: 'alice',
        leaseOwnerId: 'writer',
        nowMs: f.now,
        ttlMs: 600000))!;
    return f;
  }

  ImOutgoingSendCoordinator coordinator({ImIngressStore? storeOverride}) =>
      ImOutgoingSendCoordinator.forTesting(
          leaseContext: () async => ImMessageCoreLeaseContext(
              store: storeOverride ?? store,
              lease: lease,
              ownerUserId: 'alice',
              accountGeneration: SessionIdentityService.instance.generation,
              domainGeneration: 1));
  Future<ImOutboxResultVerdict> read() =>
      persistence.readOutboxResult(ownerUserId: 'alice', operationId: 'op');
  Future<void> rebuildParentRecoveryCopy() async {
    final copy = store.outboxRecoveryCopies['op']!;
    await store.transaction((tx) async {
      store.outboxRecoveryCopies.remove('op');
      expect(await tx.insertOutboxRecoveryIfAbsent(copy), isTrue);
    });
  }

  Future<void> fail() async {
    await prepare();
    final intent = await persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'first',
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: now);
    await persistence.transitionOutbox(
        next: intent.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: now);
    await persistence.adjudicateOutboxSdkResult(
        ownerUserId: 'alice',
        operationId: 'op',
        expectedAttemptId: 'first',
        succeeded: false,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: now,
        resultCode: '6012',
        sdkLocalId: 'local');
  }

  Future<ImOutboxDispatchAssessment> prepare(
          {ImDraftAcceptance? draft, String operation = 'op'}) =>
      persistence.prepareOutbox(
          main: ImOutboxRecord(
              ownerUserId: 'alice',
              operationId: operation,
              conversationId: 'alice|c2c_bob',
              clientCorrelationId: 'corr',
              messageType: 1,
              payloadReference: 'encrypted',
              payloadHash: 'hash',
              sdkMessageId: 'local',
              state: ImOutboxState.prepared,
              createdAtMs: now,
              updatedAtMs: now),
          recoveryCopy: ImOutboxRecoveryRecord(
              ownerUserId: 'alice',
              operationId: operation,
              conversationId: 'alice|c2c_bob',
              clientCorrelationId: 'corr',
              messageType: 1,
              payloadReferenceOrCiphertext: 'encrypted',
              payloadHash: 'hash',
              checksum: 'hash',
              state: ImOutboxCopyState.copyPrepared,
              recoveryRevision: 1,
              updatedAtMs: now),
          draftAcceptance: draft,
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: now);
}
