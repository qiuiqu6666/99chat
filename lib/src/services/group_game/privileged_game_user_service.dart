import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_game_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_game/privileged_game_user_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// 特权用户状态：登录/冷启动时读本地库立即展示 UI，后台刷新 `/me/game` 并回写。
class PrivilegedGameUserService {
  PrivilegedGameUserService._()
      : _readLocal = ((owner) =>
            PrivilegedGameUserStore.instance.read(ownerUserId: owner)),
        _writeLocal = ((owner, enabled) => PrivilegedGameUserStore.instance
            .write(ownerUserId: owner, gameEnabled: enabled)),
        _fetchRemote = GroupGameApi.instance.fetch;

  @visibleForTesting
  PrivilegedGameUserService.forTesting({
    required Future<bool?> Function(String owner) readLocal,
    required Future<void> Function(String owner, bool enabled) writeLocal,
    required Future<GroupGameStatus> Function() fetchRemote,
  })  : _readLocal = readLocal,
        _writeLocal = writeLocal,
        _fetchRemote = fetchRemote;

  final Future<bool?> Function(String owner) _readLocal;
  final Future<void> Function(String owner, bool enabled) _writeLocal;
  final Future<GroupGameStatus> Function() _fetchRemote;

  static final PrivilegedGameUserService instance =
      PrivilegedGameUserService._();

  final ValueNotifier<bool> gameEnabled = ValueNotifier<bool>(false);

  String? _activeOwner;
  int _epoch = 0;
  int? _sessionGeneration;
  bool _hydrated = false;
  Future<GroupGameStatus>? _inflightRefresh;
  DateTime? _lastRefreshAt;
  static const Duration _refreshTtl = Duration(minutes: 5);

  bool get isPrivileged => gameEnabled.value;

  String _resolveOwner(String? userId) {
    return ChatIdFormat.rawUserUid(
      userId ?? PrivilegedGameUserStore.instance.currentOwnerUserId(),
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

  /// 登录成功或冷启动恢复会话后调用：先本地、后网络。
  Future<void> activateSession({String? userId}) async {
    final owner = _resolveOwner(userId);
    if (owner.isEmpty) {
      return;
    }
    _selectOwner(owner);
    final epoch = _epoch;

    if (!_hydrated) {
      final cached = await _readLocal(owner);
      if (!_isCurrent(owner, epoch)) return;
      _hydrated = true;
      _applyEnabled(cached ?? false, notify: true);
    }

    unawaited(refreshFromNetwork());
  }

  void clearSession() {
    _epoch++;
    _sessionGeneration = null;
    _activeOwner = null;
    _hydrated = false;
    _inflightRefresh = null;
    _lastRefreshAt = null;
    _applyEnabled(false, notify: true);
  }

  /// 页面打开时可再触发一次后台刷新；有 in-flight 时复用同一请求。
  Future<GroupGameStatus> refreshFromNetwork() {
    final owner =
        _sessionGeneration == SessionIdentityService.instance.generation
            ? (_activeOwner ?? _resolveOwner(null))
            : _resolveOwner(null);
    if (owner.isEmpty)
      return Future.value(const GroupGameStatus(gameEnabled: false));
    _selectOwner(owner);
    final running = _inflightRefresh;
    if (running != null) {
      return running;
    }
    final lastRefresh = _lastRefreshAt;
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < _refreshTtl) {
      return Future<GroupGameStatus>.value(
        GroupGameStatus(gameEnabled: gameEnabled.value),
      );
    }
    late final Future<GroupGameStatus> task;
    task = _refreshFromNetworkCore(owner, _epoch).whenComplete(() {
      if (identical(_inflightRefresh, task)) {
        _inflightRefresh = null;
      }
    });
    _inflightRefresh = task;
    return task;
  }

  Future<GroupGameStatus> _refreshFromNetworkCore(
      String owner, int epoch) async {
    try {
      final status = await _fetchRemote();
      if (!_isCurrent(owner, epoch))
        return GroupGameStatus(gameEnabled: gameEnabled.value);
      _lastRefreshAt = DateTime.now();
      if (owner.isNotEmpty) {
        await _writeLocal(owner, status.gameEnabled);
        if (_isCurrent(owner, epoch)) {
          _hydrated = true;
          _applyEnabled(status.gameEnabled, notify: true);
        }
      } else {
        _applyEnabled(status.gameEnabled, notify: true);
      }
      return status;
    } catch (error) {
      // 本地三公服务尚未实现/暂时不可达时，不要把已经持久化的特权
      // 状态覆盖成 false，否则“我的配置”入口会被错误隐藏。
      debugPrint('[PrivilegedGame] refresh_failed_keep_cached '
          'enabled=${gameEnabled.value} error=$error');
      return GroupGameStatus(gameEnabled: gameEnabled.value);
    }
  }

  void _applyEnabled(bool enabled, {required bool notify}) {
    if (gameEnabled.value == enabled) {
      return;
    }
    if (notify) {
      gameEnabled.value = enabled;
    }
  }
}
