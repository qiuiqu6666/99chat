import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_image.dart';

void main() {
  testWidgets('grid constraints bound native decode even without explicit dimensions', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 2),
      child: Center(child: SizedBox(width: 80, height: 40,
        child: StickerImage.url(url: 'https://example.invalid/grid.png'))),
    )));
    final provider = tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(provider.width, 192);
    expect(provider.height, 128);
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(provider.allowUpscaling, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('large animated origin decode is capped in physical pixels', () {
    expect(stickerDecodePixels(10000, 3), 1024);
    expect(stickerDecodePixels(double.infinity, 3), 768);
  });
}
