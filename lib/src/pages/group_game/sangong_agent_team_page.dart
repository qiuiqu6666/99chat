import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_session_guard.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_member_detail_page.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';

class SangongAgentTeamPage extends StatefulWidget {
  const SangongAgentTeamPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        AppMaterialPageRoute(
          settings: const RouteSettings(name: 'sangong_agent_team'),
          builder: (_) => const SangongAgentTeamPage(),
        ),
      );

  @override
  State<SangongAgentTeamPage> createState() => _SangongAgentTeamPageState();
}

class _SangongAgentTeamPageState extends State<SangongAgentTeamPage> {
  final _accountSession = AgentSessionSnapshot();
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  bool _direct = false;
  bool _loading = true;
  String? _error;
  SangongTeamMembersDto? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_isCurrentSession) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AgentRebateApi.instance.fetchSangongTeamMembers(
        direct: _direct,
      );
      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_isCurrentSession) return;
      setState(() {
        _error = DioErrorMessage.forApp(error);
        _loading = false;
      });
    }
  }

  String _amount(num value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _transfer(SangongTeamMemberDto member) async {
    if (!mounted || !_isCurrentSession) return;
    final agent = _data?.agent;
    final available = agent == null ? null : _amount(agent.transferAvailable);
    final amountText = await AppDialog.prompt(
      title: '划转积分',
      message:
          '将自己的积分划转给 ${member.nickname.isEmpty ? member.imUserId : member.nickname}${available == null ? '' : '\n可划转约 $available'}',
      placeholder: '请输入划转数量',
      cancelText: '取消',
      confirmText: '下一步',
    );
    if (amountText == null || !mounted || !_isCurrentSession) return;
    final amount = num.tryParse(amountText.trim());
    if (amount == null || amount <= 0) {
      ToastUtils.toast('请输入大于 0 的有效数量', context: context);
      return;
    }
    final confirmed = await AppDialog.confirm(
      title: '确认划转',
      message: '确认划转 ${_amount(amount)} 积分给该下级吗？',
      cancelText: '取消',
      confirmText: '确认划转',
    );
    if (!confirmed || !mounted || !_isCurrentSession) return;
    try {
      final result = await AgentRebateApi.instance.transferToChild(
        toImUserId: member.imUserId,
        amount: amount,
      );
      if (!mounted || !_isCurrentSession) return;
      final fromBalance = result['fromBalance'];
      final maxNegative = result['maxNegative'];
      final current = _data;
      if (current?.agent != null &&
          (fromBalance != null || maxNegative != null)) {
        setState(() {
          _data = SangongTeamMembersDto(
            tenantId: current!.tenantId,
            userId: current.userId,
            direct: current.direct,
            aggregation: current.aggregation,
            sessionId: current.sessionId,
            batchNo: current.batchNo,
            businessDate: current.businessDate,
            sessionStatus: current.sessionStatus,
            agent: current.agent!.copyWith(
              balance: fromBalance == null
                  ? null
                  : (fromBalance is num
                      ? fromBalance.toDouble()
                      : num.tryParse(fromBalance.toString())?.toDouble()),
              maxNegative: maxNegative == null
                  ? null
                  : (maxNegative is num
                      ? maxNegative.toDouble()
                      : num.tryParse(maxNegative.toString())?.toDouble()),
            ),
            members: current.members,
          );
        });
      }
      ToastUtils.toast(
        '划转成功${result['referenceId'] == null ? '' : '，流水号 ${result['referenceId']}'}',
        context: context,
      );
      await _load();
    } catch (error) {
      if (mounted && _isCurrentSession) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('查询下级')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('全部下级')),
                ButtonSegment(value: true, label: Text('直属下级')),
              ],
              selected: {_direct},
              onSelectionChanged: (value) {
                final direct = value.first;
                if (direct == _direct) return;
                setState(() => _direct = direct);
                _load();
              },
            ),
          ),
          if (data != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      data.batchNo.isNotEmpty
                          ? '${data.businessDate} · 批次 ${data.batchNo}'
                          : data.businessDate.isEmpty
                              ? '批次 ID ${data.sessionId}'
                              : '${data.businessDate} · 批次 ID ${data.sessionId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text('共 ${data.members.length} 人'),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final members = _data?.members ?? const <SangongTeamMemberDto>[];
    if (members.isEmpty) return const Center(child: Text('暂无下级'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
        itemBuilder: (context, index) => _memberTile(members[index]),
      ),
    );
  }

  Widget _memberTile(SangongTeamMemberDto member) {
    final name = member.nickname.trim().isEmpty
        ? member.imUserId
        : member.nickname.trim();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 26,
        backgroundImage: member.avatarUrl.trim().isEmpty
            ? null
            : NetworkImage(member.avatarUrl.trim()),
        child: member.avatarUrl.trim().isEmpty
            ? Text(name.isEmpty ? '?' : name.characters.first)
            : null,
      ),
      title: Text(
        name,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '第 ${member.levelNo} 级  ·  余额 ${_amount(member.balance)}  ·  未返水 ${_amount(member.batchRebate)}'),
          Text(
              '闲流水 ${_amount(member.playerTurnover)}  ·  庄流水 ${_amount(member.bankerTurnover)}'),
        ],
      ),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '划转积分',
          icon: const Icon(Icons.swap_horiz_rounded),
          onPressed:
              member.imUserId.trim().isEmpty ? null : () => _transfer(member),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
      onTap: () {
        if (!_isCurrentSession) return;
        SangongAgentMemberDetailPage.open(context, member);
      },
    );
    /*
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metricSection('当前批次统计', [
                ('总流水', member.batchTotalTurnover),
                ('玩家流水', member.playerTurnover),
                ('庄家流水', member.bankerTurnover),
                ('上分', member.batchUp),
                ('下分', member.batchDown),
                ('盈亏', member.batchProfitLoss),
                ('当前已返水', member.batchRebate),
              ]),
              const SizedBox(height: 14),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 14),
              _metricSection('今日', [
                ('上分', member.todayUp),
                ('下分', member.todayDown),
                ('盈亏', member.todayProfitLoss),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: member.imUserId.trim().isEmpty
                      ? null
                      : () => _transfer(member),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('划转积分'),
                ),
              ),
            ],
          ),
        ),
      ],
    );*/
  }

  Widget _metricSection(String title, List<(String, double)> metrics) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final itemWidth = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: 10,
              children: metrics
                  .map((metric) => SizedBox(
                        width: itemWidth,
                        child: _metricItem(metric.$1, metric.$2),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _metricItem(String label, double value) {
    final theme = Theme.of(context);
    final isProfit = label == '盈亏';
    final valueColor = isProfit
        ? (value > 0
            ? Colors.red.shade600
            : value < 0
                ? Colors.green.shade600
                : theme.colorScheme.onSurface)
        : theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Text(
              _amount(value),
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
