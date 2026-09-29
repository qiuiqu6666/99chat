import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_organize_grid.dart';

void main() {
  testWidgets('organize shakes, drag reorders, add stays fixed, done stops',
      (tester) async {
    var organizing = false;
    final ids = ['a', 'b', 'c', 'd', 'e'];
    var moves = 0;
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        return Scaffold(
          appBar: AppBar(actions: [
            TextButton(
              onPressed: () => setState(() => organizing = !organizing),
              child: Text(organizing ? 'Done' : 'Organize'),
            ),
          ]),
          body: StickerOrganizeGrid(
            ids: List.of(ids),
            organizing: organizing,
            addTile: const ColoredBox(
                key: ValueKey('add'), color: Colors.white, child: Text('+')),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => taps++,
              child: ColoredBox(
                key: ValueKey('tile-${ids[index]}'),
                color: Colors.blue,
                child: Center(child: Text(ids[index])),
              ),
            ),
            onMove: (from, to) => setState(() {
              final target = ids.indexOf(to);
              ids.insert(target, ids.removeAt(ids.indexOf(from)));
              moves++;
            }),
          ),
        );
      }),
    ));
    expect(find.byType(LongPressDraggable<String>), findsNothing);
    final addPosition = tester.getTopLeft(find.byKey(const ValueKey('add')));
    await tester.tap(find.text('Organize'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final transform = find.descendant(
        of: find.byKey(const ValueKey('a')), matching: find.byType(Transform));
    final firstMatrix =
        tester.widget<Transform>(transform.first).transform.clone();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Transform>(transform.first).transform,
        isNot(firstMatrix));

    final start = tester.getCenter(find.byKey(const ValueKey('tile-a')));
    final end = tester.getCenter(find.byKey(const ValueKey('tile-d')));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(ids, ['b', 'c', 'd', 'a', 'e']);
    expect(moves, 1);
    expect(taps, 0, reason: 'drag must not open the delete confirmation');
    expect(tester.getTopLeft(find.byKey(const ValueKey('add'))), addPosition);

    // Dropping on the fixed add tile must not move a sticker.
    final cancel = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('tile-b'))));
    await tester.pump(const Duration(milliseconds: 220));
    await cancel.moveTo(tester.getCenter(find.byKey(const ValueKey('add'))));
    await tester.pump();
    await cancel.up();
    await tester.pump();
    expect(moves, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(LongPressDraggable<String>), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag near bottom scrolls to stickers on later rows',
      (tester) async {
    final ids = List.generate(40, (index) => '$index');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 320,
            child: StickerOrganizeGrid(
              ids: ids,
              organizing: true,
              addTile: const Text('+'),
              itemBuilder: (_, index) => ColoredBox(
                key: ValueKey('item-$index'),
                color: Colors.blue,
                child: Text('$index'),
              ),
              onMove: (_, __) {},
            ),
          ),
        ),
      ),
    ));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('item-0'))));
    await tester.pump(const Duration(milliseconds: 220));
    final viewport = tester.getRect(find.byType(GridView));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 5));
    await tester.pump(const Duration(milliseconds: 400));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
