import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/feedback_page.dart';

class _PopupObserver extends NavigatorObserver {
  PopupRoute<dynamic>? popup;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) popup = route;
  }
}

void main() {
  testWidgets('support action opens the existing popup and preserves feedback',
      (tester) async {
    final observer = _PopupObserver();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [observer],
      home: const FeedbackPage(),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep my feedback');
    await tester.tap(find.byKey(const ValueKey('feedback-customer-service')));

    expect(observer.popup, isA<RawDialogRoute<void>>());
    expect(observer.popup!.barrierLabel, 'Dismiss customer service');
    // Verify navigation without mounting the live service's provider/network tree.
    navigator.currentState!.removeRoute(observer.popup!);
    await tester.pumpAndSettle();
    expect(find.text('Keep my feedback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
