import 'package:flutter/widgets.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// endOfFrame called from a post-frame callback waits for the NEXT frame,
/// but Flutter only schedules that frame automatically when the scheduler is
/// idle. Search starts in a post-frame callback and must request it explicitly.
Future<void> waitForSearchJumpLayout() {
  final binding = WidgetsBinding.instance;
  final frame = binding.endOfFrame;
  binding.scheduleFrame();
  return frame;
}

/// Correct measured geometry rather than accepting a broad "near center"
/// band. The reverse chat viewport moves content down as pixels increase.
double searchJumpCenterOffset({
  required double centerDelta,
  required ScrollMetrics metrics,
}) =>
    (metrics.pixels +
            (metrics.axisDirection == AxisDirection.up
                ? -centerDelta
                : centerDelta))
        .clamp(metrics.minScrollExtent, metrics.maxScrollExtent);

/// The reverse, centered chat slivers use -globalIndex as their tag. The
/// package's offscreen forecast rejects negative offsets, which are valid
/// on the newer side of the center sliver. Materialize the target using chat order before asking it to align.
Future<bool> materializeSearchJumpTarget({
  required AutoScrollController controller,
  required int? Function() resolveIndex,
  required bool Function() isActive,
}) async {
  for (var step = 0; step < 80; step++) {
    if (!isActive() || controller.positions.length != 1) return false;
    final index = resolveIndex();
    if (index == null) return false;
    if (controller.tagMap.containsKey(-index)) return true;
    final position = controller.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      await waitForSearchJumpLayout();
      continue;
    }
    final indices = controller.tagMap.keys.map((tag) => -tag).toList()..sort();
    if (indices.isEmpty) {
      await waitForSearchJumpLayout();
      continue;
    }
    final direction = index > indices.last ? 1.0 : -1.0;
    final next = (position.pixels + direction * position.viewportDimension * .8)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((next - position.pixels).abs() < .5) return false;
    controller.jumpTo(next);
    await waitForSearchJumpLayout();
  }
  return false;
}

/// Edge rows cannot always reach the center. Accept the closest reachable
/// offset only when the target is actually visible.
bool searchJumpAtReachablePosition({
  required double targetTop,
  required double targetHeight,
  required double viewportHeight,
  required ScrollMetrics metrics,
  required double tolerance,
}) {
  final delta = targetTop + targetHeight / 2 - viewportHeight / 2;
  if (delta.abs() <= tolerance) return true;
  if (targetTop >= viewportHeight || targetTop + targetHeight <= 0) {
    return false;
  }
  final desired = metrics.pixels +
      (metrics.axisDirection == AxisDirection.up ? -delta : delta);
  final reachable =
      desired.clamp(metrics.minScrollExtent, metrics.maxScrollExtent);
  return (reachable - metrics.pixels).abs() <= 1;
}
