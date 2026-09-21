import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_history_layout.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/search_jump_scroll.dart';

V2TimMessage message(int seq) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
    })
      ..seq = '$seq'
      ..msgID = 'message_$seq'
      ..elemType = 1;

class _HistoryFixture {
  final rows = ValueNotifier<List<V2TimMessage>>([message(100)]);
  final controller = ScrollController();
  final center = GlobalKey();
  final viewport = GlobalKey();
  final heights = <String, double>{'message_100': 100};
  static const anchor = MessageAnchor(
      conversationID: 'group_g', convType: 2, msgID: 'message_100');

  Widget app() => MaterialApp(
        home: Scaffold(
          appBar: AppBar(toolbarHeight: 70),
          bottomNavigationBar: const SizedBox(height: 90),
          body: ValueListenableBuilder<List<V2TimMessage>>(
            valueListenable: rows,
            builder: (_, current, __) {
              final split = searchHistorySplitIndex(current, anchor);
              final newer = current.take(split).toList().reversed.toList();
              final older = current.skip(split).toList();
              Widget sliver(List<V2TimMessage> page) => SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, index) => SizedBox(
                        key: ValueKey(page[index].msgID!),
                        height: heights[page[index].msgID] ?? 60,
                        child: Text(page[index].msgID!),
                      ),
                      childCount: page.length,
                      findChildIndexCallback: (key) {
                        final index = page.indexWhere(
                            (m) => m.msgID == (key as ValueKey).value);
                        return index < 0 ? null : index;
                      },
                    ),
                  );
              return CustomScrollView(
                key: viewport,
                controller: controller,
                center: center,
                reverse: true,
                physics: HistoryPaginationScrollPhysics(
                  shouldCompensate: () => true,
                  shouldPreserveNewestInsertExtent: () => false,
                ),
                slivers: [
                  const SearchHistoryEdgeSpace(newer: true),
                  sliver(newer),
                  SliverPadding(key: center, padding: EdgeInsets.zero),
                  sliver(older),
                  const SearchHistoryEdgeSpace(newer: false),
                ],
              );
            },
          ),
        ),
      );

  double targetY(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey('message_100'))).dy;

  Future<void> centerTarget(WidgetTester tester) async {
    await tester.pumpWidget(app());
    for (var i = 0; i < 3; i++) {
      final delta = targetY(tester) - tester.getCenter(find.byKey(viewport)).dy;
      controller.jumpTo(searchJumpCenterOffset(
          centerDelta: delta, metrics: controller.position));
      await tester.pump();
    }
    expect(
        targetY(tester), closeTo(tester.getCenter(find.byKey(viewport)).dy, 1));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    rows.dispose();
  }
}

void main() {
  testWidgets('SDK pages preserve the row under an active drag',
      (tester) async {
    final fixture = _HistoryFixture();
    fixture.rows.value = [for (var n = 130; n >= 70; n--) message(n)];
    await fixture.centerTarget(tester);
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(fixture.viewport)));
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    final bounds = tester.getRect(find.byKey(fixture.viewport));
    final visible = find
        .byType(Text)
        .evaluate()
        .where((element) {
          final text = (element.widget as Text).data ?? '';
          if (!text.startsWith('message_')) return false;
          final y = tester.getCenter(find.text(text)).dy;
          return y > bounds.top + 40 && y < bounds.bottom - 40;
        })
        .first
        .widget as Text;
    final row = find.text(visible.data!);
    final before = tester.getCenter(row).dy;
    fixture.rows.value = [
      for (var n = 160; n > 130; n--) message(n),
      ...fixture.rows.value,
      for (var n = 69; n >= 40; n--) message(n),
    ];
    await tester.pump();
    expect(tester.getCenter(row).dy, closeTo(before, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    await fixture.dispose(tester);
  });

  testWidgets('short edge result stays centered as both SDK sides grow',
      (tester) async {
    final fixture = _HistoryFixture();
    await fixture.centerTarget(tester);
    final before = fixture.targetY(tester);
    final scrollPosition = fixture.controller.position;
    // No extra scroll/pump is inserted to make stale extent estimates settle.
    for (var page = 1; page <= 4; page++) {
      fixture.rows.value = [
        ...fixture.rows.value,
        for (var n = 100 - (page - 1) * 20 - 1; n >= 100 - page * 20; n--)
          message(n),
      ];
      await tester.pump();
      expect(fixture.targetY(tester), closeTo(before, 1));
      fixture.rows.value = [
        for (var n = 100 + page * 20; n > 100 + (page - 1) * 20; n--)
          message(n),
        ...fixture.rows.value,
      ];
      await tester.pump();
      expect(fixture.targetY(tester), closeTo(before, 1));
      expect(identical(fixture.controller.position, scrollPosition), isTrue);
    }
    final spacers = find.descendant(
        of: find.byType(SearchHistoryEdgeSpace),
        matching: find.byType(SizedBox));
    for (final box in tester.widgetList<SizedBox>(spacers)) {
      expect(box.height, 0,
          reason: 'full pages must not retain half-screen gaps');
    }
    await fixture.dispose(tester);
  });

  testWidgets(
      'long text and changing row heights never drive extent correction',
      (tester) async {
    final fixture = _HistoryFixture();
    fixture.heights['message_100'] = 900;
    await fixture.centerTarget(tester);
    final before = fixture.targetY(tester);
    for (var seq = 80; seq <= 120; seq++) {
      if (seq != 100) fixture.heights['message_$seq'] = seq.isEven ? 1300 : 42;
    }
    fixture.rows.value = [for (var n = 120; n >= 80; n--) message(n)];
    await tester.pump();
    expect(fixture.targetY(tester), closeTo(before, 1));
    fixture.heights['message_101'] = 2100;
    fixture.heights['message_99'] = 2100;
    fixture.rows.value = List.of(fixture.rows.value);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump();
      expect(fixture.targetY(tester), closeTo(before, 1));
    }
    await fixture.dispose(tester);
  });
}
