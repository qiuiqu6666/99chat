import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

import 'chat_media_send_utils.dart';

/// Only a newly inserted local gallery batch may bypass insertion animation.
/// Synced history, completed sends and unrelated single sends retain their
/// normal viewport behavior.
bool isNewOutgoingImageBatch(Iterable<V2TimMessage> insertedMessages) {
  final idsByBatch = <String, Set<String>>{};
  for (final message in insertedMessages) {
    if (message.isSelf != true ||
        message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        message.status != MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      continue;
    }
    final batch = readChatMediaBatchId(message);
    final stableId = readOutgoingStableId(message);
    if (batch == null || stableId == null) {
      continue;
    }
    final ids = idsByBatch.putIfAbsent(batch, () => <String>{});
    ids.add(stableId);
    if (ids.length >= 2) {
      return true;
    }
  }
  return false;
}
