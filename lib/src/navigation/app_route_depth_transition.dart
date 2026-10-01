import 'package:flutter/material.dart';

/// The route below an incoming page recedes and darkens with that page's
/// animation. Keeping this in the route transition preserves the page subtree.
class AppRouteDepthTransition extends StatelessWidget {
  const AppRouteDepthTransition({
    super.key,
    required this.animation,
    required this.child,
    this.curve = defaultCurve,
    this.reverseCurve = defaultCurve,
  });

  static const Duration transitionDuration = Duration(milliseconds: 340);
  static const Curve defaultCurve = Curves.fastEaseInToSlowEaseOut;
  static const double recededScale = 0.96;
  static const double maximumScrimOpacity = 0.55;

  /// Lets a MaterialPageRoute below an AppMaterialPageRoute join the transition.
  static Widget? delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) return null;
    return AppRouteDepthTransition(
      animation: secondaryAnimation,
      child: child,
    );
  }

  final Animation<double> animation;
  final Widget child;
  final Curve curve;
  final Curve reverseCurve;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final activeCurve =
            animation.status == AnimationStatus.reverse ? reverseCurve : curve;
        final progress = activeCurve.transform(animation.value.clamp(0.0, 1.0));
        final scrimOpacity = maximumScrimOpacity * progress;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scale: 1.0 - (1.0 - recededScale) * progress,
                child: child!,
              ),
              // One scrim covers both the receding page and its exposed edge.
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color.fromRGBO(0, 0, 0, scrimOpacity),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
