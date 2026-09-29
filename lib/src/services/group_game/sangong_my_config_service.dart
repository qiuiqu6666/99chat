import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_my_config.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/sangong_my_config_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
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
  SangongMyConfigService._()
      : _readLocal =
            ((owner) => SangongMyConfigStore.instance.read(ownerUserId: owner)),
        _writeLocal = ((owner, config) => SangongMyConfigStore.instance
            .write(ownerUserId: owner, config: config)),
        _fetchRemote = SangongAdminApi.instance.fetchMyConfig;

  @visibleForTesting
  SangongMyConfigService.forTesting({
    required Future<SangongMyConfig?> Function(String owner) readLocal,
    required Future<void> Function(String owner, SangongMyConfig config)
        writeLocal,
    required Future<SangongMyConfig> Function() fetchRemote,
  })  : _readLocal = readLocal,
        _writeLocal = writeLocal,
        _fetchRemote = fetchRemote;

  final Future<SangongMyConfig?> Function(String owner) _readLocal;
  final Future<void> Function(String owner, SangongMyConfig config) _writeLocal;
  final Future<SangongMyConfig> Function() _fetchRemote;

  static final SangongMyConfigService instance = SangongMyConfigService._();

  /// `null` 表示尚未灌过本地缓存（与「已缓存未配置」区分）。
  final ValueNotifier<SangongMyConfig?> configListenable =
      ValueNotifier<SangongMyConfig?>(null);

  String? _activeOwner;
  int _epoch = 0;
  int? _sessionGeneration;
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

  void _selectOwner(String owner) {
    final generation = SessionIdentityService.instance.generation;
    if (_activeOwner == owner && _sessionGeneration == generation) return;
    clearSession();
    _activeOwner = owner;
    _sessionGeneration = generation;
  }

  bool _isCurrent(String owner, int epoch) =>
      _epoch == epoch &&
      _activeOwner == owner &&
      _sessionGeneration == SessionIdentityService.instance.generation;

  /// 仅灌本地缓存（不打网络），进群页可 await 后秒开 UI。
  Future<void> ensureHydrated({String? userId}) async {
    final owner = _resolveOwner(userId);
    if (owner.isEmpty) {
      return;
    }
    _selectOwner(owner);
    if (_hydrated) {
      return;
    }
    final epoch = _epoch;
    final revision = _configRevision;
    final cached = await _readLocal(owner);
    if (!_isCurrent(owner, epoch) || revision != _configRevision) return;
    _hydrated = true;
    _applyConfig(cached, notify: true);
  }

  /// 登录成功或冷启动恢复会话后调用：先本地、后网络。
  Future<void> activateSession({String? userId}) async {
    final owner = _resolveOwner(userId);
    if (owner.isEmpty) return;
    _selectOwner(owner);
    final epoch = _epoch;
    await ensureHydrated(userId: owner);
    if (!_isCurrent(owner, epoch)) return;
    unawaited(refreshFromNetwork().then<void>((_) {},
        onError: (Object error, StackTrace _) {
      debugPrint('[SangongConfig] refresh failed: $error');
    }));
  }

  void clearSession() {
    _epoch++;
    _sessionGeneration = null;
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
    final owner = _activeOwner ?? _resolveOwner(null);
    if (owner.isEmpty) return;
    _selectOwner(owner);
    final epoch = _epoch;
    final revision = ++_configRevision;
    if (owner.isNotEmpty) {
      await _writeLocal(owner, config);
    }
    if (_isCurrent(owner, epoch) && revision == _configRevision) {
      _hydrated = true;
      _applyConfig(config, notify: true);
    }
  }

  /// 页面打开时可再触发后台刷新；有 in-flight 时复用同一请求。
  Future<SangongMyConfig> refreshFromNetwork() {
    final owner =
        _sessionGeneration == SessionIdentityService.instance.generation
            ? (_activeOwner ?? _resolveOwner(null))
            : _resolveOwner(null);
    if (owner.isEmpty) return Future.value(const SangongMyConfig());
    _selectOwner(owner);
    final running = _inflightRefresh;
    if (running != null) {
      return running;
    }
    late final Future<SangongMyConfig> task;
    task = _refreshFromNetworkCore(owner, _epoch).whenComplete(() {
      if (identical(_inflightRefresh, task)) {
        _inflightRefresh = null;
      }
    });
    _inflightRefresh = task;
    return task;
  }

  Future<SangongMyConfig> _refreshFromNetworkCore(
      String owner, int epoch) async {
    final requestRevision = _configRevision;
    try {
      final remote = await _fetchRemote();
      if (!_isCurrent(owner, epoch) || requestRevision != _configRevision)
        return config;
      if (owner.isNotEmpty) {
        await _writeLocal(owner, remote);
        if (_isCurrent(owner, epoch) && requestRevision == _configRevision) {
          _configRevision++;
          _hydrated = true;
          _applyConfig(remote, notify: true);
        }
      } else {
        _applyConfig(remote, notify: true);
      }
      return remote;
    } catch (_) {
      if (!_isCurrent(owner, epoch)) return config;
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
