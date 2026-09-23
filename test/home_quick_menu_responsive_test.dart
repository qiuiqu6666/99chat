import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/home_quick_action_tile.dart';

void main() {
  for (final size in [const Size(280, 480), const Size(320, 568), const Size(390, 844), const Size(844, 390), const Size(768, 1024)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('menu fits $size with text scale $textScale', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = size * 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        final safe = size.width > size.height
            ? const EdgeInsets.fromLTRB(44, 0, 44, 21)
            : const EdgeInsets.only(top: 44, bottom: 34);
        await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: safe, textScaler: TextScaler.linear(textScale)), child: child!),
          home: Builder(builder: (context) => Scaffold(appBar: AppBar(actions: [
            IconButton(icon: const Icon(Icons.add), onPressed: () async {
              final constraints = homeQuickMenuConstraints(MediaQuery.of(context));
              selected = await showMenu<String>(context: context,
                constraints: constraints,
                menuPadding: const EdgeInsets.only(top: 18, bottom: 6),
                shape: HomeQuickMenuShape(arrowX: constraints.maxWidth - 24),
                position: RelativeRect.fromLTRB(size.width - constraints.maxWidth - safe.right - 12, safe.top + 56, safe.right + 12, 0),
                items: [for (final entry in {'searchAdd': 'Search & Add', 'createGroup': 'Create Group', 'scanQRCode': 'Scan'}.entries)
                  PopupMenuItem<String>(value: entry.key, padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: HomeQuickActionTile(id: entry.key, title: entry.value, divider: entry.key != 'scanQRCode'))]);
            }),
          ]))),
        ));
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rect = tester.getRect(find.byType(SingleChildScrollView).last);
        expect(rect.left, greaterThanOrEqualTo(safe.left));
        expect(rect.right, lessThanOrEqualTo(size.width - safe.right));
        expect(rect.top, greaterThanOrEqualTo(safe.top));
        expect(rect.bottom, lessThanOrEqualTo(size.height - safe.bottom));
        await tester.ensureVisible(find.text('Scan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scan'));
        await tester.pumpAndSettle();
        expect(selected, 'scanQRCode');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
