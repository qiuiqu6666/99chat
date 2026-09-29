import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_http.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// 某群的反水入口判定结果。
class AgentRebateEntryState {
  const AgentRebateEntryState({
    this.bound = false,
    this.enabled = false,
    this.isAgent = false,
    this.robotId = '',
    this.machineCodeMasked,
  });

  final bool bound;
  final bool enabled;
  final bool isAgent;
  final String robotId;
  final String? machineCodeMasked;

  bool get canShowEntries => bound && enabled && isAgent;
}

/// 按群缓存：robot 绑定状态 + `/me/agent/player`。登出应 [clearSession]。
class AgentIdentityService {
  AgentIdentityService({AgentRebateApi? api})
      : _api = api ?? AgentRebateApi.instance;

  static final AgentIdentityService instance = AgentIdentityService();

  final AgentRebateApi _api;
  final Map<String, RobotGroupBindingDto> _bindingByGroup = {};
  final Map<String, AgentPlayerDto> _playerByGroup = {};
  final Map<String, Future<AgentRebateEntryState>> _inFlightByGroup = {};
  final Map<String, int> _lastRefreshAtByGroup = {};
  static const Duration _backgroundRefreshTtl = Duration(minutes: 1);
  int _sessionGeneration = 0;

  /// 兼容旧调用：最近一次解析到的代理身份（不跨群可靠）。
  AgentPlayerDto? get cachedPlayer {
    final groupId = AgentRebateHttp.groupId;
    if (groupId == null || groupId.isEmpty) {
      return null;
    }
    return _playerByGroup[_cacheKey(groupId)];
  }

  bool get hasCachedIdentity => cachedPlayer != null;

  bool get cachedIsAgent => cachedPlayer?.isAgent ?? false;

  static bool canShowEntries({
    required bool groupBound,
    required bool groupEnabled,
    required bool isAgent,
  }) {
    return groupBound && groupEnabled && isAgent;
  }

  /// @Deprecated 旧双参门控；请用 [canShowEntries] 三参版。
  static bool canShowEntriesLegacy({
    required bool groupFeatureEnabled,
    required bool isAgent,
  }) {
    return groupFeatureEnabled && isAgent;
  }

  String _cacheKey(String groupId) {
    final normalized = ChatIdFormat.normalizeGroupId(groupId.trim());
    return normalized.isNotEmpty ? normalized : groupId.trim();
  }

  AgentRebateEntryState? cachedEntry(String groupId) {
    final key = _cacheKey(groupId);
    if (key.isEmpty) return null;
    final binding = _bindingByGroup[key];
    if (binding == null) return null;
    final player = _playerByGroup[key];
    return AgentRebateEntryState(
      bound: binding.bound,
      enabled: binding.enabled,
      isAgent: player?.isAgent ?? false,
      robotId: binding.robotId,
      machineCodeMasked: binding.machineCodeMasked,
    );
  }

