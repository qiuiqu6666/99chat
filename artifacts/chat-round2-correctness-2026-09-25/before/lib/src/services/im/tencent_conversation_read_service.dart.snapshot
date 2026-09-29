import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

/// Account-fenced authority for Tencent conversation read mutations.
class TencentConversationReadService {
  TencentConversationReadService._();

  static Future<V2TimCallback> markRead({
    required MessageService messageService,
    required String conversationID,
    required bool isGroup,
    required SessionIdentity capturedIdentity,
  }) async {
    final id = _rawPeerID(conversationID, isGroup: isGroup);
    if (id.isEmpty) {
      return V2TimCallback(code: -1, desc: 'empty_conversation_id');
    }
    if (!_isCurrent(capturedIdentity)) {
      return _staleIdentity();
    }
    final result = isGroup
        ? await messageService.markGroupMessageAsRead(groupID: id)
        : await messageService.markC2CMessageAsRead(userID: id);
    return _isCurrent(capturedIdentity) ? result : _staleIdentity();
  }

  static Future<V2TimCallback> cleanUnread({
    required String conversationID,
    required SessionIdentity capturedIdentity,
    required int cleanTimestamp,
    required int cleanSequence,
    bool allowFullTypeClean = false,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return V2TimCallback(code: -1, desc: 'empty_conversation_id');
    }
    if (!_isCurrent(capturedIdentity)) {
      return _staleIdentity();
    }
    if (!allowFullTypeClean && cleanTimestamp <= 0 && cleanSequence <= 0) {
      return V2TimCallback(code: -1, desc: 'read_watermark_unavailable');
    }
    final result = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .cleanConversationUnreadMessageCount(
          conversationID: id,
          cleanTimestamp: cleanTimestamp > 0 ? cleanTimestamp : 0,
          cleanSequence: cleanSequence > 0 ? cleanSequence : 0,
        );
    return _isCurrent(capturedIdentity) ? result : _staleIdentity();
  }

  static Future<V2TimConversation?> conversationSnapshot({
    required String conversationID,
    required SessionIdentity capturedIdentity,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty || !_isCurrent(capturedIdentity)) {
      return null;
    }
    final result = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .getConversation(conversationID: id);
    if (result.code != 0 || !_isCurrent(capturedIdentity)) {
      return null;
    }
    return result.data;
  }

  static bool _isCurrent(SessionIdentity identity) {
    if (!SessionIdentityService.instance.isGenerationCurrent(
      identity.generation,
    )) {
      return false;
    }
    final currentOwner = ChatIdFormat.rawUserUid(
      ApiClient.instance.authenticatedUserId,
    );
    return identity.ownerUserId.isEmpty ||
        currentOwner.isEmpty ||
        identity.ownerUserId == currentOwner;
  }

  static String _rawPeerID(String conversationID, {required bool isGroup}) {
    final id = conversationID.trim();
    final prefix = isGroup ? 'group_' : 'c2c_';
    return id.startsWith(prefix) ? id.substring(prefix.length).trim() : id;
  }

  static V2TimCallback _staleIdentity() =>
      V2TimCallback(code: -1, desc: 'stale_identity');
}
