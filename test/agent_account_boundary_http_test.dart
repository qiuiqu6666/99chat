import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/sangong_game_http.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_game/sangong_agent_dashboard_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tokenA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const tokenB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final cancelled = throwsA(isA<DioError>().having(
    (error) => error.type,
    'type',
    DioErrorType.cancel,
  ));

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.saveToken(tokenA, userId: 'account-a');
    SangongGameHttp.clearTenant(persist: false);
  });

  tearDown(() async {
    ApiClient.instance.setLogoutInProgress(false);
    await ApiClient.instance.clearToken();
    SangongGameHttp.clearTenant(persist: false);
  });

  for (final sangong in [false, true]) {
    final label = sangong ? 'sangong' : 'agent';
    Dio client() => sangong ? SangongGameHttp.client : ApiClient.instance.dio;
    final path = sangong ? '/api/v1/me/team/members' : '/me/agent/descendants';

    test('$label uses B credentials for a new request after switching',
        () async {
      final headers = <String>[];
      client().httpClientAdapter = _Adapter((options) async {
        headers.add(options.headers['Authorization'] as String);
        return _ok();
      });
      await client().get(path);
      await ApiClient.instance.saveToken(tokenB, userId: 'account-b');
      await client().get(path);
      expect(headers, ['Bearer $tokenA', 'Bearer $tokenB']);
    });

    test('$label blocks requests during logout while A token still exists',
        () async {
      var sent = false;
      client().httpClientAdapter = _Adapter((_) async {
        sent = true;
        return _ok();
      });
      ApiClient.instance.setLogoutInProgress(true);
      expect(ApiClient.instance.token, tokenA);
      await expectLater(client().get(path), cancelled);
      expect(sent, isFalse);
    });

    test('$label rejects A response after B credentials are saved', () async {
      final started = Completer<void>();
      final response = Completer<ResponseBody>();
      client().httpClientAdapter = _Adapter((_) {
        started.complete();
        return response.future;
      });
      final request = client().get(path);
      final check = expectLater(request, cancelled);
      await started.future;
      await ApiClient.instance.saveToken(tokenB, userId: 'account-b');
      response.complete(_ok());
      await check;
    });

    test('$label cancels a queued request before attaching B credentials',
        () async {
      var sent = false;
      client().httpClientAdapter = _Adapter((_) async {
        sent = true;
        return _ok();
      });
      final switching =
          InterceptorsWrapper(onRequest: (options, handler) async {
        await ApiClient.instance.saveToken(tokenB, userId: 'account-b');
        handler.next(options);
      });
      client().interceptors.insert(1, switching);
      try {
        await expectLater(client().get(path), cancelled);
        expect(sent, isFalse);
      } finally {
        client().interceptors.remove(switching);
      }
    });

    test('$label rejects pre-boundary response even if the token is unchanged',
        () async {
      final started = Completer<void>();
      final response = Completer<ResponseBody>();
      client().httpClientAdapter = _Adapter((_) {
        started.complete();
        return response.future;
      });
      final check = expectLater(client().get(path), cancelled);
      await started.future;
      SessionIdentityService.instance.invalidate(reason: 'test_switch');
      response.complete(_ok());
      await check;
    });
  }

  test('old sangong tenant error cannot clear B tenant', () async {
    final started = Completer<void>();
    final response = Completer<ResponseBody>();
    SangongGameHttp.client.httpClientAdapter = _Adapter((_) {
      started.complete();
      return response.future;
    });
    final check = expectLater(
      SangongGameHttp.client.get('/api/v1/agent/entry-context'),
      cancelled,
    );
    await started.future;
    await ApiClient.instance.saveToken(tokenB, userId: 'account-b');
    SangongGameHttp.setTenantId('tenant-b', persist: false);
    response.complete(ResponseBody.fromString(
      '{"message":"tenant not found"}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    ));
    await check;
    expect(SangongGameHttp.tenantId, 'tenant-b');
  });

  test('logout still permits push token cleanup with the old credential',
      () async {
    ApiClient.instance.setLogoutInProgress(true);
    ApiClient.instance.dio.httpClientAdapter = _Adapter((options) async {
      expect(options.headers['Authorization'], 'Bearer $tokenA');
      return _ok();
    });
    await ApiClient.instance.dio.delete('/me/push-token');
  });

  testWidgets(
      'disposed dashboard cannot restore its tenant or start a follow-up request',
      (tester) async {
    var requests = 0;
    final response = Completer<ResponseBody>();
    SangongGameHttp.client.httpClientAdapter = _Adapter((_) {
      requests++;
      return response.future;
    });
    await tester.pumpWidget(const MaterialApp(
      home: SangongAgentDashboardPage(imGroupId: '@TGS#10001'),
    ));
    for (var i = 0; i < 10 && requests == 0; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox());
    SangongGameHttp.setTenantId('tenant-b', persist: false);
    response.complete(ResponseBody.fromString(
      '{"data":{"showAgentEntry":true,"tenantId":"tenant-a"}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(SangongGameHttp.tenantId, 'tenant-b');
    expect(requests, 1);
  });
}

ResponseBody _ok() => ResponseBody.fromString('{"data":{}}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<dynamic>? cancelFuture) =>
      respond(options);

  @override
  void close({bool force = false}) {}
}
