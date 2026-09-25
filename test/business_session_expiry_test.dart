import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_i18n_tool/language_json/strings.g.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_query_endpoint.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_expiry_service.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/business_session_guard.dart';

String jwt(DateTime? expiry, {String owner = 'account-a'}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256'})}.${encode({
        'sub': owner,
        if (expiry != null) 'exp': expiry.millisecondsSinceEpoch / 1000,
      })}.signature';
}

class ReplyAdapter implements HttpClientAdapter {
  ReplyAdapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions) reply;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future? cancelFuture) =>
      reply(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody response(int status, String code) => ResponseBody.fromString(
      jsonEncode({'code': code}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient.instance;
  var expiryCalls = 0;

  setUp(() async {
    LocaleSettings.setLocale(AppLocale.zhHans);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    client.setLogoutInProgress(false);
    client.setSuppressAuthExpired(false);
    await client.clearToken();
    expiryCalls = 0;
    ApiClient.onAuthExpired = () async {
      expiryCalls++;
    };
  });

  tearDown(() async {
    ApiClient.onAuthExpired = null;
    await client.clearToken();
    client.setLogoutInProgress(false);
    client.setSuppressAuthExpired(false);
  });

  test('JWT exp is checked at the exact boundary; legacy tokens still work',
      () {
    final now = DateTime.now();
    expect(ApiClient.isValidJwt(jwt(now.subtract(const Duration(seconds: 1)))),
        isFalse);
    expect(
        ApiClient.isValidJwt(jwt(now.add(const Duration(hours: 1)))), isTrue);
    expect(ApiClient.isJwtExpired(jwt(now), now: now), isTrue);
    expect(ApiClient.isValidJwt(jwt(null)), isTrue);
    expect(ApiClient.isValidJwt('a' * 40), isTrue);
    expect(ApiClient.isValidJwt('malformed.jwt'), isFalse);
    expect(ApiClient.jwtExpiresAt('malformed.jwt'), isNull);
  });

  for (final agent in [false, true]) {
    final label = agent ? 'group query client' : 'main client';
    final path = agent ? '/me/agent/player' : '/me';
    Dio http() => agent ? GroupQueryEndpoint.client : client.dio;

    test('$label rejects an expired JWT before sending and triggers logout',
        () async {
      var sent = false;
      http().httpClientAdapter = ReplyAdapter((_) async {
        sent = true;
        return response(200, 'OK');
      });
      await client
          .saveToken(jwt(DateTime.now().subtract(const Duration(seconds: 1))));
      await expectLater(http().get(path), throwsA(isA<DioError>()));
      expect(sent, isFalse);
      expect(expiryCalls, 1);
    });

    for (final acceptStatus in [false, true]) {
      test('$label handles server expiry (validateStatus=$acceptStatus)',
          () async {
        await client
            .saveToken(jwt(DateTime.now().add(const Duration(hours: 1))));
        http().httpClientAdapter =
            ReplyAdapter((_) async => response(401, 'TOKEN_EXPIRED'));
        await expectLater(
            http().get(path,
                options:
                    acceptStatus ? Options(validateStatus: (_) => true) : null),
            throwsA(isA<DioError>()));
        expect(expiryCalls, 1);
      });
    }

    test('$label ignores old expiry responses, including same-token relogin',
        () async {
      final token = jwt(DateTime.now().add(const Duration(hours: 1)));
      await client.saveToken(token);
      http().httpClientAdapter = ReplyAdapter((_) async {
        await client.saveToken(token);
        return response(401, 'TOKEN_EXPIRED');
      });
      await expectLater(http().get(path), throwsA(isA<DioError>()));
      expect(expiryCalls, 0);
      expect(client.token, token);
    });

    test('$label does not log out for a permission denial', () async {
      await client.saveToken(jwt(DateTime.now().add(const Duration(hours: 1))));
      http().httpClientAdapter =
          ReplyAdapter((_) async => response(403, 'UNAUTHORIZED'));
      await expectLater(http().get(path), throwsA(isA<DioError>()));
      expect(expiryCalls, 0);
    });
  }

  test('wallet PIN errors and anonymous login errors do not expire a session',
      () async {
    await client.saveToken(jwt(DateTime.now().add(const Duration(hours: 1))));
    client.dio.httpClientAdapter =
        ReplyAdapter((_) async => response(401, 'PAY_PIN_INVALID'));
    await expectLater(client.dio.post('/wallet/pay'), throwsA(isA<DioError>()));
    client.dio.httpClientAdapter =
        ReplyAdapter((_) async => response(401, 'TOKEN_EXPIRED'));
    await expectLater(
        client.dio.post('/auth/login/password'), throwsA(isA<DioError>()));
    expect(expiryCalls, 0);
  });

  test('duplicate notifications are fenced per login, not by a cooldown',
      () async {
    final expired = jwt(DateTime.now().subtract(const Duration(seconds: 1)));
    await client.saveToken(expired);
    await Future.wait(
        [client.expireSessionIfNeeded(), client.expireSessionIfNeeded()]);
    expect(expiryCalls, 1);
    await client.saveToken(expired);
    await client.expireSessionIfNeeded();
    expect(expiryCalls, 2);
  });

  test('an in-flight response can expire its current token after local exp',
      () async {
    final expired = jwt(DateTime.now().subtract(const Duration(seconds: 1)));
    await client.saveToken(expired);
    final options = RequestOptions(
        path: '/me', headers: {'Authorization': 'Bearer $expired'});
    await client.handleSessionExpiryError(DioError(
      requestOptions: options,
      response: Response(
          requestOptions: options,
          statusCode: 401,
          data: {'code': 'TOKEN_EXPIRED'}),
    ));
    expect(expiryCalls, 1);
  });

  test('local expiry clears the persisted JWT and shows the requested notice',
      () async {
    await client
        .saveToken(jwt(DateTime.now().subtract(const Duration(seconds: 1))));
    final events = <String>[];
    final service = SessionExpiryService(
      markInvalidated: (_, __) {},
      clearSession: (reason) async {
        events.add(reason);
        await client.clearToken();
      },
      showMessage: events.add,
      navigateToLogin: () => events.add('login'),
    );
    ApiClient.onAuthExpired = service.handleExpired;
    await client.expireSessionIfNeeded();
    await client.loadToken();
    expect(client.token, isNull);
    expect(events, ['session_expired', '身份信息过期，请重新登录', 'login']);
  });

  testWidgets(
      'staying on chat expires business auth without an IM event or HTTP request',
      (tester) async {
    var now = DateTime.now();
    await tester.runAsync(
        () => client.saveToken(jwt(now.add(const Duration(seconds: 5)))));
    var imConnected = true;
    final navigator = GlobalKey<NavigatorState>();
    final notices = <String>[];
    final events = <String>[];
    final service = SessionExpiryService(
      markInvalidated: (_, __) {},
      clearSession: (reason) async {
        events.add(reason);
        imConnected = false;
        client.setLogoutInProgress(true);
      },
      showMessage: notices.add,
      navigateToLogin: () {
        navigator.currentState!.pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const Text('Login')),
            (_) => false);
      },
    );
    ApiClient.onAuthExpired = service.handleExpired;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) =>
          BusinessSessionGuard(now: () => now, child: child!),
      home: const Text('Chat'),
    ));
    expect(imConnected, isTrue);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(imConnected, isFalse);
    expect(events, ['session_expired']);
    expect(notices, ['身份信息过期，请重新登录']);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('resuming checks wall-clock expiry immediately', (tester) async {
    var now = DateTime.now();
    await tester.runAsync(
        () => client.saveToken(jwt(now.add(const Duration(hours: 1)))));
    await tester.pumpWidget(
        BusinessSessionGuard(now: () => now, child: const SizedBox()));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(expiryCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    expect(expiryCalls, 1);
  });

  testWidgets('replacement token cancels the previous deadline',
      (tester) async {
    var now = DateTime.now();
    await tester.runAsync(
        () => client.saveToken(jwt(now.add(const Duration(seconds: 5)))));
    await tester.pumpWidget(
        BusinessSessionGuard(now: () => now, child: const SizedBox()));
    await tester.runAsync(() => client
        .saveToken(jwt(now.add(const Duration(hours: 1)), owner: 'account-b')));
    now = now.add(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(expiryCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'expiry during login is rechecked after auth-flow suppression ends',
      (tester) async {
    client.setSuppressAuthExpired(true);
    final now = DateTime.now();
    await tester.runAsync(
        () => client.saveToken(jwt(now.subtract(const Duration(seconds: 1)))));
    await tester.pumpWidget(
        BusinessSessionGuard(now: () => now, child: const SizedBox()));
    await tester.pump();
    expect(expiryCalls, 0);
    client.setSuppressAuthExpired(false);
    await tester.pump(const Duration(milliseconds: 1));
    expect(expiryCalls, 1);
  });
}
