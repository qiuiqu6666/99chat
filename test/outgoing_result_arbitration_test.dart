import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/account_scoped_conversation_key.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/outgoing_identity_contract.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('acknowledged and completed reject late failure without ambiguous bool',
      () async {
    final f = await _SendFixture.create();
    final success = await f.sdk(true);
    final failure = await f.sdk(false);
    expect(failure.decision, ImOutboxResultDecision.superseded);
    expect(failure.currentState, ImOutboxState.acknowledged);
    expect(failure.stateVersion, success.stateVersion);
    expect(failure.canRetry, isFalse);
    await f.complete();
    final completed = await f.sdk(false);
    expect(completed.currentState, ImOutboxState.completed);
    expect(completed.accepted, isFalse);
    expect(completed.canRetry, isFalse);
    expect(completed.stateVersion, greaterThan(success.stateVersion));
    expect(
        await f.persistence.recordOutboxSdkFailed(
            ownerUserId: 'alice',
            operationId: 'op',
            leaseOwnerId: 'writer',
            fencingToken: f.lease.fencingToken,
            nowMs: 30),
        isFalse);
  });

  test(
      'a durable provider success supersedes an already-created failure verdict',
      () async {
    final f = await _SendFixture.create();
    final view = f.persistence.watchOutboxResult('alice', 'op');
    final failed = await f.sdk(false);
    final delivered = ImCoordinatedSendResult(
        sdkResult: f.callback(6012),
        usedOutbox: true,
        identity: f.identity,
        outboxResult: failed,
        resultView: view);
    expect(delivered.sdkResult.code, 6012);
    expect(await f.provider(), isTrue);
    expect(delivered.currentOutboxResult!.stateVersion,
        greaterThan(failed.stateVersion));
    expect(delivered.sdkResult.code, 0);
    expect(delivered.sdkResult.data!.msgID, 'server');
    expect(delivered.currentOutboxResult!.canRetry, isFalse);
    expect(delivered.outcomeUnknown, isFalse);
    expect(delivered.canCompleteProjection, isTrue);
  });

  test(
      'stale attempt failure is rejected; exact provider success may settle the operation',
      () async {
    final f = await _SendFixture.create();
    final stale = await f.sdk(false, attempt: 'old-attempt');
    expect(stale.decision, ImOutboxResultDecision.staleAttempt);
    expect(stale.currentState, ImOutboxState.sending);
    expect(await f.provider(), isTrue);
    expect((await f.read()).deliveryConfirmed, isTrue);
  });

  test('unknown dispatch callbacks stay unknown until exact provider evidence',
      () async {
    final f = await _SendFixture.create();
    await f.persistence.recordOutcomeUnknown(
        ownerUserId: 'alice',
        operationId: 'op',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 20);
    expect((await f.sdk(true)).currentState, ImOutboxState.outcomeUnknown);
    expect((await f.sdk(false)).currentState, ImOutboxState.outcomeUnknown);
    expect(await f.provider(hash: 'wrong'), isFalse);
    expect((await f.read()).currentState, ImOutboxState.outcomeUnknown);
    expect(await f.provider(), isTrue);
    expect((await f.read()).deliveryConfirmed, isTrue);
  });

  test(
      'rejecting an old event does not erase the current attempt retry verdict',
      () async {
    final f = await _SendFixture.create();
    final failed = await f.sdk(false);
    final stale = await f.sdk(false, attempt: 'old-attempt');
    expect(stale.decision, ImOutboxResultDecision.staleAttempt);
    expect(stale.accepted, isFalse);
    expect(stale.stateVersion, failed.stateVersion);
    expect(stale.canRetry, isTrue);
  });

  test('abandonment does not discard later delivery evidence', () async {
    final f = await _SendFixture.create();
    await f.persistence.recordOutcomeUnknown(
        ownerUserId: 'alice',
        operationId: 'op',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 20);
    await f.persistence.abandonOutcomeUnknown(
        ownerUserId: 'alice',
        operationId: 'op',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 21);
    expect(await f.provider(), isTrue);
    expect((await f.read()).deliveryConfirmed, isTrue);
  });

  test(
      'persistence failure cannot turn valid SDK success into retryable failure',
      () {
    final pending = ImCoordinatedSendResult(
        sdkResult: V2TimValueCallback<V2TimMessage>(code: 0, desc: 'ok'),
        usedOutbox: true,
        localStatePending: true);
    expect(pending.sdkResult.code, 0);
    expect(pending.outcomeUnknown, isFalse);
    expect(pending.canCompleteProjection, isFalse);
    final failure = ImCoordinatedSendResult(
        sdkResult:
            V2TimValueCallback<V2TimMessage>(code: 6012, desc: 'failure'),
        usedOutbox: true,
        localStatePending: true);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.canCompleteProjection, isFalse);
  });

  test('provider-confirmed UI row survives a late explicit failure', () async {
    final global = await _global();
    final message = _message()
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    global.setMessageList('bob', [message], replace: true);
    expect(
        global.applyOutgoingSendResult(
            V2TimValueCallback<V2TimMessage>(
                code: 6012, desc: 'late', data: message),
            'bob',
            'local',
            ConvType.c2c,
            null,
            null),
        isFalse);
    expect(global.rawMessageList('bob')!.single.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(
        global.mayPublishOutgoingSendCompletion(
            'bob',
            'local',
            ImCoordinatedSendResult(
                sdkResult: V2TimValueCallback<V2TimMessage>(
                    code: 6012, desc: 'late', data: message),
                usedOutbox: false)),
        isFalse);
    expect(
        global.markOutgoingSendFailedByIdentity(
            conversationID: 'bob', clientId: 'local'),
        isFalse);
    global.removeMessageList('bob');
  });

  test('a sync msgID alone does not suppress a real sending failure', () async {
    final global = await _global();
    final message = _message()..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    global.setMessageList('bob', [message], replace: true);
    global.applyOutgoingSendResult(
        V2TimValueCallback<V2TimMessage>(
            code: 6012, desc: 'failed', data: message),
        'bob',
        'local',
        ConvType.c2c,
        null,
        null);
    expect(global.rawMessageList('bob')!.single.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL);
    global.removeMessageList('bob');
  });

  test('a revoked row cannot be revived by a late success result', () async {
    final global = await _global();
    final revoked = _message()
      ..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
    global.setMessageList('bob', [revoked], replace: true);
    expect(
        global.applyOutgoingSendResult(
            V2TimValueCallback<V2TimMessage>(
                code: 0, desc: 'late success', data: _message()),
            'bob',
            'local',
            ConvType.c2c,
            null,
            null),
        isFalse);
    expect(global.rawMessageList('bob')!.single.status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(
        global.mayPublishOutgoingSendCompletion(
            'bob',
            'local',
            ImCoordinatedSendResult(
                sdkResult: V2TimValueCallback<V2TimMessage>(
                    code: 0, desc: 'late', data: _message()),
                usedOutbox: false)),
        isFalse);
    global.removeMessageList('bob');
  });

  test('a deleted row and its preview are not recreated by late success',
      () async {
    final global = await _global();
    const key = 'c2c_deleted';
    global.setMessageList(key, [_message()], replace: true);
    global.commitMessageDelta(MessageDelta<V2TimMessage>(
      conversationKey: key,
      eventID: 'delete-result-test',
      kind: MessageDeltaKind.delete,
      source: MessageDeltaSource.sdkRealtime,
      generation: global.messageDeltaGenerationFor(key),
      clearEpoch: global.messageDeltaClearEpochFor(key),
      tombstones: const {'server', 'local'},
    ));
    final result = ImCoordinatedSendResult(
        sdkResult: V2TimValueCallback<V2TimMessage>(
            code: 0, desc: 'late', data: _message()),
        usedOutbox: false);
    expect(
        global.applyOutgoingSendResult(
            result.sdkResult, key, 'local', ConvType.c2c, null, null,
            coordinatedResult: result),
        isFalse);
    expect(
        global.mayPublishOutgoingSendCompletion(key, 'local', result), isFalse);
    expect(global.rawMessageList(key) ?? [], isEmpty);
    global.removeMessageList(key);
  });

  test(
      'provider evidence must match operation, owner, correlation, conversation and payload',
      () async {
    final f = await _SendFixture.create();
    for (final mismatch in [
      'owner',
      'operation',
      'correlation',
      'conversation',
      'payload'
    ]) {
      expect(
          await f.persistence.adoptOutboxProviderSucceeded(
              ownerUserId: mismatch == 'owner' ? 'other' : 'alice',
              operationId: mismatch == 'operation' ? 'other' : 'op',
              clientCorrelationId: mismatch == 'correlation' ? 'other' : 'corr',
              conversationId: mismatch == 'conversation'
                  ? 'alice|c2c_other'
                  : 'alice|c2c_bob',
              payloadHash: mismatch == 'payload' ? 'other' : 'hash',
              leaseOwnerId: 'writer',
              fencingToken: f.lease.fencingToken,
              nowMs: 26,
              serverMsgId: 'server'),
          isFalse,
          reason: mismatch);
      expect((await f.read()).currentState, ImOutboxState.sending);
    }
  });

  test('conflicted verdicts cannot publish success or enable retry', () async {
    final f = await _SendFixture.create();
    final accepted = await f.sdk(true);
    final conflict = ImOutboxResultVerdict(
        decision: ImOutboxResultDecision.identityConflict,
        main: accepted.main,
        recoveryCopy: accepted.recoveryCopy,
        reason: 'test_conflict');
    final result = ImCoordinatedSendResult(
        sdkResult: f.callback(0), usedOutbox: true, outboxResult: conflict);
    expect(conflict.deliveryConfirmed, isFalse);
    expect(conflict.canRetry, isFalse);
    expect(result.outcomeUnknown, isTrue);
    expect(result.sdkResult.code, -2);
  });

  test('an already completed dispatch refusal reports the confirmed result',
      () async {
    final f = await _SendFixture.create();
    await f.sdk(true);
    await f.complete();
    final assessment = await f.persistence.assessOutboxForDispatch(
        ownerUserId: 'alice',
        operationId: 'op',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 28);
    expect(assessment.canDispatch, isFalse);
    final result = ImCoordinatedSendResult(
        sdkResult: f.callback(-1),
        usedOutbox: true,
        outboxResult: ImOutboxResultVerdict.fromDispatchAssessment(assessment));
    expect(result.sdkResult.code, 0);
    expect(result.outcomeUnknown, isFalse);
    expect(result.currentOutboxResult!.canRetry, isFalse);
  });

  test(
      'SQLite result transaction rolls back both copies and version survives reopen',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final dir = await Directory.systemTemp.createTemp('outgoing-verdict-test-');
    final core = MessageCoreStore.instance;
    await core.closeIfOpen();
    await databaseFactory.setDatabasesPath(dir.path);
    try {
      final f = await _SendFixture.create(
          store: ConversationLocalImIngressStore(core: core));
      final before = await f.read();
      await core.runTransaction((db) => db.execute(
          "CREATE TRIGGER fail_result BEFORE UPDATE ON message_outbox "
          "WHEN NEW.state = 'acknowledged' BEGIN SELECT RAISE(ABORT, 'injected write failure'); END"));
      await expectLater(f.sdk(true), throwsA(anything));
      final after = await f.read();
      expect(after.currentState, ImOutboxState.sending);
      expect(after.stateVersion, before.stateVersion);
      expect(after.recoveryCopy!.state, before.recoveryCopy!.state);
      await core.runTransaction((db) => db.execute('DROP TRIGGER fail_result'));
      final committed = await f.sdk(true);
      await core.closeIfOpen();
      final reopened =
          Im05Persistence(store: ConversationLocalImIngressStore(core: core));
      final restored = await reopened.readOutboxResult(
          ownerUserId: 'alice', operationId: 'op');
      expect(restored.deliveryConfirmed, isTrue);
      expect(restored.stateVersion, committed.stateVersion);
      expect(restored.main!.dispatchAttemptId, 'attempt-1');
    } finally {
      await core.closeIfOpen();
      await databaseFactory
          .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
      await databaseFactory.setDatabasesPath(original);
      await dir.delete();
    }
  });
}

