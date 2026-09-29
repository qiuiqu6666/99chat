import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';

void main() {
  Finder paint() => find.descendant(
      of: find.byType(ImagePreviewCenterLoadingIndicator),
      matching: find.byType(CustomPaint));
  double drawn(WidgetTester tester) {
    final dynamic painter = tester.widget<CustomPaint>(paint()).painter;
    return painter.progress as double;
  }

  Future<void> show(WidgetTester tester, double? progress,
          {bool reduceMotion = false}) =>
      tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Center(
                  child: ImagePreviewCenterLoadingIndicator(
                      progress: progress)))));

  testWidgets('short loads never flash; sustained loads fade in once',
      (tester) async {
    await show(tester, null);
    final fade = find.descendant(
        of: find.byType(ImagePreviewCenterLoadingIndicator),
        matching: find.byType(FadeTransition));
    double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await show(tester, 0.25);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), 1);
    await show(tester, 0.5);
    expect(opacity(), 1,
        reason: 'New chunks must not fade the circle in again');
    await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'motion stays within measured bytes and stops when download stalls',
      (tester) async {
    await show(tester, 0.1);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    await show(tester, 0.5);
    expect(drawn(tester), closeTo(0.1, 0.0001));
    await tester.pump(const Duration(milliseconds: 40));
    final midway = drawn(tester);
    expect(midway, inExclusiveRange(0.1, 0.5));
    await show(tester, 0.75);
    expect(drawn(tester), midway, reason: 'Continue from the current angle');
    var previous = midway;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      final value = drawn(tester);
      expect(value, inInclusiveRange(previous, 0.75));
      previous = value;
    }
    expect(drawn(tester), 0.75);
    await show(tester, null);
    await tester.pump(const Duration(seconds: 5));
    expect(drawn(tester), 0.75);
    expect(tester.binding.transientCallbackCount, 0);
    await show(tester, 0.6);
    expect(drawn(tester), 0.6,
        reason: 'A corrected byte total must not leave the display ahead');
  });

  testWidgets('reduced motion displays measured values immediately',
      (tester) async {
    await show(tester, 0.2, reduceMotion: true);
    await show(tester, 0.8, reduceMotion: true);
    expect(drawn(tester), 0.8);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  // Optional visual artifact, rendered by the same Flutter component used in
  // the app. Normal regression runs do not depend on the recording fixture.
  if (const bool.fromEnvironment('CAPTURE_IMAGE_PROGRESS')) {
    testWidgets('capture the real progress component', (tester) async {
      tester.view.physicalSize = const Size(372, 646);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory('build/image-progress-style')
        ..createSync(recursive: true);
      final background = MemoryImage(
          File('build/image-progress-video/preview-background.png')
              .readAsBytesSync());
      final key = GlobalKey();
      for (var frame = 0; frame < 90; frame++) {
        final progress = frame < 12
            ? 0.0
            : frame < 22
                ? 0.18
                : frame < 34
                    ? 0.36
                    : frame < 44
                        ? 0.58
                        : frame < 58
                            ? 0.8
                            : 1.0;
        await tester.pumpWidget(MaterialApp(
            home: RepaintBoundary(
                key: key,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(image: background, fit: BoxFit.cover),
                    if (frame < 70)
                      Center(
                          child: ImagePreviewCenterLoadingIndicator(
                              progress: progress)),
                  ],
                ))));
        await tester.pump(const Duration(microseconds: 33333));
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File('${dir.path}/frame-${frame.toString().padLeft(3, '0')}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
