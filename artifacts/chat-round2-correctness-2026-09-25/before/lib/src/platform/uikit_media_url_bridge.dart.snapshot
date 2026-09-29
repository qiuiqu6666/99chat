import 'attachment_video_gallery_stub.dart'
    if (dart.library.io) 'attachment_video_gallery_io.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart'
    as media_preview;
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart'
    as avatar_widget;

/// 将聊天媒体预览与 UIKit Avatar 的网络 URL 解析、鉴权头注入宿主实现。
class UikitMediaUrlBridge {
  UikitMediaUrlBridge._();

  static void install() {
    installAttachmentVideoGallery();
    media_preview.resolveMediaPreviewNetworkUrl = (url) {
      return MediaUrlResolver.resolve(url) ?? url;
    };
    media_preview.mediaPreviewNetworkUrlHeaders =
        MediaUrlResolver.authHeadersFor;
    avatar_widget.resolveAvatarNetworkUrl = (url) {
      return MediaUrlResolver.resolve(url) ?? url;
    };
    avatar_widget.avatarNetworkUrlHeaders = MediaUrlResolver.authHeadersFor;
  }
}
