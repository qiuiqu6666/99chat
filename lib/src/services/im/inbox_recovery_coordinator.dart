import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/inbox_recovery_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

typedef InboxRecoveryRunner = Future<InboxRecoveryBatchResult> Function(
  InboxRecoveryRunRequest request,
);

class InboxRecoveryRunRequest {
  const InboxRecoveryRunRequest({
    required this.trigger,
    required this.ownerUserId,
    required this.accountGeneration,
    required this.nowMs,
    required this.batchSize,
    required this.phase,
    required this.foreground,
    required this.activeConversationId,
  });

  final InboxRecoveryTrigger trigger;
  final String ownerUserId;
  final int accountGeneration;
  final int nowMs;
  final int batchSize;
  final ReconnectRecoveryPhase phase;
  final bool foreground;
  final String? activeConversationId;
}

class InboxRecoveryBatchResult {
  const InboxRecoveryBatchResult({
    this.scanned = 0,
    this.dispatched = 0,
    this.deferred = 0,
    this.dueCount = 0,
    this.pendingCount = 0,
    this.oldestPendingAgeMs = 0,
    this.retryCount = 0,
    this.queueWaitUs = 0,
    this.cpuUs = 0,
    this.dbUs = 0,
    this.nextRetryAtMs,
    this.moreDue = false,
  });

  final int scanned;
  final int dispatched;
  final int deferred;
  final int dueCount;
  final int pendingCount;
  final int oldestPendingAgeMs;
  final int retryCount;
  final int queueWaitUs;
  final int cpuUs;
  final int dbUs;
  final int? nextRetryAtMs;
  final bool moreDue;
}

class InboxRecoveryMetrics {
  const InboxRecoveryMetrics({
    required this.trigger,
    required this.joinInflight,
    required this.batchSize,
    required this.dueCount,
    required this.pendingCount,
    required this.queueWaitUs,
    required this.cpuUs,
    required this.dbUs,
    required this.rerunCount,
    required this.oldestPendingAgeMs,
    required this.retryCount,
    required this.reconnectStarted,
    required this.reconnectDeferredCount,
  });

  final InboxRecoveryTrigger trigger;
  final int joinInflight;
  final int batchSize;
  final int dueCount;
  final int pendingCount;
  final int queueWaitUs;
  final int cpuUs;
  final int dbUs;
  final int rerunCount;
  final int oldestPendingAgeMs;
  final int retryCount;
  final bool reconnectStarted;
  final int reconnectDeferredCount;
}

/// Single-flight Inbox recovery. Timer / reconnect / resume / new pending
/// all enter here. A running pass never starts a second worker.
class InboxRecoveryCoordinator {
  InboxRecoveryCoordinator({
    MessagePersistCoordinator? persist,
    this.fallbackInterval = const Duration(seconds: 30),
    this.batchSize = InboxRecoveryPolicy.defaultBatchSize,
  }) : _persist = persist ?? MessagePersistCoordinator.instance;

  static final InboxRecoveryCoordinator instance = InboxRecoveryCoordinator();

  final MessagePersistCoordinator _persist;
  final Duration fallbackInterval;
  final int batchSize;

  InboxRecoveryRunner? _runner;
  InboxRecoveryState _state = InboxRecoveryState.idle;
  String _ownerUserId = '';
  int _accountGeneration = 0;
  bool _foreground = true;
  ReconnectRecoveryPhase _phase = ReconnectRecoveryPhase.realtimeLink;
  Timer? _scheduledTimer;
  Timer? _fallbackTimer;
  Timer? _retryTimer;
  int _rerunCount = 0;
  int _joinInflight = 0;
  int _reconnectDeferredCount = 0;
  bool _reconnectStarted = false;
  InboxRecoveryMetrics? _lastMetrics;
  final List<InboxRecoveryMetrics> _metrics = <InboxRecoveryMetrics>[];

  InboxRecoveryState get state => _state;
  bool get foreground => _foreground;
  ReconnectRecoveryPhase get phase => _phase;
  InboxRecoveryMetrics? get lastMetrics => _lastMetrics;
  List<InboxRecoveryMetrics> get metricsSnapshot =>
      List<InboxRecoveryMetrics>.unmodifiable(_metrics);

  @visibleForTesting
  void resetForTest() {
    _scheduledTimer?.cancel();
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _scheduledTimer = null;
    _fallbackTimer = null;
    _retryTimer = null;
    _runner = null;
    _state = InboxRecoveryState.idle;
    _ownerUserId = '';
    _accountGeneration = 0;
    _foreground = true;
    _phase = ReconnectRecoveryPhase.realtimeLink;
    _rerunCount = 0;
    _joinInflight = 0;
    _reconnectDeferredCount = 0;
    _reconnectStarted = false;
    _lastMetrics = null;
    _metrics.clear();
  }

  void bind({
    required InboxRecoveryRunner runner,
    required String ownerUserId,
    required int accountGeneration,
  }) {
    _runner = runner;
    _ownerUserId = ownerUserId;
    _accountGeneration = accountGeneration;
    _phase = ReconnectRecoveryPhase.realtimeLink;
    _reconnectStarted = false;
    _reconnectDeferredCount = 0;
    _startFallbackTimer();
  }

