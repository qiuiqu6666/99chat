import 'package:flutter/foundation.dart';

/// Temporary opt-in diagnostics. Never includes media URLs or local paths.
class ChatCoverDiag {
  static const enabled = bool.fromEnvironment('CHAT_COVER_DIAG');
  static const maxLines = 1200;
  static final Stopwatch _clock = Stopwatch()..start();
  static int _lines = 0;
  static final Set<String> _once = <String>{};

  static bool get canLog => enabled && _lines < maxLines;

  static void log(String stage, String id, String details) {
    if (!canLog) return;
    _lines++;
    debugPrint('[CoverDiag] t=${DateTime.now().millisecondsSinceEpoch} '
        'elapsed=${_clock.elapsedMilliseconds} stage=$stage id=$id $details');
  }

  /// Returns true only for the first accepted occurrence. Callers can use this
  /// to avoid rescheduling frame diagnostics on every rebuild.
  static bool logOnce(String stage, String id, String details) {
    if (!canLog || !_once.add('$stage|$id')) return false;
    log(stage, id, details);
    return true;
  }

  @visibleForTesting
  static int get debugRetainedKeyCount => _once.length;

  @visibleForTesting
  static void debugReset() {
    _lines = 0;
    _once.clear();
  }
}
