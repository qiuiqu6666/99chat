import 'package:flutter/material.dart';

/// Single-line text that seamless-scrolls only when it overflows its width.
class OverflowTextMarquee extends StatefulWidget {
  const OverflowTextMarquee({
    super.key,
    required this.text,
    required this.style,
    required this.height,
    this.velocity = 42.0,
    this.gap = 56,
  });

  final String text;
  final TextStyle style;
  final double height;
  final double velocity;
  final double gap;

  @override
  State<OverflowTextMarquee> createState() => _OverflowTextMarqueeState();
}

class _OverflowTextMarqueeState extends State<OverflowTextMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _normalizedText =>
      widget.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  void _syncAnimation(bool shouldScroll, Duration duration) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!shouldScroll) {
        if (_controller.isAnimating) {
          _controller.stop();
        }
        return;
      }
      if (_controller.duration != duration) {
        _controller.duration = duration;
        _controller
          ..reset()
          ..repeat();
      } else if (!_controller.isAnimating) {
        _controller
          ..reset()
          ..repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _normalizedText;
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final painter = TextPainter(
            text: TextSpan(text: text, style: widget.style),
            maxLines: 1,
            textDirection: Directionality.of(context),
          )..layout();
          final textWidth = painter.width;
          final shouldScroll = maxWidth > 0 && textWidth > maxWidth + 0.5;

          if (!shouldScroll) {
            _syncAnimation(false, Duration.zero);
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.style,
              ),
            );
          }

          final loopWidth = textWidth + widget.gap;
          final durationMs = (loopWidth / widget.velocity * 1000)
              .round()
              .clamp(2500, 60000);
          _syncAnimation(
            true,
            Duration(milliseconds: durationMs),
          );

          final line = Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: widget.style,
          );

          return Semantics(
            label: text,
            child: ExcludeSemantics(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(-_controller.value * loopWidth, 0),
                      child: child,
                    );
                  },
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        line,
                        SizedBox(width: widget.gap),
                        line,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
