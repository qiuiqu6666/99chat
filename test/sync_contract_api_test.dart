import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync status is explicitly bound to this device', () async {
    FlutterSecureStorage.setMockInitialValues({'device_id': 'device-contract'});
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.ensureDeviceIdReady();
    final dio = ApiClient.instance.dio;
    final saved = dio.interceptors.toList();
    addTearDown(() => dio.interceptors
      ..clear()
      ..addAll(saved));
    RequestOptions? seen;
    dio.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: (request, handler) {
        seen = request;
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'code': 0,
          'data': {'types': [], 'contactsDeltaV2': true}
        }));
      }));
    await SyncApi.instance.fetchStatus();
    expect(seen!.queryParameters['deviceId'], 'device-contract');
  });

  test('contact payload has canonical order and Unix updatedAt', () {
    final item = ContactSyncItemPayload(
        localContactId: 'c-1',
        fingerprint: 'fingerprint',
        displayName: '张三',
        phones: ['+86123'],
        takenAt:
            DateTime.fromMillisecondsSinceEpoch(1750000000000, isUtc: true));
    final json = item.toJson();
    expect(json.keys, [
      'localContactId',
      'fingerprint',
      'displayName',
      'phones',
      'updatedAt'
    ]);
    expect(json['updatedAt'], 1750000000);
  });
}
