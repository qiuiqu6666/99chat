import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared metrics for contact and group directories, including scaled text.
abstract final class DirectoryListStyle {
  static const double titleSize = 16;
  static const double subtitleSize = 13;
  static const double lineHeight = 1.25;
  static const double textGap = 4;
  static const double avatarTextGap = 12;
  static const double verticalPadding = 8;
  static const double dividerThickness = 0.6;

  static double avatarSize(bool desktop) => desktop ? 48 : 44;

  static double rowHeight(BuildContext context, {required bool desktop}) {
    final scaler = MediaQuery.textScalerOf(context);
    final textHeight = scaler.scale(titleSize) * lineHeight +
        scaler.scale(subtitleSize) * lineHeight +
        textGap;
    return math.max(
        desktop ? 68 : 64,
        math.max(avatarSize(desktop), textHeight) +
            verticalPadding * 2 +
            dividerThickness);
  }

  static Color dividerColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0x14FFFFFF)
          : const Color(0x0F000000);

  static double sectionHeight(BuildContext context) => math.max(
      32, MediaQuery.textScalerOf(context).scale(12) * lineHeight + 12);
}
