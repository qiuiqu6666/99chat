import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_chat_bubble_size.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';

void main() {
  group('resolveStickerMessageSize', () {
    test('uses the same display size as a wide chat image', () {
      final size = resolveStickerMessageSize(
        screenWidth: 390,
        screenHeight: 800,
        availableWidth: 280,
        isDesktop: false,
        maxWidthFactor: 0.4,
        intrinsicWidth: 416,
        intrinsicHeight: 304,
      );
      expect(
          size,
          resolveChatBubbleImageDisplaySize(
            maxWidth: 144,
            maxHeight: 160,
            sourceWidth: 416,
            sourceHeight: 304,
          ));
      expect(size.width / size.height, closeTo(416 / 304, 0.001));
    });

    test('uses the image screen tier for a square sticker', () {
      final size = resolveStickerMessageSize(
        screenWidth: 390,
        screenHeight: 800,
        availableWidth: 280,
        isDesktop: false,
        maxWidthFactor: 0.4,
        intrinsicWidth: 512,
        intrinsicHeight: 512,
      );
      expect(size, const Size(144, 144));
    });

    test('keeps unknown dimensions within the image limits', () {
      final size = resolveStickerMessageSize(
        screenWidth: 390,
        screenHeight: 800,
        availableWidth: 280,
        isDesktop: false,
        maxWidthFactor: 0.4,
      );
      expect(size, const Size(144, 144));
    });

    test('respects a narrow chat column', () {
      final size = resolveStickerMessageSize(
        screenWidth: 1200,
        screenHeight: 900,
        availableWidth: 200,
        isDesktop: true,
        maxWidthFactor: 0.4,
        intrinsicWidth: 512,
        intrinsicHeight: 512,
      );
      expect(size, const Size(68, 68));
    });

    test('matches the image crop frame for a very tall sticker', () {
      final size = resolveStickerMessageSize(
        screenWidth: 390,
        screenHeight: 800,
        availableWidth: 280,
        isDesktop: false,
        maxWidthFactor: 0.4,
        intrinsicWidth: 100,
        intrinsicHeight: 400,
      );
      expect(size, const Size(92, 160));
    });

    test('keeps reply previews smaller than chat stickers', () {
      final size = resolveStickerMessageSize(
        screenWidth: 390,
        screenHeight: 800,
        availableWidth: 280,
        isDesktop: false,
        maxWidthFactor: 0.22,
        intrinsicWidth: 416,
        intrinsicHeight: 304,
      );
      expect(size.width, lessThanOrEqualTo(85.8));
      expect(size.height, lessThanOrEqualTo(140));
    });
  });

  group('resolveStickerChatBubbleSize', () {
    test('scales intrinsic size by display scale when within cap', () {
      final size = resolveStickerChatBubbleSize(
        screenWidth: 390,
        maxWidthFactor: 0.4,
        intrinsicWidth: 240,
        intrinsicHeight: 180,
      );
      expect(size.width, closeTo(240 * kStickerChatBubbleDisplayScale, 0.1));
      expect(size.height, closeTo(180 * kStickerChatBubbleDisplayScale, 0.1));
    });

    test('scales down proportionally when exceeding max', () {
      final size = resolveStickerChatBubbleSize(
        screenWidth: 390,
        maxWidthFactor: 0.4,
        intrinsicWidth: 800,
        intrinsicHeight: 400,
      );
      // maxW = 0.55 * 390 = 214.5
      expect(size.width, closeTo(214.5, 0.1));
      expect(size.height, closeTo(107.25, 0.1));
    });

    test('falls back to square when intrinsic missing', () {
      final size = resolveStickerChatBubbleSize(
        screenWidth: 390,
        maxWidthFactor: 0.4,
      );
      expect(size.width, size.height);
      // 390 * 0.4 * 0.85 = 132.6
      expect(size.width, closeTo(132.6, 0.1));
    });
  });
}
