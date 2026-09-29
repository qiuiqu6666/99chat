import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

typedef ConversationProjectionKey = String Function(
  V2TimConversation conversation,
);
typedef ConversationProjectionIdKey = String Function(String id);
typedef ConversationProjectionMerge = V2TimConversation Function(
  V2TimConversation existing,
  V2TimConversation incoming,
);
typedef ConversationProjectionAdmission = bool Function(
  V2TimConversation incoming,
  List<V2TimConversation> current,
);

class ConversationProjectionReduction {
  const ConversationProjectionReduction({
    required this.conversations,
    required this.deleted,
    required this.updated,
    required this.inserted,
  });

  final List<V2TimConversation> conversations;
  final Set<String> deleted;
  final Set<String> updated;
  final Set<String> inserted;
}

/// 无状态的会话 projection merge 规则。
///
/// 这里只处理身份、删除、更新和准入，不读取 Store、不触发通知，也不
/// 修改任何全局状态。业务层可以通过回调注入 canonical key、字段合并和
/// 窗口准入规则，便于 Controller 最终接管写入。
class ConversationProjectionReducer {
  const ConversationProjectionReducer();

  static ConversationProjectionReduction reduce({
    required List<V2TimConversation> current,
    required List<V2TimConversation> upserted,
    required Set<String> deletedIds,
    required Set<String> forceAdmitIds,
    required ConversationProjectionKey keyOf,
    required ConversationProjectionIdKey keyOfId,
    required ConversationProjectionMerge mergeExisting,
    required ConversationProjectionAdmission shouldAdmit,
  }) {
    final next = List<V2TimConversation>.from(current);
    final index = <String, int>{};
    for (var i = 0; i < next.length; i++) {
      final key = keyOf(next[i]);
      if (key.isNotEmpty) index[key] = i;
    }

    final deleted = <String>{};
    for (final id in deletedIds) {
      final key = keyOfId(id);
      if (key.isNotEmpty) deleted.add(key);
    }
    if (deleted.isNotEmpty) {
      next.removeWhere((conversation) {
        final key = keyOf(conversation);
        return deleted.contains(key) ||
            deleted.contains(keyOfId(conversation.conversationID));
      });
      index
        ..clear()
        ..addEntries(
          next
              .asMap()
              .entries
              .map((entry) => MapEntry(keyOf(entry.value), entry.key))
              .where((entry) => entry.key.isNotEmpty),
        );
    }

    final updated = <String>{};
    final inserted = <String>{};
    for (final incoming in upserted) {
      final key = keyOf(incoming);
      if (key.isEmpty) continue;
      final indexOfExisting = index[key];
      if (indexOfExisting != null) {
        next[indexOfExisting] = mergeExisting(
          next[indexOfExisting],
          incoming,
        );
        updated.add(key);
        continue;
      }
      final forced =
          forceAdmitIds.map(keyOfId).any((forcedKey) => forcedKey == key);
      if (!forced && !shouldAdmit(incoming, next)) continue;
      index[key] = next.length;
      next.add(incoming);
      inserted.add(key);
    }
    return ConversationProjectionReduction(
      conversations: next,
      deleted: deleted,
      updated: updated,
      inserted: inserted,
    );
  }
}
