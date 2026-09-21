import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'call_bubble_dedupe.dart';

/// Projects local business records into the SDK window already being read.
/// The overlay store remains intact; older records enter when pagination
/// reaches their time, or when the SDK confirms there are no older pages.
List<V2TimMessage> projectChatMessageOverlays({
  required List<V2TimMessage> formalMessages,
  required List<V2TimMessage> overlays,
  required bool olderHistoryExhausted,
  required bool includesLatestEdge,
  int dividerIntervalSeconds = 300,
}) {
  if (overlays.isEmpty) return formalMessages;
  final rows = formalMessages.where((m) => m.elemType != 11).toList();
  int? oldest;
  int? newest;
  for (final row in rows) {
    final timestamp = row.timestamp ?? 0;
    if (timestamp <= 0) continue;
    if (oldest == null || timestamp < oldest) oldest = timestamp;
    if (newest == null || timestamp > newest) newest = timestamp;
  }
  final visibleOverlays = overlays.where((row) {
    if (oldest == null || newest == null) {
      // A call-only chat has no SDK boundary to clip against. Keep its
      // business history stable when the user scrolls away from latest too.
      return true;
    }
    final timestamp = row.timestamp ?? 0;
    return timestamp > 0 &&
        (olderHistoryExhausted || timestamp >= oldest) &&
        (includesLatestEdge || timestamp <= newest);
  }).toList();
  if (visibleOverlays.isEmpty) return formalMessages;

  final merged = CallBubbleDedupe.prepareOpenHistoryMessages(
    GroupTipsMessageHelper.applyPostMergeFilters([...rows, ...visibleOverlays]),
  );
  // Call normalization preserves input order. Merely appending its result
  // puts the same old call at every page's tail instead of its actual time.
  final newestFirst = TUIChatGlobalModel.sortMessagesNewestFirst(merged);
  final chronological = TUIChatGlobalModel.attachTimeDividers(
    newestFirst.reversed.toList(growable: false),
    intervalSeconds: dividerIntervalSeconds,
  );
  return List<V2TimMessage>.unmodifiable(chronological.reversed);
}
