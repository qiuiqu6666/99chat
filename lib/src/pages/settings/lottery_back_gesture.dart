import 'package:flutter/material.dart';

/// Edge-only back gesture for the lottery's custom card-expansion route.
/// Keeps horizontal attribute scrolling and the existing route animation intact.
class LotteryBackGesture extends StatefulWidget {
  const LotteryBackGesture({super.key, required this.child});
  final Widget child;

  @override
  State<LotteryBackGesture> createState() => _LotteryBackGestureState();
}

class _LotteryBackGestureState extends State<LotteryBackGesture> {
  double _distance = 0;
  bool _popping = false;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final enabled = Navigator.of(context).canPop() && route?.isCurrent == true;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (enabled)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            key: const ValueKey('lottery-back-edge'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _distance = 0,
            onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
            onHorizontalDragCancel: () => _distance = 0,
            onHorizontalDragEnd: (details) async {
              final velocity = details.primaryVelocity ?? 0;
              final shouldPop = velocity >= 0 &&
                  (_distance >= 72 || (_distance >= 20 && velocity >= 600));
              _distance = 0;
              if (!shouldPop ||
                  _popping ||
                  route?.isCurrent != true ||
                  route?.animation?.status != AnimationStatus.completed) return;
              _popping = true;
              try {
                await Navigator.of(context).maybePop();
              } finally {
                _popping = false;
              }
            },
          ),
        ),
    ]);
  }
}
