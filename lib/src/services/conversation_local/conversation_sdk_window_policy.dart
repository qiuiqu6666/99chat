import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

class ConversationSdkWindowResult {
  const ConversationSdkWindowResult({
    required this.rows,
    required this.trimmed,
    this.droppedFromStart = const <V2TimConversation>[],
    this.droppedFromEnd = const <V2TimConversation>[],
  });

  final List<V2TimConversation> rows;
  final bool trimmed;
  final List<V2TimConversation> droppedFromStart;
  final List<V2TimConversation> droppedFromEnd;
}

/// Keeps a bounded, time-contiguous SDK conversation window around the
/// visible row. Pinned and unread rows outside that slice are not spliced in.
abstract final class ConversationSdkWindowPolicy {
  static ConversationSdkWindowResult trimAroundAnchor(
    List<V2TimConversation> sorted, {
    required int type,
    String? viewportAnchorId,
  }) {
    final cap = ConversationPerfFlags.uiAppendOlderEmergencyMaxPerType;
    if (cap <= 0 || sorted.length <= cap) {
      return ConversationSdkWindowResult(rows: sorted, trimmed: false);
    }

    var anchorIndex = -1;
    final anchor = viewportAnchorId?.trim() ?? '';
    if (anchor.isNotEmpty) {
      for (var i = 0; i < sorted.length; i++) {
        if (MessageConversationId.sameConversation(
          sorted[i].conversationID,
          anchor,
        )) {
          anchorIndex = i;
          break;
        }
      }
    }
    if (anchorIndex < 0) anchorIndex = sorted.length - 1;

    var start = anchorIndex - cap ~/ 2;
    if (start < 0) start = 0;
    var end = start + cap;
    if (end > sorted.length) {
      end = sorted.length;
      start = end - cap;
    }

    final rows = sorted.sublist(start, end);
    final droppedFromStart =
        start > 0 ? List<V2TimConversation>.from(sorted.sublist(0, start)) : const <V2TimConversation>[];
    final droppedFromEnd = end < sorted.length
        ? List<V2TimConversation>.from(sorted.sublist(end))
        : const <V2TimConversation>[];
    ConversationPerfGateLog.log(
      'tab_store_window_trim',
      extras: <String, Object?>{
        'convType': type,
        'before': sorted.length,
        'after': rows.length,
        'anchor': anchor,
        'droppedHead': droppedFromStart.length,
        'droppedTail': droppedFromEnd.length,
      },
    );
    return ConversationSdkWindowResult(
      rows: rows,
      trimmed: true,
      droppedFromStart: droppedFromStart,
      droppedFromEnd: droppedFromEnd,
    );
  }
}
