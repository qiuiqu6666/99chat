import 'dart:async';
import 'package:flutter/material.dart';

/// 首格固定，整理时抖动并可长按拖动；拖到边缘时自动滚动。
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
  final void Function(String from, String to) onMove;

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
    return GridView.builder(
      key: _viewportKey,
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: widget.ids.length + 1,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = widget.ids.indexOf(key.value);
        return index < 0 ? null : index + 1;
      },
      itemBuilder: (context, index) {
        if (index == 0) return widget.addTile;
        final id = widget.ids[index - 1];
        final tile = widget.itemBuilder(context, index - 1);
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
              onAcceptWithDetails: (details) {
                if (widget.organizing && details.data == _dragging) {
                  widget.onMove(details.data, id);
                }
              },
              builder: (context, candidates, rejected) => DecoratedBox(
                decoration: BoxDecoration(
                  border: candidates.isEmpty
                      ? null
                      : Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: LongPressDraggable<String>(
                  data: id,
                  delay: const Duration(milliseconds: 180),
                  maxSimultaneousDrags: 1,
                  onDragStarted: () {
                    _dragging = id;
                    _scrollTimer?.cancel();
                    _scrollTimer = Timer.periodic(
                        const Duration(milliseconds: 16), (_) => _autoScroll());
                  },
                  onDragUpdate: (details) => _pointer = details.globalPosition,
                  onDragEnd: (_) => _endDrag(),
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
    );
  }
}
