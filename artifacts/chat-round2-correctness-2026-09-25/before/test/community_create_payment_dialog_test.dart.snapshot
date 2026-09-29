import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_create_limit_api.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/community_create_payment_dialog.dart';

const price = CommunityCreatePrice(currency: '99', amountMinor: 1000000);

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('review balance and PIN at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        ScreenUtil.init(context, designSize: const Size(750, 1624));
        return Scaffold(
            body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                      context: context,
                      builder: (_) => CommunityCreatePaymentDialog(
                          price: price, loadBalance: () async => 1288000));
                },
                child: const Text('Open')));
      })));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('12880'), findsOneWidget);
      expect(find.text('2880'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final confirm = find.byKey(const ValueKey('community-payment-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(find.byType(Checkbox), findsNothing);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(PayPasswordPrompt), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final digit in ['1', '2', '3', '4', '5']) {
        await tester.tap(find.text(digit));
        await tester.pumpAndSettle();
      }
      expect(result, isNull);
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();
      expect(result, '123456');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'balance failure can retry and insufficient funds cannot continue',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: CommunityCreatePaymentDialog(
      price: price,
      loadBalance: () async {
        if (++attempts == 1) throw StateError('offline');
        return 900000;
      },
    )));
    await tester.pumpAndSettle();
    final retry = find.text('Could not load balance. Retry');
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('9000'), findsOneWidget);
    expect(find.text('Insufficient balance. Short by'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('community-payment-confirm')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