V2TimMessage _message() =>
    V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'local'
      ..msgID = 'server'
      ..isSelf = true
      ..sender = 'alice'
      ..elemType = 1
      ..timestamp = 1700000000;

Future<TUIChatGlobalModel> _global() async {
  setupServiceLocator();
  await serviceLocator.unregister<MessageService>();
  serviceLocator.registerSingleton<MessageService>(_LocalMetadataService());
  return serviceLocator<TUIChatGlobalModel>();
}

class _LocalMetadataService implements MessageService {
  @override
  Future<V2TimCallback> setLocalCustomData(
          {required String msgID, required String localCustomData}) async =>
      V2TimCallback(code: 0, desc: '');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _SendFixture {
  _SendFixture(this.store, this.persistence, this.lease);
  final ImIngressStore store;
  final Im05Persistence persistence;
  final ImWriterLease lease;
  static Future<_SendFixture> create({ImIngressStore? store}) async {
    store ??= InMemoryImIngressStore();
    final lease = (await ImWriterLeaseService(store: store).acquire(
        ownerUserId: 'alice',
        leaseOwnerId: 'writer',
        nowMs: 10,
        ttlMs: 100000))!;
    final persistence = Im05Persistence(store: store);
    await persistence.prepareOutbox(
        main: const ImOutboxRecord(
            operationId: 'op',
            ownerUserId: 'alice',
            conversationId: 'alice|c2c_bob',
            clientCorrelationId: 'corr',
            messageType: 1,
            payloadReference: 'encrypted',
            payloadHash: 'hash',
            state: ImOutboxState.prepared,
            createdAtMs: 10,
            updatedAtMs: 10,
            sdkMessageId: 'local'),
        recoveryCopy: const ImOutboxRecoveryRecord(
            ownerUserId: 'alice',
            operationId: 'op',
            clientCorrelationId: 'corr',
            conversationId: 'alice|c2c_bob',
            messageType: 1,
            recoveryRevision: 1,
            state: ImOutboxCopyState.copyPrepared,
            payloadReferenceOrCiphertext: 'encrypted',
            payloadHash: 'hash',
            checksum: 'hash',
            updatedAtMs: 10,
            sdkLocalId: 'local'),
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 10);
    final intent = await persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'attempt-1',
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 11);
    await persistence.transitionOutbox(
        next: intent.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 12);
    return _SendFixture(store, persistence, lease);
  }

