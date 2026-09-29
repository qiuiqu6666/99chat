import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/conversation_feed/conversation_feed_body.dart';

class _RowProbe extends StatefulWidget {
  const _RowProbe(this.id, this.created, {super.key});
  final String id;
  final Map<String, int> created;
  @override
  State<_RowProbe> createState() => _RowProbeState();
}

class _RowProbeState extends State<_RowProbe> {
  @override
  void initState() {
    super.initState();
    widget.created.update(widget.id, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => Text(widget.id);
}

void main() {
  testWidgets('divider reserves the same row height and keeps child taps',
      (tester) async {
    final childKey = GlobalKey();
    var taps = 0;
    Widget frame(bool divider) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 72,
              child: ConversationFeedRowFrame(
                showDivider: divider,
                dividerInset: 80,
                dividerColor: Colors.red,
                child: GestureDetector(
                  key: childKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(frame(true));
    final childElement = childKey.currentContext;
    expect(tester.getSize(find.byKey(childKey)).height, closeTo(71.4, 0.001));
    await tester.tapAt(const Offset(150, 71));
    expect(taps, 1);
    await tester.pumpWidget(frame(false));
    expect(childKey.currentContext, same(childElement));
    expect(tester.getSize(find.byKey(childKey)), const Size(200, 72));
    await tester.tapAt(const Offset(150, 71.8));
    expect(taps, 2);
    await tester.pumpWidget(frame(true));
    expect(childKey.currentContext, same(childElement));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('feed row state survives reorder and pagination divider changes',
      (tester) async {
    final created = <String, int>{};
    final scroll = ScrollController();
    Widget feed(List<String> ids) => MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: scroll,
              itemExtent: 72,
              itemCount: ids.length,
              findChildIndexCallback: (key) =>
                  ids.indexOf((key as ValueKey).value),
              itemBuilder: (context, index) => ConversationFeedRowFrame(
                key: ValueKey(ids[index]),
                showDivider: index != ids.length - 1,
                dividerInset: 72,
                dividerColor: Colors.grey,
                child:
                    _RowProbe(ids[index], created, key: ValueKey(ids[index])),
              ),
            ),
          ),
        );
    await tester.pumpWidget(feed(['a', 'b', 'c']));
    final original = tester.state(find.byType(_RowProbe).at(1));
    await tester.pumpWidget(feed(['b', 'a', 'c']));
    expect(tester.state(find.byType(_RowProbe).at(0)), same(original));
    await tester.pumpWidget(feed(['b', 'a', 'c', 'd']));
    expect(created, {'a': 1, 'b': 1, 'c': 1, 'd': 1});
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
