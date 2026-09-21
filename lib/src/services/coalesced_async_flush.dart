import 'dart:async';

/// Awaiters in one microtask window share a durable flush. A caller arriving after
/// a flush starts joins the next window, so it cannot acknowledge an older write.
class CoalescedAsyncFlush {
  CoalescedAsyncFlush(this.flush);

  final Future<void> Function() flush;
  Future<void> _tail = Future<void>.value();
  Completer<void>? _scheduled;

  Future<void> request() {
    final scheduled = _scheduled;
    if (scheduled != null) return scheduled.future;
    final done = Completer<void>();
    _scheduled = done;
    scheduleMicrotask(() {
      final task = _tail.then((_) {
        // Keep accepting waiters while an earlier write holds this batch.
        // Clear only at the actual storage boundary, not when it is queued.
        _scheduled = null;
        return flush();
      });
      _tail = task.then<void>((_) {
        done.complete();
      }, onError: (Object error, StackTrace stack) {
        done.completeError(error, stack);
      });
    });
    return done.future;
  }
}
