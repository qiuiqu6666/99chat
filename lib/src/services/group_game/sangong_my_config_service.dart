import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_my_config.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// 当前群相对 my-config 的入口判定结果。
class SangongMyConfigGroupAccess {
  const SangongMyConfigGroupAccess({
    this.configured = false,
    this.needsSetup = false,
    this.canEditConfig = false,
    this.canManageMembers = false,
    this.myRole = '',
    this.tenantId = '',
  });

  final bool configured;
  final bool needsSetup;
  final bool canEditConfig;
  final bool canManageMembers;
  final String myRole;
  final String tenantId;

  bool get hasOpsAccess => configured && !needsSetup;
  bool get hasEntry => needsSetup || hasOpsAccess;

  bool sameAs(SangongMyConfigGroupAccess other) {
    return configured == other.configured &&
        needsSetup == other.needsSetup &&
        canEditConfig == other.canEditConfig &&
        canManageMembers == other.canManageMembers &&
        myRole == other.myRole &&
        tenantId == other.tenantId;
  }
}

/// 三公 my-config：登录/冷启动读本地秒开，后台刷新网络并回写。
class SangongMyConfigService {
  SangongMyConfigService._();

  static final SangongMyConfigService instance = SangongMyConfigService._();

  /// `null` 表示尚未灌过本地缓存（与「已缓存未配置」区分）。
  final ValueNotifier<SangongMyConfig?> configListenable =
      ValueNotifier<SangongMyConfig?>(null);

  String? _activeOwner;
  bool _hydrated = false;
  Future<SangongMyConfig>? _inflightRefresh;
  int _configRevision = 0;

  bool get hasCachedConfig => configListenable.value != null;

  SangongMyConfig get config =>
      configListenable.value ?? const SangongMyConfig();

  String _resolveOwner(String? userId) {
    return ChatIdFormat.rawUserUid(
      userId ?? SangongMyConfigStore.instance.currentOwnerUserId(),
    );
  }

  /// 仅灌本地缓存（不打网络），进群页可 await 后秒开 UI。
  Future<void> ensureHydrated({String? userId}) async {
    final owner = _resolveOwner(userId);
    if (owner.isEmpty) {
      return;
    }
    final switchingUser = _activeOwner != null && _activeOwner != owner;
    _activeOwner = owner;
    if (_hydrated && !switchingUser) {
      return;
    }
    final cached = await SangongMyConfigStore.instance.read(
      ownerUserId: owner,
    );
    _hydrated = true;
    _applyConfig(cached, notify: true);
  }

  /// 登录成功或冷启动恢复会话后调用：先本地、后网络。
  Future<void> activateSession({String? userId}) async {
    await ensureHydrated(userId: userId);
    unawaited(refreshFromNetwork());
  }

  void clearSession() {
    _configRevision++;
    _activeOwner = null;
    _hydrated = false;
    _inflightRefresh = null;
    _applyConfig(null, notify: true);
  }

  /// 服务端确认租户不存在时，清除本地失效配置，避免下次继续使用旧租户。
  Future<void> clearCachedConfig() async {
    final owner = _activeOwner ?? _resolveOwner(null);
    clearSession();
    if (owner.isNotEmpty) {
      await SangongMyConfigStore.instance.clearOwner(owner);
    }
  }

  /// 保存成功后立刻写入内存 + 本地，避免再等网络。
  Future<void> applySaved(SangongMyConfig config) async {
    final revision = ++_configRevision;
    final owner = _activeOwner ?? _resolveOwner(null);
    if (owner.isNotEmpty) {
      await SangongMyConfigStore.instance.write(
        ownerUserId: owner,
        config: config,
      );
    }
    _hydrated = true;
    if (revision == _configRevision) {
      _applyConfig(config, notify: true);
    }
  }

  /// 页面打开时可再触发后台刷新；有 in-flight 时复用同一请求。
  Future<SangongMyConfig> refreshFromNetwork() {
    final running = _inflightRefresh;
    if (running != null) {
      return running;
    }
    final task = _refreshFromNetworkCore();
    _inflightRefresh = task.whenComplete(() {
      if (identical(_inflightRefresh, task)) {
        _inflightRefresh = null;
      }
    });
    return _inflightRefresh!;
  }

  Future<SangongMyConfig> _refreshFromNetworkCore() async {
    final requestRevision = _configRevision;
    try {
      final remote = await SangongAdminApi.instance.fetchMyConfig();
      final owner = _activeOwner ?? _resolveOwner(null);
      if (owner.isNotEmpty) {
        await SangongMyConfigStore.instance.write(
          ownerUserId: owner,
          config: remote,
        );
        if ((_activeOwner == owner || _activeOwner == null) &&
            requestRevision == _configRevision) {
          _hydrated = true;
          _applyConfig(remote, notify: true);
        }
      } else {
        _applyConfig(remote, notify: true);
      }
      return remote;
    } catch (_) {
      final cached = configListenable.value;
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  void _applyConfig(SangongMyConfig? next, {required bool notify}) {
    final current = configListenable.value;
    if (current == null && next == null) {
      return;
    }
    if (current != null && next != null && current.isSameAs(next)) {
      return;
    }
    if (notify) {
      configListenable.value = next;
    }
  }

  /// 根据缓存/最新 my-config 与当前聊天群，计算入口与角色。
  static SangongMyConfigGroupAccess resolveGroupAccess({
    required SangongMyConfig? config,
    required String groupId,
    required bool userPrivileged,
  }) {
    if (!userPrivileged) {
      return const SangongMyConfigGroupAccess();
    }
    final cfg = config;
    if (cfg == null) {
      // 特权用户即使尚未在服务端创建三公配置，也必须显示配置入口；
      // 否则会因为本地无缓存而无法进入首次配置流程。
      return const SangongMyConfigGroupAccess(
        needsSetup: true,
        canEditConfig: true,
      );
    }
    if (!cfg.configured) {
      return const SangongMyConfigGroupAccess(
        needsSetup: true,
        canEditConfig: true,
      );
    }
    final boundId =
        cfg.imGroupGameId.isNotEmpty ? cfg.imGroupGameId : cfg.tenantId;
    final matched = ChatIdFormat.groupIdsEquivalent(boundId, groupId);
    if (!matched) {
      return const SangongMyConfigGroupAccess();
    }
    final tenantId = cfg.tenantId.isNotEmpty
        ? cfg.tenantId
        : ChatIdFormat.normalizeGroupId(boundId);
    return SangongMyConfigGroupAccess(
      configured: true,
      canEditConfig: cfg.canEditConfig || cfg.isOwner,
      canManageMembers: cfg.canManageMembers || cfg.isOwner,
      myRole: cfg.myRole,
      tenantId: tenantId,
    );
  }
}
