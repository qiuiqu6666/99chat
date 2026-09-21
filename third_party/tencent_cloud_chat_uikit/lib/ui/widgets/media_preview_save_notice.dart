import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tuikit_info_toast.dart';

/// Media type for [MediaPreviewSaveNotice] copy selection.
enum MediaPreviewSaveKind {
  image,
  video,
}

/// Shows save feedback via the host-injected [TUIKitInfoToast] bubble.
class MediaPreviewSaveNotice {
  MediaPreviewSaveNotice._();

  static void show(
    BuildContext context, {
    required bool success,
    MediaPreviewSaveKind kind = MediaPreviewSaveKind.image,
    String? message,
  }) {
    final successText =
        kind == MediaPreviewSaveKind.video ? '视频已保存' : '图片已保存';
    final text = TIM_t(message ?? (success ? successText : '保存失败'));
    TUIKitInfoToast.show(text);
  }
}
