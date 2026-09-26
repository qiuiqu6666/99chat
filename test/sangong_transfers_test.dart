import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_transfers_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/sangong_transfer.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_transfers_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

Map<String, dynamic> row(int id, String direction, String name) => {
      'id': id,
      'referenceId': 'ref-$id',
      'sessionId': 8,
      'amount': 2000,
      'direction': direction,
      'counterpartImUserId': 'user-$id',
      'counterpartNickname': name,
      'createdAt': '2026-09-26T08:30:00Z',
    };

void main() {
  test('API sends documented parameters, decodes counterpart and sorts by id',
      () async {
    final dio = Dio();
    final queries = <Map<String, dynamic>>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/api/v1/me/transfers');
      queries.add(Map.of(request.queryParameters));
      handler.resolve(Response(requestOptions: request, data: {
        'ok': true,
        'count': 2,
        'transfers': [row(1, 'out', '下级'), row(2, 'in', '上级')],
      }));
    }));
    final api = SangongTransfersApi(dio: dio);
    final records = await api.fetch();
    expect(queries.single, {'direction': 'all', 'limit': 100});
    expect(records.map((e) => e.id), [2, 1]);
    expect(records.first.displayName, '上级');
    expect(records.first.isOutgoing, isFalse);
    await api.fetch(direction: 'in', limit: 500, sessionId: 8);
    expect(queries.last, {'direction': 'in', 'limit': 500, 'sessionId': 8});
    await expectLater(api.fetch(limit: 501), throwsArgumentError);
    await expectLater(api.fetch(sessionId: 0), throwsArgumentError);
    expect(queries, hasLength(2));
  });

  test('API rejects business errors and malformed records', () async {
    final dio = Dio();
    Object data = {'ok': false, 'message': '没有权限'};
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: data));
    }));
    final api = SangongTransfersApi(dio: dio);
    await expectLater(api.fetch(), throwsA(isA<DioError>()));
    data = {'ok': true};
    await expectLater(api.fetch(), throwsFormatException);
    data = {
      'transfers': [row(1, 'unknown', '用户')]
    };
    await expectLater(api.fetch(), throwsFormatException);
    final transfer = SangongTransfer.fromJson({
      ...row(1, 'out', ''),
      'toNickname': '下级备用名',
    });
    expect(transfer.displayName, '下级备用名');
  });

  testWidgets('filters directions and batches, clears and retries errors',
      (tester) async {
    final api = FakeTransfersApi();
    await tester
        .pumpWidget(MaterialApp(home: SangongAgentTransfersPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('转出给 下级'), findsOneWidget);
    expect(find.text('−2000 积分'), findsOneWidget);
    expect(find.text('流水号：ref-1'), findsOneWidget);

    await tester.tap(find.text('转入'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$1, 'in');
    expect(find.text('转入自 上级'), findsOneWidget);
    expect(find.text('+2000 积分'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '8');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3, 8);
    await tester.tap(find.byTooltip('清除批次筛选'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3, isNull);

    api.fail = true;
    await tester.tap(find.text('转出'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('转入自 上级'), findsNothing);
    api.fail = false;
    api.empty = true;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无划转记录'), findsOneWidget);
  });

  testWidgets('ignores stale responses on fast direction switches',
      (tester) async {
    final api = FakeTransfersApi()
      ..pending = Completer<List<SangongTransfer>>();
    final old = api.pending!;
    await tester
        .pumpWidget(MaterialApp(home: SangongAgentTransfersPage(api: api)));
    await tester.pump();
    api.pending = null;
    await tester.tap(find.text('转入'));
    await tester.pumpAndSettle();
    old.complete([SangongTransfer.fromJson(row(1, 'out', '旧结果'))]);
    await tester.pumpAndSettle();
    expect(find.text('转出给 旧结果'), findsNothing);
    expect(find.text('转入自 上级'), findsOneWidget);
  });

  testWidgets('rejects results after account or tenant changes',
      (tester) async {
    final api = FakeTransfersApi()
      ..pending = Completer<List<SangongTransfer>>();
    await tester
        .pumpWidget(MaterialApp(home: SangongAgentTransfersPage(api: api)));
    await tester.pump();
    SessionIdentityService.instance.invalidate(reason: 'transfer-test');
    api.pending!.complete([SangongTransfer.fromJson(row(1, 'out', '旧账号'))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('旧账号'), findsNothing);
    expect(find.text('账号或群已切换，请重新进入划转记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    final originalTenant = SangongGameHttp.tenantId;
    addTearDown(
        () => SangongGameHttp.setTenantId(originalTenant, persist: false));
    SangongGameHttp.setTenantId('transfers-a', persist: false);
    await tester.pumpWidget(
        MaterialApp(home: SangongAgentTransfersPage(api: FakeTransfersApi())));
    await tester.pumpAndSettle();
    SangongGameHttp.setTenantId('transfers-b', persist: false);
    await tester.pumpAndSettle();
    expect(find.text('转出给 下级'), findsNothing);
    expect(find.text('账号或群已切换，请重新进入划转记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class FakeTransfersApi extends SangongTransfersApi {
  final calls = <(String, int, int?)>[];
  bool fail = false;
  bool empty = false;
  Completer<List<SangongTransfer>>? pending;

  @override
  Future<List<SangongTransfer>> fetch(
      {String direction = 'all', int limit = 100, int? sessionId}) async {
    calls.add((direction, limit, sessionId));
    if (pending != null) return pending!.future;
    if (fail) throw Exception('load failed');
    if (empty) return [];
    return [
      SangongTransfer.fromJson(row(
          1, direction == 'in' ? 'in' : 'out', direction == 'in' ? '上级' : '下级'))
    ];
  }
}
