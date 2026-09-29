import 'dart:async';

/// Coalesces REST/UI and realtime removal notifications. Only the small visible
/// update is awaited by navigation; destructive cleanup starts after transition.
class GroupRemovalWork {
  GroupRemovalWork({this.delay = const Duration(milliseconds: 350)});
  final Duration delay;
  final Map<String, Future<void>> _visible = {};
  final Map<String, Object> _tokens = {};
  final Map<String, Future<void>> _cleaning = {};
  final Map<String, Future<void>> _rejoining = {};

  Future<void> run({
    required String key,
    required Future<void> Function() hide,
    required Future<void> Function(bool Function() isCurrent) cleanup,
    required bool Function() isCurrent,
    required void Function(Object error, StackTrace stack) onError,
  }) {
    final existing = _visible[key];
    if (existing != null) return existing;
    final token = Object();
    _tokens[key] = token;
    final ready = Completer<void>();
    _visible[key] = ready.future;
    bool valid() => identical(_tokens[key], token) && isCurrent();
    unawaited(() async {
      try {
        if (!valid()) {
          ready.complete();
          return;
        }
        await hide();
        ready.complete();
        await Future<void>.delayed(delay);
        if (valid()) {
          final task = Future<void>.sync(() => cleanup(valid));
          _cleaning[key] = task;
          try {
            await task;
          } finally {
            if (identical(_cleaning[key], task)) _cleaning.remove(key);
          }
        }
      } catch (error, stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
        if (identical(_tokens[key], token)) {
          _tokens.remove(key);
          _visible.remove(key);
        }
        onError(error, stack);
      }
    }());
    return ready.future;
  }

  /// Stop deferred cleanup, but let an already-started hide finish before a
  /// rejoin writes the replacement membership/conversation.
  Future<void> prepareRejoin(String key) {
    final existing = _rejoining[key];
    if (existing != null) return existing;
    final pending = [_visible[key], _cleaning[key]];
    invalidate(key);
    final task = () async {
      for (final work in pending) {
        try {
          if (work != null) await work;
        } catch (_) {
          // A failed removal must not prevent a confirmed rejoin.
        }
      }
    }();
    _rejoining[key] = task;
    return task.whenComplete(() {
      if (identical(_rejoining[key], task)) _rejoining.remove(key);
    });
  }

  void invalidate(String key) {
    _tokens.remove(key);
    _visible.remove(key);
  }

  void clear() {
    _tokens.clear();
    _visible.clear();
  }
}
