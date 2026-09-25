import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/outgoing_identity_contract.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/account_scoped_conversation_key.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';

const directory = String.fromEnvironment('CRASH_DIR');
const scenario = String.fromEnvironment('CRASH_CASE');
const mode = String.fromEnvironment('CRASH_MODE');
const nonce = String.fromEnvironment('CRASH_NONCE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('isolated process $scenario $mode', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(directory);
    final core = MessageCoreStore.instance;
    final store = ConversationLocalImIngressStore(core: core);
    final cipher = OutboxPayloadCipher(
        readKey: () async => base64Encode(List.filled(32, 7)),
        writeKey: (_) async {});
    final scope = AccountScopedConversationKey(
        ownerUserId: 'alice',
        conversationType: ImConversationType.c2c,
        conversationId: 'c2c_bob');
    final identity = OutgoingIdentityContract(
        scope: scope,
        operationId: 'op-$scenario',
        clientCorrelationId: 'corr-$scenario',
        messageKind: OutgoingMessageKind.text,
        payloadFingerprint: 'fixture-payload-fingerprint',
        createdAtMs: 10);
    final persistence = Im05Persistence(store: store);
    if (mode == 'write') {
      final lease = (await ImWriterLeaseService(store: store).acquire(
          ownerUserId: 'alice',
          leaseOwnerId: 'writer',
          nowMs: 10,
          ttlMs: 100000))!;
      final protected =
          (await cipher.protect(ownerUserId: 'alice', plaintext: 'A'))!;
      final draft = ImDraftAcceptance(
          ownerUserId: 'alice',
          conversationId: 'c2c_bob',
          draftId: 'draft-A',
          protectedText: protected.value);
      await store
          .transaction((tx) => (tx as ImDraftTransaction).saveDraftHead(draft));
      final payload = (await cipher.protect(
          ownerUserId: 'alice',
          plaintext: jsonEncode({
            'schemaVersion': 1,
            if (scenario == 'prepared_resume') ...{
              'sdkLocalId': 'local',
              'conversationId': 'c2c_bob',
              'receiver': 'bob',
              'groupID': '',
              'priority': 0,
            },
            'message': {
              if (scenario == 'prepared_resume')
                ..._message().toJson()
              else
                'textElem': {'text': 'A'},
              'groupAtUserList': ['mentioned-user']
            },
            'businessCloudCustomData': {
              'messageReply': {'messageID': 'quoted-message'},
              'mentionOccurrences': ['mentioned-user']
            }
          })))!;
      final preparePersistence = scenario == 'before_commit'
          ? Im05Persistence(store: _PauseAfterAction(store))
          : persistence;
      await preparePersistence.prepareOutbox(
          main: ImOutboxRecord(
              operationId: identity.operationId,
              ownerUserId: 'alice',
              conversationId: scope.storageKey,
              clientCorrelationId: identity.clientCorrelationId,
              messageType: 1,
              payloadReference: payload.value,
              payloadHash: identity.payloadFingerprint,
              state: ImOutboxState.prepared,
              createdAtMs: 10,
              updatedAtMs: 10,
              sdkMessageId: 'local'),
          recoveryCopy: ImOutboxRecoveryRecord(
              ownerUserId: 'alice',
              operationId: identity.operationId,
              clientCorrelationId: identity.clientCorrelationId,
              conversationId: scope.storageKey,
              messageType: 1,
              recoveryRevision: 1,
              state: ImOutboxCopyState.copyPrepared,
              payloadReferenceOrCiphertext: payload.value,
              payloadHash: identity.payloadFingerprint,
              checksum: identity.payloadFingerprint,
              updatedAtMs: 10,
              sdkLocalId: 'local'),
          draftAcceptance: draft,
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: 10);
      if (scenario != 'prepared' && scenario != 'prepared_resume') {
        final intent = await persistence.recordDispatchIntent(
            ownerUserId: 'alice',
            operationId: identity.operationId,
            dispatchAttemptId: 'attempt',
            leaseOwnerId: 'writer',
            fencingToken: lease.fencingToken,
            nowMs: 11);
        if (scenario == 'sdk_success_commit_failure') {
          await persistence.transitionOutbox(
              next: intent.main!.copyWith(state: ImOutboxState.sending),
              expectedState: ImOutboxState.dispatchIntent,
              leaseOwnerId: 'writer',
              fencingToken: lease.fencingToken,
              nowMs: 12);
          // A separate serialized provider fixture stands in for a later SDK query.
          // This proves process independence, not real Tencent delivery.
          await File('$directory/provider.json').writeAsString(
              jsonEncode({
                'sender': 'alice',
                'isSelf': true,
                'status': 2,
                'msgID': 'server-confirmed',
                'cloudCustomData': identity.encodeCloudCustomData()
              }),
              flush: true);
          final db =
              await openDatabase('$directory/${MessageCoreStore.dbName}');
          await db.execute('PRAGMA foreign_keys=ON');
          await db.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
          await db.execute(
              'CREATE TABLE child(id INTEGER REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED)');
          await db.execute(
              "CREATE TRIGGER fail_commit AFTER UPDATE ON message_outbox WHEN NEW.state='acknowledged' BEGIN INSERT INTO child VALUES(9); END");
          await expectLater(
              persistence.adjudicateOutboxSdkResult(
                  ownerUserId: 'alice',
                  operationId: identity.operationId,
                  expectedAttemptId: 'attempt',
                  succeeded: true,
                  leaseOwnerId: 'writer',
                  fencingToken: lease.fencingToken,
                  nowMs: 20,
                  sdkLocalId: 'local',
                  serverMsgId: 'server-confirmed',
                  resultCode: '0'),
              throwsA(anything));
        }
      }
      await pauseForKill();
    } else {
      final draftService = ConversationDraftService.forTesting(
          ownerForTest: () => 'alice',
          writeForTest: (_, __) async => 0,
          readForTest: (_) async => 'A',
          commitForTest: (_, __) async {},
          draftStoreForTest: store,
          draftCipherForTest: cipher);
      final edit = draftService.beginEditing('c2c_bob');
      final restoredDraft = await draftService.loadDraftText(
          conversationID: 'c2c_bob', expectedEdit: edit);
      final result = await persistence.readOutboxResult(
          ownerUserId: 'alice', operationId: identity.operationId);
      if (scenario == 'before_commit') {
        expect(result.decision, ImOutboxResultDecision.missing);
        expect(restoredDraft, 'A');
      } else {
        expect(restoredDraft, isNull);
        final recoveredPayload = jsonDecode((await cipher.reveal(
            ownerUserId: 'alice', value: result.main!.payloadReference))!);
        expect(
            recoveredPayload['businessCloudCustomData']['messageReply']
                ['messageID'],
            'quoted-message');
        expect(
            recoveredPayload['message']['groupAtUserList'], ['mentioned-user']);
        final assessment = await persistence.recoverOutbox(
            ownerUserId: 'alice', operationId: identity.operationId);
        expect(assessment.canDispatch,
            scenario == 'prepared' || scenario == 'prepared_resume');
        if (scenario != 'prepared' && scenario != 'prepared_resume')
          expect(assessment.requiresOutcomeQuery, isTrue);
        if (scenario == 'prepared_resume') {
          await ApiClient.instance.saveAuthenticatedUserIdIfCurrent(
              expectedToken: null, userId: 'alice');
          final now = DateTime.now().millisecondsSinceEpoch;
          final lease = (await ImWriterLeaseService(store: store).acquire(
              ownerUserId: 'alice',
              leaseOwnerId: 'restarted-writer',
              nowMs: now,
              ttlMs: 600000))!;
          final coordinator = ImOutgoingSendCoordinator.forTesting(
              leaseContext: () async => ImMessageCoreLeaseContext(
                  store: store,
                  lease: lease,
                  ownerUserId: 'alice',
                  accountGeneration: SessionIdentityService.instance.generation,
                  domainGeneration: 1));
          final sdk = _RecoverySdk();
          Future<ImCoordinatedSendResult> resume() => coordinator.send(
              messageService: sdk,
              sdkLocalId: 'local',
              conversationId: 'c2c_bob',
              conversationType: ImConversationType.c2c,
              receiver: 'bob',
              groupID: '',
              fallbackMessage: _message(),
              recoverPreparedOutbox: true,
              operationIdOverride: identity.operationId,
              clientCorrelationIdOverride: identity.clientCorrelationId);
          final sent = await resume();
          expect(sent.identity?.operationId, identity.operationId);
          expect(sent.sdkResult.code, 0);
          await resume();
          expect(sdk.sends, 1);
          expect(
              (await persistence.readOutboxResult(
                      ownerUserId: 'alice', operationId: identity.operationId))
                  .deliveryConfirmed,
              isTrue);
        }
        if (scenario == 'sdk_success_commit_failure') {
          expect(result.currentState, ImOutboxState.sending);
          final provider =
              jsonDecode(await File('$directory/provider.json').readAsString());
          expect(provider['status'], 2);
          expect(provider['sender'], 'alice');
          final fromCloud = OutgoingIdentityContract.fromCloudCustomData(
              provider['cloudCustomData'],
              scope: scope)!;
          await core
              .runTransaction((db) => db.execute('DROP TRIGGER fail_commit'));
          expect(
              await persistence.adoptOutboxProviderSucceeded(
                  ownerUserId: 'alice',
                  operationId: fromCloud.operationId,
                  clientCorrelationId: fromCloud.clientCorrelationId,
                  conversationId: scope.storageKey,
                  payloadHash: fromCloud.payloadFingerprint,
                  leaseOwnerId: 'writer',
                  fencingToken: 1,
                  nowMs: 30,
                  serverMsgId: provider['msgID']),
              isTrue);
          expect(
              (await persistence.readOutboxResult(
                      ownerUserId: 'alice', operationId: identity.operationId))
                  .deliveryConfirmed,
              isTrue);
        }
      }
      await File('$directory/verified.json').writeAsString(
          jsonEncode({
            'scenario': scenario,
            'newProcessPid': pid,
            'draftRecovered': restoredDraft,
            'durableStateBeforeRepair': result.currentState?.name,
            'canRetry': result.canRetry,
            'recoveryPerformedSdkSends': scenario == 'prepared_resume' ? 1 : 0,
            'providerEvidence': scenario == 'prepared_resume'
                ? 'synthetic SDK callback in restarted process'
                : 'serialized synthetic fixture'
          }),
          flush: true);
      await core.closeIfOpen();
    }
  }, skip: directory.isEmpty, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> pauseForKill() async {
  await File('$directory/ready.json').writeAsString(
      jsonEncode({'pid': pid, 'nonce': nonce, 'scenario': scenario}),
      flush: true);
  await Completer<void>().future;
}

V2TimMessage _message() =>
    (V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'local'
      ..msgID = 'server-prepared-resume'
      ..sender = 'alice'
      ..userID = 'bob'
      ..isSelf = true
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'A')
      ..groupAtUserList = ['mentioned-user']);

class _RecoverySdk implements MessageService {
  int sends = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendMessage) {
      sends++;
      return Future<V2TimValueCallback<V2TimMessage>>.value(
          V2TimValueCallback<V2TimMessage>(
              code: 0, desc: '', data: _message()));
    }
    throw StateError('unexpected SDK ${invocation.memberName}');
  }
}

class _PauseAfterAction implements ImIngressStore {
  _PauseAfterAction(this.inner);
  final ImIngressStore inner;
  @override
  Future<T> transaction<T>(Future<T> Function(ImIngressTransaction) action,
          {MessagePersistPriority persistPriority =
              MessagePersistPriority.realtime}) =>
      inner.transaction((tx) async {
        final result = await action(tx);
        await pauseForKill();
        return result;
      }, persistPriority: persistPriority);
}
