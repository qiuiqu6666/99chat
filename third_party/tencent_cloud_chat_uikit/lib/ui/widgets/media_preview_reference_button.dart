import 'package:flutter/material.dart';

/// Reference artwork, drawn on a 40-unit circle so it stays crisp at any DPR.
class MediaPreviewReferenceButton extends StatelessWidget {
  const MediaPreviewReferenceButton({
    required this.icon,
    required this.label,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          enabled: onPressed != null,
          child: Opacity(
            opacity: onPressed == null ? 0.35 : 1,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CustomPaint(painter: _ReferenceIconPainter(icon)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _ReferenceIconPainter extends CustomPainter {
  const _ReferenceIconPainter(this.icon);
  final IconData icon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final stroke = Paint()
      ..color = icon == Icons.delete_outline_rounded ? Colors.red : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = stroke.color;
    if (icon == Icons.ios_share_rounded) {
      canvas.drawPath(
        Path()
          ..moveTo(20.5, 11.6)
          ..quadraticBezierTo(20.5, 10.1, 21.7, 11.1)
          ..lineTo(29.5, 17.8)
          ..quadraticBezierTo(30.4, 18.5, 29.5, 19.3)
          ..lineTo(21.8, 26)
          ..quadraticBezierTo(20.5, 27.1, 20.5, 25.5)
          ..lineTo(20.5, 22)
          ..cubicTo(16.6, 21.6, 13.2, 23.5, 11.5, 27)
          ..quadraticBezierTo(9.8, 28.6, 10.2, 26)
          ..cubicTo(10.7, 19.2, 14.4, 15.9, 20.5, 15)
          ..close(),
        fill,
      );
    } else if (icon == Icons.title_rounded) {
      canvas.drawLine(const Offset(14, 14.8), const Offset(26, 14.8), stroke);
      canvas.drawLine(const Offset(20, 15), const Offset(20, 27.2), stroke);
    } else if (icon == Icons.download_rounded) {
      canvas.drawPath(
        Path()
          ..moveTo(20, 12)
          ..lineTo(20, 23.1)
          ..moveTo(15.8, 18.8)
          ..lineTo(20, 23.1)
          ..lineTo(24.2, 18.8)
          ..moveTo(12, 23.1)
          ..lineTo(12, 28.1)
          ..lineTo(28, 28.1)
          ..lineTo(28, 23.1),
        stroke,
      );
    } else if (icon == Icons.grid_view_rounded) {
      stroke.strokeWidth = 1.9;
      canvas.drawPath(
        Path()
          ..moveTo(14.7, 13.1)
          ..quadraticBezierTo(15.3, 12.3, 16.5, 12.3)
          ..lineTo(26.7, 12.3)
          ..quadraticBezierTo(29.1, 12.3, 29.1, 14.7)
          ..lineTo(29.1, 23.4)
          ..quadraticBezierTo(29.1, 24.5, 28.7, 24.9),
        stroke,
      );
      final frame = RRect.fromRectAndRadius(
          const Rect.fromLTRB(10.5, 16.3, 25.3, 28.6),
          const Radius.circular(2.5));
      canvas.save();
      canvas.clipRRect(frame);
      canvas.drawCircle(const Offset(14.8, 20.7), 1.75, fill);
      canvas.drawPath(
        Path()
          ..moveTo(11, 28.9)
          ..lineTo(14.1, 24.7)
          ..quadraticBezierTo(14.7, 24, 15.3, 24.7)
          ..lineTo(16.7, 26)
          ..lineTo(19.4, 22.3)
          ..quadraticBezierTo(20.2, 21.5, 20.8, 22.4)
          ..lineTo(25.5, 29)
          ..close(),
        fill,
      );
      canvas.restore();
      canvas.drawRRect(frame, stroke);
    } else if (icon == Icons.delete_outline_rounded) {
      stroke.strokeWidth = 2;
      canvas.drawPath(
        Path()
          ..moveTo(17, 12.7)
          ..lineTo(17, 12.2)
          ..quadraticBezierTo(17, 11.1, 18.2, 11.1)
          ..lineTo(21.8, 11.1)
          ..quadraticBezierTo(23, 11.1, 23, 12.2)
          ..lineTo(23, 12.7)
          ..moveTo(12.6, 14.7)
          ..lineTo(27.4, 14.7)
          ..moveTo(14, 15.2)
          ..lineTo(14, 28)
          ..quadraticBezierTo(14, 29.7, 15.7, 29.7)
          ..lineTo(24.3, 29.7)
          ..quadraticBezierTo(26, 29.7, 26, 28)
          ..lineTo(26, 15.2)
          ..moveTo(18.1, 18.8)
          ..lineTo(18.1, 25.5)
          ..moveTo(21.9, 18.8)
          ..lineTo(21.9, 25.5),
        stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReferenceIconPainter oldDelegate) =>
      oldDelegate.icon != icon;
}
