import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live_watch_float_prefs.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_game_float_geometry.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/group_live/group_live_inline_watch_banner.dart';

enum _LiveResizeHandle { n, s, e, w, nw, ne, sw, se }

/// Desktop in-chat live preview: 16:9 card over the chat column, draggable.
class GroupLiveWatchFloat extends StatefulWidget {
  const GroupLiveWatchFloat({
    super.key,
    required this.session,
    required this.onClose,
    this.anchorFaceUrl = '',
  });

  final GroupLiveSession session;
  final VoidCallback onClose;
  final String anchorFaceUrl;

  static const Size minSize = Size(320, 180);
  static const double aspect = 16 / 9;
  static const double defaultRight = 12;
  static const double defaultTop = 68;
  static const double edge = 8;
  static const double handleThickness = 8;
  static const double cornerHandle = 12;
  static const Size closeAvoid = Size(40, 40);

  @override
  State<GroupLiveWatchFloat> createState() => _GroupLiveWatchFloatState();
}

class _GroupLiveWatchFloatState extends State<GroupLiveWatchFloat> {
  Offset? _offset;
  late Size _size;

  @override
  void initState() {
    super.initState();
    final prefs = GroupLiveWatchFloatPrefs.instance;
    final width = prefs.readWidthSync();
    _offset = prefs.readOffsetSync();
    if (width != null) {
      _size = Size(width, width / GroupLiveWatchFloat.aspect);
    } else {
      _size = GroupLiveWatchFloat.minSize;
    }
  }

  Offset _defaultOffset(Size stackSize, Size size) {
    return Offset(
      stackSize.width - size.width - GroupLiveWatchFloat.defaultRight,
      GroupLiveWatchFloat.defaultTop,
    );
  }

  Offset _clamped(Offset offset, Size stackSize, Size size) {
    return clampGroupGameFloatOffset(
      offset: offset,
      screenSize: stackSize,
      childSize: size,
      viewPadding: EdgeInsets.zero,
      edge: GroupLiveWatchFloat.edge,
    );
  }

  ({double minWidth, double maxWidth}) _widthBounds(Size stackSize) {
    final availableW = math.max(
      0.0,
      stackSize.width - GroupLiveWatchFloat.edge * 2,
    );
    final availableH = math.max(
      0.0,
      stackSize.height - GroupLiveWatchFloat.edge * 2,
    );
    final maxWidth = math.min(
      availableW,
      availableH * GroupLiveWatchFloat.aspect,
    );
    final minWidth = math.min(GroupLiveWatchFloat.minSize.width, maxWidth);
    return (minWidth: minWidth, maxWidth: maxWidth);
  }

  Size _fittedSize(Size stackSize, Size size) {
    final bounds = _widthBounds(stackSize);
    if (bounds.maxWidth <= 0) {
      return Size.zero;
    }
    final width = size.width.clamp(bounds.minWidth, bounds.maxWidth).toDouble();
    return Size(width, width / GroupLiveWatchFloat.aspect);
  }

  void _persist(Size stackSize) {
    final size = _fittedSize(stackSize, _size);
    if (size.width <= 0) {
      return;
    }
    final offset = _clamped(
      _offset ?? _defaultOffset(stackSize, size),
      stackSize,
      size,
    );
    unawaited(
      GroupLiveWatchFloatPrefs.instance.write(
        offset: offset,
        width: size.width,
      ),
    );
  }

  void _onMove(Offset delta, Size stackSize) {
    final size = _fittedSize(stackSize, _size);
    setState(() {
      _size = size;
      _offset = _clamped(
        (_offset ?? _defaultOffset(stackSize, size)) + delta,
        stackSize,
        size,
      );
    });
  }

