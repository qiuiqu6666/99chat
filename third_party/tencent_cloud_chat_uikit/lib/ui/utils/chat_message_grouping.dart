import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Presentation only. Input is the projected newest-first message window.
class ChatMessageGrouping {
  static bool joins(V2TimMessage? older, V2TimMessage? newer) {
    if (!_ordinary(older) || !_ordinary(newer)) return false;
    final a = older!, b = newer!;
    if (a.groupID != b.groupID) return false;
    final sender = a.sender?.trim() ?? '';
    if (sender.isEmpty || sender != b.sender?.trim() || a.isSelf != b.isSelf) {
      return false;
    }
    final start = a.timestamp ?? 0, end = b.timestamp ?? 0;
    if (start <= 0 || end < start || end - start > 120) return false;
    final dayA = DateTime.fromMillisecondsSinceEpoch(start * 1000);
    final dayB = DateTime.fromMillisecondsSinceEpoch(end * 1000);
    return dayA.year == dayB.year &&
        dayA.month == dayB.month &&
        dayA.day == dayB.day;
  }

  static bool _ordinary(V2TimMessage? message) =>
      message != null &&
      !(message.cloudCustomData?.contains('isRevoke') ?? false) &&
      !(message.localCustomData?.contains('isRevoke') ?? false) &&
      message.status != MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED &&
      const {
        MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
        MessageElemType.V2TIM_ELEM_TYPE_SOUND,
        MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
        MessageElemType.V2TIM_ELEM_TYPE_FILE,
        MessageElemType.V2TIM_ELEM_TYPE_FACE,
      }.contains(message.elemType);
}
