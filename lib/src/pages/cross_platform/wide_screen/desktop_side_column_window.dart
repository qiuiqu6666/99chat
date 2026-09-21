import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_geom_stub.dart'
    if (dart.library.io) 'package:tencent_cloud_chat_demo/src/pages/cross_platform/wide_screen/desktop_side_column_geom_io.dart'
    as geom;
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// 只改窗口宽度、不改 left/top。禁止走 bitsdojo `size` setter。
class DesktopSideColumnWindow {
  DesktopSideColumnWindow._();

  static const double columnWidth = 300;

  static bool _held = false;
  static double _grownLogicalPx = 0;
  static Rect? _baselineRect;

  static double get grownPx => _grownLogicalPx;

  static bool get hasExpanded =>
      _held && _baselineRect != null && _grownLogicalPx > 0;

  static bool get isHeld => _held;

  static bool get _canGrowOsWindow {
    if (kIsWeb) {
      return false;
    }
    return PlatformUtils().isWindows || PlatformUtils().isMacOS;
  }

  static bool _isMaximized() {
    try {
      return appWindow.isMaximized;
    } catch (_) {
      return false;
    }
  }

  static Rect? _currentRect() {
    try {
      final r = appWindow.rect;
      if (r.width <= 0 || r.height <= 0) {
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }

  /// Windows 的 `rect` 是物理像素，`size` 是逻辑像素；macOS 两侧同单位。
  static double _logicalToRectUnits(double logical) {
    try {
      final size = appWindow.size;
      final rect = appWindow.rect;
      if (size.width > 0 && rect.width > 0) {
        return logical * (rect.width / size.width);
      }
    } catch (_) {}
    return logical;
  }

  static void _widenFromRight(Rect current, double newWidth) {
    geom.applyWindowWidthKeepingOrigin(newWidth, current.height);
  }

  static void tryGrowForColumn([double width = columnWidth]) {
    if (_held) {
      return;
    }
    if (!_canGrowOsWindow || _isMaximized()) {
      _grownLogicalPx = 0;
      _baselineRect = null;
      return;
    }
    try {
      final current = _currentRect();
      if (current == null) {
        _grownLogicalPx = 0;
        _baselineRect = null;
        return;
      }
      final targetLogical = width > 0 ? width : columnWidth;
      final grow = _logicalToRectUnits(targetLogical);
      if (grow <= 0) {
        _grownLogicalPx = 0;
        _baselineRect = null;
        return;
      }
      final newWidth = current.width + grow;
      _baselineRect = current;
      _grownLogicalPx = targetLogical;
      _held = true;
      _widenFromRight(current, newWidth);
    } catch (_) {
      _held = false;
      _grownLogicalPx = 0;
      _baselineRect = null;
    }
  }

  static void releaseColumn() {
    if (!_held) {
      return;
    }
    final baseline = _baselineRect;
    _held = false;
    _grownLogicalPx = 0;
    _baselineRect = null;
    if (baseline == null) {
      return;
    }
    try {
      _widenFromRight(
        Rect.fromLTWH(
          baseline.left,
          baseline.top,
          baseline.width,
          baseline.height,
        ),
        baseline.width,
      );
    } catch (_) {}
  }
}
