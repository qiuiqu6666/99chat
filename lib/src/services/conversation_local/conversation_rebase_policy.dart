import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
// Pull in UIKit's [ConvType] enum (c2c / group / none).
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart'
    show ConvType;
// `ImConversationType` is referenced indirectly for local enums only;
// path comment kept for future extension.

/// E 块（v15/v16 §11.1.3 / §12.19）：Rebase 策略——超大积压跳位点。
///
/// 设计动机：
///   - "**慢但不能漏**"是业界共识（用户能容忍补 3s，但不能漏掉老板的早会@）。
///   - 但 5000+ 条 C2C 积压 / 10000+ 条群积压在低端机上解码会卡 5s+，体感"卡死"。
///   - 与其阻塞前 5s 等全部解码完，不如触发 Rebase：跳到 newestSeq-K，留下最近 K 条，
///     用户的"最新对话"立刻可见，旧的让 idle / 后台异步补。
///
/// 触发逻辑：
///   1. 监听 SDK `onSyncServerFinish`/`onConversationChanged` 时，比较本地 cursor 与 SDK newestSeq。
///   2. 差值超过 [ConversationPerfFlags.rebaseC2cBacklogThreshold] /
///      [ConversationPerfFlags.rebaseGroupBacklogThreshold] 时，本会话进入 Rebase 流程。
///   3. 同一会话在 [ConversationPerfFlags.rebaseCooldown] 内只触发一次。
///
/// Rebase 行为：
///   1. 把会话元数据行 cursor 标为 `rebaseCursor = newestSeq - rebaseKeepRecent`。
///   2. UI 显示 Rebase banner（E3）："X 条消息已跳过，点击查看"。
///   3. SDK listener 继续按新 cursor 续拉，旧的由 SDK 服务端按需供拉。
///
/// 本文件只承载策略状态/判定/可观测性；具体 cursor 修改在
/// [ConversationSyncService] 的 `_applyRebase` 阶段调用 [evaluateRebaseTrigger]。
class ConversationRebasePolicy {
  ConversationRebasePolicy._();

  static final ConversationRebasePolicy instance = ConversationRebasePolicy._();

  /// 最近一次触发 Rebase 的会话 ID + 时刻，用于冷却控制。
  final Map<String, DateTime> _lastRebaseAtByConvId = <String, DateTime>{};

  /// 当前还在展示 Rebase banner 的会话集合（按 conv id → 元数据）。
  /// UI 通过监听 `_bannersNotifier` 来刷新。
  final Map<String, RebaseBannerEntry> _activeBanners =
      <String, RebaseBannerEntry>{};

  final ValueNotifier<int> _bannersVersionNotifier = ValueNotifier<int>(0);

  /// UI 监听此 notifier 即可在 banner 集合变化时收到通知。
  ValueListenable<int> get bannersVersion => _bannersVersionNotifier;

  /// 当前活跃 banner 快照（不可变）。
  List<RebaseBannerEntry> activeBanners() {
    final now = DateTime.now();
    final ttl = ConversationPerfFlags.rebaseBannerTtl;
    // 顺手回收过期 banner（30s TTL 内可见，过期后删除）。
    final expired = _activeBanners.entries
        .where((e) => now.difference(e.value.createdAt) > ttl)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _activeBanners.remove(id);
    }
    if (expired.isNotEmpty) {
      _bannersVersionNotifier.value++;
    }
    if (_activeBanners.isEmpty) return const <RebaseBannerEntry>[];
    final list = _activeBanners.values.toList(growable: false);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 判定给定会话是否应触发 Rebase。
  ///
  /// [convType] 用 [ConvType.c2c] / [ConvType.group] 二选一。
  /// [sdkNewestSeq] SDK 当前会话最新 seq；[localCursorSeq] 本地 cursor 已知 seq。
  /// 返回 `null` 表示无需 Rebase；否则返回结构化结果。
  RebaseDecision? evaluateRebaseTrigger({
    required String conversationId,
    required ConvType convType,
    required int sdkNewestSeq,
    required int localCursorSeq,
  }) {
    if (!ConversationPerfFlags.pacedSdkPersist) {
      return null;
    }
    if (sdkNewestSeq <= 0 || localCursorSeq < 0) {
      return null;
    }
    final backlog = sdkNewestSeq - localCursorSeq;
    if (backlog <= 0) {
      return null;
    }
    final threshold = convType == ConvType.group
        ? ConversationPerfFlags.rebaseGroupBacklogThreshold
        : ConversationPerfFlags.rebaseC2cBacklogThreshold;
    if (backlog < threshold) {
      return null;
    }
    // 冷却：避免同一会话连续触发 storm。
    final lastAt = _lastRebaseAtByConvId[conversationId];
    final cooldown = ConversationPerfFlags.rebaseCooldown;
    if (lastAt != null &&
        DateTime.now().difference(lastAt) < cooldown) {
      return null;
    }
    final keep = ConversationPerfFlags.rebaseKeepRecent;
    final newCursor = sdkNewestSeq - keep;
    return RebaseDecision(
      conversationId: conversationId,
      convType: convType,
      backlog: backlog,
      oldCursor: localCursorSeq,
      newCursor: newCursor,
      skippedMessages: backlog - keep,
    );
  }

