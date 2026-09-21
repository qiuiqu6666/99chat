import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_file_card.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// Adapts self-hosted transfers to the same surface used by TIMUIKitFileElem.
/// The attachment service retains storage access and resumable downloads.
class ChatAttachmentFileCard extends TIMUIKitStatelessWidget {
  ChatAttachmentFileCard({
    super.key,
    required this.name,
    required this.sizeBytes,
    required this.isSelf,
    required this.isLocal,
    required this.busy,
    required this.progress,
    required this.error,
    required this.onOpen,
    required this.onPause,
    this.uploadStatus,
    this.uploadIndeterminate = false,
    this.onCancel,
  });

  final String name;
  final int sizeBytes;
  final bool isSelf, isLocal, busy;
  final double progress;
  final String error;
  final VoidCallback onOpen, onPause;
  final String? uploadStatus;
  final bool uploadIndeterminate;
  final VoidCallback? onCancel;

  String get _size => TIMUIKitFileCard.formatSize(sizeBytes);

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final theme = value.theme;
    final scale = TUIKitScreenUtils.compactChatCardScale(context);
    final trailingSize = 22 * scale;
    final subtitle = uploadStatus ??
        (error.isNotEmpty
            ? error
            : busy && !isLocal
                ? '下载中 ${(progress.clamp(0, 1) * 100).floor()}%'
                : TIMUIKitFileCard.formatSizeWithExtension(name, sizeBytes));
    return Semantics(
      label:
          '$name，$_size，${uploadStatus ?? (error.isNotEmpty ? error : isLocal ? "已下载，点击打开" : "点击下载打开")}',
      button: true,
      child: Tooltip(
        message: uploadStatus != null
            ? '$name\n$uploadStatus'
            : error.isNotEmpty
                ? error
                : name,
        // Leave mobile long presses to the surrounding message action menu.
        triggerMode: uploadStatus != null
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: GestureDetector(
          onTap: busy ? null : onOpen,
          child: TIMUIKitFileCard(
            name: name,
            subtitle: subtitle,
            isSelf: isSelf,
            isLocal: isLocal,
            isError: error.isNotEmpty,
            progress: busy && !isLocal
                ? uploadIndeterminate
                    ? null
                    : progress
                : 0,
            trailing: uploadStatus != null && onCancel != null
                ? SizedBox(
                    width: 44 * scale,
                    height: trailingSize,
                    child: Row(children: [
                      SizedBox(
                          width: 22 * scale,
                          height: trailingSize,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: busy ? '暂停上传' : '继续发送',
                            onPressed: onPause,
                            color: theme.weakTextColor,
                            iconSize: 20 * scale,
                            icon: Icon(busy ? Icons.pause : Icons.play_arrow),
                          )),
                      SizedBox(
                          width: 22 * scale,
                          height: trailingSize,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: '取消发送',
                            onPressed: onCancel,
                            color: theme.weakTextColor,
                            iconSize: 20 * scale,
                            icon: const Icon(Icons.close),
                          )),
                    ]))
                    : busy && !isLocal && uploadStatus == null
                    ? SizedBox(
                        width: trailingSize,
                        height: trailingSize,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: '暂停下载',
                          onPressed: onPause,
                          color: theme.weakTextColor,
                          icon: const Icon(Icons.pause_circle_outline),
                        ),
                      )
                    : null,
          ),
        ),
      ),
    );
  }
}
