import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_claim_action.dart';
import 'package:tencent_cloud_chat_demo/src/services/red_packet_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  DioError error(int status, String code) => DioError(
        requestOptions: RequestOptions(path: '/wallet/red-packet/3525/claim'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/wallet/red-packet/3525/claim'),
          statusCode: status,
          data: {'code': code},
        ),
      );

  test('200 with id zero finishes before balance refresh', () async {
    final balance = Completer<void>();
    final result = await RedPacketClaimAction.claim(
      '3525',
      ownerUserId: 'claim-action-test-200',
      request: (_) async => const WalletOrderResult(
        ok: true,
        state: WalletOrderState.success,
        data: {
          'id': 0,
          'packetId': 3525,
          'amount': 1888,
          'createdAt': '2026-09-25T12:53:40Z',
        },
      ),
      refreshBalance: () => balance.future,
    );
    expect(result.claimed, isTrue);
    expect(result.newlyClaimed, isTrue);
    expect(result.amountMinor, 1888);
    expect(result.claimedAtMillis, isNotNull);
    expect(balance.isCompleted, isFalse);
    expect(
      RedPacketLocalStore.instance
          .peekOpened(
            orderId: '3525',
            ownerUserId: 'claim-action-test-200',
          )
          ?.claimAmountMinor,
      1888,
    );
    balance.complete();
  });

  test('409 after retry is claimed with cached amount', () async {
    await RedPacketLocalStore.instance.markOpened(
      orderId: '3525',
      ownerUserId: 'claim-action-test-409',
      claimed: true,
      claimAmountMinor: 1888,
    );
    final result = await RedPacketClaimAction.claim(
      '3525',
      ownerUserId: 'claim-action-test-409',
      request: (_) => Future.error(error(409, 'ALREADY_CLAIMED')),
      refreshBalance: () async {},
    );
    expect(result.claimed, isTrue);
    expect(result.newlyClaimed, isFalse);
    expect(result.amountMinor, 1888);
  });

  test('409 without cached amount still counts as claimed', () async {
    final result = await RedPacketClaimAction.claim(
      '3527',
      ownerUserId: 'claim-action-test-409-no-cache',
      request: (_) => Future.error(error(409, 'ALREADY_CLAIMED')),
      refreshBalance: () async {},
    );
    expect(result.claimed, isTrue);
    expect(result.amountMinor, isNull);
  });

  test('410 and 403 are terminal results', () async {
    for (final entry in [
      (410, 'RED_PACKET_EMPTY', RedPacketClaimStatus.empty),
      (410, 'RED_PACKET_EXPIRED', RedPacketClaimStatus.expired),
      (403, 'NOT_GROUP_MEMBER', RedPacketClaimStatus.notGroupMember),
    ]) {
      final result = await RedPacketClaimAction.claim(
        '3525',
        ownerUserId: 'claim-action-test-errors',
        request: (_) => Future.error(error(entry.$1, entry.$2)),
        refreshBalance: () async {},
      );
      expect(result.status, entry.$3);
      expect(result.claimed, isFalse);
    }
  });

  test('late CAN_OPEN cannot undo a local claim', () {
    const canOpen = RedPacketClaimStateDto(
      claimState: 'CAN_OPEN',
      myClaimAmount: null,
      packetStatus: 'ACTIVE',
      remainingCount: 1,
    );
    const received = RedPacketClaimStateDto(
      claimState: 'RECEIVED',
      myClaimAmount: 1888,
      packetStatus: 'ACTIVE',
      remainingCount: 0,
    );
    const local = RedPacketOpenedRecord(
      orderId: '3525',
      openedAt: 1,
      claimed: true,
      claimAmountMinor: 1888,
    );
    expect(redPacketClaimedForDisplay(localRecord: local, serverState: canOpen),
        isTrue);
    expect(redPacketClaimedForDisplay(serverState: canOpen), isFalse);
    expect(redPacketClaimedForDisplay(serverState: received), isTrue);
  });
}
