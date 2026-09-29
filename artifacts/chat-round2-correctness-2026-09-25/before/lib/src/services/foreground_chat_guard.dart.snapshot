import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';

/// 判断会话是否仍在聊天栈内，用于抑制列表未读 bump。
class ForegroundChatGuard {
  ForegroundChatGuard._();

  @visibleForTesting
  static bool Function(String? conversationId)? debugOverride;

  static bool isActiveConversation(String? conversationId) {
    final override = debugOverride;
    if (override != null) {
      return override(conversationId);
    }
    final id = conversationId?.trim() ?? '';
    if (id.isEmpty) {
      return false;
    }
    // 只有聊天页实际可见且应用在前台时才压制未读；进入资料页、切后台
    // 或路由被覆盖后，消息仍应正常产生列表未读和最后一条消息更新。
    return ActiveChatRegistry.instance.isActiveChatInForeground(id);
  }
}
