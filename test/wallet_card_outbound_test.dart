import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/wallet_card_outbound_sidecar.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_dispatch_service.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_im_payload.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_replay_guard.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/order/wallet_card_sent_store.dart';

void main() {
  group('WalletCardImPayload', () {
    test('group transfer and community id resolve as group', () {
      expect(
        WalletCardImPayload.resolveIsGroup({
          'type': 'wallet_group_transfer',
          'conversationId': 'u123',
        }),
        isTrue,
      );
      expect(
        WalletCardImPayload.resolveIsGroup({
          'type': 'wallet_red_packet',
          'isGroup': true,
          'conversationId': 'm25KMR3N5CY',
        }),
        isTrue,
      );
      expect(
        WalletCardImPayload.resolveIsGroup({
          'type': 'wallet_red_packet',
          'conversationId': 'm25KMR3N5CY',
        }),
        isTrue,
      );
    });

    test('c2c transfer resolves peer without group', () {
      final target = WalletCardImPayload.resolveTarget({
        'type': 'wallet_transfer',
        'isGroup': false,
        'conversationId': 'c2c_user99',
      });
      expect(target.isGroup, isFalse);
      expect(target.receiverUserId, 'user99');
      expect(target.groupId, isEmpty);
    });

    test('group payload strips group_ prefix', () {
      final target = WalletCardImPayload.resolveTarget({
        'type': 'wallet_red_packet',
        'isGroup': true,
        'conversationId': 'group_m25KMR3N5CY',
      });
      expect(target.isGroup, isTrue);
      expect(target.receiverUserId, isEmpty);
      expect(target.groupId, isNotEmpty);
    });

    test('custom data keeps order keys and greeting', () {
      final data = WalletCardImPayload.buildCustomData(
        {
          'type': 'wallet_red_packet',
          'orderId': '368',
          'clientOrderId': 'red_packet_a',
          'currency': '99',
          'amount': 8800,
          'status': 'success',
          'greeting': '恭喜发财',
          'packetType': 'LUCKY',
        },
        conversationId: 'm25KMR3N5CY',
      );
      expect(data['businessID'], 'wallet_order');
      expect(data['customType'], 'wallet_red_packet');
      expect(data['orderId'], '368');
      expect(data['clientOrderId'], 'red_packet_a');
      expect(data['amount'], 8800);
      expect(data['greeting'], '恭喜发财');
      expect(data['memo'], '恭喜发财');
      expect(data['packetType'], 'LUCKY');
    });
  });

  group('WalletCardDispatchService conversation match', () {
    tearDown(WalletCardDispatchService.instance.debugClear);

    test('takeForConversation matches group_ prefix with bare id', () {
      final svc = WalletCardDispatchService.instance;
      svc.enqueue({
        'clientOrderId': 'rp_1',
        'conversationId': 'group_m25KMR3N5CY',
        'sendSource': 'payment',
      });
      final taken = svc.takeForConversation('m25KMR3N5CY');
      expect(taken, hasLength(1));
      expect(taken.first['clientOrderId'], 'rp_1');
      expect(svc.pendingCount, 0);
    });

    test('takeForConversation ignores conversation id', () {
      final svc = WalletCardDispatchService.instance;
      svc.enqueue({
        'clientOrderId': 'tf_1',
        'conversationId': 'c2c_user99',
        'sendSource': 'payment',
      });
      final taken = svc.takeForConversation('group_user99');
      expect(taken, hasLength(1));
      expect(taken.first['clientOrderId'], 'tf_1');
      expect(svc.pendingCount, 0);
    });
  });

  group('WalletCardReplayGuard claim', () {
    test('second claim joins until complete', () async {
      final guard = WalletCardReplayGuard(
        store: WalletCardSentStore(storage: MemoryWalletCardSentStorage()),
      );
      final first = await guard.claimSend(
        orderId: '368',
        clientOrderId: 'rp_1',
        source: WalletCardSendSource.payment,
      );
      expect(first.acquired, isTrue);
      final second = await guard.claimSend(
        orderId: '368',
        clientOrderId: 'rp_1',
        source: WalletCardSendSource.recovery,
      );
      expect(second.isJoin, isTrue);
      guard.completeFailed(
        orderId: '368',
        clientOrderId: 'rp_1',
        retryable: true,
      );
      expect(await second.joinFuture, isFalse);
      final third = await guard.claimSend(
        orderId: '368',
        clientOrderId: 'rp_1',
        source: WalletCardSendSource.recovery,
      );
      expect(third.acquired, isTrue);
      await guard.completeSent(orderId: '368', clientOrderId: 'rp_1');
    });
  });

  group('WalletCardOutboundSidecar retry depth', () {
    test('overlapping beginRetry is not dropped', () {
      final sidecar = WalletCardOutboundSidecar.instance;
      const convId = 'c2c_wallet_retry_depth';
      sidecar.resetForConversation(convId);
      expect(sidecar.beginRetry(convId), isTrue);
      expect(sidecar.beginRetry(convId), isTrue);
      sidecar.endRetry(convId);
      expect(sidecar.beginRetry(convId), isTrue);
      sidecar.endRetry(convId);
      sidecar.endRetry(convId);
      sidecar.resetForConversation(convId);
    });
  });
}
