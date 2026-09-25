import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// One trace per local media job. No file paths, recipients or message content.
/// SDK progress is only a milestone, not proof of message delivery.
class MediaSendPerf {
  MediaSendPerf._(this.mediaId);
  static final Map<String, MediaSendPerf> _active = {};
  static final Queue<Map<String, Object>> _recentEvents = Queue();
  static const bool _releaseConsole =
      bool.fromEnvironment('MEDIA_SEND_DIAGNOSTICS');
  static int _next = 0;

  /// Bounded, content-free snapshots remain available when release mutes logs.
  static List<Map<String, Object>> get recentEvents =>
      List.unmodifiable(_recentEvents);

  static MediaSendPerf begin(String? localId) {
    final existing = lookup(localId);
    if (existing != null) return existing;
    final trace = MediaSendPerf._('media_${++_next}');
    trace.bind(localId);
    return trace;
  }

  static MediaSendPerf? lookup(String? localId) => _active[localId];

  static Future<T> measureFor<T>(
      String? localId, String stage, Future<T> Function() work) {
    final trace = lookup(localId);
    return trace == null ? work() : trace.measure(stage, work);
  }

  final String mediaId;
  final Stopwatch _total = Stopwatch()..start();
  final Map<String, int> metrics = {};
  final Map<String, Object> _states = {};
  final Set<String> _keys = {};
  final Set<Timer> _stageTimers = {};
  int? _sdkStartedAtMs;
  bool _finished = false;

  void bind(String? localId) {
    if (localId == null || localId.isEmpty || _finished) return;
    _keys.add(localId);
    _active[localId] = this;
  }

  void record(String field, int value) {
    if (!_finished) metrics[field] = (metrics[field] ?? 0) + value;
  }

  /// All SDK/progress milestones use the media trace's start as their origin.
  void markSdkEnter(
      {required String connectionState, required bool handshakePending}) {
    if (_finished) return;
    _sdkStartedAtMs = _total.elapsedMilliseconds;
    metrics['sdkEnterMs'] = _sdkStartedAtMs!;
    metrics['uploadProgressCallbackCount'] = 0;
    _states['timingOrigin'] = 'media_start';
    _states['imConnectionStateAtSend'] = connectionState;
    _states['imHandshakePendingAtSend'] = handshakePending;
  }

  void markSdkReturn({required String connectionState}) {
    if (_finished) return;
    metrics['sdkReturnMs'] = _total.elapsedMilliseconds;
    _states['imConnectionStateAtReturn'] = connectionState;
    final upload100 = metrics['upload100Ms'];
    if (upload100 != null) {
      metrics['upload100ToSdkReturnMs'] = metrics['sdkReturnMs']! - upload100;
    }
  }

  Future<T> measure<T>(String stage, Future<T> Function() work) async {
    if (_finished) return work();
    final watch = Stopwatch()..start();
    if (stage == 'sdkUploadAndSend') {
      _sdkStartedAtMs = _total.elapsedMilliseconds;
    }
    // A stuck native Future never reaches finish(). Emit once while it is
    // pending, including in release builds, without timing out or resending it.
    late final Timer timer;
    timer = Timer(const Duration(seconds: 5), () {
      _stageTimers.remove(timer);
      if (!_finished) {
        _emit({
          'event': 'slow_stage',
          'stage': stage,
          'stageElapsedMs': watch.elapsedMilliseconds,
          'totalElapsedMs': _total.elapsedMilliseconds,
        });
      }
    });
    _stageTimers.add(timer);
    try {
      return await work();
    } finally {
      timer.cancel();
      _stageTimers.remove(timer);
      record('${stage}Ms', watch.elapsedMilliseconds);
    }
  }

  void observeUploadProgress(int progress) {
    if (_finished ||
        _sdkStartedAtMs == null ||
        progress < 0 ||
        metrics.containsKey('sdkReturnMs')) return;
    final elapsed = _total.elapsedMilliseconds;
    record('uploadProgressCallbackCount', 1);
    metrics.putIfAbsent('uploadFirstCallbackMs', () => elapsed);
    if (progress == 0) return;
    metrics.putIfAbsent('uploadFirstProgressMs', () => elapsed);
    final percent = progress.clamp(0, 100);
    if (percent > (metrics['uploadProgressPercent'] ?? 0)) {
      metrics['uploadProgressPercent'] = percent;
    }
    if (percent == 100) {
      metrics.putIfAbsent('upload100Ms', () => elapsed);
      // Retain the original duration metric for existing diagnostic readers.
      metrics.putIfAbsent(
          'uploadCompleteProgressMs', () => elapsed - _sdkStartedAtMs!);
    }
  }

  void _emit(Map<String, Object> event) {
    try {
      final snapshot = Map<String, Object>.unmodifiable({
        'mediaId': mediaId,
        ...event,
        ..._states,
        ...metrics,
      });
      if (_recentEvents.length >= 64) _recentEvents.removeFirst();
      _recentEvents.add(snapshot);
      if (!kReleaseMode) {
        debugPrint('[MediaSendPerf] ${jsonEncode(snapshot)}');
      } else if (_releaseConsole) {
        // Explicit diagnostic builds bypass the host's release print filter
        // for these numeric summaries only, never general application logs.
        Zone.root.print('[MediaSendPerf] ${jsonEncode(snapshot)}');
      }
    } catch (_) {
      // Diagnostics must not change the result of the media operation.
    }
  }

  void finish(String outcome) {
    if (_finished) return;
    record('totalMs', _total.elapsedMilliseconds);
    _finished = true;
    for (final timer in _stageTimers) {
      timer.cancel();
    }
    _stageTimers.clear();
    for (final key in _keys) {
      if (identical(_active[key], this)) _active.remove(key);
    }
    if (_releaseConsole ||
        !kReleaseMode ||
        metrics['totalMs']! >= 2000 ||
        outcome != 'success') {
      _emit({'event': 'complete', 'outcome': outcome});
    }
  }
}
