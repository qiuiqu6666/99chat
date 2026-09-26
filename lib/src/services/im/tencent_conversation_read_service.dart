import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:flutter/foundation.dart';
import 'conversation_read_policy.dart';
import '../conversation_unread_trace.dart';
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

  /// Replaces only the provider boundary; validation and account fencing still
  /// execute, allowing tests to exercise the real durable read queue.
  @visibleForTesting
  static Future<V2TimCallback> Function({
    required String conversationID,
    required int cleanTimestamp,
    required int cleanSequence,
  })? cleanUnreadForTesting;

  static Future<V2TimCallback> markRead({
    required MessageService messageService,
    required String conversationID,
    required bool isGroup,
    required SessionIdentity capturedIdentity,
    bool explicitFullConversationClear = false,
  }) async {
    final id = _rawPeerID(conversationID, isGroup: isGroup);
    if (id.isEmpty || id == 'c2c' || id == 'group') {
      return V2TimCallback(code: -1, desc: 'empty_conversation_id');
    }
    if (!_isCurrent(capturedIdentity)) {
      return _staleIdentity();
    }
    // Old page lifecycle callbacks carry no visible-message watermark.
    // They must not clear newer/unseen messages; the read outbox owns those
    // bounded acknowledgements. Full clears require an explicit user action.
    if (!explicitFullConversationClear) {
      ConversationUnreadTrace.log(
        'legacy_read_blocked',
        conversationID: conversationID,
        extras: {'isGroup': isGroup, 'reason': 'read_watermark_unavailable'},
      );
      return V2TimCallback(code: -1, desc: 'read_watermark_unavailable');
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
    bool allowFullConversationClean = false,
  }) async {
    final id = conversationID.trim();
    if (id.isEmpty) {
      return V2TimCallback(code: -1, desc: 'empty_conversation_id');
    }
    if (!_isCurrent(capturedIdentity)) {
      return _staleIdentity();
    }
    if (!ConversationReadPolicy.validTarget(id, cleanTimestamp, cleanSequence,
        explicitTypeClear: allowFullTypeClean,
        explicitConversationClear: allowFullConversationClean)) {
      ConversationUnreadTrace.log(
        'sdk_read_target_invalid',
        conversationID: id,
        extras: {
          'cleanTimestamp': cleanTimestamp,
          'cleanSequence': cleanSequence
        },
      );
      return V2TimCallback(code: -1, desc: 'read_watermark_unavailable');
    }
    ConversationUnreadTrace.log('sdk_read_request',
        conversationID: id,
        extras: {
          'cleanTimestamp': cleanTimestamp,
          'cleanSequence': cleanSequence
        });
    final override = cleanUnreadForTesting;
    final result = override != null
        ? await override(
            conversationID: id,
            cleanTimestamp: cleanTimestamp > 0 ? cleanTimestamp : 0,
            cleanSequence: cleanSequence > 0 ? cleanSequence : 0,
          )
        : await TencentImSDKPlugin.v2TIMManager
            .getConversationManager()
            .cleanConversationUnreadMessageCount(
              conversationID: id,
              cleanTimestamp: cleanTimestamp > 0 ? cleanTimestamp : 0,
              cleanSequence: cleanSequence > 0 ? cleanSequence : 0,
            );
    ConversationUnreadTrace.log('sdk_read_result', conversationID: id, extras: {
      'sdkCode': result.code,
      'identityCurrent': _isCurrent(capturedIdentity)
    });
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
