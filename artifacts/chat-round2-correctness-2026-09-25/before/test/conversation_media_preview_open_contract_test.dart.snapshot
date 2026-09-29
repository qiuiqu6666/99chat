import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

/// 图片与视频入口共享混合图集，并定位到实际点击的媒体。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  V2TimMessage imageMsg(String id) {
    final m = V2TimMessage.fromJson({
      'msgID': id,
      'timestamp': 1,
      'message_is_from_self': false,
      'message_risk_type_identified': 0,
    });
    m.msgID = id;
    m.elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
    m.imageElem = V2TimImageElem(
      imageList: [
        V2TimImage(
          type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_LARGE,
          url: 'https://example.com/$id-big.jpg',
        ),
        V2TimImage(
          type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB,
          url: 'https://example.com/$id-thumb.jpg',
        ),
      ],
    );
    return m;
  }

  V2TimMessage videoMsg(String id) {
    final m = V2TimMessage.fromJson({
      'msgID': id,
      'timestamp': 2,
      'message_is_from_self': false,
      'message_risk_type_identified': 0,
    });
    m.msgID = id;
    m.elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
    m.videoElem = V2TimVideoElem(
      videoUrl: 'https://example.com/$id.mp4',
      snapshotUrl: 'https://example.com/$id.jpg',
    );
    return m;
  }

  test('image and video entries share the same ordered media sequence', () {
    final img = imageMsg('img-1');
    final video = videoMsg('vid-1');
    final lastImage = imageMsg('img-2')..timestamp = 3;
    final list = [lastImage, video, img];

    for (final tapped in [img, video, lastImage]) {
      final preview = buildChatMediaPreviewItems(
        originList: list,
        tappedMessage: tapped,
        types: kChatMediaPreviewAllTypes,
        heroTagBuilder: (m) => 'h_${m.msgID}',
      );
      expect(preview.isMixed, isTrue);
      expect(preview.items.map((item) => item.message.msgID),
          ['img-1', 'vid-1', 'img-2']);
      expect(preview.items.map((item) => item.type), [
        ChatMediaPreviewType.image,
        ChatMediaPreviewType.video,
        ChatMediaPreviewType.image,
      ]);
      expect(preview.currentItem?.message.msgID, tapped.msgID);
      expect(preview.items[preview.initialIndex].message.msgID, tapped.msgID);
    }
  });
}
