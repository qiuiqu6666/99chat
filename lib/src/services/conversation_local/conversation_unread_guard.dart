import 'package:tencent_cloud_chat_demo/src/services/foreground_chat_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Legacy SQLite mirror reconciliation. SDK-primary counts bypass these
/// local read barriers and accept the provider's absolute unread value.
class ConversationUnreadGuard {
  ConversationUnreadGuard._();

  // The SDK can deliver the conversation row after the message callback but
  // before its unread counter catches up. Keep the UI-side bump alive for a
  // short window, tied to the exact message, so a delayed zero cannot make
  // the list badge disappear. An explicit read barrier still wins.
  static const Duration _optimisticProtectionWindow = Duration(seconds: 5);
  static final Map<String, _OptimisticUnreadStamp> _optimisticUnread =
      <String, _OptimisticUnreadStamp>{};

  static void recordOptimisticUnread({
    required String conversationId,
    required V2TimMessage message,
    required int unreadCount,
  }) {
    final id = conversationId.trim();
    final messageId = (message.msgID ?? message.id ?? '').trim();
    if (id.isEmpty || messageId.isEmpty || unreadCount <= 0) {
      return;
    }
    _optimisticUnread[id] = _OptimisticUnreadStamp(
      messageId: messageId,
      recordedAt: DateTime.now(),
    );
  }

