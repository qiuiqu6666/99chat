import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_list_result.dart';

/// C2C sequence numbers are not conversation-wide. Walk SDK pages from the
/// frozen entry message, counting received messages, without mounting pages.
class EntryUnreadLocator {
  static Future<V2TimMessage?> find({
    required int unreadCount,
    required V2TimMessage latestAtEntry,
    required Future<V2TimMessageListResult?> Function(V2TimMessage cursor)
        older,
    required bool Function() isCurrent,
  }) async {
    if (unreadCount <= 0 || (latestAtEntry.msgID?.isEmpty ?? true)) return null;
    var remaining = unreadCount;
    var cursor = latestAtEntry;
    final seen = <String>{};
    final visitedCursors = <String>{latestAtEntry.msgID!};
    final deadline = DateTime.now().add(const Duration(seconds: 24));
    V2TimMessage? consume(Iterable<V2TimMessage> messages) {
      for (final message in messages) {
        final id = message.msgID ?? '';
        if (id.isEmpty ||
            !seen.add(id) ||
            message.isSelf == true ||
            message.isExcludedFromUnreadCount == true ||
            message.elemType == 11 ||
            message.elemType == 101) {
          continue;
        }
        if (--remaining == 0) return message;
      }
      return null;
    }

    final immediate = consume([latestAtEntry]);
    if (immediate != null) return immediate;
    while (isCurrent() && DateTime.now().isBefore(deadline)) {
      final page = await older(cursor);
      if (!isCurrent() || page == null || page.messageList.isEmpty) return null;
      final target = consume(page.messageList);
      if (target != null) return target;
      final next = page.messageList.last;
      if (page.isFinished ||
          (next.msgID?.isEmpty ?? true) ||
          next.msgID == cursor.msgID ||
          !visitedCursors.add(next.msgID!)) {
        return null;
      }
      cursor = next;
    }
    return null;
  }
}
