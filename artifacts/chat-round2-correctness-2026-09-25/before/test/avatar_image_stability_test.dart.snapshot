import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';

class _ControlledImage extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image));

  void fail() => reportError(
        context: ErrorDescription('loading test avatar'),
        exception: StateError('image unavailable'),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  ui.Image bitmap(Color color) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    return image;
  }

  Future<_ControlledImage> cache(String url, {ui.Image? image}) async {
    final provider = AvatarImageWarm.providerFor(url: url, cacheSize: 40);
    final key = await provider.obtainKey(const ImageConfiguration());
    final stream = _ControlledImage();
    if (image != null) stream.complete(image);
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => stream);
    return stream;
  }

  Widget page(String url, {int type = 1}) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1),
          child: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: Builder(
                builder: (context) => Avatar(
                  faceUrl: url,
                  showName: 'Avatar',
                  type: type,
                ).getImageWidget(context, const TUITheme()),
              ),
            ),
          ),
        ),
      );

  bool paints(WidgetTester tester, ui.Image image) => tester
      .widgetList<RawImage>(find.byType(RawImage))
      .any((raw) => raw.image?.isCloneOf(image) ?? false);

  for (final type in [1, 2]) {
    testWidgets('cached avatar type $type paints on the first entry frame',
        (tester) async {
      const url = 'https://avatar.test/cached.png';
      final image = bitmap(Colors.red);
      await cache(url, image: image);

      await tester.pumpWidget(page(url, type: type));
      expect(paints(tester, image), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(url, type: type));
      expect(paints(tester, image), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('URL refresh keeps the decoded avatar until replacement arrives',
      (tester) async {
    const oldUrl = 'https://avatar.test/old.png';
    const newUrl = 'https://avatar.test/new.png';
    final oldImage = bitmap(Colors.red);
    final newImage = bitmap(Colors.blue);
    await cache(oldUrl, image: oldImage);
    final pending = await cache(newUrl);

    await tester.pumpWidget(page(oldUrl));
    expect(paints(tester, oldImage), isTrue);
    await tester.pumpWidget(page(newUrl));
    expect(paints(tester, oldImage), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(paints(tester, oldImage), isTrue);

    pending.complete(newImage);
    await tester.pump();
    expect(paints(tester, newImage), isTrue);
    expect(paints(tester, oldImage), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold load and failure retain the group fallback',
      (tester) async {
    const url = 'https://avatar.test/missing.png';
    final pending = await cache(url);
    await tester.pumpWidget(page(url, type: 2));

    bool hasGroupFallback() => tester.widgetList<Image>(find.byType(Image)).any(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName ==
                  'images/default_group_head.png',
        );
    expect(hasGroupFallback(), isTrue);
    pending.fail();
    await tester.pump();
    expect(hasGroupFallback(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
