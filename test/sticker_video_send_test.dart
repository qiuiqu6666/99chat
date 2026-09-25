import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/repository/sticker_repository.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_image.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_constants.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_media.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  test('video remains a distinct sticker media type', () {
    expect(StickerMediaType.fromJson('video'), StickerMediaType.video);
  });

  test('video sticker keeps its type and thumbnail across face data', () {
    const thumb = 'https://example.com/sticker-thumb.jpg';
    const origin = 'https://example.com/sticker.mp4?token=abc';
    final data = StickerConstants.dataForSticker(
      stickerId: 'video-sticker',
      thumbUrl: thumb,
      originUrl: origin,
      mediaType: StickerMediaType.video,
    );
    final item = StickerRepository.instance.resolveStickerItemSync(data);
    expect(item?.mediaType, StickerMediaType.video);
    expect(item?.displayUrl(preferAnimated: false), thumb);
    expect(item?.displayUrl(preferAnimated: true), origin);
  });

  test('legacy video URL remains a video even without a type hint', () {
    final item = StickerRepository.instance.resolveStickerItemSync(
      '99chat://sticker/legacy?thumbUrl=https%3A%2F%2Fexample.com%2Ft.jpg'
      '&originUrl=https%3A%2F%2Fexample.com%2Fv.webm',
    );
    expect(item?.mediaType, StickerMediaType.video);
  });

  testWidgets('sticker grid does not open video decoders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StickerImage.url(
          url: 'https://example.com/sticker.mp4',
          mediaType: StickerMediaType.video,
          preferAnimated: false,
        ),
      ),
    ));
    expect(find.byType(Video), findsNothing);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
  });
}
