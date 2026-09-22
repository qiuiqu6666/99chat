import 'dart:async';
import 'dart:collection';

import 'runtime_protocol.dart';

enum RuntimeEffectStatus { completed, failed, obsolete, overloaded }

class RuntimeEffectOutcome {
  const RuntimeEffectOutcome(
      {required this.status,
      required this.dispatched,
      this.value,
      this.error,
      this.stackTrace});
  final RuntimeEffectStatus status;
  // Obsolete dispatched writes may have succeeded remotely. Keep the actual
  // response for the durable adapter; never turn this into permission to retry.
  final bool dispatched;
  final RuntimeDocument? value;
  final Object? error;
  final StackTrace? stackTrace;
}

class _RuntimeEffectJob {
  _RuntimeEffectJob(this.lane, this.identity, this.isCurrent, this.execute);
  final String lane;
  final Object? identity;
  final bool Function() isCurrent;
  final Future<RuntimeDocument> Function() execute;
  final Completer<RuntimeEffectOutcome> completer = Completer();
}

/// Pure scheduling policy with an explicit executor port. The shadow account
/// runtime deliberately never constructs or invokes this executor. Each lane
/// is FIFO, lanes rotate fairly, and external work never occupies an actor.
class RuntimeEffectScheduler {
  RuntimeEffectScheduler(
      {this.maxConcurrent = 4,
      this.maxQueued = 256,
      this.completionsPerTurn = 32}) {
    if (maxConcurrent < 1 || maxQueued < 1 || completionsPerTurn < 1) {
      throw ArgumentError('Invalid capacity');
    }
  }
  final int maxConcurrent;
  final int maxQueued;
  final int completionsPerTurn;
  final Map<String, Queue<_RuntimeEffectJob>> _queues = {};
  final Queue<String> _ready = Queue();
  final Set<String> _activeLanes = {};
  final Map<(String, Object), Future<RuntimeEffectOutcome>> _coalesced = {};
  int _queued = 0;
  bool _closed = false;
  bool _yielding = false;
  int _completedThisTurn = 0;
  int _evictions = 0;
  final Map<String, Stopwatch> _runningWatches = {};
  Completer<void>? _idle;

  int get queuedCount => _queued;
  int get runningCount => _activeLanes.length;
  int get logicalCount => _queues.length;
  int get readyCount => _ready.length;
  int get evictionCount => _evictions;
  int get oldestInflightMs => _runningWatches.values.fold(
      0,
      (oldest, watch) => watch.elapsedMilliseconds > oldest
          ? watch.elapsedMilliseconds
          : oldest);

  /// Includes actual in-flight completion, even after a host stops waiting.
  Future<void> drain() => _idle?.future ?? Future<void>.value();

  void _completeIdle() {
    if (_queued != 0 || _activeLanes.isNotEmpty) return;
    _idle?.complete();
    _idle = null;
  }

  /// Coalescing is opt-in for equivalent reads/progress only. Callers must use
  /// a structured identity containing source, cursor, scope and dependencies;
  /// message facts and remote writes must not be given a coalescing identity.
  Future<RuntimeEffectOutcome> schedule(
      {required String lane,
      Object? coalescingIdentity,
      required bool Function() isCurrent,
      required Future<RuntimeDocument> Function() execute}) {
    if (lane.trim().isEmpty) throw ArgumentError.value(lane);
    if (_closed || !isCurrent()) {
      return Future.value(const RuntimeEffectOutcome(
          status: RuntimeEffectStatus.obsolete, dispatched: false));
    }
    final identity = coalescingIdentity;
    if (identity != null) {
      final existing = _coalesced[(lane, identity)];
      if (existing != null) return existing;
    }
    if (_queued >= maxQueued) {
      return Future.value(const RuntimeEffectOutcome(
          status: RuntimeEffectStatus.overloaded, dispatched: false));
    }
    _idle ??= Completer<void>();
    final job = _RuntimeEffectJob(lane, identity, isCurrent, execute);
    final queue = _queues.putIfAbsent(lane, Queue.new);
    final wasEmpty = queue.isEmpty;
    queue.add(job);
    _queued++;
    if (identity != null) _coalesced[(lane, identity)] = job.completer.future;
    if (wasEmpty && !_activeLanes.contains(lane)) _ready.add(lane);
    _pump();
    return job.completer.future;
  }

  void _pump() {
    if (_yielding) return;
    while (
        !_closed && _activeLanes.length < maxConcurrent && _ready.isNotEmpty) {
      final lane = _ready.removeFirst();
      final queue = _queues[lane]!;
      final job = queue.removeFirst();
      _queued--;
      _activeLanes.add(lane);
      _runningWatches[lane] = Stopwatch()..start();
      _run(job);
    }
  }

  Future<void> _run(_RuntimeEffectJob job) async {
    var dispatched = false;
    RuntimeDocument? value;
    Object? failure;
    StackTrace? stackTrace;
    try {
      if (!_closed && job.isCurrent()) {
        dispatched = true;
        value = await job.execute();
      }
    } catch (error, stack) {
      failure = error;
      stackTrace = stack;
    }
    bool current;
    try {
      current = !_closed && job.isCurrent();
    } catch (error, stack) {
      current = false;
      failure ??= error;
      stackTrace ??= stack;
    }
    _finish(
        job,
        RuntimeEffectOutcome(
            status: !current
                ? RuntimeEffectStatus.obsolete
                : failure != null
                    ? RuntimeEffectStatus.failed
                    : RuntimeEffectStatus.completed,
            dispatched: dispatched,
            value: value,
            error: failure,
            stackTrace: stackTrace));
    _activeLanes.remove(job.lane);
    _runningWatches.remove(job.lane);
    final queue = _queues[job.lane];
    if (queue != null && queue.isNotEmpty) {
      _ready.add(job.lane);
    } else {
      if (_queues.remove(job.lane) != null) _evictions++;
    }
    _completeIdle();
    // Yield fast completion bursts to frame/timer events.
    if (++_completedThisTurn >= completionsPerTurn && !_yielding) {
      _yielding = true;
      Timer.run(() {
        _yielding = false;
        _completedThisTurn = 0;
        _pump();
      });
    } else {
      _pump();
    }
  }

  void _finish(_RuntimeEffectJob job, RuntimeEffectOutcome outcome) {
    final identity = job.identity;
    if (identity != null &&
        identical(_coalesced[(job.lane, identity)], job.completer.future)) {
      _coalesced.remove((job.lane, identity));
    }
    job.completer.complete(outcome);
  }

  /// In-flight work keeps its slot until the actual adapter completes. Closing
  /// a view/runtime must not pretend to cancel an SDK request or release capacity.
  void close() {
    if (_closed) return;
    _closed = true;
    _ready.clear();
    for (final lane in _queues.keys.toList()) {
      final queue = _queues[lane]!;
      while (queue.isNotEmpty) {
        _queued--;
        _finish(
            queue.removeFirst(),
            const RuntimeEffectOutcome(
                status: RuntimeEffectStatus.obsolete, dispatched: false));
      }
      if (!_activeLanes.contains(lane)) {
        _queues.remove(lane);
        _evictions++;
      }
    }
    _completeIdle();
  }
}
