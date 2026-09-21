import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/home_tab_reselection.dart';

void main() {
  test('24 rapid tab switches never request an unread jump', () {
    final taps = HomeTabReselection();
    var selected = 0;
    var jumps = 0;
    for (var i = 0; i < 24; i++) {
      final index = (i + 1) % 3;
      if (taps.registerTap(
        index: index,
        selectedIndex: selected,
        elapsed: Duration(milliseconds: i * 250),
      )) {
        jumps++;
      }
      // Home changes selection synchronously after recognizing the gesture.
      selected = index;
    }
    expect(selected, 0);
    expect(jumps, 0);
  });

  test('same selected tab double tap jumps once and consumes the pair', () {
    final taps = HomeTabReselection();
    final results = <bool>[];
    for (final time in [0, 250, 280, 400]) {
      results.add(taps.registerTap(
        index: 1,
        selectedIndex: 1,
        elapsed: Duration(milliseconds: time),
      ));
    }
    expect(results, [false, true, false, true]);
  });

  test('switching tabs cannot carry a pending tap into another tab', () {
    final taps = HomeTabReselection();
    bool tap(int index, int selected, int time) => taps.registerTap(
          index: index,
          selectedIndex: selected,
          elapsed: Duration(milliseconds: time),
        );
    expect(tap(0, 0, 0), isFalse);
    expect(tap(1, 0, 50), isFalse);
    expect(tap(1, 1, 100), isFalse);
    expect(tap(1, 1, 200), isTrue);
    expect(tap(1, 1, 250), isFalse);
    // Programmatic tab navigation also terminates a pending gesture.
    taps.reset();
    expect(tap(1, 1, 280), isFalse);
  });

  test('expired taps start a fresh pair without delayed reset races', () {
    final taps = HomeTabReselection();
    bool tap(int time) => taps.registerTap(
          index: 0,
          selectedIndex: 0,
          elapsed: Duration(milliseconds: time),
        );
    expect(tap(0), isFalse);
    expect(tap(301), isFalse);
    expect(tap(550), isTrue);
  });
}
