import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_slide_frame_capture.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';

class _AsyncFailingCaptureBoundary extends SingleChildRenderObjectWidget {
  const _AsyncFailingCaptureBoundary({super.key, required super.child});

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _AsyncFailingCaptureRenderObject();
}

class _AsyncFailingCaptureRenderObject extends RenderRepaintBoundary {
  @override
  Future<ui.Image> toImage({double pixelRatio = 1.0}) =>
      Future<ui.Image>.error(StateError('GPU capture unavailable'));
}

void main() {
  testWidgets('an unavailable snapshot finishes and allows the next return',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    await tester.pumpWidget(MaterialApp(
      home: ChatHistoryWindowTransition(
        key: key,
        child: const SizedBox.expand(child: Text('live history')),
      ),
    ));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
              of: find.byKey(key), matching: find.byType(RepaintBoundary))
          .first,
    );
    boundary.markNeedsPaint();
    expect(key.currentState!.begin(showProgress: false), isFalse);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('live history'), findsOneWidget);
    final finished = key.currentState!.finish();
    await tester.pump();
    await finished;
    await tester.pump();
    expect(key.currentState!.begin(showProgress: false), isTrue);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('asynchronous frame capture errors fall back without escaping',
      (tester) async {
    final captureKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: _AsyncFailingCaptureBoundary(
        key: captureKey,
        child: const SizedBox.expand(child: ColoredBox(color: Colors.blue)),
      ),
    ));
    final image = await MediaPreviewSlideFrameCapture.capture(
      MediaPreviewSlideFrameRequest(
        frameCaptureKey: captureKey,
        pixelRatio: 1,
      ),
    );
    expect(image, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'retains painted rows through an empty replacement and reveals target',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    final page = ValueNotifier(0);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ChatHistoryWindowTransition(
        key: key,
        child: ValueListenableBuilder<int>(
            valueListenable: page,
            builder: (_, value, __) => SizedBox.expand(
                child: ColoredBox(
                    color: value == 2 ? Colors.blue : Colors.white,
                    child: value == 1
                        ? const SizedBox()
                        : TextButton(
                            onPressed: () => taps++,
                            child: Text('message $value'))))),
      ),
    )));
    expect(key.currentState!.begin(), isTrue);
    await tester.pump();
    final retained = tester.widget<RawImage>(find.byType(RawImage)).image;
    page.value = 1;
    await tester.pump();
    expect(
        tester.widget<RawImage>(find.byType(RawImage)).image, same(retained));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    page.value = 2;
    await tester.pump();
    await tester.tap(find.text('message 2'), warnIfMissed: false);
    expect(taps, 0);
    var done = false;
    final pending = key.currentState!.finish().then((_) => done = true);
    await tester.pump();
    await pending;
    expect(done, isTrue);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('message 2'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
    page.dispose();
  });

  testWidgets('spinner overlays retained messages without exposing target gaps',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    final captureKey = GlobalKey();
    final page = ValueNotifier(false);
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: const Color(0xff00ff00),
            child: SizedBox(
              width: 200,
              height: 200,
              child: ChatHistoryWindowTransition(
                key: key,
                child: ValueListenableBuilder<bool>(
                  valueListenable: page,
                  builder: (_, target, __) => Align(
                    alignment:
                        target ? Alignment.bottomRight : Alignment.topLeft,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: ColoredBox(
                        color: target
                            ? const Color(0xff0000ff)
                            : const Color(0xffff0000),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    Future<List<int>> pixel(int x, int y) async {
      return (await tester.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final offset = (y * image.width + x) * 4;
          return data.buffer
              .asUint8List(data.offsetInBytes + offset, 4)
              .toList();
        } finally {
          image.dispose();
        }
      }))!;
    }

    expect(key.currentState!.begin(showSpinner: true), isTrue);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final retained = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(retained.width, (200 * tester.view.devicePixelRatio).ceil());
    page.value = true;
    await tester.pump();
    // Target blue rectangle has laid out but must not be painted through the
    // transparent lower-right gap of the old viewport (wallpaper stays green).
    expect(await pixel(175, 175), [0, 255, 0, 255]);
    expect(await pixel(25, 25), [255, 0, 0, 255]);
    expect(
        find.descendant(
            of: find.byKey(key), matching: find.byType(FadeTransition)),
        findsNothing);
    final pending = key.currentState!.finish();
    expect(key.currentState!.finish(), same(pending));
    await tester.pump();
    await pending;
    await tester.pump();
    expect(await pixel(175, 175), [0, 0, 255, 255]);
    expect(await pixel(25, 25), [0, 255, 0, 255]);
    // Returning to latest can immediately start a new, independent handoff.
    expect(key.currentState!.begin(), isTrue);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained bottom reload can stay silent', (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatHistoryWindowTransition(
          key: key,
          child: const SizedBox.expand(child: Text('current history')),
        ),
      ),
    );

    expect(key.currentState!.begin(showProgress: false), isTrue);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final pending = key.currentState!.finish();
    await tester.pump();
    await pending;
    await tester.pump();
  });

  testWidgets('without a snapshot the spinner leaves the live list visible',
      (tester) async {
    final key = GlobalKey<ChatHistoryWindowTransitionState>();
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatHistoryWindowTransition(
        key: key,
        child: Builder(builder: (_) {
          builds++;
          return const SizedBox.expand(child: Text('visible messages'));
        }),
      ),
    ));
    final initialBuilds = builds;
    expect(key.currentState!.begin(retainViewport: false), isFalse);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    final listOpacity = find
        .descendant(of: find.byKey(key), matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(listOpacity).opacity, 1);
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, initialBuilds,
        reason: 'Spinner ticks must not rebuild the message list.');
    final finished = key.currentState!.finish();
    await tester.pump();
    await finished;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('visible messages'), findsOneWidget);
  });

  for (final retainViewport in [true, false]) {
    for (final changed in [false, true]) {
      testWidgets(
          'release ${retainViewport ? 'snapshot' : 'spinner'} on ${changed ? 'route exit' : 'failed load'}',
          (tester) async {
        final key = GlobalKey<ChatHistoryWindowTransitionState>();
        await tester.pumpWidget(MaterialApp(
            home: ChatHistoryWindowTransition(
                key: key,
                child:
                    const SizedBox.expand(child: Text('original message')))));
        expect(
            key.currentState!
                .begin(retainViewport: retainViewport, showSpinner: true),
            retainViewport);
        await tester.pump();
        final pending = key.currentState!.finish();
        await tester.pump();
        if (changed) {
          await tester.pumpWidget(const SizedBox());
        } else {
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(milliseconds: 200));
        }
        await pending;
        await tester.pump();
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (!changed) expect(find.text('original message'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
