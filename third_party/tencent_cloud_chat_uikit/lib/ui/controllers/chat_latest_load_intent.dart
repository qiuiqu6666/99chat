import 'dart:async';

enum ChatLatestLoadDecision { ready, blocked, discard }

/// Keeps one deliberate edge gesture through temporary pagination/layout gates.
/// Waiting owns no scrolling or trim lock, and completion never chains pages.
class ChatLatestLoadIntent {
  static const retryDelay = Duration(milliseconds: 220);
  Timer? _timer;
  bool _disposed = false;
  int _generation = 0;

  bool get isPending => _timer != null;

  void request({
    required ChatLatestLoadDecision Function() evaluate,
    required void Function() onReady,
    Duration delay = retryDelay,
  }) {
    if (_disposed || isPending) return;
    final generation = ++_generation;
    void arm(Duration wait) {
      _timer = Timer(wait, () {
        if (_disposed || generation != _generation) return;
        _timer = null;
        final decision = evaluate();
        if (_disposed || generation != _generation) return;
        switch (decision) {
          case ChatLatestLoadDecision.blocked:
            arm(retryDelay);
            break;
          case ChatLatestLoadDecision.ready:
            onReady();
            break;
          case ChatLatestLoadDecision.discard:
            break;
        }
      });
    }

    arm(delay);
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
