import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/agent_rebate_current_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/agent_rebate_descendants_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';

void main() {
  testWidgets('mounted rebate page ignores old-account summary',
      (tester) async {
    final pending = Completer<AgentRebateCurrentDto>();
    final api = _Api()..pendingCurrent = pending.future;
    await tester.pumpWidget(_app(AgentRebateCurrentPage(api: api)));
    await tester.pump();
    SessionIdentityService.instance.invalidate(reason: 'switch_account');
    pending.complete(_summary());
    await tester.pump();
    expect(find.textContaining('7552'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mounted downline page ignores old-account members',
      (tester) async {
    final pending = Completer<AgentDescendantsDto>();
    final api = _Api()..pendingDescendants = pending.future;
    await tester.pumpWidget(_app(AgentRebateDescendantsPage(
      api: api,
      profileLoader: (_) async => null,
      avatarBuilder: (_, __, ___) => const SizedBox(),
    )));
    await tester.pump();
    SessionIdentityService.instance.invalidate(reason: 'switch_account');
    pending.complete(AgentDescendantsDto.fromJson({
      'userId': 'a',
      'scope': 'all',
      'items': [
        {
          'userId': 'child-a',
          'displayName': '旧账号下级',
          'directParentUserId': 'a'
        },
      ],
    }));
    await tester.pump();
    expect(find.text('旧账号下级'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rebate confirmation cannot submit after account switch',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(_app(AgentRebateCurrentPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请反水'));
    await tester.pumpAndSettle();
    SessionIdentityService.instance.invalidate(reason: 'switch_account');
    await tester.tap(find.text('确认申请'));
    await tester.pumpAndSettle();
    expect(api.submissions, 0);
  });

  testWidgets(
      'rebate polling stops when account changes with page still mounted',
      (tester) async {
    final api = _Api()..pendingStatus = true;
    await tester.pumpWidget(_app(AgentRebateCurrentPage(api: api)));
    await tester.pump();
    final calls = api.statusCalls;
    SessionIdentityService.instance.invalidate(reason: 'switch_account');
    await tester.pump(const Duration(seconds: 3));
    expect(api.statusCalls, calls);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

Widget _app(Widget home) => MaterialApp(
      navigatorKey: AppNavigator.key,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    );

AgentRebateCurrentDto _summary() => AgentRebateCurrentDto.fromJson({
      'userId': 'a',
      'summary': {'agentNo': '7552', 'agentName': '旧账号', 'pendingRebate': 98},
      'personal': {'agentPendingRebate': 98, 'balance': 88},
    });

class _Api extends AgentRebateApi {
  _Api() : super(dio: Dio());
  Future<AgentRebateCurrentDto>? pendingCurrent;
  Future<AgentDescendantsDto>? pendingDescendants;
  bool pendingStatus = false;
  int statusCalls = 0;
  int submissions = 0;

  @override
  Future<AgentRebateCurrentDto> fetchCurrent() =>
      pendingCurrent ?? Future.value(_summary());

  @override
  Future<AgentDescendantsDto> fetchDescendants({
    AgentDescendantScope scope = AgentDescendantScope.all,
    int? page,
    int? pageSize,
  }) =>
      pendingDescendants!;

  @override
  Future<AgentRebateApplyDto> fetchPersonalRebateApplyStatus() async =>
      AgentRebateApplyDto.fromJson({'status': 'NONE'});

  @override
  Future<AgentRebateApplyDto> fetchAgentRebateApplyStatus() async {
    statusCalls++;
    return AgentRebateApplyDto.fromJson(
        {'status': pendingStatus ? 'PENDING' : 'NONE'});
  }

  @override
  Future<AgentRebateApplyDto> submitAgentRebateApply() async {
    submissions++;
    return AgentRebateApplyDto.fromJson({'status': 'SUCCESS'});
  }
}
