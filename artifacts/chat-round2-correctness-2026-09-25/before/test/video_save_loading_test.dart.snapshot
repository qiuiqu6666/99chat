import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tuikit_info_toast.dart';

void main() {
  const galleryChannel = MethodChannel('image_gallery_saver_plus');
  late Directory directory;
  late File file;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    directory = await Directory.systemTemp.createTemp('video-save-test-');
    file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes([1, 2, 3]);
  });
  tearDownAll(() async => directory.delete(recursive: true));

  for (final success in [true, false]) {
    testWidgets(
        'video save shows loading before ${success ? 'success' : 'failure'} notice',
        (tester) async {
      final galleryResult = Completer<Map<String, dynamic>>();
      final notices = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        galleryChannel,
        (call) {
          expect(call.method, 'saveFileToGallery');
          expect((call.arguments as Map)['file'], file.path);
          return galleryResult.future;
        },
      );
      TUIKitInfoToast.presenter = notices.add;
      addTearDown(() async {
        TUIKitInfoToast.presenter = null;
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(galleryChannel, null);
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(saveNetworkVideoFile(
                context,
                model: TUIChatGlobalModel(),
                message: V2TimMessage.fromJson({
                  'message_server_time': 1,
                  'message_risk_type_identified': 0,
                }),
                videoUrl: file.path,
              )),
              child: const Text('save'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('save'));
      await tester.pump();
      expect(find.text('正在保存视频…'), findsOneWidget);
      expect(notices, isEmpty);

      galleryResult.complete({'isSuccess': success});
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('正在保存视频…'), findsOneWidget);
      expect(notices, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('正在保存视频…'), findsNothing);
      expect(notices, contains(success ? '视频已保存' : '保存失败'));
      expect(tester.takeException(), isNull);
    });
  }
}
