import 'package:flutter/foundation.dart';

import 'wallet_order_events.dart';

/// 跨会话钱包卡片补发队列：入队后由任意补发入口 flush，不再按当前会话过滤。
class WalletCardDispatchService {
  WalletCardDispatchService._();

  static final WalletCardDispatchService instance = WalletCardDispatchService._();

  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];

  int get pendingCount => _queue.length;

  void enqueue(Map<String, dynamic> payload) {
    if (payload.isEmpty) return;
    final key = _key(payload);
    if (key.isEmpty) return;
    if (_queue.any((item) => _key(item) == key)) return;
    _queue.add(Map<String, dynamic>.from(payload));
  }

  void removeMatching(Map<String, dynamic> payload) {
    final key = _key(payload);
    if (key.isEmpty) return;
    _queue.removeWhere((item) => _key(item) == key);
  }

  List<Map<String, dynamic>> takeForConversation(
    String conversationId, {
    int limit = 20,
  }) {
    if (limit <= 0) return const [];
    final taken = <Map<String, dynamic>>[];
    _queue.removeWhere((payload) {
      if (taken.length >= limit) return false;
      taken.add(payload);
      return true;
    });
    return taken;
  }

  void dispatch(Map<String, dynamic> payload) {
    enqueue(payload);
    WalletOrderEvents.notifyChatCardNeedSend(payload);
  }

  void clearSession() => _queue.clear();

  String _key(Map<String, dynamic> payload) {
    final clientOrderId = payload['clientOrderId']?.toString().trim() ?? '';
    if (clientOrderId.isNotEmpty) return clientOrderId;
    return payload['orderId']?.toString().trim() ?? '';
  }

  @visibleForTesting
  void debugClear() => _queue.clear();
}
