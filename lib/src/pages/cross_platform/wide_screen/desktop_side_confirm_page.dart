import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';

class DesktopSideConfirmPage extends StatelessWidget {
  const DesktopSideConfirmPage({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    this.destructive = true,
  });

  final String title;
  final String message;
  final String confirmText;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<DefaultThemeData>(context).theme;
    final isDark = Provider.of<DefaultThemeData>(context, listen: false)
            .currentThemeType ==
        ThemeType.dark;
    final i18n = AppI18n.of(context);
    final pageBg = isDark
        ? (theme.weakBackgroundColor ?? AppColors.background(dark: true))
        : const Color(0xFFF1F1F1);
    final textColor = theme.darkTextColor ?? AppColors.text(dark: isDark);
    final weak = theme.weakTextColor ?? AppColors.subText(dark: isDark);
    final caution = theme.cautionColor ?? const Color(0xFFE53935);
    final primary = theme.primaryColor ?? AppColors.primaryBlue;

    return ColoredBox(
      color: pageBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: weak,
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: destructive ? caution : primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmText),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                i18n.t(
                  zhHans: '取消',
                  zhHant: '取消',
                  en: 'Cancel',
                  ja: 'キャンセル',
                  ko: '취소',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
