import 'dart:async';
import 'dart:collection';

/// Bounded, serialized diagnostics I/O. Timeout observers must not start a
/// second writer while the original file operation still owns its lane.
class RecoveryLogBuffer {
  RecoveryLogBuffer({
    required this.write,
    this.capacity = 200,
    this.batchSize = 20,
    this.flushDelay = const Duration(milliseconds: 500),
    this.retryDelay = const Duration(seconds: 5),
  });

  final Future<void> Function(List<String>) write;
  final int capacity;
  final int batchSize;
  final Duration flushDelay;
  final Duration retryDelay;
  final Queue<String> _pending = Queue<String>();
  Future<void>? _writing;
  Timer? _timer;
  bool _disposed = false;
  int droppedCount = 0;
  int failureCount = 0;

  int get pendingCount => _pending.length;
  bool get writing => _writing != null;

  void add(String event) {
    if (_disposed) return;
    _pending.addLast(event);
    _trim();
    _schedule(flushDelay);
  }

  void _trim() {
    while (_pending.length > capacity) {
      _pending.removeFirst();
      droppedCount++;
    }
  }

  void _schedule(Duration delay) {
    if (_disposed || _writing != null || _timer != null || _pending.isEmpty) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Flush one bounded batch, sharing any active write. Errors are recorded
  /// locally; the next attempt is delayed instead of spinning on a full disk.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_writing != null) return _writing!;
    if (_pending.isEmpty || _disposed) return Future<void>.value();
    final batch = <String>[];
    while (_pending.isNotEmpty && batch.length < batchSize) {
      batch.add(_pending.removeFirst());
    }
    var failed = false;
    late final Future<void> task;
    task = Future<void>.sync(() => write(batch)).catchError((Object _) {
      failed = true;
      failureCount++;
      // Prefer recent events if storage has been unavailable for a long time.
      for (final event in batch.reversed) {
        _pending.addFirst(event);
      }
      _trim();
    }).whenComplete(() {
      if (identical(_writing, task)) _writing = null;
      _schedule(failed ? retryDelay : flushDelay);
    });
    _writing = task;
    return task;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
