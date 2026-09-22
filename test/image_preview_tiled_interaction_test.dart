import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the gallery owned by UIKit, which declares extended_image.
// ignore: depend_on_referenced_packages
import 'package:extended_image/extended_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tiled_image_preview.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  Future<void> mount(WidgetTester tester, int w, int h) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('region_grid_');
    final file = File('${dir.path}/original')..createSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    addTearDown(ImageRegionDecodeHook.resetForTest);
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..imageElem = V2TimImageElem(imageList: [
        V2TimImage(type: 0, localUrl: file.path, width: w, height: h)
      ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TiledImagePreview(
                imageWidth: w, imageHeight: h, message: message))));
    await tester.pump();
  }

  ui.Image pixel() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    picture.dispose();
    return image;
  }

  testWidgets('double tap visually zooms wide tiles and horizontal pan works',
      (tester) async {
    ImageRegionDecodeHook.decode = (_) async => pixel();
    await mount(tester, 30000, 1000);
    await tester.pumpAndSettle();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), 1);
    final before = tester.getRect(find.byType(RawImage).first);
    await tester.tapAt(const Offset(195, 422));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(195, 422));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    final after = tester.getRect(find.byType(RawImage).first);
    expect(after.height, greaterThan(before.height));
    final x = controller.value.getTranslation().x;
    await tester.drag(find.byType(InteractiveViewer), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(controller.value.getTranslation().x, lessThan(x));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'pending decodes stay bounded across zoom and dispose drops stale results',
      (tester) async {
    final requests = <ImageRegionDecodeRequest>[];
    final pending = <Completer<ui.Image?>>[];
    ImageRegionDecodeHook.decode = (r) {
      requests.add(r);
      final future = Completer<ui.Image?>();
      pending.add(future);
      return future.future;
    };
    await mount(tester, 8000, 100000);
    expect(pending.length, 2);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(4, 4, 1, 1);
    await tester.pump();
    await tester.pump();
    expect(pending.length, 2);
    pending[0].complete(pixel());
    pending[1].complete(pixel());
    await tester.pump();
    await tester.pump();
    expect(pending.length, 4);
    for (final request in requests) {
      expect(
          request.dstWidth * request.dstHeight, lessThanOrEqualTo(512 * 512));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final future in pending) {
      if (!future.isCompleted) future.complete(pixel());
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotation and desktop resize preserve the reading center',
      (tester) async {
    ImageRegionDecodeHook.decode = (_) async => pixel();
    await mount(tester, 1080, 12000);
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.identity()..translateByDouble(0, -2000, 0, 1);
    await tester.pumpAndSettle();
    final fraction =
        (844 / 2 - controller.value.getTranslation().y) / (390 * 12000 / 1080);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(
        (390 / 2 - controller.value.getTranslation().y) / (390 * 12000 / 1080),
        closeTo(fraction, 0.001));
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(controller.value.getTranslation().x, closeTo(600, 0.01));
    expect(
        (1080 / 2 - controller.value.getTranslation().y) / (720 * 12000 / 1080),
        closeTo(fraction, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('horizontal drag at the edge advances the surrounding gallery',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ExtendedPageController();
    var page = 0;
    await tester.pumpWidget(MaterialApp(
        home: ExtendedImageGesturePageView.builder(
      controller: controller,
      itemCount: 2,
      onPageChanged: (value) => page = value,
      itemBuilder: (context, index) => index == 0
          ? const TiledImagePreview(
              imageWidth: 1080, imageHeight: 100000, inPageView: true)
          : const ColoredBox(color: Colors.blue),
    )));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TiledImagePreview), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(page, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
