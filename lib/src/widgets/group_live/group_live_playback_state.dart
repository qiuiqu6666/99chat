import 'dart:async';

import 'package:flutter/material.dart';

/// Live streams cannot seek. Keep transport diagnostics separate from UI errors.
class GroupLivePlaybackState extends ChangeNotifier {
  GroupLivePlaybackState({
    required Future<void> Function(String) openUrl,
    required Future<void> Function() pause,
    required Stream<String> errors,
    required Stream<Duration> positions,
    required Stream<bool> completed,
  })  : _openUrl = openUrl,
        _pause = pause {
    _subscriptions.add(errors.listen((message) {
      final diagnostic = message.trim();
      if (diagnostic.isEmpty ||
          diagnostic == 'Cannot seek in this stream.' ||
          diagnostic == "You can force it with '--force-seekable=yes'.") {
        return;
      }
      _setError('直播播放异常，请重试');
    }));
    _subscriptions.add(positions.listen((position) {
      // open()/playing=true only acknowledge a command, not successful playback.
      if (position > _lastPosition) _setError(null);
      _lastPosition = position;
    }));
    _subscriptions.add(completed.listen((value) {
      if (value) _setError('直播已结束或连接中断，请重试');
    }));
  }

  final Future<void> Function(String) _openUrl;
  final Future<void> Function() _pause;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _pending = Future<void>.value();
  String _url = '';
  String? _error;
  Duration _lastPosition = Duration.zero;
  bool _disposed = false;
  bool _background = false;
  int _generation = 0;
  String? get error => _error;

  void _setError(String? value) {
    if (_disposed || _error == value) return;
    _error = value;
    notifyListeners();
  }

  Future<void> open(String url) {
    _url = url.trim();
    return retry();
  }

  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    final url = _url;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      _setError('直播地址无效');
      return Future<void>.value();
    }
    _setError(null);
    // Serialize native commands; superseded requests must not reopen an old URL.
    _pending = _pending.then((_) async {
      if (_disposed || generation != _generation || _background) return;
      _lastPosition = Duration.zero;
      try {
        await _openUrl(url);
      } catch (_) {
        if (generation == _generation) _setError('直播连接失败，请重试');
      }
    });
    return _pending;
  }

  Future<void> pause() {
    if (_disposed) return Future<void>.value();
    _background = true;
    ++_generation;
    _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        await _pause();
      } catch (_) {
        _setError('直播暂停失败，请重试');
      }
    });
    return _pending;
  }

  Future<void> resume() {
    if (!_background || _disposed) return Future<void>.value();
    _background = false;
    // Player.play() seeks to zero after EOF; reopen to join the live edge.
    return retry();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

class GroupLivePlaybackError extends StatelessWidget {
  const GroupLivePlaybackError(
      {super.key, required this.playback, this.onRetry});
  final GroupLivePlaybackState playback;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (playback.error == null) return const SizedBox.shrink();
    return Center(
      child: ColoredBox(
        color: Colors.black54,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(playback.error!,
                  style: const TextStyle(color: Colors.white)),
              TextButton(
                onPressed: onRetry ?? () => unawaited(playback.retry()),
                child: const Text('重新连接'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
