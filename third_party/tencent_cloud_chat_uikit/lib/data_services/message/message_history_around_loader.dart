import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';

typedef AroundHistoryRead = Future<V2TimMessageListResult?> Function(
  HistoryMsgGetTypeEnum getType, {
  required int lastMsgSeq,
  String? lastMsgID,
  V2TimMessage? lastMsg,
});

/// Loads one side of a target window without walking from the latest page.
class MessageHistoryAroundLoader {
  static Future<V2TimMessageListResult?> loadSide({
    required AroundHistoryRead read,
    required bool isGroup,
    required bool newer,
    required int targetSeq,
    required String? targetMsgID,
    required V2TimMessage? targetMessage,
    Duration cloudTimeout = const Duration(seconds: 4),
    Duration localTimeout = const Duration(seconds: 2),
  }) async {
    // lastMsgSeq is a group-only cursor. C2C must retain the full SDK message.
    final seq = isGroup && targetSeq > 0 ? targetSeq : -1;
    if (seq <= 0 && (targetMsgID == null || targetMsgID.isEmpty)) {
      return null;
    }
    Future<V2TimMessageListResult?> fetch(
        HistoryMsgGetTypeEnum type, Duration timeout) async {
      try {
        return await read(
          type,
          lastMsgSeq: seq,
          lastMsgID: seq > 0 ? null : targetMsgID,
          lastMsg: seq > 0 ? null : targetMessage,
        ).timeout(timeout);
      } catch (_) {
        // Native callback failures and missing callbacks must both release the
        // search UI. The other source can still have this exact cursor.
        return null;
      }
    }

    final cloud = await fetch(
        newer
            ? HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG
            : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
        cloudTimeout);
    if (cloud != null &&
        (cloud.messageList.isNotEmpty || cloud.isFinished == true)) {
      return cloud;
    }
    // An unavailable cloud page may have an SDK-local copy at the same anchor.
    return await fetch(
            newer
                ? HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
                : HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
            localTimeout) ??
        cloud;
  }
}
