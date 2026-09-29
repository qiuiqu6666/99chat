import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_viewport_motion.dart';

void main() {
  test(
      'a late arrival keeps time to move instead of snapping at burst deadline',
      () {
    final motion = ChatViewportMotion()
      ..retarget(Duration.zero, outgoing: false);
    for (final time in [80, 160, 240, 320, 340]) {
      motion.consumeFraction(Duration(milliseconds: time));
      motion.retarget(Duration(milliseconds: time), outgoing: false);
    }
    expect(motion.consumeFraction(const Duration(milliseconds: 350)),
        lessThan(0.5));
  });

  test(
      'a single receive has a gentle start instead of spending most travel early',
      () {
    final motion = ChatViewportMotion()
      ..retarget(Duration.zero, outgoing: false);
    expect(motion.consumeFraction(const Duration(milliseconds: 130)),
        inInclusiveRange(0.45, 0.65));
  });
}
