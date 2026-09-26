import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_transfers_page.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_session_guard.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

class SangongAgentMemberDetailPage extends StatefulWidget {
  const SangongAgentMemberDetailPage({super.key, required this.member});
  final SangongTeamMemberDto member;

  static Future<void> open(BuildContext context, SangongTeamMemberDto member) =>
      Navigator.of(context).push(AppMaterialPageRoute(
        settings: const RouteSettings(name: 'sangong_agent_member_detail'),
        builder: (_) => SangongAgentMemberDetailPage(member: member),
      ));

  @override
  State<SangongAgentMemberDetailPage> createState() => _State();
}

class _State extends State<SangongAgentMemberDetailPage> {
  final _accountSession = AgentSessionSnapshot();
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  SangongTeamMembersDto? _team;
  SangongTeamMemberDto? _liveMember;
  Map<String, dynamic>? _daily;
  String? _error;
  int _tabIndex = 0;
  bool _summaryView = false;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _loadDaily();
  }

  Future<void> _loadTeam() async {
    if (!mounted || !_isCurrentSession) return;
    try {
      Map<String, dynamic> dashboard = const {};
      try {
        dashboard = await AgentRebateApi.instance
            .fetchSangongMemberDashboard(imUserId: widget.member.imUserId);
      } catch (_) {
        // 聚合接口不可用时回退到成员明细接口。
      }
      if (!mounted || !_isCurrentSession) return;
      final raw = dashboard['directMembers'];
      final members = raw is List
          ? raw
              .whereType<Map>()
              .map((e) =>
                  SangongTeamMemberDto.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <SangongTeamMemberDto>[];
      // 兼容旧版服务端暂未识别 agentImUserId 参数的情况：
      // 客户端仍按父级关系收敛，绝不把当前代理的其他成员展示到详情页。
      final result =
          await AgentRebateApi.instance.fetchSangongTeamMembers(direct: true);
      final ownId = widget.member.userId;
      final filtered = members.isNotEmpty
          ? members
          : result.members
              .where((item) => item.parentUserId == ownId)
              .toList(growable: false);
      final scoped = SangongTeamMembersDto(
        tenantId: result.tenantId,
        userId: result.userId,
        direct: result.direct,
        aggregation: result.aggregation,
        sessionId: result.sessionId,
        batchNo: result.batchNo,
        businessDate: result.businessDate,
        sessionStatus: result.sessionStatus,
        agent: result.agent,
        members: filtered,
      );
      if (mounted && _isCurrentSession)
        setState(() {
          _team = scoped;
        });
    } catch (e) {
      if (mounted && _isCurrentSession) setState(() => _error = DioErrorMessage.forApp(e));
    }
  }

  Future<void> _loadDaily() async {
    if (!mounted || !_isCurrentSession) return;
    try {
      String? batchNo;
      SangongTeamMemberDto? live;
      try {
        final dashboard = await AgentRebateApi.instance
            .fetchSangongMemberDashboard(imUserId: widget.member.imUserId);
        final batch = dashboard['batch'];
        batchNo = batch is Map ? batch['batchNo']?.toString() : null;
        final member = dashboard['member'];
        if (member is Map) {
          live = SangongTeamMemberDto.fromJson(
              Map<String, dynamic>.from(member));
        }
      } catch (_) {
        // 批次信息暂时不可用时，继续走日期汇总查询。
      }
      if (!mounted || !_isCurrentSession) return;
      var daily = await AgentRebateApi.instance.fetchSangongMemberDaily(
          imUserId: widget.member.imUserId, batchNo: batchNo);
      if (!mounted || !_isCurrentSession) return;
      if ((daily['days'] is! List || (daily['days'] as List).isEmpty) &&
          batchNo != null) {
        daily = await AgentRebateApi.instance
            .fetchSangongMemberDaily(imUserId: widget.member.imUserId);
      }
      if (mounted && _isCurrentSession) {
        setState(() {
          _daily = daily;
          if (live != null) _liveMember = live;
        });
      }
    } catch (_) {}
  }

  String money(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  Widget metric(String title, num value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 4),
        Text(money(value),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ]);

  bool get _isCurrentLoginMember {
    final selfId =
        ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
    final memberId = ChatIdFormat.rawUserUid(widget.member.imUserId);
    return selfId.isNotEmpty && memberId.isNotEmpty && selfId == memberId;
  }

  Future<void> _claimRebate() async {
    if (!mounted || !_isCurrentSession) return;
    if (!_isCurrentLoginMember || _claiming) return;
    setState(() => _claiming = true);
    try {
      final result = await AgentRebateApi.instance.claimSangongRebate();
      if (!mounted || !_isCurrentSession) return;
      final amount = result['amount'];
      ToastUtils.toast('返水申请成功，到账 ¥${money(_dayNum(amount))}', context: context);
      await _loadDaily();
    } catch (e) {
      if (mounted && _isCurrentSession) {
        ToastUtils.toast(DioErrorMessage.forApp(e), context: context);
      }
    } finally {
      if (mounted && _isCurrentSession) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _liveMember ?? widget.member;
    final name = m.nickname.trim().isEmpty ? m.imUserId : m.nickname.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(name),
        actions: [
          if (_isCurrentLoginMember)
            TextButton(
              onPressed: () {
                if (_isCurrentSession) SangongAgentTransfersPage.open(context);
              },
              child: const Text('划转记录'),
            ),
        ],
      ),
      body: Column(children: [
        Material(
          color: Colors.white,
          child: Row(children: [
            _tab('个人最新数据', 0),
            _tab('个人每天数据', 1),
          ]),
        ),
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(children: [
                  CircleAvatar(
                      radius: 28,
                      backgroundImage: m.avatarUrl.isEmpty
                          ? null
                          : NetworkImage(m.avatarUrl),
                      child: m.avatarUrl.isEmpty
                          ? Text(name.characters.first)
                          : null),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        Text('第 ${m.levelNo} 级代理 · 返水 ${money(m.rebatePct)}%',
                            style: TextStyle(color: Colors.grey.shade600))
                      ])
                ]),
                if (_tabIndex == 0) ...[
                  const SizedBox(height: 20),
                  _panelSwitcher(),
                  const SizedBox(height: 14),
                  const Text('用户数据',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Card(
                      color: Colors.white,
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              childAspectRatio: 2.7,
                              children: [
                                metric('余额', m.balance),
                                metric(
                                    _summaryView ? '本批次盈亏' : '最新盈亏',
                                    _summaryView
                                        ? m.batchProfitLoss
                                        : m.todayProfitLoss),
                                if (_summaryView) ...[
                                  metric('闲流水', m.playerTurnover),
                                  metric('庄流水', m.bankerTurnover),
                                  metric('总流水', m.batchTotalTurnover),
                                ] else ...[
                                  metric('闲流水', m.playerTurnover),
                                  metric('庄流水', m.bankerTurnover),
                                  metric('总流水', m.displayTotalTurnover),
                                  metric('最近闲流水', m.latestPlayerTurnover),
                                  metric('最近庄流水', m.latestBankerTurnover),
                                ],
                                metric(
                                    '上分', _summaryView ? m.batchUp : m.todayUp),
                                metric('下分',
                                    _summaryView ? m.batchDown : m.todayDown),
                                metric(
                                    '已返水',
                                    _summaryView
                                        ? m.batchRebate
                                        : m.todayRebate),
                                metric('待返水', m.pendingRebate),
                                metric('返水比例', m.rebatePct),
                              ]))),
                if (_tabIndex == 0 && _isCurrentLoginMember)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _claiming ? null : _claimRebate,
                          icon:
                              const Icon(Icons.account_balance_wallet_outlined),
                        label: Text(_claiming ? '申请中…' : '申请返水'),
                        ),
                      ),
                    ),
                ],
                if (_tabIndex == 1) _dailyView(),
              ]),
        ),
      ]),
    );
  }

  Widget _panelSwitcher() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFE9EDF4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          _panelButton('最新', false),
          _panelButton('汇总', true),
        ]),
      );

  Widget _panelButton(String label, bool summary) => Expanded(
        child: InkWell(
          onTap: () => setState(() => _summaryView = summary),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color:
                  _summaryView == summary ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _summaryView == summary
                        ? const Color(0xFF2388F5)
                        : const Color(0xFF6F7680))),
          ),
        ),
      );

  Widget _tab(String label, int index) => Expanded(
        child: InkWell(
          onTap: () {
            setState(() => _tabIndex = index);
            if (index == 1) _loadDaily();
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: _tabIndex == index
                      ? const Color(0xFF2388F5)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(label,
                style: TextStyle(
                    color: _tabIndex == index
                        ? const Color(0xFF2388F5)
                        : const Color(0xFF6F7680),
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _dailyView() {
    final days =
        (_daily?['days'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    if (days.isEmpty)
      return const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: Text('暂无历史每日数据')));
    return Column(
      children: days.map((day) {
        final metrics = <(String, num)>[
          ('余额', _dayNum(day['balance'])),
          ('盈亏', _dayNum(day['profitLoss'])),
          ('闲流水', _dayNum(day['playerTurnover'])),
          ('庄流水', _dayNum(day['bankerTurnover'])),
          ('总流水', _dayNum(day['totalTurnover'])),
          ('总上分', _dayNum(day['totalUp'])),
          ('总下分', _dayNum(day['totalDown'])),
          ('总返水', _dayNum(day['rebate'] ?? day['totalRebate'])),
        ];
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${day['businessDate'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 5.2,
                mainAxisSpacing: 5,
                crossAxisSpacing: 12,
                children: metrics
                    .map((item) => Row(children: [
                          Expanded(
                              child: Text(item.$1,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600))),
                          Text(
                              item.$1 == '团队人数'
                                  ? _dayNum(item.$2).toStringAsFixed(0)
                                  : money(item.$2),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ]))
                    .toList(),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  num _dayNum(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
}
