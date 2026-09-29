import 'dart:async';
import 'dart:collection';

/// A bounded, latest-value lane for disposable UI progress, not message data.
/// There is one real callback in flight; a slow consumer cannot build a queue
/// of obsolete percentages. Completion/error events use the durable ingress.
class CoalescedUiProgress<T> {
  CoalescedUiProgress({
    required this.onProgress,
    required this.onError,
    this.interval = const Duration(milliseconds: 50),
    this.capacity = 64,
  }) : assert(capacity > 0);

  final FutureOr<void> Function(T value) onProgress;
  final void Function(Object error, StackTrace stackTrace) onError;
  final Duration interval;
  final int capacity;
  final _pending = LinkedHashMap<String, T>();
  Timer? _timer;
  Future<void>? _active;
  String? _activeKey;
  bool _closed = false;
  bool _draining = false;

  int get pendingCount => _pending.length;

  void add(String key, T value) {
    if (_closed) return;
    // Updating an existing key keeps its place so a hot transfer cannot starve
    // other visible transfers. Evicting only loses an intermediate percentage.
    if (!_pending.containsKey(key) && _pending.length >= capacity) {
      _pending.remove(_pending.keys.first);
    }
    _pending[key] = value;
    _schedule();
  }

  void _schedule() {
    if (_closed || _timer != null || _draining || _pending.isEmpty) return;
    _timer = Timer(interval, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_draining || _closed) return;
    _draining = true;
    try {
      // Snapshot keys, not values: replacements arriving during an await should
      // still supersede old progress. New keys wait for the next display tick.
      for (final key in _pending.keys.toList(growable: false)) {
        if (_closed) return;
        if (!_pending.containsKey(key)) continue;
        final value = _pending.remove(key) as T;
        _activeKey = key;
        final work = Future<void>.sync(() => onProgress(value));
        _active = work;
        try {
          await work;
        } catch (error, stackTrace) {
          onError(error, stackTrace);
        } finally {
          _active = null;
          _activeKey = null;
        }
      }
    } finally {
      _draining = false;
      _schedule();
    }
  }

  /// Stop obsolete progress before publishing this transfer's terminal state.
  Future<void> cancel(String key) async {
    _pending.remove(key);
    final active = _activeKey == key ? _active : null;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // The drain reports the consumer error once.
      }
    }
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
