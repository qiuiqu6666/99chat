import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_activity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_outbox_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
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

  for (final type in [
    MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
    MessageElemType.V2TIM_ELEM_TYPE_VIDEO
  ]) {
    for (final group in [false, true]) {
      test(
          'recovery during live media send preserves success: type=$type group=$group',
          () async {
        final f = await _Fixture.create(type: type, group: group);
        final sdk = _PendingSdk();
        final pending = f.send(sdk);
        await sdk.entered.future;
        ImOutboxResultVerdict? during;
        try {
          // The same scan runs at reconnect and after Prepared commits.
          await f.recovery.recoverOnceForTesting();
          await f.recovery.recoverOnceForTesting();
          during = await f.read();
        } finally {
          sdk.result.complete(f.success);
        }
        final result = await pending;
        expect(during.currentState, ImOutboxState.sending);
        expect(result.sdkResult.code, 0);
        expect(result.outcomeUnknown, isFalse);
        expect((await f.read()).deliveryConfirmed, isTrue);
        expect(sdk.calls, 1);
        expect(
            OutgoingSendActivity.instance.isActive(f.context, 'op'), isFalse);
      });
    }
  }

  test('an interrupted dispatch without a live sender remains unknown',
      () async {
    final f = await _Fixture.create();
    final dispatch = await f.persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'interrupted',
        leaseOwnerId: 'writer',
        fencingToken: f.context.lease.fencingToken,
        nowMs: f.now);
    await f.persistence.transitionOutbox(
        next: dispatch.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: f.context.lease.fencingToken,
        nowMs: f.now);
    await f.recovery.recoverOnceForTesting();
    final result = await f.read();
    expect(result.currentState, ImOutboxState.outcomeUnknown);
    expect(result.canRetry, isFalse);
    expect(result.main!.resultCode, 'recovered_after_dispatch_intent');
  });

  test('normal send is protected from Prepared through result persistence',
      () async {
    final f = await _Fixture.create(
        type: MessageElemType.V2TIM_ELEM_TYPE_TEXT, prepare: false);
    final seen = <ImOutboxState>{};
    final hooked = _AfterTransactionStore(f.store, (value) async {
      final row = value is ImOutboxDispatchAssessment
          ? value.main
          : value is ImOutboxRecord
              ? value
              : value is ImOutboxResultVerdict
                  ? value.main
                  : null;
      if (row == null) return;
      expect(OutgoingSendActivity.instance.isActive(f.context, row.operationId),
          isTrue);
      seen.add(row.state);
      await f.recovery.recoverOnceForTesting();
      final current = await f.persistence
          .readOutboxResult(ownerUserId: 'alice', operationId: row.operationId);
      expect(current.currentState, row.state);
    });
    final sdk = _PendingSdk()..result.complete(f.success);
    final result = await ImOutgoingSendCoordinator.forTesting(
        leaseContext: () async => ImMessageCoreLeaseContext(
            store: hooked,
            lease: f.context.lease,
            ownerUserId: 'alice',
            accountGeneration: f.context.accountGeneration,
            domainGeneration: 1)).send(
        messageService: sdk,
        sdkLocalId: 'local',
        conversationId: 'c2c_bob',
        conversationType: ImConversationType.c2c,
        receiver: 'bob',
        groupID: '',
        fallbackMessage: f.message);
    expect(result.sdkResult.code, 0);
    expect(sdk.calls, 1);
    expect(
        seen,
        containsAll([
          ImOutboxState.prepared,
          ImOutboxState.dispatchIntent,
          ImOutboxState.sending,
          ImOutboxState.acknowledged
        ]));
    expect(
        OutgoingSendActivity.instance
            .isActive(f.context, result.identity!.operationId),
        isFalse);
  });

  test('a rejected competing attempt cannot unpin the live SDK send', () async {
    final f = await _Fixture.create();
    final sdk = _PendingSdk();
    final pending = f.send(sdk);
    await sdk.entered.future;
    try {
      final duplicate = await f.send(sdk);
      expect(duplicate.outcomeUnknown, isTrue);
      await f.recovery.recoverOnceForTesting();
      expect((await f.read()).currentState, ImOutboxState.sending);
    } finally {
      sdk.result.complete(f.success);
    }
    expect((await pending).sdkResult.code, 0);
    expect(sdk.calls, 1);
  });

  test(
      'SDK errors release activity and retain unknown delivery without resending',
      () async {
    final f = await _Fixture.create();
    final sdk = _PendingSdk();
    final pending = f.send(sdk);
    await sdk.entered.future;
    sdk.result.completeError(StateError('transport disappeared'));
    expect((await pending).outcomeUnknown, isTrue);
    expect(OutgoingSendActivity.instance.isActive(f.context, 'op'), isFalse);
    await f.recovery.recoverOnceForTesting();
    expect((await f.read()).currentState, ImOutboxState.outcomeUnknown);
    await f.send(sdk);
    expect(sdk.calls, 1);
  });

  test('activity is scoped by account and domain and releases on exceptions',
      () async {
    final f = await _Fixture.create();
    final activity = OutgoingSendActivity();
    await expectLater(
        activity.track(f.context, 'op', () async {
          expect(activity.isActive(f.context, 'op'), isTrue);
          expect(activity.isActive(f.context, 'other-op'), isFalse);
          for (final change in ['owner', 'account', 'domain']) {
            final other = ImMessageCoreLeaseContext(
                store: f.store,
                lease: f.context.lease,
                ownerUserId: change == 'owner' ? 'other' : 'alice',
                accountGeneration:
                    f.context.accountGeneration + (change == 'account' ? 1 : 0),
                domainGeneration: change == 'domain' ? 2 : 1);
            expect(activity.isActive(other, 'op'), isFalse);
          }
          expect(OutgoingSendActivity().isActive(f.context, 'op'), isFalse);
          throw StateError('aborted before SDK');
        }),
        throwsStateError);
    expect(activity.isActive(f.context, 'op'), isFalse);
  });
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

