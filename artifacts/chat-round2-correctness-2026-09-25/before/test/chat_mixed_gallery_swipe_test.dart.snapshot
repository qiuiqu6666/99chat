import 'dart:async';
import 'dart:ui' as ui;

import 'package:awesome_video_player/src/configuration/better_player_buffering_configuration.dart';
import 'package:awesome_video_player/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';

class _Image extends ImageProvider<_Image> {
  const _Image(this.image);
  final ui.Image image;
  @override
  Future<_Image> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(_Image key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

class _VideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final sources = <int, String?>{};
  final playing = <int>{};
  final paused = <int>[];
  final disposed = <int>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(
      {BetterPlayerBufferingConfiguration? bufferingConfiguration}) async {
    final id = streams.length + 1;
    streams[id] =
        StreamController<VideoEvent>(onCancel: () => Future<void>.value());
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) =>
      streams[textureId]!.stream;
  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    sources[textureId!] = dataSource.uri;
    streams[textureId]!.add(VideoEvent(
        eventType: VideoEventType.initialized,
        key: dataSource.uri,
        duration: const Duration(seconds: 60),
        size: const Size(100, 100)));
  }

  @override
  Future<void> dispose(int? textureId) async {
    playing.remove(textureId);
    disposed.add(textureId!);
    await streams[textureId]!.close();
  }

  @override
  Future<void> play(int? textureId) async {
    playing.add(textureId!);
  }

  @override
  Future<void> pause(int? textureId) async {
    playing.remove(textureId);
    paused.add(textureId!);
  }

  @override
  Future<void> setLooping(int? textureId, bool looping) async {}
  @override
  Future<void> setVolume(int? textureId, double volume) async {}
  @override
  Future<void> setSpeed(int? textureId, double speed) async {}
  @override
  Future<void> setTrackParameters(
      int? textureId, int? width, int? height, int? bitrate) async {}
  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {}
  @override
  Future<void> seekTo(int? textureId, Duration? position) async {}
  @override
  Future<Duration> getPosition(int? textureId) async =>
      const Duration(seconds: 1);
  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async => null;
  @override
  Widget buildView(int? textureId) => const SizedBox.expand();
}

