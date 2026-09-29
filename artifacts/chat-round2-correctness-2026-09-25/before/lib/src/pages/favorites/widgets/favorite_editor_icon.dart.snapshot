import 'package:flutter/material.dart';

/// Shared vector artwork for the favorite editor's tabs and insertion tools.
class FavoriteEditorIcon extends StatelessWidget {
  const FavoriteEditorIcon(this.kind,
      {this.size = 28, this.color = const Color(0xFF687487), super.key});
  final String kind;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _EditorIconPainter(kind, color)));
}

class _EditorIconPainter extends CustomPainter {
  const _EditorIconPainter(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final fill = Paint()..color = color;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final isTab = kind.startsWith('type_');
    if (isTab) {
      final colors = kind == 'type_text'
          ? [const Color(0xFF38C3FF), const Color(0xFF137AFF)]
          : kind == 'type_image'
              ? [const Color(0xFF37DFCE), const Color(0xFF00B59F)]
              : [const Color(0xFFC576FF), const Color(0xFF8234E3)];
      fill.shader = LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: colors)
          .createShader(const Rect.fromLTWH(0, 0, 32, 32));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(2, 2, 28, 28), const Radius.circular(7)),
          fill);
      fill.shader = null;
      fill.color = Colors.white;
      pen.color = Colors.white;
      if (kind == 'type_text') {
        for (final pair in [(11.0, 20.0), (16.0, 22.0), (21.0, 17.0)]) {
          canvas.drawLine(Offset(10, pair.$1), Offset(pair.$2, pair.$1), pen);
        }
      } else if (kind == 'type_image') {
        canvas.drawCircle(const Offset(10.5, 11), 2, fill);
        canvas.drawPath(
            Path()
              ..moveTo(8, 23)
              ..lineTo(11.5, 17.5)
              ..quadraticBezierTo(12.5, 16, 14, 17.5)
              ..lineTo(15.5, 19)
              ..lineTo(19.5, 14)
              ..quadraticBezierTo(21, 12.5, 22, 15)
              ..lineTo(25, 22)
              ..quadraticBezierTo(25.5, 24, 23, 24)
              ..lineTo(10, 24)
              ..quadraticBezierTo(7, 24, 8, 23),
            fill);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(8, 10, 12, 13), const Radius.circular(2)),
            fill);
        canvas.drawPath(
            Path()
              ..moveTo(22, 13)
              ..lineTo(26, 10.5)
              ..lineTo(26, 22.5)
              ..lineTo(22, 20)
              ..close(),
            fill);
      }
    } else if (kind == 'image') {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 4, 24, 24), const Radius.circular(3)),
          pen);
      canvas.drawCircle(const Offset(11, 11), 1.7, fill);
      canvas.drawPath(
          Path()
            ..moveTo(5, 24)
            ..lineTo(12, 17)
            ..lineTo(16, 21)
            ..lineTo(22, 14)
            ..lineTo(27, 20),
          pen);
    } else if (kind == 'camera') {
      canvas.drawPath(
          Path()
            ..moveTo(7, 8)
            ..lineTo(11, 8)
            ..lineTo(13, 5)
            ..lineTo(20, 5)
            ..lineTo(22, 8)
            ..lineTo(26, 8)
            ..quadraticBezierTo(29, 8, 29, 11)
            ..lineTo(29, 25)
            ..quadraticBezierTo(29, 28, 26, 28)
            ..lineTo(6, 28)
            ..quadraticBezierTo(3, 28, 3, 25)
            ..lineTo(3, 11)
            ..quadraticBezierTo(3, 8, 7, 8),
          pen);
      canvas.drawCircle(const Offset(16, 18), 5, pen);
      canvas.drawCircle(const Offset(24, 12), 1, fill);
    } else if (kind == 'location') {
      canvas.drawPath(
          Path()
            ..moveTo(16, 30)
            ..cubicTo(11, 23, 5, 17, 5, 12)
            ..cubicTo(5, -1, 27, -1, 27, 12)
            ..cubicTo(27, 17, 21, 23, 16, 30)
            ..close(),
          pen);
      canvas.drawCircle(const Offset(16, 12), 4, pen);
    } else if (kind == 'emoji') {
      canvas.drawCircle(const Offset(16, 16), 13, pen);
      canvas.drawCircle(const Offset(11, 12), 1.5, fill);
      canvas.drawCircle(const Offset(21, 12), 1.5, fill);
      canvas.drawPath(
          Path()
            ..moveTo(10, 20)
            ..quadraticBezierTo(16, 27, 22, 20),
          pen);
    } else if (kind == 'tip') {
      canvas.drawPath(
          Path()
            ..moveTo(11, 24)
            ..cubicTo(11, 20, 6, 18, 6, 12)
            ..cubicTo(6, -1, 26, -1, 26, 12)
            ..cubicTo(26, 18, 21, 20, 21, 24)
            ..close()
            ..moveTo(12, 28)
            ..lineTo(20, 28)
            ..moveTo(14, 31)
            ..lineTo(18, 31),
          pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EditorIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
