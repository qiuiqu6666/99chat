import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

/// 列表/记录类页面统一空状态插画。
///
/// UI 块（v15/v16）：可注入 [onRetry]，在空态下方渲染「点击重新加载」按钮，
/// 触发 `ConversationSyncService.userInitiatedFullRefresh`。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.message,
    this.imageWidth,
    this.padding,
    this.onRetry,
  });

  static const String assetPath = 'assets/img/empty.webp';

  final String? message;
  final double? imageWidth;
  final EdgeInsetsGeometry? padding;

  /// UI 块（v15/v16）：可选，点击后调用，应用侧会触发
  /// SDK 全量同步。仅当 [message] 不为 null 时显示按钮。
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final w = imageWidth ?? 160;
    final textColor = AppColors.subText(dark: dark);

    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              assetPath,
              width: w,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.inbox_outlined,
                size: w * 0.45,
                color: textColor.withValues(alpha: 0.45),
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                  height: 1.4,
                ),
              ),
            ],
            if (onRetry != null && message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  onRetry!();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  AppI18n.of(context).t(
                    zhHans: '点击重新加载',
                    zhHant: '點擊重新載入',
                    en: 'Tap to reload',
                    ja: 'タップで再読み込み',
                    ko: '탭하여 다시 불러오기',
                  ),
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
