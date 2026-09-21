import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _ControlledCompleter extends ImageStreamCompleter {}

void main() {
  late ui.Image bitmap;
  final streams = <_ControlledCompleter>[];
  final handles = <ImageStreamCompleterHandle>[];
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final picture = recorder.endRecording();
    bitmap = picture.toImageSync(1, 1);
    picture.dispose();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    for (final handle in handles) {
      handle.dispose();
    }
    handles.clear();
    streams.clear();
    bitmap.dispose();
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500);
  });

  Future<_ControlledCompleter> cacheImage(String url, double dpr,
      {bool ready = true}) async {
    final stream = _ControlledCompleter();
    streams.add(stream);
    handles.add(stream.keepAlive());
    if (ready) stream.setImage(ImageInfo(image: bitmap.clone()));
    PaintingBinding.instance.imageCache.putIfAbsent(
      await ResizeImage(
              CachedNetworkImageProvider(
                url,
                cacheKey: stickerNetworkImageCacheKey('test', url),
              ),
              width: stickerDecodePixels(80, dpr),
              height: stickerDecodePixels(80, dpr),
              policy: ResizeImagePolicy.fit,
              allowUpscaling: false)
          .obtainKey(ImageConfiguration.empty),
      () => stream,
    );
    return stream;
  }

  Future<void> visibility(WidgetTester tester, bool visible) async {
    final detector =
        tester.widget<VisibilityDetector>(find.byType(VisibilityDetector));
    detector.onVisibilityChanged!(VisibilityInfo(
      key: detector.key!,
      size: const Size(80, 80),
      visibleBounds: visible ? const Rect.fromLTWH(0, 0, 80, 80) : Rect.zero,
    ));
    await tester.pump();
  }

  for (final thumbCase in [
    'same URL',
    'missing thumbnail',
    'failed thumbnail'
  ]) {
    testWidgets(
        '$thumbCase unmounts animation offscreen and restores on return',
        (tester) async {
      const origin = 'https://example.invalid/sticker.gif';
      const thumb = 'https://example.invalid/thumbnail.png';
      final animated = await cacheImage(origin, tester.view.devicePixelRatio);
      final failure = thumbCase == 'failed thumbnail';
      final failedThumb = failure
          ? await cacheImage(thumb, tester.view.devicePixelRatio, ready: false)
          : null;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: StickerImage(
            item: StickerItem(
              stickerId: 'test',
              originUrl: origin,
              thumbUrl: failure
                  ? thumb
                  : thumbCase == 'same URL'
                      ? origin
                      : '',
              mediaType: 'gif',
            ),
            width: 80,
            height: 80,
            preferAnimated: !failure,
            pauseWhenOffscreen: true,
          ),
        ),
      ));
      if (failedThumb != null) {
        failedThumb.reportError(exception: StateError('thumbnail failed'));
        await tester.pump();
      }
      expect(animated.hasListeners, isTrue);
      expect(find.byType(Image), findsNWidgets(failure ? 2 : 1));
      await visibility(tester, false);
      expect(find.byType(Image), findsNothing);
      expect(animated.hasListeners, isFalse,
          reason:
              'No ImageState listener may keep GIF frames running offscreen');
      await tester.pump(const Duration(seconds: 6));
      expect(animated.hasListeners, isFalse);
      await visibility(tester, true);
      if (failedThumb != null) {
        await tester.pump();
      }
      expect(find.byType(Image), findsNWidgets(failure ? 2 : 1));
      expect(animated.hasListeners, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(animated.hasListeners, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
