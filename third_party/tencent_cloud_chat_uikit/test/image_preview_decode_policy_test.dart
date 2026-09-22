import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_decode_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

void main() {
  group('imagePreviewDecodeRoute', () {
    test('1182x45234 uses a whole bitmap and skips oversized prefetch',
        () {
      const width = 1182;
      const height = 45234;
      expect(
        imagePreviewDecodeRoute(width: width, height: height),
        ImagePreviewDecodeRoute.controlledDownsample,
      );
      expect(
        imageExceedsListPrefetchBan(width: width, height: height),
        isTrue,
      );
      expect(
        imagePreviewRequiresTileRenderer(width: width, height: height),
        isFalse,
      );
    });

    test('2496x30492 uses a whole bitmap and skips oversized prefetch',
        () {
      const width = 2496;
      const height = 30492;
      expect(
        imagePreviewDecodeRoute(width: width, height: height),
        ImagePreviewDecodeRoute.controlledDownsample,
      );
      expect(
        imageExceedsListPrefetchBan(width: width, height: height),
        isTrue,
      );
    });

    test('1080x8000 extra-tall stays off the tile path', () {
      expect(
        imagePreviewDecodeRoute(width: 1080, height: 8000),
        ImagePreviewDecodeRoute.normal,
      );
      expect(
        imagePreviewRequiresTileRenderer(width: 1080, height: 8000),
        isFalse,
      );
    });

    test('2000x6000 12MP uses controlled downsample', () {
      expect(
        imagePreviewDecodeRoute(width: 2000, height: 6000),
        ImagePreviewDecodeRoute.controlledDownsample,
      );
      expect(imageDecodedPixelCount(2000, 6000), 12 * 1000 * 1000);
    });

    test('1000x1000 uses the normal path', () {
      expect(
        imagePreviewDecodeRoute(width: 1000, height: 1000),
        ImagePreviewDecodeRoute.normal,
      );
      expect(
        imageExceedsListPrefetchBan(width: 1000, height: 1000),
        isFalse,
      );
    });

    test('invalid size is normal', () {
      expect(
        imagePreviewDecodeRoute(width: 0, height: 10),
        ImagePreviewDecodeRoute.normal,
      );
    });
  });

  for (final size in [(1182, 45234), (2496, 30492), (100, 100000)]) {
    test('extra-tall $size whole-image decode is bounded and proportional', () {
      final target = imagePreviewDecodeTarget(
        screenWidth: 390, screenHeight: 844, devicePixelRatio: 3,
        imageWidth: size.$1, imageHeight: size.$2,
      );
      expect(imagePreviewRequiresTileRenderer(width: size.$1, height: size.$2), isFalse);
      expect(target.shouldResize, isTrue);
      expect(target.height!, lessThanOrEqualTo(kImageForceTileLongestSidePx));
      expect(target.width! * target.height!, lessThanOrEqualTo(kImageDecodedPixelsControlledMax));
      expect(target.width!, closeTo(size.$1 * target.height! / size.$2, 1));
    });
  }

  test('1080x12000 controlled downsample keeps height near original', () {
    final target = imagePreviewDecodeTarget(
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 3,
      imageWidth: 1080,
      imageHeight: 12000,
    );
    expect(target.shouldResize, isFalse);
    expect(1080 * 12000, lessThanOrEqualTo(40 * 1000 * 1000));
  });

  test('oversize without thumb falls back to original for bubble display', () {
    expect(
      imageBubbleNetworkSdkTypePriority(
        exceedsListPrefetchBan: true,
        hasThumbHttp: false,
      ),
      <int>[1, 2, 0],
    );
    expect(
      imageBubbleNetworkSdkTypePriority(
        exceedsListPrefetchBan: true,
        hasThumbHttp: true,
      ),
      <int>[1],
    );
  });
}
