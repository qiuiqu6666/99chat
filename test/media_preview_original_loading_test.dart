import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/gestured_image.dart';

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

class _OriginalDownload extends Fake implements MessageService {
  var pending = Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>();
  int calls = 0;
  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl({
    required String msgID,
    bool reportError = true,
  }) {
    calls++;
    return pending.future;
  }

  @override
  Future<V2TimCallback> downloadMessage({
    required String msgID,
    required int messageType,
    required int imageType,
    required bool isSnapshot,
    V2TimMessage? message,
    void Function(V2TimMessage)? onDownloadFinished,
    bool reportError = true,
  }) async =>
      V2TimCallback(code: -1, desc: 'original unavailable');
}

void main() {
  final download = _OriginalDownload();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(download);
  });
  for (final mixed in [false, true]) {
    testWidgets(
        '${mixed ? 'mixed' : 'single'} original download keeps thumbnail and clears fan after failure',
        (tester) async {
      download.pending = Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>();
      download.calls = 0;
      final errorHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = errorHandler);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = picture.toImageSync(400, 400);
      picture.dispose();
      addTearDown(bitmap.dispose);
      final thumbnail = _Thumbnail(bitmap);
      final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
        ..msgID = 'pending-original-${mixed ? 'mixed' : 'single'}'
        ..elemType = 3
        ..imageElem = V2TimImageElem(
            imageList: [V2TimImage(type: 0, width: 400, height: 400)]);
      await tester.pumpWidget(MaterialApp(
          home: mixed
              ? ChatMediaGalleryScreen(
                  initialIndex: 0,
                  enableHero: false,
                  items: [
                      ChatMediaPreviewItem(
                          message: message,
                          type: ChatMediaPreviewType.image,
                          heroTag: 'pending-original',
                          imageProvider: thumbnail,
                          placeholderImageProvider: thumbnail),
                    ])
              : ImageScreen(
                  imageProvider: thumbnail,
                  placeholderImageProvider: thumbnail,
                  heroTag: 'pending-original',
                  sourceMessage: message,
                  enableHero: false)));
      FlutterError.onError = errorHandler;
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        FlutterError.onError = errorHandler;
      }
      expect(download.calls, 1);
      expect(find.byType(ImagePreviewCenterLoadingIndicator), findsOneWidget);
      expect(find.byType(GesturedImage), findsOneWidget);
      download.pending
          .complete(V2TimValueCallback(code: -1, desc: 'unavailable'));
      await tester.pump();
      FlutterError.onError = errorHandler;
      await tester.pump();
      FlutterError.onError = errorHandler;
      expect(find.byType(ImagePreviewCenterLoadingIndicator), findsNothing);
      expect(find.byType(GesturedImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = errorHandler;
      expect(tester.takeException(), isNull);
    });
  }
}
