import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/device_sync_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'contract-service-owner';
  const contacts = MethodChannel('github.com/QuisApp/flutter_contacts');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  late List<Interceptor> saved;
  final requests = <RequestOptions>[];
  var blocked = false;
  setUp(() async {
    requests.clear();
    blocked = false;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'device_id': 'contract-device'});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await ApiClient.instance.ensureDeviceIdReady();
    await ApiClient.instance.saveToken('contract-local-token', userId: owner);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(permissions, (_) async => 1);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts, (_) async => [
      Contact(id: 'one', displayName: 'One', phones: [Phone('+86123')]).toJson()
    ]);
    final dio = ApiClient.instance.dio;
    saved = dio.interceptors.toList();
    dio.interceptors..clear()..add(InterceptorsWrapper(onRequest: (r, handler) {
      requests.add(r);
      if (blocked) {
        handler.reject(DioError(requestOptions: r, type: DioErrorType.response,
          response: Response(requestOptions: r, statusCode: 403,
            data: {'code': 'DEVICE_NOT_BOUND', 'message': 'DEVICE_NOT_BOUND'})));
        return;
      }
      final Object payload;
      switch (r.path) {
        case '/me/sync/status':
          payload = {'contactsDeltaV2': true, 'types': []};
          break;
        case '/me/sync/contacts/sessions':
          payload = {'syncSessionId': 's1'};
          break;
        case '/me/sync/contacts/batch':
          payload = {'uploaded': 1, 'skipped': 0, 'failed': 0};
          break;
        case '/me/sync/contacts/complete':
          payload = {'syncSessionId': 's1', 'status': 'COMPLETED', 'committedRevision': 1};
          break;
        default:
          handler.reject(DioError(requestOptions: r, error: 'Unexpected route'));
          return;
      }
      handler.resolve(Response(requestOptions: r, statusCode: 200,
        data: {'code': 0, 'message': 'ok', 'data': payload}));
    }));
  });
  tearDown(() async {
    await DeviceSyncService.instance.clearForOwner(owner);
    ApiClient.instance.dio.interceptors..clear()..addAll(saved);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(contacts, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(permissions, null);
    await ApiClient.instance.clearToken();
    debugDefaultTargetPlatformOverride = null;
  });
  test('real service keeps legacy writes while querying device capability', () async {
    await DeviceSyncService.instance.syncAfterLogin();
    expect(requests.first.queryParameters['deviceId'], 'contract-device');
    final batch = requests.singleWhere((r) => r.path.endsWith('/batch')).data as Map;
    expect(batch.containsKey('baseRevision'), isFalse);
    expect(batch.containsKey('batchId'), isFalse);
    expect(batch.containsKey('payloadHash'), isFalse);
    expect((batch['items'] as List).single, contains('updatedAt'));
    expect(requests.where((r) => r.path.endsWith('/complete')), hasLength(1));
  });
  test('unbound device stops current run and subsequent runs for same identity', () async {
    blocked = true;
    await DeviceSyncService.instance.syncAfterLogin();
    await DeviceSyncService.instance.syncAfterLogin();
    expect(requests, hasLength(1));
    expect(requests.single.path, '/me/sync/status');
  });
}
