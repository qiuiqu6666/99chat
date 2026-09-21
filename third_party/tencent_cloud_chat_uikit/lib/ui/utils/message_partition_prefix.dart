import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// A longer display list can append to cached Sliver partitions only when
/// every previously published row still occupies the same position.
/// [unread] is reversed by the upper Sliver; [read] is newest-first.
bool retainsMessagePartitionPrefix({
  required List<V2TimMessage?> current,
  required List<V2TimMessage?> unread,
  required List<V2TimMessage?> read,
}) {
  final previousLength = unread.length + read.length;
  if (current.length <= previousLength) return false;
  for (var index = 0; index < previousLength; index++) {
    final previous = index < unread.length
        ? unread[unread.length - index - 1]
        : read[index - unread.length];
    final next = current[index];
    if (identical(previous, next)) continue;
    // Rebuilt time dividers with the same timestamp have identical content.
    // SDK/business rows must retain their object too, or the old partition
    // would hide a replaced/edited payload despite an unchanged message ID.
    if (previous?.elemType == 11 &&
        next?.elemType == 11 &&
        previous!.timestamp == next!.timestamp) {
      continue;
    }
    return false;
  }
  return true;
}
