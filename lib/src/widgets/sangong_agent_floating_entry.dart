import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/agent_rebate_floating_entry.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

/// 三公代理专用浮窗：查 / 团 / 个 / 隐。
class SangongAgentFloatingEntry extends StatelessWidget {
  const SangongAgentFloatingEntry({
    super.key,
    required this.theme,
    required this.conversationId,
    required this.onOpenQuery,
    required this.onOpenTeam,
    required this.onOpenPersonal,
  });

  final TUITheme theme;
  final String conversationId;
  final VoidCallback onOpenQuery;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenPersonal;

  @override
  Widget build(BuildContext context) {
    return AgentRebateFloatingEntry(
      theme: theme,
      conversationId: conversationId,
      variant: AgentRebateFloatingVariant.sangong,
      defaultBottom: 500,
      onOpenDescendants: onOpenQuery,
      onOpenRebate: onOpenTeam,
      onOpenHistory: onOpenPersonal,
    );
  }
}
