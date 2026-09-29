import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_gallery_item.dart';

enum ChatMediaPreviewType { image, video }

class ChatMediaPreviewItem {
  const ChatMediaPreviewItem({
    required this.message,
    required this.type,
    required this.heroTag,
    this.messageID,
    this.imageProvider,
    this.placeholderImageProvider,
    this.videoElement,
    this.resolveVideo,
    this.headerTitle,
    this.headerSubtitle,
    this.downloadFn,
    this.copyFn,
    this.editFn,
    this.sendFn,
    this.forwardFn,
    this.deleteFn,
  });

  final V2TimMessage message;
  final ChatMediaPreviewType type;
  final Object heroTag;
  final String? messageID;
  final ImageProvider? imageProvider;
  final ImageProvider? placeholderImageProvider;
  final V2TimVideoElem? videoElement;
  final Future<V2TimVideoElem> Function()? resolveVideo;
  final String? headerTitle;
  final String? headerSubtitle;
  final Future<void> Function()? downloadFn;
  final Future<void> Function()? copyFn;
  final Future<void> Function(BuildContext previewContext)? editFn;
  final Future<void> Function(BuildContext previewContext)? sendFn;
  final Future<void> Function()? forwardFn;
  final Future<void> Function()? deleteFn;

  ImageGalleryItem toImageGalleryItem() {
    return ImageGalleryItem(
      imageProvider: imageProvider,
      placeholderImageProvider: placeholderImageProvider,
      heroTag: heroTag.toString(),
      messageID: messageID,
      sourceMessage: message,
      headerTitle: headerTitle,
      headerSubtitle: headerSubtitle,
      downloadFn: downloadFn,
      copyFn: copyFn,
      editFn: editFn,
      sendFn: sendFn,
      forwardFn: forwardFn,
      deleteFn: deleteFn,
    );
  }
}
