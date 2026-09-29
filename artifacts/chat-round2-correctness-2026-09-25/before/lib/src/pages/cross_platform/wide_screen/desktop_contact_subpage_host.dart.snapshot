import 'package:flutter/foundation.dart';

/// 宽屏通讯录：左列整列换成「新的朋友 / 群通知」子页。
enum DesktopContactSubpage { newFriends, groupNotice }

class DesktopContactSubpageHost {
  DesktopContactSubpageHost._();

  static final ValueNotifier<DesktopContactSubpage?> pageNotifier =
      ValueNotifier<DesktopContactSubpage?>(null);

  static bool get isOpen => pageNotifier.value != null;

  static DesktopContactSubpage? get page => pageNotifier.value;

  static void open(DesktopContactSubpage page) {
    pageNotifier.value = page;
  }

  static void close() {
    if (pageNotifier.value == null) {
      return;
    }
    pageNotifier.value = null;
  }
}
