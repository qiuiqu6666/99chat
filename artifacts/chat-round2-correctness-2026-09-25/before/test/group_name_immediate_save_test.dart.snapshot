import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _SlowRefreshService extends GroupMembershipSyncService {
  _SlowRefreshService() : super.forTest();

  final refreshing = Completer<void>();
  final releaseRefresh = Completer<void>();

  @override
  Future<void> refreshGroupDetail(String groupId,
      {bool refresh = false}) async {
    refreshing.complete();
    await releaseRefresh.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'name-immediate-owner';
  const group = '@TGS#_mcNameImmediate';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  setUp(() async {
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await GroupLocalStore.instance.clearForOwner(owner);
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupType': 'Community',
        'groupName': 'Old name',
        'notice': 'Keep notice',
        'avatarUrl': 'https://test/avatar.png',
        'memberCount': 10,
        'updatedAt': 1000,
      }),
    );
  });

  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  test('backend success publishes name before slow SDK refresh completes',
      () async {
    final backendStarted = Completer<void>();
    final backendResponse = Completer<void>();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        expect(request.method, 'PUT');
        expect(request.data['groupName'], 'New name');
        backendStarted.complete();
        await backendResponse.future;
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{'groupId': group}
          },
        ));
      },
    ));
    final service = _SlowRefreshService();
    final model = TUIGroupProfileModel()
      ..groupID = group
      ..groupInfo = GroupLocalStore.instance
          .readCached(groupId: group)!
          .toV2TimGroupInfo();
    addTearDown(model.dispose);
    final saving = service.updateGroupInfo(
        info: V2TimGroupInfo(
      groupID: group,
      groupType: 'Community',
      groupName: 'New name',
    ));
    await backendStarted.future;
    expect(model.groupInfo?.groupName, 'Old name');
    backendResponse.complete();
    await service.refreshing.future;
    try {
      final stored = GroupLocalStore.instance.readCached(groupId: group)!;
      expect(stored.groupName, 'New name');
      expect(model.groupInfo?.groupName, 'New name');
      expect(stored.notice, 'Keep notice');
      expect(stored.avatarUrl, 'https://test/avatar.png');
      expect(stored.memberCount, 10);
    } finally {
      service.releaseRefresh.complete();
      await saving;
    }
    expect(model.groupInfo?.groupName, 'New name');
  });

  test('failed backend save keeps the existing local name', () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) =>
          handler.reject(DioError(requestOptions: request)),
    ));
    final service = _SlowRefreshService();
    final result = await service.updateGroupInfo(
        info: V2TimGroupInfo(
      groupID: group,
      groupType: 'Community',
      groupName: 'Rejected name',
    ));
    expect(result.code, isNot(0));
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'Old name');
    expect(service.refreshing.isCompleted, isFalse);
  });

  Future<V2TimCallback> saveName(
    GroupMembershipSyncService service, {
    String name = 'New name',
  }) {
    return service.updateGroupInfo(
      info: V2TimGroupInfo(
        groupID: group,
        groupType: 'Community',
        groupName: name,
      ),
    );
  }

  void resolvePut(dynamic data) {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        expect(request.method, 'PUT');
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: data,
        ));
      },
    ));
  }

  Future<V2TimCallback> saveNameThroughRefresh(
    _SlowRefreshService service, {
    String name = 'New name',
  }) async {
    final saving = saveName(service, name: name);
    await service.refreshing.future;
    service.releaseRefresh.complete();
    return saving;
  }

  test('PUT success with data:true still commits the new name', () async {
    resolvePut(<String, dynamic>{'data': true});
    final service = _SlowRefreshService();
    final result = await saveNameThroughRefresh(service);
    expect(result.code, 0);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'New name');
  });

  test('PUT success with null body still commits the new name', () async {
    resolvePut(null);
    final service = _SlowRefreshService();
    final result = await saveNameThroughRefresh(service);
    expect(result.code, 0);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'New name');
  });

  test('PUT success with result:"ok" still commits the new name', () async {
    resolvePut(<String, dynamic>{'result': 'ok'});
    final service = _SlowRefreshService();
    final result = await saveNameThroughRefresh(service);
    expect(result.code, 0);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'New name');
  });

  test('HTTP 200 business error does not overwrite the local name', () async {
    resolvePut(<String, dynamic>{'code': 'NOT_GROUP_OWNER_OR_ADMIN'});
    final service = _SlowRefreshService();
    final result = await saveName(service, name: 'Rejected name');
    expect(result.code, isNot(0));
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'Old name');
    expect(service.refreshing.isCompleted, isFalse);
  });

  test('PUT map without groupId still commits via optimistic name', () async {
    resolvePut(<String, dynamic>{
      'data': <String, dynamic>{'ok': true},
    });
    final service = _SlowRefreshService();
    final result = await saveNameThroughRefresh(service);
    expect(result.code, 0);
    expect(GroupLocalStore.instance.readCached(groupId: group)?.groupName,
        'New name');
  });
}
