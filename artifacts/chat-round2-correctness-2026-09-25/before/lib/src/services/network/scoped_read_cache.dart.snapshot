/// Bounded cache for successful reads. Requests with the same scope/key share
/// one Future; changing account scope discards both cache and pending lookup.
class ScopedReadCache<T> {
  ScopedReadCache({required this.ttl, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  String? _scope;
  final _cached = <String, ({T value, DateTime expires})>{};
  final _pending = <String, Future<T>>{};

  Future<T> read({
    required String scope,
    required String key,
    required Future<T> Function() load,
    bool force = false,
    bool Function(T value)? cacheIf,
  }) {
    if (_scope != scope) {
      _scope = scope;
      _cached.clear();
      _pending.clear();
    }
    final active = _pending[key];
    if (active != null) return active;
    final cached = _cached[key];
    if (!force && cached != null && _now().isBefore(cached.expires)) {
      return Future.value(cached.value);
    }
    late final Future<T> task;
    task = Future<T>.sync(load).then((value) {
      if (_scope == scope &&
          identical(_pending[key], task) &&
          (cacheIf?.call(value) ?? true)) {
        _cached.removeWhere((_, row) => !_now().isBefore(row.expires));
        if (_cached.length >= 128) _cached.remove(_cached.keys.first);
        _cached[key] = (value: value, expires: _now().add(ttl));
      }
      return value;
    }).whenComplete(() {
      if (identical(_pending[key], task)) _pending.remove(key);
    });
    _pending[key] = task;
    return task;
  }
}
