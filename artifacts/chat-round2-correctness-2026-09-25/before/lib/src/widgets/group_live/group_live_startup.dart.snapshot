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

/// Signed URL renewals do not change the live stream being watched.
bool groupLiveSameStreamSource(String previous, String current) {
  final oldUri = Uri.tryParse(previous.trim());
  final newUri = Uri.tryParse(current.trim());
  if (oldUri == null || newUri == null) return previous == current;
  if (oldUri.scheme != newUri.scheme ||
      oldUri.host != newUri.host ||
      oldUri.port != newUri.port ||
      oldUri.path != newUri.path ||
      oldUri.userInfo != newUri.userInfo) {
    return false;
  }

  bool isSignature(String key) {
    final name = key.toLowerCase();
    return name == 'txsecret' || name == 'txtime';
  }

  final oldQuery = Map<String, List<String>>.of(oldUri.queryParametersAll)
    ..removeWhere((key, _) => isSignature(key));
  final newQuery = Map<String, List<String>>.of(newUri.queryParametersAll)
    ..removeWhere((key, _) => isSignature(key));
  if (!setEquals(oldQuery.keys.toSet(), newQuery.keys.toSet())) return false;
  for (final key in oldQuery.keys) {
    final oldValues = [...oldQuery[key]!]..sort();
    final newValues = [...newQuery[key]!]..sort();
    if (!listEquals(oldValues, newValues)) return false;
  }
  return true;
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
