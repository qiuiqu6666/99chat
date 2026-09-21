import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Serial, account-keyed writes. Awaiting merge still means persisted.
class CoalescedPresenceCache {
  final Map<String, _PresenceBatch> _pending = {};
  final Map<String, Map<String, Object>> _committed = {};
  final Map<String, int> _queued = {};
  Future<void> _tail = Future.value();
  static const maxEntries = 2048;
  static const maxSnapshots = 8;

  Future<void> merge(String key, Map<String, Object> updates) {
    if (updates.isEmpty) return Future.value();
    final saved = _committed[key];
    if (!_pending.containsKey(key) &&
        !_queued.containsKey(key) &&
        saved != null &&
        updates.entries.every((entry) => saved[entry.key] == entry.value)) {
      return Future.value();
    }
    final batch = _pending.putIfAbsent(key, () {
      final value = _PresenceBatch();
      value.timer = Timer(const Duration(milliseconds: 200), () => _flush(key));
      return value;
    });
    for (final entry in updates.entries) {
      batch.updates.remove(entry.key);
      batch.updates[entry.key] = entry.value;
    }
    _trim(batch.updates);
    return batch.done.future;
  }

  static void _trim(Map<String, Object> map) {
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
  }

  void _flush(String key) {
    final batch = _pending.remove(key);
    if (batch == null) return;
    _queued[key] = (_queued[key] ?? 0) + 1;
    _tail = _tail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final values = <String, Object>{...?_committed[key]};
        if (!_committed.containsKey(key)) {
          await prefs.reload();
          try {
            final decoded = jsonDecode(prefs.getString(key) ?? '{}');
            if (decoded is Map) {
              for (final entry in decoded.entries) {
                if (entry.value is String || entry.value is num) {
                  values[entry.key.toString()] = entry.value as Object;
                }
              }
            }
          } catch (_) {}
        }
        final previous = Map<String, Object>.of(values);
        _remember(key, previous);
        for (final entry in batch.updates.entries) {
          values.remove(entry.key);
          values[entry.key] = entry.value;
        }
        _trim(values);
        final changed = values.length != previous.length ||
            values.entries.any((entry) => previous[entry.key] != entry.value);
        if (changed) {
          if (!await prefs.setString(key, jsonEncode(values))) {
            throw StateError('Presence cache write failed');
          }
          _remember(key, values);
        }
        batch.done.complete();
      } catch (error, stack) {
        // SharedPreferences changes its memory mirror even on backend failure.
        // Reload before a future snapshot eviction can mistake it for disk data.
        try {
          await (await SharedPreferences.getInstance()).reload();
        } catch (_) {}
        batch.done.completeError(error, stack);
      } finally {
        final remaining = _queued[key]! - 1;
        if (remaining == 0) {
          _queued.remove(key);
        } else {
          _queued[key] = remaining;
        }
      }
    });
  }

  void _remember(String key, Map<String, Object> values) {
    _committed.remove(key);
    final snapshot = Map<String, Object>.of(values);
    _trim(snapshot);
    _committed[key] = snapshot;
    while (_committed.length > maxSnapshots) {
      _committed.remove(_committed.keys.first);
    }
  }

  Future<void> clear(String key) {
    final batch = _pending.remove(key);
    batch?.timer.cancel();
    _committed.remove(key);
    _queued[key] = (_queued[key] ?? 0) + 1;
    final result = _tail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(key)) {
          throw StateError('Presence cache clear failed');
        }
      } finally {
        _committed.remove(key);
        final remaining = _queued[key]! - 1;
        if (remaining == 0) {
          _queued.remove(key);
        } else {
          _queued[key] = remaining;
        }
      }
    });
    _tail = result.then((_) {}, onError: (Object _, StackTrace __) {});
    if (batch != null) {
      result.then((_) => batch.done.complete(),
          onError: (Object error, StackTrace stack) =>
              batch.done.completeError(error, stack));
    }
    return result;
  }
}

class _PresenceBatch {
  final updates = <String, Object>{};
  final done = Completer<void>();
  late final Timer timer;
}
