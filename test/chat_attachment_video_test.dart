import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/chat_attachment_api.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_store.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_card.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_message_card_io.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_delta.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_identity.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_writer.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

const video = ChatAttachment(
    attachmentId: 'video',
    referenceId: 'ref',
    kind: 'video',
    name: 'source.mp4',
    sizeBytes: 10,
    mimeType: 'video/mp4',
    durationMs: 65000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets(
      'large video without cover retains play and duration, no file icon',
      (tester) async {
    var plays = 0;
    final screenshot = Platform.environment['VIDEO_QA_SCREENSHOT'] == '1';
    if (screenshot) {
      await tester.runAsync(() async {
        final loader = FontLoader('video-qa')
          ..addFont(Future.value(ByteData.sublistView(
              await File('assets/fonts/NotoSansSC-Regular.ttf')
                  .readAsBytes())));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
    }
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: screenshot ? 'video-qa' : null),
        home: Scaffold(
            body: RepaintBoundary(
                key: const ValueKey('video-qa'),
                child: ChatAttachmentVideoCard(
                    sizeBytes: 127611699,
                    durationMs: 65000,
                    onOpen: () => plays++)))));
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('121.7 MiB'), findsNothing);
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'images/play.png'),
        findsOneWidget);
    expect(find.byIcon(Icons.video_file_outlined), findsNothing);
    expect(find.text('source.mp4'), findsNothing);
    await tester.runAsync(() => precacheImage(
        const AssetImage('images/play.png',
            package: 'tencent_cloud_chat_uikit'),
        tester.element(find.byType(ChatAttachmentVideoCard))));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(AspectRatio)));
    expect(plays, 1);
    // A tap on the cover, outside the center button, also plays the video.
    await tester.tapAt(
        tester.getTopLeft(find.byType(AspectRatio)) + const Offset(12, 12));
    expect(plays, 2);
    if (screenshot) {
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('video-qa')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${Directory.systemTemp.path}/99chat-video-bubble.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('delivered custom video uses the video component',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ChatAttachmentMessageCard(attachment: video))));
    await tester.pump();
    expect(find.byType(ChatAttachmentVideoCard), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.video_file_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('broken cover still offers video playback and no layout error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatAttachmentVideoCard(
                sizeBytes: 127611699,
                durationMs: 65000,
                onOpen: () {},
                thumbnail: FileImage(File('/missing-video-cover.jpg'))))));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'images/play.png'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait dimensions and unknown duration remain usable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatAttachmentVideoCard(
                sizeBytes: 10,
                videoWidth: 1080,
                videoHeight: 1920,
                onOpen: () {}))));
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        9 / 16);
    expect(find.text('视频'), findsOneWidget);
  });

  testWidgets(
      'upload has only in-card loading, no percentage or external actions',
      (tester) async {
    var pauses = 0, cancels = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatAttachmentVideoCard(
                sizeBytes: 10,
                durationMs: 123000,
                busy: true,
                progress: .5,
                uploadStatus: '上传 50%',
                onOpen: () {},
                onPause: () => pauses++,
                onCancel: () => cancels++))));
    expect(find.text('2:03'), findsOneWidget);
    expect(find.text('上传 50%'), findsNothing);
    expect(find.text('取消发送'), findsNothing);
    expect(find.text('下载视频'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        .5);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(AspectRatio)));
    expect(pauses, 1);
    expect(cancels, 0);
  });

  testWidgets('unknown send result cannot trigger a second send',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ChatAttachmentVideoCard(
                sizeBytes: 10,
                busy: true,
                indeterminate: true,
                onOpen: null,
                uploadStatus: '发送结果待确认，请勿重复发送'))));
    final gesture =
        tester.widget<GestureDetector>(find.byType(GestureDetector).first);
    expect(gesture.onTap, isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.text('取消发送'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paused upload preserves progress and offers resume',
      (tester) async {
    var resumes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ChatAttachmentVideoCard(
        sizeBytes: 10,
        paused: true,
        progress: .65,
        indeterminate: true,
        onOpen: () => resumes++,
      )),
    ));
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        .65);
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    await tester.tapAt(tester.getCenter(find.byType(AspectRatio)));
    expect(resumes, 1);
  });

  group('account-scoped video posters', () {
    late Directory dir;
    late ChatAttachmentStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('video-cover-test-');
      store = ChatAttachmentStore(rootProvider: () async => dir);
    });
    tearDown(() => dir.delete(recursive: true));
    Future<void> original() async {
      final file =
          await store.downloadFile('alice', video.attachmentId, 'original.mp4');
      await file.writeAsBytes(List.filled(10, 7));
      await store.registerLocal('alice', video.attachmentId, file,
          expectedSize: 10);
    }

    test('cached sender cover is used without a cloud thumbnail ID', () async {
      final cover = await store.downloadFile('alice', 'video', 'cover.jpg',
          variant: 'thumbnail');
      await cover.writeAsBytes([1, 2, 3]);
      await store.registerLocal('alice', 'video', cover,
          expectedSize: 3, variant: 'thumbnail');
      final service = ChatAttachmentService(
          api: _NoVideoCoverApi(),
          store: store,
          ownerProvider: () => 'alice',
          generationProvider: () => 1,
          thumbnailBuilder: (_) => throw StateError('must not extract'));
      expect(await service.videoThumbnail(video), cover.path);
      service.dispose();
    });

    test('local extraction coalesces and caches without modifying the video',
        () async {
      await original();
      final gate = Completer<String?>();
      var builds = 0;
      final service = ChatAttachmentService(
          api: _NoVideoCoverApi(),
          store: store,
          ownerProvider: () => 'alice',
          generationProvider: () => 1,
          thumbnailBuilder: (_) {
            builds++;
            return gate.future;
          });
      final first = service.videoThumbnail(video);
      final second = service.videoThumbnail(video);
      final cover =
          await File('${dir.path}/generated.jpg').writeAsBytes([1, 2, 3]);
      gate.complete(cover.path);
      expect(await first, await second);
      expect(await service.videoThumbnail(video), await first);
      expect(builds, 1);
      final originalFile =
          await store.localFile('alice', 'video', expectedSize: 10);
      expect(await originalFile!.readAsBytes(), List.filled(10, 7));
      service.dispose();
    });

    test('missing original never downloads a video for a poster', () async {
      var builds = 0;
      final service = ChatAttachmentService(
          api: _NoVideoCoverApi(),
          store: store,
          ownerProvider: () => 'alice',
          generationProvider: () => 1,
          thumbnailBuilder: (_) async {
            builds++;
            return null;
          });
      expect(await service.videoThumbnail(video), isNull);
      expect(builds, 0);
      service.dispose();
    });

    test('late extraction after account switch cannot publish a cover',
        () async {
      await original();
      var owner = 'alice', generation = 1;
      final gate = Completer<String?>();
      final started = Completer<void>();
      final service = ChatAttachmentService(
          api: _NoVideoCoverApi(),
          store: store,
          ownerProvider: () => owner,
          generationProvider: () => generation,
          thumbnailBuilder: (_) {
            started.complete();
            return gate.future;
          });
      final pending = service.videoThumbnail(video);
      final check =
          expectLater(pending, throwsA(isA<ChatAttachmentException>()));
      await started.future;
      owner = 'bob';
      generation++;
      final cover =
          await File('${dir.path}/generated.jpg').writeAsBytes([1, 2, 3]);
      gate.complete(cover.path);
      await check;
      expect(
          await store.localFile('bob', 'video', variant: 'thumbnail'), isNull);
      service.dispose();
    });
  });

  test('retired native placeholder stays removed when stale history completes',
      () {
    final writer = MessageReconciliationWriter<String>(
        comparator: (a, b) => a.value.compareTo(b.value));
    const local = MessageReconciliationRecord(
        value: 'placeholder', localID: 'local-1', outgoingStableID: 'local-1');
    const other = MessageReconciliationRecord(
        value: 'other', localID: 'local-2', outgoingStableID: 'local-2');
    const sent = MessageReconciliationRecord(value: 'sent', msgID: 'local-1');
    writer.seedAuthoritative(
        conversationID: 'c2c_peer', records: [local, other, sent]);
    final request = writer.beginInitialHistory(
        conversationID: 'c2c_peer',
        requestedSource: MessageReconciliationSource.cloud,
        networkState: MessageReconciliationNetworkState.online);
    writer.applyDelta(MessageDelta<String>(
        conversationKey: 'c2c_peer',
        eventID: 'retire',
        kind: MessageDeltaKind.delete,
        source: MessageDeltaSource.sendPipeline,
        generation: request.generation,
        clearEpoch: 0,
        localDeletes: {'local-1'}));
    expect(writer.valuesFor('c2c_peer'), ['other', 'sent']);
    writer.completeHistory(
        request: request,
        history: [local, other, sent],
        actualSource: MessageReconciliationSource.cloud,
        networkState: MessageReconciliationNetworkState.online);
    expect(writer.valuesFor('c2c_peer'), ['other', 'sent']);
  });

  test('production handoff removes only the selected local video', () async {
    final global = serviceLocator<TUIChatGlobalModel>();
    final sender = TUIChatSeparateViewModel();
    const conv = 'c2c_video-handoff';
    global.configureMessageWriterScope(
        ownerUserID: 'video-owner', accountGeneration: 1, domainGeneration: 1);
    V2TimMessage placeholder(String id) => V2TimMessage.fromJson({
          'message_server_time': 1700000000,
          'message_risk_type_identified': 0,
        })
          ..id = id
          ..isSelf = true
          ..elemType = 5
          ..videoElem = V2TimVideoElem(videoPath: '/local.mp4')
          ..status = 1;
    final first = placeholder('video-old'), other = placeholder('video-other');
    global.setMessageList(conv, [first, other], replace: true);
    sender.retireBackendVideoPlaceholder(convID: conv, clientId: 'video-old');
    expect(global.rawMessageList(conv)!.map((m) => m.id), ['video-other']);
    global.setMessageList(conv, [first, other], replace: true);
    expect(global.rawMessageList(conv)!.map((m) => m.id), ['video-other']);
    sender.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
}

class _NoVideoCoverApi extends ChatAttachmentApi {
  @override
  Future<Map<String, dynamic>> access(ChatAttachment attachment, String purpose,
          {CancelToken? cancelToken}) async =>
      throw const ChatAttachmentException('THUMBNAIL_MISSING', 'no cover');
}
