import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Candidates are ordered by authority; equal timestamps keep the live row.
V2TimMessage? latestChatPreview({
  required Iterable<V2TimMessage?> candidates,
  required int clearedAtMs,
  required int Function(V2TimMessage?) timestampMs,
}) {
  V2TimMessage? latest;
  for (final message in candidates) {
    if (message == null) continue;
    final timestamp = timestampMs(message);
    if (clearedAtMs > 0 && timestamp <= clearedAtMs) continue;
    if (latest == null || timestamp > timestampMs(latest)) latest = message;
  }
  return latest;
}
