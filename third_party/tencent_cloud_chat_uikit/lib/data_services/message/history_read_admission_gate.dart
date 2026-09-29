import 'dart:async';

/// Bounds the number of physical SDK history reads, including reads whose
/// Dart caller already timed out. A lease is released only when that native
/// Future actually settles.
class HistoryReadAdmissionGate {
  HistoryReadAdmissionGate({
    required this.maxConcurrent,
    required this.maxQueued,
  })  : assert(maxConcurrent > 0),
        assert(maxQueued >= 0);

  final int maxConcurrent;
  final int maxQueued;
  final List<_HistoryReadWaiter> _waiters = <_HistoryReadWaiter>[];
  int _active = 0;

  int get activeCount => _active;
  int get queuedCount => _waiters.length;

  Future<HistoryReadAdmissionLease> acquire({required Duration timeout}) {
    if (_active < maxConcurrent && _waiters.isEmpty) {
      _active++;
      return Future<HistoryReadAdmissionLease>.value(
        HistoryReadAdmissionLease._(_release),
      );
    }
    if (_waiters.length >= maxQueued) {
      return Future<HistoryReadAdmissionLease>.error(
        const HistoryReadCapacityException(),
      );
    }

    final waiter = _HistoryReadWaiter();
    _waiters.add(waiter);
    waiter.timer = Timer(timeout, () {
      if (_waiters.remove(waiter) && !waiter.completer.isCompleted) {
        waiter.completer.completeError(
          TimeoutException(
              'Timed out waiting for a history read slot', timeout),
        );
      }
    });
    return waiter.completer.future;
  }

  void _release() {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeAt(0);
      waiter.timer?.cancel();
      if (waiter.completer.isCompleted) continue;
      // Hand the existing permit directly to the next waiter.
      waiter.completer.complete(HistoryReadAdmissionLease._(_release));
      return;
    }
    if (_active > 0) _active--;
  }
}

class HistoryReadAdmissionLease {
  HistoryReadAdmissionLease._(this._releasePermit);

  final void Function() _releasePermit;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _releasePermit();
  }
}

class HistoryReadCapacityException implements Exception {
  const HistoryReadCapacityException();

  @override
  String toString() => 'HistoryReadCapacityException';
}

class _HistoryReadWaiter {
  final Completer<HistoryReadAdmissionLease> completer =
      Completer<HistoryReadAdmissionLease>();
  Timer? timer;
}
