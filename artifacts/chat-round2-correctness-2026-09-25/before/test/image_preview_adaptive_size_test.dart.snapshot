import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

void main() {
  test('tiny photos do not upscale on entry', () {
    final config = imagePreviewDisplayConfig(
        imageWidth: 64, imageHeight: 64, screenWidth: 390, screenHeight: 844);
    expect(config.fit, BoxFit.scaleDown);
    expect(
        imagePreviewInitialDisplaySize(
            imageWidth: 64,
            imageHeight: 64,
            screenWidth: 390,
            screenHeight: 844,
            fit: config.fit),
        const Size(64, 64));
  });
  test('reading width is stable across rotation and bounded on desktop', () {
    Size size(double w, double h) => imagePreviewInitialDisplaySize(
        imageWidth: 1080,
        imageHeight: 12000,
        screenWidth: w,
        screenHeight: h,
        fit: BoxFit.fitWidth);
    expect(size(390, 844).width, 390);
    expect(size(844, 390).width, 390);
    expect(size(1920, 1080).width, 720);
    expect(size(1024, 1366).width, 720);
  });
  test('narrow low resolution long images have an initial upscale limit', () {
    expect(
        imagePreviewInitialDisplaySize(
                imageWidth: 120,
                imageHeight: 2400,
                screenWidth: 390,
                screenHeight: 844,
                fit: BoxFit.fitWidth)
            .width,
        240);
  });
}
