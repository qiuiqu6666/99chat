import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A short, local burst that does not change the underlying star action.
class StarBurstButton extends StatefulWidget {
  const StarBurstButton(
      {super.key,
      required this.starred,
      required this.tooltip,
      required this.backgroundColor,
      required this.color,
      required this.onPressed});
  final bool starred;
  final String tooltip;
  final Color backgroundColor;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  State<StarBurstButton> createState() => _StarBurstButtonState();
}

class _StarBurstButtonState extends State<StarBurstButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (!MediaQuery.disableAnimationsOf(context)) _controller.forward(from: 0);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final active = _controller.isAnimating;
        final fade = active ? math.sin(math.pi * t) : 0.0;
        final scale =
            active ? 1 + .28 * math.sin(t * math.pi * 2) * (1 - t) : 1.0;
        return SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (active) ...[
                  Positioned(
                    left: -16,
                    top: -16,
                    width: 80,
                    height: 80,
                    child: IgnorePointer(
                        child: Transform.scale(
                      scale: .6 + t * .6,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          Colors.amber.withValues(alpha: fade * .35),
                          Colors.amber.withValues(alpha: 0),
                        ]),
                      )),
                    )),
                  ),
                  for (var i = 0; i < 8; i++)
                    Positioned(
                      left: 20 + math.cos(i * math.pi / 4) * (15 + 22 * t),
                      top: 20 + math.sin(i * math.pi / 4) * (15 + 22 * t),
                      child: IgnorePointer(
                          child: Opacity(
                              opacity: fade,
                              child: Icon(Icons.auto_awesome,
                                  size: 8 * (1 - .4 * t),
                                  color: const Color(0xFFFFBA38)))),
                    ),
                ],
                Transform.scale(
                    scale: scale,
                    child: IconButton(
                      tooltip: widget.tooltip,
                      onPressed: _busy ? null : _tap,
                      style: IconButton.styleFrom(
                          backgroundColor: widget.backgroundColor),
                      icon: Icon(
                          widget.starred
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: widget.color,
                          size: 26),
                    )),
              ],
            ));
      },
    );
  }
}
