import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_dispatch_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_im_payload.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_replay_guard.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_send_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_order_events.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

/// 支付 REST 成功后的钱包卡片唯一 IM 发送入口（聊天页不得再 create）。
class WalletCardImSender {
  WalletCardImSender._();

  static final WalletCardImSender instance = WalletCardImSender._();

  final WalletCardSendService _sendSvc = WalletCardSendService();

  Future<bool> sendAfterRest(
    Map<String, dynamic> payload, {
    WalletCardSendSource source = WalletCardSendSource.payment,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;
    WalletCardDispatchService.instance.enqueue(payload);
    var sent = await send(payload, source: source);
    // OutcomeUnknown 可能已经到达腾讯，禁止立刻再 createCustomMessage。
    // 明确失败才短延迟补一次；未知结果留给 pending / 进会话确认。
    if (!sent &&
        payload['imOutcomeUnknown'] != true &&
        SessionIdentityService.instance.isCurrent(identity)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (SessionIdentityService.instance.isCurrent(identity)) {
        sent = await send(
          payload,
          source: WalletCardSendSource.recovery,
        );
      }
    }
    if (sent && SessionIdentityService.instance.isCurrent(identity)) {
      WalletOrderEvents.notifyChatCardSent(payload);
    }
    return sent;
  }

  Future<bool> send(
    Map<String, dynamic> payload, {
    WalletCardSendSource source = WalletCardSendSource.payment,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;
    final orderId = payload['orderId']?.toString() ?? '';
    final clientOrderId = payload['clientOrderId']?.toString() ?? '';
    final target = WalletCardImPayload.resolveTarget(payload);
    if (!target.isValid) {
      debugPrint(
        'wallet-card skip empty-target clientOrderId=$clientOrderId '
        'conv=${payload['conversationId']}',
      );
      return false;
    }

    if (source == WalletCardSendSource.manual) {
      await WalletCardReplayGuard.instance.resetForManual(
        orderId: orderId,
        clientOrderId: clientOrderId,
      );
    }

    if (payload['imOutcomeUnknown'] == true &&
        source != WalletCardSendSource.manual) {
      debugPrint(
        'wallet-card skip outcome-unknown pending adoption '
        'clientOrderId=$clientOrderId',
      );
      return false;
    }

    final claim = await WalletCardReplayGuard.instance.claimSend(
      orderId: orderId,
      clientOrderId: clientOrderId,
      source: source,
    );
    if (!SessionIdentityService.instance.isCurrent(identity)) return false;

    if (claim.isJoin) {
      debugPrint('wallet-card join inflight clientOrderId=$clientOrderId');
      return await claim.joinFuture!;
    }

    if (claim.rejected) {
      debugPrint(
        'wallet-card skip claim-reject clientOrderId=$clientOrderId '
        'source=${source.name}',
      );
      if (await WalletCardReplayGuard.instance.alreadySent(
        orderId: orderId,
        clientOrderId: clientOrderId,
      )) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return false;
        WalletCardDispatchService.instance.removeMatching(payload);
        await _sendSvc.markSent(payload);
        WalletOrderEvents.notifyChatCardSent(payload);
        return true;
      }
      return false;
    }

    try {
      if (target.receiverUserId.isNotEmpty) {
        C2cFriendMessageGuard.trustCanSendHint(
          target.receiverUserId,
          source: 'wallet_card_outbound',
        );
      }

      await _sendSvc.markSending(
        payload,
        requireCanRetry: source != WalletCardSendSource.payment,
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        await _markFailed(payload, source, identity, orderId, clientOrderId);
        return false;
      }

      final convId = target.isGroup ? target.groupId : target.receiverUserId;
      final data = WalletCardImPayload.buildCustomData(
        payload,
        conversationId: convId,
      );
      final sdk = TIMUIKitCore.getSDKInstance();
      final created = await sdk.getMessageManager().createCustomMessage(
            data: jsonEncode(data),
          );
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        WalletCardReplayGuard.instance.completeFailed(
          orderId: orderId,
          clientOrderId: clientOrderId,
          retryable: true,
        );
        return false;
      }
      final msg = created.data?.messageInfo;
      if (created.code != 0 || msg == null) {
        debugPrint(
          'wallet-card createCustomMessage failed code=${created.code} '
          'desc=${created.desc} clientOrderId=$clientOrderId',
        );
        await _markFailed(payload, source, identity, orderId, clientOrderId);
        return false;
      }

      final sendResult =
          await ChatExternalMessageSender.sendCreatedMessageDetailed(
        messageInfo: msg,
        receiverUserId: target.receiverUserId,
        groupId: target.groupId,
        reason: 'wallet_card_sent',
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        WalletCardReplayGuard.instance.completeFailed(
          orderId: orderId,
          clientOrderId: clientOrderId,
          retryable: true,
        );
        return false;
      }
      if (sendResult.state == ExternalMessageSendState.outcomeUnknown) {
        debugPrint(
          'wallet-card outcome unknown; keep pending for adoption '
          'clientOrderId=$clientOrderId',
        );
        payload['imOutcomeUnknown'] = true;
        WalletCardDispatchService.instance.removeMatching(payload);
        WalletCardReplayGuard.instance.completeUnknown(
          orderId: orderId,
          clientOrderId: clientOrderId,
        );
        return false;
      }
      if (!sendResult.succeeded) {
        debugPrint(
          'wallet-card sendMessage failed clientOrderId=$clientOrderId '
          'group=${target.groupId} peer=${target.receiverUserId}',
        );
        await _markFailed(payload, source, identity, orderId, clientOrderId);
        return false;
      }

      if (!SessionIdentityService.instance.isCurrent(identity)) {
        WalletCardReplayGuard.instance.completeFailed(
          orderId: orderId,
          clientOrderId: clientOrderId,
          retryable: true,
        );
        return false;
      }
      WalletCardDispatchService.instance.removeMatching(payload);
      await WalletCardReplayGuard.instance.completeSent(
        orderId: orderId,
        clientOrderId: clientOrderId,
      );
      if (!SessionIdentityService.instance.isCurrent(identity)) return false;
      await _sendSvc.markSent(payload);
      return true;
    } catch (e) {
      debugPrint('wallet-card send error clientOrderId=$clientOrderId err=$e');
      await _markFailed(payload, source, identity, orderId, clientOrderId);
      return false;
    }
  }

  Future<void> _markFailed(
    Map<String, dynamic> payload,
    WalletCardSendSource source,
    SessionIdentity identity,
    String orderId,
    String clientOrderId,
  ) async {
    WalletCardReplayGuard.instance.completeFailed(
      orderId: orderId,
      clientOrderId: clientOrderId,
      retryable: true,
    );
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    final failed = await _sendSvc.markFailed(payload);
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    WalletOrderEvents.notifyChatCardSendFailed(
      failed.toPayload(),
      source: source.name,
    );
  }
}
