import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

/// Lightweight identity for a conversation row.
///
/// This belongs to the session projection boundary rather than the legacy
/// list notifier. It intentionally hashes only fields that can change what a
/// row paints, avoiding full-message JSON serialization on realtime updates.
class ConversationProjectionFingerprint {
  const ConversationProjectionFingerprint._();

  static int hash(V2TimConversation conversation) {
    final lastMessage = conversation.lastMessage;
    final activeMs = ConversationLocalStore.activeTimeMs(conversation);
    final orderKey = activeMs > 0 ? 0 : (conversation.orderkey ?? 0);
    return Object.hash(
      conversation.conversationID,
      conversation.unreadCount ?? 0,
      conversation.isPinned == true,
      conversation.recvOpt ?? 0,
      orderKey,
      activeMs,
      lastMessage?.msgID?.trim() ?? '',
      lastMessage?.id?.trim() ?? '',
      lastMessage?.isSelf == true,
      lastMessage?.status ?? -1,
      lastMessage?.isPeerRead == true,
      revokedLastMessageFingerprint(lastMessage),
      _lastMessagePreviewFingerprint(lastMessage),
      conversation.showName?.trim() ?? '',
      conversation.faceUrl?.trim() ?? '',
      conversation.draftText?.trim() ?? '',
      displayNameStoreFragment(conversation),
      localDisplayIdentityFragment(conversation),
    );
  }

  static String string(V2TimConversation conversation) {
    final lastMessage = conversation.lastMessage;
    final activeMs = ConversationLocalStore.activeTimeMs(conversation);
    final orderKey = activeMs > 0 ? 0 : (conversation.orderkey ?? 0);
    return [
      conversation.conversationID,
      '${conversation.unreadCount ?? 0}',
      '${conversation.isPinned == true}',
      '${conversation.recvOpt ?? 0}',
      '$orderKey',
      '$activeMs',
      lastMessage?.msgID?.trim() ?? '',
      lastMessage?.id?.trim() ?? '',
      lastMessage?.isSelf == true ? '1' : '0',
      '${lastMessage?.status ?? -1}',
      lastMessage?.isPeerRead == true ? '1' : '0',
      revokedLastMessageFingerprint(lastMessage),
      _lastMessagePreviewFingerprint(lastMessage),
      conversation.showName?.trim() ?? '',
      conversation.faceUrl?.trim() ?? '',
      conversation.draftText?.trim() ?? '',
      displayNameStoreFragment(conversation),
      localDisplayIdentityFragment(conversation),
    ].join('|');
  }

  static String _lastMessagePreviewFingerprint(V2TimMessage? message) {
    return GroupTipsMessageHelper.contentFingerprint(message);
  }

  static String displayNameStoreFragment(V2TimConversation conversation) {
    if (conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false)) {
      return '';
    }
    final fromUser = conversation.userID?.trim() ?? '';
    final fromConv = conversation.conversationID.trim();
    final raw = fromUser.isNotEmpty
        ? fromUser
        : (fromConv.startsWith('c2c_') ? fromConv.substring(4) : fromConv);
    final userId = ChatIdFormat.rawUserUid(raw);
    if (userId.isEmpty) {
      return '';
    }
    return DisplayNameStore.instance.c2c(userId)?.trim() ?? '';
  }

  /// Row paint reads GroupLocalStore / UserProfileLocal first. The conversation
  /// object's showName/faceUrl can stay stale, so the feed slot fingerprint
  /// must include those local identity fields or it will reuse the old child.
  static String localDisplayIdentityFragment(V2TimConversation conversation) {
    if (conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false)) {
      final fromGroup = conversation.groupID?.trim() ?? '';
      final fromConv = conversation.conversationID.trim();
      final gid = fromGroup.isNotEmpty
          ? fromGroup
          : (fromConv.startsWith('group_')
              ? fromConv.substring(6)
              : fromConv);
      if (gid.isEmpty) {
        return '';
      }
      try {
        final record = GroupLocalStore.instance.readCached(groupId: gid);
        if (record == null) {
          return '';
        }
        return '${record.groupName.trim()}\u0000${record.avatarUrl.trim()}\u0000${record.avatarVersion}';
      } catch (_) {
        return '';
      }
    }
    final fromUser = conversation.userID?.trim() ?? '';
    final fromConv = conversation.conversationID.trim();
    final raw = fromUser.isNotEmpty
        ? fromUser
        : (fromConv.startsWith('c2c_') ? fromConv.substring(4) : fromConv);
    final userId = ChatIdFormat.rawUserUid(raw);
    if (userId.isEmpty) {
      return '';
    }
    try {
      final record = UserProfileLocalService.instance.readCached(userId);
      if (record == null) {
        return '';
      }
      return '${record.friendRemark.trim()}\u0000${record.nickname.trim()}\u0000${record.avatarUrl.trim()}\u0000${record.avatarVersion}';
    } catch (_) {
      return '';
    }
  }
}
