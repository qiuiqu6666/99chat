import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_overlay_route.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_image_page.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/gestured_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  const _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image.clone())),
      );
}

class _DelayedPreviewProvider extends ImageProvider<_DelayedPreviewProvider> {
  final ready = Completer<ImageInfo>();
  int loads = 0;
  @override
  Future<_DelayedPreviewProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _DelayedPreviewProvider key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(ready.future);
  }
}

Future<Color> _pixelAt(
  WidgetTester tester,
  GlobalKey boundaryKey,
  int x,
  int y,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (y * image.width + x) * 4;
    final color = Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}

Future<Rect> _redBounds(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var left = image.width, top = image.height, right = -1, bottom = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        if (data.getUint8(offset) > 200 && data.getUint8(offset + 1) < 20) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    image.dispose();
    return Rect.fromLTRB(
        left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
  }))!;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final mixed in [false, true]) {
    for (final scenario in ['ready', 'slow', 'failed', 'drag', 'close_early']) {
      testWidgets(
          '${mixed ? 'mixed' : 'single'} thumbnail lands before original: $scenario',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final errorHandler = FlutterError.onError;
        addTearDown(() => FlutterError.onError = errorHandler);
        ui.Image bitmap(Color color) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
              const Rect.fromLTWH(0, 0, 400, 400), Paint()..color = color);
          final picture = recorder.endRecording();
          final image = picture.toImageSync(400, 400);
          picture.dispose();
          return image;
        }

        final thumb = bitmap(const Color(0xFFFF0000)),
            full = bitmap(const Color(0xFF0000FF));
        addTearDown(thumb.dispose);
        addTearDown(full.dispose);
        final thumbnail = _TestImageProvider(thumb);
        final original = _DelayedPreviewProvider();
        if (scenario == 'ready' || scenario == 'drag') {
          original.ready.complete(ImageInfo(image: full.clone()));
        }
        final message =
            V2TimMessage.fromJson({'message_risk_type_identified': 0})
              ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
              ..imageElem = V2TimImageElem(
                  imageList: [V2TimImage(type: 0, width: 400, height: 400)]);
        final preview = mixed
            ? ChatMediaGalleryScreen(items: [
                ChatMediaPreviewItem(
                    message: message,
                    type: ChatMediaPreviewType.image,
                    heroTag: 'handoff',
                    imageProvider: original,
                    placeholderImageProvider: thumbnail)
              ], initialIndex: 0, sourceMessage: message)
            : ImageScreen(
                imageProvider: original,
                placeholderImageProvider: thumbnail,
                heroTag: 'handoff',
                sourceMessage: message);
        final navigator = GlobalKey<NavigatorState>(), boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorKey: navigator,
              home: const ColoredBox(
                  color: Colors.black,
                  child: Stack(children: [
                    Positioned(
                        left: 20,
                        top: 550,
                        width: 80,
                        height: 80,
                        child: PreviewHero(
                            tag: 'handoff',
                            child: SizedBox(
                                width: 80,
                                height: 80,
                                child: ColoredBox(color: Color(0xFFFF0000))))),
                  ])),
            )));
        navigator.currentState!.push(MediaPreviewOverlayRoute<void>(
          enableGestureBack: false,
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, animation, secondaryAnimation) =>
              MediaPreviewChromeScope(animation: animation, child: preview),
        ));
        await tester.pump();
        FlutterError.onError = errorHandler;
        await tester.pump();
        FlutterError.onError = errorHandler;
        await tester.pump(const Duration(milliseconds: 150));
        FlutterError.onError = errorHandler;
        expect(original.loads, 0,
            reason:
                'No original image resolution during the position animation');
        expect(await _pixelAt(tester, boundary, 100, 430),
            const Color(0xFFFF0000));
        if (scenario == 'close_early') {
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
          expect(original.loads, 0);
        } else {
          await tester.pump(const Duration(milliseconds: 150));
          FlutterError.onError = errorHandler;
          await tester.pump(const Duration(milliseconds: 20));
          FlutterError.onError = errorHandler;
          await tester.pump();
          FlutterError.onError = errorHandler;
          await tester.pump();
          FlutterError.onError = errorHandler;
          expect(original.loads, greaterThan(0));
          if (scenario == 'slow' || scenario == 'failed') {
            expect(find.byType(ImagePreviewCenterLoadingIndicator), findsOneWidget);
            expect(tester.getCenter(find.byType(ImagePreviewCenterLoadingIndicator)),
                const Offset(200, 400));
            // Away from the loading indicator, the landed thumbnail remains.
            expect(await _pixelAt(tester, boundary, 80, 300),
                const Color(0xFFFF0000));
            if (scenario == 'failed') {
              original.ready.completeError(StateError('original unavailable'));
            } else {
              original.ready.complete(ImageInfo(image: full.clone()));
            }
          }
          await tester.pump();
          FlutterError.onError = errorHandler;
          await tester.pump(const Duration(milliseconds: 20));
          FlutterError.onError = errorHandler;
          final expected = scenario == 'failed'
              ? const Color(0xFFFF0000)
              : const Color(0xFF0000FF);
          expect(find.byType(ImagePreviewCenterLoadingIndicator), findsNothing);
          expect(await _pixelAt(tester, boundary, 80, 300), expected);
          expect(await _pixelAt(tester, boundary, 320, 550), expected);
          final route = ModalRoute.of(tester.element(find.byWidget(preview)))!;
          if (scenario == 'drag') {
            await tester.dragFrom(const Offset(200, 400), const Offset(0, 150));
          } else {
            await tester.binding.handlePopRoute();
          }
          expect(route.animation!.status, AnimationStatus.reverse,
              reason:
                  'Back starts the bubble flight directly, without a preliminary scale/fade');
          await tester.pump();
          FlutterError.onError = errorHandler;
          var elapsed = 0;
          final duration = route.reverseTransitionDuration.inMilliseconds;
          for (final time in [
            (duration * .2).round(),
            (duration * .5).round(),
            (duration * .9).round(),
            duration - 1
          ]) {
            await tester.pump(Duration(milliseconds: time - elapsed));
            FlutterError.onError = errorHandler;
            elapsed = time;
            final rect = Rect.lerp(
              const Rect.fromLTWH(20, 550, 80, 80),
              const Rect.fromLTWH(0, 200, 400, 400),
              1 - Curves.fastOutSlowIn.transform(time / duration),
            )!;
            if (scenario != 'drag' || time == duration - 1) {
              expect(
                  await _pixelAt(tester, boundary, rect.center.dx.round(),
                      (rect.top + 4).round()),
                  expected);
              expect(
                  await _pixelAt(tester, boundary, rect.center.dx.round(),
                      (rect.bottom - 4).round()),
                  expected);
            }
          }
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
          expect(await _pixelAt(tester, boundary, 60, 590),
              const Color(0xFFFF0000));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        FlutterError.onError = errorHandler;
        await tester.pumpAndSettle();
        FlutterError.onError = errorHandler;
        PaintingBinding.instance.imageCache.clear();
      });
    }
  }

  for (final mixedGallery in [false, true]) {
    testWidgets(
        '${mixedGallery ? 'mixed gallery' : 'image preview'} lands continuously and zooms beyond the initial image',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final errorHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = errorHandler);

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 400, 400),
        Paint()..color = const Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(400, 400);
      picture.dispose();
      addTearDown(image.dispose);
      final boundaryKey = GlobalKey();
      final navigatorKey = GlobalKey<NavigatorState>();
      final message = V2TimMessage.fromJson({
        'timestamp': 1,
        'message_is_from_self': false,
        'message_risk_type_identified': 0,
      })
        ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
        ..imageElem = V2TimImageElem(imageList: [
          V2TimImage(type: 0, width: 400, height: 400),
        ]);
      final metrics = MediaPreviewSlideMetrics();
      addTearDown(metrics.dispose);
      final Widget preview = mixedGallery
          ? ChatMediaGalleryImagePage(
              item: ChatMediaPreviewItem(
                message: message,
                type: ChatMediaPreviewType.image,
                heroTag: 'preview',
                imageProvider: _TestImageProvider(image),
              ),
              inPageView: false,
              isActive: true,
              allowHero: true,
              entranceSettled: true,
              isGalleryScrolling: false,
              slidePageKey: GlobalKey(),
              slideMetrics: metrics,
              onTap: () {},
            )
          : ImageScreen(
              imageProvider: _TestImageProvider(image),
              heroTag: 'preview',
              sourceMessage: message,
            );
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const ColoredBox(
            color: Colors.black,
            child: Stack(children: [
              Positioned(
                left: 20,
                top: 550,
                width: 80,
                height: 80,
                child: PreviewHero(
                  tag: 'preview',
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: ColoredBox(color: Color(0xFFFF0000)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ));
      navigatorKey.currentState!.push(MediaPreviewOverlayRoute<void>(
        enableGestureBack: false,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ColoredBox(color: Colors.black, child: preview),
      ));
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pump();
      FlutterError.onError = errorHandler;
      // Inspect the actual Hero overlay before handoff to the preview. Its
      // content must already be centered, not fly to y=0 and jump on landing.
      var elapsed = 0;
      for (final time in [60, 150, 250, 299]) {
        await tester.pump(Duration(milliseconds: time - elapsed));
        elapsed = time;
        FlutterError.onError = errorHandler;
        final expected = Rect.lerp(
          const Rect.fromLTWH(20, 550, 80, 80),
          const Rect.fromLTWH(0, 200, 400, 400),
          Curves.fastOutSlowIn.transform(time / 300),
        )!;
        // Probe just inside/outside the image's expected top and bottom,
        // rather than checking the already-settled preview alone.
        final x = expected.center.dx.round();
        for (final y in [expected.top + 3, expected.bottom - 3]) {
          expect(await _pixelAt(tester, boundaryKey, x, y.round()),
              const Color(0xFFFF0000));
        }
        for (final y in [expected.top - 3, expected.bottom + 3]) {
          expect(
              await _pixelAt(tester, boundaryKey, x, y.round()), Colors.black);
        }
      }
      FlutterError.onError = errorHandler;
      await tester.pump(const Duration(milliseconds: 500));
      FlutterError.onError = errorHandler;
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;

      expect(await _pixelAt(tester, boundaryKey, 200, 150), Colors.black);
      expect(await _pixelAt(tester, boundaryKey, 200, 400),
          const Color(0xFFFF0000));
      final heroLayout = tester.widget<MediaPreviewHeroLayout>(
        find.byType(MediaPreviewHeroLayout),
      );
      expect(
          heroLayout.inset(tester.getRect(find.descendant(
              of: find.byType(MediaPreviewHeroLayout),
              matching: find.byType(Hero)))),
          const Rect.fromLTWH(0, 200, 400, 400));

      final gesture =
          tester.state<GesturedImageState>(find.byType(GesturedImage));
      gesture.handleDoubleTap(
          scale: 3, doubleTapPosition: const Offset(200, 400));
      await tester.pump();
      FlutterError.onError = errorHandler;
      expect(await _pixelAt(tester, boundaryKey, 200, 150),
          const Color(0xFFFF0000));
      expect(await _pixelAt(tester, boundaryKey, 200, 650),
          const Color(0xFFFF0000));

      final before = gesture.gestureDetails!.offset!;
      await tester.dragFrom(const Offset(200, 150), const Offset(0, 60));
      await tester.pump();
      FlutterError.onError = errorHandler;
      expect(gesture.gestureDetails!.offset!.dy, greaterThan(before.dy));

      gesture.reset();
      await tester.pump();
      FlutterError.onError = errorHandler;
      expect(await _pixelAt(tester, boundaryKey, 200, 150), Colors.black);
      navigatorKey.currentState!.pop();
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pump(const Duration(milliseconds: 1));
      FlutterError.onError = errorHandler;
      expect(await _pixelAt(tester, boundaryKey, 200, 150), Colors.black);
      expect(await _pixelAt(tester, boundaryKey, 200, 550),
          const Color(0xFFFF0000));
      elapsed = 1;
      for (final time in [60, 150, 250]) {
        await tester.pump(Duration(milliseconds: time - elapsed));
        elapsed = time;
        FlutterError.onError = errorHandler;
        final expected = Rect.lerp(
          const Rect.fromLTWH(20, 550, 80, 80),
          const Rect.fromLTWH(0, 200, 400, 400),
          1 - Curves.fastOutSlowIn.transform(time / 300),
        )!;
        final painted = await _redBounds(tester, boundaryKey);
        expect(painted.left, closeTo(expected.left, 1.5));
        expect(painted.top, closeTo(expected.top, 1.5));
        expect(painted.right, closeTo(expected.right, 1.5));
        expect(painted.bottom, closeTo(expected.bottom, 1.5));
        final x = expected.center.dx.round();
        for (final y in [expected.top + 3, expected.bottom - 3]) {
          expect(await _pixelAt(tester, boundaryKey, x, y.round()),
              const Color(0xFFFF0000),
              reason: 'return image at ${time}ms');
        }
        for (final y in [expected.top - 3, expected.bottom + 3]) {
          expect(
              await _pixelAt(tester, boundaryKey, x, y.round()), Colors.black,
              reason: 'no stationary duplicate at ${time}ms');
        }
      }
      await tester.pumpAndSettle();
      FlutterError.onError = errorHandler;
      expect(await _pixelAt(tester, boundaryKey, 60, 590),
          const Color(0xFFFF0000));
      expect(await _pixelAt(tester, boundaryKey, 200, 400), Colors.black);
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = errorHandler;
      await tester.pumpAndSettle();
    });
  }
}
