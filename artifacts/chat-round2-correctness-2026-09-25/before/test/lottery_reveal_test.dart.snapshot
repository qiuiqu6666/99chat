import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_reveal_state.dart';

void main() {
  test('reveal resets on next issue and re-enabling', () {
    final state = LotteryRevealState();
    expect(state.isHidden('203'), false);
    state.toggle();
    expect(state.isHidden('203'), true);
    state.reveal('203');
    expect(state.isHidden('203'), false);
    expect(state.isHidden('204'), true);
    state.toggle();
    state.toggle();
    expect(state.isHidden('203'), true);
  });

  testWidgets(
      'preview and full page show results even when reveal was previously enabled',
      (tester) async {
    final state = lotteryRevealState('demo');
    if (!state.enabled) state.toggle();
    addTearDown(() {
      if (state.enabled) state.toggle();
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      LotteryLatestPreview(),
      LotteryLatestPreview(),
    ]))));
    expect(find.byKey(const ValueKey('lottery-reveal-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('lottery-reveal-cover')), findsNothing);
    expect(find.text('第 203 期'), findsNWidgets(2));
    expect(find.textContaining('特码 48'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('lottery-reveal-cover')), findsNothing);
    expect(find.text('已揭晓'), findsNothing);
    expect(find.text('眯牌·开'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: TestPage()));
    expect(find.byKey(const ValueKey('lottery-reveal-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('lottery-reveal-cover')), findsNothing);
    expect(find.textContaining('特码 48'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