  void unbind({int? accountGeneration}) {
    if (accountGeneration != null && accountGeneration != _accountGeneration) {
      return;
    }
    _scheduledTimer?.cancel();
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _scheduledTimer = null;
    _fallbackTimer = null;
    _retryTimer = null;
    _runner = null;
    _state = InboxRecoveryState.idle;
    _ownerUserId = '';
    _accountGeneration = 0;
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      _scheduledTimer?.cancel();
      _scheduledTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      _fallbackTimer?.cancel();
      _fallbackTimer = null;
      if (_state == InboxRecoveryState.scheduled) {
        _state = InboxRecoveryState.idle;
      }
      return;
    }
    _startFallbackTimer();
  }

  void bindAccountGeneration(int generation) {
    if (generation == _accountGeneration) return;
    _accountGeneration = generation;
    if (_state == InboxRecoveryState.running) {
      _state = InboxRecoveryState.rerunRequested;
    }
  }

  void markRealtimeLinkReady() {
    if (_phase == ReconnectRecoveryPhase.realtimeLink) {
      _phase = ReconnectRecoveryPhase.visibleGap;
    }
  }

  void request({
    required InboxRecoveryTrigger trigger,
    String? ownerUserId,
    int? accountGeneration,
    Duration delay = Duration.zero,
    int? nextRetryAtMs,
  }) {
    final owner = ownerUserId ?? _ownerUserId;
    final generation = accountGeneration ?? _accountGeneration;
    if (_runner == null || owner.isEmpty) return;
    if (owner != _ownerUserId || generation != _accountGeneration) {
      return;
    }
    if (!_foreground && trigger == InboxRecoveryTrigger.timerFallback) {
      return;
    }
    if (trigger == InboxRecoveryTrigger.reconnect) {
      _reconnectStarted = true;
      _phase = ReconnectRecoveryPhase.realtimeLink;
    }

    if (_state == InboxRecoveryState.running ||
        _state == InboxRecoveryState.rerunRequested) {
      _state = InboxRecoveryState.rerunRequested;
      _joinInflight += 1;
      _rerunCount += 1;
      return;
    }
    if (_state == InboxRecoveryState.scheduled) {
      _joinInflight += 1;
      return;
    }

    final wait = nextRetryAtMs == null
        ? delay
        : Duration(
            milliseconds: (nextRetryAtMs - DateTime.now().millisecondsSinceEpoch)
                .clamp(0, 60 * 1000),
          );
    _state = InboxRecoveryState.scheduled;
    _scheduledTimer?.cancel();
    _scheduledTimer = Timer(wait, () {
      _scheduledTimer = null;
      unawaited(_run(trigger: trigger, ownerUserId: owner, accountGeneration: generation));
    });
  }

  Future<void> _run({
    required InboxRecoveryTrigger trigger,
    required String ownerUserId,
    required int accountGeneration,
  }) async {
    if (_runner == null) {
      _state = InboxRecoveryState.idle;
      return;
    }
    if (ownerUserId != _ownerUserId ||
        accountGeneration != _accountGeneration) {
      _state = InboxRecoveryState.idle;
      return;
    }
    if (!_foreground && trigger == InboxRecoveryTrigger.timerFallback) {
      _state = InboxRecoveryState.idle;
      return;
    }
    if (trigger == InboxRecoveryTrigger.timerFallback ||
        trigger == InboxRecoveryTrigger.resume) {
      if (!_shouldProduce(trigger)) {
        _state = InboxRecoveryState.idle;
        return;
      }
    }

    _state = InboxRecoveryState.running;
    if (trigger == InboxRecoveryTrigger.reconnect &&
        _phase == ReconnectRecoveryPhase.realtimeLink) {
      _phase = ReconnectRecoveryPhase.visibleGap;
    } else if (_phase == ReconnectRecoveryPhase.visibleGap) {
      _phase = ReconnectRecoveryPhase.inboxHighPriority;
    }

    final persistBlocked = !_shouldProduce(trigger);
    if (persistBlocked && _isBackgroundOnlyPhase) {
      _reconnectDeferredCount += 1;
      _record(
        trigger: trigger,
        batchSize: 0,
        dueCount: 0,
        pendingCount: 0,
        queueWaitUs: 0,
        cpuUs: 0,
        dbUs: 0,
        oldestPendingAgeMs: 0,
        retryCount: 0,
      );
      _finishRun(trigger: trigger, nextRetryAtMs: null, moreDue: true);
      return;
    }

    final request = InboxRecoveryRunRequest(
      trigger: trigger,
      ownerUserId: ownerUserId,
      accountGeneration: accountGeneration,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      batchSize: _batchSizeFor(trigger),
      phase: _phase,
      foreground: _foreground,
      activeConversationId: _persist.activeChatConversationId,
    );
    InboxRecoveryBatchResult result;
    try {
      result = await _runner!(request);
    } catch (_) {
      result = const InboxRecoveryBatchResult();
    }
    if (ownerUserId != _ownerUserId ||
        accountGeneration != _accountGeneration) {
      _state = InboxRecoveryState.idle;
      return;
    }
    if (result.deferred > 0 && persistBlocked) {
      _reconnectDeferredCount += result.deferred;
    }
    _record(
      trigger: trigger,
      batchSize: result.scanned,
      dueCount: result.dueCount,
      pendingCount: result.pendingCount,
      queueWaitUs: result.queueWaitUs,
      cpuUs: result.cpuUs,
      dbUs: result.dbUs,
      oldestPendingAgeMs: result.oldestPendingAgeMs,
      retryCount: result.retryCount,
    );
    _advancePhase(result);
    _finishRun(
      trigger: trigger,
      nextRetryAtMs: result.nextRetryAtMs,
      moreDue: result.moreDue || result.scanned >= request.batchSize,
    );
  }

  void _finishRun({
    required InboxRecoveryTrigger trigger,
    required int? nextRetryAtMs,
    required bool moreDue,
  }) {
    final rerun = _state == InboxRecoveryState.rerunRequested;
    if (rerun) {
      _state = InboxRecoveryState.idle;
      request(trigger: trigger);
      return;
    }
    _state = InboxRecoveryState.idle;
    if (moreDue &&
        _phase != ReconnectRecoveryPhase.backgroundHistory &&
        _foreground) {
      if (_persist.shouldProduceBackground) {
        _phase = ReconnectRecoveryPhase.backgroundHistory;
        request(trigger: InboxRecoveryTrigger.retryDue);
      } else {
        _reconnectDeferredCount += 1;
      }
      return;
    }
    if (moreDue && _foreground && _shouldProduce(trigger)) {
      request(
        trigger: trigger == InboxRecoveryTrigger.reconnect
            ? InboxRecoveryTrigger.retryDue
            : trigger,
      );
      return;
    }
    if (nextRetryAtMs != null && _foreground) {
      _retryTimer?.cancel();
      final waitMs =
          (nextRetryAtMs - DateTime.now().millisecondsSinceEpoch).clamp(0, 60000);
      _retryTimer = Timer(Duration(milliseconds: waitMs), () {
        _retryTimer = null;
        request(trigger: InboxRecoveryTrigger.retryDue);
      });
    }
  }

  void _advancePhase(InboxRecoveryBatchResult result) {
    if (_phase == ReconnectRecoveryPhase.visibleGap && result.scanned == 0) {
      _phase = ReconnectRecoveryPhase.inboxHighPriority;
    } else if (_phase == ReconnectRecoveryPhase.inboxHighPriority &&
        result.scanned == 0 &&
        _persist.shouldProduceBackground) {
      _phase = ReconnectRecoveryPhase.backgroundHistory;
    }
  }

  bool get _isBackgroundOnlyPhase =>
      _phase == ReconnectRecoveryPhase.backgroundHistory;

  bool _shouldProduce(InboxRecoveryTrigger trigger) {
    if (trigger == InboxRecoveryTrigger.pendingWrite) {
      return true;
    }
    if (_phase == ReconnectRecoveryPhase.backgroundHistory ||
        trigger == InboxRecoveryTrigger.timerFallback) {
      return _persist.shouldProduceBackground;
    }
    return !_persist.hasRealtimeBacklog;
  }

  int _batchSizeFor(InboxRecoveryTrigger trigger) {
    final size = batchSize.clamp(
      InboxRecoveryPolicy.minBatchSize,
      InboxRecoveryPolicy.maxBatchSize,
    );
    if (trigger == InboxRecoveryTrigger.reconnect ||
        _phase == ReconnectRecoveryPhase.visibleGap ||
        _phase == ReconnectRecoveryPhase.inboxHighPriority) {
      return InboxRecoveryPolicy.minBatchSize;
    }
    return size;
  }

  void _startFallbackTimer() {
    _fallbackTimer?.cancel();
    if (!_foreground || _runner == null) return;
    _fallbackTimer = Timer.periodic(fallbackInterval, (_) {
      request(trigger: InboxRecoveryTrigger.timerFallback);
    });
  }

  void _record({
    required InboxRecoveryTrigger trigger,
    required int batchSize,
    required int dueCount,
    required int pendingCount,
    required int queueWaitUs,
    required int cpuUs,
    required int dbUs,
    required int oldestPendingAgeMs,
    required int retryCount,
  }) {
    final metrics = InboxRecoveryMetrics(
      trigger: trigger,
      joinInflight: _joinInflight,
      batchSize: batchSize,
      dueCount: dueCount,
      pendingCount: pendingCount,
      queueWaitUs: queueWaitUs,
      cpuUs: cpuUs,
      dbUs: dbUs,
      rerunCount: _rerunCount,
      oldestPendingAgeMs: oldestPendingAgeMs,
      retryCount: retryCount,
      reconnectStarted: _reconnectStarted,
      reconnectDeferredCount: _reconnectDeferredCount,
    );
    _lastMetrics = metrics;
    _metrics.add(metrics);
    if (_metrics.length > 64) {
      _metrics.removeRange(0, _metrics.length - 64);
    }
    _joinInflight = 0;
  }
}
