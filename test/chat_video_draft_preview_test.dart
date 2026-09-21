import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_video_draft_preview.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  bool initialize = true;
  bool failPlayback = false;
  bool stalled = false;
  Completer<int?>? creationGate;
  final streams = <int, StreamController<VideoEvent>>{};
  final views = <VideoViewType>[];
  final disposed = <int>[];
  int plays = 0;
  int pauses = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    views.add(options.viewType);
    final id = views.length;
    streams[id] = StreamController<VideoEvent>(onCancel: () => Future<void>.value());
    if (creationGate != null) return await creationGate!.future;
    return id;
  }
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (initialize) {
      streams[playerId]!.add(VideoEvent(eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 55), size: const Size(720, 1280)));
    }
    return streams[playerId]!.stream;
  }
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
    if (failPlayback) throw StateError('native playback failed');
  }
  @override
  Future<void> pause(int playerId) async { pauses++; }
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      stalled ? Duration.zero : const Duration(seconds: 1);
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}

void main() {
  late _VideoPlatform platform;
  setUp(() {
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  void testIos(String description, WidgetTesterCallback body) =>
      testWidgets(description, body,
          variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  Future<void> open(WidgetTester tester, ValueChanged<(String, int)> result) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(onPressed: () async {
        final value = await Navigator.of(context).push<(String, int)>(
          MaterialPageRoute(builder: (context) => ChatVideoDraftPreview(
            filePath: '/recorded.mov', sizeText: '13.3MB', durationSeconds: 0,
            canRetake: true,
            onCancel: () => Navigator.of(context).pop(('cancel', 0)),
            onRetake: () => Navigator.of(context).pop(('retake', 0)),
            onSend: (seconds) => Navigator.of(context).pop(('send', seconds)),
          )));
        if (value != null) result(value);
      }, child: const Text('open'));
    })));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  for (final action in ['close', 'retake', 'send']) {
    testIos('$action remains usable while initialization never completes', (tester) async {
      platform.initialize = false;
      (String, int)? result;
      await open(tester, (value) => result = value);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('video-preview-$action')));
      await tester.pumpAndSettle();
      expect(result?.$1, action == 'close' ? 'cancel' : action);
      expect(platform.disposed, [1]);
      expect(platform.plays, 0);
      await tester.pump(const Duration(seconds: 9));
      expect(platform.views, [VideoViewType.platformView]);
      expect(tester.takeException(), isNull);
    });
  }

  testIos('timeout shows fallback without retrying native player creation', (tester) async {
    platform.initialize = false;
    (String, int)? result;
    await open(tester, (value) => result = value);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(platform.disposed, [1]);
    expect(platform.views, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('video-preview-retake')));
    await tester.pumpAndSettle();
    expect(result?.$1, 'retake');
    expect(tester.takeException(), isNull);
  });

  testIos('late native creation after closing is disposed without playback', (tester) async {
    platform.creationGate = Completer<int?>();
    await open(tester, (_) {});
    await tester.tap(find.byKey(const ValueKey('video-preview-close')));
    await tester.pumpAndSettle();
    platform.creationGate!.complete(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(platform.disposed, [1]);
    expect(platform.plays, 0);
    expect(platform.views, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testIos('one iOS native view plays and send returns its duration', (tester) async {
    (String, int)? result;
    await open(tester, (value) => result = value);
    expect(platform.views, [VideoViewType.platformView]);
    expect(platform.plays, 1);
    expect(find.text('00:55  13.3MB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-preview-send')));
    await tester.pumpAndSettle();
    expect(result, ('send', 55));
    expect(platform.disposed, [1]);
    expect(tester.takeException(), isNull);
  });

  testIos('playback error falls back and close still works', (tester) async {
    platform.failPlayback = true;
    (String, int)? result;
    await open(tester, (value) => result = value);
    await tester.pump();
    expect(platform.disposed, [1]);
    await tester.tap(find.byKey(const ValueKey('video-preview-close')));
    await tester.pumpAndSettle();
    expect(result?.$1, 'cancel');
    expect(platform.views, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testIos('backgrounding does not restart paused video', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await open(tester, (_) {});
    final plays = platform.plays;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(platform.plays, plays);
    expect(platform.pauses, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.plays, greaterThan(plays));
    await tester.tap(find.byKey(const ValueKey('video-preview-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testIos('native error after initialization releases the player and allows send', (tester) async {
    (String, int)? result;
    await open(tester, (value) => result = value);
    platform.streams[1]!.addError(PlatformException(
        code: 'decode_failed', message: 'Video decoder failed'));
    await tester.pump();
    await tester.pump();
    expect(platform.disposed, [1]);
    await tester.tap(find.byKey(const ValueKey('video-preview-send')));
    await tester.pumpAndSettle();
    expect(result, ('send', 55));
    expect(tester.takeException(), isNull);
  });

  testIos('initialized but stalled playback becomes a usable fallback', (tester) async {
    platform.stalled = true;
    await open(tester, (_) {});
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(platform.disposed, [1]);
    expect(platform.views, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('video-preview-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
