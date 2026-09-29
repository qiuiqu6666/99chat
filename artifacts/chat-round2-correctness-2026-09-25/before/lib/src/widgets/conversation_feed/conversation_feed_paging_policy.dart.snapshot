import 'dart:math' as math;

/// A virtual list's placeholder tail is not downloaded content. Base SDK
/// lookahead on real rows so requests start before the user reaches that tail.
bool conversationFeedNeedsPage({
  required double viewportHeight,
  required double extentAfter,
  required double pixels,
  double? loadedContentExtent,
}) {
  final remaining = loadedContentExtent == null
      ? extentAfter
      : loadedContentExtent - pixels - viewportHeight;
  return remaining < math.max(640.0, viewportHeight * 0.9);
}

/// Near-top lookahead for restoring a contiguous newer prefix after a trim.
bool conversationFeedNeedsNewerPrefix({
  required double viewportHeight,
  required double pixels,
}) {
  return pixels < math.max(640.0, viewportHeight * 0.9);
}
