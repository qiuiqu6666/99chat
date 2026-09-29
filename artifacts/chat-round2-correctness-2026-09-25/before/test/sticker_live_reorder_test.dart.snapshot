import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/sticker/sticker_organize_grid.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets('live preview before release, cancel=$cancel', (tester) async {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final saved = Completer<void>();
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
                  onMove: (from, to) async {
                    commits++;
                    await saved.future;
                    setState(() {
                      final target = ids.indexOf(to);
                      ids.insert(target, ids.removeAt(ids.indexOf(from)));
                    });
                  },
                )),
      )));
      final a = tester.getCenter(find.byKey(const ValueKey('a')));
      final b = tester.getCenter(find.byKey(const ValueKey('b')));
      final e = tester.getCenter(find.byKey(const ValueKey('e')));
      final gesture = await tester.startGesture(a);
      await gesture.moveTo(b);
      await tester.pump();
      expect(tester.getCenter(find.byKey(const ValueKey('b'))), a,
          reason: 'neighbor must move before releasing the pointer');
      expect(commits, 0);
      await gesture.moveTo(e);
      await tester.pump();
      expect(tester.getCenter(find.byKey(const ValueKey('a'))), e);
      expect(commits, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getCenter(find.byKey(const ValueKey('a'))), e,
          reason: 'stationary pointer must not oscillate between positions');
      if (cancel) {
        await gesture.moveTo(const Offset(-30, -30));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      if (cancel) {
        expect(commits, 0);
        expect(tester.getCenter(find.byKey(const ValueKey('a'))), a);
      } else {
        expect(commits, 1);
        expect(tester.getCenter(find.byKey(const ValueKey('a'))), e,
            reason: 'hold final preview while persistence is pending');
        saved.complete();
        await tester.pump();
        expect(ids, ['b', 'c', 'd', 'e', 'a', 'f']);
        expect(tester.getCenter(find.byKey(const ValueKey('a'))), e);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
