import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/qr_app_payload.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/qr_gallery_result_sheet.dart';

void main() {
  String code(String id, String name) => QrAppPayload.encode(
      baseUrl: 'https://99chat.vip',
      type: QrAppPayloadType.user,
      id: id,
      name: name);

  Future<void> openSheet(WidgetTester tester, List<String> values,
      void Function(String?) onResult) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () async {
                onResult(await QrGalleryResultSheet.show(context, values));
              },
              child: const Text('Open')));
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('does not choose a target until the selected row is tapped',
      (tester) async {
    final a = code('a', 'Alice');
    final b = code('b', 'Bob');
    var completed = false;
    String? selected;
    await openSheet(tester, [a, b], (value) {
      completed = true;
      selected = value;
    });
    expect(completed, isFalse);
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(selected, b);
  });

  testWidgets('dismissal returns no target', (tester) async {
    var selected = 'not completed';
    await openSheet(tester, [code('a', 'Alice'), code('b', 'Bob')],
        (value) => selected = value ?? 'cancelled');
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(selected, 'cancelled');
  });

  testWidgets('many long codes scroll without overflow and hide login secrets',
      (tester) async {
    final values = List.generate(12, (i) => code('user-$i', 'Long name ' * 25));
    const login = '{"type":"web_login","sessionId":"do-not-display","v":1}';
    String? selected;
    await openSheet(tester, [login, ...values], (value) => selected = value);
    expect(find.textContaining('do-not-display'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.textContaining('user-11'), 180,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.textContaining('user-11'));
    await tester.pumpAndSettle();
    expect(selected, values.last);
    expect(tester.takeException(), isNull);
  });
}
