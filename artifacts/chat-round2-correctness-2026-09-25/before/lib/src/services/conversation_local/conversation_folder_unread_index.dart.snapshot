import 'package:tencent_cloud_chat_demo/src/services/conversation_folder_store.dart';

/// Rebuild membership only when folders/archive state change. Message updates
/// use the reverse index and never walk unrelated folders or their members.
class ConversationFolderUnreadIndex {
  final Map<String, Set<String>> _foldersByConversation = {};
  final Map<String, String> _queryIds = {};
  final Map<String, int> _counts = {};
  final Map<String, int> _totals = {};

  static String _key(String id) =>
      ConversationFolder.folderConversationIdentity(id) ?? id.trim();

  bool get isEmpty => _queryIds.isEmpty;
  Iterable<String> get allQueryIds => _queryIds.values;
  Map<String, int> get totals => Map.unmodifiable(_totals);

  void rebuild(Map<String, Iterable<String>> membership) {
    _foldersByConversation.clear();
    _queryIds.clear();
    _counts.clear();
    _totals.clear();
    for (final folder in membership.entries) {
      _totals[folder.key] = 0;
      for (final id in folder.value) {
        final key = _key(id);
        if (key.isEmpty) continue;
        _queryIds.putIfAbsent(key, () => id);
        (_foldersByConversation[key] ??= {}).add(folder.key);
      }
    }
  }

  Set<String> queryIdsForChanges(Iterable<String> changedIds) => {
        for (final id in changedIds)
          if (_queryIds[_key(id)] case final String queryId) queryId,
      };

  Set<String> applyCounts(Map<String, int> counts) {
    final changedFolders = <String>{};
    for (final entry in counts.entries) {
      final key = _key(entry.key);
      final folders = _foldersByConversation[key];
      if (folders == null) continue;
      final next = entry.value < 0 ? 0 : entry.value;
      final delta = next - (_counts[key] ?? 0);
      _counts[key] = next;
      if (delta == 0) continue;
      for (final folder in folders) {
        _totals[folder] = (_totals[folder]! + delta).clamp(0, 1 << 30);
        changedFolders.add(folder);
      }
    }
    return changedFolders;
  }
}
