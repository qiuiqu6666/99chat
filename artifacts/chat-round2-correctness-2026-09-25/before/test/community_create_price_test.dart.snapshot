import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_create_limit_api.dart';

void main() {
  test('Community price uses backend minor units for 99 currency', () {
    final limits = GroupCreateLimitsResponse.fromJson({
      'enabled': true,
      'communityCreatePrice': {'currency': '99', 'amountMinor': 1000000},
    });

    expect(limits.communityCreatePrice?.isValid, isTrue);
    expect(limits.communityCreatePrice?.displayAmount, '10000');
    expect(limits.communityCreatePrice?.currency, '99');
  });

  test('USDT price uses six decimal minor units', () {
    final price = CommunityCreatePrice.fromJson({
      'currency': 'USDT',
      'amountMinor': 1250000,
    });
    expect(price.isValid, isTrue);
    expect(price.displayAmount, '1.25');
  });
}
