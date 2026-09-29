import 'dart:async';

/// One reusable short-sound lane. Ordinary bursts never build a playback queue;
/// a settings preview may replace the single pending preview.
class NotificationSoundPlayback {
  NotificationSoundPlayback({
    required this.canPlay,
    required this.prepare,
    required this.load,
    required this.rewind,
    required this.play,
    required this.onError,
    required this.onFinished,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final bool Function() canPlay;
  final Future<void> Function() prepare;
  final Future<void> Function(String asset) load;
  final Future<void> Function() rewind;
  final Future<void> Function() play;
  final Future<void> Function(Object error, StackTrace stack) onError;
  final void Function() onFinished;
  final int Function() _nowMs;
  String? _loadedAsset;
  String? _pendingPreview;
  int? _lastStartedAt;
  Future<void>? _running;

  Future<void> request(String asset, {bool force = false}) {
    if (!canPlay()) return Future<void>.value();
    final running = _running;
    if (running != null) {
      if (force) _pendingPreview = asset;
      return running;
    }
    final now = _nowMs();
    if (!force && _lastStartedAt != null && now - _lastStartedAt! < 800) {
      return Future<void>.value();
    }
    _lastStartedAt = now;
    final done = Completer<void>();
    _running = done.future;
    unawaited(_drain(asset).then((_) {
      _running = null;
      done.complete();
    }, onError: (Object error, StackTrace stack) {
      _running = null;
      done.completeError(error, stack);
    }));
    return done.future;
  }

  Future<void> _drain(String asset) async {
    String? next = asset;
    while (next != null && canPlay()) {
      try {
        await prepare();
        if (!canPlay()) break;
        if (_loadedAsset != next) {
          await load(next);
          _loadedAsset = next;
        }
        if (!canPlay()) break;
        await rewind();
        if (!canPlay()) break;
        await play();
      } catch (error, stack) {
        _loadedAsset = null;
        if (canPlay()) await onError(error, stack);
      } finally {
        onFinished();
      }
      next = _pendingPreview;
      _pendingPreview = null;
    }
    _pendingPreview = null;
  }
}
