import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/painting.dart';

void applyWindowWidthKeepingOrigin(double width, double height) {
  try {
    appWindow.alignment = null;
  } catch (_) {}
  try {
    final current = appWindow.rect;
    appWindow.rect = Rect.fromLTWH(current.left, current.top, width, height);
  } catch (_) {}
}
