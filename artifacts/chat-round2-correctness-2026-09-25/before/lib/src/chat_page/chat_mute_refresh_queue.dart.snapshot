import 'dart:async';

/// Serializes mute snapshots without losing changes received during a fetch.
/// A newer request invalidates the old snapshot before it can be published.
class ChatMuteRefreshQueue {
  int _generation = 0;
  int _revision = 0;
  Future<void>? _running;
  Future<void> Function(bool Function() isCurrent)? _pending;

  Future<void> refresh(
    Future<void> Function(bool Function() isCurrent) action,
  ) {
    _revision++;
    _pending = action;
    if (_running != null) return _running!;
    final generation = _generation;
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(() async {
      try {
        while (generation == _generation && _pending != null) {
          final next = _pending!;
          _pending = null;
          final revision = _revision;
          await next(() => generation == _generation && revision == _revision);
        }
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        if (identical(_running, completion.future)) _running = null;
      }
    }());
    return completion.future;
  }

  void cancel() {
    _generation++;
    _pending = null;
    _running = null;
  }
}
