import 'package:tencent_cloud_chat_demo/src/api/conversation_pin_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_diag_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_sync_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

class ConversationPinResult {
  const ConversationPinResult({
    required this.applied,
    required this.sdkOk,
    required this.isPinned,
  });

  /// 本地列表是否已按结果更新。
  final bool applied;

  /// 腾讯为主时表示 IM `pinConversation` 是否成功；
  /// 仅自建路径时与 [applied] 同义。
  final bool sdkOk;

  final bool isPinned;
}

/// 会话置顶入口。腾讯 IM `pinConversation` / SDK `isPinned` 为唯一真相。
class ConversationPinService {
  ConversationPinService._();

  static final ConversationPinService instance = ConversationPinService._();

  Future<ConversationPinResult> togglePinned({
    required V2TimConversation conversation,
    String source = 'unknown',
    double? listScrollOffset,
  }) {
    final nextPinned =
        !ConversationPinSyncService.instance.pinValueFor(conversation);
    return setPinned(
      conversation: conversation,
      isPinned: nextPinned,
      source: source,
      listScrollOffset: listScrollOffset,
    );
  }

  Future<ConversationPinResult> setPinned({
    required V2TimConversation conversation,
    required bool isPinned,
    String source = 'unknown',
    double? listScrollOffset,
  }) async {
    final conversationID = conversation.conversationID.trim();
    if (conversationID.isEmpty) {
      ChatDiagLog.log(
        'ConvPin',
        'skip_empty_id',
        extras: <String, Object?>{'source': source},
      );
      return ConversationPinResult(
        applied: false,
        sdkOk: false,
        isPinned: conversation.isPinned ?? false,
      );
    }

    final prevPinned =
        ConversationPinSyncService.instance.pinValueFor(conversation);
    if (prevPinned == isPinned) {
      return ConversationPinResult(
        applied: true,
        sdkOk: true,
        isPinned: isPinned,
      );
    }

    ConversationPinFlickerLog.log(
      'pin_start',
      conversationID: conversationID,
      extras: <String, Object?>{
        'source': source,
        'prevPinned': prevPinned,
        'nextPinned': isPinned,
        'listScroll': listScrollOffset?.toStringAsFixed(1) ?? 'na',
      },
    );
    ChatDiagLog.log(
      'ConvPin',
      'start',
      conversationID: conversationID,
      extras: <String, Object?>{
        'source': source,
        'nextPinned': isPinned,
        'prevPinned': prevPinned,
      },
    );

    try {
      final applied = await ConversationPinSyncService.instance.setPinned(
        conversation: conversation,
        pinned: isPinned,
        source: source,
        listScrollOffset: listScrollOffset,
      );
      ChatDiagLog.log(
        'ConvPin',
        applied.applied ? 'tencent_ok' : 'tencent_or_local_fail',
        conversationID: conversationID,
        extras: <String, Object?>{
          'source': source,
          'localPinned': applied.isPinned,
          'sdkOk': applied.sdkOk,
        },
      );
      return ConversationPinResult(
        applied: applied.applied,
        sdkOk: applied.sdkOk,
        isPinned: applied.isPinned,
      );
    } on ConversationPinLimitExceededException {
      ChatDiagLog.log(
        'ConvPin',
        'pin_limit',
        conversationID: conversationID,
        extras: <String, Object?>{
          'source': source,
        },
      );
      rethrow;
    }
  }

  static V2TimConversation groupConversationSnapshot({
    required String groupID,
    V2TimConversation? existing,
  }) {
    if (existing != null && existing.conversationID.trim().isNotEmpty) {
      return existing;
    }
    final id = groupID.trim();
    return V2TimConversation(
      conversationID: 'group_$id',
      type: 2,
      groupID: id,
      isPinned: existing?.isPinned ?? false,
      showName: existing?.showName,
      faceUrl: existing?.faceUrl,
      unreadCount: existing?.unreadCount ?? 0,
      recvOpt: existing?.recvOpt,
      lastMessage: existing?.lastMessage,
    );
  }

  static V2TimConversation c2cConversationSnapshot({
    required String userID,
    V2TimConversation? existing,
  }) {
    if (existing != null && existing.conversationID.trim().isNotEmpty) {
      return existing;
    }
    final id = userID.trim();
    return V2TimConversation(
      conversationID: 'c2c_$id',
      type: 1,
      userID: id,
      isPinned: existing?.isPinned ?? false,
      showName: existing?.showName,
      faceUrl: existing?.faceUrl,
      unreadCount: existing?.unreadCount ?? 0,
      recvOpt: existing?.recvOpt,
      lastMessage: existing?.lastMessage,
    );
  }
}
