import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';

/// 离页草稿时序打点。正文与 conversationId 只打 hash / length。
class ConversationDraftLeaveTrace {
  ConversationDraftLeaveTrace._();

  static const Duration _focusWindow = Duration(seconds: 8);

  static const Set<String> _allowedExtras = <String>{
    'source',
    'generation',
    'suppress',
    'reason',
    'code',
    'disposition',
    'shouldNotifyUi',
    'upserted',
    'explicitDraft',
    'projectedEmpty',
    'persistedEmpty',
    'overlayEmpty',
    'willExplicit',
    'patched',
    'editing',
    'hasOpenChat',
    'draftLen',
  };

  static String _focusedId = '';
  static DateTime? _focusedAt;

  @visibleForTesting
  static Map<String, Object?> lastLineForTest = <String, Object?>{};

  static void focus(String conversationId) {
    _focusedId = conversationId.trim();
    _focusedAt = DateTime.now();
  }

  static bool isFocused(String conversationId) {
    if (_focusedId.isEmpty || _focusedAt == null) {
      return false;
    }
    if (DateTime.now().difference(_focusedAt!) >= _focusWindow) {
      return false;
    }
    return MessageConversationId.sameConversation(_focusedId, conversationId);
  }

  static int _draftLen(String? draftText) {
    if (draftText == null) {
      return -1;
    }
    return draftText.trim().length;
  }

  static void stage(
    String name, {
    String conversationId = '',
    String? draftText,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    final draftLen = _draftLen(draftText);
    final draftHash =
        draftText == null ? '' : ConversationPerfGateLog.textHash(draftText);
    final filtered = <String, Object?>{};
    for (final entry in extras.entries) {
      if (_allowedExtras.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    final line = <String, Object?>{
      'stage': name,
      't': DateTime.now().millisecondsSinceEpoch,
      'conv': ConversationPerfGateLog.conversationKeyHash(conversationId),
      'draftLen': draftLen,
      'draftHash': draftHash,
      'empty': draftLen == 0,
      ...filtered,
    };
    lastLineForTest = line;
    if (!kDebugMode || !ConversationPerfFlags.draftLeaveTraceEnabled) {
      return;
    }
    ConversationPerfGateLog.log(name, extras: line);
    final extraText = filtered.isEmpty
        ? ''
        : ' ${filtered.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint(
      '[DraftLeaveTrace] stage=$name t=${line['t']} conv=${line['conv']} '
      'draftLen=$draftLen draftHash=$draftHash empty=${draftLen == 0}'
      '$extraText',
    );
  }
}
