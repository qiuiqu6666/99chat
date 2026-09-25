import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_repository.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/widgets/pay_method_sheet.dart';

const _platform = WalletPayMethodDto(
  id: '99',
  coin: '99币',
  net: '',
  bal: '46.24',
  fiat: '46.24',
  balMinor: 4624,
  scale: 2,
  color: Colors.blue,
  badgeColor: Colors.blue,
  badge: '99',
  platformCoin: true,
);

const _usdt = WalletPayMethodDto(
  id: 'USDT',
  coin: 'USDT',
  net: 'TRC20',
  bal: '1234567890.12',
  fiat: '1234567890.12',
  balMinor: 123456789012,
  scale: 2,
  color: Colors.green,
  badgeColor: Colors.red,
  badge: 'T',
);

void main() {
  for (final size in [const Size(375, 667), const Size(320, 568)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('payment rows fit $size at text scale $textScale',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = size * 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        WalletPayMethodDto? selected;

        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: const EdgeInsets.only(top: 24, bottom: 34),
            ),
            child: child!,
          ),
          home: Builder(builder: (context) {
            ScreenUtil.init(context, designSize: const Size(750, 1624));
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    selected = await showModalBottomSheet<WalletPayMethodDto>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const WalletPayMethodSheet(
                        items: [_platform, _usdt],
                        sel: _platform,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          }),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Amounts must stay inside their own tappable card, including wrapped
        // long balances. Checking only for RenderFlex errors misses clipping.
        for (final amount in [
          '46.24',
          '≈¥46.24',
          _usdt.bal,
          '≈¥${_usdt.fiat}'
        ]) {
          final text = find.text(amount);
          await tester.scrollUntilVisible(
            text,
            60,
            scrollable: find.descendant(
              of: find.byType(WalletPayMethodSheet),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.ancestor(of: text, matching: find.byType(InkWell));
          final textRect = tester.getRect(text);
          final cardRect = tester.getRect(card.first);
          expect(textRect.left, greaterThanOrEqualTo(cardRect.left));
          expect(textRect.right, lessThanOrEqualTo(cardRect.right));
          expect(textRect.top, greaterThanOrEqualTo(cardRect.top));
          expect(textRect.bottom, lessThanOrEqualTo(cardRect.bottom));
          expect(tester.takeException(), isNull);
        }

        await tester.ensureVisible(find.text('USDT'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('USDT'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm Payment'));
        await tester.pumpAndSettle();
        expect(selected?.id, 'USDT');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
