import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/wallet_time.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/wallet_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/red_packet_local_store.dart';

enum RedPacketClaimStatus { claimed, empty, expired, notGroupMember }

bool redPacketClaimedForDisplay({
  RedPacketClaimOutcome? outcome,
  RedPacketOpenedRecord? localRecord,
  RedPacketClaimStateDto? serverState,
  bool inOfficialClaims = false,
}) =>
    outcome?.claimed == true ||
    localRecord?.claimed == true ||
    serverState?.received == true ||
    inOfficialClaims;

class RedPacketClaimOutcome {
  const RedPacketClaimOutcome(this.status,
      {this.amountMinor, this.claimedAtMillis, this.newlyClaimed = false});

  final RedPacketClaimStatus status;
  final int? amountMinor;
  final int? claimedAtMillis;
  final bool newlyClaimed;

  bool get claimed => status == RedPacketClaimStatus.claimed;
}

/// The returned Future covers only the claim HTTP request. Local persistence and
/// wallet refresh are started after the response without holding the open button.
class RedPacketClaimAction {
  RedPacketClaimAction._();

  static Future<RedPacketClaimOutcome> claim(
    String packetId, {
    Future<WalletOrderResult> Function(String)? request,
    RedPacketLocalStore? store,
    String? ownerUserId,
    Future<void> Function()? refreshBalance,
  }) async {
    final localStore = store ?? RedPacketLocalStore.instance;
    RedPacketClaimOutcome outcome;
    try {
      final result = await (request?.call(packetId) ??
          WalletApi.instance.claimRedPacket(orderId: packetId));
      final amount = _asPositiveInt(result.data['amount']);
      if (amount == null) {
        throw const FormatException('Claim response has no positive amount');
      }
      outcome = RedPacketClaimOutcome(
        RedPacketClaimStatus.claimed,
        amountMinor: amount,
        claimedAtMillis: parseWalletApiTimeToLocal(result.data['createdAt'])
            ?.millisecondsSinceEpoch,
        newlyClaimed: true,
      );
    } on DioError catch (error) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      final code = body is Map ? body['code']?.toString() : null;
      if (status == 409 && code == 'ALREADY_CLAIMED') {
        outcome = RedPacketClaimOutcome(
          RedPacketClaimStatus.claimed,
          amountMinor: localStore
              .peekOpened(orderId: packetId, ownerUserId: ownerUserId)
              ?.claimAmountMinor,
          claimedAtMillis: localStore
              .peekOpened(orderId: packetId, ownerUserId: ownerUserId)
              ?.claimedAt,
        );
      } else if (status == 410 && code == 'RED_PACKET_EMPTY') {
        return const RedPacketClaimOutcome(RedPacketClaimStatus.empty);
      } else if (status == 410 && code == 'RED_PACKET_EXPIRED') {
        return const RedPacketClaimOutcome(RedPacketClaimStatus.expired);
      } else if (status == 403 && code == 'NOT_GROUP_MEMBER') {
        return const RedPacketClaimOutcome(RedPacketClaimStatus.notGroupMember);
      } else {
        rethrow;
      }
    }

    // markOpened updates its memory cache synchronously before its first await.
    unawaited(localStore
        .markOpened(
          orderId: packetId,
          ownerUserId: ownerUserId,
          claimed: true,
          claimAmountMinor: outcome.amountMinor,
          claimedAt:
              outcome.claimedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
        )
        .catchError((Object _) {}));
    unawaited(Future.sync(refreshBalance ??
            () async {
              await WalletStore.instance.getWallet(force: true);
            })
        .catchError((Object _) {}));
    return outcome;
  }

  static int? _asPositiveInt(Object? value) {
    final amount = value is num ? value.toInt() : int.tryParse('$value');
    return amount != null && amount > 0 ? amount : null;
  }
}
