import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/agent_rebate_http.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用数字公开群 ID，避免 normalize 成社群完整前缀后对不上 fake map key。
  const groupA = '@TGS#10001';
  const groupB = '@TGS#10002';

  tearDown(() {
    AgentRebateHttp.clearGroup();
  });

  test('caches per group and does not cross-contaminate', () async {
    final api = _FakeAgentRebateApi()
      ..contexts[groupA] = _entryContext(groupA, show: true)
      ..contexts[groupB] = _entryContext(groupB, show: false);
    final service = AgentIdentityService(api: api);

    final a = await service.refreshForGroup(groupA);
    expect(a.canShowEntries, isTrue);
    // Cache hits return immediately while a single background refresh may be
    // in flight; the entry must remain available during that refresh.
    expect(api.entryContextCallCount, greaterThanOrEqualTo(1));

    final aAgain = await service.refreshForGroup(groupA, force: false);
    expect(aAgain.canShowEntries, isTrue);
    expect(api.entryContextCallCount, greaterThanOrEqualTo(1));

    final b = await service.refreshForGroup(groupB);
    expect(b.canShowEntries, isFalse);
    expect(api.entryContextCallCount, greaterThanOrEqualTo(2));
  });

  test('hides entry when group not bound or not enabled', () async {
    final api = _FakeAgentRebateApi()
      ..contexts[groupA] = _entryContext(groupA, show: false);
    final service = AgentIdentityService(api: api);

    final state = await service.refreshForGroup(groupA);
    expect(state.bound, isFalse);
    expect(state.enabled, isFalse);
    expect(state.isAgent, isFalse);
    expect(api.entryContextCallCount, 1);
  });

  test('clearSession invalidates an in-flight identity result', () async {
    final completer = Completer<AgentEntryContextDto>();
    final api = _FakeAgentRebateApi()..pendingContext = completer.future;
    final service = AgentIdentityService(api: api);

    final result = service.refreshForGroup(groupA);
    service.clearSession();
    completer.complete(_entryContext(groupA, show: true));

    final state = await result;
    expect(state.canShowEntries, isFalse);
    expect(service.cachedEntry(groupA), isNull);
  });

  test('canShowEntries requires bound + enabled + isAgent', () {
    expect(
      AgentIdentityService.canShowEntries(
        groupBound: true,
        groupEnabled: true,
        isAgent: true,
      ),
      isTrue,
    );
    expect(
      AgentIdentityService.canShowEntries(
        groupBound: true,
        groupEnabled: false,
        isAgent: true,
      ),
      isFalse,
    );
  });
}

AgentEntryContextDto _entryContext(String groupId, {required bool show}) {
  return AgentEntryContextDto(
    showAgentEntry: show,
    tenantId: show ? 'tenant-1' : '',
    agentImGroupId: groupId,
    agentImUserId: 'im-user-1',
    userId: 'user-1',
    nickname: '代理',
    balance: 0,
    rebatePct: show ? 2.5 : 0,
  );
}

class _FakeAgentRebateApi extends AgentRebateApi {
  _FakeAgentRebateApi() : super(dio: Dio());

  final Map<String, AgentEntryContextDto> contexts = {};
  Future<AgentEntryContextDto>? pendingContext;
  int entryContextCallCount = 0;

  @override
  Future<AgentEntryContextDto> fetchEntryContext(String groupId) async {
    entryContextCallCount++;
    final pending = pendingContext;
    if (pending != null) return pending;
    return contexts[groupId] ?? _entryContext(groupId, show: false);
  }
}
