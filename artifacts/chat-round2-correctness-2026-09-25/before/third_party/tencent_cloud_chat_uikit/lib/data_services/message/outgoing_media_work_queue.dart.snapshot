import 'dart:async';
import 'dart:collection';

/// Process-owned work slots. Route disposal never cancels accepted work.
/// Callers validate the captured account before doing work or publishing it.
class OutgoingMediaWorkQueue {
  OutgoingMediaWorkQueue({this.maxConcurrent = 3}) : assert(maxConcurrent > 0);

  static final sends = OutgoingMediaWorkQueue();
  static final imagePreparation = OutgoingMediaWorkQueue(maxConcurrent: 2);

  final int maxConcurrent;
  final Queue<Future<void> Function()> _pending = Queue();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() work) {
    final result = Completer<T>();
    _pending.add(() async {
      try {
        result.complete(await work());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _drain();
    return result.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _pending.isNotEmpty) {
      final next = _pending.removeFirst();
      _active++;
      unawaited(next().whenComplete(() {
        _active--;
        _drain();
      }));
    }
  }
}
