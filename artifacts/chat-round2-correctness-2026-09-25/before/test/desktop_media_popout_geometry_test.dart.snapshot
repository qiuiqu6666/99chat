import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_media_popout_geometry.dart';

void main() {
  const origin = Offset(120, 80);
  const display = Size(1920, 1080);

  group('resolveOpenFrame', () {
    test('open frame is display logical size', () {
      expect(
        resolveOpenFrame(
          mainOrigin: origin,
          displayLogicalSize: display,
        ),
        origin & display,
      );
    });

    test('square, portrait, and missing image sizes do not shrink the frame', () {
      final frame = resolveOpenFrame(
        mainOrigin: origin,
        displayLogicalSize: display,
      );
      expect(frame.size, display);
      expect(const Size(800, 800), isNot(display));
      expect(const Size(1080, 1920), isNot(display));
      expect(Size.zero, isNot(display));
    });
  });
}
