import 'dart:ui' as ui;
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_shell.dart';

void main() {
  testWidgets('measure preview backdrop at ten percent entrance', (tester) async {
    final animation = AnimationController(vsync: tester, value: 0.1,
        duration: const Duration(milliseconds: 340));
    final latch = MediaPreviewEntranceLatch(onSettled: () {});
    final metrics = MediaPreviewSlideMetrics();
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(
      key: boundary,
      child: ColoredBox(color: Colors.white, child: MediaPreviewChromeScope(
        animation: animation,
        child: MediaPreviewSlideShell(
          slidePageKey: GlobalKey<ExtendedImageSlidePageState>(),
          slideMetrics: metrics, entranceLatch: latch,
          onSlidingPage: (_) {}, slideEndHandler: (_, {state, details}) => false,
          bodyBuilder: (_, __) => const SizedBox.expand(),
          chromeBuilder: (_) => const SizedBox.shrink(), onClose: () {},
          opaquePlatformBackdrop: false, enableEdgeBack: false,
        ),
      )),
    )));
    expect(latch.settled, isFalse);
    expect(latch.scrimOpacity(animation, 1), 0.1);
    final pixel = await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final red = bytes.getUint8((10 * image.width + 10) * 4);
      image.dispose();
      return red;
    });
    debugPrint('entrance=0.10, expected white-under-10%-black red≈230; measured red=$pixel');
    // Audit reproducer: current image layer covers the animated scrim.
    expect(pixel, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    latch.dispose();
    metrics.dispose();
    animation.dispose();
  });
}
