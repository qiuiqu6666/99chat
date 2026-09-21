import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

/// 消息历史统一由腾讯 IM SDK 提供。
///
/// 保留这个纯过滤工具供旧的测试/兼容代码使用；Community 不再有静默
/// 归档补拉调度器或自建后端正文读取路径。
class SilentArchiveService {
  SilentArchiveService._();

  static bool _archiveMessageStrictlyOlder(
    V2TimMessage message,
    V2TimMessage before,
  ) {
    if (TUIChatGlobalModel.messagesCorrelateForDedup(message, before)) {
      return false;
    }
    final messageSeq = int.tryParse(message.seq ?? '');
    final beforeSeq = int.tryParse(before.seq ?? '');
    if (messageSeq != null &&
        beforeSeq != null &&
        messageSeq > 0 &&
        beforeSeq > 0) {
      return messageSeq < beforeSeq;
    }
    return (message.timestamp ?? 0) < (before.timestamp ?? 0);
  }

  /// 去掉已在当前窗内的消息，以及不比锚点更旧的归档重叠段。
  static List<V2TimMessage> filterArchiveSupplement({
    required List<V2TimMessage> candidates,
    required List<V2TimMessage>? existing,
    required V2TimMessage? oldestAnchor,
  }) {
    if (candidates.isEmpty) {
      return const <V2TimMessage>[];
    }
    return candidates.where((message) {
      if (existing != null && existing.isNotEmpty) {
        for (final kept in existing) {
          if (TUIChatGlobalModel.messagesCorrelateForDedup(message, kept)) {
            return false;
          }
        }
      }
      if (oldestAnchor != null &&
          !_archiveMessageStrictlyOlder(message, oldestAnchor)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}
