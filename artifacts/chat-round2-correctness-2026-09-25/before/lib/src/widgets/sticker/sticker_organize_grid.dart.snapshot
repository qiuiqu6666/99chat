import 'dart:async';
import 'package:flutter/material.dart';

/// 首格固定，整理时抖动并可直接拖动；拖到边缘时自动滚动。
class StickerOrganizeGrid extends StatefulWidget {
  const StickerOrganizeGrid({
    super.key,
    required this.ids,
    required this.organizing,
    required this.addTile,
    required this.itemBuilder,
    required this.onMove,
  });

  final List<String> ids;
  final bool organizing;
  final Widget addTile;
  final Widget Function(BuildContext, int) itemBuilder;
  final FutureOr<void> Function(String from, String to) onMove;

  @override
  State<StickerOrganizeGrid> createState() => _StickerOrganizeGridState();
}

class _StickerOrganizeGridState extends State<StickerOrganizeGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: -1,
    upperBound: 1,
  );
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  Timer? _scrollTimer;
  Offset? _pointer;
  String? _dragging;
  List<String>? _previewIds;
  bool _committing = false;

  int? _pointerIndex() {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || _pointer == null || !_scroll.hasClients) {
      return null;
    }
    final point = box.globalToLocal(_pointer!);
    if (point.dx < 8 ||
        point.dx >= box.size.width - 8 ||
        point.dy < 0 ||
        point.dy >= box.size.height) {
      return null;
    }
    final stride = (box.size.width - 16 - 24) / 4 + 8;
    var column = ((point.dx - 8) / stride).floor().clamp(0, 3);
    if (Directionality.of(context) == TextDirection.rtl) column = 3 - column;
    final row = ((point.dy + _scroll.offset - 4) / stride).floor();
    final index = row * 4 + column - 1;
    final count = (_previewIds ?? widget.ids).length;
    // 「＋」仍不可放置；末尾空格和网格内下方空白均表示移到最后。
    if (index < 0 || count == 0) return null;
    return index.clamp(0, count - 1);
  }

  void _previewMove() {
    final target = _pointerIndex();
    final ids = _previewIds;
    if (target == null || ids == null || _dragging == null) return;
    final from = ids.indexOf(_dragging!);
    if (from < 0 || from == target) return;
    setState(() => ids.insert(target, ids.removeAt(from)));
  }

  Future<void> _finishDrag() async {
    final from = _dragging;
    final preview = _previewIds;
    final validDrop = _pointerIndex() != null;
    _endDrag();
    if (!mounted) return;
    final target = from == null ? -1 : preview?.indexOf(from) ?? -1;
    _committing = true;
    try {
      if (widget.organizing &&
          validDrop &&
          from != null &&
          target >= 0 &&
          target < widget.ids.length &&
          widget.ids[target] != from) {
        await widget.onMove(from, widget.ids[target]);
      }
    } finally {
      if (mounted) {
        setState(() {
          _previewIds = null;
          _committing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.organizing) _shake.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StickerOrganizeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.organizing != oldWidget.organizing) {
      if (widget.organizing) {
        _shake.repeat(reverse: true);
      } else {
        _shake.stop();
        _endDrag();
        _previewIds = null;
      }
    }
  }

  void _endDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _pointer = null;
    _dragging = null;
  }

  void _autoScroll() {
    if (!_scroll.hasClients || _pointer == null) return;
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final y = box.globalToLocal(_pointer!).dy;
    const edge = 56.0;
    final delta = y < edge
        ? -8.0 * ((edge - y) / edge).clamp(0.0, 1.0)
        : y > box.size.height - edge
            ? 8.0 * ((y - box.size.height + edge) / edge).clamp(0.0, 1.0)
            : 0.0;
    if (delta == 0) return;
    _scroll.jumpTo((_scroll.offset + delta).clamp(
        _scroll.position.minScrollExtent, _scroll.position.maxScrollExtent));
    _previewMove();
  }

  @override
  void dispose() {
    _endDrag();
    _shake.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = _previewIds ?? widget.ids;
    return Listener(
      onPointerMove: (event) {
        if (widget.organizing) {
          _pointer = event.position;
          _previewMove();
        }
      },
      child: GridView.builder(
        key: _viewportKey,
        controller: _scroll,
        // 整理时竖向手势也属于表情拖动；跨屏由边缘自动滚动处理。
        physics:
            widget.organizing ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: widget.ids.length + 1,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = ids.indexOf(key.value);
          return index < 0 ? null : index + 1;
        },
        itemBuilder: (context, index) {
          if (index == 0) return widget.addTile;
          final id = ids[index - 1];
          final sourceIndex = widget.ids.indexOf(id);
          if (sourceIndex < 0) return const SizedBox.shrink();
          final tile = widget.itemBuilder(context, sourceIndex);
          return KeyedSubtree(
            key: ValueKey(id),
            child: LayoutBuilder(builder: (context, constraints) {
              final shakingTile = AnimatedBuilder(
                animation: _shake,
                child: tile,
                builder: (context, child) => Transform.rotate(
                  angle: widget.organizing &&
                          !MediaQuery.disableAnimationsOf(context)
                      ? _shake.value * 0.025 * (index.isEven ? 1 : -1)
                      : 0,
                  child: child,
                ),
              );
              if (!widget.organizing) return shakingTile;
              return DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    widget.organizing &&
                    details.data != id &&
                    details.data == _dragging &&
                    widget.ids.contains(details.data),
                builder: (context, candidates, rejected) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: candidates.isEmpty
                        ? null
                        : Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Draggable<String>(
                    data: id,
                    hitTestBehavior: HitTestBehavior.opaque,
                    maxSimultaneousDrags:
                        _committing || (_dragging != null && _dragging != id)
                            ? 0
                            : 1,
                    onDragStarted: () {
                      _dragging = id;
                      _previewIds = List.of(widget.ids);
                      _previewMove();
                      _scrollTimer?.cancel();
                      _scrollTimer = Timer.periodic(
                          const Duration(milliseconds: 16),
                          (_) => _autoScroll());
                    },
                    onDragEnd: (_) => _finishDrag(),
                    feedback: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: tile,
                      ),
                    ),
                    childWhenDragging: Opacity(opacity: 0.2, child: tile),
                    child: shakingTile,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
