import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_preview_image_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

void main() {
  testWidgets('speculative local images are bounded even without metadata',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(393, 852), devicePixelRatio: 3),
      child: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    final original = FileImage(File('/does-not-need-to-exist.jpg'));
    final adjacent = ChatMessagePreviewImageResolver.wrapAdjacentPrecacheDecode(
      context: context,
      message: null,
      provider: original,
    ) as ResizeImage;
    expect(adjacent.imageProvider, same(original));
    expect(adjacent.width, 1179);
    expect(adjacent.height, 2048);
    expect(adjacent.policy, ResizeImagePolicy.fit);
    for (final fullResolution in [false, true]) {
      expect(
        ChatMessagePreviewImageResolver.wrapPreviewDecode(
          context: context,
          message: null,
          provider: original,
          preferFullResolution: fullResolution,
        ),
        same(original),
        reason: 'Visible file images and zoom retain full source resolution',
      );
    }
  });

  test('preferFullResolution skips screen cap for camera original over 2000px',
      () {
    final capped = imagePreviewDecodeTarget(
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 2,
      imageWidth: 4000,
      imageHeight: 3000,
    );
    final full = imagePreviewDecodeTarget(
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 2,
      imageWidth: 4000,
      imageHeight: 3000,
      preferFullResolution: true,
    );
    expect(capped.shouldResize, isTrue);
    expect(full.shouldResize, isFalse);
  });

  test('preferFullResolution still caps originals above 40MP', () {
    final full = imagePreviewDecodeTarget(
      screenWidth: 390,
      screenHeight: 844,
      devicePixelRatio: 2,
      imageWidth: 8000,
      imageHeight: 6000,
      preferFullResolution: true,
    );
    expect(full.shouldResize, isTrue);
    expect(full.width, lessThan(8000));
    expect(full.width, greaterThan(2000));
  });

  testWidgets('1280px BIG is too low on a 1920 Win/Mac display', (tester) async {
    late bool tooLow;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1920, 1080), devicePixelRatio: 1),
      child: Builder(builder: (context) {
        tooLow = isImagePreviewResolutionTooLow(
          imageWidth: 1280,
          imageHeight: 720,
          context: context,
        );
        return const SizedBox();
      }),
    ));
    if (Platform.isWindows || Platform.isMacOS) {
      expect(tooLow, isTrue);
    } else {
      expect(tooLow, isFalse);
    }
  });

  test('53MP originals skip adjacent gallery precache', () {
    final message = V2TimMessage.fromJson({
      'msgID': 'msg-tall',
      'timestamp': 1,
      'message_is_from_self': false,
      'message_risk_type_identified': 0,
    });
    message.elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
    message.imageElem = V2TimImageElem(imageList: [
      V2TimImage(type: 0, width: 1182, height: 45234, url: 'o'),
    ]);
    expect(shouldSkipGalleryAdjacentPrecacheForMessage(message), isTrue);
  });
}
