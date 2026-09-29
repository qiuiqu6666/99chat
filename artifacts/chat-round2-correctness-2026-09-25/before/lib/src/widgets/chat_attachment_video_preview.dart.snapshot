import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';

/// A preview-only adapter; never replaces or sends the custom transport message.
V2TimMessage attachmentVideoPreviewMessage({
  required ChatAttachment attachment,
  required ChatAttachmentPlayback source,
  V2TimMessage? original,
  String? thumbnail,
}) {
  final message = V2TimMessage.fromJson(original?.toJson() ??
      {
        'message_server_time': 0,
        'message_risk_type_identified': 0,
      });
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
  message.videoElem = V2TimVideoElem(
    videoPath: source.local ? source.location : null,
    localVideoUrl: source.local ? source.location : null,
    videoUrl: source.local ? null : source.location,
    videoSize: attachment.sizeBytes,
    duration: attachment.durationMs == null
        ? null
        : (attachment.durationMs! / 1000).ceil(),
    snapshotPath: thumbnail,
    localSnapshotUrl: thumbnail,
    snapshotWidth: attachment.width,
    snapshotHeight: attachment.height,
  );
  return message;
}

VideoScreen attachmentVideoScreen({
  required V2TimMessage message,
  required ChatAttachmentPlayback source,
  required String heroTag,
  required Future<void> Function() onSave,
  Future<V2TimVideoElem?> Function()? onRecover,
  List<ChatMediaPreviewItem>? galleryItems,
  int initialIndex = 0,
}) =>
    VideoScreen(
      message: message,
      videoElement: message.videoElem!,
      heroTag: heroTag,
      preferOnlinePlayback: true,
      playbackHeaders: source.headers,
      externalVideo: true,
      saveVideoFn: onSave,
      recoverVideoFn: onRecover,
      galleryItems: galleryItems,
      initialIndex: initialIndex,
    );
