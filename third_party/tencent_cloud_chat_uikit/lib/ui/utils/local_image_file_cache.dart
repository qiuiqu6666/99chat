import 'dart:async';
import 'dart:io';

/// Shared, bounded metadata cache. Rendering reads [peek] only; filesystem
/// queries run asynchronously. Invalidating an entry rejects late probe results.
class LocalImageFileCache {
  LocalImageFileCache({
    Future<bool> Function(String)? probe,
    DateTime Function()? now,
    this.capacity = 512,
    this.ttl = const Duration(seconds: 5),
  })  : assert(capacity > 0),
        _probe = probe ?? _fileAvailable,
        _now = now ?? DateTime.now;

  static final instance = LocalImageFileCache();
  final Future<bool> Function(String) _probe;
  final DateTime Function() _now;
  final int capacity;
  final Duration ttl;
  final _entries = <String, ({bool exists, DateTime checked})>{};
  final Map<String, Future<bool>> _pending = {};

  static Future<bool> _fileAvailable(String path) async {
    try {
      final stat = await File(path).stat();
      return stat.type == FileSystemEntityType.file && stat.size > 0;
    } catch (_) {
      return false;
    }
  }

  bool? peek(String path) {
    final entry = _entries.remove(path);
    if (entry == null) return null;
    _entries[path] = entry;
    return entry.exists;
  }

  Future<bool> check(String path, {bool refresh = false}) {
    if (refresh) _pending.remove(path);
    final entry = _entries[path];
    if (!refresh && entry != null && _now().difference(entry.checked) < ttl) {
      return Future.value(entry.exists);
    }
    final existing = _pending[path];
    if (existing != null) return existing;
    late final Future<bool> task;
    task = Future<bool>.sync(() => _probe(path))
        .catchError((_) => false)
        .then((exists) {
      if (identical(_pending[path], task)) {
        _pending.remove(path);
        _entries.remove(path);
        _entries[path] = (exists: exists, checked: _now());
        while (_entries.length > capacity) {
          _entries.remove(_entries.keys.first);
        }
      }
      return exists;
    });
    _pending[path] = task;
    return task;
  }

  void invalidate(String path) {
    _entries.remove(path);
    _pending.remove(path);
  }

  void clear() {
    _entries.clear();
    _pending.clear();
  }
}
