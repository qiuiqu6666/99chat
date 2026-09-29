import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/agent_rebate_floating_entry.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_float_prefs.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('expanded layout and reentry preserve the dragged anchor', (tester) async {
    const id = 'preserved-anchor-test';
    const saved = Offset(730, 510);
    await AgentRebateFloatPrefs.instance.writeOffset(id, saved);
    await AgentRebateFloatPrefs.instance.writeExpanded(id, false);
    Widget page() => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: Stack(fit: StackFit.expand, children: [
        AgentRebateFloatingEntry(
          theme: const TUITheme(), conversationId: id,
          onOpenDescendants: () {}, onOpenRebate: () {}, onOpenHistory: () {},
        ),
      ])),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final original = tester.getCenter(find.text('显'));
    await tester.tap(find.text('显'));
    await tester.pumpAndSettle();
    expect(AgentRebateFloatPrefs.instance.readOffsetSync(id), saved);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(AgentRebateFloatPrefs.instance.readOffsetSync(id), saved);
    await tester.tap(find.text('隐'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('显')), original);
    expect(AgentRebateFloatPrefs.instance.readOffsetSync(id), saved);
  });

  testWidgets('expands and opens downline and history actions', (tester) async {
    var descendantsOpenCount = 0;
    var rebateOpenCount = 0;
    var historyOpenCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              AgentRebateFloatingEntry(
                theme: const TUITheme(),
                conversationId: 'actions-test',
                onOpenDescendants: () => descendantsOpenCount++,
                onOpenRebate: () => rebateOpenCount++,
                onOpenHistory: () => historyOpenCount++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('显'), findsOneWidget);
    expect(find.text('查'), findsNothing);

    await tester.tap(find.text('显'));
    await tester.pumpAndSettle();

    expect(find.text('查'), findsOneWidget);
    expect(find.text('反'), findsOneWidget);
    expect(find.text('历'), findsOneWidget);
    expect(find.text('隐'), findsOneWidget);

    await tester.tap(find.text('查'));
    await tester.tap(find.text('反'));
    await tester.tap(find.text('历'));
    expect(descendantsOpenCount, 1);
    expect(rebateOpenCount, 1);
    expect(historyOpenCount, 1);

    await tester.tap(find.text('隐'));
    await tester.pumpAndSettle();
    expect(find.text('显'), findsOneWidget);
    expect(find.text('查'), findsNothing);
    expect(find.text('反'), findsNothing);
    expect(find.text('历'), findsNothing);
  });
}
