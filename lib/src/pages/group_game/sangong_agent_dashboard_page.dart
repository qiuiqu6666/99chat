import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_session_guard.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_member_detail_page.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

class SangongAgentDashboardPage extends StatefulWidget {
  const SangongAgentDashboardPage({super.key, this.imGroupId = ''});

  final String imGroupId;

  static Future<void> open(
    BuildContext context, {
    String imGroupId = '',
  }) =>
      Navigator.of(context).push(
        AppMaterialPageRoute(
          settings: const RouteSettings(name: 'sangong_agent_dashboard'),
          builder: (_) => SangongAgentDashboardPage(imGroupId: imGroupId),
        ),
      );

  @override
  State<SangongAgentDashboardPage> createState() =>
      _SangongAgentDashboardPageState();
}

class _SangongAgentDashboardPageState extends State<SangongAgentDashboardPage> {
  final _accountSession = AgentSessionSnapshot();
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      if ((SangongGameHttp.tenantId ?? '').trim().isEmpty &&
          widget.imGroupId.trim().isNotEmpty) {
        final context = await AgentRebateApi.instance.fetchEntryContext(
          widget.imGroupId,
        );
        if (!mounted || !_isCurrentSession) return;
        if (context.tenantId.trim().isNotEmpty) {
          SangongGameHttp.setTenantId(context.tenantId);
        }
      }
      final data = await AgentRebateApi.instance.fetchSangongTeamDashboard(
        direct: false,
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

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  String _text(dynamic value) => value?.toString() ?? '';
  String _num(dynamic value) {
    final number = value is num ? value : num.tryParse(_text(value)) ?? 0;
    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
  }

  String _money(dynamic value) => '¥${_num(value)}';

  num _asNum(dynamic value) =>
      value is num ? value : num.tryParse(_text(value)) ?? 0;

  String _signedMoney(dynamic value) {
    final number = value is num ? value : num.tryParse(_text(value)) ?? 0;
    if (number > 0) return '+${_money(number)}';
    if (number < 0) return '-¥${_num(number.abs())}';
    return _money(0);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _map(_data?['summary']);
    final batch = _map(_data?['batch']);
    final members = (_data?['members'] is List)
        ? (_data!['members'] as List).whereType<Map>().map(_map).toList()
        : const <Map<String, dynamic>>[];
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        leading: const AppBackButton(),
        title:
            const Text('团队统计', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('重试'))
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _batchCard(batch),
                      const SizedBox(height: 18),
                      _sectionTitle('团队概览', Icons.insights_rounded),
                      const SizedBox(height: 10),
                      _summaryCard(summary),
                      const SizedBox(height: 22),
                      _sectionTitle('下级明细', Icons.groups_2_rounded,
                          trailing: '${members.length} 人'),
                      const SizedBox(height: 10),
                      if (members.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('暂无下级'))),
                      ...members.map(_memberCard),
                    ],
                  ),
                ),
    );
  }

  Widget _batchCard(Map<String, dynamic> batch) {
    final running = _text(batch['status']).toLowerCase() == 'running';
    final start = _text(batch['startedAt']);
    final stop = _text(batch['stoppedAt']);
    String time(String value) => value.length >= 16
        ? value.substring(5, 16).replaceFirst('T', ' ')
        : value;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded,
              size: 19, color: Color(0xFF2388F5)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('当前业务批次',
                    style: TextStyle(fontSize: 12, color: Color(0xFF858C98))),
                const SizedBox(height: 4),
                Text(
                    _text(batch['batchNo']).isEmpty
                        ? '未指定'
                        : _text(batch['batchNo']),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                if (start.isNotEmpty)
                  Text('${time(start)} ～ ${running ? '至今' : time(stop)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF858C98))),
              ])),
          Text(running ? '● 开机中' : '已结算',
              style: TextStyle(
                  color: running
                      ? const Color(0xFF15945A)
                      : const Color(0xFF77808F),
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, {String? trailing}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2388F5)),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: const TextStyle(fontSize: 13, color: Color(0xFF77808F))),
      ],
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _heroMetric('团队总余额', _money(summary['totalBalance']), null),
          const SizedBox(height: 12),
          _heroMetric(
            '总流水',
            _money(summary['totalTurnover'] ??
                (_asNum(summary['playerTurnover']) +
                    _asNum(summary['bankerTurnover']))),
            null,
          ),
          const SizedBox(height: 14),
          _compactGrid(summary),
        ]),
      ),
    );
  }

  Widget _heroMetric(String label, String value, dynamic state) {
    final number = state is num ? state : num.tryParse(_text(state)) ?? 0;
    final color = state == null
        ? const Color(0xFF17181A)
        : number > 0
            ? const Color(0xFF15945A)
            : number < 0
                ? const Color(0xFFE04B4B)
                : const Color(0xFF17181A);
    return Row(children: [
      Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF858C98)))),
      Text(value,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: color))
    ]);
  }

  Widget _compactGrid(Map<String, dynamic> summary) {
    final fields = <(String, String, bool)>[
      ('闲流水', _money(summary['playerTurnover']), false),
      ('庄流水', _money(summary['bankerTurnover']), false),
      ('团队人数', _num(summary['memberCount']), false),
      ('直属人数', _num(summary['directMemberCount']), false),
      ('上分', _money(summary['totalUp']), false),
      ('下分', _money(summary['totalDown']), false),
      ('团队盈亏', _money(summary['totalProfitLoss'] ?? summary['profitLoss']), false),
    ];
    return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 3.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        children: fields
            .map((item) => Row(children: [
                  Expanded(
                      child: Text(item.$1,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF858C98)))),
                  Text(item.$2,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))
                ]))
            .toList());
  }

  Widget _rebateRow(Map<String, dynamic> summary) {
    final rate = _text(summary['rebatePct']).isNotEmpty
        ? '${_num(summary['rebatePct'])}%'
        : '—';
    final items = <(String, String)>[
      ('返水比例', rate),
      ('应返水', _money(summary['expectedRebate'] ?? summary['rebate'])),
      ('已返水', _money(summary['batchRebate'])),
      ('未返水', _money(summary['pendingRebate'])),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3.8,
      mainAxisSpacing: 8,
      crossAxisSpacing: 12,
      children: items
          .map((item) => Row(children: [
                Expanded(
                    child: Text(item.$1,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF858C98)))),
                Text(item.$2,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ]))
          .toList(),
    );
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final name = _text(member['nickname']).trim().isEmpty
        ? _text(member['imUserId'])
        : _text(member['nickname']);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
            radius: 24,
            backgroundImage: _text(member['avatarUrl']).isEmpty
                ? null
                : NetworkImage(_text(member['avatarUrl'])),
            child: _text(member['avatarUrl']).isEmpty
                ? Text(name.isEmpty ? '?' : name.characters.first)
                : null),
        title: Text(name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '${_levelLabel(member['levelNo'])} · 余额 ${_money(member['balance'])} · 返水 ${_num(member['rebatePct'] ?? member['rebatePer10000'])}% · 闲 ${_money(member['playerTurnover'])} · 庄 ${_money(member['bankerTurnover'])}'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          if (!_isCurrentSession) return;
          SangongAgentMemberDetailPage.open(
            context,
            SangongTeamMemberDto.fromJson(member),
          );
        },
      ),
    );
  }

  String _levelLabel(dynamic value) {
    final level = int.tryParse(_text(value)) ?? 0;
    const labels = <String>['', '一级代理', '二级代理', '三级代理'];
    return level > 0 && level < labels.length ? labels[level] : '第 $level 级';
  }
}
