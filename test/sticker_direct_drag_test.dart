import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_organize_grid.dart';

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    for (final target in ['b', 'e']) {
      testWidgets('$kind directly drags a to $target without holding',
          (tester) async {
        final ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
        var taps = 0;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
          body: StatefulBuilder(
              builder: (context, setState) => StickerOrganizeGrid(
                    ids: List.of(ids),
                    organizing: true,
                    addTile: const Text('+'),
                    itemBuilder: (_, index) => GestureDetector(
                      onTap: () => taps++,
                      child: ColoredBox(
                          key: ValueKey('tile-${ids[index]}'),
                          color: Colors.blue,
                          child: Center(child: Text(ids[index]))),
                    ),
                    onMove: (from, to) => setState(() {
                      final dest = ids.indexOf(to);
                      ids.insert(dest, ids.removeAt(ids.indexOf(from)));
                    }),
                  )),
        )));
        final start = tester.getCenter(find.byKey(const ValueKey('tile-a')));
        final end = tester.getCenter(find.byKey(ValueKey('tile-$target')));
        final gesture = await tester.startGesture(start, kind: kind);
        for (var step = 1; step <= 5; step++) {
          await gesture.moveTo(Offset.lerp(start, end, step / 5)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump();
        expect(ids.indexOf('a'), target == 'b' ? 1 : 4);
        expect(taps, 0);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      });
    }
  }
}