  void _onResize(_LiveResizeHandle handle, Offset delta, Size stackSize) {
    final oldSize = _fittedSize(stackSize, _size);
    if (oldSize.width <= 0) {
      return;
    }
    final oldOffset = _clamped(
      _offset ?? _defaultOffset(stackSize, oldSize),
      stackSize,
      oldSize,
    );

    final fromWidth = handle == _LiveResizeHandle.e ||
        handle == _LiveResizeHandle.w ||
        handle == _LiveResizeHandle.ne ||
        handle == _LiveResizeHandle.nw ||
        handle == _LiveResizeHandle.se ||
        handle == _LiveResizeHandle.sw;
    final fromHeight = handle == _LiveResizeHandle.n ||
        handle == _LiveResizeHandle.s ||
        handle == _LiveResizeHandle.ne ||
        handle == _LiveResizeHandle.nw ||
        handle == _LiveResizeHandle.se ||
        handle == _LiveResizeHandle.sw;

    double? widthCandidate;
    if (fromWidth) {
      final dx = handle == _LiveResizeHandle.e ||
              handle == _LiveResizeHandle.ne ||
              handle == _LiveResizeHandle.se
          ? delta.dx
          : -delta.dx;
      widthCandidate = oldSize.width + dx;
    }
    double? heightCandidate;
    if (fromHeight) {
      final dy = handle == _LiveResizeHandle.s ||
              handle == _LiveResizeHandle.se ||
              handle == _LiveResizeHandle.sw
          ? delta.dy
          : -delta.dy;
      heightCandidate = oldSize.height + dy;
    }

    double width;
    if (widthCandidate != null && heightCandidate != null) {
      final fromHeightWidth = heightCandidate * GroupLiveWatchFloat.aspect;
      width = (widthCandidate - oldSize.width).abs() >=
              (fromHeightWidth - oldSize.width).abs()
          ? widthCandidate
          : fromHeightWidth;
    } else if (widthCandidate != null) {
      width = widthCandidate;
    } else {
      width = (heightCandidate ?? oldSize.height) * GroupLiveWatchFloat.aspect;
    }

    final nextSize =
        _fittedSize(stackSize, Size(width, width / GroupLiveWatchFloat.aspect));
    var left = oldOffset.dx;
    var top = oldOffset.dy;
    final lockRight = handle == _LiveResizeHandle.w ||
        handle == _LiveResizeHandle.nw ||
        handle == _LiveResizeHandle.sw;
    final lockBottom = handle == _LiveResizeHandle.n ||
        handle == _LiveResizeHandle.ne ||
        handle == _LiveResizeHandle.nw;
    if (lockRight) {
      left = oldOffset.dx + oldSize.width - nextSize.width;
    }
    if (lockBottom) {
      top = oldOffset.dy + oldSize.height - nextSize.height;
    }

    setState(() {
      _size = nextSize;
      _offset = _clamped(Offset(left, top), stackSize, nextSize);
    });
  }

  Widget _handle({
    required _LiveResizeHandle handle,
    required Size stackSize,
    required MouseCursor cursor,
    required double? left,
    required double? top,
    required double? right,
    required double? bottom,
    required double? width,
    required double? height,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => _onResize(handle, details.delta, stackSize),
          onPanEnd: (_) => _persist(stackSize),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          if (!stackSize.width.isFinite ||
              !stackSize.height.isFinite ||
              stackSize.width <= 0 ||
              stackSize.height <= 0) {
            return const SizedBox.shrink();
          }
          final size = _fittedSize(stackSize, _size);
          if (size.width <= 0) {
            return const SizedBox.shrink();
          }
          final offset = _clamped(
            _offset ?? _defaultOffset(stackSize, size),
            stackSize,
            size,
          );
          const t = GroupLiveWatchFloat.handleThickness;
          const c = GroupLiveWatchFloat.cornerHandle;
          const avoid = GroupLiveWatchFloat.closeAvoid;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: offset.dx,
                top: offset.dy,
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onPanUpdate: (details) =>
                          _onMove(details.delta, stackSize),
                      onPanEnd: (_) => _persist(stackSize),
                      child: Material(
                        elevation: 8,
                        shadowColor: Colors.black38,
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: GroupLiveInlineWatchBanner(
                          key: ValueKey(
                            'watch_${widget.session.liveSessionId}',
                          ),
                          session: widget.session,
                          anchorFaceUrl: widget.anchorFaceUrl,
                          onClose: widget.onClose,
                        ),
                      ),
                    ),
                    _handle(
                      handle: _LiveResizeHandle.n,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeUpDown,
                      left: c,
                      top: 0,
                      right: avoid.width,
                      bottom: null,
                      width: null,
                      height: t,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.s,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeUpDown,
                      left: c,
                      top: null,
                      right: c,
                      bottom: 0,
                      width: null,
                      height: t,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.w,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeLeftRight,
                      left: 0,
                      top: c,
                      right: null,
                      bottom: c,
                      width: t,
                      height: null,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.e,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeLeftRight,
                      left: null,
                      top: avoid.height,
                      right: 0,
                      bottom: c,
                      width: t,
                      height: null,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.nw,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeUpLeft,
                      left: 0,
                      top: 0,
                      right: null,
                      bottom: null,
                      width: c,
                      height: c,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.ne,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeUpRight,
                      left: null,
                      top: 0,
                      right: avoid.width,
                      bottom: null,
                      width: c,
                      height: c,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.sw,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeDownLeft,
                      left: 0,
                      top: null,
                      right: null,
                      bottom: 0,
                      width: c,
                      height: c,
                    ),
                    _handle(
                      handle: _LiveResizeHandle.se,
                      stackSize: stackSize,
                      cursor: SystemMouseCursors.resizeDownRight,
                      left: null,
                      top: null,
                      right: 0,
                      bottom: 0,
                      width: c,
                      height: c,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
