import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final batch in [false, true]) {
    test(
        'mixed media uses chat order for ${batch ? 'a selection batch' : 'group sequences'}',
        () {
      final messages = [
        for (var i = 0; i < 4; i++)
          V2TimMessage.fromJson(
              {'message_msg_id': 'media$i', 'message_risk_type_identified': 0})
            ..groupID = '@TGS#gallery'
            ..seq = '${batch ? 10 - i : i + 1}'
            ..timestamp = 1700000010 - i
            ..localCustomData = batch
                ? jsonEncode(
                    {kChatMediaBatchIdKey: 'batch', kChatMediaBatchIndexKey: i})
                : null
            ..elemType = i.isEven
                ? MessageElemType.V2TIM_ELEM_TYPE_IMAGE
                : MessageElemType.V2TIM_ELEM_TYPE_VIDEO
            ..imageElem = i.isEven
                ? V2TimImageElem(imageList: [
                    V2TimImage(type: 1, url: 'https://example.com/$i.jpg')
                  ])
                : null
            ..videoElem = i.isOdd
                ? V2TimVideoElem(videoUrl: 'https://example.com/$i.mp4')
                : null,
      ];
      final chat = TUIChatGlobalModel.sortMessagesNewestFirst(messages);
      expect(chat.reversed.map((m) => m.msgID),
          ['media0', 'media1', 'media2', 'media3']);
      for (final tapped in messages) {
        for (final input in [chat, chat.reversed.toList()]) {
          final preview = buildChatMediaPreviewItems(
              originList: input,
              tappedMessage: tapped,
              types: kChatMediaPreviewAllTypes,
              heroTagBuilder: (m) => m.msgID!);
          expect(preview.items.map((item) => item.message.msgID),
              chat.reversed.map((m) => m.msgID));
          expect(
              preview.items[preview.initialIndex].message.msgID, tapped.msgID);
          expect(preview.isMixed, isTrue);
        }
      }
    });
  }
}
