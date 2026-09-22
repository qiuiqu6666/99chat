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
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_overlay_route.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/gestured_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_shell.dart';

class _BitmapProvider extends ImageProvider<_BitmapProvider> {
  const _BitmapProvider(this.bitmap);
  final ui.Image bitmap;
  @override
  Future<_BitmapProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
          _BitmapProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: bitmap.clone())));
}

Future<List<Color>> _pixels(
    WidgetTester tester, GlobalKey key, List<Offset> points) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = points.map((point) {
      final offset = (point.dy.round() * image.width + point.dx.round()) * 4;
      return Color.fromARGB(bytes.getUint8(offset + 3), bytes.getUint8(offset),
          bytes.getUint8(offset + 1), bytes.getUint8(offset + 2));
    }).toList();
    image.dispose();
    return colors;
  }))!;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets('image backdrop fades in and reveals chat during drag',
      (tester) async {
    final animation = AnimationController(
        vsync: tester, value: .1, duration: const Duration(milliseconds: 340));
    final latch = MediaPreviewEntranceLatch(onSettled: () {});
    final metrics = MediaPreviewSlideMetrics();
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
      key: boundary,
      child: ColoredBox(
          color: Colors.white,
          child: MediaPreviewChromeScope(
            animation: animation,
            child: MediaPreviewSlideShell(
                  slidePageKey: GlobalKey(),
              slideMetrics: metrics,
              entranceLatch: latch,
              onSlidingPage: (_) {},
              slideEndHandler: (_, {state, details}) => false,
              bodyBuilder: (_, __) => const SizedBox.expand(),
              chromeBuilder: (_) => const SizedBox.shrink(),
              onClose: () {},
              opaquePlatformBackdrop: false,
              enableEdgeBack: false,
            ),
          )),
    )));
    final entering =
        (await _pixels(tester, boundary, [const Offset(10, 10)])).single;
    expect(entering.r * 255, closeTo(230, 2));
    animation.value = 1;
    await tester.pump();
    expect((await _pixels(tester, boundary, [const Offset(10, 10)])).single,
        Colors.black);
    metrics.applyVerticalDrag(200, const Size(400, 800));
    await tester.pump();
    final dragging =
        (await _pixels(tester, boundary, [const Offset(10, 10)])).single;
    expect(dragging.r, greaterThan(.1));
    await tester.pumpWidget(const SizedBox.shrink());
    latch.dispose();
    metrics.dispose();
    animation.dispose();
  });

  for (final mixed in [false, true]) {
    for (final scenario in ['zoom', 'scroll', 'slide', 'interrupt']) {
      final tall = scenario == 'scroll';
      testWidgets(
          '${mixed ? 'gallery' : 'single'} $scenario closes from painted frame',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final errorHandler = FlutterError.onError;
        addTearDown(() => FlutterError.onError = errorHandler);
        final height = tall ? 2400 : 400;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        const colors = [
          Color(0xFFFF0000),
          Color(0xFF00FF00),
          Color(0xFF0000FF),
          Color(0xFFFFFF00)
        ];
        for (var y = 0; y < height; y += 100) {
          for (var x = 0; x < 400; x += 100) {
            canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 100, 100),
                Paint()..color = colors[(x ~/ 100 + y ~/ 100) % colors.length]);
          }
        }
        final picture = recorder.endRecording();
        final bitmap = picture.toImageSync(400, height);
        picture.dispose();
        addTearDown(bitmap.dispose);
        final provider = _BitmapProvider(bitmap);
        final message =
            V2TimMessage.fromJson({'message_risk_type_identified': 0})
              ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
              ..imageElem = V2TimImageElem(
                  imageList: [V2TimImage(type: 0, width: 400, height: height)]);
        final preview = mixed
            ? ChatMediaGalleryScreen(items: [
                ChatMediaPreviewItem(
                    message: message,
                    type: ChatMediaPreviewType.image,
                    heroTag: 'continuity',
                    imageProvider: provider,
                    placeholderImageProvider: provider)
              ], initialIndex: 0, sourceMessage: message)
            : ImageScreen(
                imageProvider: provider,
                placeholderImageProvider: provider,
                heroTag: 'continuity',
                sourceMessage: message);
        final navigator = GlobalKey<NavigatorState>(), boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorKey: navigator,
              home: ColoredBox(
                  color: Colors.white,
                  child: Stack(children: [
                    Positioned(
                        left: 20,
                        top: 550,
                        width: 80,
                        height: 120,
                        child: PreviewHero(
                            tag: 'continuity',
                            child: Image(
                                image: provider,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter))),
                  ])),
            )));
        await tester.pumpAndSettle();
        final bubbleBefore = await _pixels(
            tester, boundary, [const Offset(40, 570), const Offset(75, 630)]);
        navigator.currentState!.push(MediaPreviewOverlayRoute<void>(
          enableGestureBack: false,
          pageBuilder: (_, animation, __) =>
              MediaPreviewChromeScope(animation: animation, child: preview),
        ));
        await tester.pump();
        FlutterError.onError = errorHandler;
        await tester.pump();
        FlutterError.onError = errorHandler;
        if (scenario == 'interrupt') {
          await tester.pump(const Duration(milliseconds: 100));
          FlutterError.onError = errorHandler;
          final opening =
              await _pixels(tester, boundary, [const Offset(60, 560)]);
          navigator.currentState!.pop();
          await tester.pump();
          FlutterError.onError = errorHandler;
          await tester.pump();
          FlutterError.onError = errorHandler;
          expect(await _pixels(tester, boundary, [const Offset(60, 560)]),
              opening);
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
          expect(
              await _pixels(tester, boundary,
                  [const Offset(40, 570), const Offset(75, 630)]),
              bubbleBefore);
          await tester.pumpWidget(const SizedBox.shrink());
          FlutterError.onError = errorHandler;
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
          PaintingBinding.instance.imageCache.clear();
          return;
        }
        await tester.pump(const Duration(milliseconds: 339));
        FlutterError.onError = errorHandler;
        const points = [
          Offset(45, 240),
          Offset(145, 350),
          Offset(260, 460),
          Offset(355, 560)
        ];
        final landing = await _pixels(tester, boundary, points);
        await tester.pumpAndSettle();
        FlutterError.onError = errorHandler;
        expect(await _pixels(tester, boundary, points), landing,
            reason: 'The final flight crop must match the landed preview');
        TestGesture? slide;
        if (scenario == 'slide') {
          slide = await tester.startGesture(const Offset(200, 400));
          await slide.moveBy(const Offset(0, 20));
          await tester.pump();
          FlutterError.onError = errorHandler;
          await slide.moveBy(const Offset(0, 150));
          await tester.pump();
          FlutterError.onError = errorHandler;
        } else if (tall) {
          // Pin a deterministic scrolled viewport; gesture routing/inertia is
          // covered by the tall-image gesture suite separately.
          final viewer = tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
          viewer.transformationController!.value = Matrix4.identity()
            ..translateByDouble(0, -250, 0, 1);
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
        } else {
          final gesture = tester
              .state<GesturedImageState>(find.byType(GesturedImage).first);
          gesture.handleDoubleTap(
              scale: 3, doubleTapPosition: const Offset(200, 400));
          await tester.pump();
          FlutterError.onError = errorHandler;
          await tester.dragFrom(const Offset(200, 400), const Offset(75, 110));
          await tester.pumpAndSettle();
          FlutterError.onError = errorHandler;
        }
        final before = await _pixels(tester, boundary, points);
        expect(before, isNot(landing),
            reason: 'Exercise a changed visible crop');
        if (slide != null) {
          await slide.up();
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump();
        FlutterError.onError = errorHandler;
        await tester.pump();
        FlutterError.onError = errorHandler;
        expect(await _pixels(tester, boundary, points), before,
            reason:
                'Closing must retain the exact zoom/pan/scroll crop on its first frame');
        await tester.pump(const Duration(milliseconds: 279));
        FlutterError.onError = errorHandler;
        expect(
            await _pixels(tester, boundary,
                [const Offset(40, 570), const Offset(75, 630)]),
            bubbleBefore,
            reason: 'The last return frame must already match the bubble crop');
        await tester.pumpAndSettle();
        FlutterError.onError = errorHandler;
        expect(
            await _pixels(tester, boundary,
                [const Offset(40, 570), const Offset(75, 630)]),
            bubbleBefore);
        await tester.pumpWidget(const SizedBox.shrink());
        FlutterError.onError = errorHandler;
        await tester.pumpAndSettle();
        FlutterError.onError = errorHandler;
        PaintingBinding.instance.imageCache.clear();
      });
    }
  }
}
