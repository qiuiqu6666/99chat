import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_recovery_worker.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

void main() {
  setUp(InboxRecoveryCoordinator.instance.resetForTest);
  tearDown(InboxRecoveryCoordinator.instance.resetForTest);

  test('1000 pending with 5 due only reads the due set', () async {
    final store = InMemoryImIngressStore();
    final gateway = DurableIngressGateway(store: store);
    for (var i = 0; i < 1000; i++) {
      await gateway.append(_draft('p$i', ImEventKind.notification));
    }
    await store.transaction((tx) async {
      for (var i = 0; i < 1000; i++) {
        await tx.updateInboxRetry(
          ownerUserId: 'alice',
          eventNamespace: 'chat',
          eventId: 'p$i',
          retryCount: 1,
          nextRetryAtMs: i < 5 ? 10 : 9 * 1000 * 1000,
          lastErrorClass: InboxErrorClass.network.name,
        );
      }
    });
    final due = await gateway.listForRecovery(
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      nowMs: 1000,
      limit: 40,
    );
    final counts = await gateway.countForRecovery(
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      nowMs: 1000,
    );
    expect(due.map((row) => row.event.eventId), ['p0', 'p1', 'p2', 'p3', 'p4']);
    expect(counts.dueCount, 5);
    expect(counts.pendingCount, 1000);
  });

  test('empty inbox recovery is a due peek, not a full scan', () async {
    final store = InMemoryImIngressStore();
    final gateway = DurableIngressGateway(store: store);
    final due = await gateway.listForRecovery(
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      nowMs: 1000,
      limit: 40,
    );
    expect(due, isEmpty);
    final counts = await gateway.countForRecovery(
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      nowMs: 1000,
    );
    expect(counts.pendingCount, 0);
    expect(counts.dueCount, 0);
  });

  test('permanent errors leave abandoned and are not due again', () async {
    final store = InMemoryImIngressStore();
    final gateway = DurableIngressGateway(store: store);
    final leases = ImWriterLeaseService(store: store);
    final lease = await leases.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: 'due-test',
      nowMs: 0,
      ttlMs: 10000,
    );
    await gateway.append(_draft('bad', ImEventKind.notification));
    await store.transaction((tx) async {
      await tx.updateInboxRetry(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'bad',
        retryCount: 0,
        nextRetryAtMs: 0,
        lastErrorClass: '',
      );
      final current = await tx.findInbox(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'bad',
      );
      await tx.updateInboxRetry(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'bad',
        retryCount: current!.retryCount,
        nextRetryAtMs: 0,
        lastErrorClass: '',
      );
    });
    final router = ImMailboxRouter(handler: (_) async {});
    final worker = ImRecoveryWorker(
      gateway: gateway,
      router: router,
      lease: lease!,
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      jitterMs: 0,
      loadPayload: (_) async => const ImRecoveryPayload.unavailable(),
    );
    await worker.run(nowMs: 100, limit: 20);
    final first = await store.transaction(
      (tx) => tx.findInbox(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'bad',
      ),
    );
    expect(first!.status, isNot(ImInboxStatus.completed));
    expect(first.nextRetryAtMs, greaterThan(100));

    await gateway.scheduleRetry(
      record: first,
      errorClass: InboxErrorClass.permanent,
      nowMs: 200,
      jitterMs: 0,
    );
    final abandoned = await store.transaction(
      (tx) => tx.findInbox(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'bad',
      ),
    );
    expect(abandoned!.status, ImInboxStatus.abandoned);
    final due = await gateway.listForRecovery(
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      nowMs: 200 + 60 * 1000,
      limit: 20,
    );
    expect(due, isEmpty);
  });

  test('db retry update cannot mark a row completed', () async {
    final store = InMemoryImIngressStore();
    final gateway = DurableIngressGateway(store: store);
    await gateway.append(_draft('keep', ImEventKind.notification));
    final ok = await store.transaction((tx) {
      return tx.updateInboxRetry(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'keep',
        retryCount: 1,
        nextRetryAtMs: 5000,
        lastErrorClass: InboxErrorClass.network.name,
        nextStatus: ImInboxStatus.completed,
      );
    });
    expect(ok, isFalse);
    final row = await store.transaction(
      (tx) => tx.findInbox(
        ownerUserId: 'alice',
        eventNamespace: 'chat',
        eventId: 'keep',
      ),
    );
    expect(row!.status, ImInboxStatus.prepared);
    expect(row.nextRetryAtMs, 0);
  });

  test('retry backoff follows 2s 5s 15s 30s 60s', () {
    expect(InboxRecoveryPolicy.nextRetryDelayMs(0, jitterMs: 0), 2000);
    expect(InboxRecoveryPolicy.nextRetryDelayMs(1, jitterMs: 0), 5000);
    expect(InboxRecoveryPolicy.nextRetryDelayMs(2, jitterMs: 0), 15000);
    expect(InboxRecoveryPolicy.nextRetryDelayMs(3, jitterMs: 0), 30000);
    expect(InboxRecoveryPolicy.nextRetryDelayMs(4, jitterMs: 0), 60000);
    expect(InboxRecoveryPolicy.nextRetryDelayMs(8, jitterMs: 0), 60000);
  });
}

ImIngressDraft<String> _draft(String eventId, ImEventKind kind) {
  return ImIngressDraft<String>(
    eventId: eventId,
    eventNamespace: 'chat',
    kind: kind,
    ownerUserId: 'alice',
    accountGeneration: 1,
    domainGeneration: 1,
    clearEpoch: 0,
    source: ImEventSource.sdkListener,
    authority: ImEventAuthority.provider,
    observedAtMs: 1,
    payloadHash: eventId,
    recoveryMode: kind == ImEventKind.notification
        ? ImRecoveryMode.commandArguments
        : ImRecoveryMode.sdkOverlapReplay,
    recoveryRef: eventId,
    payload: eventId,
  );
}
