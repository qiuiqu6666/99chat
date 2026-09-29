import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/avatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets(
      'avatar preview never displays the thumbnail as a full-screen image',
      (tester) async {
    final previousErrorHandler = FlutterError.onError;
    final imageErrors = <String>[];
    FlutterError.onError = (details) {
      imageErrors.add(details.exceptionAsString());
    };
    try {
      const thumbUrl = 'https://avatar.test/user_thumb.png';
      const previewUrl = 'https://avatar.test/user_preview.png';
      final avatar = Avatar(
        faceUrl: thumbUrl,
        showName: 'User',
        previewFaceUrl: previewUrl,
      );
      for (final url in [thumbUrl, previewUrl]) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final bitmap = picture.toImageSync(8, 8);
        picture.dispose();
        final provider = avatar.getImageProvider(url: url);
        final key = await provider.obtainKey(const ImageConfiguration());
        final stream = OneFrameImageStreamCompleter(
          Future<ImageInfo>.value(ImageInfo(image: bitmap)),
        );
        PaintingBinding.instance.imageCache.putIfAbsent(key, () => stream);
      }
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
        await tester.pump(const Duration(milliseconds: 100));
      }
      final imageScreen = tester.widget<ImageScreen>(find.byType(ImageScreen));
      expect(
          imageScreen.imageProvider, avatar.getImageProvider(url: previewUrl));
      expect(imageScreen.placeholderImageProvider, isNull);
      expect(imageScreen.enableHero, isFalse);

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
