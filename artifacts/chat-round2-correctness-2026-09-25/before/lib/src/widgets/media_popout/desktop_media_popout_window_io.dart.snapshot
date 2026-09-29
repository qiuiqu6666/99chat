import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_geometry.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_host.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_img_trace.dart';

WindowController? _controller;
Completer<void>? _ready;
bool _mainHandlerBound = false;
Future<void> _openChain = Future<void>.value();

void _bindMainHandler() {
  if (_mainHandlerBound) {
    return;
  }
  _mainHandlerBound = true;
  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    if (call.method == 'mediaPopoutReady') {
      final ready = _ready;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
      return null;
    }
    if (call.method == 'mediaPopoutHostAction') {
      final raw = call.arguments;
      Map<String, dynamic> args;
      if (raw is String) {
        final decoded = jsonDecode(raw);
        args = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } else if (raw is Map) {
        args = Map<String, dynamic>.from(raw);
      } else {
        args = <String, dynamic>{};
      }
      return await DesktopMediaPopoutHost.handleAction(args);
    }
    return null;
  });
}

Offset _mainOrigin() {
  try {
    return appWindow.position;
  } catch (_) {
    return Offset.zero;
  }
}

Size _displayLogicalSize() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) {
    return const Size(960, 540);
  }
  final dpr = view.devicePixelRatio;
  if (dpr <= 0) {
    return const Size(960, 540);
  }
  final physical = view.display.size;
  return Size(physical.width / dpr, physical.height / dpr);
}

Future<void> _applyDisplayFrame() async {
  final controller = _controller;
  if (controller == null) {
    return;
  }
  await controller.setFrame(
    resolveOpenFrame(
      mainOrigin: _mainOrigin(),
      displayLogicalSize: _displayLogicalSize(),
    ),
  );
  await controller.center();
}

Future<void> _invokeChild(String method, [dynamic arguments]) async {
  final controller = _controller;
  if (controller == null) {
    return;
  }
  Object? lastError;
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      await DesktopMultiWindow.invokeMethod(
        controller.windowId,
        method,
        arguments,
      );
      return;
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
    }
  }
  if (lastError != null) {
    throw lastError;
  }
}

Future<bool> openOrFocus(Map<String, dynamic> payload) {
  final done = Completer<bool>();
  _openChain = _openChain.then((_) => _openOrFocusBody(payload)).then((ok) {
    if (!done.isCompleted) {
      done.complete(ok);
    }
  }, onError: (Object _, StackTrace __) {
    if (!done.isCompleted) {
      done.complete(false);
    }
  });
  return done.future;
}

Future<bool> _openOrFocusBody(Map<String, dynamic> payload) async {
  if (!Platform.isWindows && !Platform.isMacOS) {
    return false;
  }
  late final String encoded;
  try {
    encoded = jsonEncode(payload);
  } catch (_) {
    return false;
  }
  _bindMainHandler();
  ChatImgTrace.log(
    '[ChatImg] event=popout_host_open ${_payloadSummary(payload)}',
  );
  try {
    final reused = await _stillOpen();
    ChatImgTrace.log('[ChatImg] event=popout_host_window reused=$reused');
    if (!reused) {
      _ready = Completer<void>();
      final window = await DesktopMultiWindow.createWindow(
        jsonEncode(<String, dynamic>{'kind': 'media'}),
      );
      _controller = window;
      await window.setTitle('媒体');
      try {
        await _ready!.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // 子窗引擎若仍在启动，下面 setPayload 仍会再试一次。
      }
    }
    await _applyDisplayFrame();
    if (reused) {
      // 标题栏 X 只是 hide。先 show 再灌 payload，避免隐藏态 0 尺寸把预览铺成黑。
      await _controller!.show();
    }
    await _invokeChild('setPayload', encoded);
    if (!reused) {
      await _controller!.show();
    }
    try {
      await _invokeChild('windowShown');
    } catch (_) {}
    ChatImgTrace.log('[ChatImg] event=popout_host_open_done reused=$reused');
    return true;
  } catch (error) {
    ChatImgTrace.log('[ChatImg] event=popout_host_open_error error=$error');
    if (_controller != null) {
      try {
        await _controller!.show();
        await _invokeChild('setPayload', encoded);
        await _invokeChild('windowShown');
      } catch (_) {}
      return true;
    }
    return false;
  }
}

String _payloadSummary(Map<String, dynamic> payload) {
  final raw = payload['items'];
  final count = raw is List ? raw.length : 0;
  if (raw is! List || raw.isEmpty || raw.first is! Map) {
    return 'items=$count';
  }
  final first = raw.first as Map;
  final orig = '${first['originalUrl'] ?? ''}';
  final url = '${first['url'] ?? ''}';
  final local = '${first['localPath'] ?? ''}';
  return 'items=$count w=${first['width'] ?? 0}x${first['height'] ?? 0} '
      'orig=${orig.isNotEmpty} url=${url.isNotEmpty} local=${local.isNotEmpty}';
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
