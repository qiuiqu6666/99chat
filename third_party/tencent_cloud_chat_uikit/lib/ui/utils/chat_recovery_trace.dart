import 'dart:collection';
import 'dart:async';
import 'dart:developer' as developer;

/// Low-volume operation diagnostics, including in release builds. Never pass
/// message bodies, SDK payloads, credentials or file URLs here.
class ChatRecoveryTrace {
  static final _events = Queue<String>();
  static int _sequence = 0;
  static final _revokeFrames = <String, String>{};
  static const capacity = 200;
  static final Stopwatch _processClock = Stopwatch()..start();

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
      ..write(' schema=CHAT_TRACE')
      ..write(' monoUs=${_processClock.elapsedMicroseconds}')
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

/// Observes queue ownership without introducing deadlines or cancellation.
/// One shared watchdog; the registry and the event ring are both bounded.
class ChatTraceOperation {
  ChatTraceOperation(this.queueName,
      {this.conversationID = '',
      this.generation = 0,
      this.stallAfter = const Duration(seconds: 5)})
      : operationID = ChatRecoveryTrace.nextOperation(queueName) {
    _pending[operationID] = this;
    while (_pending.length > 256) {
      _pending.remove(_pending.keys.first);
    }
    _emit('enqueue');
    _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
      for (final op in _pending.values.toList(growable: false)) {
        if (!op._reportedStall && op.elapsed.elapsed >= op.stallAfter) {
          op._reportedStall = true;
          op._emit('stall');
        }
      }
    });
  }
  static final _pending = <String, ChatTraceOperation>{};
  static Timer? _watchdog;
  final String queueName, conversationID, operationID;
  final int generation;
  final Duration stallAfter;
  final Stopwatch elapsed = Stopwatch()..start();
  final Stopwatch stageElapsed = Stopwatch()..start();
  String stage = 'queued';
  String? nativeRequestID;
  bool _finished = false;
  bool _reportedStall = false;

  void enter(String next, {String? nativeRequest}) {
    if (_finished) return;
    stage = next;
    stageElapsed.reset();
    _reportedStall = false;
    nativeRequestID = nativeRequest;
    _emit(next == 'start' ? 'start' : 'stage');
  }

  void finish({Object? error}) {
    if (_finished) return;
    _emit(error == null ? 'finish' : 'fail', error: error);
    _finished = true;
    elapsed.stop();
    _pending.remove(operationID);
    if (_pending.isEmpty) {
      _watchdog?.cancel();
      _watchdog = null;
    }
  }

  void _emit(String event, {Object? error}) {
    final queue = _pending.values.where((op) => op.queueName == queueName);
    final oldest = queue.fold<int>(
        0,
        (age, op) => op.elapsed.elapsedMilliseconds > age
            ? op.elapsed.elapsedMilliseconds
            : age);
    ChatRecoveryTrace.log('queue_$event',
        conversationID: conversationID,
        operation: operationID,
        fields: {
          'operationID': operationID,
          'queueName': queueName,
          'stage': stage,
          'depth': queue.length,
          'oldestAge': oldest,
          'nativeRequestID': nativeRequestID,
          'generation': generation,
          'elapsed': elapsed.elapsedMilliseconds,
          'stageElapsedMs': stageElapsed.elapsedMilliseconds,
          if (error != null) 'errorType': error.runtimeType,
        });
  }
}
