import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/sangong_ledger_float_prefs.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_game_float_geometry.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// 用户资料页可拖拽浮窗：查看三公流水。
///
/// 固定圆形「流」按钮；拖动结束后左右吸边。相对所在 [Stack] 定位，
/// 宽屏右栏资料页也能显示，而不是按整窗坐标落到栏外。
class UserProfileGameLedgerFloatingEntry extends StatefulWidget {
  const UserProfileGameLedgerFloatingEntry({
    super.key,
    required this.theme,
    required this.onOpenLedger,
  });

  final TUITheme theme;
  final VoidCallback onOpenLedger;

  static const Color _accent = Color(0xFF1677FF);
  static const Size _size = Size(58, 58);

  @override
  State<UserProfileGameLedgerFloatingEntry> createState() =>
      _UserProfileGameLedgerFloatingEntryState();
}

class _UserProfileGameLedgerFloatingEntryState
    extends State<UserProfileGameLedgerFloatingEntry> {
  final GlobalKey _panelKey = GlobalKey();

  Offset? _offset;
  Offset? _restoredOffset;
  Size _childSize = UserProfileGameLedgerFloatingEntry._size;
  bool _dragging = false;
  bool _prefsLoaded = false;
  bool _paneIsNearlyFullScreen = false;
  Size? _lastPaneSize;

  @override
  void initState() {
    super.initState();
    unawaited(_restorePrefs());
  }

  Future<void> _restorePrefs() async {
    final saved = await SangongLedgerFloatPrefs.instance.readOffset();
    if (!mounted) {
      return;
    }
    setState(() {
      _restoredOffset = saved;
      _prefsLoaded = true;
    });
  }

  Size _paneSizeOf(BuildContext context, BoxConstraints constraints) {
    final biggest = constraints.biggest;
    if (biggest.width.isFinite &&
        biggest.height.isFinite &&
        biggest.width > 0 &&
        biggest.height > 0) {
      return biggest;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      return box.size;
    }
    return MediaQuery.sizeOf(context);
  }

  bool _isNearlyFullScreen(Size paneSize, Size windowSize) {
    return (paneSize.width - windowSize.width).abs() < 16 &&
        (paneSize.height - windowSize.height).abs() < 120;
  }

  EdgeInsets _panePaddingOf(BuildContext context, Size paneSize) {
    final media = MediaQuery.of(context);
    _paneIsNearlyFullScreen = _isNearlyFullScreen(paneSize, media.size);
    return _paneIsNearlyFullScreen ? media.viewPadding : EdgeInsets.zero;
  }

  bool _offsetFitsPane(
    Offset offset,
    Size paneSize,
    EdgeInsets padding,
    Size childSize,
  ) {
    final clamped = clampGroupGameFloatOffset(
      offset: offset,
      screenSize: paneSize,
      childSize: childSize,
      viewPadding: padding,
    );
    return (offset.dx - clamped.dx).abs() < 2 &&
        (offset.dy - clamped.dy).abs() < 2;
  }

  Offset _defaultOffset(Size paneSize, EdgeInsets padding, Size childSize) {
    return clampGroupGameFloatOffset(
      offset: defaultGroupGameFloatOffset(
        screenSize: paneSize,
        childSize: childSize,
        bottomInset: padding.bottom,
      ),
      screenSize: paneSize,
      childSize: childSize,
      viewPadding: padding,
    );
  }

  Offset _resolvedOffset(Size paneSize, EdgeInsets padding) {
    final restored = _restoredOffset;
    if (!_dragging && restored != null) {
      _restoredOffset = null;
      if (_offsetFitsPane(restored, paneSize, padding, _childSize)) {
        _offset = restored;
      }
    }
    final base = _offset ?? _defaultOffset(paneSize, padding, _childSize);
    final next = clampGroupGameFloatOffset(
      offset: base,
      screenSize: paneSize,
      childSize: _childSize,
      viewPadding: padding,
    );
    _offset = next;
    _lastPaneSize = paneSize;
    return next;
  }

  void _measureChildIfNeeded() {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final size = box.size;
    if ((size.width - _childSize.width).abs() < 0.5 &&
        (size.height - _childSize.height).abs() < 0.5) {
      return;
    }
    final paneSize = _lastPaneSize ?? MediaQuery.sizeOf(context);
    final padding = _panePaddingOf(context, paneSize);
    setState(() {
      _childSize = size;
      final base = _offset ?? _defaultOffset(paneSize, padding, size);
      _offset = clampGroupGameFloatOffset(
        offset: base,
        screenSize: paneSize,
        childSize: size,
        viewPadding: padding,
      );
    });
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    Size screenSize,
    EdgeInsets padding,
  ) {
    if (!_dragging) {
      return;
    }
    final current = _offset ?? _defaultOffset(screenSize, padding, _childSize);
    setState(() {
      _offset = clampGroupGameFloatOffset(
        offset: current + details.delta,
        screenSize: screenSize,
        childSize: _childSize,
        viewPadding: padding,
      );
    });
  }

  void _snapAndPersist(Size screenSize, EdgeInsets padding) {
    final current = _offset;
    if (current == null) {
      return;
    }
    final snapped = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: current,
      screenSize: screenSize,
      childSize: _childSize,
      viewPadding: padding,
    );
    setState(() {
      _dragging = false;
      _offset = snapped;
    });
    if (_paneIsNearlyFullScreen) {
      unawaited(SangongLedgerFloatPrefs.instance.writeOffset(snapped));
    }
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, EdgeInsets padding) {
    _snapAndPersist(screenSize, padding);
  }

  void _onPanCancel(Size screenSize, EdgeInsets padding) {
    _snapAndPersist(screenSize, padding);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        elevation: 24,
        child: LayoutBuilder(
          builder: (context, constraints) {
          final paneSize = _paneSizeOf(context, constraints);
          final padding = _panePaddingOf(context, paneSize);
          final offset = _resolvedOffset(paneSize, padding);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _measureChildIfNeeded();
            }
          });

          final i18n = AppI18n.of(context);
          final primary = widget.theme.primaryColor ??
              UserProfileGameLedgerFloatingEntry._accent;
          final isDark = (widget.theme.weakBackgroundColor ?? Colors.white)
                  .computeLuminance() <
              0.5;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: offset.dx,
                top: offset.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onPanStart: _onPanStart,
                  onPanUpdate: (details) =>
                      _onPanUpdate(details, paneSize, padding),
                  onPanEnd: (details) =>
                      _onPanEnd(details, paneSize, padding),
                  onPanCancel: () => _onPanCancel(paneSize, padding),
                  child: KeyedSubtree(
                    key: _panelKey,
                    child: Tooltip(
                      message:
                          i18n.t(zhHans: '流水', zhHant: '流水', en: 'Ledger'),
                      child: Material(
                        color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
                        shape: const CircleBorder(),
                        elevation: _dragging ? 10 : 6,
                        shadowColor: isDark ? Colors.black87 : Colors.black26,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _dragging || !_prefsLoaded
                              ? null
                              : widget.onOpenLedger,
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: Center(
                              child: Text(
                                i18n.t(zhHans: '流', zhHant: '流', en: 'L'),
                                style: TextStyle(
                                  fontSize: 24,
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}
