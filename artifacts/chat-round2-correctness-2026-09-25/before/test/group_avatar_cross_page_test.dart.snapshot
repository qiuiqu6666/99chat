import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_group_avatar.dart';
import 'package:tencent_cloud_chat_demo/utils/avatar_image_warm.dart';
import 'package:tencent_cloud_chat_demo/utils/group_avatar_source.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _ImageCompleter extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://avatar.test/group.png';

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  setUp(() {
    AvatarImageWarm.clearRetainedDecoded();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(AvatarImageWarm.clearRetainedDecoded);

  ui.Image bitmap(Color color) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(8, 8);
    picture.dispose();
    return image;
  }

  Future<_ImageCompleter> cache({
    String groupId = 'one',
    int version = 7,
    double dpr = 1,
    ui.Image? image,
  }) async {
    final source = GroupAvatarSource.resolve(
      groupId: groupId,
      fallbackUrl: url,
      fallbackVersion: version,
    );
    final provider = AvatarImageWarm.providerFor(
      url: source.faceUrl,
      cacheKey: source.cacheKey,
      cacheSize: (GroupAvatarSource.cacheLogicalSize(40) * dpr).round(),
    );
    final key = await provider.obtainKey(const ImageConfiguration());
    final completer = _ImageCompleter();
    if (image != null) completer.complete(image);
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => completer);
    return completer;
  }

  Widget page({
    double size = 40,
    double dpr = 1,
    String groupId = 'one',
    int version = 7,
    Future<String?> Function()? preview,
  }) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: dpr),
          child: Center(
              child: AppGroupAvatar(
            groupId: groupId,
            faceUrl: url,
            showName: 'Group',
            size: size,
            avatarVersion: version,
            enablePreview: preview != null,
            previewUrlResolver: preview,
          )),
        ),
      );

  bool paints(WidgetTester tester, ui.Image image) => tester
      .widgetList<RawImage>(find.byType(RawImage))
      .any((raw) => raw.image?.isCloneOf(image) ?? false);

  for (final dpr in [1.0, 2.0, 3.0]) {
    testWidgets('all four page sizes share the first cached frame at DPR $dpr',
        (tester) async {
      final image = bitmap(Colors.red);
      await cache(dpr: dpr, image: image);
      for (final size in [40.0, 48.0, 54.0, 56.0]) {
        await tester.pumpWidget(page(size: size, dpr: dpr));
        expect(paints(tester, image), isTrue, reason: 'size $size');
        expect(tester.getSize(find.byType(AppGroupAvatar)), Size.square(size));
        await tester.pumpWidget(const SizedBox());
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same URL with a new version replaces the image after decoding',
      (tester) async {
    final old = bitmap(Colors.red);
    final next = bitmap(Colors.blue);
    await cache(image: old);
    final pending = await cache(version: 8);
    await tester.pumpWidget(page());
    await tester.pumpWidget(page(version: 8));
    expect(paints(tester, old), isTrue);
    pending.complete(next);
    await tester.pump();
    expect(paints(tester, next), isTrue);
    expect(paints(tester, old), isFalse);
  });

  testWidgets('recycling a row for another group never retains the old avatar',
      (tester) async {
    final old = bitmap(Colors.red);
    await cache(image: old);
    await cache(groupId: 'two');
    await tester.pumpWidget(page());
    expect(paints(tester, old), isTrue);
    await tester.pumpWidget(page(groupId: 'two'));
    expect(paints(tester, old), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warming follows the group tier despite a different page size',
      (tester) async {
    final image = bitmap(Colors.red);
    await cache(image: image);
    await tester.pumpWidget(page());
    final source = GroupAvatarSource.resolve(
      groupId: 'one',
      fallbackUrl: url,
      fallbackVersion: 7,
    );
    await AvatarImageWarm.warmSources(
      [source.warmSource(size: 54)],
      context: tester.element(find.byType(AppGroupAvatar)),
      logicalSize: 40,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page(size: 56));
    expect(paints(tester, image), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a profile does not request the full-size preview',
      (tester) async {
    var requests = 0;
    await cache(image: bitmap(Colors.red));
    await tester.pumpWidget(page(
        size: 56,
        preview: () async {
          requests++;
          return null;
        }));
    await tester.pump();
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
}
