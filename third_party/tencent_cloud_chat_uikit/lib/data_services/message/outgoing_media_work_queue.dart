import 'dart:async';
import 'dart:collection';

/// Process-owned work slots. Route disposal never cancels accepted work.
/// Callers validate the captured account before doing work or publishing it.
class OutgoingMediaWorkQueue {
  OutgoingMediaWorkQueue({this.maxConcurrent = 3, this.maxWeight})
      : assert(maxConcurrent > 0),
        assert(maxWeight == null || maxWeight > 0);

  static final sends = OutgoingMediaWorkQueue();
  static final imagePreparation = OutgoingMediaWorkQueue(maxConcurrent: 2);
  // Estimated decode/rotation/encode working bytes, not an OS allocation cap.
  // Larger jobs run alone; upload admission is deliberately independent.
  static final imageDecode =
      OutgoingMediaWorkQueue(maxConcurrent: 2, maxWeight: 96 * 1024 * 1024);

  final int maxConcurrent;
  final int? maxWeight;
  final Queue<({int weight, Future<void> Function() work})> _pending = Queue();
  int _active = 0;
  int _activeWeight = 0;

  Future<T> run<T>(Future<T> Function() work, {int weight = 1}) {
    if (weight <= 0) throw ArgumentError.value(weight, 'weight');
    final admitted = maxWeight == null ? weight : weight.clamp(1, maxWeight!);
    final result = Completer<T>();
    _pending.add((
      weight: admitted,
      work: () async {
        try {
          result.complete(await work());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      }
    ));
    _drain();
    return result.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _pending.isNotEmpty) {
      if (maxWeight != null &&
          _activeWeight + _pending.first.weight > maxWeight!) break;
      final next = _pending.removeFirst();
      _active++;
      _activeWeight += next.weight;
      unawaited(next.work().whenComplete(() {
        _active--;
        _activeWeight -= next.weight;
        _drain();
      }));
    }
  }
}
