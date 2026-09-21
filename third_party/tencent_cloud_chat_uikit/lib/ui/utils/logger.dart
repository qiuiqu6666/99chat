import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

final outputLogger = TencentCloudChatLog();

class TencentCloudChatLog {
  /// The host app intentionally silences `debugPrint`; keep UIKit diagnostics
  /// available through Android/iOS logcat in debug/profile builds instead.
  void i(String text) {
    if (kReleaseMode || text.trim().isEmpty) {
      return;
    }
    developer.log(text, name: '99chat.uikit');
  }
}
