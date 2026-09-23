import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';

/// Vector artwork follows the silver-outline / blue-fill moments reference.
class MomentsActionBar extends StatelessWidget {
  const MomentsActionBar({
    super.key,
    required this.dark,
    required this.liked,
    required this.likeLabel,
    required this.commentLabel,
    required this.onLike,
    required this.onComment,
    required this.onOpen,
    this.onDelete,
  });

  final bool dark;
  final bool liked;
  final String likeLabel;
  final String commentLabel;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? const Color(0xFFE8EAEE) : const Color(0xFF343B46);

    Widget action(_ActionGlyph glyph, String label, VoidCallback onTap,
        {bool selected = false}) {
      return Semantics(
        selected: selected,
        child: TextButton.icon(
          onPressed: onTap,
          icon: _ActionIcon(glyph: glyph, dark: dark),
          label: Text(label, style: const TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
            foregroundColor: selected ? const Color(0xFF39ACFA) : foreground,
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(_ActionGlyph.like, likeLabel, onLike, selected: liked),
        Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          color: dark ? const Color(0xFF303238) : const Color(0xFFDCE0E6),
        ),
        action(_ActionGlyph.comment, commentLabel, onComment),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: TIM_t('更多'),
          padding: EdgeInsets.zero,
          icon: Container(
            width: 40,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF25282E) : const Color(0xFFEBEEF2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: _ActionIcon(glyph: _ActionGlyph.more, dark: dark),
          ),
          onSelected: (action) {
            if (action == 'open') onOpen();
            if (action == 'delete') onDelete?.call();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'open', child: Text(TIM_t('查看详情'))),
            if (onDelete != null)
              PopupMenuItem(value: 'delete', child: Text(TIM_t('删除'))),
          ],
        ),
      ],
    );
  }
}

enum _ActionGlyph { like, comment, more }

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.glyph, required this.dark});

  final _ActionGlyph glyph;
  final bool dark;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: 24,
          child: CustomPaint(painter: _ActionIconPainter(glyph, dark)),
        ),
      );
}

class _ActionIconPainter extends CustomPainter {
  const _ActionIconPainter(this.glyph, this.dark);

  final _ActionGlyph glyph;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 96);
    const bounds = Rect.fromLTWH(0, 0, 96, 96);
    final silver = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [Color(0xFFF4F6F9), Color(0xFFBFC7D3)]
            : const [Color(0xFF697584), Color(0xFF424D5C)],
      ).createShader(bounds);
    final outline = Paint()
      ..shader = silver.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final blue = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF48C2FF), Color(0xFF2699F5)],
      ).createShader(bounds);

    switch (glyph) {
      case _ActionGlyph.like:
        final hand = Path()
          ..moveTo(32, 37)
          ..lineTo(55, 10)
          ..cubicTo(59, 5, 63, 9, 62, 15)
          ..lineTo(58, 35)
          ..lineTo(81, 35)
          ..cubicTo(89, 35, 92, 41, 89, 49)
          ..lineTo(78, 78)
          ..quadraticBezierTo(76, 84, 68, 84)
          ..lineTo(32, 84)
          ..close();
        canvas.drawPath(hand, blue);
        final silhouette = Path()
          ..moveTo(11, 38)
          ..lineTo(32, 38)
          ..lineTo(55, 10)
          ..cubicTo(59, 5, 63, 9, 62, 15)
          ..lineTo(58, 35)
          ..lineTo(81, 35)
          ..cubicTo(89, 35, 92, 41, 89, 49)
          ..lineTo(78, 78)
          ..quadraticBezierTo(76, 84, 68, 84)
          ..lineTo(11, 84)
          ..close();
        canvas.drawPath(silhouette, outline);
        canvas.drawLine(const Offset(29, 40), const Offset(29, 82), outline);
      case _ActionGlyph.comment:
        final bubble = Path()
          ..moveTo(22, 14)
          ..lineTo(74, 14)
          ..quadraticBezierTo(87, 14, 87, 27)
          ..lineTo(87, 61)
          ..quadraticBezierTo(87, 74, 74, 74)
          ..lineTo(40, 74)
          ..lineTo(23, 89)
          ..lineTo(23, 74)
          ..lineTo(22, 74)
          ..quadraticBezierTo(9, 74, 9, 61)
          ..lineTo(9, 27)
          ..quadraticBezierTo(9, 14, 22, 14)
          ..close();
        canvas.drawPath(bubble, outline);
        for (final x in [29.0, 48.0, 67.0]) {
          canvas.drawCircle(Offset(x, 44), 6, blue);
        }
      case _ActionGlyph.more:
        for (final x in [20.0, 48.0, 76.0]) {
          canvas.drawCircle(Offset(x, 48), 8.5, silver);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ActionIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.dark != dark;
}
