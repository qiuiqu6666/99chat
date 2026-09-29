import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

/// Preserve the previous snapshot and order. Only changed visible IDs require
/// a lookup; a missing/reidentified row requests the caller's full fallback.
List<V2TimConversation>? patchConversationContents({
  required List<V2TimConversation> current,
  required Map<String, int> positions,
  required Iterable<String> changedIds,
  required V2TimConversation? Function(String) lookup,
}) {
  List<V2TimConversation>? next;
  for (final id in changedIds) {
    final index = positions[id.trim()];
    if (index == null) continue;
    final row = lookup(id);
    if (row == null || row.conversationID.trim() != id.trim()) return null;
    if (identical(current[index], row)) continue;
    next ??= List.of(current);
    next[index] = row;
  }
  return next == null ? current : List.unmodifiable(next);
}

Iterable<V2TimConversation> resolveObservedConversationRows({
  required Iterable<String> observedIds,
  required V2TimConversation? Function(String) lookup,
}) sync* {
  for (final id in observedIds) {
    final row = lookup(id);
    if (row != null) yield row;
  }
}
