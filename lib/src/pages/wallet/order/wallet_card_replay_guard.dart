import 'dart:async';

import 'wallet_card_sent_store.dart';

enum WalletCardSendSource {
  /// 支付 REST 成功后的当场发卡。
  payment,

  /// 用户在失败弹窗 / 待处理列表里点「重新发送」。
  manual,

  /// 登录 / 回前台 recovery：REST 已成功但 IM 未送达时补发。
  recovery,

  /// 进会话、拉历史等顺手自动补发。
  autoRetry,
}

/// IM 发送相位（内存态；[sent] 另由 [WalletCardSentStore] 持久化）。
enum WalletCardSendPhase {
  pending,
  sending,
  sent,
  unknown,
  failedRetryable,
  failedFinal,
}

enum WalletCardClaimKind {
  /// 调用方获得发送权，必须在结束后 complete*。
  acquired,

  /// 已有发送在途，应 await [WalletCardClaimResult.joinFuture]。
  join,

  /// 禁止发送（已 sent / unknown 非 manual / failed_final 等）。
  reject,
}

class WalletCardClaimResult {
  final WalletCardClaimKind kind;
  final Future<bool>? joinFuture;

  const WalletCardClaimResult._(this.kind, {this.joinFuture});

  factory WalletCardClaimResult.acquired() =>
      const WalletCardClaimResult._(WalletCardClaimKind.acquired);

  factory WalletCardClaimResult.join(Future<bool> future) =>
      WalletCardClaimResult._(WalletCardClaimKind.join, joinFuture: future);

  factory WalletCardClaimResult.reject() =>
      const WalletCardClaimResult._(WalletCardClaimKind.reject);

  bool get acquired => kind == WalletCardClaimKind.acquired;
  bool get isJoin => kind == WalletCardClaimKind.join;
  bool get rejected => kind == WalletCardClaimKind.reject;
}

/// 钱包 IM 卡片统一发送闸门：原子 claim + 相位状态机，避免同一笔并发/串行双发。
class WalletCardReplayGuard {
  WalletCardReplayGuard({WalletCardSentStore? store})
      : _store = store ?? WalletCardSentStore.instance;

  static final WalletCardReplayGuard instance = WalletCardReplayGuard();

  final WalletCardSentStore _store;

  /// primaryKey → phase（sent 以 store 为准，此处可缓存）。
  final Map<String, WalletCardSendPhase> _phases = <String, WalletCardSendPhase>{};

  /// primaryKey → in-flight completer（sending 时必有）。
  final Map<String, Completer<bool>> _inflight = <String, Completer<bool>>{};

  Iterable<String> keysOf({
    String orderId = '',
    String clientOrderId = '',
  }) {
    return <String>[orderId, clientOrderId];
  }

  Future<void> rememberRestSuccess({
    String orderId = '',
    String clientOrderId = '',
  }) {
    return _store.markRestCommitted(keysOf(
      orderId: orderId,
      clientOrderId: clientOrderId,
    ));
  }

  Future<void> rememberImSent({
    String orderId = '',
    String clientOrderId = '',
  }) async {
    await _store.markSent(keysOf(
      orderId: orderId,
      clientOrderId: clientOrderId,
    ));
    _setPhase(
      orderId: orderId,
      clientOrderId: clientOrderId,
      phase: WalletCardSendPhase.sent,
    );
  }

  Future<bool> alreadySent({
    String orderId = '',
    String clientOrderId = '',
  }) {
    return _store.isSent(keysOf(
      orderId: orderId,
      clientOrderId: clientOrderId,
    ));
  }

  Future<bool> allowSend({
    String orderId = '',
    String clientOrderId = '',
    required WalletCardSendSource source,
  }) async {
    if (await alreadySent(
      orderId: orderId,
      clientOrderId: clientOrderId,
    )) {
      return false;
    }
    final phase = _phaseOf(orderId: orderId, clientOrderId: clientOrderId);
    switch (phase) {
      case WalletCardSendPhase.sent:
        return false;
      case WalletCardSendPhase.failedFinal:
        return false;
      case WalletCardSendPhase.unknown:
        return source == WalletCardSendSource.manual;
      case WalletCardSendPhase.sending:
        return false;
      case WalletCardSendPhase.pending:
      case WalletCardSendPhase.failedRetryable:
        return true;
    }
  }

  /// 原子抢占发送权。成功获得 [WalletCardClaimKind.acquired] 后必须 complete*。
  Future<WalletCardClaimResult> claimSend({
    String orderId = '',
    String clientOrderId = '',
    required WalletCardSendSource source,
  }) async {
    final keys = _normalizedKeys(orderId: orderId, clientOrderId: clientOrderId);
    if (keys.isEmpty) return WalletCardClaimResult.reject();

    if (await alreadySent(orderId: orderId, clientOrderId: clientOrderId)) {
      _setPhaseForKeys(keys, WalletCardSendPhase.sent);
      return WalletCardClaimResult.reject();
    }

    final primary = _primaryKey(keys);
    final phase = _phaseOf(orderId: orderId, clientOrderId: clientOrderId);

    if (phase == WalletCardSendPhase.sending) {
      final existing = _completerFor(keys);
      if (existing != null) {
        return WalletCardClaimResult.join(existing.future);
      }
      return WalletCardClaimResult.reject();
    }

    if (phase == WalletCardSendPhase.sent ||
        phase == WalletCardSendPhase.failedFinal) {
      return WalletCardClaimResult.reject();
    }

    if (phase == WalletCardSendPhase.unknown &&
        source != WalletCardSendSource.manual) {
      return WalletCardClaimResult.reject();
    }

    final completer = Completer<bool>();
    _inflight[primary] = completer;
    for (final key in keys) {
      _phases[key] = WalletCardSendPhase.sending;
      _inflight[key] = completer;
    }
    return WalletCardClaimResult.acquired();
  }

