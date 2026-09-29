import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_success_view.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';

void main() {
  testWidgets('success screen updates colors and system bars with theme',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, value, __) => MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: value,
        home: const FeedbackSuccessView(),
      ),
    ));
    for (final dark in [false, true, false]) {
      mode.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppColors.card(dark: dark));
      expect(
          tester.widget<Text>(find.text('Submitted successfully')).style!.color,
          AppColors.text(dark: dark));
      final overlay = tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
          .value;
      expect(overlay.systemNavigationBarColor, AppColors.card(dark: dark));
      expect(overlay.statusBarIconBrightness,
          dark ? Brightness.light : Brightness.dark);
      final button = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('feedback-success-done')));
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      expect(button.style!.backgroundColor!.resolve({}),
          dark ? const Color(0xFF176DD9) : AppColors.primaryBlue);
      expect(tester.takeException(), isNull);
    }
  });
}
