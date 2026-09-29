import 'package:flutter/widgets.dart';

/// 真最新端：列表尽头 + 已确认投影 tip 已进当前连续窗口 + 窗口不缺更新页。
///
/// 像素距离只做几何容错。缓冲非空 / N>0 不是历史缺页，也不裁决物化。
class TrueLatestEnd {
  TrueLatestEnd._();

  /// 布局/浮点抖动。不得用几十像素表达产品「到底」。
  static const double geometryEpsilon = 2.0;

  static bool isAtListEnd({
    required double distanceFromLatestEdge,
    bool overscrolledPastLatest = false,
  }) {
    if (overscrolledPastLatest) {
      return true;
    }
    return distanceFromLatestEdge.abs() <= geometryEpsilon;
  }

  static bool atListEndFromPosition(ScrollPosition? position) {
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    final distance = position.pixels - position.minScrollExtent;
    final overscrolledPastLatest =
        position.outOfRange && position.pixels < position.minScrollExtent;
    return isAtListEnd(
      distanceFromLatestEdge: distance,
      overscrolledPastLatest: overscrolledPastLatest,
    );
  }

  /// 已确认投影（不含自己的 SENDING/FAILED 占位）的 tip 已出现在已建列表。
  static bool isLatestRowMaterialized({
    required bool latestConfirmedIdentityInBuiltList,
    @Deprecated('Buffer empty is not materialization')
    bool latestIdentityInBuiltList = false,
    @Deprecated('Buffer empty is not materialization')
    int bufferedNewerCount = 0,
  }) {
    return latestConfirmedIdentityInBuiltList;
  }

  /// 仅历史页缺口。live buffer / receivedCount / durable 热账不是缺页。
  static bool hasMissingNewer({
    required bool haveMoreLatestData,
    required bool memoryWindowMissingNewer,
    bool historyKnownTipMissing = false,
    @Deprecated('Live buffer is not a history page gap')
    bool durableGapWithLiveDeliveries = false,
  }) {
    return haveMoreLatestData ||
        memoryWindowMissingNewer ||
        historyKnownTipMissing;
  }

  static bool atTrueLatestEnd({
    required bool atListEnd,
    required bool latestRowMaterialized,
    required bool hasMissingNewer,
  }) {
    return atListEnd && latestRowMaterialized && !hasMissingNewer;
  }
}