  /// 进群时优先读取本地入口状态，并异步更新三公入口上下文。
  ///
  /// - `force: false`（默认）：本地缓存立即返回，超过刷新间隔后异步更新；
  /// - `force: true`：明确需要强制校验时才同步请求服务端。
  Future<AgentRebateEntryState> refreshForGroup(
    String groupId, {
    bool force = false,
  }) {
    final key = _cacheKey(groupId);
    if (key.isEmpty) {
      debugPrint('[AgentEntryCheck] skip reason=empty_group_id');
      return Future.value(const AgentRebateEntryState());
    }
    debugPrint('[AgentEntryCheck] enter group=$key force=$force');
    AgentRebateHttp.setGroupId(key);

    // 本地命中即返回：写内存映射 + 返回状态。
    final cached = force ? null : (cachedEntry(key) ?? _loadFromLocal(key));
    if (cached != null) {
      // 本地快照立即返回；网络只在后台做一次，并通过同一 in-flight
      // 表去重。这样聊天页首帧不再等待接口，但下一次进入能读到新状态。
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastRefreshAtByGroup[key] ?? 0;
      final ageMs = last == 0 ? -1 : now - last;
      if (now - last >= _backgroundRefreshTtl.inMilliseconds) {
        debugPrint('[AgentEntryCheck] cache_hit group=$key '
            'show=${cached.canShowEntries} refresh=async ageMs=$ageMs');
        _lastRefreshAtByGroup[key] = now;
        // 调用方已经先拿到并渲染本地快照；这里返回异步刷新结果，
        // 让当前聊天页在权限发生变化时立即显示/隐藏“查、隐”入口。
        return _refreshNetworkForGroup(key);
      }
      debugPrint('[AgentEntryCheck] cache_hit group=$key '
          'show=${cached.canShowEntries} refresh=skip ageMs=$ageMs '
          'ttlMs=${_backgroundRefreshTtl.inMilliseconds}');
      return Future<AgentRebateEntryState>.value(cached);
    }

    final existing = _inFlightByGroup[key];
    if (existing != null) {
      debugPrint('[AgentEntryCheck] request_join group=$key');
      return existing;
    }
    debugPrint('[AgentEntryCheck] cache_miss group=$key refresh=network');
    final generation = _sessionGeneration;
    final owner = _currentOwner();
    _lastRefreshAtByGroup[key] = DateTime.now().millisecondsSinceEpoch;
    final request = _loadForGroup(key, owner, generation);
    _inFlightByGroup[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlightByGroup[key], request)) {
        _inFlightByGroup.remove(key);
      }
    });
  }

  Future<AgentRebateEntryState> _refreshNetworkForGroup(String key) {
    final existing = _inFlightByGroup[key];
    if (existing != null) {
      debugPrint('[AgentEntryCheck] request_join group=$key');
      return existing;
    }
    final generation = _sessionGeneration;
    _lastRefreshAtByGroup[key] = DateTime.now().millisecondsSinceEpoch;
    final request = _loadForGroup(key, _currentOwner(), generation);
    _inFlightByGroup[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlightByGroup[key], request)) {
        _inFlightByGroup.remove(key);
      }
    });
  }

  String _currentOwner() {
    return ContactSocialCacheStore.safeLoginUserId().trim();
  }

  /// 从本地 store 命中即写内存并返回；不命中返回 null（不阻塞）。
  AgentRebateEntryState? _loadFromLocal(String key) {
    final owner = _currentOwner();
    if (owner.isEmpty) {
      return null;
    }
    final record = AgentRebateEntryLocalStore.instance.readCachedSync(
      ownerUserId: owner,
      groupId: key,
    );
    if (record == null) {
      return null;
    }
    _bindingByGroup[key] = RobotGroupBindingDto(
      groupId: key,
      bound: record.bound,
      enabled: record.enabled,
      robotId: record.robotId,
      machineCodeMasked: record.machineCodeMasked,
    );
    final player = record.toPlayerDto();
    if (player != null) {
      _playerByGroup[key] = player;
    } else {
      _playerByGroup.remove(key);
    }
    return AgentRebateEntryState(
      bound: record.bound,
      enabled: record.enabled,
      isAgent: record.isAgent,
      robotId: record.robotId,
      machineCodeMasked: record.machineCodeMasked,
    );
  }

  Future<bool> isAgent({bool refresh = false}) async {
    final groupId = AgentRebateHttp.groupId;
    if (groupId == null || groupId.isEmpty) {
      return false;
    }
    final state = await refreshForGroup(groupId, force: refresh);
    return state.isAgent;
  }

  Future<bool> refresh() => isAgent(refresh: true);

  Future<AgentRebateEntryState> _loadForGroup(
    String key,
    String owner,
    int generation,
  ) async {
    try {
      debugPrint('[AgentEntryCheck] request_start group=$key '
          'endpoint=/me/robot/groups/{groupId}');
      final binding = await _api.fetchRobotGroup(key);
      if (generation != _sessionGeneration) {
        return const AgentRebateEntryState();
      }
      _bindingByGroup[key] = binding;
      if (!binding.isReady) {
        _playerByGroup.remove(key);
        unawaited(_persistLocal(owner, key, binding, null));
        return AgentRebateEntryState(
          bound: binding.bound,
          enabled: binding.enabled,
          isAgent: false,
          robotId: binding.robotId,
          machineCodeMasked: binding.machineCodeMasked,
        );
      }
      AgentRebateHttp.setGroupId(key);
      final player = await _api.fetchPlayer();
      if (generation != _sessionGeneration) {
        return const AgentRebateEntryState();
      }
      _playerByGroup[key] = player;
      unawaited(_persistLocal(owner, key, binding, player));
      return AgentRebateEntryState(
        bound: binding.bound,
        enabled: binding.enabled,
        isAgent: player.isAgent,
        robotId: binding.robotId,
        machineCodeMasked: binding.machineCodeMasked,
      );
    } catch (error) {
      debugPrint('[AgentEntryCheck] request_failed group=$key '
          'error=$error');
      if (generation == _sessionGeneration) {
        _playerByGroup.remove(key);
      }
      final binding = _bindingByGroup[key];
      return AgentRebateEntryState(
        bound: binding?.bound ?? false,
        enabled: binding?.enabled ?? false,
        isAgent: false,
        robotId: binding?.robotId ?? '',
        machineCodeMasked: binding?.machineCodeMasked,
      );
    }
  }

  Future<void> _persistLocal(
    String owner,
    String key,
    RobotGroupBindingDto binding,
    AgentPlayerDto? player,
  ) async {
    if (owner.isEmpty) {
      return;
    }
    final record = AgentRebateEntryRecord.fromBindingAndPlayer(
      binding,
      player,
      DateTime.now().millisecondsSinceEpoch,
    );
    await AgentRebateEntryLocalStore.instance.upsert(
      ownerUserId: owner,
      groupId: key,
      record: record,
    );
  }

  /// 反水接口返回 NOT_AGENT / PLAYER_NOT_FOUND 时清除当前群代理缓存。
  void revokeGroupAgent(String? groupId) {
    final key = _cacheKey(groupId ?? AgentRebateHttp.groupId ?? '');
    if (key.isEmpty) return;
    _playerByGroup.remove(key);
    final owner = _currentOwner();
    if (owner.isEmpty) return;
    unawaited(
      AgentRebateEntryLocalStore.instance.markNotAgent(
        ownerUserId: owner,
        groupId: key,
      ),
    );
  }

  void clearSession() {
    _sessionGeneration++;
    _bindingByGroup.clear();
    _playerByGroup.clear();
    _inFlightByGroup.clear();
    _lastRefreshAtByGroup.clear();
    AgentRebateHttp.clearGroup();
    unawaited(AgentRebateEntryLocalStore.instance.clearSession());
  }
}
