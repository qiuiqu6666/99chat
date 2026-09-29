import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_gallery_pick_utils.dart';

void main() {
  testWidgets('picker dismissal and a mixed batch finish without pumping frames',
      (tester) async {
    final sent = <String>[];
    // Real timers run while the test deliberately never paints another frame.
    // The previous endOfFrame waits would leave the first image and the video
    // behind it blocked until a chat was shown again.
    await tester.runAsync(() async {
      await (() async {
        await ChatGalleryPickUtils.waitForPickerDismissSettle(
          transitionDuration: Duration.zero,
        );
        await ChatGalleryPickUtils.yieldForMediaSend();
        for (var i = 0; i < 6; i++) {
          sent.add('image-$i');
          await ChatGalleryPickUtils.yieldForMediaSend();
        }
        sent.add('video');
      })().timeout(const Duration(seconds: 2));
    });
    expect(sent, [...List.generate(6, (i) => 'image-$i'), 'video']);
    await tester.pump();
  });

  testWidgets('background admission finishes while frame scheduling is disabled',
      (tester) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    try {
      expect(binding.framesEnabled, isFalse);
      await tester.runAsync(() async {
        await ChatGalleryPickUtils.yieldForMediaSend()
            .timeout(const Duration(seconds: 1));
      });
    } finally {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pump();
  });
}
