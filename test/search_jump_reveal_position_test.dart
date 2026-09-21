import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// UIKit owns this dependency; use its actual scroll controller in the test.
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_visibility.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_scroll.dart';

void main() {
  testWidgets(
      'unread overlay retains messages then allows immediate drag and fling',
      (tester) async {
    final transition = GlobalKey<ChatHistoryWindowTransitionState>();
    final viewport = GlobalKey();
    final controller = AutoScrollController();
    final heights = ValueNotifier(List<double>.filled(60, 100));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatHistoryWindowTransition(
          key: transition,
          child: LayoutBuilder(
              builder: (_, constraints) => ValueListenableBuilder<List<double>>(
                    valueListenable: heights,
                    builder: (_, rows, __) => CustomScrollView(
                      key: viewport,
                      reverse: true,
                      controller: controller,
                      cacheExtent: 0,
                      slivers: [
                        SliverToBoxAdapter(
                            child: SizedBox(height: constraints.maxHeight / 2)),
                        SliverList(
                            delegate: SliverChildBuilderDelegate(
                                (_, index) => AutoScrollTag(
                                      key: ValueKey(index),
                                      controller: controller,
                                      index: -index,
                                      child: SizedBox(
                                          height: rows[index],
                                          child: Text('unread-$index')),
                                    ),
                                childCount: rows.length)),
                        SliverToBoxAdapter(
                            child: SizedBox(height: constraints.maxHeight / 2)),
                      ],
                    ),
                  )),
        ),
      ),
    ));
    final position = controller.position;
    transition.currentState!.begin(showSpinner: true);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // A late media size changes the around-window geometry during loading.
    heights.value = List.generate(60, (i) => 80.0 + (i % 4) * 30);
    var positioned = false;
    Future<void> locate() async {
      final ready = await materializeSearchJumpTarget(
          controller: controller, resolveIndex: () => 35, isActive: () => true);
      expectSync(ready, isTrue);
      await waitForSearchJumpLayout();
      final targetBox =
          controller.tagMap[-35]!.context.findRenderObject()! as RenderBox;
      final viewportBox =
          viewport.currentContext!.findRenderObject()! as RenderBox;
      final targetTop =
          targetBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      controller.jumpTo(searchJumpCenterOffset(
          centerDelta: targetTop +
              targetBox.size.height / 2 -
              viewportBox.size.height / 2,
          metrics: controller.position));
      await waitForSearchJumpLayout();
      positioned = true;
    }

    final pending = locate();
    for (var frame = 0; frame < 180 && !positioned; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(positioned, isTrue);
    await pending;
    final pixels = position.pixels;
    final target = tester.getRect(find.byKey(const ValueKey(35)));
    expect(target.center.dy,
        closeTo(tester.getRect(find.byKey(viewport)).center.dy, 2));
    final finished = transition.currentState!.finish();
    await tester.pump();
    await finished;
    await tester.pump();
    expect(identical(controller.position, position), isTrue);
    expect(position.pixels, closeTo(pixels, .5));
    expect(tester.getRect(find.byKey(const ValueKey(35))).center.dy,
        closeTo(target.center.dy, .5));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    // There must be no remaining input blocker after the target is revealed.
    final gesture =
        await tester.startGesture(tester.getRect(find.byKey(viewport)).center);
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect((position.pixels - pixels).abs(), greaterThan(20));
    await gesture.up();
    await tester.pumpAndSettle();
    final beforeFling = position.pixels;
    await tester.fling(find.byKey(viewport), const Offset(0, -200), 1200);
    await tester.pump(const Duration(milliseconds: 16));
    final afterFling = position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    expect((afterFling - beforeFling).abs(), greaterThan(20));
    expect((position.pixels - afterFling).abs(), greaterThan(1),
        reason: 'Ballistic scrolling must continue after the unread handoff.');
    await tester.pumpWidget(const SizedBox());
    heights.dispose();
    controller.dispose();
  });

  for (final stable in [false, true]) {
    testWidgets(
        stable
            ? 'revealing the target preserves its ScrollPosition and visible bubble'
            : 'old wrapper removal replaces the positioned Scrollable',
        (tester) async {
      final controller = AutoScrollController();
      final visible = ValueNotifier(false);
      final center = GlobalKey();
      var targetInitializations = 0;
      Widget list() => CustomScrollView(
            controller: controller,
            reverse: true,
            center: center,
            cacheExtent: 0,
            slivers: [
              SliverPadding(key: center, padding: EdgeInsets.zero),
              SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                return AutoScrollTag(
                  key: ValueKey(index),
                  controller: controller,
                  index: -index,
                  child: index == 19
                      ? _TargetBubble(onInit: () => targetInitializations++)
                      : SizedBox(
                          height: 95 + index % 3 * 40,
                          child: Text('row $index')),
                );
              }, childCount: 40)),
            ],
          );
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, __) => stable
              ? ChatHistoryVisibility(visible: show, child: list())
              : show
                  ? list()
                  : Opacity(opacity: 0, child: IgnorePointer(child: list())),
        ),
      )));

      var positioned = false;
      Future<void> locate() async {
        await materializeSearchJumpTarget(
            controller: controller,
            resolveIndex: () => 19,
            isActive: () => true);
        await controller.scrollToIndex(-19,
            preferPosition: AutoScrollPosition.middle);
        positioned = true;
      }

      final pending = locate();
      for (var frame = 0; frame < 150 && !positioned; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(positioned, isTrue);
      await pending;
      final position = controller.position;
      final pixels = position.pixels;
      final before = tester.getRect(find.text('selected message'));
      final mounts = targetInitializations;
      expect(before.center.dy, closeTo(300, 2));

      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      if (stable) {
        expect(identical(controller.position, position), isTrue);
        expect(controller.position.pixels, closeTo(pixels, .5));
        expect(tester.getRect(find.text('selected message')).center.dy,
            closeTo(before.center.dy, .5));
        expect(targetInitializations, mounts);
        final gate = find.byType(ChatHistoryVisibility);
        expect(
            tester
                .widget<Opacity>(find
                    .descendant(of: gate, matching: find.byType(Opacity))
                    .first)
                .opacity,
            1);
        expect(
            tester
                .widget<IgnorePointer>(find
                    .descendant(of: gate, matching: find.byType(IgnorePointer))
                    .first)
                .ignoring,
            isFalse);
      } else {
        expect(identical(controller.position, position), isFalse);
        expect((controller.position.pixels - pixels).abs(), greaterThan(100),
            reason:
                'Removing the wrapper loses the just-centered target offset.');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      visible.dispose();
    });
  }
}

class _TargetBubble extends StatefulWidget {
  const _TargetBubble({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_TargetBubble> createState() => _TargetBubbleState();
}

class _TargetBubbleState extends State<_TargetBubble> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 140, child: Text('selected message'));
}
