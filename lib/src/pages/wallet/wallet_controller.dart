import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/errors/app_error.dart';

import 'order/wallet_order_events.dart';
import 'order/wallet_pending_recovery_service.dart';
import 'progress/wallet_withdraw_progress_service.dart';
import 'wallet_error_mapper.dart';
import 'wallet_repository.dart';
import 'wallet_repository_provider.dart';
import 'wallet_store.dart';
import 'wallet_snapshot_local_store.dart';

class WalletController extends ChangeNotifier {
  final WalletRepository _repo;
  final WalletSnapshotLocalStore _localStore;
  WalletController({
    WalletRepository? repo,
    WalletSnapshotLocalStore? localStore,
  })  : _repo = repo ?? createWalletRepository(),
        _localStore = localStore ?? WalletSnapshotLocalStore.instance {
    WalletOrderEvents.balanceChanged.addListener(_onBalanceChanged);
  }

  bool loading = false;
  bool loadFailed = false;
  bool showBal = true;
  AppError? lastError;

  String totalBal = '0.00';
  String totalBalUsd = '';
  String trxAddr = '';
  List<CoinDto> coins = [];

  bool _dead = false;
  bool _busy = false;
  bool _refreshAgain = false;
  bool _hasSnapshot = false;
  SessionIdentity? _displayIdentity;

  void _applySnapshot(WalletDto data) {
    totalBal = data.totalBal;
    totalBalUsd = data.totalBalUsd;
    trxAddr = data.trxAddr;
    coins = data.coins;
    _hasSnapshot = true;
  }

  Future<void> load({bool force = false}) async {
    if (_dead) return;
    final identity = SessionIdentityService.instance.capture(
      ownerUserId: ApiClient.instance.authenticatedUserId,
    );
    bool isCurrent() =>
        !_dead &&
        identity ==
            SessionIdentityService.instance.capture(
              ownerUserId: ApiClient.instance.authenticatedUserId,
            );
    final accountChanged = _displayIdentity != identity;
    if (accountChanged) {
      _displayIdentity = identity;
      _hasSnapshot = false;
      totalBal = '0.00';
      totalBalUsd = '';
      trxAddr = '';
      coins = [];
    }
    if (_busy) {
      _refreshAgain = _refreshAgain || force || accountChanged;
      if (accountChanged) {
        loading = true;
        loadFailed = false;
        lastError = null;
        notifyListeners();
      }
      return;
    }
    _busy = true;
    loading = !_hasSnapshot;
    loadFailed = false;
    lastError = null;
    notifyListeners();

    try {
      if (!_hasSnapshot) {
        final cached = await _localStore.read(identity.ownerUserId);
        if (!isCurrent()) return;
        if (cached != null) {
          _applySnapshot(cached);
          loading = false;
          notifyListeners();
        }
      }
      _recoverPending().catchError((e) {
        debugPrint('recover pending wallet orders error: $e');
      });

      // Always revalidate disk snapshots; they must not renew the memory TTL.
      final data = await _repo.getWallet().timeout(const Duration(seconds: 6));
      if (!isCurrent()) return;
      _applySnapshot(data);
      WalletStore.instance.updateWallet(data);
      loadFailed = false;
      lastError = null;
      loading = false;
      notifyListeners();
      try {
        await _localStore.write(identity.ownerUserId, data);
      } catch (_) {
        // Disk errors must not turn a successful network load into a failure.
      }
    } catch (e, st) {
      if (!isCurrent()) return;
      loadFailed = !_hasSnapshot;
      lastError = WalletErrorMapper.map(e, action: 'load');
      if (kDebugMode) {
        debugPrint('load wallet error: $e\n$st');
      }
    } finally {
      _busy = false;
      loading = false;
      if (!isCurrent() && _displayIdentity == identity) {
        _displayIdentity = null;
        _hasSnapshot = false;
        totalBal = '0.00';
        totalBalUsd = '';
        trxAddr = '';
        coins = [];
        loadFailed = false;
        lastError = null;
      }
      if (!_dead) notifyListeners();
      if (_refreshAgain && !_dead) {
        _refreshAgain = false;
        unawaited(load(force: true));
      }
    }
  }

  Future<void> _recoverPending() async {
    await WalletPendingRecoveryService.instance.recover(
      reason: 'wallet_home',
    );
    await WalletWithdrawProgressService.instance.reconcile(
      reason: 'wallet_home',
    );
  }

  void _onBalanceChanged() {
    if (_dead) return;
    unawaited(load(force: true));
  }

  void toggleBal() {
    showBal = !showBal;
    notifyListeners();
  }

  @override
  void dispose() {
    _dead = true;
    WalletOrderEvents.balanceChanged.removeListener(_onBalanceChanged);
    super.dispose();
  }
}