void main() {
  late _VideoPlatform platform;
  FlutterExceptionHandler? testErrorHandler;
  late VideoPlayerPlatform originalPlatform;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    originalPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform = _VideoPlatform();
  });
  tearDownAll(() => VideoPlayerPlatform.instance = originalPlatform);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      FlutterError.onError = testErrorHandler;
    }
  }

  List<ChatMediaPreviewItem> items(ui.Image bitmap) {
    return [
      for (var i = 0; i < 4; i++)
        if (i == 0 || i == 3)
          ChatMediaPreviewItem(
            message: V2TimMessage.fromJson({
              'message_msg_id': 'image$i',
              'message_risk_type_identified': 0
            })
              ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE
              ..imageElem = V2TimImageElem(
                  imageList: [V2TimImage(type: 0, width: 100, height: 100)]),
            type: ChatMediaPreviewType.image,
            heroTag: 'image$i',
            imageProvider: _Image(bitmap),
            placeholderImageProvider: _Image(bitmap),
          )
        else
          ChatMediaPreviewItem(
            message: V2TimMessage.fromJson({
              'message_msg_id': 'video$i',
              'message_risk_type_identified': 0
            })
              ..elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO
              ..videoElem = V2TimVideoElem(
                  videoUrl: 'https://example.com/video$i.mp4',
                  snapshotWidth: 100,
                  snapshotHeight: 100),
            type: ChatMediaPreviewType.video,
            heroTag: 'video$i',
            videoElement:
                V2TimVideoElem(snapshotWidth: 100, snapshotHeight: 100),
            resolveVideo: () async => V2TimVideoElem(
                videoUrl: 'https://example.com/video$i.mp4',
                snapshotWidth: 100,
                snapshotHeight: 100),
          ),
    ];
  }

  for (final start in [0, 1]) {
    testWidgets('item $start opens the album and releases playback',
        (tester) async {
      final errorHandler = testErrorHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = errorHandler);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = picture.toImageSync(100, 100);
      picture.dispose();
      addTearDown(bitmap.dispose);
      final media = items(bitmap);
      final navigator = GlobalKey<NavigatorState>();
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Chat')),
      ));
      navigator.currentState!.push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => ChatMediaGalleryScreen(
          items: media,
          initialIndex: start,
          sourceMessage: media[start].message,
          enableHero: false,
          onOpenMedia: () {
            opened++;
            navigator.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Conversation album')),
            ));
          },
        ),
      ));
      await settle(tester);
      expect(find.byTooltip('图集'), findsOneWidget);
      await tester.tap(find.byTooltip('图集'));
      await settle(tester);
      expect(opened, 1);
      expect(find.text('Conversation album'), findsOneWidget);
      expect(find.byType(ChatMediaGalleryScreen), findsNothing);
      expect(platform.playing, isEmpty);
      navigator.currentState!.pop();
      await settle(tester);
      expect(find.text('Chat'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'opening item $start can swipe through images and videos in both directions',
        (tester) async {
      final errorHandler = testErrorHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = errorHandler);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.red, BlendMode.src);
      final picture = recorder.endRecording();
      final bitmap = picture.toImageSync(100, 100);
      picture.dispose();
      addTearDown(bitmap.dispose);
      final media = items(bitmap);
      var current = start;
      await tester.pumpWidget(MaterialApp(
          home: ChatMediaGalleryScreen(
        items: media,
        initialIndex: start,
        sourceMessage: media[start].message,
        enableHero: false,
        onGalleryIndexChanged: (index) => current = index,
      )));
      FlutterError.onError = errorHandler;
      await settle(tester);

      void expectPage(int index) {
        expect(current, index);
        if (index == 0 || index == 3) {
          expect(find.byType(TIMUIKitVideoPlayer), findsNothing);
          expect(platform.playing, isEmpty);
        } else {
          expect(find.byType(TIMUIKitVideoPlayer), findsOneWidget);
          expect(
              tester
                  .widget<TIMUIKitVideoPlayer>(find.byType(TIMUIKitVideoPlayer))
                  .message
                  .msgID,
              'video$index');
          expect(platform.playing, hasLength(1));
          expect(platform.sources[platform.playing.single],
              'https://example.com/video$index.mp4');
        }
      }

      expectPage(start);
      for (final next in [for (var i = start + 1; i <= 3; i++) i, 2, 1, 0]) {
        final previousPlayers = Set<int>.of(platform.playing);
        await tester.dragFrom(
            const Offset(400, 300), Offset(next > current ? -650 : 650, 0));
        await settle(tester);
        expectPage(next);
        for (final id in previousPlayers) {
          expect(platform.paused, contains(id));
          expect(platform.disposed, contains(id));
        }
      }
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      expect(platform.playing, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('history expansion keeps the currently playing video',
      (tester) async {
    final errorHandler = testErrorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = errorHandler);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final bitmap = picture.toImageSync(100, 100);
    picture.dispose();
    addTearDown(bitmap.dispose);
    final media = items(bitmap);
    Widget gallery(List<ChatMediaPreviewItem> values, int initialIndex) =>
        MaterialApp(
            home: ChatMediaGalleryScreen(
          items: values,
          initialIndex: initialIndex,
          sourceMessage: media.first.message,
          enableHero: false,
        ));
    await tester.pumpWidget(gallery(media, 0));
    FlutterError.onError = errorHandler;
    await settle(tester);
    for (var i = 0; i < 2; i++) {
      await tester.dragFrom(const Offset(400, 300), const Offset(-650, 0));
      await settle(tester);
    }
    expect(platform.playing, hasLength(1));
    final activePlayer = platform.playing.single;
    expect(platform.sources[activePlayer], 'https://example.com/video2.mp4');
    final older = ChatMediaPreviewItem(
      message: V2TimMessage.fromJson(
          {'message_msg_id': 'older', 'message_risk_type_identified': 0})
        ..elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      type: ChatMediaPreviewType.image,
      heroTag: 'older',
      imageProvider: _Image(bitmap),
    );
    await tester.pumpWidget(gallery([older, ...media], 1));
    await settle(tester);
    expect(find.byType(TIMUIKitVideoPlayer), findsOneWidget);
    expect(
        tester
            .widget<TIMUIKitVideoPlayer>(find.byType(TIMUIKitVideoPlayer))
            .message
            .msgID,
        'video2');
    expect(platform.playing, {activePlayer});
    await tester.dragFrom(const Offset(400, 300), const Offset(-650, 0));
    await settle(tester);
    expect(platform.playing, isEmpty);
    expect(find.byType(TIMUIKitVideoPlayer), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
