import 'package:flutter/material.dart';

/// 预览遮罩色。未包裹时为纯黑（手机/全屏预览不变）。
class MediaPreviewBackdropScope extends InheritedWidget {
  const MediaPreviewBackdropScope({
    super.key,
    required this.color,
    this.desktopOverlayChrome = false,
    required super.child,
  });

  /// Win/Mac 独立媒体小窗：深色半透明遮罩（图片 contain，四周露出遮罩）。
  static const Color desktopPopout = Color(0xE6101010);

  final Color color;
  final bool desktopOverlayChrome;

  static Color of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MediaPreviewBackdropScope>()
            ?.color ??
        Colors.black;
  }

  static bool desktopOverlayChromeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MediaPreviewBackdropScope>()
            ?.desktopOverlayChrome ??
        false;
  }

  @override
  bool updateShouldNotify(MediaPreviewBackdropScope oldWidget) {
    return oldWidget.color != color ||
        oldWidget.desktopOverlayChrome != desktopOverlayChrome;
  }
}
