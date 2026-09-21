import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

/// 聊天内红包 / 转账 / 名片卡片尺寸：移动端走 ScreenUtil，Web 宽/高分轨缩放。
abstract final class ChatWalletCardMetrics {
  ChatWalletCardMetrics._();

  static const double designMaxWidth = 340;
  static const double designMinWidth = 180;

  /// 手机聊天卡片最大宽度。桌面仍走 [desktopCardMaxWidth]，互不影响。
  static const double mobileCardMaxWidth = 290;
  static const double mobileCardMinWidth = 168;
  static const double designMinCardHeight = 156;

  /// 脚栏块设计高度：上下 padding 8+8 + 一行脚栏字约 24。
  static const double designFooterBlockHeight = 40;
  static const double designIconSize = 68;

  /// Web 横向（宽度、字号、圆角）。
  static const double webWidthScale = 0.82;

  /// Web 纵向基准（高度、竖向内边距），与宽度分轨避免改宽时拉高卡片。
  static const double webHeightScale = 0.72;

  /// Web 纵向额外压缩。
  static const double webVerticalScale = 0.68;

  /// Web 卡片正文字号额外压缩（红包/转账/名片内文）。
  static const double webCardTextScale = 0.78;

  /// 桌面走 8pt 节奏：宽高同一倍率，头像 40，高度随内容，不强制撑高。
  static const double desktopLayoutScale = 0.75;
  static const double desktopCardMaxWidth = 264;
  static const double desktopIconSizePx = 40;
  static const double desktopTitleFontSize = 14;
  static const double desktopSubtitleFontSize = 12;
  static const double desktopFooterFontSize = 11;
  static const double desktopFooterPadV = 6;

  /// A transient zero/unbounded root viewport can poison ScreenUtil's global
  /// scale during chat startup. Keep card geometry within logical-pixel
  /// bounds so one custom message cannot expand the entire sliver.
  static const double minMobileScale = 0.5;
  static const double maxMobileScale = 1.5;

  static bool get isWeb => PlatformUtils().isWeb;

  static bool get useDesktopChatCard =>
      !isWeb && PlatformUtils().isDesktop;

  /// 750 设计稿在 375 逻辑宽上的倍率。
  static const double desktopLogicalScale = 0.5;

  static double get maxWidth {
    if (isWeb) return designMaxWidth * webWidthScale;
    if (useDesktopChatCard) {
      return desktopCardMaxWidth;
    }
    return mobileCardMaxWidth;
  }

  static double get minWidth {
    if (isWeb) return designMinWidth * webWidthScale;
    if (useDesktopChatCard) {
      return 200;
    }
    return mobileCardMinWidth;
  }

  static double get minCardHeight {
    if (isWeb) {
      return designMinCardHeight * webHeightScale * webVerticalScale;
    }
    if (useDesktopChatCard) {
      return 0;
    }
    return h(designMinCardHeight);
  }

  static double get footerBlockHeight {
    if (isWeb) {
      return designFooterBlockHeight * webHeightScale * webVerticalScale;
    }
    if (useDesktopChatCard) {
      return 0;
    }
    return h(designFooterBlockHeight);
  }

  /// 内容区最小高度，保证整卡 ≥ [minCardHeight] 且脚栏贴底。
  static double get minBodyHeight {
    final value = minCardHeight - footerBlockHeight;
    return value > 0 ? value : 0;
  }

  static double desktopMaxWidthForChat() => maxWidth;

  static double clampCardWidth(double parentMax) {
    if (!parentMax.isFinite || parentMax <= 0) {
      return maxWidth;
    }
    return math.min(maxWidth, math.max(minWidth, parentMax));
  }

  @visibleForTesting
  static double boundedMobileScale(double rawScale) {
    if (!rawScale.isFinite || rawScale <= 0) {
      return 1;
    }
    return rawScale.clamp(minMobileScale, maxMobileScale).toDouble();
  }

  static double _safeMobileScaled(
    num value,
    double Function(num value) scale,
  ) {
    final designValue = value.toDouble();
    if (designValue == 0) return 0;
    try {
      final scaled = scale(value);
      final rawScale = scaled / designValue;
      return designValue * boundedMobileScale(rawScale);
    } catch (_) {
      return designValue;
    }
  }

  static double w(num value) {
    if (isWeb) return value.toDouble() * webWidthScale;
    if (useDesktopChatCard) {
      return value.toDouble() * desktopLayoutScale;
    }
    return _safeMobileScaled(value, (input) => input.w);
  }

  static double h(num value) {
    if (isWeb) {
      return value.toDouble() * webHeightScale * webVerticalScale;
    }
    if (useDesktopChatCard) {
      return value.toDouble() * desktopLayoutScale;
    }
    return _safeMobileScaled(value, (input) => input.h);
  }

  static double sp(num value) {
    if (isWeb) return value.toDouble() * webWidthScale;
    if (useDesktopChatCard) {
      return value.toDouble() * desktopLogicalScale;
    }
    return _safeMobileScaled(value, (input) => input.sp);
  }

  static double r(num value) {
    if (isWeb) return value.toDouble() * webWidthScale;
    if (useDesktopChatCard) {
      return value.toDouble() * desktopLayoutScale;
    }
    return _safeMobileScaled(value, (input) => input.r);
  }

  static double iconSize([num design = designIconSize]) {
    if (isWeb) return design.toDouble() * webHeightScale * 0.78;
    if (useDesktopChatCard) return desktopIconSizePx;
    return w(design);
  }

  static double footerSp([num design = 18]) {
    if (isWeb) return design.toDouble() * webHeightScale * 0.92;
    if (useDesktopChatCard) return desktopFooterFontSize;
    return sp(design);
  }

  static double titleFontSize({required double mobile}) =>
      useDesktopChatCard ? desktopTitleFontSize : mobile;

  static double subtitleFontSize({required double mobile}) =>
      useDesktopChatCard ? desktopSubtitleFontSize : mobile;

  /// 飞书 PC 卡片 12px 内边距；微信 PC 支付卡约 10/12。桌面写死逻辑像素。
  static EdgeInsets get bodyPadding {
    if (useDesktopChatCard) {
      return const EdgeInsets.fromLTRB(12, 10, 12, 8);
    }
    return EdgeInsets.fromLTRB(w(16), h(12), w(16), h(8));
  }

  static EdgeInsets get footerPadding {
    if (useDesktopChatCard) {
      return const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: desktopFooterPadV,
      );
    }
    return EdgeInsets.symmetric(horizontal: w(16), vertical: h(8));
  }

  static double get leadingTextGap =>
      useDesktopChatCard ? 10 : w(12);

  /// 标题与副标题：桌面 4px（4N / 8pt 半格），避免三张卡各用 6/8/10。
  static double lineGap({required double mobile}) =>
      useDesktopChatCard ? 4 : mobile;

  /// 卡片主体文案（标题/金额/副标题），Web 比 [sp] 再小一档。
  static double cardSp(num value) {
    if (isWeb) {
      return value.toDouble() * webWidthScale * webCardTextScale;
    }
    if (useDesktopChatCard) {
      return value.toDouble() * desktopLogicalScale;
    }
    return _safeMobileScaled(value, (input) => input.sp);
  }
}
