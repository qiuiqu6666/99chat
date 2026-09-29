import 'package:flutter/material.dart';

const _scratchRadius = 9.0;

class LotteryScratchCover extends StatefulWidget {
  const LotteryScratchCover(
      {super.key,
      required this.hidden,
      required this.onRevealed,
      required this.child});
  final bool hidden;
  final VoidCallback onRevealed;
  final Widget child;
  @override
  State<LotteryScratchCover> createState() => _LotteryScratchCoverState();
}

class _LotteryScratchCoverState extends State<LotteryScratchCover> {
  final _points = <Offset>[];
  final _cells = <int>{};
  Offset? _previous;
  bool _finished = false;

  @override
  void didUpdateWidget(LotteryScratchCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hidden != oldWidget.hidden) {
      _points.clear();
      _cells.clear();
      _previous = null;
      _finished = false;
    }
  }

  void _scratch(Offset point, Size size) {
    if (_finished || size.isEmpty) return;
    final start = _previous ?? point;
    final steps = ((point - start).distance / 4).ceil().clamp(1, 400);
    for (var step = 1; step <= steps; step++) {
      final p = Offset.lerp(start, point, step / steps)!;
      _points.add(p);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 32; x++) {
          final center =
              Offset((x + .5) * size.width / 32, (y + .5) * size.height / 8);
          if ((center - p).distance <= _scratchRadius) _cells.add(y * 32 + x);
        }
      }
    }
    _previous = point;
    setState(() {});
    if (_cells.length / 256 >= .45) {
      _finished = true;
      widget.onRevealed();
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        ExcludeSemantics(excluding: widget.hidden, child: widget.child),
        if (widget.hidden)
          Positioned.fill(
              child: LayoutBuilder(
            builder: (context, constraints) => Semantics(
                label: '滑动刮开开奖结果',
                child: GestureDetector(
                  key: const ValueKey('lottery-reveal-cover'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onPanStart: (details) {
                    _previous = null;
                    _scratch(details.localPosition, constraints.biggest);
                  },
                  onPanUpdate: (details) =>
                      _scratch(details.localPosition, constraints.biggest),
                  onPanEnd: (_) => _previous = null,
                  onPanCancel: () => _previous = null,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CustomPaint(
                          painter: _ScratchPainter(List.of(_points)))),
                )),
          )),
      ]);
}

class _ScratchPainter extends CustomPainter {
  const _ScratchPainter(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE2E8F0));
    final label = TextPainter(
        text: const TextSpan(
            text: '滑动刮开',
            style: TextStyle(
                color: Color(0xFF536780),
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width);
    label.paint(
        canvas,
        Offset(
            (size.width - label.width) / 2, (size.height - label.height) / 2));
    final eraser = Paint()..blendMode = BlendMode.clear;
    for (final point in points) {
      canvas.drawCircle(point, _scratchRadius, eraser);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScratchPainter oldDelegate) => true;
}
