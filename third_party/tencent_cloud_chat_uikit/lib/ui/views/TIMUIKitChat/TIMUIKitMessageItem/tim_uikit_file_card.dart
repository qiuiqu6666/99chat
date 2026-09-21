import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/theme/color.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_file_icon.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/textSize.dart';

/// Shared file-message surface. Callers retain their own transport and gestures.
class TIMUIKitFileCard extends TIMUIKitStatelessWidget {
  TIMUIKitFileCard(
      {super.key,
      required this.name,
      required this.isSelf,
      required this.isLocal,
      this.subtitle,
      this.progress = 0,
      this.isError = false,
      this.trailing});

  final String name;
  final String? subtitle;
  final bool isSelf, isLocal, isError;
  final double? progress;
  final Widget? trailing;

  static String formatSize(int sizeBytes) {
    // Keep the established file card's binary sizing and displayed unit labels.
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String formatSizeWithExtension(String name, int sizeBytes) {
    final size = formatSize(sizeBytes);
    final position = name.lastIndexOf('.');
    if (position < 1) return size;
    final ext = name.substring(position + 1).trim();
    if (ext.isEmpty) return size;
    return '$size · ${ext.toUpperCase()}';
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;
    final scale = TUIKitScreenUtils.compactChatCardScale(context);
    final radius = BorderRadius.circular(14);
    final iconSize = 44 * scale;
    final textLeft = 12 + iconSize + 10;
    final nameWidth = 126 * scale;
    final Widget? trailingWidget = trailing;
    final fill = theme.chatMessageItemFromOthersBgColor ??
        theme.weakBackgroundColor ??
        Colors.white;
    return Container(
      width: 240,
      height: 72 * scale,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
            color: theme.weakDividerColor ?? CommonColor.weakDividerColor),
        borderRadius: radius,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: LinearProgressIndicator(
                value: progress?.clamp(0, 1),
                backgroundColor: fill,
                valueColor: AlwaysStoppedAnimation(
                    theme.lightPrimaryMaterialColor.shade50),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 14 * scale,
            child: TIMUIKitFileIcon(size: iconSize),
          ),
          Positioned(
            left: textLeft,
            top: 13 * scale,
            width: nameWidth,
            child: CustomText(
              name,
              width: nameWidth,
              maxLines: 1,
              style: TextStyle(
                color: theme.darkTextColor,
                fontSize: 15 * scale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (subtitle != null)
            Positioned(
              left: textLeft,
              top: 39 * scale,
              right: 70,
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12 * scale,
                  color: isError
                      ? Theme.of(context).colorScheme.error
                      : theme.weakTextColor,
                ),
              ),
            ),
          if (trailingWidget != null)
            Positioned(
              right: 12,
              top: 12 * scale,
              child: trailingWidget,
            ),
        ],
      ),
    );
  }
}