  /// 应用 Rebase：写状态 + log + 暴露 banner。
  /// 实际 SDK cursor 写入由调用方负责（往往在 [ConversationSyncService]）。
  void applyRebase(RebaseDecision decision) {
    final id = decision.conversationId;
    _lastRebaseAtByConvId[id] = DateTime.now();
    if (ConversationPerfFlags.rebaseBannerEnabled) {
      _activeBanners[id] = RebaseBannerEntry(
        conversationId: id,
        convType: decision.convType,
        skipped: decision.skippedMessages,
        rebaseAtMs: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now(),
      );
      _bannersVersionNotifier.value++;
    }
    ConversationPerfGateLog.log(
      'conv_rebase_triggered',
      extras: <String, Object?>{
        'conversationId': id,
        'convType': decision.convType.name,
        'backlog': decision.backlog,
        'oldCursor': decision.oldCursor,
        'newCursor': decision.newCursor,
        'skipped': decision.skippedMessages,
      },
    );
  }

  /// 用户点 banner「查看」时由 UI 调用；返回该会话的 SDK 服务端 hint ID 以便上层跳转。
  void dismissBanner(String conversationId) {
    if (_activeBanners.remove(conversationId) != null) {
      _bannersVersionNotifier.value++;
    }
  }
}

/// 单个 Rebase 判定结果。
@immutable
class RebaseDecision {
  const RebaseDecision({
    required this.conversationId,
    required this.convType,
    required this.backlog,
    required this.oldCursor,
    required this.newCursor,
    required this.skippedMessages,
  });

  final String conversationId;
  final ConvType convType;
  final int backlog;
  final int oldCursor;

  /// 新的 cursor，建议直接跳到该值（= newestSeq - rebaseKeepRecent）。
  final int newCursor;

  /// 共跳过了多少条消息（UI 给用户看的数量）。
  final int skippedMessages;
}

/// UI 展示用的 Rebase banner 元数据。
@immutable
class RebaseBannerEntry {
  const RebaseBannerEntry({
    required this.conversationId,
    required this.convType,
    required this.skipped,
    required this.rebaseAtMs,
    required this.createdAt,
  });

  final String conversationId;
  final ConvType convType;
  final int skipped;
  final int rebaseAtMs;
  final DateTime createdAt;
}

/// 会话类型投影工具——把 [ConvType]（UIKit 中 `c2c`/`group`/`none`）落地到
/// Rebase 阈值决策。注意 UIKit 的 `ConvType.none` 视作 c2c 退路。
ConvType convTypeFromV2(int? type) {
  switch (type) {
    case 2:
      return ConvType.group;
    case 1:
    default:
      return ConvType.c2c;
  }
}

/// 把 SDK `V2TimMessage.seq` 安全提取为 int。
///
/// 腾讯 SDK V2TimMessage.seq 是 String?（API 用 json 序列化）。
int safeExtractSeq(V2TimMessage? msg) {
  if (msg == null) return 0;
  final raw = msg.seq;
  if (raw == null || raw.isEmpty) return 0;
  return int.tryParse(raw) ?? 0;
}

/// 把 SDK `V2TimConversation` 的 cursor 等价物安全提取。
int safeExtractConvLastSeq(V2TimConversation? conv) {
  if (conv == null) return 0;
  // Flutter SDK V2TimConversation 没有直接 cursor 字段，
  // orderkey 仍可作为「会话维度 seq 兜底」。
  return conv.orderkey ?? 0;
}
