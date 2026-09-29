import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_video_card.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';

/// Video presentation shared by durable uploads and delivered video messages.
/// Storage references and filenames are deliberately not the visual identity.
class ChatAttachmentVideoCard extends StatelessWidget {
  const ChatAttachmentVideoCard({
    super.key,
    required this.sizeBytes,
    required this.onOpen,
    this.thumbnail,
    this.durationMs,
    this.videoWidth,
    this.videoHeight,
    this.busy = false,
    this.paused = false,
    this.progress = 0,
    this.indeterminate = false,
    this.error = '',
    this.uploadStatus,
    this.onPause,
    this.onCancel,
    this.onDownload,
  });

  final int sizeBytes;
  final int? durationMs, videoWidth, videoHeight;
  final ImageProvider? thumbnail;
  final bool busy, indeterminate, paused;
  final double progress;
  final String error;
  final String? uploadStatus;
  final VoidCallback? onOpen, onPause, onCancel, onDownload;

  String get _duration => TIMUIKitVideoCard.durationLabel(durationMs);

  @override
  Widget build(BuildContext context) {
    final ratio = videoWidth != null &&
            videoHeight != null &&
            videoWidth! > 0 &&
            videoHeight! > 0
        ? (videoWidth! / videoHeight!)
        : 9 / 16;
    final action = busy ? onPause : onOpen;
    final scale = TUIKitScreenUtils.compactChatCardScale(context);
    final controlSize = 48 * scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '视频，$_duration，${attachmentSizeLabel(sizeBytes)}',
          button: true,
          child: GestureDetector(
            onTap: action,
            child: TIMUIKitVideoCard(
              aspectRatio: ratio,
              durationMs: durationMs,
              cover: thumbnail == null
                  ? const SizedBox.expand()
                  : Image(
                      image: thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.expand()),
              centerControl: (busy && onPause != null) || paused
                  ? Semantics(
                      label: paused
                          ? '继续上传'
                          : uploadStatus != null
                              ? '暂停上传'
                              : '暂停下载',
                      child: SizedBox(
                        width: controlSize,
                        height: controlSize,
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: indeterminate && !paused
                                  ? null
                                  : progress.clamp(0.0, 1.0).toDouble(),
                              backgroundColor: Colors.white24,
                              color: Colors.white,
                              strokeWidth: 3 * scale,
                            ),
                            Icon(
                              paused ? Icons.file_upload_outlined : Icons.pause,
                              color: Colors.white,
                              size: 28 * scale,
                            ),
                          ],
                        ),
                      ),
                    )
                  : action == null
                      ? const Icon(Icons.schedule, color: Colors.white70)
                      : null,
            ),
          ),
        ),
      ],
    );
  }
}
