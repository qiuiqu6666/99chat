import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/life_payment/life_payment_city_index_bar.dart';
import 'package:tencent_cloud_chat_demo/country_list_pick-1.0.1+5/lib/selection_list.dart';
import 'package:tencent_cloud_chat_demo/country_list_pick-1.0.1+5/lib/support/code_country.dart';

class RowTag extends ISuspensionBean {
  RowTag(this.tag);
  final String tag;
  @override
  String getSuspensionTag() => tag;
}

Finder letter(String tag) => find.descendant(
    of: find.byType(IndexBar), matching: find.text(tag));

void main() {
  testWidgets('dragging the alphabet repaints the selected letter immediately',
      (tester) async {
    final rows = List.generate(40, (i) => RowTag('ABCD'[i ~/ 10]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 320,
          child: AzListView(
            data: rows,
            itemCount: rows.length,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row-$i')),
            indexBarData: const ['A', 'B', 'C', 'D'],
            indexBarItemHeight: 30,
            indexBarOptions: const IndexBarOptions(
              textStyle: TextStyle(color: Colors.grey),
              selectTextStyle: TextStyle(color: Colors.white),
              selectItemDecoration: BoxDecoration(color: Colors.blue),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(tester.getCenter(letter('A')));
    await drag.moveBy(const Offset(0, 31));
    await tester.pump();
    await drag.moveTo(tester.getCenter(letter('D')));
    await tester.pump();
    expect(tester.widget<Text>(letter('D')).style!.color, Colors.white);
    expect(tester.widget<Text>(letter('A')).style!.color, Colors.grey);
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('scroll selection persists with both pressed and selected styles',
      (tester) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final rows = List.generate(40, (i) => RowTag('ABCD'[i ~/ 10]));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      height: 320,
      child: AzListView(
        data: rows,
        itemCount: rows.length,
        itemScrollController: controller,
        itemPositionsListener: positions,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row-$i')),
        indexBarData: const ['A', 'B', 'C', 'D'],
        indexBarOptions: const IndexBarOptions(
          textStyle: TextStyle(color: Colors.grey),
          selectTextStyle: TextStyle(color: Colors.white),
          selectItemDecoration: BoxDecoration(color: Colors.blue),
          downTextStyle: TextStyle(color: Colors.yellow),
          downItemDecoration: BoxDecoration(color: Colors.red),
        ),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('A')).style!.color, Colors.white);
    controller.jumpTo(index: 11);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('B')).style!.color, Colors.white);
    expect(tester.widget<Text>(letter('A')).style!.color, Colors.grey);
    await tester.tap(letter('C'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('C')).style!.color, Colors.white);
    await tester.dragFrom(const Offset(150, 200), const Offset(0, 650));
    await tester.pumpAndSettle();
    final visible = visibleSuspensionTag(rows, positions.itemPositions.value);
    expect(visible, isNot('C'));
    expect(tester.widget<Text>(letter(visible)).style!.color, Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('city index highlights the resolved group after a missing letter',
      (tester) async {
    final controller = ItemScrollController();
    final positions = ItemPositionsListener.create();
    final rows = List.generate(30, (i) => RowTag('AHZ'[i ~/ 10]));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      height: 500,
      child: Stack(children: [
        AzListView(
          data: rows,
          itemCount: rows.length,
          itemScrollController: controller,
          itemPositionsListener: positions,
          itemBuilder: (_, i) => SizedBox(height: 60, child: Text('city-$i')),
          indexBarData: const [],
        ),
        LifePaymentCityIndexBar(
          items: rows,
          itemPositionsListener: positions,
          availableInitials: const ['A', 'H', 'Z'],
          onSelect: (tag) => LifePaymentCityIndexBar.jumpToTag(
              controller: controller, data: rows, tag: tag),
        ),
      ]),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(letter('G'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('H')).style!.color, Colors.white);
    expect(tester.widget<Text>(letter('G')).style!.color, isNot(Colors.white));
    controller.jumpTo(index: 21);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('Z')).style!.color, Colors.white);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('visible group ignores stale, cached, and offscreen positions', () {
    final data = [RowTag('A'), RowTag('B'), RowTag('C')];
    expect(visibleSuspensionTag(data, const [
      ItemPosition(index: 0, itemLeadingEdge: -1, itemTrailingEdge: 0),
      ItemPosition(index: 1, itemLeadingEdge: -.1, itemTrailingEdge: .2),
      ItemPosition(index: 2, itemLeadingEdge: .2, itemTrailingEdge: .6),
      ItemPosition(index: 100, itemLeadingEdge: -.2, itemTrailingEdge: .1),
    ]), 'B');
    expect(visibleSuspensionTag([], const [
      ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 1),
    ]), '');
  });

  testWidgets('replacement data and position listener keep selection in sync',
      (tester) async {
    final controller = ItemScrollController();
    Widget page(List<RowTag> rows, ItemPositionsListener positions) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 300, child: AzListView(
        data: rows, itemCount: rows.length,
        itemScrollController: controller, itemPositionsListener: positions,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row-$i')),
        indexBarData: const ['A', 'B', 'C', 'D'],
        indexBarOptions: const IndexBarOptions(
          selectTextStyle: TextStyle(color: Colors.white),
          selectItemDecoration: BoxDecoration(color: Colors.blue),
          textStyle: TextStyle(color: Colors.grey),
        ),
      ))),
    );
    final oldPositions = ItemPositionsListener.create();
    await tester.pumpWidget(page(List.generate(30, (_) => RowTag('A')), oldPositions));
    await tester.pumpAndSettle();
    final newPositions = ItemPositionsListener.create();
    await tester.pumpWidget(page(List.generate(30, (i) => RowTag(i < 10 ? 'C' : 'D')), newPositions));
    await tester.pumpAndSettle();
    controller.jumpTo(index: 12);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('D')).style!.color, Colors.white);
    expect(newPositions.itemPositions.value, isNotEmpty);
    await tester.pumpWidget(page([], newPositions));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(letter('D')).style!.color, Colors.grey);
    expect(tester.takeException(), isNull);
  });

  testWidgets('country selection accounts for the header on scroll and tap',
      (tester) async {
    final countries = List.generate(36, (i) => CountryCode(
      name: '${'ABC'[i ~/ 12]}${(i % 12).toString().padLeft(2, '0')}',
      flagUri: 'flags/af.png', code: 'AF', dialCode: '+93',
    ));
    await tester.pumpWidget(MaterialApp(home: SelectionList(
      countries, countries.first, useUiOverlay: false,
      countryBuilder: (_, country) => SizedBox(height: 50, child: Text(country.name!)),
    )));
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('A')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('B')).style!.color, isNot(Colors.white));
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('B00')).dy, closeTo(0, 1));
    expect(tester.widget<Text>(find.text('B')).style!.color, Colors.white);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'C');
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
