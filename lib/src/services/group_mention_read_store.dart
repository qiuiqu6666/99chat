import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Exact mention acknowledgements, separate from the conversation unread
/// watermark: jumping to one mention must not consume any other message.
class GroupMentionReadStore {
  static final instance = GroupMentionReadStore();

  final _loaded = <String, Set<String>>{};
  final _loading = <String, Future<Set<String>>>{};
  final _writeTails = <String, Future<void>>{};

  static String? sequenceKey(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number != null && number > 0 ? '$number' : null;
  }

  String _key(String owner, String conversation) {
    final id = conversation.trim();
    final group = id.startsWith('group_') ? id.substring(6) : id;
    return 'group_mentions_read_v1:'
        '${base64Url.encode(utf8.encode(jsonEncode([owner.trim(), group])))}';
  }

  Set<String>? cached(String owner, String conversation) {
    final key = _key(owner, conversation);
    // A page reopened during a write must wait instead of rendering old data.
    return _writeTails.containsKey(key) ? null : _loaded[key];
  }

  Future<Set<String>> load(String owner, String conversation) {
    if (owner.trim().isEmpty || conversation.trim().isEmpty) {
      return Future.value(const <String>{});
    }
    final key = _key(owner, conversation);
    final writing = _writeTails[key];
    if (writing != null) {
      return writing.then((_) => load(owner, conversation));
    }
    final cached = _loaded[key];
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(key, () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rows = (prefs.getStringList(key) ?? const <String>[])
            .map(sequenceKey)
            .whereType<String>();
        return _loaded[key] = Set<String>.unmodifiable(rows);
      } finally {
        _loading.remove(key);
      }
    });
  }

  Future<bool> acknowledge(
      String owner, String conversation, String seq) async {
    final sequence = sequenceKey(seq);
    if (owner.trim().isEmpty ||
        conversation.trim().isEmpty ||
        sequence == null) {
      return false;
    }
    await load(owner, conversation);
    final key = _key(owner, conversation);
    final previousWrite = _writeTails[key];
    final task = (() async {
      if (previousWrite != null) await previousWrite;
      final previous = _loaded[key] ?? const <String>{};
      if (previous.contains(sequence)) return true;
      final updated = {...previous, sequence};
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(key, updated.toList())) return false;
      _loaded[key] = Set<String>.unmodifiable(updated);
      return true;
    })();
    // One failed write must not prevent a later user action from saving.
    final tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writeTails[key] = tail;
    try {
      return await task;
    } finally {
      if (identical(_writeTails[key], tail)) _writeTails.remove(key);
    }
  }
}
