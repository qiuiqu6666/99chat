import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_window_stub.dart'
    if (dart.library.io) 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_window_io.dart'
    as impl;
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';

class DesktopMediaPopout {
  static void install() {
    DesktopMediaPreviewHook.openOrFocus = openOrFocus;
  }

  static Future<bool> openOrFocus(Map<String, dynamic> payload) {
    return impl.openOrFocus(payload);
  }
}
