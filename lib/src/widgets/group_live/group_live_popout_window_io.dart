import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';

WindowController? _controller;
String? _playUrl;
String? _fallbackFlvUrl;

Future<void> openOrFocus(GroupLivePlayInfo playInfo) async {
  if (!Platform.isWindows) {
    return;
  }
  final playUrl = playInfo.playUrl;
  final fallbackFlvUrl = playInfo.fallbackFlvUrl;
  if (await _stillOpen()) {
    await _controller!.show();
    if (playUrl != _playUrl || fallbackFlvUrl != _fallbackFlvUrl) {
      _playUrl = playUrl;
      _fallbackFlvUrl = fallbackFlvUrl;
      await DesktopMultiWindow.invokeMethod(
        _controller!.windowId,
        'switchUrl',
        jsonEncode({
          'playUrl': playUrl,
          'fallbackFlvUrl': fallbackFlvUrl,
        }),
      );
    }
    return;
  }
  _playUrl = playUrl;
  _fallbackFlvUrl = fallbackFlvUrl;
  final window = await DesktopMultiWindow.createWindow(
    jsonEncode({
      'playUrl': playUrl,
      'fallbackFlvUrl': fallbackFlvUrl,
    }),
  );
  _controller = window;
  await window.setFrame(const Offset(0, 0) & const Size(960, 540));
  await window.center();
  await window.setTitle('群直播');
  await window.show();
}

Future<bool> _stillOpen() async {
  final controller = _controller;
  if (controller == null) {
    return false;
  }
  try {
    final ids = await DesktopMultiWindow.getAllSubWindowIds();
    return ids.contains(controller.windowId);
  } catch (_) {
    return false;
  }
}
