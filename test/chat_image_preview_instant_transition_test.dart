import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  const _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _TestImageProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final mixedGallery in [false, true]) {
    for (final closeMode in ['back', 'slide']) {
      testWidgets(
        '${mixedGallery ? 'mixed gallery' : 'image'} opens instantly and $closeMode closes correctly',
        (tester) async {
          final errorHandler = FlutterError.onError;
          addTearDown(() => FlutterError.onError = errorHandler);
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.red, BlendMode.src);
          final picture = recorder.endRecording();
          final bitmap = picture.toImageSync(100, 100);
          picture.dispose();
          addTearDown(bitmap.dispose);
          final provider = _TestImageProvider(bitmap);
          final message =
              V2TimMessage.fromJson({'message_risk_type_identified': 0})
                ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
                ..imageElem = V2TimImageElem(
                    imageList: [V2TimImage(type: 0, width: 100, height: 100)]);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('chat page')),
          ));

          navigator.currentState!.push(MediaPreviewOverlayRoute<void>(
            enableGestureBack: false,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, animation, __) => MediaPreviewChromeScope(
              animation: const AlwaysStoppedAnimation<double>(1),
              child: mixedGallery
                  ? ChatMediaGalleryScreen(
                      items: [
                        ChatMediaPreviewItem(
                          message: message,
                          type: ChatMediaPreviewType.image,
                          heroTag: 'instant-image',
                          imageProvider: provider,
                          placeholderImageProvider: provider,
                        ),
                      ],
                      initialIndex: 0,
                      sourceMessage: message,
                      enableHero: false,
                    )
                  : ImageScreen(
                      imageProvider: provider,
                      placeholderImageProvider: provider,
                      heroTag: 'instant-image',
                      sourceMessage: message,
                      enableHero: false,
                    ),
            ),
          ));
          await tester.pump();
          FlutterError.onError = errorHandler;
          expect(navigator.currentState!.canPop(), isTrue);
          expect(
              find.byType(mixedGallery ? ChatMediaGalleryScreen : ImageScreen),
              findsOneWidget);

          if (closeMode == 'back') {
            await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
            await tester.pump();
            FlutterError.onError = errorHandler;
          } else {
            final gesture = await tester.startGesture(const Offset(400, 300));
            await gesture.moveBy(const Offset(0, 20));
            await tester.pump();
            FlutterError.onError = errorHandler;
            await gesture.moveBy(const Offset(0, 150));
            await tester.pump();
            FlutterError.onError = errorHandler;
            await gesture.up();
            await tester.pump();
            FlutterError.onError = errorHandler;
            expect(
                find.byType(
                    mixedGallery ? ChatMediaGalleryScreen : ImageScreen),
                findsOneWidget,
                reason:
                    'Slide dismissal should continue from the drag, not cut away');
            await tester.pump(const Duration(milliseconds: 220));
            FlutterError.onError = errorHandler;
          }
          expect(find.text('chat page'), findsOneWidget);
          expect(
              find.byType(mixedGallery ? ChatMediaGalleryScreen : ImageScreen),
              findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(milliseconds: 340));
        },
      );
    }
  }
}
