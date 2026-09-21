import 'dart:async';

/// 统一网络任务优先级。数值越小越优先。
enum NetworkTaskPriority {
  userInitiated,
  startupCritical,
  backgroundSync,
  speculativeWarm
}

/// 轻量网络调度器：限制并发，并合并相同 key 的并发请求。
///
/// 它只负责调度 HTTP Future，不缓存已完成结果；调用方仍负责 freshness。
class NetworkTaskScheduler {
  NetworkTaskScheduler._();

  static final NetworkTaskScheduler instance = NetworkTaskScheduler._();

  static const int _maxConcurrent = 4;
  int _running = 0;
  int _sequence = 0;
  final Map<String, Future<Object?>> _inFlight = <String, Future<Object?>>{};
  final List<_QueuedNetworkTask<Object?>> _queue =
      <_QueuedNetworkTask<Object?>>[];

  Future<T> run<T>({
    required String dedupeKey,
    required Future<T> Function() task,
    NetworkTaskPriority priority = NetworkTaskPriority.backgroundSync,
  }) {
    final existing = _inFlight[dedupeKey];
    if (existing != null) return existing.then((value) => value as T);

    final completer = Completer<T>();
    final queued = _QueuedNetworkTask<T>(
      priority: priority,
      sequence: _sequence++,
      task: task,
      completer: completer,
    );
    _inFlight[dedupeKey] = completer.future;
    _queue.add(queued as _QueuedNetworkTask<Object?>);
    _pump();
    return completer.future.whenComplete(() {
      if (identical(_inFlight[dedupeKey], completer.future)) {
        _inFlight.remove(dedupeKey);
      }
    });
  }

  void _pump() {
    while (_running < _maxConcurrent && _queue.isNotEmpty) {
      _queue.sort((a, b) {
        final byPriority = a.priority.index.compareTo(b.priority.index);
        return byPriority != 0 ? byPriority : a.sequence.compareTo(b.sequence);
      });
      final item = _queue.removeAt(0);
      _running++;
      item.run().whenComplete(() {
        _running--;
        _pump();
      });
    }
  }
}

class _QueuedNetworkTask<T> {
  _QueuedNetworkTask({
    required this.priority,
    required this.sequence,
    required this.task,
    required this.completer,
  });

  final NetworkTaskPriority priority;
  final int sequence;
  final Future<T> Function() task;
  final Completer<T> completer;

  Future<void> run() async {
    try {
      completer.complete(await task());
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
  }
}
