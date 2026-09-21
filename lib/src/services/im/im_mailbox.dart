import 'dart:async';
import 'dart:collection';

import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';

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

/// Per-conversation logical queues plus a bounded worker pool.
///
/// Ordering is still per mailbox key (conversation + history lane). Worker
/// count does not grow with conversation count: idle queues are recycled.
class ImMailboxRouter {
  ImMailboxRouter({
    required ImMailboxEventHandler handler,
    this.maxConcurrentWorkers = 8,
    this.handlerTimeout = const Duration(seconds: 30),
  }) : _handler = handler {
    if (maxConcurrentWorkers <= 0) {
      throw ArgumentError.value(
        maxConcurrentWorkers,
        'maxConcurrentWorkers',
        'must be positive',
      );
    }
    if (handlerTimeout <= Duration.zero) {
      throw ArgumentError.value(
        handlerTimeout,
        'handlerTimeout',
        'must be positive',
      );
    }
  }

  final ImMailboxEventHandler _handler;
  final int maxConcurrentWorkers;
  final Duration handlerTimeout;
  final Map<String, _ImMailbox> _mailboxes = <String, _ImMailbox>{};
  final LinkedHashSet<String> _ready = LinkedHashSet<String>();
  final Set<String> _busy = <String>{};
  final Map<String, int> _inflightStartedMs = <String, int>{};
  int _evictionCount = 0;
  int _limitHitCount = 0;

  /// Compat for existing diagnostics: worker cap, not logical-mailbox cap.
  int get maxActiveMailboxes => maxConcurrentWorkers;

  int get activeMailboxCount => _mailboxes.length;

  int get readyMailboxCount => _ready.length;

  int get idleMailboxCount {
    var idle = 0;
    _mailboxes.forEach((key, mailbox) {
      if (!_busy.contains(key) && mailbox.isIdle) idle++;
    });
    return idle;
  }

  int get activeWorkerCount => _busy.length;

  int get evictionCount => _evictionCount;

  int get limitHitCount => _limitHitCount;

  int get pendingEventCount => _mailboxes.values.fold<int>(
        0,
        (total, mailbox) => total + mailbox.pendingEventCount,
      );

  int get inFlightEventCount => activeWorkerCount;

