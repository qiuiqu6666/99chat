import 'package:flutter/material.dart';
import '../i18n/app_i18n.dart';

/// Use logical pixels and the safe viewport, never physical screen resolution.
BoxConstraints homeQuickMenuConstraints(MediaQueryData media) {
  final availableWidth = (media.size.width - media.padding.horizontal - 24)
      .clamp(0.0, double.infinity);
  final preferredWidth = (media.size.shortestSide * .56).clamp(200.0, 224.0);
  final width = preferredWidth.clamp(0.0, availableWidth);
  final height = (media.size.height -
          media.padding.vertical -
          media.viewInsets.bottom -
          24)
      .clamp(0.0, double.infinity);
  return BoxConstraints(
      minWidth: width, maxWidth: width, maxHeight: height * .65);
}

class HomeQuickActionTile extends StatelessWidget {
  const HomeQuickActionTile(
      {required this.id,
      required this.title,
      this.divider = true,
      this.dark = false,
      super.key});
  final String id;
  final String title;
  final bool divider;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final subtitle = switch (id) {
      'searchAdd' => i18n.t(
          zhHans: '通过账号/手机号搜索好友',
          zhHant: '透過帳號/手機號搜尋好友',
          en: 'Find friends by account or phone',
          ja: 'アカウント・電話番号で検索',
          ko: '계정 또는 전화번호로 검색'),
      'createGroup' => i18n.t(
          zhHans: '发起多人聊天',
          zhHant: '發起多人聊天',
          en: 'Start a group conversation',
          ja: 'グループチャットを開始',
          ko: '그룹 대화 시작'),
      'createChannel' => i18n.t(
          zhHans: '发布内容，供订阅者阅读',
          zhHant: '發佈內容，供訂閱者閱讀',
          en: 'Publish posts for subscribers',
          ja: '購読者に投稿を公開',
          ko: '구독자에게 게시물 발행'),
      _ => i18n.t(
          zhHans: '扫描二维码添加好友',
          zhHant: '掃描 QR 碼添加好友',
          en: 'Scan a QR code to add friends',
          ja: 'QRコードで友だちを追加',
          ko: 'QR 코드로 친구 추가'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          border: divider
              ? Border(
                  bottom: BorderSide(
                      color: dark
                          ? const Color(0xFF383A40)
                          : const Color(0xFFF0F1F4)))
              : null),
      child: Row(children: [
        Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: dark ? const Color(0xFF203B56) : const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(10)),
            child: Center(
                child: SizedBox.square(
                    dimension: 21,
                    child: CustomPaint(painter: _QuickActionPainter(id))))),
        const SizedBox(width: 9),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(title,
                  style: TextStyle(
                      color: dark ? Colors.white : const Color(0xFF101522),
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(
                      color: dark
                          ? const Color(0xFFA7ABB6)
                          : const Color(0xFF7B8190),
                      fontSize: 10,
                      height: 1.4)),
            ])),
        const SizedBox(width: 8),
        const SizedBox(
            width: 7,
            height: 12,
            child: CustomPaint(painter: _QuickChevronPainter())),
      ]),
    );
  }
}

class _QuickActionPainter extends CustomPainter {
  const _QuickActionPainter(this.id);
  final String id;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 36, size.height / 36);
    final fill = Paint()..color = const Color(0xFF0088FF);
    final line = Paint()
      ..color = fill.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (id == 'searchAdd') {
      canvas.drawCircle(const Offset(13, 10), 6, fill);
      canvas.drawPath(
          Path()
            ..moveTo(2, 29)
            ..cubicTo(2, 22, 8, 18, 16, 19)
            ..cubicTo(13, 23, 13, 27, 15, 30)
            ..lineTo(4, 30)
            ..quadraticBezierTo(2, 30, 2, 29),
          fill);
      canvas.drawCircle(const Offset(23, 25), 5.5, line);
      canvas.drawLine(const Offset(27, 29), const Offset(32, 34), line);
    } else if (id == 'createGroup') {
      canvas.drawCircle(const Offset(12, 11), 5.6, fill);
      canvas.drawCircle(const Offset(25, 13), 4.8, fill);
      canvas.drawPath(
          Path()
            ..moveTo(1.2, 29)
            ..cubicTo(1.2, 17, 23, 17, 23, 29)
            ..quadraticBezierTo(23, 31, 21, 31)
            ..lineTo(3.2, 31)
            ..quadraticBezierTo(1.2, 31, 1.2, 29),
          fill);
      canvas.drawPath(
          Path()
            ..moveTo(23, 21)
            ..cubicTo(30, 19.5, 34, 24, 34, 29)
            ..quadraticBezierTo(34, 30, 32, 30)
            ..lineTo(25, 30)
            ..cubicTo(26, 27, 25, 24, 23, 21),
          fill);
    } else if (id == 'createChannel') {
      canvas.drawCircle(const Offset(18, 18), 14, fill);
      canvas.drawPath(
          Path()
            ..moveTo(10, 16)
            ..lineTo(26, 10)
            ..lineTo(26, 26)
            ..lineTo(10, 20)
            ..close(),
          Paint()..color = Colors.white);
      canvas.drawRect(
          const Rect.fromLTWH(8, 15, 4, 7), Paint()..color = Colors.white);
    } else {
      final p = Path();
      p.moveTo(4, 11);
      p.lineTo(4, 7);
      p.quadraticBezierTo(4, 4, 7, 4);
      p.lineTo(11, 4);
      p.moveTo(25, 4);
      p.lineTo(29, 4);
      p.quadraticBezierTo(32, 4, 32, 7);
      p.lineTo(32, 11);
      p.moveTo(32, 25);
      p.lineTo(32, 29);
      p.quadraticBezierTo(32, 32, 29, 32);
      p.lineTo(25, 32);
      p.moveTo(11, 32);
      p.lineTo(7, 32);
      p.quadraticBezierTo(4, 32, 4, 29);
      p.lineTo(4, 25);
      p.moveTo(7.5, 18);
      p.lineTo(28.5, 18);
      canvas.drawPath(p, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QuickActionPainter oldDelegate) => oldDelegate.id != id;
}

class _QuickChevronPainter extends CustomPainter {
  const _QuickChevronPainter();
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      Path()
        ..moveTo(1, 1)
        ..lineTo(size.width - 1, size.height / 2)
        ..lineTo(1, size.height - 1),
      Paint()
        ..color = const Color(0xFF828898)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
  @override
  bool shouldRepaint(_QuickChevronPainter oldDelegate) => false;
}

class HomeQuickMenuShape extends ShapeBorder {
  const HomeQuickMenuShape(
      {required this.arrowX, this.borderColor = const Color(0xFFE9EAEE)});
  final double arrowX;
  final Color borderColor;
  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.only(top: 8);
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final x = arrowX.clamp(8.0, rect.width - 8) + rect.left;
    final card =
        Rect.fromLTRB(rect.left, rect.top + 8, rect.right, rect.bottom);
    return Path.combine(
        PathOperation.union,
        Path()
          ..addRRect(RRect.fromRectAndRadius(card, const Radius.circular(12))),
        Path()
          ..moveTo(x - 6, card.top + 1)
          ..lineTo(x, rect.top)
          ..lineTo(x + 6, card.top + 1)
          ..close());
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      canvas.drawPath(
          getOuterPath(rect),
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
}
