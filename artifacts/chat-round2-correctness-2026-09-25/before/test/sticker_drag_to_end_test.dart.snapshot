import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_organize_grid.dart';

void main() {
  for (final destination in ['last sticker', 'empty cell', 'space below']) {
    testWidgets(
        'drag to $destination shifts all earlier stickers before release',
        (tester) async {
      final ids = ['a', 'b', 'c', 'd', 'e'];
      var commits = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => StickerOrganizeGrid(
                  ids: List.of(ids),
                  organizing: true,
                  addTile: const Text('+'),
                  itemBuilder: (_, index) => ColoredBox(
                      color: Colors.blue,
                      child: Center(child: Text(ids[index]))),
                  onMove: (from, to) => setState(() {
                    commits++;
                    final index = ids.indexOf(to);
                    ids.insert(index, ids.removeAt(ids.indexOf(from)));
                  }),
                )),
      )));
      final positions = [
        for (final id in ids) tester.getCenter(find.byKey(ValueKey(id)))
      ];
      final end = switch (destination) {
        'empty cell' =>
          positions.last + Offset(positions[1].dx - positions[0].dx, 0),
        'space below' => Offset(positions.last.dx,
            tester.getRect(find.byType(GridView)).bottom - 70),
        _ => positions.last,
      };
      final gesture = await tester.startGesture(positions.first);
      await gesture.moveTo(end);
      await tester.pump();
      for (var i = 1; i < ids.length; i++) {
        expect(tester.getCenter(find.byKey(ValueKey(ids[i]))), positions[i - 1],
            reason: '${ids[i]} must shift forward while pointer is still down');
      }
      expect(tester.getCenter(find.byKey(const ValueKey('a'))), positions.last);
      expect(commits, 0);
      await gesture.up();
      await tester.pump();
      expect(ids, ['b', 'c', 'd', 'e', 'a']);
      expect(commits, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
