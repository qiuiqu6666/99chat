import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

/// 消息列表搜索框下「已在××登录」横条（微信风）。
class DesktopLoginBanner extends StatelessWidget {
  const DesktopLoginBanner({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = AppColors.text(dark: dark);
    final iconColor = AppColors.subText(dark: dark);
    return Semantics(
      button: true,
      label: text,
      child: Material(
        color: AppColors.surfaceAlt(dark: dark),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 20,
                  color: iconColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
