import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

/// Profile 默认开启未读诊断；可用 IM_UNREAD_TRACE 显式覆盖。
class ConversationUnreadTrace {
  ConversationUnreadTrace._();

  static const bool enabled =
      bool.fromEnvironment('IM_UNREAD_TRACE', defaultValue: kProfileMode);
  static const _tag = 'UnreadTrace';

  static void log(
    String event, {
    String? conversationID,
    int? unreadBefore,
    int? unreadAfter,
    Map<String, Object?> extras = const {},
  }) {
    if (!enabled) {
      return;
    }
    debugPrint(
      formatLineForTest(
        event,
        conversationID: conversationID,
        unreadBefore: unreadBefore,
        unreadAfter: unreadAfter,
        extras: {'atMs': DateTime.now().millisecondsSinceEpoch, ...extras},
      ),
    );
  }

  static void logConversations(
    String event, {
    required List<V2TimConversation> conversations,
    Map<String, Object?> extras = const {},
  }) {
    if (!enabled) {
      return;
    }
    for (final conversation in conversations) {
      log(
        event,
        conversationID: conversation.conversationID,
        unreadAfter: conversation.unreadCount,
        extras: {
          ...extras,
          'messageSeq': conversation.lastMessage?.seq,
          'messageTimestamp': conversation.lastMessage?.timestamp,
        },
      );
    }
  }

  @visibleForTesting
  static String formatLineForTest(
    String event, {
    String? conversationID,
    int? unreadBefore,
    int? unreadAfter,
    Map<String, Object?> extras = const {},
  }) {
    final buffer = StringBuffer('$_tag event=$event');
    final id = conversationID?.trim() ?? '';
    if (id.isNotEmpty) {
      buffer.write(' conv=$id');
    }
    if (unreadBefore != null) {
      buffer.write(' unreadBefore=$unreadBefore');
    }
    if (unreadAfter != null) {
      buffer.write(' unreadAfter=$unreadAfter');
    }
    for (final entry in extras.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      buffer.write(' ${entry.key}=$value');
    }
    return buffer.toString();
  }
}

/// 多选「标记已读」诊断的兼容入口；不向控制台输出。
class MarkSelectedReadLog {
  MarkSelectedReadLog._();

  static const bool enabled = false;
  static const int _idSampleLimit = 40;

  static void log(String message, [Map<String, Object?> extras = const {}]) {}

  static String summarizeIds(Iterable<String> ids,
      {int limit = _idSampleLimit}) {
    final list = ids.where((e) => e.trim().isNotEmpty).toList();
    if (list.isEmpty) {
      return '(none)';
    }
    if (list.length <= limit) {
      return list.join(',');
    }
    final head = list.take(limit).join(',');
    return '$head,...(+${list.length - limit})';
  }

  static String summarizeUnread(
    List<V2TimConversation> conversations, {
    int limit = _idSampleLimit,
  }) {
    final parts = <String>[];
    for (final conversation in conversations) {
      if (parts.length >= limit) {
        parts.add('...(+${conversations.length - limit})');
        break;
      }
      final id = conversation.conversationID.trim();
      if (id.isEmpty) {
        continue;
      }
      parts.add('$id:${conversation.unreadCount ?? 0}');
    }
    return parts.isEmpty ? '(none)' : parts.join(',');
  }
}
