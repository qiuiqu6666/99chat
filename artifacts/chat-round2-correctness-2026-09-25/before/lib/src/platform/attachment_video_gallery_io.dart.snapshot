import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service_io.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_preview.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

void installAttachmentVideoGallery() {
  externalChatMediaPreviewItem = attachmentVideoGalleryItem;
}

ChatMediaPreviewItem? attachmentVideoGalleryItem(V2TimMessage message) {
  final attachment = ChatAttachment.tryParse(message.customElem?.data);
  if (attachment?.kind != 'video') return null;
  final a = attachment!;
  final owner = ApiClient.instance.authenticatedUserId;
  final generation = ApiClient.instance.credentialGeneration;
  void check() {
    if (owner != ApiClient.instance.authenticatedUserId ||
        generation != ApiClient.instance.credentialGeneration) {
      throw const ChatAttachmentException('SESSION_CHANGED', '账号已切换');
    }
  }

  final preview = attachmentVideoPreviewMessage(
      attachment: a,
      source: const ChatAttachmentPlayback(''),
      original: message);
  return ChatMediaPreviewItem(
      message: preview,
      type: ChatMediaPreviewType.video,
      heroTag: 'attachment-video:${a.attachmentId}:${a.referenceId}',
      messageID: message.msgID ?? message.id,
      videoElement: preview.videoElem,
      resolveVideo: () async {
        check();
        final service = ChatAttachmentService.instance;
        final path = await service.resolveFile(a);
        check();
        final cover = await service.videoThumbnail(a);
        check();
        final resolved = attachmentVideoPreviewMessage(
                attachment: a,
                source: ChatAttachmentPlayback(path, local: true),
                original: message,
                thumbnail: cover)
            .videoElem!;
        // Preserve identity of the element also used by the gallery cover.
        preview.videoElem!.videoPath = resolved.videoPath;
        preview.videoElem!.localVideoUrl = resolved.localVideoUrl;
        preview.videoElem!.snapshotPath = resolved.snapshotPath;
        preview.videoElem!.localSnapshotUrl = resolved.localSnapshotUrl;
        return preview.videoElem!;
      });
}
