import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Uses the last plain-text line for the footer when there is room. Rich text
/// and bidi content keep a separate footer so links, emoji and selection retain
/// their original layout. No frame-delayed measuring or message mutation.
class ChatTextBubbleLayout extends StatelessWidget {
  const ChatTextBubbleLayout({
    super.key,
    required this.text,
    required this.textStyle,
    required this.timeText,
    required this.body,
    required this.metadata,
    this.reserveReceipt = false,
    this.forceSeparateFooter = false,
  });

  final String text;
  final TextStyle textStyle;
  final String timeText;
  final Widget body;
  final Widget metadata;
  final bool reserveReceipt;
  final bool forceSeparateFooter;

  bool get _plainText =>
      !text.contains(RegExp(r'[\[\]@*_`#<>\t\r]|://|www\.')) &&
      !text.codeUnits.any((unit) =>
          (unit >= 0xD800 && unit <= 0xDFFF) ||
          (unit >= 0x0590 && unit <= 0x08FF) ||
          (unit >= 0x200B && unit <= 0x206F));

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final footerPainter = TextPainter(
      text: TextSpan(
        text: timeText,
        style: DefaultTextStyle.of(context).style.merge(
          const TextStyle(fontSize: 11, height: 1),
        ),
      ),
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    // Reserve the double-check width before its status changes.
    final footerWidth =
        (footerPainter.width + (reserveReceipt ? 20 : 0) + 2).ceilToDouble();
    final footerHeight = math.max(footerPainter.height, 10.0);
    footerPainter.dispose();

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final inlineAllowed = !forceSeparateFooter &&
          direction == TextDirection.ltr &&
          _plainText &&
          maxWidth > footerWidth + 8;
      if (!inlineAllowed) {
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: metadata,
            )
          ],
        );
        // Emoji/short links must not expand to a full-width empty card.
        // Markdown and preview cards may contain LayoutBuilder, so those keep
        // the bounded width without requesting intrinsic layout.
        return forceSeparateFooter ? content : IntrinsicWidth(child: content);
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth);
      final lines = painter.computeLineMetrics();
      final longest =
          lines.fold<double>(0, (width, line) => math.max(width, line.width));
      final lastWidth = lines.isEmpty ? 0.0 : lines.last.width;
      final neededWidth = math.max(longest, lastWidth + 8 + footerWidth);
      final inline = neededWidth.ceilToDouble() + 1 <= maxWidth &&
          (lines.isEmpty || lines.last.height >= footerHeight);
      final width = inline
          ? math.min(maxWidth, neededWidth.ceilToDouble() + 1)
          : maxWidth;
      painter.dispose();
      return SizedBox(
        width: width,
        child: Stack(children: [
          Padding(
            padding: EdgeInsets.only(bottom: inline ? 0 : footerHeight + 4),
            child: SizedBox(width: width, child: body),
          ),
          Positioned(
              right: 0,
              bottom: 0,
              child: SizedBox(
                  width: footerWidth,
                  height: footerHeight,
                  child: Align(
                      alignment: Alignment.centerRight, child: metadata))),
        ]),
      );
    });
  }
}
