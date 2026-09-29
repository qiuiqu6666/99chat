import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bottom in [0.0, 34.0]) {
    for (final location in ['top', 'middle', 'bottom']) {
      testWidgets('selection preserves $location rows with inset $bottom', (tester) async {
        final editing = ValueNotifier(false);
        final scroll = ScrollController();
        addTearDown(editing.dispose);
        addTearDown(scroll.dispose);
        const viewport = Key('viewport');
        const bar = Key('bar');
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: bottom),
              viewPadding: EdgeInsets.only(bottom: bottom)),
          child: ValueListenableBuilder<bool>(
            valueListenable: editing,
            builder: (context, selected, _) => Scaffold(
              bottomNavigationBar: SizedBox(
                key: bar,
                child: selected ? SafeArea(top: false,
                  child: const SizedBox(height: kBottomNavigationBarHeight,
                    child: Center(child: Text('Actions'))))
                  : SizedBox(height: kBottomNavigationBarHeight + bottom,
                    child: const Text('Navigation')),
              ),
              body: Scaffold(
                bottomNavigationBar: const SizedBox.shrink(),
                body: ListView.builder(
                  key: viewport, controller: scroll, itemExtent: 72,
                  itemCount: 60,
                  itemBuilder: (_, index) => Text('row-$index', key: ValueKey(index)),
                ),
              ),
            ),
          ),
        )));
        if (location == 'middle') scroll.jumpTo(1200);
        if (location == 'bottom') scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final row = (scroll.offset / 72).ceil();
        final originalRow = tester.getRect(find.byKey(ValueKey(row)));
        final originalViewport = tester.getRect(find.byKey(viewport));
        final originalBar = tester.getRect(find.byKey(bar));
        final originalOffset = scroll.offset;
        for (final selected in [true, false, true, false]) {
          editing.value = selected;
          await tester.pump();
          expect(tester.getRect(find.byKey(ValueKey(row))), originalRow);
          expect(tester.getRect(find.byKey(viewport)), originalViewport);
          expect(tester.getRect(find.byKey(bar)), originalBar);
          expect(scroll.offset, originalOffset);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
