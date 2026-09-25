import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/src/repository/sticker_repository.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_constants.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_image_size_probe.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_recent_store.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_media.dart';

class StickerSendHelper {
  StickerSendHelper._();

  static bool isDynamicStickerData(String data) {
    return StickerRepository.instance.isDynamicFaceData(data);
  }

  static void sendViaPanelCallback(
    void Function(int index, String data) sendFaceMessage, {
    required String stickerId,
    required String thumbUrl,
    String? originUrl,
    String mediaType = StickerMediaType.image,
  }) {
    final id = stickerId.trim();
    if (id.isEmpty) {
      return;
    }
    StickerRepository.instance.putCache(
      StickerItem(
        stickerId: id,
        thumbUrl: thumbUrl,
        originUrl: originUrl ?? thumbUrl,
        mediaType: mediaType,
      ),
    );
    StickerRecentStore.add(id);
    var item = StickerRepository.instance.getCached(id);
    if (item != null && !item.hasIntrinsicSize) {
      final size = StickerImageSizeProbe.instance
              .cached(item.displayUrl(preferAnimated: false)) ??
          StickerImageSizeProbe.instance.cached(item.originUrl);
      if (size != null) {
        item = item.copyWithSize(
          width: size.width.round(),
          height: size.height.round(),
        );
        StickerRepository.instance.putCache(item);
      }
    }
    sendFaceMessage(
      StickerConstants.stickerFaceGroupIndex,
      StickerConstants.dataForSticker(
        stickerId: id,
        thumbUrl: thumbUrl,
        originUrl: originUrl,
        mediaType: mediaType,
        width: item?.width,
        height: item?.height,
      ),
    );
  }
}