  int get oldestInflightMs {
    if (_inflightStartedMs.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var oldest = now;
    for (final started in _inflightStartedMs.values) {
      if (started < oldest) oldest = started;
    }
    return now - oldest;
  }

  ImMailboxSnapshot snapshot() => ImMailboxSnapshot(
        logicalCount: activeMailboxCount,
        readyCount: readyMailboxCount,
        idleCount: idleMailboxCount,
        activeWorkerCount: activeWorkerCount,
        maxWorkers: maxConcurrentWorkers,
        pendingEventCount: pendingEventCount,
        oldestInflightMs: oldestInflightMs,
        limitHitCount: _limitHitCount,
        evictionCount: _evictionCount,
      );

  Future<void> dispatch<T>(
    EventEnvelope<T> event, {
    ImIngressLane lane = ImIngressLane.realtime,
  }) {
    final key = _mailboxKey(event, lane);
    final mailbox = _mailboxes.putIfAbsent(
      key,
      () => _ImMailbox(
        handler: _handler,
        handlerTimeout: handlerTimeout,
      ),
    );
    final future = mailbox.enqueue(event, lane: lane);
    _markReady(key);
    return future;
  }

  Future<void> drain() async {
    while (_mailboxes.isNotEmpty || _busy.isNotEmpty || _ready.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  String _mailboxKey(EventEnvelope<dynamic> event, ImIngressLane lane) {
    final scope = event.scope?.canonicalConversationId ?? '@account';
    final laneSuffix = lane == ImIngressLane.history ? '|history' : '';
    return '${event.ownerUserId}|${event.eventNamespace}|$scope$laneSuffix';
  }

  void _markReady(String key) {
    if (_busy.contains(key) || _ready.contains(key)) return;
    final mailbox = _mailboxes[key];
    if (mailbox == null || mailbox.isIdle) return;
    _ready.add(key);
    _trySchedule();
  }

  void _trySchedule() {
    while (_busy.length < maxConcurrentWorkers) {
      final key = _dequeueReady();
      if (key == null) return;
      final mailbox = _mailboxes[key];
      if (mailbox == null || mailbox.isIdle) {
        _evictIfIdle(key, mailbox);
        continue;
      }
      _busy.add(key);
      _inflightStartedMs[key] = DateTime.now().millisecondsSinceEpoch;
      unawaited(_run(key, mailbox));
    }
  }

  String? _dequeueReady() {
    String? fifo;
    final stale = <String>[];
    for (final key in _ready) {
      final mailbox = _mailboxes[key];
      if (mailbox == null || mailbox.isIdle) {
        stale.add(key);
        continue;
      }
      if (mailbox.hasPriorityWork) {
        _ready.remove(key);
        _ready.removeAll(stale);
        return key;
      }
      fifo ??= key;
    }
    if (stale.isNotEmpty) _ready.removeAll(stale);
    if (fifo == null) return null;
    _ready.remove(fifo);
    return fifo;
  }

  Future<void> _run(String key, _ImMailbox mailbox) async {
    try {
      await mailbox.pumpUntilEmpty();
    } finally {
      _busy.remove(key);
      _inflightStartedMs.remove(key);
      if (mailbox.hasPending) {
        _ready.add(key);
      } else {
        _evictIfIdle(key, mailbox);
      }
      _trySchedule();
    }
  }

  void _evictIfIdle(String key, _ImMailbox? mailbox) {
    if (mailbox == null) {
      _mailboxes.remove(key);
      return;
    }
    if (mailbox.isIdle &&
        !_busy.contains(key) &&
        identical(_mailboxes[key], mailbox)) {
      _mailboxes.remove(key);
      _ready.remove(key);
      _evictionCount++;
    }
  }
}

class _ImMailbox {
  _ImMailbox({
    required this.handler,
    required this.handlerTimeout,
  });

  final ImMailboxEventHandler handler;
  final Duration handlerTimeout;
  final Map<ImIngressLane, Queue<_QueuedEvent>> _queues = {
    ImIngressLane.urgent: Queue<_QueuedEvent>(),
    ImIngressLane.realtime: Queue<_QueuedEvent>(),
    ImIngressLane.history: Queue<_QueuedEvent>(),
    ImIngressLane.background: Queue<_QueuedEvent>(),
  };

  int get pendingEventCount => _queues.values.fold<int>(
        0,
        (total, queue) => total + queue.length,
      );

  bool get hasPending => pendingEventCount > 0;

  bool get hasPriorityWork =>
      _queues[ImIngressLane.urgent]!.isNotEmpty ||
      _queues[ImIngressLane.realtime]!.isNotEmpty;

  bool get isIdle => !hasPending;

  Future<void> enqueue<T>(
    EventEnvelope<T> event, {
    required ImIngressLane lane,
  }) {
    final completer = Completer<void>();
    _queues[lane]!.add(_QueuedEvent(event: event, completer: completer));
    return completer.future;
  }

  Future<void> pumpUntilEmpty() async {
    while (true) {
      final next = _takeNext();
      if (next == null) return;
      try {
        await Future<void>.sync(() => handler(next.event)).timeout(
          handlerTimeout,
        );
        if (!next.completer.isCompleted) {
          next.completer.complete();
        }
      } catch (error, stack) {
        if (!next.completer.isCompleted) {
          next.completer.completeError(error, stack);
        }
      }
    }
  }

  _QueuedEvent? _takeNext() {
    for (final lane in ImIngressLane.values) {
      final queue = _queues[lane]!;
      if (queue.isNotEmpty) return queue.removeFirst();
    }
    return null;
  }
}

class _QueuedEvent {
  const _QueuedEvent({required this.event, required this.completer});

  final EventEnvelope<dynamic> event;
  final Completer<void> completer;
}
