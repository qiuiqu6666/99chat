import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quote image and video use a 40px thumb instead of bubble elems', () {
    final quote = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/'
      'tim_uikit_reply_quote_card.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(quote.contains('TIMUIKitImageElem('), isFalse);
    expect(quote.contains('TIMUIKitVideoElem('), isFalse);
    expect(quote.contains('kReplyQuoteThumbSize'), isTrue);
    expect(quote.contains('TIM_t("图片")'), isTrue);
    expect(quote.contains('TIM_t("视频")'), isTrue);
    expect(quote.contains('const double kReplyQuoteThumbSize'), isFalse);
  });

  test('input reply preview is a telegram bar and does not nest the quote card',
      () {
    final quote = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/'
      'tim_uikit_reply_quote_card.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final previewStart = quote.indexOf('class TIMUIKitInputReplyPreview');
    expect(previewStart, greaterThanOrEqualTo(0));
    final preview = quote.substring(previewStart);
    expect(preview.contains('TIMUIKitReplyQuoteCard('), isFalse);
    expect(preview.contains('TIM_t("回复")'), isTrue);
    expect(preview.contains('onTap: onClose'), isTrue);
    expect(preview.contains('_ReplyQuoteThumb('), isTrue);
  });

  test('image bubbles no longer special-case reply layout', () {
    final image = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitMessageItem/tim_uikit_chat_image_elem.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(image.contains('isReplyQuote'), isFalse);
    expect(image.contains('kReplyQuoteThumbSize'), isFalse);
    expect(image.contains('layoutLimits.maxHeight'), isTrue);
  });

  test('video card has no compact reply mode', () {
    final card = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitMessageItem/tim_uikit_video_card.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(card.contains('this.compact'), isFalse);
    expect(card.contains('final bool compact'), isFalse);
    expect(card.contains('kReplyQuoteThumbSize'), isFalse);

    final video = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKitMessageItem/tim_uikit_chat_video_elem.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(video.contains('compact:'), isFalse);
  });
}
