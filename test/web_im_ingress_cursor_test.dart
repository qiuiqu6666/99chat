@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/event_envelope.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store_platform_web.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_draft_submission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cursor finds records after 1000 unrelated object-store entries',
      () async {
    final owner = 'web_cursor_${DateTime.now().microsecondsSinceEpoch}';
    final store = WebImIngressStore();
    await store.transaction<void>((transaction) async {
      final drafts = transaction as ImDraftTransaction;
      for (var index = 0; index < 1001; index++) {
        await drafts.saveDraftHead(ImDraftAcceptance(
          ownerUserId: owner,
          conversationId: 'draft_${index.toString().padLeft(4, '0')}',
          draftId: 'draft-$index',
          protectedText: 'ciphertext',
        ));
      }
      await transaction.insertInbox(ImInboxRecord(
        event: EventEnvelope<void>(
          eventId: 'target-inbox',
          eventNamespace: 'chat',
          kind: ImEventKind.realtimeMessage,
          ownerUserId: owner,
          accountGeneration: 1,
          domainGeneration: 1,
          clearEpoch: 0,
          accountIngressSequence: 1,
          scopeIngressSequence: 0,
          source: ImEventSource.sdkListener,
          authority: ImEventAuthority.provider,
          observedAtMs: 100,
        ),
        payloadHash: 'hash',
        recoveryMode: ImRecoveryMode.sdkBoundaryReplay,
        recoveryRef: 'target-inbox',
        status: ImInboxStatus.prepared,
      ));
      await transaction.insertOutboxIfAbsent(ImOutboxRecord(
        operationId: 'target-outbox-$owner',
        ownerUserId: owner,
        conversationId: 'c2c_bob',
        clientCorrelationId: 'target-correlation',
        messageType: 1,
        payloadReference: '{}',
        payloadHash: 'hash',
        state: ImOutboxState.prepared,
        createdAtMs: 100,
        updatedAtMs: 100,
        sdkMessageId: 'target-local-id',
      ));
      await transaction.insertOutboxIfAbsent(ImOutboxRecord(
        operationId: 'retry-child-$owner',
        ownerUserId: owner,
        conversationId: 'c2c_bob',
        clientCorrelationId: 'retry-correlation',
        messageType: 1,
        payloadReference: '{}',
        state: ImOutboxState.retryable,
        createdAtMs: 101,
        updatedAtMs: 101,
        retryOfOperationId: 'target-outbox-$owner',
      ));
    });

    await store.transaction<void>((transaction) async {
      final due = await transaction.listInboxForRecovery(
        ownerUserId: owner,
        accountGeneration: 1,
        domainGeneration: 1,
        nowMs: 200,
        processingTimeoutMs: 50,
        limit: 10,
      );
      expect(due.map((row) => row.event.eventId), <String>['target-inbox']);
      final counts = await transaction.countInboxRecovery(
        ownerUserId: owner,
        accountGeneration: 1,
        domainGeneration: 1,
        nowMs: 200,
        processingTimeoutMs: 50,
      );
      expect(counts.pendingCount, 1);
      expect(counts.dueCount, 1);

      final outboxes = await transaction.listOutboxesForRecovery(
        ownerUserId: owner,
        states: const <ImOutboxState>[ImOutboxState.prepared],
        limit: 10,
        afterOperationId: '',
      );
      expect(outboxes.map((row) => row.operationId),
          <String>['target-outbox-$owner']);
      final byLocalId = await transaction.findOutboxBySdkLocalId(
        ownerUserId: owner,
        conversationId: 'c2c_bob',
        sdkLocalId: 'target-local-id',
      );
      expect(byLocalId?.operationId, 'target-outbox-$owner');
      expect(
          await transaction.hasOtherRetryChild(
            ownerUserId: owner,
            parentOperationId: 'target-outbox-$owner',
            excludingOperationId: 'target-outbox-$owner',
          ),
          isTrue);
    });
  });
}
