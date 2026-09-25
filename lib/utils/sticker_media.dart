/// 表情资源类型：静态图与 GIF 动图。
class StickerMediaType {
  StickerMediaType._();

  static const String image = 'image';
  static const String gif = 'gif';
  static const String video = 'video';

  static String fromJson(dynamic value) {
    final v = value?.toString().toLowerCase().trim() ?? '';
    if (v == video) return video;
    if (v == gif || v == 'animated') {
      return gif;
    }
    return image;
  }

  static bool isGifMediaType(String mediaType) => mediaType == gif;

  static bool isVideoUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.webm');
  }

  static bool isGifUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.gif');
  }

  static bool isAnimated({
    required String mediaType,
    required String thumbUrl,
    required String originUrl,
  }) {
    if (isGifMediaType(mediaType) || mediaType == video) {
      return true;
    }
    return isGifUrl(thumbUrl) || isGifUrl(originUrl);
  }
}
