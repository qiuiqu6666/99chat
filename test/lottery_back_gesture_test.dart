import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_drawer.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/test_page.dart';

void main() {
  testWidgets(
      'expanded lottery returns to chat on right edge swipe without shrinking',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showLotteryDrawer(context, groupUid: 'gesture-test'),
        child: const Text('聊天'),
      ),
    ))));
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lottery-preview-open')));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsOneWidget);
    await tester.dragFrom(const Offset(10, 300), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsOneWidget);
    await tester.dragFrom(const Offset(10, 300), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsOneWidget);
    await tester.tap(find.text('智能预测'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('五行').first, const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsOneWidget);
    expect(
        ModalRoute.of(tester.element(find.byType(TestPage)))!
            .reverseTransitionDuration,
        Duration.zero);
    await tester.dragFrom(const Offset(10, 250), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.byType(TestPage), findsNothing);
    expect(find.text('聊天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lottery root route does not expose a back gesture',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TestPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lottery-back-edge')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