  static void clearOptimisticUnread(String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty) {
      return;
    }
    _optimisticUnread.remove(id);
    _optimisticUnread.removeWhere(
      (key, _) => MessageConversationId.sameConversation(key, id),
    );
  }

  static void clearOptimisticUnreadMany(Iterable<String> conversationIds) {
    for (final id in conversationIds) {
      clearOptimisticUnread(id);
    }
  }

  static void clearAllOptimisticUnread() {
    _optimisticUnread.clear();
  }

  static int resolveForListApply({
    required String conversationId,
    required int existingUnread,
    required V2TimConversation incoming,
    V2TimMessage? existingLastMessage,
    String? ownerUserId,
  }) {
    final olderSnapshot = shouldPreserveUnreadAnchor(
      conversationId: conversationId,
      existingUnread: existingUnread,
      existingLastMessage: existingLastMessage,
      incoming: incoming,
      ownerUserId: ownerUserId,
    );
    final sdkUnread = _resolveUnread(
      incoming,
      ownerUserId: ownerUserId,
      existingLastMessage: existingLastMessage,
      existingUnread: existingUnread,
    );
    var resolved = sdkUnread;
    if (olderSnapshot && sdkUnread < existingUnread) {
      resolved = existingUnread;
    }
    if (_shouldPreserveOptimisticUnread(
      conversationId: conversationId,
      existingUnread: existingUnread,
      sdkUnread: sdkUnread,
      existingLastMessage: existingLastMessage,
      incoming: incoming,
      ownerUserId: ownerUserId,
    )) {
      resolved = existingUnread;
    }
    incoming.unreadCount = resolved;
    return resolved;
  }

  /// Keeps unread comparison metadata monotonic without changing UI preview
  /// selection, which also supports explicit message deletion/rollback.
  static bool shouldPreserveUnreadAnchor({
    required String conversationId,
    required int existingUnread,
    required V2TimConversation incoming,
    V2TimMessage? existingLastMessage,
    String? ownerUserId,
  }) {
    final barrier = existingUnread > 0
        ? ConversationLocalStore.instance
            .readBarrierFor(conversationId, ownerUserId: ownerUserId)
        : null;
    final existingId =
        (existingLastMessage?.msgID ?? existingLastMessage?.id ?? '').trim();
    final incomingId =
        (incoming.lastMessage?.msgID ?? incoming.lastMessage?.id ?? '').trim();
    // A read of M1 cannot acknowledge the later unread M2 merely because
    // their C2C timestamps share a second. The exact read identity disambiguates
    // this replay; only a read snapshot for M2 may lower its count.
    final readReplayBehindUnread = barrier != null &&
        barrier.lastMessageId.isNotEmpty &&
        incomingId == barrier.lastMessageId &&
        existingId.isNotEmpty &&
        existingId != incomingId &&
        (existingLastMessage?.timestamp ?? 0) >= barrier.lastMessageTimestamp;
    return readReplayBehindUnread ||
        _incomingSnapshotIsOlder(
          existingLastMessage: existingLastMessage,
          incomingLastMessage: incoming.lastMessage,
        );
  }

  static bool _shouldPreserveOptimisticUnread({
    required String conversationId,
    required int existingUnread,
    required int sdkUnread,
    required V2TimMessage? existingLastMessage,
    required V2TimConversation incoming,
    String? ownerUserId,
  }) {
    if (existingUnread <= 0 || sdkUnread >= existingUnread) {
      if (sdkUnread > 0 && existingUnread > 0) {
        // The SDK has caught up with the optimistic value.
        clearOptimisticUnread(conversationId);
      }
      return false;
    }
    if (ForegroundChatGuard.isActiveConversation(conversationId)) {
      return false;
    }
    final id = conversationId.trim();
    final stamp = _stampFor(id);
    if (stamp == null) {
      return false;
    }
    final now = DateTime.now();
    if (now.difference(stamp.recordedAt) > _optimisticProtectionWindow) {
      clearOptimisticUnread(id);
      return false;
    }
    final readClearedAt = ConversationLocalStore.instance.readClearedAtFor(
      id,
      ownerUserId: ownerUserId,
    );
    if (readClearedAt >= stamp.recordedAt.millisecondsSinceEpoch) {
      clearOptimisticUnread(id);
      return false;
    }
    final existingId =
        (existingLastMessage?.msgID ?? existingLastMessage?.id ?? '').trim();
    if (existingId != stamp.messageId) {
      // A different local message superseded the optimistic stamp.
      clearOptimisticUnread(id);
      return false;
    }
    final incomingId =
        (incoming.lastMessage?.msgID ?? incoming.lastMessage?.id ?? '').trim();
    if (incomingId.isNotEmpty && incomingId == existingId) {
      // Same-message decreases are account-level read acknowledgements,
      // commonly produced when another device opens the conversation.
      clearOptimisticUnread(id);
      return false;
    }
    if (!_incomingSnapshotIsOlder(
      existingLastMessage: existingLastMessage,
      incomingLastMessage: incoming.lastMessage,
    )) {
      clearOptimisticUnread(id);
      return false;
    }
    if (lastMessageAdvanced(
      before: existingLastMessage,
      after: incoming.lastMessage,
    )) {
      clearOptimisticUnread(id);
      return false;
    }
    return true;
  }

  static _OptimisticUnreadStamp? _stampFor(String conversationId) {
    final direct = _optimisticUnread[conversationId];
    if (direct != null) {
      return direct;
    }
    for (final entry in _optimisticUnread.entries) {
      if (MessageConversationId.sameConversation(entry.key, conversationId)) {
        return entry.value;
      }
    }
    return null;
  }

  static int resolveForPersist({
    required V2TimConversation conversation,
    required int uiUnread,
    required bool suppressStaleForRecentlyLeft,
    String? ownerUserId,
  }) {
    // suppressStaleForRecentlyLeft 保留签名兼容。
    final resolved = _resolveUnread(
      conversation,
      ownerUserId: ownerUserId,
    );
    conversation.unreadCount = resolved;
    return resolved;
  }

  static bool _incomingSnapshotIsOlder({
    required V2TimMessage? existingLastMessage,
    required V2TimMessage? incomingLastMessage,
  }) {
    if (existingLastMessage == null) return false;
    if (incomingLastMessage == null) return true;
    final existingId =
        (existingLastMessage.msgID ?? existingLastMessage.id ?? '').trim();
    final incomingId =
        (incomingLastMessage.msgID ?? incomingLastMessage.id ?? '').trim();
    if (existingId.isNotEmpty && incomingId == existingId) return false;

    final isGroup = (existingLastMessage.groupID?.trim().isNotEmpty ?? false) ||
        (incomingLastMessage.groupID?.trim().isNotEmpty ?? false);
    if (isGroup) {
      final existingSeq =
          int.tryParse(existingLastMessage.seq?.trim() ?? '') ?? 0;
      final incomingSeq =
          int.tryParse(incomingLastMessage.seq?.trim() ?? '') ?? 0;
      if (existingSeq > 0 && incomingSeq > 0 && incomingSeq != existingSeq) {
        return incomingSeq < existingSeq;
      }
    }
    final existingTs = existingLastMessage.timestamp ?? 0;
    final incomingTs = incomingLastMessage.timestamp ?? 0;
    return existingTs > 0 && incomingTs > 0 && incomingTs < existingTs;
  }

  /// Message delivery is not an unread-count authority. The same message can
  /// be replayed or already read on another device; wait for the SDK count.
  static bool shouldOptimisticBumpUnread({
    required String conversationId,
    required V2TimMessage message,
  }) {
    return false;
  }

  /// 合并前后 lastMessage 是否前进到新消息（同 msgID 状态升级不算前进）。
  static bool lastMessageAdvanced({
    V2TimMessage? before,
    V2TimMessage? after,
  }) {
    if (after == null) {
      return false;
    }
    if (before == null) {
      return true;
    }
    final beforeId = before.msgID?.trim() ?? '';
    final afterId = after.msgID?.trim() ?? '';
    if (beforeId.isNotEmpty && afterId.isNotEmpty && beforeId == afterId) {
      return false;
    }
    final beforeTs = before.timestamp ?? 0;
    final afterTs = after.timestamp ?? 0;
    if (afterTs > beforeTs) {
      return true;
    }
    if (afterTs < beforeTs) {
      return false;
    }
    return beforeId != afterId;
  }

  static int _resolveUnread(
    V2TimConversation conversation, {
    String? ownerUserId,
    V2TimMessage? existingLastMessage,
    int? existingUnread,
  }) {
    // Route visibility does not prove the newest bubble was rendered. Apply
    // only a confirmed message watermark, shared with the durable projection.
    ConversationLocalStore.instance.resolveSdkUnreadAgainstReadBarrier(
      conversation,
      ownerUserId: ownerUserId,
      existingLastMessage: existingLastMessage,
      existingUnread: existingUnread,
    );
    return conversation.unreadCount ?? 0;
  }
}

class _OptimisticUnreadStamp {
  const _OptimisticUnreadStamp({
    required this.messageId,
    required this.recordedAt,
  });

  final String messageId;
  final DateTime recordedAt;
}