  OutgoingIdentityContract get identity => OutgoingIdentityContract(
      scope: AccountScopedConversationKey.tryParse(
          ownerUserId: 'alice',
          conversationType: ImConversationType.c2c,
          conversationId: 'c2c_bob')!,
      operationId: 'op',
      clientCorrelationId: 'corr',
      messageKind: OutgoingMessageKind.text,
      payloadFingerprint: 'hash',
      createdAtMs: 10,
      sdkLocalId: 'local');
  V2TimValueCallback<V2TimMessage> callback(int code) =>
      V2TimValueCallback<V2TimMessage>(
          code: code, desc: 'sdk result', data: _message());
  Future<ImOutboxResultVerdict> sdk(bool success,
          {String attempt = 'attempt-1'}) =>
      persistence.adjudicateOutboxSdkResult(
          ownerUserId: 'alice',
          operationId: 'op',
          expectedAttemptId: attempt,
          succeeded: success,
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: 25,
          sdkLocalId: 'local',
          serverMsgId: 'server',
          resultCode: success ? '0' : '6012');
  Future<bool> provider({String hash = 'hash'}) =>
      persistence.adoptOutboxProviderSucceeded(
          ownerUserId: 'alice',
          operationId: 'op',
          clientCorrelationId: 'corr',
          conversationId: 'alice|c2c_bob',
          payloadHash: hash,
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: 26,
          sdkLocalId: 'local',
          serverMsgId: 'server');
  Future<bool> complete() => persistence.completeOutboxProjection(
      ownerUserId: 'alice',
      operationId: 'op',
      leaseOwnerId: 'writer',
      fencingToken: lease.fencingToken,
      nowMs: 27);
  Future<ImOutboxResultVerdict> read() =>
      persistence.readOutboxResult(ownerUserId: 'alice', operationId: 'op');
}
