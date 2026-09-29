import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';

/// Shared rules for outgoing message meta (time + delivery check).
class OutgoingMessageDisplay {
  OutgoingMessageDisplay._();

  /// Delivery/read check is shown only after SDK reports send success.
  /// Client-side [msgID] or status `0` must not imply success.
  static bool shouldShowDeliveryCheck({required int status}) {
    return status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
  }

  /// Group all-read: unread is 0 and at least one member has read.
  /// `readCount=0 && unreadCount=0` is not all-read.
  static bool isGroupAllRead({
    int? readCount,
    int? unreadCount,
  }) {
    return (unreadCount ?? 0) == 0 && (readCount ?? 0) > 0;
  }

  /// Double-check upgrade. Requires a delivery check first; never creates ✓.
  static bool shouldShowReadUpgrade({
    required int status,
    bool isC2cPeerRead = false,
    int? groupReadCount,
    int? groupUnreadCount,
  }) {
    if (!shouldShowDeliveryCheck(status: status)) {
      return false;
    }
    if (isC2cPeerRead) {
      return true;
    }
    return isGroupAllRead(
      readCount: groupReadCount,
      unreadCount: groupUnreadCount,
    );
  }
}
