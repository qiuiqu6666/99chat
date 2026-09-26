import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_transfers_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/agent_rebate_models.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_team_page.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_member_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.saveToken(token, userId: 'self');
    SangongGameHttp.setTenantId('transfers-test', persist: false);
  });
  tearDown(() async {
    await ApiClient.instance.clearToken();
    SangongGameHttp.clearTenant(persist: false);
  });

  test('production client includes JWT and tenant header', () async {
    final dio = SangongGameHttp.client;
    final adapter = dio.httpClientAdapter;
    addTearDown(() => dio.httpClientAdapter = adapter);
    dio.httpClientAdapter = TransferAdapter((request) {
      expect(request.headers['Authorization'], 'Bearer $token');
      expect(request.headers['X-Tenant-Id'], 'transfers-test');
      expect(request.path, '/api/v1/me/transfers');
    });
    expect(await SangongTransfersApi().fetch(), isEmpty);
  });

  testWidgets('team entry opens separate transfers page', (tester) async {
    mockPages();
    await tester.pumpWidget(const MaterialApp(home: SangongAgentTeamPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('划转记录'));
    await tester.pumpAndSettle();
    expect(find.text('我的划转记录'), findsOneWidget);
    expect(find.text('暂无划转记录'), findsOneWidget);
  });

  testWidgets('personal entry appears only for signed-in member',
      (tester) async {
    mockPages();
    await tester.pumpWidget(MaterialApp(
        home: SangongAgentMemberDetailPage(
      member: SangongTeamMemberDto.fromJson(
          {'imUserId': 'other', 'nickname': '其他人'}),
    )));
    await tester.pumpAndSettle();
    expect(find.text('划转记录'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: SangongAgentMemberDetailPage(
      member:
          SangongTeamMemberDto.fromJson({'imUserId': 'self', 'nickname': '自己'}),
    )));
    await tester.pumpAndSettle();
    expect(find.text('划转记录'), findsOneWidget);
    await tester.tap(find.text('划转记录'));
    await tester.pumpAndSettle();
    expect(find.text('我的划转记录'), findsOneWidget);
  });
}

void mockPages() {
  final dio = SangongGameHttp.client;
  final saved = dio.interceptors.toList();
  dio.interceptors.clear();
  addTearDown(() => dio.interceptors
    ..clear()
    ..addAll(saved));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    handler.resolve(Response(requestOptions: request, data: {
      'ok': true,
      'members': [],
      'transfers': [],
      'days': [],
    }));
  }));
}

class TransferAdapter implements HttpClientAdapter {
  TransferAdapter(this.inspect);
  final void Function(RequestOptions) inspect;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<dynamic>? cancelFuture) async {
    inspect(options);
    return ResponseBody.fromString('{"ok":true,"transfers":[]}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}
