import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// Serializes incomplete SDK conversation lookups and shares one request per
/// conversation across overlapping realtime callbacks.
class ConversationPatchHydrator {
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  Future<void> _tail = Future<void>.value();

  static bool needsHydration(V2TimConversation patch) {
    final unread = patch.unreadCount;
    return unread == null || (unread > 0 && patch.lastMessage == null);
  }

  Future<void> hydrate(
    List<V2TimConversation> patches, {
    required bool Function() isCurrent,
    required void Function(V2TimConversation conversation) apply,
  }) async {
    final pending = <Future<void>>[];
    for (final patch in patches) {
      if (!isCurrent()) return;
      if (!needsHydration(patch)) continue;
      final rawId = patch.conversationID.trim();
      if (rawId.isEmpty) continue;
      final comparable = MessageConversationId.normalizeComparableKey(rawId);
      final key = comparable.isEmpty ? rawId : comparable;
      final existing = _inFlight[key];
      if (existing != null) {
        pending.add(existing);
        continue;
      }

      late final Future<void> task;
      task = _tail.then<void>((_) async {
        if (!isCurrent()) return;
        try {
          final result = await TencentImSDKPlugin.v2TIMManager
              .getConversationManager()
              .getConversation(conversationID: rawId);
          final full = result.data;
          if (full != null && isCurrent()) apply(full);
        } catch (_) {}
      }).whenComplete(() {
        if (identical(_inFlight[key], task)) _inFlight.remove(key);
      });
      _inFlight[key] = task;
      _tail = task.catchError((Object _) {});
      pending.add(task);
    }
    if (pending.isNotEmpty) await Future.wait<void>(pending);
  }

  void reset() {
    _inFlight.clear();
    _tail = Future<void>.value();
  }
}
