import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// Shared design tokens for app surfaces.
///
/// Auth still uses the stronger brand presentation below, while product
/// screens should prefer the semantic tokens so chat, wallet, moments and
/// settings resolve to the same visual system.
class AppTokens {
  AppTokens._();

  // ── Color: Brand (deep business blue) ────────────────────────────────────
  static const Color brand500 = Color(0xFF1E90FF);
  static const Color brand600 = Color(0xFF1E90FF);
  static const Color brand700 = Color(0xFF1E90FF);
  static const Color brand400 = Color(0xFF1E90FF);
  static const Color brand300 = Color(0xFF1E90FF);
  static const Color brand50 = Color(0xFFEAF4FF);
  static const Color brand100 = Color(0xFFD7EBFF);

  // Chat light surfaces (conversation page chrome + bubbles).
  static const Color chatBgLight = Color(0xFFF4F5F7);
  static const Color chatChromeDivider = Color(0xFFEAEAEA);
  static const Color chatBubbleSelfLight = Color(0xFFDCEEFF);
  static const Color chatBubbleOtherLight = Color(0xFFFFFFFF);
  static const Color chatBubbleOtherBorder = Color(0xFFE8E9EC);
  static const Color chatBubbleTextLight = Color(0xFF1C1C1E);
  // Time-divider pill text color (TUIKit 5.0.1 only exposes text color;
  // pill background/widget structure are TUIKit-internal).
  static const Color chatTimestampLight = Color(0xFFA1A7B0);
  // Input fill in chat composer (slightly deeper than page background,
  // sandwiched between bg #F4F5F7 and border #E8E9EC).
  static const Color chatInputFillLight = Color(0xFFEEF0F3);
  // Group announcement pill on chat header (light-blue background + deep-blue text).
  static const Color chatAnnouncementBgLight = Color(0xFFEAF4FF);
  static const Color chatAnnouncementTextLight = Color(0xFF1F5BB7);
  static const double chatChromeDividerWidth = 0.5;
  static const double chatBubbleVerticalGap = 12;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E90FF), Color(0xFF1E90FF), Color(0xFF1E90FF)],
    stops: [0.0, 0.55, 1.0],
  );

  // ── Color: Neutral (slate-ish grays for elegant text hierarchy) ──────────
  static const Color ink900 = Color(0xFF0B1220);
  static const Color ink800 = Color(0xFF111827);
  static const Color ink700 = Color(0xFF1F2937);
  static const Color ink600 = Color(0xFF374151);
  static const Color ink500 = Color(0xFF4B5563);
  static const Color ink400 = Color(0xFF6B7280);
  static const Color ink300 = Color(0xFF9CA3AF);
  static const Color ink200 = Color(0xFFD1D5DB);
  static const Color ink150 = Color(0xFFE6E6E9);
  static const Color ink100 = Color(0xFFE5E7EB);
  static const Color ink50 = Color(0xFFF3F4F6);
  static const Color ink25 = Color(0xFFF9FAFB);

  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFFAFBFC);
  static const Color divider = Color(0xFFEEF0F4);
  static const Color fieldFill = Color(0xFFF1F2F4);

  // Semantic color tokens.
  static const Color backgroundLight = Color(0xFFF5F6F8);
  static const Color surfaceLight = Colors.white;
  static const Color surfaceAltLight = Color(0xFFF1F3F5);
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF7B8491);
  static const Color borderLight = Color(0xFFE6E8EC);
  static const Color shadowLight = Color(0x080B1220);

  static const Color backgroundDark = Color(0xFF101114);
  static const Color surfaceDark = Color(0xFF1B1D22);
  static const Color surfaceAltDark = Color(0xFF23262D);
  static const Color textPrimaryDark = Color(0xFFF4F4F4);
  static const Color textSecondaryDark = Color(0xFF9A9CA3);
  static const Color borderDark = Color(0xFF2A2D33);
  static const Color shadowDark = Color(0x2D000000);

  // Desktop left nav rail: keep it distinct from the white window chrome.
  static const Color desktopNavRailLight = Color(0xFF3F4C68);
  static const Color desktopNavRailDark = Color(0xFF16181E);
  static const Color desktopNavRailBorderLight = Color(0xFF334058);
  static const Color desktopNavRailBorderDark = Color(0xFF2A2D33);
  static const Color desktopNavRailInactiveLight = Color(0xFFC5CDD8);
  static const Color desktopNavRailInactiveDark = Color(0xFF9AA0AA);
  static const Color desktopNavRailLabelLight = Color(0xFFE8EDF4);
  static const Color desktopNavRailLabelDark = Color(0xFFE5E7EB);

  static const Color desktopTitleBarLight = Color(0xFFF2F3F5);
  static const Color desktopTitleBarDark = Color(0xFF1B1D22);
  static const Color desktopTitleBarBorderLight = Color(0xFFE6E8EC);
  static const Color desktopTitleBarBorderDark = Color(0xFF2A2D33);
  static const Color desktopTitleBarIconLight = Color(0xFF4B5563);
  static const Color desktopTitleBarIconDark = Color(0xFFD1D5DB);

  static Color desktopNavRail(bool dark) =>
      dark ? desktopNavRailDark : desktopNavRailLight;
  static Color desktopNavRailBorder(bool dark) =>
      dark ? desktopNavRailBorderDark : desktopNavRailBorderLight;
  static Color desktopNavRailInactive(bool dark) =>
      dark ? desktopNavRailInactiveDark : desktopNavRailInactiveLight;
  static Color desktopNavRailLabel(bool dark) =>
      dark ? desktopNavRailLabelDark : desktopNavRailLabelLight;
  static Color desktopTitleBar(bool dark) =>
      dark ? desktopTitleBarDark : desktopTitleBarLight;
  static Color desktopTitleBarBorder(bool dark) =>
      dark ? desktopTitleBarBorderDark : desktopTitleBarBorderLight;
  static Color desktopTitleBarIcon(bool dark) =>
      dark ? desktopTitleBarIconDark : desktopTitleBarIconLight;

  static const Color accent = brand500;
  static const Color accentSoft = brand50;
  static const Color danger = Color(0xFFDC2626);
  static const Color walletDanger = Color(0xFFE60022);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSurfaceLight = Color(0xFFFFF7E8);
  static const Color warningSurfaceDark = Color(0xFF332716);

  static Color appBackground(bool dark) =>
      dark ? backgroundDark : backgroundLight;
  static Color appSurface(bool dark) => dark ? surfaceDark : surfaceLight;
  static Color appSurfaceAlt(bool dark) =>
      dark ? surfaceAltDark : surfaceAltLight;
  static Color appTextPrimary(bool dark) =>
      dark ? textPrimaryDark : textPrimaryLight;
  static Color appTextSecondary(bool dark) =>
      dark ? textSecondaryDark : textSecondaryLight;
  static Color appBorder(bool dark) => dark ? borderDark : borderLight;
  static Color appShadow(bool dark) => dark ? shadowDark : shadowLight;

  // ── Spacing scale (4pt base) ─────────────────────────────────────────────
  static const double s2 = 4;
  static const double s3 = 8;
  static const double s4 = 12;
  static const double s5 = 16;
  static const double s6 = 20;
  static const double s7 = 24;
  static const double s8 = 32;
  static const double s9 = 40;
  static const double s10 = 56;

  // ── Radius ───────────────────────────────────────────────────────────────
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rCard = 18;
  static const double rXl = 20;
  static const double rPill = 999;

  static const double buttonHeight = 48;
  static const double listItemHeight = 56;

  // ── Elevation / shadows ──────────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: const Color(0xFF0B1220).withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
  static List<BoxShadow> get shadowBrand => [];

  // ── Typography ───────────────────────────────────────────────────────────
  /// 窄屏 Web / H5 用内置 NotoSansSC；原生移动端为 null（系统默认）。
  static String? get fontFamily => kIsWeb ? 'NotoSansSC' : null;

  /// 宽屏与桌面端用操作系统字体，不走内置 Noto。
  /// Android / iOS 原生返回 null，不改移动端。
  static String? get desktopUiFontFamily {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'Microsoft YaHei UI';
      case TargetPlatform.macOS:
        return 'PingFang SC';
      case TargetPlatform.linux:
        return 'Noto Sans CJK SC';
      case TargetPlatform.iOS:
        return kIsWeb ? 'PingFang SC' : null;
      case TargetPlatform.android:
        return kIsWeb ? 'sans-serif' : null;
      default:
        return null;
    }
  }

  static bool usesSystemUiFont(BuildContext context) {
    return PlatformUtils().isDesktop ||
        TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop;
  }

  static String? fontFamilyOf(BuildContext context) {
    if (usesSystemUiFont(context)) {
      return desktopUiFontFamily ?? fontFamily;
    }
    return fontFamily;
  }

  static List<String>? fontFamilyFallbackOf(BuildContext context) {
    if (usesSystemUiFont(context) && desktopUiFontFamily != null) {
      return desktopUiFontFamilyFallback;
    }
    return null;
  }

  static List<String> get desktopUiFontFamilyFallback {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return const ['Microsoft YaHei', 'Segoe UI'];
      case TargetPlatform.macOS:
        return const ['PingFang TC', 'Hiragino Sans GB', 'Helvetica Neue'];
      case TargetPlatform.linux:
        return const ['Noto Sans CJK TC', 'WenQuanYi Micro Hei', 'sans-serif'];
      case TargetPlatform.iOS:
        return const ['PingFang TC', 'Hiragino Sans GB', 'Helvetica Neue'];
      case TargetPlatform.android:
        return const ['Noto Sans CJK SC', 'Roboto', 'sans-serif'];
      default:
        return const <String>[];
    }
  }

  /// 桌面全局默认行高，避免中文被 1.0/1.1 裁切。
  static const double desktopUiLineHeight = 1.35;

  /// 宽屏 / 桌面端套系统字体族与标题层级；窄屏 Theme 不走这里。
  static ThemeData applyDesktopTypography(ThemeData theme) {
    final family = desktopUiFontFamily;
    if (family == null) return theme;
    final fallback = desktopUiFontFamilyFallback;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: (theme.appBarTheme.titleTextStyle ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
            .copyWith(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        toolbarTextStyle: (theme.appBarTheme.toolbarTextStyle ??
                const TextStyle(fontSize: 12))
            .copyWith(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        titleTextStyle: (theme.dialogTheme.titleTextStyle ??
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
            .copyWith(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 16,
          height: 1.25,
        ),
        contentTextStyle: (theme.dialogTheme.contentTextStyle ??
                const TextStyle(fontSize: 14))
            .copyWith(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 14,
          height: desktopUiLineHeight,
        ),
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(
        textStyle: (theme.popupMenuTheme.textStyle ??
                const TextStyle(fontSize: 14))
            .copyWith(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 14,
          height: desktopUiLineHeight,
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.25,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: 13,
          height: 1.3,
        ),
      ),
    );
  }

  static TextStyle get display => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: ink900,
        height: 1.2,
      );
  static TextStyle get title => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: ink900,
        height: 1.25,
      );
  static TextStyle get subtitle => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: ink400,
        height: 1.45,
        letterSpacing: 0,
      );
  static TextStyle get label => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ink700,
        letterSpacing: 0,
      );
  static TextStyle get body => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: ink800,
        height: 1.5,
      );
  static TextStyle get bodyStrong => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink900,
      );
  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: ink400,
        letterSpacing: 0,
      );
  static TextStyle get button => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: Colors.white,
      );
  static TextStyle get link => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: brand500,
      );
  static TextStyle get authHeroTitle => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: Colors.white,
        height: 1.18,
      );
  static TextStyle get authTabActive => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0,
      );
  static TextStyle get authTabInactive => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Color(0xCCFFFFFF),
        letterSpacing: 0,
      );
}
