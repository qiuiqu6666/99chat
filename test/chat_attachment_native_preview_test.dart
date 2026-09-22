import 'dart:async';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_preview.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';

const video = ChatAttachment(
    attachmentId: 'a',
    referenceId: 'r',
    kind: 'video',
    name: 'original.mp4',
    sizeBytes: 128 * 1024 * 1024,
    durationMs: 80000,
    width: 1080,
    height: 1920,
    mimeType: 'video/mp4');

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  testWidgets(
      'mixed gallery resolves active external video instead of SDK source',
      (tester) async {
    final previousErrorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    final pending = Completer<V2TimVideoElem>();
    var calls = 0;
    Future<V2TimVideoElem> resolve() {
      calls++;
      return pending.future;
    }

    final preview = attachmentVideoPreviewMessage(
        attachment: video, source: const ChatAttachmentPlayback(''));
    await tester.pumpWidget(MaterialApp(
        home: ChatMediaGalleryScreen(
      initialIndex: 0,
      enableHero: false,
      items: [
        ChatMediaPreviewItem(
            message: preview,
            type: ChatMediaPreviewType.video,
            heroTag: 'external-gallery',
            videoElement: preview.videoElem,
            resolveVideo: resolve),
      ],
    )));
    await tester.pump();
    FlutterError.onError = previousErrorHandler;
    final player =
        tester.widget<TIMUIKitVideoPlayer>(find.byType(TIMUIKitVideoPlayer));
    expect(player.externalVideo, isTrue);
    expect(player.resolveVideo, same(resolve));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(V2TimVideoElem());
    await tester.pump();
  });

  test(
      'remote video uses native screen and signed headers without mutating message',
      () {
    final original = V2TimMessage.fromJson(
        {'message_server_time': 1, 'message_risk_type_identified': 0})
      ..elemType = 2;
    const source = ChatAttachmentPlayback(
        'https://storage.example/video?signature=test',
        headers: {'x-storage-token': 'signed-test'});
    final preview = attachmentVideoPreviewMessage(
        attachment: video,
        source: source,
        original: original,
        thumbnail: '/cover.jpg');
    expect(original.elemType, 2);
    expect(original.videoElem, isNull);
    expect(preview.elemType, 5);
    expect(preview.videoElem!.videoUrl, source.location);
    expect(preview.videoElem!.duration, 80);
    expect(preview.videoElem!.snapshotPath, '/cover.jpg');
    final screen = attachmentVideoScreen(
        message: preview, source: source, heroTag: 'a', onSave: () async {});
    expect(screen, isA<VideoScreen>());
    expect(screen.playbackHeaders, source.headers);
    expect(screen.externalVideo, isTrue);
    expect(screen.preferOnlinePlayback, isTrue);
  });
  test('local original stays local in native preview', () {
    final preview = attachmentVideoPreviewMessage(
        attachment: video,
        source: const ChatAttachmentPlayback('/original.mp4', local: true));
    expect(preview.videoElem!.localVideoUrl, '/original.mp4');
    expect(preview.videoElem!.videoPath, '/original.mp4');
    expect(preview.videoElem!.videoUrl, isNull);
    expect(preview.videoElem!.videoSize, 128 * 1024 * 1024);
  });
  test(
      'external path reaches native route and both player engines carry signed headers',
      () {
    final entry = File('lib/src/widgets/chat_attachment_message_card_io.dart')
        .readAsStringSync();
    expect(entry, contains('await pushMediaPreview('));
    expect(entry, contains('child: attachmentVideoScreen('));
    expect(entry, contains('isMessageContextMenuOverlayOpen'));
    expect(entry, contains('saveScrollBeforeMediaPreview'));
    final screen = File(
            'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/video_screen.dart')
        .readAsStringSync();
    expect(
        screen, contains('widget._useGallery ? null : widget.playbackHeaders'));
    expect(screen.replaceAll(RegExp(r'\s+'), ' '),
        contains('_playerItem.resolveVideo != null : widget.externalVideo'));
    final player = File(
            'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart')
        .readAsStringSync();
    expect(
        'widget.playbackHeaders ?? chatMediaNetworkHeaders(resolvedUrl)'
            .allMatches(player),
        hasLength(2));
    expect(player, contains('if (widget.externalVideo) return;'));
    expect(player, contains('if (widget.externalVideo) return false;'));
  });
  testWidgets('external missing source never falls back to SDK download',
      (tester) async {
    final preview = attachmentVideoPreviewMessage(
        attachment: video, source: const ChatAttachmentPlayback(''));
    preview.msgID = 'custom-message-not-an-sdk-video';
    final key = GlobalKey<TIMUIKitVideoPlayerState>();
    await tester.pumpWidget(MaterialApp(
        home: TIMUIKitVideoPlayer(
            key: key,
            message: preview,
            isSending: false,
            externalVideo: true,
            preferOnlinePlayback: true,
            deferInitialization: true)));
    expect(await key.currentState!.getMessageInfo(), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('signed history playback URL bypasses host URL rewriting',
      (tester) async {
    const signed = 'https://storage.example/a%2fb.mp4?signature=unchanged';
    final originalResolver = resolveMediaPreviewNetworkUrl;
    resolveMediaPreviewNetworkUrl = (_) => 'https://rewritten.invalid/';
    addTearDown(() => resolveMediaPreviewNetworkUrl = originalResolver);
    final preview = attachmentVideoPreviewMessage(
        attachment: video, source: const ChatAttachmentPlayback(signed));
    final key = GlobalKey<TIMUIKitVideoPlayerState>();
    await tester.pumpWidget(MaterialApp(
        home: TIMUIKitVideoPlayer(
            key: key,
            message: preview,
            isSending: false,
            externalVideo: true,
            preferOnlinePlayback: true,
            deferInitialization: true)));
    expect((await key.currentState!.getMessageInfo())!.path, signed);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('gallery source loads lazily and failed preparation can retry',
      (tester) async {
    var requests = 0;
    final preview = attachmentVideoPreviewMessage(
        attachment: video, source: const ChatAttachmentPlayback(''));
    final key = GlobalKey<TIMUIKitVideoPlayerState>();
    await tester.pumpWidget(MaterialApp(
        home: TIMUIKitVideoPlayer(
            key: key,
            message: preview,
            isSending: false,
            externalVideo: true,
            preferOnlinePlayback: true,
            deferInitialization: true,
            resolveVideo: () async {
              requests++;
              if (requests == 1) throw StateError('temporary download failure');
              return V2TimVideoElem(
                  videoUrl: 'https://storage.example/ready.mp4');
            })));
    expect(requests, 0);
    await expectLater(key.currentState!.getMessageInfo(), throwsStateError);
    expect((await key.currentState!.getMessageInfo())!.path,
        'https://storage.example/ready.mp4');
    expect((await key.currentState!.getMessageInfo())!.path,
        'https://storage.example/ready.mp4');
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
