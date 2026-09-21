import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_reading_viewport_anchor.dart';

void main() {
  testWidgets('center-front pages do not double-compensate the reading row',
      (tester) async {
    final scroll = ScrollController(initialScrollOffset: 160);
    final newerRows = ValueNotifier(<int>[]);
    final centerKey = GlobalKey();
    final anchorKey = GlobalKey();
    HistoryReadingViewportAnchor? anchor;
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<List<int>>(
        valueListenable: newerRows,
        builder: (_, newer, __) => CustomScrollView(
          controller: scroll,
          reverse: true,
          center: centerKey,
          physics: HistoryPaginationScrollPhysics(
            shouldPreserveNewestInsertExtent: () => true,
            revealGrowthPending: () => true,
            newestInsertAnchorCorrection: (_) => anchor
                ?.correctionFor(anchorKey.currentContext?.findRenderObject()),
          ),
          slivers: [
            SliverList.list(children: [
              for (final id in newer)
                SizedBox(height: 40.0 + id % 5 * 70, child: Text('new $id')),
            ]),
            SliverList(
              key: centerKey,
              delegate: SliverChildBuilderDelegate(
                (_, index) => SizedBox(
                  height: 70,
                  child: Text('old $index', key: index == 5 ? anchorKey : null),
                ),
                childCount: 500,
              ),
            ),
          ],
        ),
      ),
    ));
    anchor = HistoryReadingViewportAnchor.capture(
        anchorKey.currentContext!.findRenderObject());
    expect(anchor, isNotNull);
    final before = tester.getTopLeft(find.byKey(anchorKey)).dy;
    newerRows.value = List.generate(20, (i) => i);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(anchorKey)).dy, closeTo(before, 1));
    expect(scroll.offset, closeTo(160, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    newerRows.dispose();
  });

  for (final dragging in [false, true]) {
    testWidgets(
        'mixed-height newer rows preserve reading position (drag=$dragging)',
        (tester) async {
      final scroll = ScrollController(initialScrollOffset: 160);
      final rows = ValueNotifier(List.generate(500, (i) => 100 - i));
      final anchorKey = GlobalKey();
      HistoryReadingViewportAnchor? anchor;
      var mediaHeight = 40.0;
      var cacheExtent = 200.0;
      var layoutCorrections = 0;
      double top() {
        final context = anchorKey.currentContext!;
        final row = context.findRenderObject() as RenderBox;
        final viewport = RenderAbstractViewport.of(row);
        return row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      }

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder<List<int>>(
          valueListenable: rows,
          builder: (_, values, __) => CustomScrollView(
            controller: scroll,
            reverse: true,
            cacheExtent: cacheExtent,
            physics: HistoryPaginationScrollPhysics(
              parent: const ClampingScrollPhysics(),
              shouldPreserveNewestInsertExtent: () => anchor != null,
              // Deliberately wrong estimate: the measured anchor must win.
              newestInsertRoom: () => 9000,
              revealGrowthPending: () => true,
              newestInsertAnchorCorrection: (metrics) {
                if (anchor == null || anchorKey.currentContext == null) {
                  return null;
                }
                layoutCorrections++;
                return anchor.correctionFor(
                    anchorKey.currentContext!.findRenderObject());
              },
            ),
            slivers: [
              SliverList(
                  delegate: SliverChildBuilderDelegate(
                (_, index) {
                  final id = values[index];
                  return SizedBox(
                    key: ValueKey(id),
                    height: id == 101 ? mediaHeight : 45.0 + id.abs() % 4 * 23,
                    child: SizedBox(
                      key: id == 96 ? anchorKey : null,
                      child: Text('message $id'),
                    ),
                  );
                },
                childCount: values.length,
                findChildIndexCallback: (key) {
                  final index = values.indexOf((key as ValueKey<int>).value);
                  return index < 0 ? null : index;
                },
              ))
            ],
          ),
        )),
      ));
      anchor = HistoryReadingViewportAnchor.capture(
          anchorKey.currentContext!.findRenderObject());
      expect(anchor, isNotNull);
      final gesture =
          dragging ? await tester.startGesture(const Offset(400, 300)) : null;
      if (gesture != null) {
        await gesture.moveBy(const Offset(0, -35));
        await tester.pump();
      }
      final afterUserMove = top();
      rows.value = [101, ...rows.value];
      await tester.pump();
      expect(top(), closeTo(afterUserMove, 1), reason: 'first painted frame');
      mediaHeight = 270;
      cacheExtent = 1000;
      rows.value = [...rows.value];
      await tester.pump();
      expect(top(), closeTo(afterUserMove, 1),
          reason: 'late image size and estimates');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(top(), closeTo(afterUserMove, 1),
            reason: 'no multi-frame drift');
      }
      expect(layoutCorrections, greaterThan(0));
      await gesture?.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      rows.dispose();
    });
  }
}
