import 'dart:collection';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// 内部 helper：把 [V2TimMessage.seq]（String?）安全转 int。
int safeExtractSeq(V2TimMessage? msg) {
  if (msg == null) return 0;
  final raw = msg.seq;
  if (raw == null || raw.isEmpty) return 0;
  final v = int.tryParse(raw);
  return v ?? 0;
}

/// E9（v15/v16 / §12.19）：seq 单调性 gap detection 埋点。
///
/// 重连 / SDK listener 累积过程中，会话内消息 seq 可能出现空洞：
///   - 服务端补拉丢了若干条（漏掉某些 seq）。
///   - SDK listener 顺序与发送顺序错乱，乱序合并导致 seq 中空缺。
///
/// 检测方法（环形窗口）：
///   - 每个会话保留最近 N 条消息 seq（默认 64）。
///   - 新消息到达时，先排序窗口，若相邻差 > 1 视为 gap。
///   - gap>1 连续多少次触发 `seq_gap_detected` 埋点 + 累计 gap 数量。
///
/// 本 detector 只观测不修改：UI 元数据先行接收，messageID 去重是另一道关（v15 §12.16）。
class ConversationSeqGapDetector {
  ConversationSeqGapDetector._();

  static final ConversationSeqGapDetector instance =
      ConversationSeqGapDetector._();

  final Map<String, List<int>> _windowByConv = <String, List<int>>{};
  final Map<String, int> _maxSeenByConv = <String, int>{};

  static const int _fallbackWindow = 64;

  int _windowSize() => ConversationPerfFlags.seqGapWindowSize > 0
      ? ConversationPerfFlags.seqGapWindowSize
      : _fallbackWindow;

  /// 接收一条消息（仅观察 seq，不入库）。
  ///
  /// 返回值：true 表示探测到 gap 并已埋点；false 表示无 gap 或开关关闭。
  bool observe(String conversationId, V2TimMessage? msg) {
    if (!ConversationPerfFlags.seqGapDetectionEnabled) {
      return false;
    }
    if (msg == null || conversationId.isEmpty) return false;
    // 腾讯 SDK V2TimMessage.seq 是 String?（API 用 json 序列化）。
    final seq = safeExtractSeq(msg);
    if (seq <= 0) return false;
    final convId = conversationId.trim();
    final window = _windowByConv.putIfAbsent(
      convId,
      () => <int>[],
    );
    final maxSeen = _maxSeenByConv[convId] ?? 0;
    // 重复 seq 不算 gap。
    if (seq == maxSeen) {
      return false;
    }
    int gap = 0;
    if (seq > maxSeen) {
      // 前进 seq。
      gap = (seq - maxSeen - 1).clamp(0, 1 << 20);
      _maxSeenByConv[convId] = seq;
    } else if (window.isNotEmpty) {
      // 乱序到达：基于相邻比较判 gap。
      gap = _detectOutOfOrderGap(window, seq);
    }
    window.add(seq);
    // 滚动窗口。
    while (window.length > _windowSize()) {
      window.removeAt(0);
    }
    if (gap <= 0) return false;
    StartupPerfLog.markTagged(
      'seq_gap_detected',
      category: 'msg_realtime',
      details: <String, Object>{
        'conversationId': convId,
        'seq': seq,
        'maxSeen': maxSeen,
        'gap': gap,
        'msgId': msg.msgID ?? '',
        'windowSize': window.length,
      },
    );
    return true;
  }

  /// 直接注入 seq 序列用于测试。
  void debugInject(String conversationId, Iterable<int> seqs) {
    final convId = conversationId.trim();
    if (convId.isEmpty) return;
    final list = _windowByConv.putIfAbsent(convId, () => <int>[]);
    for (final s in seqs) {
      if (s <= 0) continue;
      list.add(s);
      final cur = _maxSeenByConv[convId] ?? 0;
      if (s > cur) {
        _maxSeenByConv[convId] = s;
      }
    }
    while (list.length > _windowSize()) {
      list.removeAt(0);
    }
  }

