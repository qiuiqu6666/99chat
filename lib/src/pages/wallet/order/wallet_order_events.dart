import 'package:flutter/foundation.dart';

import 'package:tencent_cloud_chat_demo/src/services/conversation_refresh_bus.dart';

class WalletOrderEvents {
  WalletOrderEvents._();

  static const Duration _chatCardFailNoticeWindow = Duration(seconds: 8);

  /// 聊天页只刷新 / 清队列，不得再 create。
  static const String cardSent = 'cardSent';

  /// 需要补发：聊天页应转调 [WalletCardImSender]，不得本页 create。
  static const String cardNeedSend = 'cardNeedSend';

  static const String walletCardEventKey = 'walletCardEvent';

  static final ValueNotifier<int> balanceChanged = ValueNotifier<int>(0);
  static final ValueNotifier<int> recordChanged = ValueNotifier<int>(0);
  static final ValueNotifier<Map<String, dynamic>?> chatCardPayload =
      ValueNotifier<Map<String, dynamic>?>(null);
  static final ValueNotifier<Map<String, dynamic>?> chatCardSendFailedPayload =
      ValueNotifier<Map<String, dynamic>?>(null);
  static final Map<String, DateTime> _chatCardFailNoticeClaims =
      <String, DateTime>{};

  static void notifyBalance() => balanceChanged.value++;

  static void notifyRecord() => recordChanged.value++;

  /// 直发/发送成功：仅通知 UI，不要求再次发送。
  static void notifyChatCardSent([Map<String, dynamic>? data]) {
    _publishChatCard(data, event: cardSent, reason: 'wallet_chat_card_sent');
  }

  /// 需要补发：监听方应调用 WalletCardImSender，不得本页 create。
  static void notifyChatCardNeedSend([Map<String, dynamic>? data]) {
    _publishChatCard(
      data,
      event: cardNeedSend,
      reason: 'wallet_chat_card_need_send',
    );
  }

  /// 兼容旧调用：视为需要补发。
  @Deprecated('Use notifyChatCardSent or notifyChatCardNeedSend')
  static void notifyChatCard([Map<String, dynamic>? data]) {
    notifyChatCardNeedSend(data);
  }

  static void _publishChatCard(
    Map<String, dynamic>? data, {
    required String event,
    required String reason,
  }) {
    if (data == null) {
      chatCardPayload.value = null;
    } else {
      chatCardPayload.value = {
        ...Map<String, dynamic>.from(data),
        walletCardEventKey: event,
      };
    }
    ConversationRefreshBus.instance.requestRefresh(reason: reason);
  }

  static void notifyChatCardSendFailed(
    Map<String, dynamic> data, {
    String source = 'autoRetry',
  }) {
    chatCardSendFailedPayload.value = {
      ...data,
      'source': source,
    };
    ConversationRefreshBus.instance
        .requestRefresh(reason: 'wallet_chat_card_failed');
  }

  static bool claimChatCardFailNotice(Map<String, dynamic> data) {
    final key = _chatCardFailNoticeKey(data);
    if (key.isEmpty) {
      return true;
    }
    final now = DateTime.now();
    _chatCardFailNoticeClaims.removeWhere(
      (_, claimedAt) => now.difference(claimedAt) > _chatCardFailNoticeWindow,
    );
    final last = _chatCardFailNoticeClaims[key];
    if (last != null && now.difference(last) <= _chatCardFailNoticeWindow) {
      return false;
    }
    _chatCardFailNoticeClaims[key] = now;
    return true;
  }

  static String _chatCardFailNoticeKey(Map<String, dynamic> data) {
    final clientOrderId = data['clientOrderId']?.toString().trim() ?? '';
    if (clientOrderId.isNotEmpty) {
      return clientOrderId;
    }
    return data['orderId']?.toString().trim() ?? '';
  }
}
