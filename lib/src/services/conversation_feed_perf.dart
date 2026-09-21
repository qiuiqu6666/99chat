import 'package:flutter/foundation.dart';

/// Low-overhead, one-line-per-second counters for conversation-feed work.
///
/// The hot paths only update in-memory integers. A summary is emitted when the
/// next event crosses the one-second boundary, avoiding a periodic timer and
/// per-message logging pressure.
class ConversationFeedPerf {
  ConversationFeedPerf._();

  static const int _windowDurationMs = 1000;

  @visibleForTesting
  static bool? debugEnabledOverride;

  @visibleForTesting
  static void Function(String line)? debugSink;

  @visibleForTesting
  static int Function()? debugNowMillis;

  static bool get isEnabled =>
      debugEnabledOverride ?? (kDebugMode || kProfileMode);

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, int> _counters = <String, int>{};
  static final Map<String, int> _gauges = <String, int>{};
  static int _windowStartMs = -1;

  static void increment(
    String metric, {
    int amount = 1,
    String? reason,
  }) {
    if (!isEnabled || amount <= 0) return;
    _rollWindow();
    _add(_safeLabel(metric), amount);
    final normalizedReason = reason?.trim() ?? '';
    if (normalizedReason.isNotEmpty) {
      _add('${_safeLabel(metric)}_${_safeLabel(normalizedReason)}', amount);
    }
  }

  static void gauge(String metric, int value) {
    if (!isEnabled) return;
    _rollWindow();
    _gauges[_safeLabel(metric)] = value;
  }

  static void recordRowRetention({
    required String event,
    required String conversationKeyHash,
    required int timestamp,
    required int activeRowCount,
    required int keepAliveCount,
  }) {
    if (!isEnabled) return;
    increment(event);
    gauge('activeRowCount', activeRowCount);
    gauge('keepAliveCount', keepAliveCount);
    final line =
        '[FeedPerf] event=$event conversationKeyHash=$conversationKeyHash '
        'timestamp=$timestamp activeRowCount=$activeRowCount '
        'keepAliveCount=$keepAliveCount';
    final sink = debugSink;
    if (sink != null) {
      sink(line);
    } else {
      debugPrint(line);
    }
  }

  static void recordDurationMicros(String metric, int elapsedMicros) {
    if (!isEnabled) return;
    _rollWindow();
    final safeMetric = _safeLabel(metric);
    final safeMicros = elapsedMicros < 0 ? 0 : elapsedMicros;
    _add('${safeMetric}_samples', 1);
    _add('${safeMetric}_us', safeMicros);
    final maxKey = '${safeMetric}_usMax';
    final currentMax = _counters[maxKey] ?? 0;
    if (safeMicros > currentMax) {
      _counters[maxKey] = safeMicros;
    }
  }

  static Map<String, int> snapshot() => Map<String, int>.unmodifiable(
        <String, int>{..._counters, ..._gauges},
      );

  @visibleForTesting
  static void flushForTest() {
    if (!isEnabled) return;
    _emitWindow(_nowMs());
  }

  @visibleForTesting
  static void resetForTest() {
    _counters.clear();
    _gauges.clear();
    _windowStartMs = -1;
    debugNowMillis = null;
  }

  static void _add(String metric, int amount) {
    _counters[metric] = (_counters[metric] ?? 0) + amount;
  }

  static void _rollWindow() {
    final now = _nowMs();
    if (_windowStartMs < 0) {
      _windowStartMs = now;
      return;
    }
    if (now - _windowStartMs < _windowDurationMs) return;
    _emitWindow(now);
  }

  static void _emitWindow(int now) {
    if (_windowStartMs < 0) {
      _windowStartMs = now;
      return;
    }
    final elapsed = now - _windowStartMs;
    if (_counters.isEmpty && _gauges.isEmpty) {
      _windowStartMs = now;
      return;
    }
    final fields = <String>['[FeedPerf]', 'windowMs=$elapsed'];
    final counterKeys = _counters.keys.toList()..sort();
    for (final key in counterKeys) {
      fields.add('$key=${_counters[key]}');
    }
    final gaugeKeys = _gauges.keys.toList()..sort();
    for (final key in gaugeKeys) {
      fields.add('$key=${_gauges[key]}');
    }
    final line = fields.join(' ');
    final sink = debugSink;
    if (sink != null) {
      sink(line);
    } else {
      debugPrint(line);
    }
    _counters.clear();
    _windowStartMs = now;
  }

  static int _nowMs() => debugNowMillis?.call() ?? _clock.elapsedMilliseconds;

  static String _safeLabel(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return sanitized.length <= 48 ? sanitized : sanitized.substring(0, 48);
  }
}
