import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_anchor_scroll_controller.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_scroll_anchor.dart';

void main() {
  testWidgets('layout preserves the visible row and active drag after trimming',
      (tester) async {
    final controller = ConversationAnchorScrollController();
    var rows = List<String?>.generate(100, (i) => 'row$i');
    late StateSetter rebuild;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return ListView.builder(
          controller: controller,
          itemExtent: 88,
          itemCount: rows.length,
          itemBuilder: (_, i) => Text(rows[i]!, key: ValueKey(rows[i]!)));
    })));
    controller.jumpTo(2000);
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(controller.position.isScrollingNotifier.value, isTrue);
    final before = tester.getTopLeft(find.byKey(const ValueKey('row25'))).dy;
    var previous = rows;
    controller.resolveLayoutOffset = (pixels) {
      if (identical(previous, rows)) return null;
      final anchor = ConversationScrollAnchor.capture(previous,
          offset: pixels, extent: 88);
      previous = rows;
      return anchor?.restore(rows, extent: 88);
    };
    rebuild(() => rows = rows.sublist(10));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('row25'))).dy,
        closeTo(before, 0.1));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('row25'))).dy,
        closeTo(before - 30, 0.1));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
