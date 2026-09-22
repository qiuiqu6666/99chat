import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_chrome.dart';

class _Controller extends ChangeNotifier {
  _Controller get value => this;
  bool get isInitialized => true;
  Duration get duration => const Duration(seconds: 138);
  Duration get position => const Duration(seconds: 32);
  Completer<void>? pauseGate;
  Future<void> pause() async => pauseGate?.future;
}

class _Player extends TIMUIKitVideoPlayer {
  _Player({required super.key})
      : super(
          message: V2TimMessage.fromJson({
            'message_server_time': 1,
            'message_risk_type_identified': 0,
          }),
          isSending: false,
          deferInitialization: true,
        );

  @override
  _PlayerState createState() => _PlayerState();
}

class _PlayerState extends TIMUIKitVideoPlayerState {
  final controller = _Controller();
  Completer<void>? seekGate;
  Duration? sought;
  int starts = 0;
  @override
  dynamic get playbackController => controller;
  @override
  Future<void> seekPlaybackTo(Duration position) async {
    sought = position;
    await seekGate?.future;
  }

  @override
  Future<void> startDeferredPlayback() async {
    starts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    final fontRoot = Platform.environment['VIDEO_PREVIEW_FONT_ROOT'];
    if (fontRoot != null) {
      for (final font in {
        'Roboto': 'roboto-regular.ttf',
        'MaterialIcons': 'materialicons-regular.otf',
        'CupertinoSystemText': 'roboto-regular.ttf',
        'CupertinoSystemDisplay': 'roboto-regular.ttf',
      }.entries) {
        final cjkFont = Platform.environment['VIDEO_PREVIEW_CJK_FONT'];
        final path = font.key.startsWith('Cupertino') && cjkFont != null
            ? cjkFont
            : '$fontRoot/${font.value}';
        await (FontLoader(font.key)
              ..addFont(File(path)
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes))))
            .load();
      }
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    required GlobalKey<TIMUIKitVideoPlayerState> playerKey,
    required GlobalKey<MediaPreviewVideoChromeState> chromeKey,
    bool playing = true,
    bool active = true,
    bool ready = true,
    VoidCallback? onToggle,
    Future<void> Function()? onMore,
    EdgeInsets insets = EdgeInsets.zero,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    GlobalKey? captureKey,
  }) async {
    await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('video-preview-root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto', brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: insets,
              viewPadding: insets,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: tester.view.physicalSize / tester.view.devicePixelRatio,
              viewPadding: insets,
              padding: insets,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Material(
              color: Colors.black,
              child: RepaintBoundary(
                key: captureKey,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => chromeKey.currentState?.toggleControls(),
                        child: const Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ColoredBox(color: Color(0xFF243738)),
                          ),
                        ),
                      ),
                    ),
                    _Player(key: playerKey),
                    Positioned.fill(
                      child: MediaPreviewVideoChrome(
                        key: chromeKey,
                        playerKey: playerKey,
                        title: 'Family group',
                        subtitle: 'Today 12:30',
                        galleryIndicator: '3 / 8',
                        isPlaying: playing,
                        isReady: ready,
                        active: active,
                        onBack: () {},
                        onTogglePlayback: onToggle ?? () {},
                        onMore: onMore ?? () async {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )));
    await tester.pump(const Duration(milliseconds: 300));
  }

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('video-controls-fade')))
      .opacity;

  testWidgets('canvas toggles controls without interrupting playback',
      (tester) async {
    final player = GlobalKey<TIMUIKitVideoPlayerState>();
    final chrome = GlobalKey<MediaPreviewVideoChromeState>();
    var toggles = 0;
    await mount(tester,
        playerKey: player, chromeKey: chrome, onToggle: () => toggles++);
    final instance = player.currentState;
    await tester.tapAt(const Offset(400, 250));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(toggles, 0);
    await tester.tapAt(const Offset(400, 250));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(identical(player.currentState, instance), isTrue);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(toggles, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto hides playing controls but keeps pause and loading visible',
      (tester) async {
    final player = GlobalKey<TIMUIKitVideoPlayerState>();
    final chrome = GlobalKey<MediaPreviewVideoChromeState>();
    await mount(tester, playerKey: player, chromeKey: chrome);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(tester), 0);
    await mount(tester, playerKey: player, chromeKey: chrome, playing: false);
    await tester.pump(const Duration(seconds: 10));
    expect(opacity(tester), 1);
    expect(find.byKey(const ValueKey('video-center-play')), findsOneWidget);
    await mount(tester, playerKey: player, chromeKey: chrome, ready: false);
    await tester.pump(const Duration(seconds: 10));
    expect(opacity(tester), 1);
    expect(find.byKey(const ValueKey('video-center-play')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu suspends hide timer and starts a full delay on return',
      (tester) async {
    final player = GlobalKey<TIMUIKitVideoPlayerState>();
    final chrome = GlobalKey<MediaPreviewVideoChromeState>();
    final menu = Completer<void>();
    await mount(tester,
        playerKey: player, chromeKey: chrome, onMore: () => menu.future);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pump(const Duration(seconds: 8));
    expect(opacity(tester), 1);
    menu.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrub holds chrome and waits for pause before seek and resume',
      (tester) async {
    final playerKey = GlobalKey<TIMUIKitVideoPlayerState>();
    final chrome = GlobalKey<MediaPreviewVideoChromeState>();
    await mount(tester, playerKey: playerKey, chromeKey: chrome);
    final player = playerKey.currentState! as _PlayerState;
    player.controller.pauseGate = Completer<void>();
    final slider = find.byType(Slider);
    final start = tester.getCenter(slider);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(seconds: 5));
    expect(opacity(tester), 1);
    await gesture.up();
    await tester.pump();
    expect(player.sought, isNull);
    expect(player.starts, 0);
    player.controller.pauseGate!.complete();
    await tester.pump();
    expect(player.sought, isNotNull);
    expect(player.starts, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending seek cannot restart the old video after paging',
      (tester) async {
    final oldKey = GlobalKey<TIMUIKitVideoPlayerState>();
    final chrome = GlobalKey<MediaPreviewVideoChromeState>();
    await mount(tester, playerKey: oldKey, chromeKey: chrome);
    final oldPlayer = oldKey.currentState! as _PlayerState;
    final seek = Completer<void>();
    oldPlayer.seekGate = seek;
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(0.3);
    slider.onChanged!(0.6);
    slider.onChangeEnd!(0.6);
    await tester.pump();
    expect(oldPlayer.sought, isNotNull);
    final newKey = GlobalKey<TIMUIKitVideoPlayerState>();
    await mount(tester, playerKey: newKey, chromeKey: chrome);
    seek.complete();
    await tester.pump();
    expect(oldPlayer.starts, 0);
    expect((newKey.currentState! as _PlayerState).starts, 0);
    expect(opacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape insets and large text leave every control reachable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(812, 375);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      playing: false,
      textScale: 1.8,
      insets: const EdgeInsets.only(left: 44, right: 44, bottom: 21),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byIcon(Icons.arrow_back_ios_new_rounded)).left,
        greaterThan(44));
    expect(tester.getRect(find.byType(Slider)).bottom, lessThan(354));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'video menu retains save forward speed and confirmed-delete callbacks',
      (tester) async {
    var save = 0;
    var forward = 0;
    var delete = 0;
    double? speed;
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      onMore: () => showMediaPreviewVideoActions(
        context: tester.element(find.byType(MediaPreviewVideoChrome)),
        playbackSpeed: 1,
        onDownload: () async {
          save++;
        },
        onForward: () async {
          forward++;
        },
        onDelete: () async {
          delete++;
        },
        onSpeedChanged: (value) async {
          speed = value;
        },
      ),
    );
    for (final target in [
      find.text('1.5×'),
      find.byKey(const ValueKey('video-action-save')),
      find.byKey(const ValueKey('video-action-forward')),
      find.byKey(const ValueKey('video-action-delete')),
    ]) {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .widget<CupertinoActionSheetAction>(
                find.byKey(const ValueKey('video-action-delete')))
            .isDestructiveAction,
        isTrue,
      );
      expect(target, findsOneWidget);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    expect(speed, 1.5);
    expect(save, 1);
    expect(forward, 1);
    expect(delete, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancelFromBarrier in [false, true]) {
    testWidgets(
        'iOS sheet cancel keeps preview open (barrier=$cancelFromBarrier)',
        (tester) async {
      var commands = 0;
      await mount(
        tester,
        playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
        chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
        onMore: () => showMediaPreviewVideoActions(
          context: tester.element(find.byType(MediaPreviewVideoChrome)),
          playbackSpeed: 1.5,
          onDownload: () async {
            commands++;
          },
          onSpeedChanged: (_) async {
            commands++;
          },
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-action-delete')), findsNothing);
      expect(find.byKey(const ValueKey('video-action-forward')), findsNothing);
      expect(
          tester
              .widget<CupertinoSlidingSegmentedControl<double>>(
                  find.byType(CupertinoSlidingSegmentedControl<double>))
              .groupValue,
          1.5);
      await tester.pump(const Duration(seconds: 5));
      expect(opacity(tester), 1);
      if (cancelFromBarrier) {
        await tester.tapAt(const Offset(10, 10));
      } else {
        await tester.tap(find.byKey(const ValueKey('video-action-cancel')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.byType(MediaPreviewVideoChrome), findsOneWidget);
      expect(commands, 0);
      expect(opacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final landscape in [false, true]) {
    testWidgets(
        'iOS action sheet fits safe areas and large text (landscape=$landscape)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          landscape ? const Size(812, 375) : const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var openedMedia = 0;
      var enteredPip = 0;
      await mount(
        tester,
        playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
        chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
        brightness: landscape ? Brightness.dark : Brightness.light,
        textScale: landscape ? 1.6 : 1,
        insets: landscape
            ? const EdgeInsets.only(left: 44, right: 44, bottom: 21)
            : const EdgeInsets.only(top: 47, bottom: 34),
        onMore: () => showMediaPreviewVideoActions(
          context: tester.element(find.byType(MediaPreviewVideoChrome)),
          playbackSpeed: 1,
          onDownload: () async {},
          onForward: () async {},
          onDelete: () async {},
          onSpeedChanged: (_) async {},
          onOpenMedia: () {
            openedMedia++;
          },
          onPictureInPicture: () async {
            enteredPip++;
          },
        ),
      );
      for (final action in ['media', 'pip']) {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancelRect =
            tester.getRect(find.byKey(const ValueKey('video-action-cancel')));
        expect(cancelRect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height));
        if (action == 'media' &&
            Platform.environment['CAPTURE_VIDEO_ACTIONS'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('video-preview-root')));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    'artifacts/video-ios-actions-${landscape ? 'landscape' : 'portrait'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        final target = find.byKey(ValueKey('video-action-$action'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }
      expect(openedMedia, 1);
      expect(enteredPip, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('portrait control layout visual receipt', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      captureKey: capture,
      playing: false,
      insets: const EdgeInsets.only(top: 47, bottom: 34),
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_VIDEO_CHROME'] == '1') {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('artifacts/video-preview-portrait.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
