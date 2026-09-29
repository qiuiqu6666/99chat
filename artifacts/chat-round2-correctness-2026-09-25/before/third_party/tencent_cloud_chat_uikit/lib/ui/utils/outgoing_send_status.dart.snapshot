import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';

/// Outgoing send-state machine. Success is created only by a final send
/// result (`code == 0`) or by reconciling SENDING/UNKNOWN with an
/// SDK-confirmed `SEND_SUCC`. Local `SEND_FAIL` cannot be lifted by echo.
class OutgoingSendStatus {
  OutgoingSendStatus._();

  static const int unconfirmed = 0;

  static bool isUnconfirmed(int? status) =>
      status == null || status == unconfirmed;

  /// Display/live status. Never treats empty status or a client `msgID` as
  /// success. [msgID] is accepted only so callers cannot "fix" SENDING by
  /// passing an id — it is ignored.
  static int normalize({
    required int? status,
    int? fallback,
    String? msgID,
  }) {
    final resolved = status ?? fallback ?? unconfirmed;
    if (resolved == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC ||
        resolved == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL ||
        resolved == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      return resolved;
    }
    return unconfirmed;
  }

  /// Self-message merge.
  ///
  /// Rule 1: local `SEND_FAIL` becomes `SEND_SUCC` only when
  /// [fromFinalSendSuccess] is true (final `sendMessage` `code == 0`).
  /// Rule 2: `SENDING` / UNKNOWN plus incoming `SEND_SUCC` may reconcile
  /// to success. These rules must not be combined.
  static int mergeSelf({
    required int? previous,
    required int? incoming,
    bool fromFinalSendSuccess = false,
  }) {
    if (previous == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      if (fromFinalSendSuccess) {
        return MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
      }
      return MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (incoming == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      return MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    }
    if (incoming == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      return MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    }
    if (previous == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) {
      return MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    }
    if (incoming == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
        previous == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
      return MessageStatus.V2TIM_MSG_STATUS_SENDING;
    }
    return unconfirmed;
  }
}
