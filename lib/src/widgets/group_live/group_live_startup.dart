import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';

/// Only protocols supported by the installed HTTP player. Never send WebRTC
/// signalling URLs to media_kit, even when the signalling endpoint uses HTTPS.
List<String> groupLiveHttpSources(GroupLivePlayInfo info) {
  final result = <String>[];
  void add(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !result.contains(value)) {
      result.add(value);
    }
  }

  final protocol = info.protocol.toLowerCase();
  final rtc = protocol.contains('webrtc') ||
      protocol.contains('trtc') ||
      protocol == 'leb' ||
      info.playUrl.trim() == info.primaryWebRtcUrl;
  if (!rtc) add(info.playUrl);
  add(info.fallbackFlvUrl);
  add(info.fallbackHlsUrl);
  return List.unmodifiable(result);
}

/// Bounded startup wait. Command acknowledgement must never mark a frame ready.
class GroupLiveStartup extends ChangeNotifier {
  GroupLiveStartup({this.timeout = const Duration(seconds: 12)});
  final Duration timeout;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool ready = false;
  bool timedOut = false;
  Duration? firstFrameElapsed;

  void waitForFrame(Future<void> frame, {void Function(Duration)? onReady}) {
    final generation = ++_generation;
    _timer?.cancel();
    ready = false;
    timedOut = false;
    firstFrameElapsed = null;
    _clock
      ..reset()
      ..start();
    _timer = Timer(timeout, () {
      if (_disposed || generation != _generation) return;
      timedOut = true;
      notifyListeners();
    });
    notifyListeners();
    frame.then((_) {
      if (_disposed || generation != _generation) return;
      _timer?.cancel();
      _clock.stop();
      ready = true;
      timedOut = false;
      firstFrameElapsed = _clock.elapsed;
      onReady?.call(_clock.elapsed);
      notifyListeners();
    }, onError: (Object _, StackTrace __) {
      if (_disposed || generation != _generation) return;
      _timer?.cancel();
      timedOut = true;
      notifyListeners();
    });
  }

  void suspend() {
    ++_generation;
    _timer?.cancel();
    _clock.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    super.dispose();
  }
}
