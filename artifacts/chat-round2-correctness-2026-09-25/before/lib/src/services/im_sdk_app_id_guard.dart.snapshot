import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/config.dart';
import 'package:tencent_cloud_chat_demo/src/services/local_account_data_purge.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';

/// F 块（v15/v16 / §11.1.4 Q8）：跨 SDKAppID 切换保护。
///
/// 腾讯 IM SDK 行为：
///   - 第一次 `initSDK` 之后 SDK 内部绑定当前 SDKAppID。
///   - 重复 `initSDK` 时若 SDKAppID 不同，SDK 服务端会返回错误码 20008
///     (`ERR_SDKAPPID_NOT_MATCH`)，且本地消息/会话会与旧 SDKAppID 错配。
///   - **必须**主动清盘（owner disk + InMemory conversation cache）后再登出，
///     否则下次冷启动会读到错误 SDKAppID 的会话索引，UI 永远展示错位数据。
///
/// 设计：
///   - 持久化「上一次成功 init 的 SDKAppID」到 SharedPreferences（key: `last_initsdk_appid`）。
///   - 启动时检查：
///     * 若 pref 不存在：首次启动，正常 init。
///     * 若 pref 存在且当前 SDKAppID == pref：正常 init。
///     * 若 pref 存在且当前 SDKAppID != pref：**立刻同步清盘**（不等待
///       IM login 报错，因为可能根本登不上）后正常 init。
///
/// 错误码 20008 / `ERR_SDKAPPID_NOT_MATCH` 在 SDK listener 出现时也兜底再清一次。
class ImSdkAppIdGuard {
  ImSdkAppIdGuard._();

  static final ImSdkAppIdGuard instance = ImSdkAppIdGuard._();

  /// SharedPreferences key。
  static const String _kLastInitSdkAppId = 'im_last_initsdk_appid';
  static const String _kLastInitResolvedOwner = 'im_last_initsdk_owner';

  /// 当前进程活跃的 SDKAppID（解析后落地）。
  int? _activeSdkAppId;

  /// 当前进程活跃的 owner（用于对照切换）。
  String? _activeResolvedOwner;

  /// 标记 F1（F2）方提到的"切换 SDKAppID"事件是否已完成清盘。
  /// 用于上层避免重复清盘。
  bool _purgeInFlight = false;

  /// 启动时由 App 入口调用一次。返回 `true` 表示**无需清盘**，可继续。
  /// 返回 `false` 表示**应清盘**。上层在拿到 false 后需拒绝 init sdk 并提示用户。
  /// 该函数不做任何破坏性 IO。
  ///
  /// FFB-5（v17）：增加 owner 空字符串 vs pref 非空字符串的边界审计——
  /// 如果 pref 记录的 owner 是空字符串、当前 owner 非空，视为"上次 init 时 owner
  /// 尚未就绪"，主动拒绝并要求上层清盘后重新走。
  Future<bool> ensureConsistentAtStart({
    required int resolvedSdkAppId,
    required String resolvedOwner,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAppId = prefs.getInt(_kLastInitSdkAppId);
      final lastOwner = prefs.getString(_kLastInitResolvedOwner) ?? '';
      _activeSdkAppId = resolvedSdkAppId;
      _activeResolvedOwner = resolvedOwner;
      // 首次或匹配：无需清盘。
      if (lastAppId == null || lastAppId == resolvedSdkAppId) {
        if (lastAppId == null) {
          // 首次启动：直接落盘（仅 owner 非空时写，避免污染 pref）。
          await prefs.setInt(_kLastInitSdkAppId, resolvedSdkAppId);
          if (resolvedOwner.isNotEmpty) {
            await prefs.setString(_kLastInitResolvedOwner, resolvedOwner);
          }
        }
        return true;
      }
      // 跨 SDKAppID：需要清盘。
      StartupPerfLog.markTagged(
        'sdkappid_change_detected',
        category: 'im_init',
        details: <String, Object>{
          'lastAppId': lastAppId,
          'currentAppId': resolvedSdkAppId,
          'lastOwner': lastOwner,
          'currentOwner': resolvedOwner,
          'phase': 'boot',
        },
      );
      return false;
    } catch (e) {
      // 启动期检测失败不应阻塞主流程；留 false 让上层继续。
      _activeSdkAppId = resolvedSdkAppId;
      _activeResolvedOwner = resolvedOwner;
      return true;
    }
  }

