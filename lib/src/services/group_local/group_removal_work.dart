import 'dart:async';

/// Coalesces REST/UI and realtime removal notifications. Only the small visible
/// update is awaited by navigation; destructive cleanup starts after transition.
class GroupRemovalWork {
  GroupRemovalWork({this.delay = const Duration(milliseconds: 350)});
  final Duration delay;
  final Map<String, Future<void>> _visible = {};
  final Map<String, Object> _tokens = {};

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
        if (valid()) await cleanup(valid);
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

  void invalidate(String key) {
    _tokens.remove(key);
    _visible.remove(key);
  }

  void clear() {
    _tokens.clear();
    _visible.clear();
  }
}
