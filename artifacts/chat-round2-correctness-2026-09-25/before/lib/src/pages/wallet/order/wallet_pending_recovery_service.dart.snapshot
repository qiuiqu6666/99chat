import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import '../wallet_repository.dart';
import '../wallet_repository_provider.dart';
import 'wallet_order.dart';
import 'wallet_order_events.dart';
import 'wallet_order_service.dart';
import 'wallet_card_im_sender.dart';
import 'wallet_card_replay_guard.dart';
import 'wallet_card_send_service.dart';
import '../progress/wallet_withdraw_progress_service.dart';

class WalletPendingRecoveryResult {
  final int checkedOrders;
  final int refreshedOrders;
  final int queuedCards;

  const WalletPendingRecoveryResult({
    this.checkedOrders = 0,
    this.refreshedOrders = 0,
    this.queuedCards = 0,
  });

  bool get hasChanges => refreshedOrders > 0 || queuedCards > 0;
}

class WalletPendingRecoveryService {
  WalletPendingRecoveryService._()
      : _repo = createWalletRepository(),
        _orderSvc = WalletOrderService();

  static final WalletPendingRecoveryService instance =
      WalletPendingRecoveryService._();

  final WalletRepository _repo;
  final WalletOrderService _orderSvc;

  Future<WalletPendingRecoveryResult>? _task;
  SessionIdentity? _taskIdentity;
  DateTime? _lastRunAt;
  SessionIdentity? _lastRunIdentity;

  Future<WalletPendingRecoveryResult> recover({
    String reason = 'wallet_recover',
    bool force = false,
  }) {
    final identity = SessionIdentityService.instance.capture();
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return Future.value(const WalletPendingRecoveryResult());
    }
    final running = _task;
    if (running != null && _taskIdentity == identity) return running;

    final now = DateTime.now();
    final last = _lastRunAt;
    if (!force && _lastRunIdentity == identity && last != null &&
        now.difference(last) < const Duration(seconds: 5)) {
      return Future.value(const WalletPendingRecoveryResult());
    }
    _lastRunAt = now;
    _lastRunIdentity = identity;

    late final Future<WalletPendingRecoveryResult> task;
    task = _run(reason: reason, identity: identity).whenComplete(() {
      if (identical(_task, task)) {
        _task = null;
        _taskIdentity = null;
      }
    });
    _task = task;
    _taskIdentity = identity;
    return task;
  }


  bool _shouldRefreshBalance(WalletOrderResult result) {
    if (!result.ok) return false;
    return result.state == WalletOrderState.success ||
        result.state == WalletOrderState.accepted ||
        result.state == WalletOrderState.pending ||
        result.state == WalletOrderState.refunded;
  }

  bool _isCurrent(SessionIdentity identity) =>
      SessionIdentityService.instance.isCurrent(identity);

  Future<WalletPendingRecoveryResult> _run({
    required String reason,
    required SessionIdentity identity,
  }) async {
    final pendingBefore = await _orderSvc.recoverPending();
    if (!_isCurrent(identity) || pendingBefore.isEmpty) {
      return const WalletPendingRecoveryResult();
    }

    final results = NetworkStatusService.instance.isOnline
        ? await _orderSvc.refreshPending(_repo.queryOrderStatus)
        : <WalletOrderResult>[];
    if (!_isCurrent(identity)) return const WalletPendingRecoveryResult();

    if (results.isNotEmpty) {
      WalletOrderEvents.notifyRecord();
    }
    if (results.any(_shouldRefreshBalance)) {
      WalletOrderEvents.notifyBalance();
    }

    await WalletWithdrawProgressService.instance.reconcile(
      reason: reason,
    );
    if (!_isCurrent(identity)) return const WalletPendingRecoveryResult();

    var queuedCards = 0;
    if (NetworkStatusService.instance.isOnline) {
      queuedCards = await resendRetryableImCards(identity: identity);
    }
    if (!_isCurrent(identity)) return const WalletPendingRecoveryResult();

    if (kDebugMode && (results.isNotEmpty || queuedCards > 0)) {
      debugPrint(
        'wallet pending recovered reason=$reason '
        'checked=${pendingBefore.length} refreshed=${results.length} '
        'queuedCards=$queuedCards',
      );
    }

    return WalletPendingRecoveryResult(
      checkedOrders: pendingBefore.length,
      refreshedOrders: results.length,
      queuedCards: queuedCards,
    );
  }

  /// REST 已成功、IM 未送达的卡片：在线时补发，失败不得记 alreadySent。
  @visibleForTesting
  static Future<int> sendRetryableCards({
    required bool online,
    required List<Map<String, dynamic>> payloads,
    required Future<bool> Function(Map<String, dynamic> payload) send,
  }) async {
    if (!online || payloads.isEmpty) {
      return 0;
    }
    var queued = 0;
    for (final payload in payloads) {
      if (await send(payload)) {
        queued++;
      }
    }
    return queued;
  }

  Future<int> resendRetryableImCards({SessionIdentity? identity}) async {
    final captured = identity ?? SessionIdentityService.instance.capture();
    if (!_isCurrent(captured)) return 0;
    final payloads = await WalletCardSendService().retryPayloads();
    if (!_isCurrent(captured)) return 0;
    var queued = 0;
    for (final payload in payloads) {
      if (!_isCurrent(captured)) break;
      if (await WalletCardImSender.instance.send(
        payload,
        source: WalletCardSendSource.recovery,
      )) queued++;
    }
    return queued;
  }

  Future<void> syncWithdrawProgress({String reason = 'wallet_recover'}) {
    return WalletWithdrawProgressService.instance.reconcile(reason: reason);
  }
}
