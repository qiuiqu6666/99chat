import 'sangong_account_flow_list.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_demo/src/utils/sangong_operator_names.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_admin_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/i18n/app_i18n.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_admin_models.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_game_settings.dart';
import 'package:tencent_cloud_chat_demo/src/theme/app_colors.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_dialog.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_hud.dart';

/// 用户资料页：自下而上展示三公流水（下注 / 庄 / 上下分）。
class UserProfileGameLedgerSheet extends StatefulWidget {
  const UserProfileGameLedgerSheet({
    super.key,
    required this.imUserId,
    this.displayName = '',
    this.embedded = false,
  });

  final String imUserId;
  final String displayName;

  /// 嵌在宽屏资料右侧栏时铺满剩余高度，去掉底栏拖动条。
  final bool embedded;

  static Future<void> show(
    BuildContext context, {
    required String imUserId,
    String displayName = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: UserProfileGameLedgerSheet(
            imUserId: imUserId,
            displayName: displayName,
          ),
        ),
      ),
    );
  }

  @override
  State<UserProfileGameLedgerSheet> createState() =>
      _UserProfileGameLedgerSheetState();
}

class _UserProfileGameLedgerSheetState extends State<UserProfileGameLedgerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  Map<String, String> _operatorNames = const {};
  SangongUserFlowReport _flow = const SangongUserFlowReport();
  SangongUserFlowReport _bankerReport = const SangongUserFlowReport();
  int? _currentBalance;
  SangongUserGroupInfo _userGroup = const SangongUserGroupInfo();
  SangongGameSettings _gameSettings = SangongGameSettings.defaults();
  num? _rebatePer10000;
  String _parentLabel = '未设置';
  String _parentImUserId = '';
  String _agentGroupId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _titleName {
    final fromApi = _flow.nickname.trim();
    if (fromApi.isNotEmpty) {
      return fromApi;
    }
    final fallback = widget.displayName.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }
    return widget.imUserId.trim();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tenantReady =
          await SangongGameHttp.setTenantFromMyConfig(force: true);
      if (!tenantReady) {
        if (!mounted) return;
        setState(() {
          _error = null; // 上游会控制 sheet 是否展示
          _loading = false;
        });
        return;
      }
      final imUserId = widget.imUserId.trim();
      final detail = await SangongAdminApi.instance.fetchUserDetail(imUserId);
      debugPrint(
          '[SangongUserDetail] keys=${detail.keys.toList()} agentImGroupId=${detail['agentImGroupId']}');
      if (!mounted) {
        return;
      }
      final userRaw = detail['user'];
      final flowRaw = detail['flow'];
      final settingsRaw = detail['settings'];
      final bankerReport = SangongUserFlowReport.fromJson(
        flowRaw is Map ? Map<String, dynamic>.from(flowRaw) : detail,
      );
      final flow = await SangongAdminApi.instance.fetchUserFlow(imUserId: imUserId);
      if (!mounted) return;
      final report = userRaw is Map
          ? SangongAdminUserReport.fromJson(Map<String, dynamic>.from(userRaw))
          : null;
      final settings = settingsRaw is Map
          ? SangongGameSettings.fromJson(Map<String, dynamic>.from(settingsRaw))
          : SangongGameSettings.defaults();
      final rebate = userRaw is Map
          ? Map<String, dynamic>.from(userRaw)
          : const <String, dynamic>{};
      final bindingRaw = detail['agentChatBinding'] ??
          detail['chatBinding'] ??
          detail['agentChatBindingInfo'] ??
          detail;
      final binding = bindingRaw is Map
          ? Map<String, dynamic>.from(bindingRaw)
          : const <String, dynamic>{};
      final boundGroupId = binding['agentImGroupId']?.toString() ??
          detail['agentImGroupId']?.toString() ??
          (userRaw is Map ? userRaw['agentImGroupId']?.toString() : null) ??
          '';
      final parentRaw = detail['parent'] is Map
          ? <String, dynamic>{'parent': detail['parent']}
          : const <String, dynamic>{};
      final parent = parentRaw['parent'];
      final parentMap =
          parent is Map ? Map<String, dynamic>.from(parent) : null;
      final parentLabel = parentMap == null
          ? '未设置'
          : ((parentMap['nickname']?.toString().trim().isNotEmpty == true)
              ? parentMap['nickname'].toString().trim()
              : parentMap['imUserId']?.toString().trim() ?? '未设置');
      final accounts = rebate['accounts'];
      final account =
          accounts is List && accounts.isNotEmpty && accounts.first is Map
              ? Map<String, dynamic>.from(accounts.first as Map)
              : rebate;
      final rawRebate = account['rebatePer10000'];
      final per10000 = rawRebate is num
          ? rawRebate
          : num.tryParse('$rawRebate') ??
              ((account['rebatePct'] is num)
                  ? (account['rebatePct'] as num) * 100
                  : num.tryParse('${account['rebatePct']}') == null
                      ? null
                      : num.parse('${account['rebatePct']}') * 100);
      setState(() {
        _flow = flow;
        _bankerReport = bankerReport;
        _currentBalance = report?.balance;
        _userGroup = report?.group ?? const SangongUserGroupInfo();
        _gameSettings = settings;
        _rebatePer10000 = per10000;
        _parentLabel = parentLabel;
        _parentImUserId = parentMap?['imUserId']?.toString() ?? '';
        _agentGroupId = boundGroupId;
        _loading = false;
      });
      unawaited(_loadOperatorNames(flow));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = DioErrorMessage.forApp(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadOperatorNames(SangongUserFlowReport report) async {
    bool active() => mounted && identical(_flow, report);
    final names = await resolveSangongOperatorNames(
      report.scoreEntries.map((entry) => entry.operator),
      (ids) async {
        final result = await TIMUIKitCore.getSDKInstance().getUsersInfo(userIDList: ids);
        if (result.code != 0) return <String, String>{};
        return {
          for (final user in result.data ?? [])
            if (user.userID != null) user.userID!: user.nickName ?? '',
        };
      },
      isActive: active,
    );
    if (active()) setState(() => _operatorNames = names);
  }

  String _formatTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return trimmed;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  String _signedAmount(int value) {
    if (value > 0) {
      return '+$value';
    }
    return '$value';
  }

  Color _amountColor(int value, {required bool dark}) {
    if (value > 0) {
      return const Color(0xFF2E7D32);
    }
    if (value < 0) {
      return const Color(0xFFC62828);
    }
    return AppColors.subText(dark: dark);
  }

  DateTime? _parseTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.tryParse(trimmed);
  }

  List<T> _newestFirst<T>(List<T> items, String Function(T item) timeOf) {
    final sorted = List<T>.from(items);
    sorted.sort((a, b) {
      final ta = _parseTime(timeOf(a));
      final tb = _parseTime(timeOf(b));
      if (ta == null && tb == null) {
        return 0;
      }
      if (ta == null) {
        return 1;
      }
      if (tb == null) {
        return -1;
      }
      return tb.compareTo(ta);
    });
    return sorted;
  }

  String _groupLabel(AppI18n i18n) {
    final label = _userGroup.displayLabel;
    if (label.isNotEmpty) {
      return label;
    }
    return i18n.t(
      zhHans: '未分组',
      zhHant: '未分組',
      en: 'Ungrouped',
    );
  }

  String? _sessionSubtitle(AppI18n i18n) {
    final parts = <String>[];
    if (!_flow.isAllHistory &&
        _flow.sessionId != null &&
        _flow.sessionId! > 0) {
      parts.add(
        i18n.t(
          zhHans: '会话 ${_flow.sessionId}',
          zhHant: '會話 ${_flow.sessionId}',
          en: 'Session ${_flow.sessionId}',
        ),
      );
    }
    if (_parentLabel != '未设置') {
      parts.add(
        i18n.t(
          zhHans: '上级：$_parentLabel',
          zhHant: '上級：$_parentLabel',
          en: 'Parent: $_parentLabel',
        ),
      );
    }
    if (_currentBalance != null) {
      parts.add(
        i18n.t(
          zhHans: '当前积分：$_currentBalance',
          zhHant: '當前積分：$_currentBalance',
          en: 'Balance: $_currentBalance',
        ),
      );
    }
    parts.add(
      i18n.t(
        zhHans: _rebatePer10000 == null
            ? '返水：未获取'
            : '返水：${_rebatePer10000!.toStringAsFixed(0)}',
        zhHant: _rebatePer10000 == null
            ? '返水：未取得'
            : '返水：${_rebatePer10000!.toStringAsFixed(0)}',
        en: _rebatePer10000 == null
            ? 'Rebate: unavailable'
            : 'Rebate: ${_rebatePer10000!.toStringAsFixed(0)}',
      ),
    );
    return parts.join(' · ');
  }

  bool get _hasMultipleSessions {
    final ids = <int>{};
    for (final entry in _flow.betFlow) {
      if (entry.sessionId > 0) {
        ids.add(entry.sessionId);
      }
    }
    for (final entry in _bankerReport.bankerFlow) {
      if (entry.sessionId > 0) {
        ids.add(entry.sessionId);
      }
    }
    return ids.length > 1;
  }

  bool _shouldShowEntrySession(int sessionId) {
    return sessionId > 0 && (_flow.isAllHistory || _hasMultipleSessions);
  }

  String? _sessionLabel(int sessionId, AppI18n i18n) {
    if (!_shouldShowEntrySession(sessionId)) {
      return null;
    }
    return i18n.t(
      zhHans: '会话$sessionId',
      zhHant: '會話$sessionId',
      en: 'S$sessionId',
    );
  }

  String _tabCountSuffix(int count, int loaded) {
    final total = count > 0 ? count : loaded;
    if (total <= 0) {
      return '';
    }
    return ' ($total)';
  }

  int _compareDesc(int a, int b) => b.compareTo(a);

  List<SangongUserBetFlowEntry> get _betItemsNewestFirst {
    final sorted = List<SangongUserBetFlowEntry>.from(_flow.betFlow);
    sorted.sort((a, b) {
      final ta = _parseTime(a.settledAt);
      final tb = _parseTime(b.settledAt);
      if (ta != null && tb != null) {
        return tb.compareTo(ta);
      }
      if (ta != null) {
        return -1;
      }
      if (tb != null) {
        return 1;
      }
      final sessionCmp = _compareDesc(a.sessionId, b.sessionId);
      if (sessionCmp != 0) {
        return sessionCmp;
      }
      final periodCmp = _compareDesc(a.periodNo, b.periodNo);
      if (periodCmp != 0) {
        return periodCmp;
      }
      return _compareDesc(a.door, b.door);
    });
    return sorted;
  }

  List<SangongUserBankerFlowEntry> get _bankerItemsNewestFirst {
    final sorted = List<SangongUserBankerFlowEntry>.from(_bankerReport.bankerFlow);
    sorted.sort((a, b) {
      final ta = _parseTime(a.settledAt);
      final tb = _parseTime(b.settledAt);
      if (ta != null && tb != null) {
        return tb.compareTo(ta);
      }
      if (ta != null) {
        return -1;
      }
      if (tb != null) {
        return 1;
      }
      final sessionCmp = _compareDesc(a.sessionId, b.sessionId);
      if (sessionCmp != 0) {
        return sessionCmp;
      }
      return _compareDesc(a.periodNo, b.periodNo);
    });
    return sorted;
  }

  Future<void> _setRebate() async {
    try {
      final text = await AppDialog.prompt(
        title: '设置用户返水',
        message: '请输入万分比例，例如 300 表示一万返 300。',
        placeholder: '万分比例',
        cancelText: '取消',
        confirmText: '保存',
        initialValue: _rebatePer10000?.toStringAsFixed(0) ?? '',
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
      );
      final value = num.tryParse(text?.trim() ?? '');
      if (value == null || value < 0) return;
      final hud = AppHud.begin();
      try {
        await AgentRebateApi.instance.setChildRebate(
          userId: widget.imUserId,
          rebatePer10000: value,
        );
        if (mounted) setState(() => _rebatePer10000 = value);
        ToastUtils.toast('已设置：一万返 ${value.toStringAsFixed(0)}');
      } finally {
        await hud.end();
      }
    } catch (error) {
      ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
    }
  }

  void _changeParent() {
    _promptParent();
  }

  Future<void> _promptParent() async {
    final parent = await AppDialog.prompt(
      title: '设置上级代理',
      message: '请输入上级代理用户 ID。',
      placeholder: '上级用户 ID',
      cancelText: '取消',
      confirmText: '保存',
      initialValue: _parentImUserId,
      allowEmpty: true,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9@]')),
        LengthLimitingTextInputFormatter(11),
      ],
    );
    try {
      if (parent == null) return;
      final normalizedParent = parent.trim().replaceFirst(RegExp(r'^@'), '');
      final hud = AppHud.begin();
      try {
        if (normalizedParent.isEmpty) {
          await AgentRebateApi.instance.removeChildParent(widget.imUserId);
        } else {
          await AgentRebateApi.instance.setChildParent(
            childUserId: widget.imUserId,
            parentUserId: normalizedParent,
          );
        }
        ToastUtils.toast(
          normalizedParent.isEmpty ? '已解除上级代理' : '上级代理设置成功',
        );
      } finally {
        await hud.end();
      }
    } catch (error) {
      ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
    }
  }

  List<SangongUserLedgerFlowEntry> get _ledgerItemsNewestFirst =>
      _newestFirst(_flow.ledgerFlow, (e) => e.createdAt);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = AppColors.text(dark: dark);
    final subColor = AppColors.subText(dark: dark);
    final surface = AppColors.card(dark: dark);
    final divider = subColor.withValues(alpha: 0.2);
    final primary = Theme.of(context).colorScheme.primary;
    final i18n = AppI18n.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
    final sessionSubtitle = _sessionSubtitle(i18n);
    final embedded = widget.embedded;
    final tabViews = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _buildError(titleColor, subColor)
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildBetList(titleColor, subColor, divider),
                  _buildBankerList(titleColor, subColor, divider),
                  _buildBalanceList(titleColor, subColor),
                ],
              );

    if (embedded) {
      return _buildEmbeddedBody(
        titleColor: titleColor,
        subColor: subColor,
        surface: surface,
        divider: divider,
        primary: primary,
        i18n: i18n,
        sessionSubtitle: sessionSubtitle,
        tabViews: tabViews,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: subColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (_rebatePer10000 != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '当前返水：一万返 ${_rebatePer10000!.toStringAsFixed(0)}',
                    style: TextStyle(color: primary, fontSize: 14),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n.t(
                            zhHans: '【$_titleName】流水',
                            zhHant: '【$_titleName】流水',
                            en: 'Ledger · $_titleName',
                          ),
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!_loading && sessionSubtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              sessionSubtitle,
                              style: TextStyle(color: subColor, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => unawaited(_load()),
                    icon: Icon(Icons.refresh_rounded, color: subColor),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _setRebate,
                      child: const Text('设置返水'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _changeParent,
                      child: const Text('设置上级'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _bindAgentChatGroup,
                      child: const Text('绑定代理群'),
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: primary,
              unselectedLabelColor: subColor,
              indicatorColor: primary,
              dividerColor: divider,
              tabs: [
                Tab(
                  text: i18n.t(
                    zhHans:
                        '下注流水${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                    zhHant:
                        '下注流水${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                    en: 'Bets${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                  ),
                ),
                Tab(
                  text: i18n.t(
                    zhHans: '庄流水$_bankerCountSuffix',
                    zhHant: '莊流水$_bankerCountSuffix',
                    en: 'Banker$_bankerCountSuffix',
                  ),
                ),
                Tab(
                  text: i18n.t(
                    zhHans:
                        '上下分${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                    zhHant:
                        '上下分${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                    en: 'Balance${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                  ),
                ),
              ],
            ),
            Flexible(child: tabViews),
            SizedBox(height: bottomInset > 0 ? bottomInset : 12),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedBody({
    required Color titleColor,
    required Color subColor,
    required Color surface,
    required Color divider,
    required Color primary,
    required AppI18n i18n,
    required String? sessionSubtitle,
    required Widget tabViews,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chipFill = dark ? const Color(0xFF2A2D33) : const Color(0xFFF3F4F6);
    return ColoredBox(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i18n.t(
                          zhHans: '流水',
                          zhHant: '流水',
                          en: 'Ledger',
                        ),
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      if (!_loading && sessionSubtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sessionSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _loading ? null : () => unawaited(_load()),
                  icon: Icon(Icons.refresh_rounded, size: 18, color: subColor),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: chipFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    _buildEmbeddedAction(
                      label: i18n.t(zhHans: '返水', zhHant: '返水', en: 'Rebate'),
                      color: primary,
                      onTap: _loading ? null : _setRebate,
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 8,
                      endIndent: 8,
                      color: divider,
                    ),
                    _buildEmbeddedAction(
                      label: i18n.t(zhHans: '上级', zhHant: '上級', en: 'Parent'),
                      color: primary,
                      onTap: _loading ? null : _changeParent,
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 8,
                      endIndent: 8,
                      color: divider,
                    ),
                    _buildEmbeddedAction(
                      label: i18n.t(
                        zhHans: '代理群',
                        zhHant: '代理群',
                        en: 'Agent',
                      ),
                      color: primary,
                      onTap: _loading ? null : _bindAgentChatGroup,
                    ),
                  ],
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: primary,
            unselectedLabelColor: subColor,
            indicatorColor: primary,
            indicatorWeight: 2,
            dividerColor: divider,
            labelPadding: EdgeInsets.zero,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(
                height: 36,
                text: i18n.t(
                  zhHans:
                      '下注${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                  zhHant:
                      '下注${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                  en: 'Bets${_tabCountSuffix(_flow.counts.bet, _flow.betFlow.length)}',
                ),
              ),
              Tab(
                height: 36,
                text: i18n.t(
                  zhHans: '庄$_bankerCountSuffix',
                  zhHant: '莊$_bankerCountSuffix',
                  en: 'Banker$_bankerCountSuffix',
                ),
              ),
              Tab(
                height: 36,
                text: i18n.t(
                  zhHans:
                      '上下分${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                  zhHant:
                      '上下分${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                  en: 'Balance${_tabCountSuffix(_flow.counts.ledger, _flow.ledgerFlow.length)}',
                ),
              ),
            ],
          ),
          Expanded(child: tabViews),
        ],
      ),
    );
  }

  Widget _buildEmbeddedAction({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null ? color.withValues(alpha: 0.4) : color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bindAgentChatGroup() async {
    final group = await AppDialog.prompt(
        title: '绑定代理群',
        message: '请输入代理 IM 群 ID，留空可解除绑定。',
        placeholder: '代理群 IM ID',
        initialValue: _agentGroupId,
        cancelText: '取消',
        confirmText: '保存',
        allowEmpty: true);
    if (group == null) return;
    final normalizedGroup = AgentRebateApi.normalizeAgentChatGroupId(group);
    final hud = AppHud.begin();
    try {
      try {
        if (normalizedGroup.isEmpty) {
          await AgentRebateApi.instance.removeAgentChatGroup(widget.imUserId);
          if (mounted) setState(() => _agentGroupId = '');
        } else {
          await AgentRebateApi.instance.bindAgentChatGroup(
              agentImUserId: widget.imUserId,
              agentImGroupId: normalizedGroup);
          if (mounted) setState(() => _agentGroupId = normalizedGroup);
        }
        ToastUtils.toast(
            normalizedGroup.isEmpty ? '已解除代理群绑定' : '代理群绑定成功');
      } catch (error) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    } finally {
      await hud.end();
    }
  }

  Widget _buildError(Color titleColor, Color subColor) {
    final i18n = AppI18n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: subColor, size: 40),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => unawaited(_load()),
              child: Text(
                i18n.t(zhHans: '重试', zhHant: '重試', en: 'Retry'),
                style: TextStyle(color: titleColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(Color subColor) {
    final emptyText = AppI18n.of(context).t(
      zhHans: '暂无记录',
      zhHant: '暫無記錄',
      en: 'No records',
    );
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 28,
              color: subColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              emptyText,
              style: TextStyle(color: subColor, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Text(
        emptyText,
        style: TextStyle(color: subColor, fontSize: 14),
      ),
    );
  }

  Widget _buildTotalBar({
    required Color titleColor,
    required Color subColor,
    required Color divider,
    required String label,
    required String trailing,
    int? trailingValue,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: subColor.withValues(alpha: dark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: trailingValue != null
                    ? _amountColor(trailingValue, dark: dark)
                    : titleColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetList(Color titleColor, Color subColor, Color divider) {
    if (_flow.hasUnifiedEntries) {
      return SangongAccountFlowList(entries: _flow.betEntries, bets: true);
    }
    final allItems = _flow.betFlow;
    if (allItems.isEmpty) {
      return _buildEmpty(subColor);
    }
    final items = _betItemsNewestFirst;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final betTotal = allItems.fold<int>(0, (sum, e) => sum + e.betAmount);
    final netTotal = allItems
        .where((e) => e.net != null)
        .fold<int>(0, (sum, e) => sum + e.net!);
    final count = _flow.counts.bet > 0 ? _flow.counts.bet : allItems.length;
    final i18n = AppI18n.of(context);
    return Column(
      children: [
        _buildTotalBar(
          titleColor: titleColor,
          subColor: subColor,
          divider: divider,
          label: i18n.t(
            zhHans: '合计（$count笔）',
            zhHant: '合計（$count筆）',
            en: 'Total ($count)',
          ),
          trailing: i18n.t(
            zhHans: '下注 $betTotal · 输赢 ${_signedAmount(netTotal)}',
            zhHant: '下注 $betTotal · 輸贏 ${_signedAmount(netTotal)}',
            en: 'Bet $betTotal · Net ${_signedAmount(netTotal)}',
          ),
          trailingValue: netTotal,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: divider),
            itemBuilder: (context, index) {
              final item = items[index];
              final time = _formatTime(item.betAt);
              final sessionLabel = _sessionLabel(item.sessionId, i18n);
              final subtitle = [
                if (sessionLabel != null) sessionLabel,
                if (item.periodNo > 0) '第${item.periodNo}局',
                if (item.doorLabel.isNotEmpty) item.doorLabel,
                if (!item.settled)
                  i18n.t(zhHans: '未结算', zhHant: '未結算', en: 'Pending'),
                if (item.compare.trim().isNotEmpty) item.compare.trim(),
              ].join(' · ');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '下注 ${item.betAmount}',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: subtitle.isNotEmpty
                    ? Text(
                        subtitle,
                        style: TextStyle(color: subColor, fontSize: 12),
                      )
                    : null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.net != null)
                      Text(
                        _signedAmount(item.net!),
                        style: TextStyle(
                          color: _amountColor(item.net!, dark: dark),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        i18n.t(
                          zhHans: '待结算',
                          zhHant: '待結算',
                          en: 'Pending',
                        ),
                        style: TextStyle(color: subColor, fontSize: 13),
                      ),
                    Text(
                      time.isNotEmpty
                          ? time
                          : i18n.t(
                              zhHans: '下注时间未提供',
                              zhHant: '下注時間未提供',
                              en: 'Bet time unavailable',
                            ),
                      style: TextStyle(color: subColor, fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatBankerBracketTime(String raw) {
    final parsed = _parseTime(raw);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '【$month-$day $hour:$minute】';
  }

  static const Color _bankerGreen = Color(0xFF1B9E3E);
  static const Color _bankerBlue = Color(0xFF1976D2);

  /// 上下分参考样式：标签/时间浅绿、上分金额褐红、剩余/下分金额深灰。
  static const Color _ledgerLabelGreen = Color(0xFF88B04B);
  static const Color _ledgerCreditValue = Color(0xFFC0504D);

  /// 上下分专用：【MM-DD HH:MM:SS】
  String _formatLedgerBracketTime(String raw) {
    final parsed = _parseTime(raw);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '【$month-$day $hour:$minute:$second】';
  }

  int _bankerWater(SangongUserBankerFlowEntry item) {
    return _gameSettings.computeBankerWater(
      item.totalBetAmount,
      bankerRakePoints: item.bankerRakePoints,
    );
  }

  Widget _buildBankerFlowRow(
    SangongUserBankerFlowEntry item, {
    required Color titleColor,
  }) {
    final time = _formatBankerBracketTime(item.settledAt);
    final sessionLabel = _sessionLabel(item.sessionId, AppI18n.of(context));
    final period = item.periodNo > 0 ? '${item.periodNo}' : '-';
    final grab = item.totalBetAmount;
    final water = _bankerWater(item);
    final net = item.net;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 15, height: 1.35),
              children: [
                if (time.isNotEmpty)
                  TextSpan(
                    text: time,
                    style: const TextStyle(color: _bankerGreen),
                  ),
                if (sessionLabel != null)
                  TextSpan(
                    text: '$sessionLabel ',
                    style: TextStyle(color: titleColor.withValues(alpha: 0.72)),
                  ),
                TextSpan(
                  text: '岛数:$period',
                  style: const TextStyle(color: _bankerGreen),
                ),
                TextSpan(
                  text: '抢注:$grab',
                  style: TextStyle(color: titleColor),
                ),
                TextSpan(
                  text: '水:$water',
                  style: const TextStyle(color: _bankerBlue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 15, height: 1.35),
              children: [
                const TextSpan(
                  text: '出入:',
                  style: TextStyle(color: _bankerGreen),
                ),
                TextSpan(
                  text: '$net',
                  style: const TextStyle(color: _bankerGreen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _bankerCountSuffix => _flow.hasUnifiedEntries
      ? _tabCountSuffix(_flow.bankerEntries.length + _flow.coBankFlow.length, _flow.bankerEntries.length + _flow.coBankFlow.length)
      : _tabCountSuffix(_bankerReport.counts.banker, _bankerReport.bankerFlow.length);

  Widget _buildBankerList(Color titleColor, Color subColor, Color divider) {
    if (_flow.hasUnifiedEntries) {
      return SangongAccountFlowList(entries: _flow.bankerEntries, bets: true, contributions: _flow.coBankFlow);
    }
    final allItems = _bankerReport.bankerFlow;
    if (allItems.isEmpty) {
      return _buildEmpty(subColor);
    }
    final items = _bankerItemsNewestFirst;
    final totalBetAmount =
        allItems.fold<int>(0, (sum, e) => sum + e.totalBetAmount);
    final waterTotal = allItems.fold<int>(0, (sum, e) => sum + _bankerWater(e));
    final netTotal = allItems.fold<int>(0, (sum, e) => sum + e.net);
    final count =
        _bankerReport.counts.banker > 0 ? _bankerReport.counts.banker : allItems.length;
    final i18n = AppI18n.of(context);
    return Column(
      children: [
        _buildTotalBar(
          titleColor: titleColor,
          subColor: subColor,
          divider: divider,
          label: i18n.t(
            zhHans: '合计（$count笔）',
            zhHant: '合計（$count筆）',
            en: 'Total ($count)',
          ),
          trailing: i18n.t(
            zhHans:
                '抢注 $totalBetAmount · 水 $waterTotal · 出入 ${_signedAmount(netTotal)}',
            zhHant:
                '搶注 $totalBetAmount · 水 $waterTotal · 出入 ${_signedAmount(netTotal)}',
            en: 'Grab $totalBetAmount · Water $waterTotal · Net ${_signedAmount(netTotal)}',
          ),
          trailingValue: netTotal,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: divider),
            itemBuilder: (context, index) {
              return _buildBankerFlowRow(
                items[index],
                titleColor: titleColor,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerFlowRow(
    SangongUserLedgerFlowEntry item, {
    required Color titleColor,
  }) {
    final time = _formatLedgerBracketTime(item.createdAt);
    final change = item.balanceChange.abs();
    final actionLabel = item.isDebit ? '下分' : '上分';
    final operator = item.operator.trim();
    // 参考：【06-17 06:06:25】 上分:188 剩余:-13879
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 15, height: 1.25, color: titleColor),
          children: [
            if (time.isNotEmpty)
              TextSpan(
                text: '$time ',
                style: const TextStyle(color: _ledgerLabelGreen),
              ),
            TextSpan(
              text: '$actionLabel:',
              style: const TextStyle(color: _ledgerLabelGreen),
            ),
            TextSpan(
              text: '$change',
              style: const TextStyle(color: _ledgerCreditValue),
            ),
            const TextSpan(
              text: ' 剩余:',
              style: TextStyle(color: _ledgerLabelGreen),
            ),
            TextSpan(
              text: '${item.balanceAfter}',
              style: TextStyle(color: titleColor),
            ),
            if (operator.isNotEmpty) ...[
              const TextSpan(
                text: ' 操作:',
                style: TextStyle(color: _ledgerLabelGreen),
              ),
              TextSpan(
                text: operator,
                style: TextStyle(color: titleColor.withValues(alpha: 0.82)),
              ),
            ],
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildLedgerSummaryRow({
    required Color titleColor,
    required int creditTotal,
    required int debitTotal,
  }) {
    final name = _titleName;
    // 参考：【昵称】总上分:42000 总下分:0（可换行）
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 15, height: 1.3, color: titleColor),
          children: [
            TextSpan(
              text: '【$name】',
              style: const TextStyle(color: _ledgerLabelGreen),
            ),
            const TextSpan(
              text: '总上分:',
              style: TextStyle(color: _ledgerLabelGreen),
            ),
            TextSpan(
              text: '$creditTotal',
              style: const TextStyle(color: _ledgerCreditValue),
            ),
            const TextSpan(
              text: ' 总下分:',
              style: TextStyle(color: _ledgerLabelGreen),
            ),
            TextSpan(
              text: '$debitTotal',
              style: TextStyle(color: titleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceList(Color titleColor, Color subColor) {
    if (_flow.hasUnifiedEntries) {
      return SangongAccountFlowList(entries: _flow.scoreEntries, bets: false, operatorNames: _operatorNames);
    }
    final allItems = _flow.ledgerFlow;
    if (allItems.isEmpty) {
      return _buildEmpty(subColor);
    }
    // 与参考图一致：时间正序（旧→新），汇总行贴在列表底部。
    final items = _ledgerItemsNewestFirst.reversed.toList(growable: false);
    final creditTotal = allItems
        .where((e) => e.balanceChange > 0)
        .fold<int>(0, (sum, e) => sum + e.balanceChange);
    final debitTotal = allItems
        .where((e) => e.balanceChange < 0)
        .fold<int>(0, (sum, e) => sum + e.balanceChange.abs());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _buildLedgerFlowRow(
                items[index],
                titleColor: titleColor,
              );
            },
          ),
        ),
        _buildLedgerSummaryRow(
          titleColor: titleColor,
          creditTotal: creditTotal,
          debitTotal: debitTotal,
        ),
      ],
    );
  }
}
