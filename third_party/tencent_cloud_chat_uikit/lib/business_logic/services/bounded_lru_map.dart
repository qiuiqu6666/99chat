import 'dart:collection';

/// A recoverable cache, never an authoritative store. Reads refresh recency.
class BoundedLruMap<K, V> extends MapBase<K, V> {
  BoundedLruMap(this.capacity, {this.normalize}) : assert(capacity > 0);

  final int capacity;
  final V Function(V)? normalize;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();
  int evictions = 0;

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    if (!_entries.containsKey(key)) this[key] = ifAbsent();
    return this[key] as V;
  }

  @override
  V? operator [](Object? key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = normalize?.call(value) ?? value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
      evictions++;
    }
  }

  @override
  Iterable<K> get keys => _entries.keys.toList(growable: false);
  @override
  int get length => _entries.length;
  @override
  bool containsKey(Object? key) => _entries.containsKey(key);
  @override
  V? remove(Object? key) => _entries.remove(key);
  @override
  void clear() => _entries.clear();
}
