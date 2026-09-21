import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';

FixedScrollMetrics _metrics(double maxExtent, {double pixels = 200}) =>
    FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: maxExtent,
      pixels: pixels,
      viewportDimension: 600,
      axisDirection: AxisDirection.up,
      devicePixelRatio: 1,
    );

void main() {
  for (final growth in [-6000.0, 6000.0]) {
    for (final scrolling in [false, true]) {
      test('missing row anchor ignores estimate $growth (scrolling=$scrolling)',
          () {
        var applied = 0.0;
        final physics = HistoryPaginationScrollPhysics(
          shouldPreserveNewestInsertExtent: () => true,
          shouldCompensate: () => true,
          revealGrowthPending: () => true,
          newestInsertRoom: () => 40,
          newestInsertAnchorCorrection: (_) => null,
          onNewestInsertApplied: (delta) => applied += delta,
        );
        final result = physics.adjustPositionForNewDimensions(
          oldPosition: _metrics(10000),
          newPosition: _metrics(10000 + growth),
          isScrolling: scrolling,
          velocity: scrolling ? -500 : 0,
        );
        expect(result, 200);
        expect(applied, 0);
      });
    }
    test('measured insert wins even when estimated total changes by $growth',
        () {
      final physics = HistoryPaginationScrollPhysics(
        shouldPreserveNewestInsertExtent: () => true,
        revealGrowthPending: () => true,
        newestInsertRoom: () => 10,
        newestInsertAnchorCorrection: (_) => 40,
      );
      expect(
        physics.adjustPositionForNewDimensions(
          oldPosition: _metrics(10000),
          newPosition: _metrics(10000 + growth),
          isScrolling: true,
          velocity: -500,
        ),
        240,
      );
    });
  }

  test('legacy reveal budget cannot turn a 6000px estimate into a jump', () {
    var room = 40.0;
    final physics = HistoryPaginationScrollPhysics(
      shouldPreserveNewestInsertExtent: () => true,
      revealGrowthPending: () => true,
      newestInsertRoom: () => room,
      onNewestInsertApplied: (delta) => room -= delta,
    );
    final first = physics.adjustPositionForNewDimensions(
      oldPosition: _metrics(10000),
      newPosition: _metrics(16000),
      isScrolling: true,
      velocity: -500,
    );
    expect(first, 240);
    expect(room, 0);
    expect(
      physics.adjustPositionForNewDimensions(
        oldPosition: _metrics(16000, pixels: first),
        newPosition: _metrics(22000, pixels: first),
        isScrolling: true,
        velocity: -500,
      ),
      first,
    );
  });
}
