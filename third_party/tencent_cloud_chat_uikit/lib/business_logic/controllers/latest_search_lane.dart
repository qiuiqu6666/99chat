import 'dart:async';

/// One actual SDK future and only the latest waiting request per source.
/// A UI timeout must not free the slot: SDK futures cannot be cancelled.
class LatestSearchLane<T> {
  bool _running = false;
  _SearchJob<T>? _pending;

  Future<T?> run(Future<T> Function() read, bool Function() isCurrent) {
    final job = _SearchJob(read, isCurrent);
    cancelPending();
    if (_running) {
      _pending = job;
    } else {
      _start(job);
    }
    return job.result.future;
  }

  void cancelPending() {
    _pending?.result.complete(null);
    _pending = null;
  }

  void _start(_SearchJob<T> job) async {
    if (!job.isCurrent()) {
      job.result.complete(null);
      return;
    }
    _running = true;
    try {
      job.result.complete(await job.read());
    } catch (error, stack) {
      job.result.completeError(error, stack);
    } finally {
      _running = false;
      final next = _pending;
      _pending = null;
      if (next != null) _start(next);
    }
  }
}

class _SearchJob<T> {
  _SearchJob(this.read, this.isCurrent);
  final Future<T> Function() read;
  final bool Function() isCurrent;
  final result = Completer<T?>();
}
