import 'package:flutter/foundation.dart';

/// 聊天图片下载 / 预取诊断。过滤关键字：`[ChatImg]`。
class ChatImgTrace {
  ChatImgTrace._();

  /// 排查全屏预览原图/大图时改为 true，过滤关键字：`[ChatImg]`。
  static const bool enabled = true;

  static void log(String message) {
    if (!enabled) {
      return;
    }
    debugPrint(message);
    // ignore: avoid_print
    print(message);
  }
}
