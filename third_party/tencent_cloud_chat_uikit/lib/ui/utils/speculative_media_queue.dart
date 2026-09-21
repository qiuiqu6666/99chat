import 'dart:async';

/// Bounded speculative work, rechecking interaction state before every start.
/// Cancelling pending work never cancels an already accepted foreground send.
class SpeculativeMediaQueue {
  SpeculativeMediaQueue({
    required this.canStart,
    this.maxConcurrent = 3,
    this.capacity = 40,
    this.stagger = const Duration(milliseconds: 32),
    this.retryDelay = const Duration(milliseconds: 100),
  })  : assert(maxConcurrent > 0),
        assert(capacity > 0);

  final bool Function() canStart;
  final int maxConcurrent;
  final int capacity;
  final Duration stagger;
  final Duration retryDelay;
  final _pending = <String, Future<void> Function()>{};
  final Set<String> _active = {};
  Timer? _timer;
  bool _paused = false;

  void add(String key, Future<void> Function() work) {
    if (_active.contains(key)) return;
    if (!_pending.containsKey(key) && _pending.length >= capacity) {
      _pending.remove(_pending.keys.first);
    }
    _pending[key] = work;
    _schedule(Duration.zero);
  }

  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      _schedule(stagger);
    }
  }

  void cancelPending() {
    _pending.clear();
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration delay) {
    if (_paused ||
        _pending.isEmpty ||
        _timer != null ||
        _active.length >= maxConcurrent) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      if (_paused || _pending.isEmpty) return;
      if (!canStart()) {
        _schedule(retryDelay);
        return;
      }
      final key = _pending.keys.first;
      final work = _pending.remove(key)!;
      _active.add(key);
      Future<void>.sync(work)
          .catchError((Object _, StackTrace __) {})
          .whenComplete(() {
        _active.remove(key);
        _schedule(stagger);
      });
      _schedule(stagger);
    });
  }
}
