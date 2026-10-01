import 'dart:async';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
// UIKit's image renderer is intentionally tested through its transitive dependency.
// ignore: depend_on_referenced_packages
import 'package:extended_image/extended_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';

class _MemoryAvatar extends Avatar {
  _MemoryAvatar(
      {required super.faceUrl,
      required super.previewFaceUrl,
      required super.type,
      required this.providers})
      : super(showName: 'Avatar');
  final Map<String, ImageProvider> providers;
  @override
  ImageProvider getImageProvider({String? url, String? cacheKey}) =>
      providers[url ?? faceUrl]!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final viewport in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 768)
  ]) {
    for (final pixels in [
      const Size(64, 64),
      const Size(180, 180),
      const Size(1200, 400),
      const Size(200, 1200)
    ]) {
      test('avatar contain fit $pixels in $viewport', () {
        final config = imagePreviewDisplayConfigResolved(
            sourceMessage: null,
            decodedWidth: pixels.width.toInt(),
            decodedHeight: pixels.height.toInt(),
            screenWidth: viewport.width,
            screenHeight: viewport.height,
            fitTallImagesToScreenWidth: false,
            fitToViewport: true);
        final size = imagePreviewInitialDisplaySize(
            imageWidth: config.imageWidth,
            imageHeight: config.imageHeight,
            screenWidth: viewport.width,
            screenHeight: viewport.height,
            fit: config.fit);
        expect(size.width, lessThanOrEqualTo(viewport.width + 0.01));
        expect(size.height, lessThanOrEqualTo(viewport.height + 0.01));
        expect(
            (size.width - viewport.width).abs() < 0.01 ||
                (size.height - viewport.height).abs() < 0.01,
            isTrue);
        expect(size.aspectRatio, closeTo(pixels.aspectRatio, 0.0001));
        expect(config.verticallyScrollable, isFalse);
        expect(config.alignment, Alignment.center);
      });
    }
  }

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final avatarType in [1, 2]) {
    testWidgets('avatar type=$avatarType fills viewport using preview image',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousErrorHandler = FlutterError.onError;
      final imageErrors = <String>[];
      FlutterError.onError = (details) {
        imageErrors.add(details.exceptionAsString());
      };
      try {
        const thumbUrl = 'https://avatar.test/user_thumb.png';
        const previewUrl = 'https://avatar.test/user_preview.png';
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final bytes = await tester.runAsync(() async {
          final bitmap = await picture.toImage(180, 180);
          final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          bitmap.dispose();
          return data!.buffer.asUint8List();
        });
        picture.dispose();
        final avatar = _MemoryAvatar(
            type: avatarType,
            faceUrl: thumbUrl,
            previewFaceUrl: previewUrl,
            providers: {
              thumbUrl: MemoryImage(bytes!),
              previewUrl: MemoryImage(bytes),
            });
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => avatar.openPreview(context),
                child: const Text('Open avatar'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Open avatar'));
        await tester.pump();
        for (var frame = 0;
            frame < 8 && find.byType(ImageScreen).evaluate().isEmpty;
            frame++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump(const Duration(milliseconds: 100));
        }
        final imageScreen =
            tester.widget<ImageScreen>(find.byType(ImageScreen));
        expect(imageScreen.imageProvider,
            avatar.getImageProvider(url: previewUrl));
        expect(imageScreen.placeholderImageProvider, isNull);
        expect(imageScreen.enableHero, isFalse);
        expect(imageScreen.fitToViewport, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        for (var frame = 0; frame < 20; frame++) {
          final dynamic state = tester.state(find.byType(ExtendedImage).first);
          if (state.extendedImageInfo != null) break;
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
            (tester.state(find.byType(ExtendedImage).first) as dynamic)
                .extendedImageInfo,
            isNotNull);
        final image =
            tester.widget<ExtendedImage>(find.byType(ExtendedImage).first);
        expect(image.fit, BoxFit.contain);
        expect(tester.getSize(find.byType(ExtendedImage).first),
            tester.view.physicalSize / tester.view.devicePixelRatio);

        if (const bool.fromEnvironment('CAPTURE_AVATAR_PREVIEW')) {
          final boundary = tester
              .element(find.byType(ExtendedImage).first)
              .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
          await tester.runAsync(() async {
            final capture = await boundary.toImage();
            final bytes =
                await capture.toByteData(format: ui.ImageByteFormat.png);
            final file =
                File('artifacts/avatar-preview-fit/type-$avatarType.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            capture.dispose();
          });
        }
        tester.view.physicalSize = const Size(844, 390);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
            tester.widget<ExtendedImage>(find.byType(ExtendedImage).first).fit,
            BoxFit.contain);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ImageScreen), findsNothing);
      } finally {
        FlutterError.onError = previousErrorHandler;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(imageErrors, isEmpty);
    });
  }

  testWidgets('avatar waits for its preview without a black loading flash',
      (tester) async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    final preview = Completer<String?>();
    final avatar = Avatar(
      faceUrl: 'https://avatar.test/user_thumb.png',
      showName: 'User',
      previewUrlResolver: () => preview.future,
    );
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => avatar.openPreview(context),
              child: const Text('Open avatar'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open avatar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ImageScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Open avatar'), findsOneWidget);
    } finally {
      if (!preview.isCompleted) preview.complete(null);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      FlutterError.onError = previousErrorHandler;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    }
  });
}
