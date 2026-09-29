import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/az_list_view.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  testWidgets(
      'inserting rows above preserves the visible contact and its position',
      (tester) async {
    final errorHandler = FlutterError.onError;
    Widget page(List<String> names) {
      final rows = names
          .map((name) => ISuspensionBeanImpl(memberInfo: name, tagIndex: 'A'))
          .toList();
      return MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  height: 400,
                  child: AZListViewContainer(
                    memberList: rows,
                    isShowIndexBar: false,
                    itemIdentity: (row) => row.memberInfo as String,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 50, child: Text(names[i])),
                  ))));
    }

    final names = List.generate(60, (i) => 'row-$i');
    await tester.pumpWidget(page(names));
    await tester.pumpAndSettle();
    FlutterError.onError = errorHandler;
    await tester.drag(find.byType(AZListViewContainer), const Offset(0, -420));
    await tester.pumpAndSettle();
    FlutterError.onError = errorHandler;
    final name = names.firstWhere((name) {
      final finder = find.text(name);
      if (finder.evaluate().isEmpty) return false;
      final y = tester.getTopLeft(finder).dy;
      return y >= 0 && y < 400;
    });
    expect(name, isNot('row-0'));
    final before = tester.getTopLeft(find.text(name)).dy;
    await tester.pumpWidget(page(['new-a', 'new-b', ...names]));
    await tester.pumpAndSettle();
    FlutterError.onError = errorHandler;
    expect(tester.getTopLeft(find.text(name)).dy, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });
}
