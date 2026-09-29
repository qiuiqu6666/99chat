import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

class ImRecoveryPayload {
  const ImRecoveryPayload._({required this.canRecover, this.payload});

  const ImRecoveryPayload.recovered(Object? payload)
      : this._(canRecover: true, payload: payload);

  const ImRecoveryPayload.unavailable() : this._(canRecover: false);

  final bool canRecover;
  final Object? payload;
}

/// Marker used when an ephemeral UI event has no durable payload to recover.
/// It is intentionally distinct from null so command payload loss cannot be
/// mistaken for a successfully recovered event.
class ImRecoveredEphemeralUiEvent {
  const ImRecoveredEphemeralUiEvent();
}

typedef ImRecoveryPayloadLoader = Future<ImRecoveryPayload> Function(
  ImInboxRecord record,
);

class ImRecoveryRunResult {
  const ImRecoveryRunResult({
    required this.scanned,
    required this.dispatched,
    required this.deferred,
    this.dueCount = 0,
    this.pendingCount = 0,
    this.oldestPendingAgeMs = 0,
    this.retryCount = 0,
    this.queueWaitUs = 0,
    this.cpuUs = 0,
    this.dbUs = 0,
    this.nextRetryAtMs,
    this.moreDue = false,
  });

  final int scanned;
  final int dispatched;
  final int deferred;
  final int dueCount;
  final int pendingCount;
  final int oldestPendingAgeMs;
  final int retryCount;
  final int queueWaitUs;
  final int cpuUs;
  final int dbUs;
  final int? nextRetryAtMs;
  final bool moreDue;

  InboxRecoveryBatchResult toBatchResult() => InboxRecoveryBatchResult(
        scanned: scanned,
        dispatched: dispatched,
        deferred: deferred,
        dueCount: dueCount,
        pendingCount: pendingCount,
        oldestPendingAgeMs: oldestPendingAgeMs,
        retryCount: retryCount,
        queueWaitUs: queueWaitUs,
        cpuUs: cpuUs,
        dbUs: dbUs,
        nextRetryAtMs: nextRetryAtMs,
        moreDue: moreDue,
      );
}

/// Replays durable ingress rows after the unique MessageCore owner is ready.
///
/// The worker never invents a message body. For formal SDK messages the
/// payload loader must read the SDK local store or a bounded overlap window.
/// Only ephemeral UI rows may be dispatched without a payload. Other rows must
/// still provide a recoverable command or formal SDK message, even when their
/// metadata/projection transition was already committed.
class ImRecoveryWorker {
  ImRecoveryWorker({
    required this.gateway,
    required this.router,
    required this.lease,
    required this.ownerUserId,
    required this.accountGeneration,
    required this.domainGeneration,
    required this.loadPayload,
    this.processingTimeoutMs = 30000,
    this.jitterMs,
  });

  final DurableIngressGateway gateway;
  final ImMailboxRouter router;
  final ImWriterLease lease;
  final String ownerUserId;
  final int accountGeneration;
  final int domainGeneration;
  final ImRecoveryPayloadLoader loadPayload;
  final int processingTimeoutMs;
  final int? jitterMs;

