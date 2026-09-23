import 'dart:async';
import 'dart:convert';

import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_effect_scheduler.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

/// Admission labels, never separate authority lanes within a conversation.
enum ImIngressLane { urgent, realtime, history, background }

typedef ImMailboxEventHandler = FutureOr<void> Function(
    EventEnvelope<dynamic> event);

class ImMailboxSnapshot {
  const ImMailboxSnapshot({
    required this.logicalCount,
    required this.readyCount,
    required this.idleCount,
    required this.activeWorkerCount,
    required this.maxWorkers,
    required this.pendingEventCount,
    required this.oldestInflightMs,
    required this.limitHitCount,
    required this.evictionCount,
  });

  final int logicalCount;
  final int readyCount;
  final int idleCount;
  final int activeWorkerCount;
  final int maxWorkers;
  final int pendingEventCount;
  final int oldestInflightMs;
  final int limitHitCount;
  final int evictionCount;
}

/// Host adapter to the runtime scheduler. All sources and ingress labels for
/// one account/conversation share FIFO order. SDK payloads stay in the host
/// executor; no SDK object is admitted into a pure RuntimeDocument/reducer.
///
/// In-flight I/O owns its slot until actual completion. A timeout only notifies
/// the caller; it cannot release a writer or overlap the next conversation turn.
class ImMailboxRouter {
  ImMailboxRouter({
    required ImMailboxEventHandler handler,
    this.maxConcurrentWorkers = 8,
    this.maxQueuedEvents = 4096,
    this.handlerTimeout = const Duration(seconds: 30),
  })  : _handler = handler,
        _scheduler = RuntimeEffectScheduler(
            maxConcurrent: maxConcurrentWorkers, maxQueued: maxQueuedEvents) {
    if (handlerTimeout <= Duration.zero) {
      throw ArgumentError.value(
          handlerTimeout, 'handlerTimeout', 'must be positive');
    }
  }

  final ImMailboxEventHandler _handler;
  final RuntimeEffectScheduler _scheduler;
  final int maxConcurrentWorkers;
  final int maxQueuedEvents;
  final Duration handlerTimeout;
  int _limitHitCount = 0;
  int _waitingAdmissions = 0;
  Future<void> _admissionTail = Future<void>.value();
  Completer<void> _completion = Completer<void>();

  int get maxActiveMailboxes => maxConcurrentWorkers;
  int get activeMailboxCount => _scheduler.logicalCount;
  int get readyMailboxCount => _scheduler.readyCount;
  int get idleMailboxCount => 0;
  int get activeWorkerCount => _scheduler.runningCount;
  int get evictionCount => _scheduler.evictionCount;
  int get limitHitCount => _limitHitCount;
  int get pendingEventCount => _scheduler.queuedCount + _waitingAdmissions;
  int get inFlightEventCount => activeWorkerCount;
  int get oldestInflightMs => _scheduler.oldestInflightMs;

  ImMailboxSnapshot snapshot() => ImMailboxSnapshot(
        logicalCount: activeMailboxCount,
        readyCount: readyMailboxCount,
        idleCount: idleMailboxCount,
        activeWorkerCount: activeWorkerCount,
        maxWorkers: maxConcurrentWorkers,
        pendingEventCount: pendingEventCount,
        oldestInflightMs: oldestInflightMs,
        limitHitCount: limitHitCount,
        evictionCount: evictionCount,
      );

  Future<void> dispatch<T>(
    EventEnvelope<T> event, {
    ImIngressLane lane = ImIngressLane.realtime,
  }) {
    final result = Completer<void>();
    _waitingAdmissions++;
    // Backpressure is lossless. Rejected SDK callbacks otherwise fall into a
    // finite retry cache. One admission tail preserves producer order while
    // work in already admitted conversations continues on bounded workers.
    _admissionTail = _admissionTail.then((_) async {
      try {
        if (_scheduler.queuedCount >= maxQueuedEvents) _limitHitCount++;
        while (_scheduler.queuedCount >= maxQueuedEvents) {
          await _completion.future;
        }
        final key = jsonEncode([
          event.ownerUserId,
          event.scope?.canonicalConversationId,
        ]);
        final work = _scheduler.schedule(
          lane: key,
          isCurrent: () =>
              true, // Host handler checks account/domain/clear fences.
          execute: () async {
            final deadline = Timer(handlerTimeout, () {
              if (!result.isCompleted) {
                result.completeError(TimeoutException(
                    'Ingress handler still running; conversation remains occupied',
                    handlerTimeout));
              }
            });
            try {
              await Future<void>.sync(() => _handler(event));
              return RuntimeDocument({});
            } finally {
              deadline.cancel();
            }
          },
        );
        unawaited(work.then((outcome) {
          final completed = _completion;
          _completion = Completer<void>();
          completed.complete();
          if (result.isCompleted) return;
          if (outcome.status == RuntimeEffectStatus.completed) {
            result.complete();
          } else {
            result.completeError(
                outcome.error ??
                    StateError(
                        'Message runtime admission ${outcome.status.name}'),
                outcome.stackTrace);
          }
        }));
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        _waitingAdmissions--;
      }
    });
    return result.future;
  }

  Future<void> drain() async {
    while (true) {
      final admissions = _admissionTail;
      await admissions;
      await _scheduler.drain();
      if (identical(admissions, _admissionTail)) return;
    }
  }
}
