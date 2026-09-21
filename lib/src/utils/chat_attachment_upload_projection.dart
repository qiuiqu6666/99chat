import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment_task.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_message_overlay_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

const _uploadPrefix = 'local_attachment_upload:';
const _uploadMarker = 'chat.attachment.local-upload';

String attachmentUploadOverlayId(ChatAttachmentTask task) =>
    '$_uploadPrefix${task.ownerUserId}:${task.taskId}';

Map<String, dynamic>? _uploadData(V2TimMessage message) {
  final id = message.msgID ?? '';
  final raw = message.localCustomData ?? '';
  if (!id.startsWith(_uploadPrefix) ||
      message.isSelf != true ||
      raw.length > 4096) {
    return null;
  }
  try {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['type'] != _uploadMarker ||
        data['taskId'] is! String ||
        data['ownerUserId'] != message.sender ||
        id != '$_uploadPrefix${data['ownerUserId']}:${data['taskId']}') {
      return null;
    }
    return data;
  } catch (_) {
    return null;
  }
}

String? attachmentUploadTaskId(V2TimMessage message, String owner) {
  final data = _uploadData(message);
  return owner.isNotEmpty && data?['ownerUserId'] == owner
      ? data!['taskId'] as String
      : null;
}

/// A UI-only record: never create it through the SDK or persist it as history.
/// Progress is deliberately excluded; the visible card listens to the task.
V2TimMessage attachmentUploadOverlay(ChatAttachmentTask task) {
  final id = attachmentUploadOverlayId(task);
  final message = V2TimMessage.fromJson({
    'message_msg_id': id,
    'message_server_time': task.createdAt ~/ 1000,
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.id = id;
  message.msgID = id;
  message.timestamp = task.createdAt ~/ 1000;
  message.sender = task.ownerUserId;
  message.isSelf = true;
  message.isRead = true;
  message.isExcludedFromUnreadCount = true;
  message.isExcludedFromLastMessage = true;
  message.userID = task.target.isGroup ? null : task.target.id;
  message.groupID = task.target.isGroup ? task.target.id : null;
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
  message.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
  message.localCustomData = jsonEncode({
    'type': _uploadMarker,
    'taskId': task.taskId,
    'ownerUserId': task.ownerUserId,
    'attachmentId': task.attachmentId,
    'referenceId': task.referenceId,
  });
  return message;
}

/// Only add/remove this account's upload rows for this conversation. Existing
/// call/group overlays and other conversations keep their own lifecycle.
void syncAttachmentUploadOverlays({
  required LocalMessageOverlayStore store,
  required String owner,
  required ChatAttachmentTarget target,
  required List<ChatAttachmentTask> tasks,
}) {
  if (owner.isEmpty) return;
  final conversationID = '${target.isGroup ? "group" : "c2c"}_${target.id}';
  final visible = tasks
      .where((task) =>
          !task.terminal &&
          task.ownerUserId == owner &&
          task.target.key == target.key)
      .toList();
  final liveIds = visible.map(attachmentUploadOverlayId).toSet();
  store.removeWhere(
      conversationID,
      (message) =>
          attachmentUploadTaskId(message, owner) != null &&
          !liveIds.contains(message.msgID));
  for (final task in visible) {
    store.upsert(conversationID, attachmentUploadOverlay(task));
  }
}

/// The Outbox can publish its formal bubble before dispatch returns. Hide the
/// upload row as soon as that exact reference is represented, including a failed
/// Outbox bubble: from that point the Outbox owns delivery and retry.
List<V2TimMessage> hideRepresentedAttachmentUploads({
  required List<V2TimMessage> overlays,
  required List<V2TimMessage> formalMessages,
  required String owner,
  List<ChatAttachmentTask>? pendingTasks,
}) {
  if (!overlays
      .any((message) => (message.msgID ?? '').startsWith(_uploadPrefix))) {
    return overlays;
  }
  final currentTasks = pendingTasks == null
      ? null
      : {
          for (final task in pendingTasks)
            if (task.ownerUserId == owner && !task.terminal) task.taskId: task,
        };
  final references = <String>{};
  for (final message in formalMessages) {
    if (message.isSelf != true || message.sender != owner) continue;
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      try {
        final data = jsonDecode(message.cloudCustomData ?? '');
        if (data is Map &&
            data['type'] == 'chat.native-video' &&
            data['version'] == 1 &&
            data['attachmentId'] is String &&
            data['referenceId'] is String) {
          references.add('${data['attachmentId']}:${data['referenceId']}');
        }
      } catch (_) {}
    }
    final attachment = ChatAttachment.tryParse(message.customElem?.data);
    if (attachment != null) {
      references.add('${attachment.attachmentId}:${attachment.referenceId}');
    }
  }
  return overlays.where((message) {
    final data = _uploadData(message);
    if (data == null) return true;
    if (data['ownerUserId'] != owner) return false;
    final task = currentTasks?[data['taskId']];
    // The task can advance before the post-frame overlay publication. Consult
    // the live task snapshot to avoid even one frame of duplicate/newly cancelled rows.
    if (currentTasks != null && task == null) return false;
    return !references.contains(
        '${task?.attachmentId ?? data['attachmentId']}:${task?.referenceId ?? data['referenceId']}');
  }).toList(growable: false);
}
