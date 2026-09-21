import 'package:flutter/foundation.dart';

import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// E7（v15/v16）：离线状态可观测——记录「30 天未拉过离线的用户占比 / 拉取 P99 延迟 /
/// payload 大小分布」。
///
/// 设计：
///   - 离线拉取失败/超时：每次记一条 `offline_pull_event{status, latencyMs, payloadBytes}`。
///   - 30 天活跃阈值：从 SharedPreferences 读 `last_offline_pull_at_ms`，由调用方更新。
///   - 占位仅承载埋点 + 内存直方图；不落库，避免污染主链。
class ConversationOfflineStats {
  ConversationOfflineStats._();

  static final ConversationOfflineStats instance = ConversationOfflineStats._();

  /// 离线拉取的 P99 延迟跟踪。每次成功/失败入队一个 sample，超 cap 时整体 flush。
  final List<int> _latencyMsSamples = <int>[];
  final List<int> _payloadBytesSamples = <int>[];
  int _totalSuccess = 0;
  int _totalFailed = 0;
  int _totalRebase = 0;

  /// 每帧最多保留多少样本点；超出 FIFO 截尾。
  static const int _sampleCap = 200;

  void recordPullStart() {
    if (!ConversationPerfFlags.offlineStatsLogEnabled) return;
    StartupPerfLog.markTagged(
      'offline_pull_event_start',
      category: 'offline_sync',
      details: <String, Object>{},
    );
  }

  void recordPullSuccess({
    required int latencyMs,
    required int payloadBytes,
    required int pulledCount,
    required String owner,
  }) {
    if (!ConversationPerfFlags.offlineStatsLogEnabled) return;
    _totalSuccess++;
    _appendSample(_latencyMsSamples, latencyMs);
    _appendSample(_payloadBytesSamples, payloadBytes);
    StartupPerfLog.markTagged(
      'offline_pull_event',
      category: 'offline_sync',
      details: <String, Object>{
        'status': 'success',
        'latencyMs': latencyMs,
        'payloadBytes': payloadBytes,
        'pulledCount': pulledCount,
        'owner': owner,
      },
    );
    // P99 监视：超 2000ms 单独标红。
    if (latencyMs >= 2000) {
      StartupPerfLog.markTagged(
        'offline_pull_latency_warning',
        category: 'offline_sync',
        details: <String, Object>{
          'latencyMs': latencyMs,
          'owner': owner,
          'pulledCount': pulledCount,
        },
      );
    }
  }

  void recordPullFailure({
    required int latencyMs,
    required int code,
    String? message,
    required String owner,
  }) {
    if (!ConversationPerfFlags.offlineStatsLogEnabled) return;
    _totalFailed++;
    _appendSample(_latencyMsSamples, latencyMs);
    StartupPerfLog.markTagged(
      'offline_pull_event',
      category: 'offline_sync',
      details: <String, Object>{
        'status': 'failed',
        'latencyMs': latencyMs,
        'code': code,
        'message': message ?? '',
        'owner': owner,
      },
    );
  }

  void recordRebase({required String conversationId, required int backlog}) {
    if (!ConversationPerfFlags.offlineStatsLogEnabled) return;
    _totalRebase++;
    StartupPerfLog.markTagged(
      'offline_rebase_event',
      category: 'offline_sync',
      details: <String, Object>{
        'conversationId': conversationId,
        'backlog': backlog,
      },
    );
  }

  /// 输出当前样本的 P50 / P95 / P99 摘要。
  /// [source] 用于区分 "latency" 或 "payload"。
  @visibleForTesting
  Map<String, int> summary(String source) {
    final list = source == 'latency'
        ? _latencyMsSamples
        : source == 'payload'
            ? _payloadBytesSamples
            : <int>[];
    if (list.isEmpty) return const {};
    final sorted = List<int>.from(list)..sort();
    final n = sorted.length;
    int at(double q) {
      final idx = (q * n).clamp(0, n - 1).toInt();
      return sorted[idx];
    }

    return <String, int>{
      'count': n,
      'p50': at(0.50),
      'p95': at(0.95),
      'p99': at(0.99),
      'max': sorted.last,
      'min': sorted.first,
    };
  }

  void clear() {
    _latencyMsSamples.clear();
    _payloadBytesSamples.clear();
    _totalSuccess = 0;
    _totalFailed = 0;
    _totalRebase = 0;
  }

  int get totalSuccess => _totalSuccess;
  int get totalFailed => _totalFailed;
  int get totalRebase => _totalRebase;

  static void _appendSample(List<int> list, int v) {
    list.add(v);
    if (list.length > _sampleCap) {
      list.removeRange(0, list.length - _sampleCap);
    }
  }
}
