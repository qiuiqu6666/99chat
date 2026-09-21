import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';

/// 持久化的「某账号 × 某群」反水入口判定快照。
///
/// 仅供 `AgentRebateEntryLocalStore` 内部使用，不对外暴露。
class AgentRebateEntryRecord {
  const AgentRebateEntryRecord({
    this.bound = false,
    this.enabled = false,
    this.isAgent = false,
    this.robotId = '',
    this.machineCodeMasked,
    this.rebateRate = 0,
    this.levelNo = 0,
    this.playerType = '',
    this.playerNo = '',
    this.displayName = '',
    this.dataVersion = 1,
    this.fetchedAtMs = 0,
  });

  final bool bound;
  final bool enabled;
  final bool isAgent;
  final String robotId;
  final String? machineCodeMasked;
  final double rebateRate;
  final int levelNo;
  final String playerType;
  final String playerNo;
  final String displayName;
  final int dataVersion;
  final int fetchedAtMs;

  AgentPlayerDto? toPlayerDto() {
    if (!bound || !enabled) {
      return null;
    }
    return AgentPlayerDto(
      userId: '',
      playerNo: playerNo,
      displayName: displayName,
      playerType: playerType,
      levelNo: levelNo,
      balance: 0,
      rebateRate: rebateRate,
      isAgent: isAgent,
    );
  }

  static AgentRebateEntryRecord fromBindingAndPlayer(
    RobotGroupBindingDto binding,
    AgentPlayerDto? player,
    int fetchedAtMs,
  ) {
    return AgentRebateEntryRecord(
      bound: binding.bound,
      enabled: binding.enabled,
      isAgent: player?.isAgent ?? false,
      robotId: binding.robotId,
      machineCodeMasked: binding.machineCodeMasked,
      rebateRate: player?.rebateRate ?? 0,
      levelNo: player?.levelNo ?? 0,
      playerType: player?.playerType ?? '',
      playerNo: player?.playerNo ?? '',
      displayName: player?.displayName ?? '',
      dataVersion: 1,
      fetchedAtMs: fetchedAtMs,
    );
  }

  AgentRebateEntryRecord copyWith({bool? isAgent, int? fetchedAtMs}) {
    return AgentRebateEntryRecord(
      bound: bound,
      enabled: enabled,
      isAgent: isAgent ?? this.isAgent,
      robotId: robotId,
      machineCodeMasked: machineCodeMasked,
      rebateRate: rebateRate,
      levelNo: levelNo,
      playerType: playerType,
      playerNo: playerNo,
      displayName: displayName,
      dataVersion: dataVersion,
      fetchedAtMs: fetchedAtMs ?? this.fetchedAtMs,
    );
  }
}