class _PendingSdk implements MessageService {
  int calls = 0;
  final entered = Completer<void>();
  final result = Completer<V2TimValueCallback<V2TimMessage>>();
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendMessage) {
      calls++;
      if (!entered.isCompleted) entered.complete();
      return result.future;
    }
    throw StateError('unexpected SDK call ${invocation.memberName}');
  }
}

class _Fixture {
  final store = InMemoryImIngressStore();
  late final persistence = Im05Persistence(store: store);
  late final ImMessageCoreLeaseContext context;
  late final OutgoingOutboxRecoveryService recovery;
  late final V2TimMessage message;
  final int now = DateTime.now().millisecondsSinceEpoch;
  final bool group;
  _Fixture(this.group);
  String get conversationId => group ? 'group_team' : 'c2c_bob';
  ImConversationType get conversationType =>
      group ? ImConversationType.group : ImConversationType.c2c;

  static Future<_Fixture> create(
      {int type = MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      bool group = false,
      bool prepare = true}) async {
    final f = _Fixture(group);
    final lease = (await ImWriterLeaseService(store: f.store).acquire(
        ownerUserId: 'alice',
        leaseOwnerId: 'writer',
        nowMs: f.now,
        ttlMs: 600000))!;
    f.context = ImMessageCoreLeaseContext(
        store: f.store,
        lease: lease,
        ownerUserId: 'alice',
        accountGeneration: SessionIdentityService.instance.generation,
        domainGeneration: 1);
    f.recovery = OutgoingOutboxRecoveryService.forTesting(
        leaseContext: () async => f.context);
    f.message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'local'
      ..msgID = 'server'
      ..userID = group ? null : 'bob'
      ..groupID = group ? 'team' : null
      ..sender = 'alice'
      ..isSelf = true
      ..elemType = type
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    if (prepare) {
      await f.persistence.prepareOutbox(
          main: ImOutboxRecord(
              ownerUserId: 'alice',
              operationId: 'op',
              conversationId: 'alice|${f.conversationId}',
              clientCorrelationId: 'corr',
              messageType: type,
              payloadReference: 'encrypted',
              payloadHash: 'hash',
              sdkMessageId: 'local',
              state: ImOutboxState.prepared,
              createdAtMs: f.now,
              updatedAtMs: f.now),
          recoveryCopy: ImOutboxRecoveryRecord(
              ownerUserId: 'alice',
              operationId: 'op',
              conversationId: 'alice|${f.conversationId}',
              clientCorrelationId: 'corr',
              messageType: type,
              payloadReferenceOrCiphertext: 'encrypted',
              payloadHash: 'hash',
              checksum: 'hash',
              state: ImOutboxCopyState.copyPrepared,
              recoveryRevision: 1,
              updatedAtMs: f.now),
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: f.now);
    }
    return f;
  }

  V2TimValueCallback<V2TimMessage> get success =>
      V2TimValueCallback<V2TimMessage>(code: 0, desc: 'ok', data: message);
  Future<ImOutboxResultVerdict> read() =>
      persistence.readOutboxResult(ownerUserId: 'alice', operationId: 'op');
  Future<ImCoordinatedSendResult> send(_PendingSdk sdk) =>
      ImOutgoingSendCoordinator.forTesting(leaseContext: () async => context)
          .send(
              messageService: sdk,
              sdkLocalId: 'local',
              conversationId: conversationId,
              conversationType: conversationType,
              receiver: group ? '' : 'bob',
              groupID: group ? 'team' : '',
              fallbackMessage: message,
              recoverPreparedOutbox: true,
              operationIdOverride: 'op',
              clientCorrelationIdOverride: 'corr');
}