  Future<ImRecoveryRunResult> run({
    int nowMs = 0,
    int limit = InboxRecoveryPolicy.defaultBatchSize,
    ReconnectRecoveryPhase phase = ReconnectRecoveryPhase.inboxHighPriority,
    String? activeConversationId,
    bool allowBackground = true,
    MessagePersistPriority persistPriority =
        MessagePersistPriority.backgroundRepair,
  }) async {
    final cpu = Stopwatch()..start();
    final effectiveNow =
        nowMs > 0 ? nowMs : DateTime.now().millisecondsSinceEpoch;
    final db = Stopwatch()..start();
    final records = await gateway.listForRecovery(
      ownerUserId: ownerUserId,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
      nowMs: effectiveNow,
      processingTimeoutMs: processingTimeoutMs,
      limit: limit,
      persistPriority: persistPriority,
    );
    db.stop();
    InboxRecoveryCounts? counts;
    if (records.isNotEmpty) {
      counts = await gateway.countForRecovery(
        ownerUserId: ownerUserId,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        nowMs: effectiveNow,
        processingTimeoutMs: processingTimeoutMs,
        persistPriority: persistPriority,
      );
    }
    var dispatched = 0;
    var deferred = 0;
    var retryUpdates = 0;
    var moreDue = records.length >= limit;
    int? nextRetryAtMs;
    for (final record in records) {
      if (phase == ReconnectRecoveryPhase.visibleGap) {
        final conversationId = record.event.scope?.canonicalConversationId ?? '';
        if (activeConversationId != null &&
            conversationId != activeConversationId &&
            !InboxRecoveryPolicy.isHighPriority(record.recoveryPriority)) {
          moreDue = true;
          continue;
        }
      }
      if (InboxRecoveryPolicy.isBackgroundPriority(record.recoveryPriority) &&
          !allowBackground) {
        deferred++;
        moreDue = true;
        break;
      }
      ImRecoveryPayload recovery;
      Object? loadError;
      if (record.status == ImInboxStatus.projectionPublished) {
        recovery = const ImRecoveryPayload.recovered(null);
      } else if (record.recoveryMode == ImRecoveryMode.ephemeralUi) {
        recovery = const ImRecoveryPayload.recovered(
          ImRecoveredEphemeralUiEvent(),
        );
      } else {
        try {
          recovery = await loadPayload(record);
        } catch (error) {
          loadError = error;
          recovery = const ImRecoveryPayload.unavailable();
        }
      }
      if (!recovery.canRecover) {
        deferred++;
        final scheduled = await _scheduleFailure(
          record,
          errorClass: loadError == null
              ? InboxErrorClass.unknown
              : InboxRecoveryPolicy.classify(loadError),
          nowMs: effectiveNow,
        );
        if (scheduled != null) {
          retryUpdates++;
          nextRetryAtMs = _minRetry(nextRetryAtMs, scheduled);
        }
        continue;
      }
      final event = _withPayload(record.event, recovery.payload);
      try {
        await router.dispatch(event, lane: _laneFor(event));
        dispatched++;
      } catch (error) {
        deferred++;
        final scheduled = await _scheduleFailure(
          record,
          errorClass: InboxRecoveryPolicy.classify(error),
          nowMs: effectiveNow,
        );
        if (scheduled != null) {
          retryUpdates++;
          nextRetryAtMs = _minRetry(nextRetryAtMs, scheduled);
        }
      }
    }
    cpu.stop();
    return ImRecoveryRunResult(
      scanned: records.length,
      dispatched: dispatched,
      deferred: deferred,
      dueCount: counts?.dueCount ?? records.length,
      pendingCount: counts?.pendingCount ?? records.length,
      oldestPendingAgeMs: counts?.oldestPendingAgeMs ?? 0,
      retryCount: retryUpdates,
      cpuUs: cpu.elapsedMicroseconds,
      dbUs: db.elapsedMicroseconds,
      nextRetryAtMs: nextRetryAtMs,
      moreDue: moreDue,
    );
  }

  Future<int?> _scheduleFailure(
    ImInboxRecord record, {
    required InboxErrorClass errorClass,
    required int nowMs,
  }) async {
    try {
      final ok = await gateway.scheduleRetry(
        record: record,
        errorClass: errorClass,
        nowMs: nowMs,
        jitterMs: jitterMs,
      );
      if (!ok) return null;
      if (InboxRecoveryPolicy.isPermanent(
        errorClass: errorClass,
        retryCount: record.retryCount + 1,
      )) {
        return null;
      }
      return InboxRecoveryPolicy.nextRetryAtMs(
        nowMs: nowMs,
        retryCount: record.retryCount,
        jitterMs: jitterMs,
      );
    } catch (_) {
      return null;
    }
  }
}

int? _minRetry(int? current, int next) {
  if (current == null || next < current) return next;
  return current;
}

EventEnvelope<dynamic> _withPayload(
  EventEnvelope<void> event,
  Object? payload,
) {
  return EventEnvelope<dynamic>(
    eventId: event.eventId,
    eventNamespace: event.eventNamespace,
    kind: event.kind,
    scope: event.scope,
    ownerUserId: event.ownerUserId,
    accountGeneration: event.accountGeneration,
    domainGeneration: event.domainGeneration,
    viewInstanceId: event.viewInstanceId,
    surfaceId: event.surfaceId,
    viewSessionGeneration: event.viewSessionGeneration,
    historyRequestGeneration: event.historyRequestGeneration,
    sendOperationGeneration: event.sendOperationGeneration,
    clearEpoch: event.clearEpoch,
    accountIngressSequence: event.accountIngressSequence,
    scopeIngressSequence: event.scopeIngressSequence,
    providerSequence: event.providerSequence,
    sourceRevision: event.sourceRevision,
    membershipRevision: event.membershipRevision,
    operationId: event.operationId,
    source: event.source,
    authority: event.authority,
    proof: event.proof,
    cursor: event.cursor,
    observedAtMs: event.observedAtMs,
    payload: payload,
  );
}

ImIngressLane _laneFor(EventEnvelope<dynamic> event) {
  if (event.kind == ImEventKind.messageMutation) {
    return ImIngressLane.urgent;
  }
  if (event.kind == ImEventKind.historyPage) {
    return ImIngressLane.history;
  }
  return ImIngressLane.realtime;
}
