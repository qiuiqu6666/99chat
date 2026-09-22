import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_fingerprint.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Immutable list-row display value. Rows subscribe to this, not the SDK object.
class ConversationRowView {
  const ConversationRowView({
    required this.conversationId,
    required this.displayName,
    required this.avatarKey,
    required this.lastMessagePreview,
    required this.lastMessageId,
    required this.lastMessageStatus,
    required this.lastMessageRevoked,
    required this.displayTimeMs,
    required this.unreadCount,
    required this.pinned,
    required this.muted,
    required this.draftText,
    required this.hasMention,
    required this.type,
    required this.orderKey,
    required this.activeTimeMs,
    this.previewFingerprint = '',
  });

  final String conversationId;
  final String displayName;
  final String avatarKey;
  final String lastMessagePreview;
  final String previewFingerprint;
  final String lastMessageId;
  final int lastMessageStatus;
  final bool lastMessageRevoked;
  final int displayTimeMs;
  final int unreadCount;
  final bool pinned;
  final bool muted;
  final String draftText;
  final bool hasMention;
  final int type;
  final int orderKey;
  final int activeTimeMs;

  factory ConversationRowView.fromConversation(V2TimConversation row) {
    final message = row.lastMessage;
    return ConversationRowView(
      conversationId: row.conversationID.trim(),
      displayName: (row.showName ?? '').trim(),
      avatarKey: (row.faceUrl ?? '').trim(),
      lastMessagePreview: previewTextOf(message),
      previewFingerprint: conversationPreviewFingerprint(message),
      lastMessageId: message?.msgID?.trim() ?? '',
      lastMessageStatus: message?.status ?? 0,
      lastMessageRevoked: _isRevoked(message),
      displayTimeMs: ConversationLocalStore.displayTimestampMs(row),
      unreadCount: row.unreadCount ?? 0,
      pinned: row.isPinned == true,
      muted: row.recvOpt == 2,
      draftText: row.draftText ?? '',
      hasMention: row.groupAtInfoList?.isNotEmpty == true,
      type: row.type ?? 0,
      orderKey: row.orderkey ?? 0,
      activeTimeMs: ConversationLocalStore.activeTimeMs(row),
    );
  }

  static bool _isRevoked(V2TimMessage? message) {
    if (message == null) return false;
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) {
      return true;
    }
    return (message.revokerInfo?.userID ?? '').trim().isNotEmpty;
  }

  static String previewTextOf(V2TimMessage? message) {
    if (message == null) return '';
    if (_isRevoked(message)) return 'revoked';
    final text = message.textElem?.text?.trim();
    if (text != null && text.isNotEmpty) return text;
    return '${message.elemType ?? 0}';
  }

  bool sameSortKey(ConversationRowView other) {
    return pinned == other.pinned &&
        orderKey == other.orderKey &&
        activeTimeMs == other.activeTimeMs;
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationRowView &&
        other.conversationId == conversationId &&
        other.displayName == displayName &&
        other.avatarKey == avatarKey &&
        other.lastMessagePreview == lastMessagePreview &&
        other.previewFingerprint == previewFingerprint &&
        other.lastMessageId == lastMessageId &&
        other.lastMessageStatus == lastMessageStatus &&
        other.lastMessageRevoked == lastMessageRevoked &&
        other.displayTimeMs == displayTimeMs &&
        other.unreadCount == unreadCount &&
        other.pinned == pinned &&
        other.muted == muted &&
        other.draftText == draftText &&
        other.hasMention == hasMention &&
        other.type == type &&
        other.orderKey == orderKey &&
        other.activeTimeMs == activeTimeMs;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        conversationId,
        displayName,
        avatarKey,
        lastMessagePreview,
        previewFingerprint,
        lastMessageId,
        lastMessageStatus,
        lastMessageRevoked,
        displayTimeMs,
        unreadCount,
        pinned,
        muted,
        draftText,
        hasMention,
        type,
        orderKey,
        activeTimeMs,
      ]);
}
