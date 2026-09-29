import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// Windows / macOS 媒体独立窗入口。UIKit 只持有回调，不依赖 `desktop_multi_window`。
class DesktopMediaPreviewHook {
  static Future<bool> Function(Map<String, dynamic> payload)? openOrFocus;

  static Future<bool> tryOpen(Map<String, dynamic> payload) async {
    if (!PlatformUtils().isWinMacDesktop) {
      return false;
    }
    final hook = openOrFocus;
    if (hook == null) {
      return false;
    }
    try {
      return await hook(payload);
    } catch (_) {
      return false;
    }
  }
}
