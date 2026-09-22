import 'dart:convert';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// One by-value capture per evaluation. Never memoized by object identity:
/// the SDK may mutate that same object before the next evaluation.
class ConversationPreviewToken {
  ConversationPreviewToken({
    required V2TimMessage? message,
    required String conversationKey,
    required int listRevision,
    required int projectionRevision,
  }) : messageFingerprint = conversationPreviewFingerprint(message) {
    token = Object.hash(
        conversationKey, listRevision, projectionRevision, messageFingerprint);
  }

  final String messageFingerprint;
  late final int token;
}

/// Capture display content by value: SDK and local edits may mutate an existing
/// message object without changing its ID, timestamp or delivery status.
String conversationPreviewFingerprint(V2TimMessage? message) {
  if (message == null) return '';
  return jsonEncode([
    message.msgID, message.id, message.timestamp, message.status,
    message.elemType, message.sender, message.userID, message.groupID,
    message.nickName, message.friendRemark, message.nameCard,
    message.isSelf, message.isPeerRead,
    message.localCustomData, message.cloudCustomData,
    message.revokerInfo?.toJson(),
    // Native toJson uses elemList, which need not reflect typed-element edits.
    message.textElem?.toJson(), message.customElem?.toJson(),
    message.imageElem?.toJson(), message.soundElem?.toJson(),
    message.videoElem?.toJson(), message.fileElem?.toJson(),
    message.locationElem?.toJson(), message.faceElem?.toJson(),
    message.mergerElem?.toJson(), message.groupTipsElem?.toJson(),
  ]);
}
