import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final mixed in [false, true]) {
    for (final fails in [false, true]) {
      testWidgets(
          '${mixed ? 'mixed' : 'single'} video shows one fan above cover until ${fails ? 'failure' : 'first frame'}',
          (tester) async {
        final errorHandler = FlutterError.onError;
        addTearDown(() => FlutterError.onError = errorHandler);
        final messenger = tester.binding.defaultBinaryMessenger;
        const channel = MethodChannel('better_player_channel');
        final events = <MethodChannel>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'create') {
            final id = events.length;
            final event = MethodChannel('better_player_channel/videoEvents$id');
            events.add(event);
            messenger.setMockMethodCallHandler(event, (_) async => null);
            return {'textureId': id};
          }
          if (call.method == 'position') return 100;
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          for (final event in events) {
            messenger.setMockMethodCallHandler(event, null);
          }
        });

        Future<void> pump([Duration duration = Duration.zero]) async {
          await tester.pump(duration);
          FlutterError.onError = errorHandler;
        }

        final video = V2TimVideoElem(
          videoUrl: 'https://example.invalid/loading.mp4',
          snapshotWidth: 400,
          snapshotHeight: 800,
          duration: 30,
        );
        final message =
            V2TimMessage.fromJson({'message_risk_type_identified': 0})
              ..elemType = 5
              ..videoElem = video;
        await tester.pumpWidget(MaterialApp(
          home: mixed
              ? ChatMediaGalleryScreen(
                  initialIndex: 0,
                  enableHero: false,
                  items: [
                    ChatMediaPreviewItem(
                      message: message,
                      type: ChatMediaPreviewType.video,
                      heroTag: 'video-loading',
                      videoElement: video,
                      resolveVideo: () async => video,
                    ),
                  ],
                )
              : VideoScreen(
                  message: message,
                  heroTag: 'video-loading',
                  videoElement: video,
                  externalVideo: true,
                  preferOnlinePlayback: true,
                ),
        ));
        FlutterError.onError = errorHandler;
        await pump();
        await pump(const Duration(milliseconds: 350));
        await pump();
        expect(events, hasLength(1));
        final fan = find.byType(ImagePreviewCenterLoadingIndicator);
        expect(fan, findsOneWidget);
        expect(
            tester.getCenter(fan), tester.getCenter(find.byType(MaterialApp)));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        final envelope = fails
            ? const StandardMethodCodec().encodeErrorEnvelope(
                code: 'decode_failed', message: 'Video unavailable')
            : const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'initialized',
                'width': 400.0,
                'height': 800.0,
                'duration': 30000,
              });
        await messenger.handlePlatformMessage(
            events.single.name, envelope, (_) {});
        for (var frame = 0; frame < 8; frame++) {
          await pump(const Duration(milliseconds: 100));
        }
        expect(fan, findsNothing);
        if (fails) {
          expect(find.text('视频加载失败'), findsOneWidget);
        } else {
          final player = tester.state<TIMUIKitVideoPlayerState>(
              find.byType(TIMUIKitVideoPlayer));
          expect(player.isPlaybackPipelineReady, isTrue);
          expect(player.isPlaying, isTrue);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
