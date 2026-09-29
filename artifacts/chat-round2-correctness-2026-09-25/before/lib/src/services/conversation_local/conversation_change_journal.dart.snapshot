import 'dart:collection';

/// Bounded deltas for independently paced consumers. Null means a full read
/// is required (structural change, reset, or a consumer older than retention).
class ConversationChangeJournal {
  ConversationChangeJournal({this.capacity = 64}) : assert(capacity > 0);

  final int capacity;
  final Queue<({int revision, Set<String>? ids})> _entries = Queue();
  int _latest = 0;
  int _floor = 0;

  void record(int revision, Iterable<String>? ids) {
    assert(revision > _latest);
    _latest = revision;
    _entries.add((revision: revision, ids: ids == null ? null : Set.of(ids)));
    while (_entries.length > capacity) {
      _floor = _entries.removeFirst().revision;
    }
  }

  Set<String>? changesSince(int revision) {
    if (revision < _floor || revision > _latest) return null;
    final changed = <String>{};
    for (final entry in _entries) {
      if (entry.revision <= revision) continue;
      if (entry.ids == null) return null;
      changed.addAll(entry.ids!);
    }
    return changed;
  }

  void reset({int revision = 0}) {
    _entries.clear();
    _latest = revision;
    _floor = revision;
  }
}
