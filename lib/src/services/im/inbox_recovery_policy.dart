import 'dart:math';

import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';

enum InboxErrorClass {
  network,
  format,
  permanent,
  unknown,
}

enum InboxRecoveryTrigger {
  pendingWrite,
  reconnect,
  resume,
  retryDue,
  timerFallback,
}

enum InboxRecoveryState {
  idle,
  scheduled,
  running,
  rerunRequested,
}

enum ReconnectRecoveryPhase {
  realtimeLink,
  visibleGap,
  inboxHighPriority,
  backgroundHistory,
}

class InboxRecoveryPolicy {
  static const int defaultBatchSize = 40;
  static const int minBatchSize = 20;
  static const int maxBatchSize = 100;
  static const int maxRetryCount = 8;
  static const List<int> retryDelaysMs = <int>[
    2000,
    5000,
    15000,
    30000,
    60000,
  ];

  static int recoveryPriorityFor(ImEventKind kind) {
    switch (kind) {
      case ImEventKind.messageMutation:
        return 0;
      case ImEventKind.realtimeMessage:
      case ImEventKind.readReceipt:
        return 1;
      case ImEventKind.historyPage:
        return 3;
      default:
        return 2;
    }
  }

  static bool isHighPriority(int recoveryPriority) => recoveryPriority <= 1;

  static bool isBackgroundPriority(int recoveryPriority) =>
      recoveryPriority >= 3;

  static int nextRetryDelayMs(int retryCount, {int? jitterMs}) {
    final index = retryCount < 0
        ? 0
        : (retryCount >= retryDelaysMs.length
            ? retryDelaysMs.length - 1
            : retryCount);
    final base = retryDelaysMs[index];
    final jitter = jitterMs ?? _jitter(base);
    return base + jitter;
  }

  static int nextRetryAtMs({
    required int nowMs,
    required int retryCount,
    int? jitterMs,
  }) {
    return nowMs + nextRetryDelayMs(retryCount, jitterMs: jitterMs);
  }

  static bool isPermanent({
    required InboxErrorClass errorClass,
    required int retryCount,
  }) {
    if (errorClass == InboxErrorClass.permanent ||
        errorClass == InboxErrorClass.format) {
      return true;
    }
    return retryCount >= maxRetryCount;
  }

  static InboxErrorClass classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('timeout') ||
        text.contains('offline') ||
        text.contains('unavailable')) {
      return InboxErrorClass.network;
    }
    if (text.contains('format') ||
        text.contains('parse') ||
        text.contains('malformed')) {
      return InboxErrorClass.format;
    }
    if (text.contains('permanent') ||
        text.contains('invalid recovery') ||
        text.contains('not recoverable')) {
      return InboxErrorClass.permanent;
    }
    return InboxErrorClass.unknown;
  }

  static int _jitter(int baseMs) {
    if (baseMs <= 0) return 0;
    final span = max(1, (baseMs * 0.2).round());
    return Random().nextInt(span + 1);
  }
}

class InboxRecoveryCounts {
  const InboxRecoveryCounts({
    required this.pendingCount,
    required this.dueCount,
    this.oldestPendingAgeMs = 0,
  });

  final int pendingCount;
  final int dueCount;
  final int oldestPendingAgeMs;
}
