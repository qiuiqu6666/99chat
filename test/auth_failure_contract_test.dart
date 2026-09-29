import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/auth_failure_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/auth_version_prompt.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 429;
  Map<String, dynamic> body = {
    'code': 'LOGIN_RATE_LIMITED',
    'message': '尝试过多，请稍后再试'
  };
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? stream, Future? cancel) async {
    requests.add(o);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Response response(String path, int status, Map<String, dynamic> body) =>
      Response(
          requestOptions: RequestOptions(path: path, method: 'POST'),
          statusCode: status,
          data: body);
  test('password lock requires exact HTTP status, code and login endpoint', () {
    final body = {
      'code': 'LOGIN_RATE_LIMITED',
      'message': 'server text',
      'retryAfter': 999
    };
    expect(
        AuthFailurePolicy.passwordLockMessage(
            response('/auth/login/password', 429, body)),
        'server text');
    expect(
        AuthFailurePolicy.passwordLockMessage(
            response('/auth/login/password/verify', 429, body)),
        isNull);
    expect(
        AuthFailurePolicy.passwordLockMessage(
            response('/auth/login/password', 401, body)),
        isNull);
    expect(
        AuthFailurePolicy.passwordLockMessage(
            response('/auth/login/password', 429, {'code': 'RATE_LIMITED'})),
        isNull);
  });
  test(
      'version denial uses unwrapped HTTP errors across all five auth endpoints',
      () {
    for (final path in AuthFailurePolicy.versionPaths) {
      for (final code in [
        'CLIENT_VERSION_REQUIRED',
        'CLIENT_VERSION_TOO_LOW'
      ]) {
        final body = {
          'code': code,
          'message': 'upgrade',
          'minVersionCode': 20,
          'downloadUrl': 'https://example.com/new.apk'
        };
        expect(
            AuthFailurePolicy.versionFailure(response(path, 403, body))
                ?.downloadUri
                .toString(),
            'https://example.com/new.apk');
        expect(AuthFailurePolicy.versionFailure(response(path, 200, body)),
            isNull);
      }
    }
    expect(
        AuthFailurePolicy.versionFailure(response(
            '/wallet/transfer', 403, {'code': 'CLIENT_VERSION_TOO_LOW'})),
        isNull);
  });
  test(
      'password failure sends once and subsequent attempts keep fixed device ID and real version headers',
      () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '3.0.1',
        buildNumber: '20',
        buildSignature: '');
    final client = ApiClient.instance;
    final adapter = _Adapter();
    final old = client.dio.httpClientAdapter;
    client.dio.httpClientAdapter = adapter;
    addTearDown(() {
      client.dio.httpClientAdapter = old;
    });
    await Future.wait(List.generate(10, (_) => client.ensureDeviceIdReady()));
    final device = client.deviceId;
    for (var i = 0; i < 2; i++) {
      await expectLater(
          AuthApi.instance
              .loginPassword(account: 'test', password: 'badpassword'),
          throwsA(isA<DioError>()));
      expect(adapter.requests.length, i + 1);
      final sent = adapter.requests.last;
      expect((sent.data as Map)['deviceId'], device);
      expect(sent.headers['X-App-Version'], '3.0.1');
      expect(sent.headers['X-App-Version-Code'], '20');
      expect(sent.headers['X-Client-Platform'], isNotEmpty);
    }
    adapter.status = 403;
    adapter.body = {'code': 'CLIENT_VERSION_TOO_LOW', 'message': '升级'};
    await expectLater(
        AuthApi.instance
            .loginPasswordVerify(challengeId: 'challenge', smsCode: '123456'),
        throwsA(isA<DioError>()));
    expect(adapter.requests.length, 3);
    expect(adapter.requests.last.path, '/auth/login/password/verify');
    expect((adapter.requests.last.data as Map)['deviceId'], device);
  });
  testWidgets(
      'version rejection shows one upgrade dialog without a fabricated countdown',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(navigatorKey: AppNavigator.key, home: const Scaffold()));
    const failure = AuthVersionFailure(
        message: '版本过低，请升级后再登录',
        downloadUrl: 'https://example.com/app.apk',
        changelog: '修复问题');
    final prompt = AuthVersionPrompt.show(failure);
    await tester.pumpAndSettle();
    await AuthVersionPrompt.show(failure);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('立即升级'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await prompt;
  });
}
