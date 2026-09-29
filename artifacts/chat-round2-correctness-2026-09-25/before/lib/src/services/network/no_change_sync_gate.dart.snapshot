/// Suppress only repeated reads of an unchanged checkpoint. A realtime hint,
/// manual refresh or account change invalidates both the gate and old replies.
class NoChangeSyncGate {
  NoChangeSyncGate(
      {this.delay = const Duration(seconds: 30), DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Duration delay;
  final DateTime Function() _now;
  String? _key;
  DateTime? _until;
  int generation = 0;

  bool shouldSkip(String key) =>
      _key == key && _until != null && _now().isBefore(_until!);
  Duration get remaining =>
      _until == null ? Duration.zero : _until!.difference(_now());

  void recordEmpty(String key, int requestGeneration) {
    if (requestGeneration != generation) return;
    _key = key;
    _until = _now().add(delay);
  }

  void invalidate() {
    generation++;
    _key = null;
    _until = null;
  }
}
