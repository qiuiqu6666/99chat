import 'dart:collection';
import 'dart:developer' as developer;

/// Low-volume operation diagnostics, including in release builds. Never pass
/// message bodies, SDK payloads, credentials or file URLs here.
class ChatRecoveryTrace {
  static final _events = Queue<String>();
  static int _sequence = 0;
  static final _revokeFrames = <String, String>{};
  static const capacity = 200;

  /// The host owns persistence. A diagnostics failure must never escape into
  /// the chat operation that produced the event.
  static void Function(String)? sink;
  static final _run = DateTime.now().toUtc().microsecondsSinceEpoch.toString();

  static String nextOperation(String name) => '$name-${++_sequence}';

  static List<String> get recentEvents => List.unmodifiable(_events);

  static bool get hasPendingRevokeFrames => _revokeFrames.isNotEmpty;

  static String _rowKey(String conversation, String message) =>
      '${conversation.replaceFirst(RegExp(r'^(c2c_|group_)'), '')}|$message';

  static void expectRevokeFrame(
      String conversation, String message, String operation) {
    _revokeFrames[_rowKey(conversation, message)] = operation;
    while (_revokeFrames.length > capacity) {
      _revokeFrames.remove(_revokeFrames.keys.first);
    }
  }

  static String? takeRevokeFrame(String conversation, String message) =>
      _revokeFrames.remove(_rowKey(conversation, message));

  static void log(
    String event, {
    required String conversationID,
    String? operation,
    String? messageID,
    Map<String, Object?> fields = const {},
  }) {
    String safe(Object? value) {
      var text = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
      text = text.replaceAll(RegExp(r'https?://\S+'), '<url>');
      text = text.replaceAll(
          RegExp(r'(token|userSig|authorization|password|secret)\s*[:=]\s*\S+',
              caseSensitive: false),
          '<credential>');
      return text.length <= 256 ? text : '${text.substring(0, 253)}...';
    }

    final line = StringBuffer('[ChatRecovery] event=${safe(event)} run=$_run')
      ..write(' time=${DateTime.now().toUtc().toIso8601String()}')
      ..write(' conv=${safe(conversationID)}');
    if (operation != null) line.write(' op=${safe(operation)}');
    if (messageID != null) line.write(' msg=${safe(messageID)}');
    fields.entries.take(16).forEach((entry) {
      final private = RegExp(
              r'token|sig|password|secret|body|payload|content|url',
              caseSensitive: false)
          .hasMatch(entry.key);
      line.write(
          ' ${safe(entry.key)}=${private ? '<redacted>' : safe(entry.value)}');
    });
    final text = line.toString();
    final bounded =
        text.length <= 2048 ? text : '${text.substring(0, 2045)}...';
    _events.addLast(bounded);
    while (_events.length > capacity) {
      _events.removeFirst();
    }
    developer.log(bounded, name: 'ninechat.recovery');
    try {
      sink?.call(bounded);
    } catch (_) {
      // Logging is never part of the success/failure of a message operation.
    }
  }
}
