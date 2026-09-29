import 'package:pasteboard/pasteboard.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_clipboard_image_stub.dart'
    if (dart.library.io) 'package:tencent_cloud_chat_uikit/ui/utils/desktop_clipboard_image_io.dart'
    as native;

/// 宽屏输入框注册，给 [FocusNode.onKey] 这条已接通的按键链用。
Future<void> Function()? desktopChatInputPaste;

/// 桌面「复制图片」必须同时写入位图格式。只写文件列表(CF_HDROP)时，
/// 其它软件能贴，但输入框的 [Pasteboard.image] 读不到。
Future<bool> copyDesktopMediaFile(String path) async {
  if (await native.writeImagePathToClipboard(path)) {
    return true;
  }
  try {
    return await Pasteboard.writeFiles([path]);
  } catch (_) {
    return false;
  }
}

bool looksLikeImageBytes(List<int> bytes) {
  if (bytes.length < 12) {
    return false;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return true;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  if (bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    return brand == 'heic' ||
        brand == 'heix' ||
        brand == 'mif1' ||
        brand == 'msf1' ||
        brand == 'avif' ||
        brand == 'avis';
  }
  return false;
}
