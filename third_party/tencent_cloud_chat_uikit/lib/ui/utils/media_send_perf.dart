import 'dart:convert';
import 'package:flutter/foundation.dart';

/// One trace per local media job. No file paths, recipients or message content.
/// Native send includes upload: separate network/send timings are not observable.
class MediaSendPerf {
  MediaSendPerf._(this.mediaId);
  static final Map<String, MediaSendPerf> _active = {};
  static int _next = 0;

  static MediaSendPerf begin(String? localId) {
    final existing = lookup(localId);
    if (existing != null) return existing;
    final trace = MediaSendPerf._('media_${++_next}');
    trace.bind(localId);
    return trace;
  }

  static MediaSendPerf? lookup(String? localId) => _active[localId];
  final String mediaId;
  final Stopwatch _total = Stopwatch()..start();
  final Map<String, int> metrics = {};
  final Set<String> _keys = {};
  bool _finished = false;

  void bind(String? localId) {
    if (localId == null || localId.isEmpty || _finished) return;
    _keys.add(localId);
    _active[localId] = this;
  }

  void record(String field, int value) {
    if (!_finished) metrics[field] = (metrics[field] ?? 0) + value;
  }

  Future<T> measure<T>(String stage, Future<T> Function() work) async {
    final watch = Stopwatch()..start();
    try {
      return await work();
    } finally {
      record('${stage}Ms', watch.elapsedMilliseconds);
    }
  }

  void finish(String outcome) {
    if (_finished) return;
    record('totalMs', _total.elapsedMilliseconds);
    _finished = true;
    for (final key in _keys) {
      if (identical(_active[key], this)) _active.remove(key);
    }
    if (!kReleaseMode) {
      debugPrint('[MediaSendPerf] ${jsonEncode({
            'mediaId': mediaId,
            'outcome': outcome,
            ...metrics,
          })}');
    }
  }
}
