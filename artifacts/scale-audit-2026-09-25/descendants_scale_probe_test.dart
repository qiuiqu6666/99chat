// Synthetic UI-entry probe. Injected API/profile loaders perform no network IO.
// ignore_for_file: avoid_print
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/user_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/agent_rebate_descendants_page.dart';

void main() {
  testWidgets(
      'diagnostic: 10k descendants auto-drain and per-page profile batches overlap',
      (tester) async {
    final api = _ScaleAuditAgentApi();
    final pending = <Completer<UserSearchResult?>>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AgentRebateDescendantsPage(
        api: api,
        profileLoader: (_) {
          final task = Completer<UserSearchResult?>();
          pending.add(task);
          return task.future;
        },
        avatarBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48),
      ),
    ));
    try {
      await tester.pumpAndSettle();
      print(
          'SCALE_AUDIT descendants=10000 entryPageRequests=${api.pageRequests} concurrentUnresolvedProfiles=${pending.length} userScrolls=0');
      expect(api.pageRequests, 51);
      expect(pending.length, greaterThan(8));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final task in pending) {
        task.complete(null);
      }
      await tester.pumpAndSettle();
    }
  });
}

class _ScaleAuditAgentApi extends AgentRebateApi {
  _ScaleAuditAgentApi() : super(dio: Dio());
  int pageRequests = 0;
  @override
  Future<AgentDescendantsDto> fetchDescendants({
    AgentDescendantScope scope = AgentDescendantScope.all,
    int? page,
    int? pageSize,
  }) async {
    pageRequests++;
    final current = page ?? 1;
    final size = pageSize ?? 50;
    final start = (current - 1) * size;
    final end = (start + size).clamp(0, 10000);
    return AgentDescendantsDto.fromJson({
      'userId': 'audit_owner',
      'scope': 'all',
      'total': 10000,
      'page': current,
      'pageSize': size,
      'count': end - start,
      'hasMore': end < 10000,
      'items': [
        for (var i = start; i < end; i++)
          {
            'userId': 'audit_$i',
            'displayName': 'Member $i',
            'directParentUserId': 'audit_owner',
            'balance': i,
          }
      ],
    });
  }
}
