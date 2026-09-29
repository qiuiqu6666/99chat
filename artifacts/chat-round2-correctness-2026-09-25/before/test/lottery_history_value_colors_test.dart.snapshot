import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  testWidgets('latest draw tags color parity size element and wave',
      (tester) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, isDark, __) => MaterialApp(
        theme: isDark ? ThemeData.dark() : ThemeData.light(),
        home: const TestPage(),
      ),
    ));

    void expectTagColor(String label, Color color) {
      expect(
          tester
              .widgetList<Text>(find.text(label))
              .any((text) => text.style?.color == color),
          isTrue);
    }

    expectTagColor('双', const Color(0xFFEF2F4E));
    expectTagColor('大', const Color(0xFFEF2F4E));
    expectTagColor('火', const Color(0xFFD72C48));
    expectTagColor('蓝波', const Color(0xFF007AFF));
    dark.value = true;
    await tester.pumpAndSettle();
    expectTagColor('火', const Color(0xFFFF788A));
    expectTagColor('蓝波', const Color(0xFF007AFF));
  });

  testWidgets('history values use distinct colors in light and dark themes',
      (tester) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: dark,
      builder: (_, isDark, __) => MaterialApp(
        theme: isDark ? ThemeData.dark() : ThemeData.light(),
        home: const TestPage(),
      ),
    ));

    Future<void> check(Color fireColor) async {
      await tester.ensureVisible(find.text('09-21 17:04'));
      await tester.pump();
      bool hasColor(String label, Color color) => tester
          .widgetList<Text>(find.text(label))
          .any((text) => text.style?.color == color);
      expect(hasColor('单', const Color(0xFF007AFF)), isTrue);
      expect(hasColor('双', const Color(0xFFEF2F4E)), isTrue);
      expect(hasColor('小', const Color(0xFF007AFF)), isTrue);
      expect(hasColor('大', const Color(0xFFEF2F4E)), isTrue);
      expect(hasColor('火', fireColor), isTrue);
    }

    await check(const Color(0xFFD72C48));
    dark.value = true;
    await tester.pumpAndSettle();
    await check(const Color(0xFFFF788A));
  });
}
