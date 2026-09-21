import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

void main() {
  V2TimMessage oversized({
    required String originPath,
    String? thumbUrl,
  }) {
    final message = V2TimMessage.fromJson({
      'msgID': 'msg-oversize',
      'timestamp': 1,
      'message_is_from_self': true,
      'message_risk_type_identified': 0,
    });
    message.elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
    message.imageElem = V2TimImageElem(
      path: originPath,
      imageList: [
        V2TimImage(
          type: 0,
          width: 1182,
          height: 45234,
          url: 'https://example.com/origin.webp',
        ),
        if (thumbUrl != null)
          V2TimImage(
            type: 1,
            width: 198,
            height: 198,
            url: thumbUrl,
          ),
      ],
    );
    return message;
  }

  test('oversize local bubble path does not return original file', () {
    final message = oversized(originPath: r'C:\tmp\origin.webp');
    expect(
      ChatImageMessagePrefetch.debugResolveLocalBubblePath(message),
      isNull,
    );
  });

  test('oversize thumb url does not fall back to original http', () {
    final withoutThumb = oversized(originPath: r'C:\tmp\origin.webp');
    expect(ChatImageMessagePrefetch.resolveBubbleThumbUrl(withoutThumb), isNull);

    final withThumb = oversized(
      originPath: r'C:\tmp\origin.webp',
      thumbUrl: 'https://example.com/thumb.jpg',
    );
    expect(
      ChatImageMessagePrefetch.resolveBubbleThumbUrl(withThumb),
      'https://example.com/thumb.jpg',
    );
  });

  test('oversize original url still needs thumb online url', () {
    final withoutThumb = oversized(originPath: r'C:\tmp\origin.webp');
    expect(imageMessageNeedsBubbleThumbOnlineUrl(withoutThumb), isTrue);
    expect(imageMessageHasSdkTypeHttpUrl(withoutThumb, 1), isFalse);

    final withThumb = oversized(
      originPath: r'C:\tmp\origin.webp',
      thumbUrl: 'https://example.com/thumb.jpg',
    );
    expect(imageMessageNeedsBubbleThumbOnlineUrl(withThumb), isFalse);
    expect(imageMessageHasSdkTypeHttpUrl(withThumb, 1), isTrue);
  });
}