  /// 给上层使用：执行跨 SDKAppID 切换清盘（同步调用 owner-disk purge）。
  ///
  /// 调用前提：F1 `ensureConsistentAtStart` 返回 false。
  Future<void> purgeOwnerDiskForSdkAppIdChange({
    required String resolvedOwner,
    required int fromSdkAppId,
    required int toSdkAppId,
  }) async {
    if (_purgeInFlight) return;
    _purgeInFlight = true;
    try {
      // 这里清盘的 owner 是「旧 SDKAppID」所绑定的、当前可能在 SharedPreferences 的 owner。
      // 上层一般已在 `clearForLogout` 阶段先调用过；本函数兜底独立跑一次。
      if (resolvedOwner.isNotEmpty) {
        await LocalAccountDataPurge.instance.purgeOwnerDisk(resolvedOwner);
      }
      StartupPerfLog.markTagged(
        'sdkappid_purge_owner_disk_finished',
        category: 'im_init',
        details: <String, Object>{
          'fromSdkAppId': fromSdkAppId,
          'toSdkAppId': toSdkAppId,
          'owner': resolvedOwner,
        },
      );
      // 完成后落地新 SDKAppID。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastInitSdkAppId, toSdkAppId);
      if (resolvedOwner.isNotEmpty) {
        await prefs.setString(_kLastInitResolvedOwner, resolvedOwner);
      }
    } finally {
      _purgeInFlight = false;
    }
  }

  /// 正常成功 init SDK 后由调用方标记落地。
  ///
  /// FFB-5（v17）：新增 [isOwnerResolved] 参数。如果调用方已经把 owner
  /// 解析完成（如 IM login 后），传 `true`；此时若 [resolvedOwner] 是空字符串，
  /// **禁止**写 pref（避免污染），改为打 `sdkappid_mark_init_owner_empty_blocked`
  /// 埋点。如果调用方在 owner 还未就绪时调（如 `_coreInstance.init` 早于 login），
  /// 传 `false`（默认值），仍按原行为写 pref（但仅在 owner 非空时写）。
  Future<void> markInitSuccess({
    required int sdkAppId,
    required String resolvedOwner,
    bool isOwnerResolved = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // FFB-5：登录路径上 owner 已解析但仍为空 → 阻止污染 pref。
    if (isOwnerResolved && resolvedOwner.isEmpty) {
      StartupPerfLog.markTagged(
        'sdkappid_mark_init_owner_empty_blocked',
        category: 'im_init',
        details: <String, Object>{
          'sdkAppId': sdkAppId,
          'owner': resolvedOwner,
          'phase': 'mark_init_success',
        },
      );
      // 仍然写 appid，因为 appid 是关键；只跳过 owner 写。
      await prefs.setInt(_kLastInitSdkAppId, sdkAppId);
      _activeSdkAppId = sdkAppId;
      _activeResolvedOwner = resolvedOwner;
      return;
    }
    await prefs.setInt(_kLastInitSdkAppId, sdkAppId);
    if (resolvedOwner.isNotEmpty) {
      await prefs.setString(_kLastInitResolvedOwner, resolvedOwner);
    }
    _activeSdkAppId = sdkAppId;
    _activeResolvedOwner = resolvedOwner;
    StartupPerfLog.markTagged(
      'sdkappid_init_success',
      category: 'im_init',
      details: <String, Object>{
        'sdkAppId': sdkAppId,
        'owner': resolvedOwner,
        'ownerResolved': isOwnerResolved,
        'fallbackSdkAppId': IMDemoConfig.sdkAppID,
      },
    );
  }

  /// 兜底——SDK listener 出现错误码 20008 时调用。
  /// [code] 20008 / ERR_SDKAPPID_NOT_MATCH。
  Future<void> onSdkErrorCode({
    required int code,
    String? message,
  }) async {
    if (code != 20008) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAppId = prefs.getInt(_kLastInitSdkAppId);
      StartupPerfLog.markTagged(
        'sdkappid_mismatch_sdk_error',
        category: 'im_init',
        details: <String, Object>{
          'code': code,
          'message': message ?? '',
          'lastAppId': lastAppId ?? -1,
          'activeSdkAppId': _activeSdkAppId ?? -1,
          'phase': 'sdk_listener',
        },
      );
      if (lastAppId != null &&
          _activeSdkAppId != null &&
          lastAppId != _activeSdkAppId) {
        await purgeOwnerDiskForSdkAppIdChange(
          resolvedOwner: _activeResolvedOwner ?? '',
          fromSdkAppId: lastAppId,
          toSdkAppId: _activeSdkAppId!,
        );
      }
    } catch (e) {
      // 出错静默，避免主流程被 metrics 拖累。
    }
  }

  /// 仅用于测试：清空落地值。
  Future<void> debugReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastInitSdkAppId);
    await prefs.remove(_kLastInitResolvedOwner);
    _activeSdkAppId = null;
    _activeResolvedOwner = null;
  }
}
