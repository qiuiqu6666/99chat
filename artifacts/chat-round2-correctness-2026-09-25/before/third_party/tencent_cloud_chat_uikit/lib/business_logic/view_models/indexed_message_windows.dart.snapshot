import 'dart:collection';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';

/// Indexes every publication path, including the realtime/media fast paths.
/// Removing a window releases its row references and only its unshared IDs.
class IndexedMessageWindows extends MapBase<String, List<V2TimMessage>?> {
  IndexedMessageWindows({
    required this.onRetained,
    required this.onReleased,
    required this.onWindowRemoved,
    required this.onCleared,
    this.onWindowChanged,
  });

  final void Function(Iterable<String>) onRetained;
  final void Function(Iterable<String>) onReleased;
  final void Function(String) onWindowRemoved;
  final void Function() onCleared;
  final void Function(String)? onWindowChanged;
  final _windows = <String, List<V2TimMessage>?>{};
  final _keysByWindow = <String, Set<String>>{};
  final _byID = <String, Map<String, List<V2TimMessage>>>{};
  final _rowsByWindow = <String, Set<V2TimMessage>>{};
  final _windowsByRow = Map<V2TimMessage, Set<String>>.identity();
  int _identityEpoch = V2TimMessage.identityMutationEpoch;

  void _refreshIdentities() {
    if (_identityEpoch == V2TimMessage.identityMutationEpoch) return;
    final changes = V2TimMessage.identityChangesSince(_identityEpoch);
    _identityEpoch = V2TimMessage.identityMutationEpoch;
    final dirty = changes == null
        ? _windows.keys.toSet()
        : <String>{for (final row in changes) ...?_windowsByRow[row]};
    for (final conversation in dirty) {
      _index(conversation, _windows[conversation]);
    }
  }

  void _index(String conversation, List<V2TimMessage>? rows) {
    for (final row in _rowsByWindow.remove(conversation) ?? <V2TimMessage>{}) {
      final owners = _windowsByRow[row]!;
      owners.remove(conversation);
      if (owners.isEmpty) _windowsByRow.remove(row);
    }
    final retained = Set<V2TimMessage>.identity()..addAll(rows ?? []);
    _rowsByWindow[conversation] = retained;
    for (final row in retained) {
      (_windowsByRow[row] ??= <String>{}).add(conversation);
    }
    final next = <String, List<V2TimMessage>>{};
    for (final row in rows ?? const <V2TimMessage>[]) {
      for (final key in {row.msgID?.trim() ?? '', row.id?.trim() ?? ''}) {
        if (key.isNotEmpty) (next[key] ??= []).add(row);
      }
    }
    final oldKeys = _keysByWindow[conversation] ?? const <String>{};
    final released = <String>[];
    for (final key in oldKeys) {
      if (next.containsKey(key)) continue;
      final locations = _byID[key]!;
      locations.remove(conversation);
      if (locations.isEmpty) {
        _byID.remove(key);
        released.add(key);
      }
    }
    for (final entry in next.entries) {
      (_byID[entry.key] ??= {})[conversation] = entry.value;
    }
    _keysByWindow[conversation] = next.keys.toSet();
    onReleased(released);
    onRetained(next.keys);
    onWindowChanged?.call(conversation);
  }

  List<MapEntry<String, V2TimMessage>> find(String id) {
    _refreshIdentities();
    final locations = _byID[id.trim()];
    return [
      if (locations != null)
        for (final entry in locations.entries)
          for (final message in entry.value) MapEntry(entry.key, message),
    ];
  }

  bool containsMessage(String id) {
    _refreshIdentities();
    return _byID.containsKey(id.trim());
  }

  @override
  List<V2TimMessage>? operator [](Object? key) => _windows[key];

  @override
  void operator []=(String key, List<V2TimMessage>? value) {
    _refreshIdentities();
    _windows[key] = value;
    _index(key, value);
  }

  @override
  Iterable<String> get keys => _windows.keys;

  @override
  List<V2TimMessage>? remove(Object? key) {
    if (key is! String || !_windows.containsKey(key)) return null;
    _refreshIdentities();
    final previous = _windows.remove(key);
    _index(key, null);
    _keysByWindow.remove(key);
    _rowsByWindow.remove(key);
    onWindowRemoved(key);
    return previous;
  }

  @override
  void clear() {
    _windows.clear();
    _keysByWindow.clear();
    _byID.clear();
    _rowsByWindow.clear();
    _windowsByRow.clear();
    _identityEpoch = V2TimMessage.identityMutationEpoch;
    onCleared();
  }
}

/// Loaded rows keep their receipts; notifications for unloaded rows have a
/// bounded LRU. This is a UI cache, not the SDK/host's durable receipt store.
class WindowMessageReceiptCache extends MapBase<String, V2TimMessageReceipt> {
  WindowMessageReceiptCache({required this.isLoaded, this.pendingLimit = 512});

  final bool Function(String) isLoaded;
  final int pendingLimit;
  final _values = <String, V2TimMessageReceipt>{};
  final _pending = LinkedHashSet<String>();

  void retain(Iterable<String> ids) {
    for (final id in ids) {
      _pending.remove(id);
    }
  }

  void release(Iterable<String> ids) {
    for (final id in ids) {
      remove(id);
    }
  }

  @override
  V2TimMessageReceipt? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, V2TimMessageReceipt value) {
    final loaded = isLoaded(key);
    _values[key] = value;
    _pending.remove(key);
    if (!loaded) _pending.add(key);
    while (_pending.length > pendingLimit) {
      remove(_pending.first);
    }
  }

  @override
  Iterable<String> get keys => _values.keys;

  @override
  V2TimMessageReceipt? remove(Object? key) {
    _pending.remove(key);
    return _values.remove(key);
  }

  @override
  void clear() {
    _pending.clear();
    _values.clear();
  }
}
