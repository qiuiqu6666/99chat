import 'package:tencent_cloud_chat_sdk/models/common_utils.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// F 块 P3 / F5（v15/v16）：登出后立即冷启动 audit 帮手——给出 owner disk 状态快照，
/// 便于验证「清盘是否真的清干净」，也能用于生产环境异常分析。
///
/// 关键问题（v15 §11.1.4）：
///   - "登出后立即冷启动" 时 owner disk 必须已被清空，否则下一账号首次启动
///     会读到上一账号的会话预览。
///   - 现有架构 (`clearForLogout` + `LocalAccountDataPurge.purgeOwnerDisk`)
///     在常见路径上保证清盘，但生产环境仍有「调用顺序错乱 / 时序竞争」导致
///     残留会话行的可能。
///
/// 本文件提供 [snapshotNow]，在以下时机调用即可打点：
///   - `clearForLogout` finish 之后
///   - cold-start bootstrap 完成 `ConversationLocalStore.countRows` 之前
///   - 任何怀疑「清盘不彻底」的事故调查时
class OwnerDiskStateSnapshot {
  OwnerDiskStateSnapshot._();

  /// 打一条 `owner_disk_state` 埋点 — 包含本地库的 row 数、当前 owner 状态。
  ///
  /// 不抛错，所有异常吞到 debugPrint。
  static Future<void> snapshotNow({
    required String phase,
    String? hintOwner,
  }) async {
    try {
      final owner = hintOwner ?? _resolveOwnerForAudit();
      final store = ConversationLocalStore.instance;
      int c2cRows = 0;
      int groupRows = 0;
      try {
        c2cRows = await store.countByConvType(
          convType: 1,
          ownerUserId: owner,
        );
      } catch (_) {}
      try {
        groupRows = await store.countByConvType(
          convType: 2,
          ownerUserId: owner,
        );
      } catch (_) {}
      StartupPerfLog.markTagged(
        'owner_disk_state',
        category: 'account_lifecycle',
        details: <String, Object>{
          'phase': phase,
          'owner': owner,
          'c2cRows': c2cRows,
          'groupRows': groupRows,
          'totalRows': c2cRows + groupRows,
        },
      );
      // 单独的 total 看会被 sentry 报警。
      final total = c2cRows + groupRows;
      if (total > 0) {
        StartupPerfLog.markTagged(
          'owner_disk_state_residual_rows',
          category: 'account_lifecycle',
          details: <String, Object>{
            'phase': phase,
            'owner': owner,
            'c2cRows': c2cRows,
            'groupRows': groupRows,
            'totalRows': total,
          },
        );
      }
    } catch (e) {
      // 仅打印，不影响上层。
      // ignore: avoid_print
      print('[OwnerDiskStateSnapshot] failed: $e');
    }
  }

  static String _resolveOwnerForAudit() {
    try {
      final v = CommonUtils.getLoginUser();
      return v.isEmpty ? '' : v;
    } catch (_) {
      return '';
    }
  }
}