  /// 抄底——dump 当前窗口用于诊断。不可变视图。
  List<int> snapshotWindow(String conversationId) {
    final convId = conversationId.trim();
    final list = _windowByConv[convId];
    if (list == null) return const [];
    return UnmodifiableListView<int>(list);
  }

  void clear(String conversationId) {
    final convId = conversationId.trim();
    _windowByConv.remove(convId);
    _maxSeenByConv.remove(convId);
  }

  void clearAll() {
    _windowByConv.clear();
    _maxSeenByConv.clear();
  }

  // ====================================================================
  // FFB-3：cloud catch-up seq gap 桥接
  // ====================================================================
  // 来源：`[ChatHistory] event=cloud_catch_up_settled reason=seq_gap_<a>_<b>`
  // 是另一条独立的 seq gap 数据源：本 detector 之前只覆盖 SDK realtime 流，
  // cloud catch-up 流程的 gap 信息没有被探测到。本方法把这条数据源桥接进来：
  //   - gap > `seqGapWindowSize`（含 `seqGapWindowSize` 作为阈值下限）触发
  //     `seq_gap_detected{source: 'cloud_catch_up_settled'}` 埋点；
  //   - 否则只累加 `seq_gap_window_observed{kind: 'cloud', gap}` 计数。
  //
  // 已知限制：`ChatHistoryTrace.log` 在 UIKit 三方包里（third_party/...）
  // 没有公开 hook；`MessageCloudCatchUpResult` 也不携带 seq 区间。
  // 因此当前调用点仅供我们自己云端 catch-up 路径使用（chat 页 history_warm
  // / archive 历史拉取后比对最新 seq 时调用）。三方 UIKit 云端补拉的回调
  // 留待后续 UIKit 暴露 callback 后再接入。

  static const String _cloudGapSourceTag = 'cloud_catch_up_settled';

  /// 桥接 cloud catch-up gap 数据。
  ///
  /// 参数：
  ///   - [conversationId]：会话 id（C2C user_id / Group @TGS#_xxx）。
  ///   - [lowSeq] / [highSeq]：cloud catch-up 观察到的断层两端 seq。
  ///     注意顺序 — 调用方若不确定方向，请传已知较旧 / 较新的两端，由方法内部判定。
  ///
  /// 返回值：true 表示 gap 超过阈值并打了 `seq_gap_detected` 埋点。
  bool recordCloudCatchUpSettled({
    required String conversationId,
    required int lowSeq,
    required int highSeq,
  }) {
    if (!ConversationPerfFlags.seqGapDetectionEnabled) return false;
    final convId = conversationId.trim();
    if (convId.isEmpty) return false;
    if (lowSeq <= 0 || highSeq <= 0) return false;
    final gap = (highSeq - lowSeq).abs();
    if (gap <= 0) return false;
    final threshold = _windowSize();
    if (gap < threshold) {
      // 不打主流埋点，只发低优观察埋点（保留可观测性，但避免 sentry spam）。
      StartupPerfLog.markTagged(
        'seq_gap_window_observed',
        category: 'msg_realtime',
        details: <String, Object>{
          'source': _cloudGapSourceTag,
          'conversationId': convId,
          'gap': gap,
          'low': lowSeq,
          'high': highSeq,
          'threshold': threshold,
        },
      );
      return false;
    }
    StartupPerfLog.markTagged(
      'seq_gap_detected',
      category: 'msg_realtime',
      details: <String, Object>{
        'source': _cloudGapSourceTag,
        'conversationId': convId,
        'gap': gap,
        'low': lowSeq,
        'high': highSeq,
        'threshold': threshold,
      },
    );
    return true;
  }

  /// 在乱序到达场景下用排好序的窗口估算 gap。
  static int _detectOutOfOrderGap(List<int> window, int incoming) {
    if (window.isEmpty) return 0;
    final sorted = List<int>.from(window)..sort();
    var nearestAbove = -1;
    for (final s in sorted) {
      if (s > incoming) {
        nearestAbove = s;
        break;
      }
    }
    if (nearestAbove > incoming + 1) {
      return nearestAbove - incoming - 1;
    }
    return 0;
  }
}
