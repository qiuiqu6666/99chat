import 'package:flutter/widgets.dart';

/// Corrects a changing window's coordinate space during viewport layout.
/// Returning false requests a second layout; Flutter then updates the active
/// scroll activity against the corrected dimensions, including a running fling.
class ConversationAnchorScrollController extends ScrollController {
  double? Function(double pixels)? resolveLayoutOffset;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
      ScrollContext context, ScrollPosition? oldPosition) {
    return _AnchorScrollPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
    );
  }
}

class _AnchorScrollPosition extends ScrollPositionWithSingleContext {
  _AnchorScrollPosition(
      {required this.owner,
      required super.physics,
      required super.context,
      super.initialPixels,
      super.keepScrollOffset,
      super.oldPosition});
  final ConversationAnchorScrollController owner;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final target = owner.resolveLayoutOffset?.call(pixels);
    if (target != null) {
      final bounded = target.clamp(minScrollExtent, maxScrollExtent);
      if ((bounded - pixels).abs() > 0.01) {
        correctBy(bounded - pixels);
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
