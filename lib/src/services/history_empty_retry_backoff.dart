/// An empty page is a reason to defer another read, never proof of completeness.
class HistoryEmptyRetryBackoff {
  HistoryEmptyRetryBackoff({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _entries =
      <String, ({String signature, int attempts, DateTime until})>{};
  static const _delays = [
    Duration(seconds: 15),
    Duration(seconds: 60),
    Duration(minutes: 5),
  ];

  bool isDeferred(String key, String signature) {
    final entry = _entries[key];
    if (entry == null) return false;
    if (entry.signature != signature) {
      _entries.remove(key);
      return false;
    }
    return _now().isBefore(entry.until);
  }

  void recordEmpty(String key, String signature) {
    final previous = _entries.remove(key);
    final attempts =
        previous?.signature == signature ? previous!.attempts + 1 : 1;
    if (_entries.length >= 256) _entries.remove(_entries.keys.first);
    _entries[key] = (
      signature: signature,
      attempts: attempts.clamp(1, _delays.length),
      until: _now().add(_delays[(attempts - 1).clamp(0, _delays.length - 1)]),
    );
  }

  void invalidate(String key) => _entries.remove(key);
  void clear() => _entries.clear();
}
