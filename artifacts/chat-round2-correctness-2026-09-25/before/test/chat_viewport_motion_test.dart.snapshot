import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_viewport_motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  test('send and receive finish at rest with distance-aware bounded durations',
      () {
    for (final outgoing in [true, false]) {
      for (final extent in [64.0, 400.0, 800.0]) {
        final motion = ChatViewportMotion()
          ..retarget(ms(0), outgoing: outgoing, distance: extent);
        final end =
            ChatViewportMotion.durationFor(outgoing: outgoing, extent: extent);
        expect(end, lessThanOrEqualTo(ChatViewportMotion.maxDuration));
        var distance = extent;
        distance *= 1 - motion.consumeFraction(end ~/ 2);
        expect(distance, closeTo(extent / 2, extent * .005));
        distance *= 1 - motion.consumeFraction(end);
        expect(distance, 0);
      }
    }
  });

  test('retargeting remains monotone and settles after the final arrival', () {
    final motion = ChatViewportMotion()
      ..retarget(ms(0), outgoing: false, distance: 200);
    var distance = 200.0;
    for (final time in [50, 100, 150, 200, 250, 300, 340]) {
      distance *= 1 - motion.consumeFraction(ms(time));
      distance += 120;
      motion.retarget(ms(time), outgoing: false, distance: distance);
    }
    var previous = distance;
    for (var time = 350; time < 690; time += 10) {
      distance *= 1 - motion.consumeFraction(ms(time));
      expect(distance, inInclusiveRange(0, previous));
      previous = distance;
    }
    distance *= 1 - motion.consumeFraction(ms(690));
    expect(distance, 0);
  });

  test('dropped frames and reduced motion do not prolong scrolling', () {
    final motion = ChatViewportMotion()..retarget(ms(0), outgoing: false);
    expect(motion.consumeFraction(ms(800)), 1);
    motion.retarget(ms(900), outgoing: true);
    expect(motion.consumeFraction(ms(901), disableAnimations: true), 1);
  });

  test('60Hz and 120Hz reach identical positions at the same time', () {
    double remaining(int step) {
      final motion = ChatViewportMotion()..retarget(ms(0), outgoing: false);
      var distance = 500.0;
      for (var t = step; t <= 128; t += step) {
        distance *= 1 - motion.consumeFraction(ms(t));
      }
      return distance;
    }

    expect(remaining(8), closeTo(remaining(16), .0001));
  });

  test('a new transaction restarts its clock after cancellation', () {
    final motion = ChatViewportMotion()..retarget(ms(0), outgoing: false);
    motion.consumeFraction(ms(150));
    motion.retarget(ms(0), outgoing: true, restart: true);
    expect(motion.consumeFraction(ms(120)), closeTo(.5, .0001));
    expect(motion.consumeFraction(ms(240)), 1);
  });

  test('retargeting preserves measured speed across a second message', () {
    final motion = ChatViewportMotion()
      ..retarget(ms(0), outgoing: false, distance: 120);
    var remaining = 120.0;
    remaining *= 1 - motion.consumeFraction(ms(79));
    final before = remaining;
    remaining *= 1 - motion.consumeFraction(ms(80));
    final speedBefore = (before - remaining) * 1000;
    remaining += 96;
    motion.retarget(ms(80), outgoing: true, distance: remaining);
    final speedAfter = remaining * motion.consumeFraction(ms(81)) * 1000;
    expect(speedAfter, closeTo(speedBefore, speedBefore * .04));
  });

  test('large bursts retain at most one viewport of animation', () {
    expect(ChatViewportMotion.correction(0, 80, 600), 80);
    expect(ChatViewportMotion.correction(100, 2000, 600), 500);
    expect(ChatViewportMotion.correction(900, 200, 600), -300);
    expect(ChatViewportMotion.correction(100, 200, 0), 200);
  });
}
