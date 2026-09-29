import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/overflow_text_marquee.dart';

/// 群聊头部导航下方的公告跑马灯。
///
/// 文本超出可视宽度时无缝循环滚动；未超出则静态左对齐显示。
class GroupNoticeMarquee extends StatelessWidget {
  const GroupNoticeMarquee({
    super.key,
    required this.text,
    this.onTap,
    this.onClose,
    this.label = '群公告：',
    this.backgroundColor = const Color(0xFFFFF7E3),
    this.textColor = const Color(0xFF8A6417),
    this.velocity = 42.0,
  });

  /// 公告内容（会自动去除首尾空白并把换行折叠为空格）。
  final String text;

  /// 点击文本区时的回调（一般用于展开完整公告）。
  final VoidCallback? onTap;

  /// 点击右侧关闭按钮时的回调；为 null 时不显示关闭按钮。
  final VoidCallback? onClose;

  /// 公告正文前的固定标签，如「群公告：」。
  final String label;

  final Color backgroundColor;
  final Color textColor;

  /// 滚动速度，单位：逻辑像素/秒。
  final double velocity;

  static const double _height = 20;

  @override
  Widget build(BuildContext context) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return const SizedBox.shrink();
    }

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w500,
    );
    final labelStyle = textStyle.copyWith(fontWeight: FontWeight.w600);

    return Material(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    Text(label, style: labelStyle),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OverflowTextMarquee(
                        text: normalized,
                        style: textStyle,
                        height: _height,
                        velocity: velocity,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
