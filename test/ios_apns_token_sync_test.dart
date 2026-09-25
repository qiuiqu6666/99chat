import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/ios_apns_push_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/push_token_local/push_token_upload_local_store.dart';

class _PushAdapter implements HttpClientAdapter {
  _PushAdapter(this.reply);
  final Future<ResponseBody> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future? cancelFuture) =>
      reply(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _reply({bool ok = true, bool hasVoip = true}) =>
    ResponseBody.fromString(
        jsonEncode({
          'ok': ok,
          'platform': 'IOS',
          'provider': 'APNS',
          'hasVoipToken': hasVoip
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = ApiClient.instance;
  final store = PushTokenUploadLocalStore.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('ios_apns_push');
  late IosApnsPushService service;
  late Map<String, dynamic> nativeTokens;
  late List<RequestOptions> requests;
  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = Directory.systemTemp.createTempSync('ios_push_sync_');
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
  });
  tearDownAll(() async {
    await store.closeIfOpen();
    databaseDirectory.deleteSync(recursive: true);
  });
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(
        {'device_id': 'push-test-device'});
    SharedPreferences.setMockInitialValues({});
    client.setLogoutInProgress(false);
    await client.clearToken();
    await store.clearAll();
    service = IosApnsPushService.forTest();
    nativeTokens = {
      'apnsToken': 'apns-test',
      'voipToken': '',
      'bundleId': 'vip.99chat.iOS',
      'apsEnvironment': 'production'
    };
    requests = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCachedTokens') {
        return Map<String, dynamic>.from(nativeTokens);
      }
      return null;
    });
    client.dio.httpClientAdapter = _PushAdapter((request) async {
      requests.add(request);
      return _reply();
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await client.clearToken();
  });

  Future<void> login([String owner = 'push-owner']) =>
      client.saveToken(owner.padRight(40, 'x'), userId: owner);

  test('completed pass releases the task for a later registration', () async {
    var runs = 0;
    await service.runTokenSyncForTest(() async {
      runs++;
    });
    await service.runTokenSyncForTest(() async {
      runs++;
    });
    expect(runs, 2);
  });

  test('callbacks during upload coalesce into a second awaited pass', () async {
    final firstGate = Completer<void>(), nextGate = Completer<void>();
    final order = <String>[];
    final first = service.runTokenSyncForTest(() async {
      order.add('initial');
      await firstGate.future;
    });
    final joined = service.runTokenSyncForTest(() async {
      order.add('superseded');
    });
    final latest = service.runTokenSyncForTest(() async {
      order.add('fresh-token');
      await nextGate.future;
    });
    expect(identical(first, joined), isTrue);
    expect(identical(first, latest), isTrue);
    var finished = false;
    first.then((_) => finished = true);
    firstGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(order, ['initial', 'fresh-token']);
    expect(finished, isFalse);
    nextGate.complete();
    await latest;
    expect(finished, isTrue);
  });

  test('a failing pass still drains pending work and releases the task',
      () async {
    final gate = Completer<void>();
    final first = service.runTokenSyncForTest(() async {
      await gate.future;
      throw StateError('unavailable');
    });
    var runs = 0;
    service.runTokenSyncForTest(() async {
      runs++;
    });
    gate.complete();
    await first;
    await service.runTokenSyncForTest(() async {
      runs++;
    });
    expect(runs, 2);
  });

  test('token callback before login cannot block registration after login',
      () async {
    await service.runTokenSyncForTest();
    expect(requests, isEmpty);
    await login();
    await service.runTokenSyncForTest();
    expect(requests, hasLength(1));
    expect(requests.single.data, containsPair('apsEnvironment', 'production'));
    expect(requests.single.data, containsPair('bundleId', 'vip.99chat.iOS'));
  });

  test('restoring a saved JWT registers tokens without a new login', () async {
    await service.runTokenSyncForTest();
    expect(requests, isEmpty);
    String encodePart(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final jwt = '${encodePart({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${encodePart({
          'sub': 'restored-owner',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        })}.test-signature';
    FlutterSecureStorage.setMockInitialValues({
      'device_id': 'restored-device',
      'auth_token_secure': jwt,
      'auth_user_id_secure': 'restored-owner',
    });

    // Cold startup uses this same credential loader; no saveToken/login call.
    await client.loadToken();
    expect(client.authenticatedUserId, 'restored-owner');
    nativeTokens['voipToken'] = 'restored-voip';
    await service.runTokenSyncForTest();

    expect(requests, hasLength(1));
    expect(requests.single.path, '/me/push-token');
    expect(requests.single.headers['Authorization'], 'Bearer $jwt');
    expect(requests.single.data, containsPair('deviceId', 'restored-device'));
    expect(requests.single.data, containsPair('platform', 'IOS'));
    expect(requests.single.data, containsPair('token', 'apns-test'));
    expect(requests.single.data, containsPair('voipToken', 'restored-voip'));
    expect(requests.single.data, containsPair('bundleId', 'vip.99chat.iOS'));
  });

  test('empty initial APNs token can be registered when it arrives later',
      () async {
    await login();
    nativeTokens['apnsToken'] = '';
    await service.runTokenSyncForTest();
    expect(requests, isEmpty);
    nativeTokens['apnsToken'] = 'arrived-apns-token';
    await service.runTokenSyncForTest();
    expect(requests, hasLength(1));
    expect(requests.single.data, containsPair('token', 'arrived-apns-token'));
  });

  test(
      'historical SQLite receipt cannot block startup registration or 6h refresh',
      () async {
    await login();
    await client.ensureDeviceIdReady();
    final tokenHash = sha256
        .convert(utf8
            .encode('${client.deviceId}|apns-test||vip.99chat.ios|production'))
        .toString();
    await store.markSuccess(
        ownerUserId: 'push-owner',
        deviceId: client.deviceId,
        platform: 'IOS',
        tokenKeyHash: tokenHash);
    await service.runTokenSyncForTest();
    await service.runTokenSyncForTest();
    expect(requests, hasLength(1));
    await IosApnsPushService.forTest().runTokenSyncForTest();
    expect(requests, hasLength(2),
        reason:
            'A new app process re-registers even with fresh local receipts');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        'ios_apns_last_submit_at',
        DateTime.now()
            .subtract(const Duration(hours: 7))
            .millisecondsSinceEpoch);
    await service.runTokenSyncForTest();
    expect(requests, hasLength(3));
  });

  test('HTTP 200 ok=false is not cached as a successful registration',
      () async {
    await login();
    client.dio.httpClientAdapter = _PushAdapter((request) async {
      requests.add(request);
      return _reply(ok: requests.length > 1);
    });
    await service.runTokenSyncForTest();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ios_apns_last_submit_key'), isNull);
    await service.runTokenSyncForTest();
    expect(requests, hasLength(2));
    expect(prefs.getString('ios_apns_last_submit_key'), isNotNull);
  });

  test('failed VoIP fallback leaves registration retryable', () async {
    await login();
    nativeTokens['voipToken'] = 'voip-test';
    var voipAttempts = 0;
    client.dio.httpClientAdapter = _PushAdapter((request) async {
      requests.add(request);
      if (request.path == '/me/voip-push-token') {
        voipAttempts++;
        return _reply(ok: voipAttempts > 1);
      }
      return _reply(hasVoip: false);
    });
    await service.runTokenSyncForTest();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ios_apns_last_submit_key'), isNull);
    await service.runTokenSyncForTest();
    expect(voipAttempts, 2);
    expect(requests, hasLength(4));
    expect(prefs.getString('ios_apns_last_submit_key'), isNotNull);
  });

  test(
      'account change during POST cannot mark the old reply as current success',
      () async {
    await login('owner-a');
    final posted = Completer<void>(), reply = Completer<ResponseBody>();
    client.dio.httpClientAdapter = _PushAdapter((request) async {
      requests.add(request);
      if (requests.length == 1) {
        posted.complete();
        return reply.future;
      }
      return _reply();
    });
    final first = service.runTokenSyncForTest();
    await posted.future;
    await login('owner-b');
    final joined = service.runTokenSyncForTest();
    reply.complete(_reply());
    await first;
    await joined;
    expect(requests, hasLength(2));
    expect(requests.first.headers['Authorization'],
        isNot(requests.last.headers['Authorization']));
    await service.runTokenSyncForTest();
    expect(requests, hasLength(2));
  });
}
