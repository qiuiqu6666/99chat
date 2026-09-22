import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tiled_image_preview.dart';

class _Downloads extends Fake implements MessageService {
  _Downloads(this.path);
  final String path;
  int downloads = 0;
  V2TimMessage? received;

  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl({
    required String msgID,
    bool reportError = true,
  }) async =>
      throw StateError('URL refresh unavailable');

  @override
  Future<V2TimCallback> downloadMessage({
    required String msgID,
    required int messageType,
    required int imageType,
    required bool isSnapshot,
    V2TimMessage? message,
    void Function(V2TimMessage)? onDownloadFinished,
    bool reportError = true,
  }) async {
    downloads++;
    received = message;
    message?.imageElem?.imageList?.first?.localUrl = path;
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

void main() {
  testWidgets('remote long image downloads despite URL and renders local tiles',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('tile_download_');
    final file = File('${directory.path}/original')..createSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final service = _Downloads(file.path);
    serviceLocator.registerSingleton<MessageService>(service);
    addTearDown(() => serviceLocator.unregister<MessageService>());
    addTearDown(ImageRegionDecodeHook.resetForTest);
    final paths = <String>[];
    ImageRegionDecodeHook.decode = (request) async {
      paths.add(request.path);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(1, 1);
      picture.dispose();
      return image;
    };
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..msgID = 'remote-long-image'
      ..imageElem = V2TimImageElem(imageList: [
        V2TimImage(
            type: 0,
            url: 'https://example.com/long.jpg',
            width: 1080,
            height: 100000),
      ]);
    await tester.pumpWidget(MaterialApp(
        home: TiledImagePreview(
      imageWidth: 1080,
      imageHeight: 100000,
      message: message,
    )));
    await tester.pumpAndSettle();
    expect(service.downloads, 1);
    expect(service.received, same(message));
    expect(paths, isNotEmpty);
    expect(paths.every((path) => path == file.path), isTrue);
    expect(find.byType(RawImage), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
