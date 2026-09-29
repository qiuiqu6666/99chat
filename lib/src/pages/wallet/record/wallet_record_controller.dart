import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';

import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'wallet_record_updates.dart';

import '../order/wallet_pending_recovery_service.dart';
import '../wallet_repository.dart';
import '../wallet_repository_provider.dart';
import 'wallet_record_models.dart';

class WalletRecordController extends ChangeNotifier {
  final WalletRepository _repo;
  WalletRecordController({
    WalletRepository? repo,
  }) : _repo = repo ?? createWalletRepository() {
    final updates = _repo;
    if (updates is WalletRecordLocalUpdates) {
      final localUpdates = updates as WalletRecordLocalUpdates;
      _commits = localUpdates.recordCommits.listen((event) {
        if (_dead ||
            event.identity != _displayIdentity ||
            event.identity != _identity() ||
            event.scopeKey != localUpdates.recordScopeKey(filter)) return;
        _localDirty = true;
        if (_active) unawaited(_reloadLocal());
      });
    }
  }

  bool loading = false;
  String err = '';
  HistoryRecordFilter filter = HistoryRecordFilter.all;

  List<WalletRecordDto> list = [];
  bool _dead = false;

  Future<void>? _flight;
  StreamSubscription<WalletRecordCommit>? _commits;
  int _revision = 0;
  SessionIdentity? _displayIdentity;
  bool _active = true;
  bool _localDirty = false;
  bool _readingLocal = false;
  SessionIdentity _identity() => SessionIdentityService.instance
      .capture(ownerUserId: ApiClient.instance.authenticatedUserId);

  void setActive(bool active) {
    _active = active;
    if (active && _localDirty) unawaited(_reloadLocal());
  }

  Future<void> _reloadLocal() async {
    if (_dead || !_active || loading || _readingLocal || !_localDirty) return;
    if (_displayIdentity != _identity()) {
      _localDirty = false;
      return;
    }
    final updates = _repo;
    if (updates is! WalletRecordLocalUpdates) return;
    final localUpdates = updates as WalletRecordLocalUpdates;
    _readingLocal = true;
    try {
      while (_localDirty && !_dead && _active && !loading) {
        _localDirty = false;
        final identity = _identity();
        final revision = _revision;
        final result = await localUpdates.readLocalRecords(filter);
        if (_dead || identity != _identity() || revision != _revision) return;
        if (!_active || loading) {
          _localDirty = true;
          return;
        }
        list = result;
        notifyListeners();
      }
    } catch (_) {
      _localDirty = true;
    } finally {
      _readingLocal = false;
    }
  }

  Future<void> load() {
    if (_dead) return Future.value();
    _revision++;
    final identity = _identity();
    if (_displayIdentity != identity) {
      _displayIdentity = identity;
      list = [];
      err = '';
      if (_flight != null) notifyListeners();
    }
    if (_flight != null) return _flight!;
    late final Future<void> flight;
    flight = _drainLoads().whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
      if (_localDirty && _active && !_dead) unawaited(_reloadLocal());
    });
    _flight = flight;
    return flight;
  }

  Future<void> _drainLoads() async {
    loading = true;
    err = '';
    notifyListeners();
    try {
      while (!_dead) {
        final revision = _revision;
        final identity = _identity();
        final requestedFilter = filter;
        try {
          final result = await _repo.getWalletRecordsByFilter(requestedFilter);
          if (_dead) return;
          if (revision != _revision) continue;
          if (identity != _identity()) return;
          list = result;
          err = '';
          _refreshPendingInBackground();
        } catch (_) {
          if (_dead) return;
          if (revision != _revision) continue;
          if (identity != _identity()) return;
          err = AppI18n.current.t(
            zhHans: '记录加载失败，请稍后重试',
            zhHant: '記錄載入失敗，請稍後再試',
            en: 'Failed to load records. Please try again later.',
            ja: '履歴の読み込みに失敗しました。しばらくしてからもう一度お試しください。',
            ko: '기록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
          );
          list = [];
        }
        break;
      }
    } finally {
      loading = false;
      if (!_dead) notifyListeners();
    }
  }

  Future<void> _refreshPending() async {
    await WalletPendingRecoveryService.instance.recover(
      reason: 'wallet_record',
      force: true,
    );
  }

  void _refreshPendingInBackground() {
    unawaited(() async {
      try {
        await _refreshPending();
      } catch (_) {}
    }());
  }

  void setFilter(HistoryRecordFilter v) {
    if (filter == v) return;
    filter = v;
    load();
  }

  @override
  void dispose() {
    _dead = true;
    _revision++;
    unawaited(_commits?.cancel());
    super.dispose();
  }
}
