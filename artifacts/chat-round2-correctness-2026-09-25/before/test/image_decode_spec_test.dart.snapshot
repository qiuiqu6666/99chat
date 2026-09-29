import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_decode_spec.dart';

void main() {
  setUp(ImageDecodeSpec.resetMetricsForTest);

  test('avatar decodes near display pixels, not the original 1080', () {
    final spec = ImageDecodeSpec.avatar(logical: 48, devicePixelRatio: 3);
    expect(spec.targetDecodeWidth, inInclusiveRange(144, 192));
    expect(spec.targetDecodeHeight, spec.targetDecodeWidth);
    expect(int.parse(spec.sizeBucket), lessThanOrEqualTo(256));
  });

  test('chat thumbnail does not decode a 3000px original for a 300dp bubble', () {
    final spec = ImageDecodeSpec.chatThumbnail(
      logicalWidth: 300,
      logicalHeight: 200,
      devicePixelRatio: 3,
      sourceWidth: 3000,
      sourceHeight: 2000,
    );
    expect(spec.targetDecodeWidth, lessThanOrEqualTo(1440));
    expect(spec.pixelCount, lessThan(3000 * 2000));
  });

  test('long image is clamped by decodedPixelCount not width only', () {
    final spec = ImageDecodeSpec.chatThumbnail(
      logicalWidth: 400,
      logicalHeight: 190,
      devicePixelRatio: 3,
      sourceWidth: 1000,
      sourceHeight: 15000,
    );
    expect(spec.pixelCount, lessThanOrEqualTo(ImageDecodeSpec.defaultMaxDecodedPixels));
    expect(ImageDecodeSpec.imageDecodeOversizeCount, greaterThan(0));
    expect(spec.targetDecodeWidth, lessThan(1000));
  });

  test('bubble decode helper shrinks a 1000x15000 source', () {
    final target = clampChatBubbleDecodeToPixelBudget(
      const ChatBubbleImageDecodeTarget(width: 1440),
      sourceWidth: 1000,
      sourceHeight: 15000,
    );
    final width = target.width ?? 1;
    final height = ((width * 15000) / 1000).round();
    expect(width * height, lessThanOrEqualTo(ImageDecodeSpec.defaultMaxDecodedPixels));
  });

  test('preview and bubble cache keys stay on different variants', () {
    expect(
      ImageDecodeSpec.bucketFor(144),
      '256',
    );
    expect(
      ImageDecodeSpec.bucketFor(900),
      '1080',
    );
    expect(
      ImageDecodeSpec.bucketFor(2000),
      '1440',
    );
  });
}
