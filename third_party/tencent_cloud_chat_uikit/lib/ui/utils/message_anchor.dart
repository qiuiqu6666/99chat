import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Stable anchor used by search jump. It intentionally contains only immutable
/// identifiers from the search result, so every entry point can pass the same
/// semantics to chat without depending on the current visible message list.
class MessageAnchor {
  const MessageAnchor({
    required this.conversationID,
    required this.convType,
    this.msgID,
    this.localID,
    this.seq,
    this.timestamp,
    this.sender,
    this.elemType,
  });

  final String conversationID;
  final int convType;
  final String? msgID;
  final String? localID;
  final String? seq;
  final int? timestamp;
  final String? sender;
  final int? elemType;

  static String? _clean(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static String conversationIDOf(V2TimConversation conversation) {
    final raw = _clean(conversation.conversationID);
    if (raw != null) {
      return raw;
    }
    final groupID = _clean(conversation.groupID);
    if (groupID != null) {
      return 'group_$groupID';
    }
    final userID = _clean(conversation.userID);
    if (userID != null) {
      return 'c2c_$userID';
    }
    return '';
  }

  factory MessageAnchor.fromConversationMessage(
    V2TimConversation conversation,
    V2TimMessage message,
  ) {
    return MessageAnchor(
      conversationID: conversationIDOf(conversation),
      convType: conversation.type ?? 1,
      msgID: _clean(message.msgID),
      localID: _clean(message.id),
      seq: _clean(message.seq),
      timestamp: message.timestamp,
      sender: _clean(message.sender) ?? _clean(message.userID),
      elemType: message.elemType,
    );
  }

  int? get seqInt {
    final value = seq;
    if (value == null || value.isEmpty) {
      return null;
    }
    return int.tryParse(value);
  }

  String get stableKey {
    final msg = msgID;
    if (msg != null && msg.isNotEmpty) return 'msg_$msg';
    final local = localID;
    if (local != null && local.isNotEmpty) return 'id_$local';
    final seqValue = seq;
    if (seqValue != null && seqValue.isNotEmpty) return 'seq_$seqValue';
    return '${sender ?? ''}_${timestamp ?? ''}_${elemType ?? ''}';
  }

  bool matches(V2TimMessage? message) {
    if (message == null || message.elemType == 11 || message.elemType == 101) {
      return false;
    }
    final targetID = _clean(msgID);
    final currentID = _clean(message.msgID);
    if (targetID != null && currentID != null) return targetID == currentID;

    // Only positive group sequences identify messages; C2C/unsent messages
    // commonly share seq=0, including multiple messages within one second.
    final targetSeq = seqInt;
    final currentSeq = int.tryParse(message.seq?.trim() ?? '');
    if (convType == 2 &&
        targetSeq != null &&
        targetSeq > 0 &&
        currentSeq != null &&
        currentSeq > 0) {
      return targetSeq == currentSeq;
    }

    final targetLocal = _clean(localID);
    final currentLocal = _clean(message.id);
    if (targetLocal != null && currentLocal != null) {
      return targetLocal == currentLocal;
    }
    if (targetID != null ||
        targetLocal != null ||
        (convType == 2 && targetSeq != null && targetSeq > 0)) {
      return false;
    }

    return timestamp != null &&
        timestamp == message.timestamp &&
        _clean(sender) != null &&
        _clean(sender) == (_clean(message.sender) ?? _clean(message.userID)) &&
        elemType != null &&
        elemType == message.elemType;
  }

  /// Loading neighbours is not evidence that the clicked message was found.
  bool isPresentIn(Iterable<V2TimMessage?> messages) => messages.any(matches);
}
