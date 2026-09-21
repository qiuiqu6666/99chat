import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/true_latest_end.dart';

/// 「回到底部」胶囊显隐。
///
/// 真最新端隐藏。N 不点亮胶囊。离开 FOLLOW 用固定 24px；胶囊用 0.5 屏。
class BackToBottomCapsulePolicy {
  BackToBottomCapsulePolicy._();

  /// 用户主动离开 LIVE FOLLOW 的固定逻辑距离。
  static const double followExitThresholdPx = 24.0;

  /// 离开 FOLLOW 后，超过该视口比例才显示胶囊。
  static const double capsuleShowViewportRatio = 0.5;

  /// 已显示后的隐藏滞回。
  static const double capsuleHideViewportRatio = 0.45;

  /// 视口未布局时第二档的兜底视口高度。
  static const double fallbackViewportDimension = 600.0;

  /// 离开底部超过约一屏才点亮「回到底部」（无 N 时）。保留旧名供引用。
  static const double showViewportRatio = capsuleShowViewportRatio;

  /// 隐藏滞后，避免在阈值附近闪烁。
  static const double hideViewportRatio = capsuleHideViewportRatio;

  /// 几何尽头容差。产品贴底以 [TrueLatestEnd] 为准。
  static const double geometryEpsilon = TrueLatestEnd.geometryEpsilon;

  static bool isAtListEnd(double distanceFromBottom) {
    return TrueLatestEnd.isAtListEnd(distanceFromLatestEdge: distanceFromBottom);
  }

  /// 兼容旧名：语义为几何尽头，不是 24px 产品贴底。
  static bool isPhysicallyAtBottom(double distanceFromBottom) {
    return isAtListEnd(distanceFromBottom);
  }

  static double effectiveViewportDimension(double viewportDimension) {
    return viewportDimension > 0 ? viewportDimension : fallbackViewportDimension;
  }

  static bool shouldShow({
    required bool atTrueLatestEnd,
    required bool hasMissingNewer,
    double distanceFromLatestEdge = 0,
    double viewportDimension = 0,
    bool capsuleCurrentlyVisible = false,
    required bool presentationBottomLocked,
    required bool programmaticScrollToBottom,
    @Deprecated('N does not light the capsule') int liveUnreadCount = 0,
    @Deprecated('Use distanceFromLatestEdge') bool leftBottomByOneScreen = false,
    @Deprecated('Use atTrueLatestEnd') bool physicallyAtBottom = false,
    @Deprecated('Not a product SSOT') bool latestMessageVisible = false,
    @Deprecated('Use hasMissingNewer') bool missingNewerThanViewport = false,
  }) {
    if (presentationBottomLocked || programmaticScrollToBottom) {
      return false;
    }
    if (atTrueLatestEnd) {
      return false;
    }
    if (hasMissingNewer || missingNewerThanViewport) {
      return true;
    }
    if (distanceFromLatestEdge <= followExitThresholdPx) {
      return false;
    }
    final viewport = effectiveViewportDimension(viewportDimension);
    final showAt = viewport * capsuleShowViewportRatio;
    final hideAt = viewport * capsuleHideViewportRatio;
    if (capsuleCurrentlyVisible) {
      return distanceFromLatestEdge >= hideAt;
    }
    return distanceFromLatestEdge >= showAt;
  }
}
