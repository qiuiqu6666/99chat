// Integration coverage intentionally uses the image/cache dependencies owned
// by the local tencent_cloud_chat_uikit package.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:file/memory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/gestured_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';

class _Thumbnail extends ImageProvider<_Thumbnail> {
  _Thumbnail(this.image);
  final ui.Image image;
  @override
  Future<_Thumbnail> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Thumbnail key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

class _Download extends Fake implements BaseCacheManager {
  final events = StreamController<FileResponse>();
  int requests = 0;
  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    expect(withProgress, isTrue);
    requests++;
    return events.stream;
  }
}

// The intermediate BIG tier must never be downloaded just to start a second
// progress cycle for ORIGIN. This reproduces the two-stage flow in the recording.
class _IntermediateBig extends ImageProvider<_IntermediateBig> {
  int loads = 0;
  final ready = Completer<ImageInfo>();
  @override
  Future<_IntermediateBig> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _IntermediateBig key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(ready.future);
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    // Avoid initializing the disk cache/path_provider in this widget-test isolate.
    CachedNetworkImageProvider.defaultCacheManager = _Download();
  });

  testWidgets('unknown and stalled progress schedule no animation frames',
      (tester) async {
    for (final progress in <double?>[null, 0, 0.25, null, 1]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: ImagePreviewCenterLoadingIndicator(progress: progress))));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.binding.transientCallbackCount, 0);
      final paint = find.descendant(
          of: find.byType(ImagePreviewCenterLoadingIndicator),
          matching: find.byType(CustomPaint));
      final widget = tester.widget(paint);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.widget(paint), same(widget),
          reason: 'Time alone cannot advance or restart the loading sector');
    }
  });

  testWidgets('sector paints measured quarters clockwise from twelve oclock',
      (tester) async {
    final boundaryKey = GlobalKey();
    for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: ImagePreviewCenterLoadingIndicator(
                      size: 52, progress: progress)))));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final data = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!;
      });
      // Probe safely inside each quadrant, away from ring and sector edges.
      final samples = [
        const Offset(36, 16),
        const Offset(36, 36),
        const Offset(16, 36),
        const Offset(16, 16)
      ];
      for (var quadrant = 0; quadrant < samples.length; quadrant++) {
        final point = samples[quadrant];
        final red =
            data!.getUint8((point.dy.toInt() * 52 + point.dx.toInt()) * 4);
        expect(red > 200, quadrant < progress * 4,
            reason: '$progress must fill exactly ${progress * 4} quarters');
      }
    }
  });

  for (final mixed in [false, true]) {
    for (final closeEarly in [false, true]) {
      testWidgets(
          '${mixed ? 'mixed' : 'single'} original byte progress preserves image subtree, closeEarly=$closeEarly',
          (tester) async {
        final errorHandler = FlutterError.onError;
        addTearDown(() => FlutterError.onError = errorHandler);
        final cache = _Download();
        final oldCache = CachedNetworkImageProvider.defaultCacheManager;
        CachedNetworkImageProvider.defaultCacheManager = cache;
        addTearDown(
            () => CachedNetworkImageProvider.defaultCacheManager = oldCache);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.red, BlendMode.src);
        final picture = recorder.endRecording();
        final bitmap = picture.toImageSync(400, 400);
        picture.dispose();
        addTearDown(bitmap.dispose);
        final thumbnail = _Thumbnail(bitmap);
        final intermediate = _IntermediateBig();
        final url = 'https://image.test/original-$mixed-$closeEarly.png';
        final message =
            V2TimMessage.fromJson({'message_risk_type_identified': 0})
              ..msgID = 'measured-$mixed-$closeEarly'
              ..elemType = 3
              ..imageElem = V2TimImageElem(imageList: [
                V2TimImage(type: 0, width: 400, height: 400, url: url),
              ]);
        await tester.pumpWidget(MaterialApp(
            home: mixed
                ? ChatMediaGalleryScreen(
                    initialIndex: 0,
                    enableHero: false,
                    items: [
                        ChatMediaPreviewItem(
                            message: message,
                            type: ChatMediaPreviewType.image,
                            heroTag: url,
                            imageProvider: intermediate,
                            placeholderImageProvider: thumbnail),
                      ])
                : ImageScreen(
                    imageProvider: intermediate,
                    placeholderImageProvider: thumbnail,
                    heroTag: url,
                    sourceMessage: message,
                    enableHero: false)));
        FlutterError.onError = errorHandler;
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
          FlutterError.onError = errorHandler;
        }
        expect(cache.requests, 1);
        expect(intermediate.loads, 0,
            reason:
                'Keep the thumbnail and download ORIGIN once, skipping BIG');
        final image = tester.widget(find.byType(ExtendedImage));
        final gesture = tester.element(find.byType(GesturedImage));
        final indicator =
            tester.element(find.byType(ImagePreviewCenterLoadingIndicator));
        for (final bytes in [10, 25, 50, 75, 100]) {
          cache.events.add(DownloadProgress(url, 100, bytes));
          await tester.pump();
          await tester.pump();
          FlutterError.onError = errorHandler;
          expect(
              tester
                  .widget<ImagePreviewCenterLoadingIndicator>(
                      find.byType(ImagePreviewCenterLoadingIndicator))
                  .progress,
              bytes / 100);
          expect(tester.widget(find.byType(ExtendedImage)), same(image),
              reason: 'A download chunk must not rebuild the displayed image');
          expect(tester.element(find.byType(GesturedImage)), same(gesture));
          expect(
              tester.element(find.byType(ImagePreviewCenterLoadingIndicator)),
              same(indicator));
          await tester.pump(const Duration(seconds: 1));
          FlutterError.onError = errorHandler;
          expect(cache.requests, 1);
        }
        if (closeEarly) {
          await tester.pumpWidget(const SizedBox.shrink());
          FlutterError.onError = errorHandler;
          cache.events.add(DownloadProgress(url, 100, 100));
          unawaited(cache.events.close());
          await tester.pump();
        } else {
          // 100% downloaded remains visible until a decoded frame is available.
          expect(
              find.byType(ImagePreviewCenterLoadingIndicator), findsOneWidget);
          final file = await tester.runAsync(() async {
            final bytes =
                (await bitmap.toByteData(format: ui.ImageByteFormat.png))!;
            return MemoryFileSystem().file('/original.png')
              ..writeAsBytesSync(bytes.buffer.asUint8List());
          });
          cache.events.add(FileInfo(file!, FileSource.Online,
              DateTime.now().add(const Duration(days: 1)), url));
          unawaited(cache.events.close());
          var finished = false;
          for (var frame = 0; frame < 8; frame++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)));
            await tester.pump();
            FlutterError.onError = errorHandler;
            final loading = find.byType(ImagePreviewCenterLoadingIndicator);
            if (loading.evaluate().isEmpty) {
              finished = true;
            } else {
              expect(finished, isFalse,
                  reason: 'The ring must not reappear after the decoded frame');
              expect(
                  tester
                      .widget<ImagePreviewCenterLoadingIndicator>(loading)
                      .progress,
                  1,
                  reason:
                      'The completed sector must never reset to an empty ring');
              expect(tester.element(loading), same(indicator));
            }
          }
          expect(find.byType(ImagePreviewCenterLoadingIndicator), findsNothing);
          expect(find.byType(GesturedImage), findsOneWidget);
          expect(cache.requests, 1);
          expect(intermediate.loads, 0);
          await tester.pumpWidget(const SizedBox.shrink());
          FlutterError.onError = errorHandler;
        }
        expect(tester.takeException(), isNull);
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
    }
  }
}
