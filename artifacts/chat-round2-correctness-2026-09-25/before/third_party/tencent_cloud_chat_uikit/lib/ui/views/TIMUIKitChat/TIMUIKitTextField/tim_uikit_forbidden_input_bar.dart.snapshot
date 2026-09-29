import 'package:tencent_cloud_chat_uikit/ui/utils/chat_input_bar_metrics.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// 群禁言 / 个人禁言时替换输入栏的提示条（图标 + 文案居中）。
class TIMUIKitForbiddenInputBar extends StatelessWidget {
  const TIMUIKitForbiddenInputBar({
    super.key,
    required this.text,
    required this.theme,
    this.backgroundColor,
  });

  final String text;
  final TUITheme theme;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? theme.weakBackgroundColor ?? Colors.white;
    final divider = theme.weakDividerColor ?? const Color(0xFFE5E6E9);
    final textColor =
        theme.weakTextColor ?? theme.darkTextColor ?? const Color(0xFF666666);

    return Container(
      width: double.infinity,
      height: ChatInputBarMetrics.height,
      padding: const EdgeInsets.symmetric(
          vertical: ChatInputBarMetrics.verticalPadding, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: divider, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.block,
            color: Color(0xFFE84A32),
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
