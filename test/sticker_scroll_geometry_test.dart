import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/src/repository/sticker_repository.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_face_bubble.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_constants.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_image_size_probe.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_send_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = StickerRepository.instance;
  final probe = StickerImageSizeProbe.instance;
  const url = 'https://example.com/scroll-sticker.png';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository.clear();
    probe.clear();
  });

  test('new sticker messages carry dimensions to an empty recipient cache', () {
    repository.putCache(StickerItem(
      stickerId: 'sent',
      thumbUrl: url,
      originUrl: url,
      width: 400,
      height: 200,
    ));
    String? sentData;
    StickerSendHelper.sendViaPanelCallback(
      (_, data) => sentData = data,
      stickerId: 'sent',
      thumbUrl: url,
    );
    repository.clear();
    final received = repository.resolveStickerItemSync(sentData!)!;
    expect((received.width, received.height), (400, 200));
  });

  test('changed resources do not inherit the old image dimensions', () {
    repository.putCache(StickerItem(
      stickerId: 'changed',
      thumbUrl: url,
      originUrl: url,
      width: 400,
      height: 200,
    ));
    final changed = repository.resolveStickerItemSync(
      StickerConstants.dataForSticker(
        stickerId: 'changed',
        thumbUrl: 'https://example.com/replacement.png',
      ),
    )!;
    expect(changed.hasIntrinsicSize, isFalse);
  });

  test('incomplete and invalid payload dimensions are ignored as a pair', () {
    for (final query in [
      'width=400',
      'width=-1&height=200',
      'width=400&height=0',
      'width=wrong&height=200'
    ]) {
      final parsed = StickerConstants.parseEmbeddedUrls(
        '99chat://sticker/invalid?thumbUrl=x&$query',
      );
      expect((parsed.width, parsed.height), (null, null));
    }
  });

  test('reading legacy face data retains the already measured dimensions', () {
    repository.putCache(StickerItem(
      stickerId: 'known',
      thumbUrl: url,
      originUrl: url,
      width: 400,
      height: 200,
    ));
    final revision = repository.revision.value;
    final data =
        StickerConstants.dataForSticker(stickerId: 'known', thumbUrl: url);
    for (var i = 0; i < 3; i++) {
      final item = repository.resolveStickerItemSync(data)!;
      expect((item.width, item.height), (400, 200));
      expect(repository.revision.value, revision,
          reason: 'mounting another message must not erase and republish size');
    }
  });

  test('a favorite refresh cannot strip dimensions from the same resource', () {
    repository.putCache(StickerItem(
      stickerId: 'favorite',
      thumbUrl: url,
      originUrl: url,
      width: 400,
      height: 200,
    ));
    repository.putCaches([
      StickerItem(stickerId: 'favorite', thumbUrl: url, originUrl: url),
    ]);
    final item = repository.getCached('favorite')!;
    expect((item.width, item.height), (400, 200));
  });

  testWidgets('a remounted URL sticker uses the known ratio on its first frame',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(400, 200);
      await probe.probe(url, provider: MemoryImage(bytes));
    });
    Widget app(Key key) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 800)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: StickerFaceBubble(key: key, data: url),
                ),
              ),
            ),
          ),
        );
    for (var mount = 0; mount < 2; mount++) {
      await tester.pumpWidget(app(ValueKey(mount)));
      final firstFrame = tester.getSize(find.byType(StickerFaceBubble));
      expect(firstFrame.height, closeTo(firstFrame.width / 2, .01),
          reason: 'the square fallback must never reach the sliver layout');
      await tester.pump();
      expect(tester.getSize(find.byType(StickerFaceBubble)), firstFrame);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final input in ['touch', 'mouse drag', 'wheel']) {
    testWidgets(
        '$input: scrolling toward newer sticker rows has no next-frame jump',
        (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await probe.probe(url, provider: MemoryImage(await _png(400, 200)));
      });
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        home: Scaffold(
          body: ListView.builder(
            controller: scroll,
            reverse: true,
            cacheExtent: 0,
            itemCount: 80,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('row $index', key: ValueKey('label-$index')),
                  const StickerFaceBubble(data: url),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      scroll.jumpTo(1600);
      await tester.pump();
      await tester.pump();
      final gesture = input == 'wheel'
          ? null
          : await tester.startGesture(
              const Offset(200, 600),
              kind: input == 'touch'
                  ? PointerDeviceKind.touch
                  : PointerDeviceKind.mouse,
            );
      var totalMotion = 0.0;
      for (var step = 0; step < 5; step++) {
        final before = scroll.offset;
        if (gesture == null) {
          await tester.sendEventToBinding(const PointerScrollEvent(
            position: Offset(200, 400),
            scrollDelta: Offset(0, 90),
          ));
        } else {
          await gesture.moveBy(const Offset(0, -90));
        }
        await tester.pump();
        totalMotion += before - scroll.offset;
        // Scrollable suppresses hit testing during a held drag, so locate the
        // visible row by its painted coordinate instead of hitTestable().
        final key = find
            .byType(Text)
            .evaluate()
            .map((element) => element.widget.key!)
            .firstWhere((key) {
          final top = tester.getTopLeft(find.byKey(key)).dy;
          return top > 20 && top < 700;
        });
        final paintedTop = tester.getTopLeft(find.byKey(key)).dy;
        final pixels = scroll.offset;
        await tester.pump();
        expect(scroll.offset, closeTo(pixels, .01));
        expect(tester.getTopLeft(find.byKey(key)).dy, closeTo(paintedTop, .01),
            reason:
                'step $step must not resize newly mounted media after paint');
      }
      expect(totalMotion, greaterThan(300),
          reason: 'the test must really scroll');
      await gesture?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    });
  }
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
