import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_business_identity.dart';

void main() {
  test('each wallet family has one unambiguous card identity', () {
    for (final family in WalletBusinessFamily.values) {
      final identity = WalletBusinessIdentity.fromMap({
        'businessID': 'wallet_order',
        'customType': family.wireType,
        'type': family.wireType,
        'orderId': '7',
        'cardId': '${family.cardPrefix}:7',
      });
      expect(identity?.family, family);
      expect(identity?.expectedCardId, '${family.cardPrefix}:7');
    }
  });

  test('conflicting family and order fields are rejected', () {
    expect(
        WalletBusinessIdentity.fromMap({
          'customType': 'wallet_red_packet',
          'type': 'wallet_transfer',
          'orderId': '7',
        }),
        isNull);
    expect(
        WalletBusinessIdentity.fromMap({
          'type': 'wallet_transfer',
          'orderId': '7',
          'id': '8',
        }),
        isNull);
    expect(
        WalletBusinessIdentity.fromMap({
          'type': 'wallet_transfer',
          'orderId': '7',
          'cardId': 'rp:7',
        }),
        isNull);
    expect(
        WalletBusinessIdentity.fromMap({
          'businessID': 'another_business',
          'type': 'wallet_transfer',
          'orderId': '7',
        }),
        isNull);
  });

  test('cross-family numeric IDs alone do not prove the same order', () {
    final red = WalletBusinessIdentity.fromMap({
      'type': 'wallet_red_packet',
      'orderId': '7',
      'cardId': 'rp:7',
    })!;
    final transfer = WalletBusinessIdentity.fromMap({
      'type': 'wallet_transfer',
      'orderId': '7',
      'cardId': 'transfer:7',
    })!;
    expect(red.sharesConfirmedIdentityWith(transfer), isFalse);
    final sameClient = WalletBusinessIdentity.fromMap({
      'type': 'wallet_transfer',
      'orderId': '7',
      'cardId': 'transfer:7',
      'clientOrderId': 'shared-client',
    })!;
    final otherFamily = WalletBusinessIdentity.fromMap({
      'type': 'wallet_red_packet',
      'orderId': '7',
      'cardId': 'rp:7',
      'clientOrderId': 'shared-client',
    })!;
    expect(sameClient.sharesConfirmedIdentityWith(otherFamily), isTrue);
  });
}
