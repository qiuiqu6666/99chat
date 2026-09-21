import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the same controller dependency used internally by UIKit.
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_scroll.dart';

void main() {
  testWidgets('search first, middle and last rows center in the chat viewport',
      (tester) async {
    final controller = AutoScrollController();
    final viewportKey = GlobalKey();
    final heights = ValueNotifier<List<double>>([70, 100, 140]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      appBar: AppBar(toolbarHeight: 80),
      bottomNavigationBar: const SizedBox(height: 100),
      body: LayoutBuilder(
          builder: (_, constraints) => ValueListenableBuilder<List<double>>(
                valueListenable: heights,
                builder: (_, values, __) => CustomScrollView(
                  key: viewportKey,
                  reverse: true,
                  controller: controller,
                  slivers: [
                    SliverToBoxAdapter(
                        child: SizedBox(height: constraints.maxHeight / 2)),
                    SliverList(
                        delegate: SliverChildBuilderDelegate(
                            (_, index) => AutoScrollTag(
                                  key: ValueKey(index),
                                  index: -index,
                                  controller: controller,
                                  child: SizedBox(
                                      height: values[index],
                                      child: Text('target-$index')),
                                ),
                            childCount: values.length)),
                    SliverToBoxAdapter(
                        child: SizedBox(height: constraints.maxHeight / 2)),
                  ],
                ),
              )),
    )));
    for (final index in [0, 1, 2]) {
      var complete = false;
      final scroll = controller
          .scrollToIndex(-index, preferPosition: AutoScrollPosition.middle)
          .then((_) => complete = true);
      for (var frame = 0; frame < 80 && !complete; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(complete, isTrue);
      await scroll;
      final viewport = tester.getRect(find.byKey(viewportKey));
      expect(tester.getRect(find.byKey(ValueKey(index))).center.dy,
          closeTo(viewport.center.dy, 2));
    }

    // Late media/text layout changes must be corrected with measured pixels,
    // rather than accepted inside the old 28–72 px tolerance band.
    heights.value = [70, 100, 220];
    await tester.pump();
    final viewport = tester.getRect(find.byKey(viewportKey));
    final target = tester.getRect(find.byKey(const ValueKey(2)));
    final delta = target.center.dy - viewport.center.dy;
    expect(delta.abs(), greaterThan(2));
    controller.jumpTo(searchJumpCenterOffset(
        centerDelta: delta, metrics: controller.position));
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey(2))).center.dy,
        closeTo(viewport.center.dy, 2));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    heights.dispose();
  });

  testWidgets(
      'post-frame jump requests its layout frame without external events',
      (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var oldFinished = false;
    tester.binding.addPostFrameCallback((_) async {
      await tester.binding.endOfFrame;
      oldFinished = true;
    });
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(oldFinished, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason:
            'The old search wait stalls until an unrelated UI/network update.');
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(oldFinished, isTrue);

    var finished = false;
    tester.binding.addPostFrameCallback((_) async {
      await waitForSearchJumpLayout();
      finished = true;
    });
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(finished, isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('offscreen negative chat tag is materialized and centered',
      (tester) async {
    final controller = AutoScrollController(axis: Axis.vertical);
    final center = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomScrollView(
      reverse: true,
      center: center,
      controller: controller,
      cacheExtent: 0,
      slivers: [
        SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
          final globalIndex = 29 - index;
          return AutoScrollTag(
              key: ValueKey(globalIndex),
              controller: controller,
              index: -globalIndex,
              child:
                  SizedBox(height: 120, child: Text('message-$globalIndex')));
        }, childCount: 30)),
        SliverPadding(key: center, padding: EdgeInsets.zero),
        SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
          final globalIndex = 30 + index;
          return AutoScrollTag(
            key: ValueKey(globalIndex),
            controller: controller,
            index: -globalIndex,
            child: SizedBox(
                height: 70 + (index % 3) * 50, child: Text('message-$index')),
          );
        }, childCount: 30)),
      ],
    ))));
    expect(controller.tagMap.containsKey(-5), isFalse);
    // Regression: the dependency cannot forecast toward this negative tag.
    var oldCompleted = false;
    controller
        .scrollToIndex(-5, preferPosition: AutoScrollPosition.middle)
        .then((_) => oldCompleted = true);
    for (var i = 0; i < 100 && !oldCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(oldCompleted, isTrue);
    expect(controller.tagMap.containsKey(-5), isFalse);

    Future<void> locate(int index) async {
      final ready = await materializeSearchJumpTarget(
          controller: controller,
          resolveIndex: () => index,
          isActive: () => true);
      expectSync(ready, isTrue);
      await controller.scrollToIndex(-index,
          preferPosition: AutoScrollPosition.middle);
    }

    for (final index in [5, 50]) {
      var completed = false;
      locate(index).then((_) => completed = true);
      for (var i = 0; i < 200 && !completed; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completed, isTrue);
      final tagContext = controller.tagMap[-index]!.context;
      final scrollable = Scrollable.of(tagContext);
      final viewport = scrollable.context.findRenderObject();
      expect(viewport, isA<RenderBox>());
      final target = tagContext.findRenderObject()! as RenderBox;
      final viewportBox = viewport! as RenderBox;
      final targetTop =
          target.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      expect(
          searchJumpAtReachablePosition(
            targetTop: targetTop,
            targetHeight: target.size.height,
            viewportHeight: viewportBox.size.height,
            metrics: scrollable.position,
            tolerance: 28,
          ),
          isTrue,
          reason:
              'top=$targetTop viewport=${viewportBox.size} row=${target.size}');
      final row = tester.getRect(find.byKey(ValueKey(index)));
      expect(row.center.dy, closeTo(300, 2));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test('cancellation avoids scroll mutations', () async {
    final controller = AutoScrollController();
    expect(
        await materializeSearchJumpTarget(
            controller: controller,
            resolveIndex: () => 5,
            isActive: () => false),
        isFalse);
    controller.dispose();
  });

  test('visible edge row succeeds without an impossible centering loop', () {
    final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 3000,
        pixels: 0,
        viewportDimension: 600,
        axisDirection: AxisDirection.up,
        devicePixelRatio: 1);
    expect(
        searchJumpAtReachablePosition(
            targetTop: 500,
            targetHeight: 100,
            viewportHeight: 600,
            metrics: metrics,
            tolerance: 28),
        isTrue);
    expect(
        searchJumpAtReachablePosition(
            targetTop: -200,
            targetHeight: 100,
            viewportHeight: 600,
            metrics: metrics,
            tolerance: 28),
        isFalse);
    expect(
        searchJumpAtReachablePosition(
            targetTop: 50,
            targetHeight: 100,
            viewportHeight: 600,
            metrics: metrics.copyWith(pixels: 500),
            tolerance: 28),
        isFalse);
  });
}
