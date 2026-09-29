import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/pages/profile_signature_edit_page.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required String initialSignature,
    required Future<bool> Function(String text) onSave,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: DefaultThemeData(),
        child: MaterialApp(
          home: Scaffold(
            body: ProfileSignatureEditPage(
              initialSignature: initialSignature,
              embedded: true,
              onSave: onSave,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('完成 is disabled when text equals initialSignature',
      (tester) async {
    final saveCalls = <String>[];
    await pumpPage(
      tester,
      initialSignature: 'hello',
      onSave: (text) async {
        saveCalls.add(text);
        return true;
      },
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(saveCalls, isEmpty);
  });

  testWidgets('完成 is enabled after a one-character change', (tester) async {
    await pumpPage(
      tester,
      initialSignature: 'hello',
      onSave: (text) async => true,
    );

    await tester.enterText(find.byType(TextField), 'hello!');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('_submit does not call onSave when unchanged', (tester) async {
    final saveCalls = <String>[];
    await pumpPage(
      tester,
      initialSignature: 'hello',
      onSave: (text) async {
        saveCalls.add(text);
        return true;
      },
    );

    await tester.enterText(find.byType(TextField), 'hello!');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(saveCalls, isEmpty);
  });
}
