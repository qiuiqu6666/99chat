import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// E10（v15/v16）：首屏位置审计——观测 `scrollToSpecificMessage` /
/// `locateMessage` 是否被使用。
///
/// 设计：
///   - 这些 UIKit 帮助方法用于「点击消息外链 / @ 提醒跳转到指定消息」。
///   - 我们项目把外链入口放进 chat page，使用前先打点，便于验证「跳转能力是否被
///     真正消费」以及「若没有使用，是否可以下线」。
///   - audit 阶段只观测不修改，绝不拦截调用路径。
class ConversationFirstScreenLocatorAudit {
  ConversationFirstScreenLocatorAudit._();

  static final ConversationFirstScreenLocatorAudit instance =
      ConversationFirstScreenLocatorAudit._();

  static const String _tagScrollToSpecificMessage =
      'locate_scroll_to_specific_message';
  static const String _tagLocateMessage = 'locate_locate_message';
  static const String _tagChatPageOpened = 'locate_chat_page_opened';

  /// 用户从外链打开某条具体消息时调用。
  void recordScrollToSpecificMessage({
    required String conversationId,
    required String targetMsgId,
    String? reason,
  }) {
    if (!ConversationPerfFlags.firstScreenLocateAuditEnabled) return;
    StartupPerfLog.markTagged(
      _tagScrollToSpecificMessage,
      category: 'chat_locate',
      details: <String, Object>{
        'conversationId': conversationId,
        'targetMsgId': targetMsgId,
        'reason': reason ?? '',
      },
    );
  }

  /// UIKit `locateMessage` 调用入口审计。
  void recordLocateMessage({
    required String conversationId,
    required int indexHint,
    String? reason,
  }) {
    if (!ConversationPerfFlags.firstScreenLocateAuditEnabled) return;
    StartupPerfLog.markTagged(
      _tagLocateMessage,
      category: 'chat_locate',
      details: <String, Object>{
        'conversationId': conversationId,
        'indexHint': indexHint,
        'reason': reason ?? '',
      },
    );
  }

  /// 进入聊天页时调用一次（用于交叉对比「打开了但未做跳转」的比例）。
  void recordChatPageOpened({required String conversationId}) {
    if (!ConversationPerfFlags.firstScreenLocateAuditEnabled) return;
    StartupPerfLog.markTagged(
      _tagChatPageOpened,
      category: 'chat_locate',
      details: <String, Object>{
        'conversationId': conversationId,
      },
    );
  }
}
