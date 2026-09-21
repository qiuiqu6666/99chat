import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'wallet_order.dart';
import 'wallet_pending_store.dart';

class WalletOrderService {
  static final Set<String> _runningClientIds = <String>{};

  final WalletPendingStore pendingStore;
  bool _busy = false;
  String _lockedClientId = '';

  WalletOrderService({WalletPendingStore? store})
      : pendingStore = store ?? WalletPendingStore();

  bool get busy => _busy;
  String get lockedClientId => _lockedClientId;

  Future<List<WalletOrderDraft>> recoverPending() {
    return pendingStore.load();
  }

  Future<List<WalletOrderResult>> refreshPending(
    Future<WalletOrderResult> Function(WalletOrderDraft draft) query,
  ) async {
    final items = await pendingStore.load();
    final results = <WalletOrderResult>[];
    final now = DateTime.now().toIso8601String();

    for (final draft in items) {
      if (!draft.needsOrderStatusQuery) {
        continue;
      }
      try {
        final querying = draft.copyWith(
          retryCount: draft.retryCount + 1,
          lastQueryAt: now,
          updatedAt: now,
        );
        await pendingStore.put(querying);

        final ret = await query(querying);
        results.add(ret);

        final updated = querying.copyWith(
          serverOrderId: ret.orderId.isNotEmpty ? ret.orderId : querying.serverOrderId,
          orderState: ret.state.name,
          updatedAt: DateTime.now().toIso8601String(),
        );

        await _saveAfterResult(updated, ret);
      } catch (_) {
        await pendingStore.put(draft.copyWith(
          retryCount: draft.retryCount + 1,
          lastQueryAt: now,
          updatedAt: now,
        ));
      }
    }

    return results;
  }

  String start(String prefix) {
    if (_lockedClientId.isEmpty) {
      _lockedClientId = WalletIdMaker.make(prefix);
    }
    return _lockedClientId;
  }

  void cancel() {
    if (!_busy) _lockedClientId = '';
  }

  void release() {
    if (!_busy) _lockedClientId = '';
  }

  Future<WalletOrderResult> run(
    WalletOrderDraft draft,
    Future<WalletOrderResult> Function(String clientOrderId) job,
  ) async {
    final identity = SessionIdentityService.instance.capture();
    if (!SessionIdentityService.instance.isCurrent(identity)) {
      return _sessionChangedResult(draft.clientOrderId);
    }
    final clientId = draft.clientOrderId.trim();
    if (_busy || clientId.isEmpty || !_runningClientIds.add(clientId)) {
      return WalletOrderResult(
        ok: false,
        state: WalletOrderState.failed,
        err: WalletOrderErr.duplicateSubmit,
        clientOrderId: draft.clientOrderId,
        msg: WalletOrderErr.duplicateSubmit.text,
      );
    }

    _busy = true;
    final now = DateTime.now().toIso8601String();
    final pendingDraft = draft.copyWith(
      updatedAt: now,
      lastQueryAt: now,
      orderState: WalletOrderState.submitting.name,
    );
    try {
      await pendingStore.put(pendingDraft);
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        return _sessionChangedResult(draft.clientOrderId);
      }
      final ret = await job(draft.clientOrderId);
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        return _sessionChangedResult(draft.clientOrderId);
      }
      final savedDraft = pendingDraft.copyWith(
        serverOrderId: ret.orderId.isNotEmpty ? ret.orderId : pendingDraft.serverOrderId,
        orderState: ret.state.name,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await _saveAfterResult(savedDraft, ret);

      _lockedClientId = '';
      return ret;
    } on WalletSubmitException catch (e) {
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        return _sessionChangedResult(draft.clientOrderId);
      }
      _lockedClientId = '';
      if (!e.requestSent) {
        await pendingStore.remove(draft.clientOrderId);
        return WalletOrderResult(
          ok: false,
          state: WalletOrderState.failed,
          err: WalletOrderErr.networkError,
          clientOrderId: draft.clientOrderId,
          msg: e.message.isNotEmpty ? e.message : WalletOrderErr.networkError.text,
        );
      }

      await pendingStore.put(pendingDraft.copyWith(
        retryCount: pendingDraft.retryCount + 1,
        lastQueryAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        orderState: WalletOrderState.unknown.name,
      ));
      return WalletOrderResult(
        ok: true,
        state: WalletOrderState.unknown,
        err: WalletOrderErr.networkError,
        clientOrderId: draft.clientOrderId,
        msg: e.message.isNotEmpty
            ? e.message
            : AppI18n.current.t(
                zhHans: '交易状态确认中，可在记录中查看',
                zhHant: '交易狀態確認中，可在記錄中查看',
                en: 'Transaction status is being confirmed. Check History for updates.',
                ja: '取引状況を確認中です。履歴でご確認ください。',
                ko: '거래 상태를 확인 중입니다. 기록에서 확인할 수 있습니다.',
              ),
      );
    } catch (_) {
      if (!SessionIdentityService.instance.isCurrent(identity)) {
        return _sessionChangedResult(draft.clientOrderId);
      }
      await pendingStore.remove(draft.clientOrderId);
      _lockedClientId = '';
      return WalletOrderResult(
        ok: false,
        state: WalletOrderState.failed,
        err: WalletOrderErr.networkError,
        clientOrderId: draft.clientOrderId,
        msg: AppI18n.current.t(
          zhHans: '提交失败，请重试',
          zhHant: '提交失敗，請重試',
          en: 'Submission failed. Please try again.',
          ja: '送信に失敗しました。もう一度お試しください。',
          ko: '제출에 실패했습니다. 다시 시도해 주세요.',
        ),
      );
    } finally {
      if (clientId.isNotEmpty) {
        _runningClientIds.remove(clientId);
      }
      _busy = false;
    }
  }

  WalletOrderResult _sessionChangedResult(String clientOrderId) {
    return WalletOrderResult(
      ok: false,
      state: WalletOrderState.unknown,
      err: WalletOrderErr.networkError,
      clientOrderId: clientOrderId,
      msg: AppI18n.current.t(
        zhHans: '账号已切换，请在当前账号确认交易状态',
        zhHant: '帳號已切換，請在目前帳號確認交易狀態',
        en: 'The account changed. Check the transaction status in the current account.',
        ja: 'アカウントが切り替わりました。現在のアカウントで取引状況を確認してください。',
        ko: '계정이 변경되었습니다. 현재 계정에서 거래 상태를 확인하세요.',
      ),
    );
  }


  Future<void> _saveAfterResult(
    WalletOrderDraft draft,
    WalletOrderResult ret,
  ) async {
    if (!ret.ok || _isFailedDone(ret.state)) {
      await pendingStore.remove(draft.clientOrderId);
      return;
    }

    if (_canRemove(draft)) {
      await pendingStore.remove(draft.clientOrderId);
      return;
    }

    await pendingStore.put(draft);
  }

  bool _isFailedDone(WalletOrderState state) {
    return state == WalletOrderState.failed ||
        state == WalletOrderState.expired ||
        state == WalletOrderState.cancelled ||
        state == WalletOrderState.refunded;
  }

  bool _canRemove(WalletOrderDraft draft) {
    if (!draft.isDoneOrder) return false;
    if (!draft.needsChatCard) return true;
    return draft.cardSent || draft.cardIgnored;
  }
}