  Future<void> completeSent({
    String orderId = '',
    String clientOrderId = '',
  }) async {
    await rememberImSent(orderId: orderId, clientOrderId: clientOrderId);
    _finishInflight(
      orderId: orderId,
      clientOrderId: clientOrderId,
      result: true,
      phase: WalletCardSendPhase.sent,
    );
  }

  void completeUnknown({
    String orderId = '',
    String clientOrderId = '',
  }) {
    _finishInflight(
      orderId: orderId,
      clientOrderId: clientOrderId,
      result: false,
      phase: WalletCardSendPhase.unknown,
    );
  }

  void completeFailed({
    String orderId = '',
    String clientOrderId = '',
    bool retryable = true,
  }) {
    _finishInflight(
      orderId: orderId,
      clientOrderId: clientOrderId,
      result: false,
      phase: retryable
          ? WalletCardSendPhase.failedRetryable
          : WalletCardSendPhase.failedFinal,
    );
  }

  /// 手动重发前：unknown / failed_* → pending。不清除已 sent。
  Future<void> resetForManual({
    String orderId = '',
    String clientOrderId = '',
  }) async {
    if (await alreadySent(orderId: orderId, clientOrderId: clientOrderId)) {
      return;
    }
    final phase = _phaseOf(orderId: orderId, clientOrderId: clientOrderId);
    if (phase == WalletCardSendPhase.sending) return;
    if (phase == WalletCardSendPhase.sent) return;
    _setPhase(
      orderId: orderId,
      clientOrderId: clientOrderId,
      phase: WalletCardSendPhase.pending,
    );
  }

  WalletCardSendPhase debugPhase({
    String orderId = '',
    String clientOrderId = '',
  }) {
    return _phaseOf(orderId: orderId, clientOrderId: clientOrderId);
  }

  /// 兼容旧测试：非原子 begin；新代码请用 [claimSend]。
  @Deprecated('Use claimSend')
  bool tryBeginSend({
    String orderId = '',
    String clientOrderId = '',
  }) {
    final keys = _normalizedKeys(orderId: orderId, clientOrderId: clientOrderId);
    if (keys.isEmpty) return false;
    for (final key in keys) {
      if (_inflight.containsKey(key)) return false;
      if (_phases[key] == WalletCardSendPhase.sending) return false;
    }
    final completer = Completer<bool>();
    for (final key in keys) {
      _phases[key] = WalletCardSendPhase.sending;
      _inflight[key] = completer;
    }
    return true;
  }

  /// 兼容旧测试。
  @Deprecated('Use completeSent / completeFailed / completeUnknown')
  void endSend({
    String orderId = '',
    String clientOrderId = '',
  }) {
    final phase = _phaseOf(orderId: orderId, clientOrderId: clientOrderId);
    if (phase != WalletCardSendPhase.sending) {
      _clearInflightOnly(orderId: orderId, clientOrderId: clientOrderId);
      return;
    }
    _finishInflight(
      orderId: orderId,
      clientOrderId: clientOrderId,
      result: false,
      phase: WalletCardSendPhase.pending,
    );
  }

  WalletCardSendPhase _phaseOf({
    required String orderId,
    required String clientOrderId,
  }) {
    for (final key in _normalizedKeys(
      orderId: orderId,
      clientOrderId: clientOrderId,
    )) {
      final phase = _phases[key];
      if (phase != null) return phase;
    }
    return WalletCardSendPhase.pending;
  }

  void _setPhase({
    required String orderId,
    required String clientOrderId,
    required WalletCardSendPhase phase,
  }) {
    _setPhaseForKeys(
      _normalizedKeys(orderId: orderId, clientOrderId: clientOrderId),
      phase,
    );
  }

  void _setPhaseForKeys(Set<String> keys, WalletCardSendPhase phase) {
    for (final key in keys) {
      _phases[key] = phase;
    }
  }

  Completer<bool>? _completerFor(Set<String> keys) {
    for (final key in keys) {
      final c = _inflight[key];
      if (c != null) return c;
    }
    return null;
  }

  void _finishInflight({
    required String orderId,
    required String clientOrderId,
    required bool result,
    required WalletCardSendPhase phase,
  }) {
    final keys = _normalizedKeys(orderId: orderId, clientOrderId: clientOrderId);
    final completer = _completerFor(keys);
    _setPhaseForKeys(keys, phase);
    for (final key in keys) {
      _inflight.remove(key);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _clearInflightOnly({
    required String orderId,
    required String clientOrderId,
  }) {
    final keys = _normalizedKeys(orderId: orderId, clientOrderId: clientOrderId);
    for (final key in keys) {
      _inflight.remove(key);
    }
  }

  String _primaryKey(Set<String> keys) {
    if (keys.isEmpty) return '';
    return keys.first;
  }

  Set<String> _normalizedKeys({
    required String orderId,
    required String clientOrderId,
  }) {
    return keysOf(orderId: orderId, clientOrderId: clientOrderId)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '--')
        .toSet();
  }
}
