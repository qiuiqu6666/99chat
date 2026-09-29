import 'dart:math' as math;

import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';

/// Distance gates for loading an older history page before the visual top.
class HistoryPreviousPrefetchPolicy {
  HistoryPreviousPrefetchPolicy._();

  static double prefetchDistancePx(double cacheExtent) {
    return math.max(
      ChatListPaginationUiGate.loadPreviousTopNearPx,
      cacheExtent,
    );
  }

  static double remainingToOldestEdge({
    required double pixels,
    required double maxScrollExtent,
  }) {
    return maxScrollExtent - pixels;
  }

  static bool isInPreviousPrefetchBand({
    required double pixels,
    required double maxScrollExtent,
    required double prefetchPx,
    required bool hasPixels,
    required bool hasContentDimensions,
  }) {
    if (!hasPixels || !hasContentDimensions) {
      return false;
    }
    if (maxScrollExtent <= 0) {
      return false;
    }
    return remainingToOldestEdge(
          pixels: pixels,
          maxScrollExtent: maxScrollExtent,
        ) <=
        prefetchPx;
  }

  static bool shouldShowPreviousLoadSpinner({
    required double pixels,
    required double maxScrollExtent,
    required bool hasPixels,
    required bool hasContentDimensions,
  }) {
    return isInPreviousPrefetchBand(
      pixels: pixels,
      maxScrollExtent: maxScrollExtent,
      prefetchPx: ChatListPaginationUiGate.loadPreviousTopNearPx,
      hasPixels: hasPixels,
      hasContentDimensions: hasContentDimensions,
    );
  }
}
