import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/chat_cards/chat_wallet_card_metrics.dart';

void main() {
  test('wallet card scale rejects invalid startup viewport values', () {
    expect(ChatWalletCardMetrics.boundedMobileScale(double.nan), 1);
    expect(ChatWalletCardMetrics.boundedMobileScale(double.infinity), 1);
    expect(ChatWalletCardMetrics.boundedMobileScale(-1), 1);
    expect(ChatWalletCardMetrics.boundedMobileScale(0), 1);
  });

  test('wallet card scale clamps extreme ScreenUtil geometry', () {
    expect(ChatWalletCardMetrics.boundedMobileScale(0.01), 0.5);
    expect(ChatWalletCardMetrics.boundedMobileScale(641), 1.5);
    expect(ChatWalletCardMetrics.boundedMobileScale(1.2), 1.2);
    expect(
      156 * ChatWalletCardMetrics.boundedMobileScale(641),
      lessThanOrEqualTo(234),
    );
  });
}
