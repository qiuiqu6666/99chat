import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'group-detail-dedupe-owner';
  const group = '@TGS#_mcDetailDedupe';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });

  setUp(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });
  tearDown(() async {
    await GroupLocalStore.instance.clearForOwner(owner);
    ApiClient.instance.dio.interceptors.clear();
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });

  test('coalesces concurrent normal detail calls but keeps refresh separate',
      () async {
    final normal = Completer<Response<dynamic>>();
    final forced = Completer<Response<dynamic>>();
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          final isRefresh = request.queryParameters['refresh'] == true;
          (isRefresh ? forced : normal).future.then(handler.resolve);
        },
      ),
    );

    final first = MeGroupApi.instance.fetchGroupDetail(group);
    final second = MeGroupApi.instance.fetchGroupDetail(group);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);

    final refresh = MeGroupApi.instance.fetchGroupDetail(
      group,
      refresh: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 2);

    Response<dynamic> response() => Response<dynamic>(
          requestOptions: RequestOptions(path: '/group/$group'),
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'groupId': group,
              'groupName': 'Dedupe group',
              'memberCount': 7,
              'updatedAt': 1789069002315,
            },
          },
        );

    normal.complete(response());
    forced.complete(response());
    expect((await first)?.groupName, 'Dedupe group');
    expect((await second)?.memberCount, 7);
    expect((await refresh)?.groupName, 'Dedupe group');
  });

  test('parses the shared raw payload with each caller fallback', () async {
    final responseGate = Completer<Response<dynamic>>();
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          responseGate.future.then(handler.resolve);
        },
      ),
    );
    final muted = MeGroupRecord.fromJson(<String, dynamic>{
      'groupId': group,
      'isAllMuted': true,
    });
    final unmuted = MeGroupRecord.fromJson(<String, dynamic>{
      'groupId': group,
      'isAllMuted': false,
    });

    final first = MeGroupApi.instance.fetchGroupDetail(
      group,
      preserveIsAllMutedFrom: muted,
    );
    final second = MeGroupApi.instance.fetchGroupDetail(
      group,
      preserveIsAllMutedFrom: unmuted,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
    responseGate.complete(
      Response<dynamic>(
        requestOptions: RequestOptions(path: '/group/$group'),
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'groupId': group,
            'groupName': 'Raw payload',
            'updatedAt': 1789069002315,
          },
        },
      ),
    );
    expect((await first)?.isAllMuted, isTrue);
    expect((await second)?.isAllMuted, isFalse);
  });

  test('account generation prevents sharing an old owner request', () async {
    final gates = <Completer<Response<dynamic>>>[];
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          final gate = Completer<Response<dynamic>>();
          gates.add(gate);
          gate.future.then(handler.resolve);
        },
      ),
    );
    final oldOwner = MeGroupApi.instance.fetchGroupDetail(group);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    SessionIdentityService.instance.invalidate(reason: 'test_account_switch');
    await ApiClient.instance.saveToken('test-token-b', userId: 'other-owner');
    final newOwner = MeGroupApi.instance.fetchGroupDetail(group);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 2);

    Response<dynamic> response(String name) => Response<dynamic>(
          requestOptions: RequestOptions(path: '/group/$group'),
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'groupId': group,
              'groupName': name,
              'updatedAt': 1789069002315,
            },
          },
        );
    gates[0].complete(response('old owner'));
    gates[1].complete(response('new owner'));
    expect(await oldOwner, isNull);
    expect((await newOwner)?.groupName, 'new owner');
  });

  test('a failed detail request is removed so the next call retries', () async {
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.reject(DioError(requestOptions: request));
        },
      ),
    );
    await expectLater(
      MeGroupApi.instance.fetchGroupDetail(group),
      throwsA(isA<DioError>()),
    );
    await expectLater(
      MeGroupApi.instance.fetchGroupDetail(group),
      throwsA(isA<DioError>()),
    );
    expect(calls, 2);
  });
}
