import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_session_guard.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_page_transitions.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_member_detail_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_back_button.dart';

class SangongAgentPersonalPage extends StatefulWidget {
  const SangongAgentPersonalPage(
      {super.key, required this.imGroupId, this.imUserId});
  final String imGroupId;
  final String? imUserId;

  @visibleForTesting
  static String resolveCurrentImUserId() {
    return ContactSocialCacheStore.safeLoginUserId().trim();
  }

  static String _personalErrorText(Object error) {
    final text = DioErrorMessage.forApp(error);
    if (text.contains('Incorrect result size') || text.contains('用户不存在')) {
      return '当前账号在该群没有代理数据';
    }
    return text;
  }

  static Future<void> open(BuildContext context, {required String imGroupId, String? imUserId}) async {
    final session = AgentSessionSnapshot();
    if (!session.isCurrent) return;
    try {
      final id = resolveCurrentImUserId();
      if (id.isEmpty) throw StateError('未找到当前登录用户');
      final data = await AgentRebateApi.instance.fetchSangongMemberDashboard(imUserId: id);
      final member = data['member'];
      if (member is! Map) throw StateError('个人数据格式无效');
      if (!context.mounted || !session.isCurrent) return;
      await Navigator.of(context).push(AppMaterialPageRoute(
        settings: const RouteSettings(name: 'sangong_agent_member_detail'),
        builder: (_) => SangongAgentMemberDetailPage(member: SangongTeamMemberDto.fromJson(Map<String, dynamic>.from(member))),
      ));
    } catch (e) {
      if (context.mounted && session.isCurrent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_personalErrorText(e))));
    }
  }

  @override
  State<SangongAgentPersonalPage> createState() => _State();
}

class _State extends State<SangongAgentPersonalPage> {
  final _accountSession = AgentSessionSnapshot();
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_isCurrentSession) return;
    try {
      final id = SangongAgentPersonalPage.resolveCurrentImUserId();
      if (id.isEmpty) throw StateError('未找到当前登录用户');
      final data = await AgentRebateApi.instance
          .fetchSangongMemberDashboard(imUserId: id);
      final member = data['member'];
      if (member is! Map) throw StateError('个人数据格式无效');
      if (!mounted || !_isCurrentSession) return;
      final detail = SangongAgentMemberDetailPage(
        member: SangongTeamMemberDto.fromJson(Map<String, dynamic>.from(member)),
      );
      await Navigator.of(context).pushReplacement(
        AppMaterialPageRoute(
          settings: const RouteSettings(name: 'sangong_agent_member_detail'),
          builder: (_) => detail,
        ),
      );
      if (mounted && _isCurrentSession) setState(() => _loading = false);
    } catch (e) {
      if (mounted && _isCurrentSession)
        setState(() {
          _error = SangongAgentPersonalPage._personalErrorText(e);
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),title: const Text('个人数据')),
        body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Text(_error ?? '暂无数据')),
      );
}
