import 'dart:async';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

/// Search results are display snapshots, not authoritative chat-entry metadata.
/// Resolve the SDK conversation before history preparation, as directory opens do.
Future<V2TimConversation> resolveSearchChatEntry({
  required V2TimConversation source,
  required Future<V2TimConversation?> Function(String) loadConversation,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final id = source.conversationID.trim();
  if (id.isEmpty) return source;
  V2TimConversation? current;
  try {
    current = await loadConversation(id).timeout(timeout);
  } catch (_) {
    // A new chat or unavailable SDK must still allow navigation.
    return source;
  }
  if (current == null ||
      isGroupConversation(current) != isGroupConversation(source)) {
    return source;
  }
  final sameConversation = isGroupConversation(source)
      ? searchGroupIdsEquivalent(
          current.groupID ?? current.conversationID,
          source.groupID ?? source.conversationID,
        )
      : searchStripConversationPrefix(current.conversationID) ==
          searchStripConversationPrefix(source.conversationID);
  if (!sameConversation) return source;

  // Copy rather than mutate either the search snapshot or the SDK cache.
  // Keep SDK history/read metadata, including an authoritative null lastMessage.
  return V2TimConversation(
    conversationID: current.conversationID,
    type: current.type,
    userID: current.userID,
    groupID: current.groupID,
    groupType: current.groupType,
    showName: source.showName?.trim().isNotEmpty == true
        ? source.showName
        : current.showName,
    faceUrl: source.faceUrl?.trim().isNotEmpty == true
        ? source.faceUrl
        : current.faceUrl,
    unreadCount: current.unreadCount,
    lastMessage: current.lastMessage,
    draftText: source.draftText ?? current.draftText,
    draftTimestamp: source.draftTimestamp ?? current.draftTimestamp,
    groupAtInfoList: current.groupAtInfoList,
    isPinned: current.isPinned,
    recvOpt: current.recvOpt,
    orderkey: current.orderkey,
    markList: current.markList,
    customData: current.customData,
    conversationGroupList: current.conversationGroupList,
    c2cReadTimestamp: current.c2cReadTimestamp,
    groupReadSequence: current.groupReadSequence,
  );
}
