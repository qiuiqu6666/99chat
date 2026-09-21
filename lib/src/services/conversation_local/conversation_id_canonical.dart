// P1-2: 写入侧会话 ID 归一。
//
// 日志里观察到同一个会话同时存在
//   `@TGS#_mc2SX4NMM62CZ` 与 `group_@TGS#_mc2SX4NMM62CZ`
//   `m2E3PN2N5CX` 与 `group_m2E3PN2N5CX`
// 这导致 ConvLocalStore / chat_history_peek_bootstrap 等写入侧 map 出现
// 双 key cache 行：cache 重复、history_warm_stale_reconcile 双跑、
// 同一可见投影重复构建。
//
// 读侧保持原状（`_inboundStateKey` / `_isSameConversationID` 已做别名合并）；
// 这里只约束「写入 storage key 时统一形态」。读取时仍然按现有别名查找。
//
// 选择 ChatIdFormat.canonicalGroupStorageId 作为唯一权威形态：
//   - 群 ID：去掉 `group_` 前缀 → 写出时不带前缀；写入 storage 时若读方期待
//     `group_<canonical>`，由现有 `group_<canonical>` 反向读取走别名合并
//     路径命中（`_inboundStateKey` 在 tui_chat_global_model.dart 中已实现）。
//   - c2c：保留 `c2c_<uid>` 形态（无歧义）。
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

class ConversationIdCanonical {
  ConversationIdCanonical._();

  /// 写入 ConvLocalStore / chat_history_peek_bootstrap / 角标聚合等
  /// 「内部 cache key」时统一调用本函数。
  ///
  /// 行为：
  /// - 空串返回空串。
  /// - `group_<x>`：返回 `x` 的 canonical（去掉前缀再 canonicalize 再回加）。
  /// - `c2c_<x>`：原样返回。
  /// - 其它：若看起来像群 ID（含 @TGS#、短码形态），canonicalize；否则原样。
  static String forStorage(String rawConversationId) {
    final trimmed = rawConversationId.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('group_')) {
      final inner = trimmed.substring(6).trim();
      if (inner.isEmpty) {
        return trimmed;
      }
      final canonical = ChatIdFormat.canonicalGroupStorageId(inner);
      if (canonical.isEmpty) {
        return trimmed;
      }
      return canonical;
    }
    if (lower.startsWith('c2c_')) {
      return trimmed;
    }
    if (_looksLikeGroupId(trimmed)) {
      final canonical = ChatIdFormat.canonicalGroupStorageId(trimmed);
      if (canonical.isNotEmpty) {
        return canonical;
      }
    }
    return trimmed;
  }

  static bool _looksLikeGroupId(String id) {
    if (id.isEmpty) return false;
    if (id.startsWith('@')) return true;
    if (ChatIdFormat.looksLikeCommunityGroupId(id)) return true;
    return false;
  }
}
