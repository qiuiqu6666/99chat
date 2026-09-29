import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_expiry_service.dart';
import 'package:tencent_cloud_chat_demo/utils/dio_error_message.dart';

const message = '该账号已禁用，请联系管理员';

class _Adapter implements HttpClientAdapter {
  Future<void> Function()? beforeReply;
  String code = 'ACCOUNT_DISABLED';
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future? cancelFuture) async {
    await beforeReply?.call();
    return ResponseBody.fromString(
        jsonEncode({'code': code, 'message': message}), 403,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient.instance;
  late _Adapter adapter;
  late List<String> notices;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    client.setLogoutInProgress(false);
    await client.clearToken();
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    notices = [];
    ApiClient.onAccountDisabled = (text) async {
      notices.add(text);
    };
  });
  tearDown(() {
    ApiClient.onAccountDisabled = null;
  });

  for (final path in [
    '/me',
    '/wallet/balance',
    '/auth/login/password',
    '/sms/send'
  ]) {
    test('$path clears persisted credentials and preserves message', () async {
      await client.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      await expectLater(client.dio.post(path), throwsA(isA<DioError>()));
      expect(client.token, isNull);
      await client.loadToken();
      expect(client.token, isNull);
      expect(notices, [message]);
    });
  }
  test('anonymous SMS denial also exits without an existing token', () async {
    await expectLater(client.dio.post('/sms/send'), throwsA(isA<DioError>()));
    expect(notices, [message]);
  });
  test('ordinary 403 is not a global logout', () async {
    adapter.code = 'UNAUTHORIZED';
    await client.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    expect(client.token, isNotNull);
    expect(notices, isEmpty);
  });
  test('missing UI callback still deletes the stored token', () async {
    ApiClient.onAccountDisabled = null;
    await client.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    await client.loadToken();
    expect(client.token, isNull);
  });
  test('late business denial cannot clear a replacement token', () async {
    await client.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    adapter.beforeReply =
        () => client.saveToken('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    expect(client.token, startsWith('bbbb'));
    expect(notices, isEmpty);
  });
  test('late public response cannot clear a new login', () async {
    adapter.beforeReply =
        () => client.saveToken('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await expectLater(client.dio.post('/sms/send'), throwsA(isA<DioError>()));
    expect(client.token, startsWith('bbbb'));
    expect(notices, isEmpty);
  });
  test('concurrent denials trigger one callback', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    ApiClient.onAccountDisabled = (text) async {
      notices.add(text);
      entered.complete();
      await gate.future;
    };
    final first = expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    await entered.future;
    await expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    gate.complete();
    await first;
    expect(notices, [message]);
  });
  test('custom validateStatus cannot accept a disabled response', () async {
    await expectLater(
        client.dio.get('/me', options: Options(validateStatus: (_) => true)),
        throwsA(isA<DioError>()));
    expect(notices, [message]);
  });
  test('teardown failure still clears credentials and completes request',
      () async {
    await client.saveToken('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    ApiClient.onAccountDisabled = (_) async {
      throw StateError('teardown');
    };
    await expectLater(client.dio.get('/me'), throwsA(isA<DioError>()));
    expect(client.token, isNull);
  });
  test('UI error formatter returns exact server message', () {
    final options = RequestOptions(path: '/sms/send');
    final error = DioError(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 403,
          data: {'code': 'ACCOUNT_DISABLED', 'message': ' 原文 /support '},
        ));
    expect(DioErrorMessage.forApp(error), ' 原文 /support ');
  });
  test('anonymous disabled account clears session then notifies and navigates',
      () async {
    final events = <String>[];
    final service = SessionExpiryService(
      clearSession: (reason) async {
        events.add(reason);
      },
      markInvalidated: (_, text) {
        expect(text, message);
      },
      showMessage: events.add,
      navigateToLogin: () {
        events.add('login');
      },
    );
    await service.handleAccountDisabled(message);
    expect(events, ['account_disabled', message, 'login']);
  });
}
