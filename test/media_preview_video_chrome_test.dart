import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_reference_button.dart';
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
  double speed = 1.0;
  @override
  dynamic get playbackController => controller;
  @override
  double get playbackSpeed => speed;
  @override
  Future<void> setPlaybackSpeed(double value) async {
    speed = value;
  }

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
    Future<void> Function()? onForward,
    Future<void> Function()? onSave,
    Future<void> Function()? onDelete,
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
                        onForward: onForward,
                        onSave: onSave,
                        onDelete: onDelete,
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

  testWidgets('time sits above the progress bar and speed cycles on tap',
      (tester) async {
    final playerKey = GlobalKey<TIMUIKitVideoPlayerState>();
    final chromeKey = GlobalKey<MediaPreviewVideoChromeState>();
    await mount(tester, playerKey: playerKey, chromeKey: chromeKey);
    final player = playerKey.currentState! as _PlayerState;
    final speedButton = find.byKey(const ValueKey('video-playback-speed'));
    final timeline = find.text('00:32 / 02:18');
    expect(timeline, findsOneWidget);
    expect(tester.getTopLeft(timeline).dy,
        lessThan(tester.getTopLeft(find.byType(Slider)).dy));
    for (final expected in <(double, String)>[
      (1.5, '1.5×'),
      (2.0, '2.0×'),
      (1.0, '1.0×'),
    ]) {
      await tester.tap(speedButton);
      await tester.pump();
      expect(player.speed, expected.$1);
      expect(find.text(expected.$2), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    unawaited(tester
        .state<MediaPreviewVideoChromeState>(
            find.byType(MediaPreviewVideoChrome))
        .showActions());
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

  testWidgets('inline video actions use round buttons and keep their callbacks',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final called = <String>[];
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      playing: false,
      insets: const EdgeInsets.only(top: 47, bottom: 34),
      onForward: () async => called.add('forward'),
      onSave: () async => called.add('save'),
      onDelete: () async => called.add('delete'),
    );

    for (final action in ['forward', 'save', 'delete']) {
      final button = find.byKey(ValueKey('video-inline-$action'));
      expect(button, findsOneWidget);
      expect(tester.widget<MediaPreviewReferenceButton>(button).icon, isNotNull);
      final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: button, matching: find.byType(Tooltip)).first);
      expect(tooltip.message, isNotEmpty);
      final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first);
      expect(material.shape, isA<CircleBorder>());
      expect(material.color, Colors.black.withValues(alpha: 0.45));
      expect(tester.getSize(button), const Size(40, 40));
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(810));
      await tester.tap(button);
      await tester.pump();
    }
    final forwardCenter =
        tester.getCenter(find.byKey(const ValueKey('video-inline-forward')));
    final saveCenter =
        tester.getCenter(find.byKey(const ValueKey('video-inline-save')));
    final deleteCenter =
        tester.getCenter(find.byKey(const ValueKey('video-inline-delete')));
    expect(saveCenter.dx - forwardCenter.dx, closeTo(44, 1));
    expect(deleteCenter.dx - saveCenter.dx, closeTo(44, 1));
    expect(
        tester.getRect(find.byKey(const ValueKey('video-inline-delete'))).right,
        closeTo(378, 1));
    expect(called, ['forward', 'save', 'delete']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape video actions stay inside the right safe area',
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
      insets: const EdgeInsets.only(left: 44, right: 44, bottom: 21),
      onForward: () async {},
      onSave: () async {},
      onDelete: () async {},
    );
    final deleteButton = find.byKey(const ValueKey('video-inline-delete'));
    expect(tester.getRect(deleteButton).right, closeTo(756, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('video save animates while waiting for completion',
      (tester) async {
    final save = Completer<void>();
    var calls = 0;
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      onSave: () {
        calls++;
        return save.future;
      },
    );

    await tester.tap(find.byKey(const ValueKey('video-inline-save')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    expect(find.byKey(const ValueKey('video-save-loading')), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(tester), 1);

    save.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('video-save-loading')), findsNothing);
    expect(find.byKey(const ValueKey('video-inline-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('video menu keeps actions without a duplicate speed selector',
      (tester) async {
    var save = 0;
    var forward = 0;
    var delete = 0;
    await mount(
      tester,
      playerKey: GlobalKey<TIMUIKitVideoPlayerState>(),
      chromeKey: GlobalKey<MediaPreviewVideoChromeState>(),
      onMore: () => showMediaPreviewVideoActions(
        context: tester.element(find.byType(MediaPreviewVideoChrome)),
        onDownload: () async {
          save++;
        },
        onForward: () async {
          forward++;
        },
        onDelete: () async {
          delete++;
        },
      ),
    );
    for (final target in [
      find.byKey(const ValueKey('video-action-save')),
      find.byKey(const ValueKey('video-action-forward')),
      find.byKey(const ValueKey('video-action-delete')),
    ]) {
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      unawaited(tester
          .state<MediaPreviewVideoChromeState>(
              find.byType(MediaPreviewVideoChrome))
          .showActions());
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
          find.byType(CupertinoSlidingSegmentedControl<double>), findsNothing);
      expect(find.text('播放速度'), findsNothing);
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
          onDownload: () async {
            commands++;
          },
        ),
      );
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      unawaited(tester
          .state<MediaPreviewVideoChromeState>(
              find.byType(MediaPreviewVideoChrome))
          .showActions());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('video-action-delete')), findsNothing);
      expect(find.byKey(const ValueKey('video-action-forward')), findsNothing);
      expect(
          find.byType(CupertinoSlidingSegmentedControl<double>), findsNothing);
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
          onDownload: () async {},
          onForward: () async {},
          onDelete: () async {},
          onOpenMedia: () {
            openedMedia++;
          },
        ),
      );
      for (final action in ['media']) {
        expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
        unawaited(tester
            .state<MediaPreviewVideoChromeState>(
                find.byType(MediaPreviewVideoChrome))
            .showActions());
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
