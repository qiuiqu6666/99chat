import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tiled_image_preview.dart';

class _Bitmap extends ImageProvider<_Bitmap> {
  const _Bitmap(this.image);
  final ui.Image image;
  @override
  Future<_Bitmap> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Bitmap key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  for (final failure in ['null', 'throw', 'missing']) {
    testWidgets('tile decoder $failure keeps long fallback interactive',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('tile_fallback_');
      final file = File('${directory.path}/original')..createSync();
      addTearDown(() => directory.deleteSync(recursive: true));
      final previous = ImageRegionDecodeHook.decode;
      addTearDown(() => ImageRegionDecodeHook.decode = previous);
      ImageRegionDecodeHook.decode = failure == 'missing'
          ? null
          : (_) async {
              if (failure == 'throw') throw StateError('decode failed');
              return null;
            };
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = picture.toImageSync(200, 2400);
      picture.dispose();
      addTearDown(bitmap.dispose);
      final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
        ..imageElem = V2TimImageElem(imageList: [
          V2TimImage(type: 0, localUrl: file.path, width: 2000, height: 24000),
        ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TiledImagePreview(
        imageWidth: 2000,
        imageHeight: 24000,
        message: message,
        placeholder: _Bitmap(bitmap),
      ))));
      await tester.pumpAndSettle();
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      await tester.dragFrom(const Offset(200, 600), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
          viewer.transformationController!.value.storage[13], lessThan(-100));
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 2);
      tester.view.physicalSize = const Size(1920,1080);
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(find.byType(Image)).width,720);
      expect(tester.takeException(), isNull);
    });
  }
  for (final height in [400, 4800]) {
    testWidgets('failed preview $height supports pinch and pan',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = picture.toImageSync(400, height);
      picture.dispose();
      addTearDown(bitmap.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ImagePreviewLoadingLayer(
                  placeholder: _Bitmap(bitmap),
                  showSpinner: false,
                  interactive: true))));
      await tester.pumpAndSettle();
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final controller = viewer.transformationController!;
      if (height > 800) {
        await tester.dragFrom(const Offset(200, 600), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(controller.value.storage[13], lessThan(-100));
      }
      final first =
          await tester.startGesture(const Offset(150, 400), pointer: 1);
      final second =
          await tester.startGesture(const Offset(250, 400), pointer: 2);
      await tester.pump();
      await first.moveTo(const Offset(100, 400));
      await second.moveTo(const Offset(300, 400));
      await tester.pump();
      await first.moveTo(const Offset(70, 400));
      await second.moveTo(const Offset(330, 400));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.2));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final before = controller.value.storage[13];
      await tester.dragFrom(const Offset(200, 500), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(controller.value.storage[13], lessThan(before));
      expect(tester.takeException(), isNull);
    });
  }
}
