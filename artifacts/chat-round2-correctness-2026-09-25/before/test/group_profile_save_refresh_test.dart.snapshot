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
import 'package:tencent_cloud_chat_demo/utils/group_display_resolver.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/group/group_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _DelayedGroupServices implements GroupServices {
  final started = Completer<void>();
  final response = Completer<List<V2TimGroupInfoResult>>();

  @override
  Future<List<V2TimGroupInfoResult>?> getGroupsInfo({
    required List<String> groupIDList,
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'profile-save-owner';
  const group = '@TGS#_mcProfileSave';

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
        'avatarUrl': 'https://old.test/avatar.png',
        'notice': 'Old notice',
        'memberCount': 10,
        'myRole': 400,
        'updatedAt': 1000,
      }),
    );
  });

  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  for (final notice in ['New notice', '']) {
    test('saved notice "$notice" reaches the open profile and Store', () async {
      ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.method, 'PUT');
          expect(request.data['notice'], notice);
          handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            // A successful save may return only the changed fields.
            data: <String, dynamic>{
              'data': <String, dynamic>{'groupId': group, 'notice': notice},
            },
          ));
        },
      ));
      final model = TUIGroupProfileModel()
        ..groupID = group
        ..groupInfo = GroupLocalStore.instance
            .readCached(groupId: group)!
            .toV2TimGroupInfo();
      addTearDown(model.dispose);
      var notifications = 0;
      model.addListener(() => notifications++);

      final result = await GroupMembershipSyncService.instance.updateGroupInfo(
        info: V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          notification: notice,
        ),
      );

      final stored = GroupLocalStore.instance.readCached(groupId: group)!;
      expect(result.code, 0);
      expect(stored.notice, notice);
      expect(model.groupInfo?.notification, notice);
      expect(notifications, greaterThan(0));
      expect(
          GroupDisplayResolver.resolveNoticeFromSources(
            localRecord: stored,
            fallbackNotification: 'Old notice',
          ),
          notice);
      expect(stored.groupName, 'Old name');
      expect(stored.memberCount, 10);
      expect(stored.avatarUrl, 'https://old.test/avatar.png');
    });
  }

  for (final restAvailable in [true, false]) {
    test('late SDK response preserves edits (REST available: $restAvailable)',
        () async {
      ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) {
          if (!restAvailable) {
            handler.reject(DioError(requestOptions: request));
            return;
          }
          handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'data': <String, dynamic>{'groupId': group, 'updatedAt': 1000},
            },
          ));
        },
      ));
      final services = _DelayedGroupServices();
      await serviceLocator.unregister<GroupServices>();
      serviceLocator.registerSingleton<GroupServices>(services);
      final model = TUIGroupProfileModel()..groupID = group;
      addTearDown(model.dispose);
      final loading = model.loadGroupInfo(group);
      await services.started.future;
      await GroupLocalStore.instance.patch(
        ownerUserId: owner,
        groupId: group,
        transform: (current) => current.copyWith(
          groupName: 'Saved name',
          avatarUrl: 'https://new.test/avatar.png',
          notice: 'Saved notice',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      expect(model.groupInfo?.notification, 'Saved notice');
      services.response.complete([
        V2TimGroupInfoResult(
          resultCode: 0,
          groupInfo: V2TimGroupInfo(
            groupID: group,
            groupType: 'Community',
            groupName: 'Old name',
            faceUrl: 'https://old.test/avatar.png',
            notification: 'Old notice',
            memberCount: 12,
          ),
        ),
      ]);
      await loading;

      final stored = GroupLocalStore.instance.readCached(groupId: group)!;
      expect(stored.groupName, 'Saved name');
      expect(stored.avatarUrl, 'https://new.test/avatar.png');
      expect(model.groupInfo?.groupName, 'Saved name');
      expect(model.groupInfo?.faceUrl, 'https://new.test/avatar.png');
      expect(model.groupInfo?.notification, 'Saved notice');
      expect(model.displayedMemberCount(), 12);
    });
  }

  test('late unversioned REST detail cannot overwrite a saved notice',
      () async {
    final restStarted = Completer<void>();
    final restResponse = Completer<void>();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) async {
        restStarted.complete();
        await restResponse.future;
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'groupId': group,
              'notice': 'Old notice',
            },
          },
        ));
      },
    ));
    final services = _DelayedGroupServices();
    services.response.complete([
      V2TimGroupInfoResult(
        resultCode: 0,
        groupInfo: V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          memberCount: 10,
        ),
      ),
    ]);
    await serviceLocator.unregister<GroupServices>();
    serviceLocator.registerSingleton<GroupServices>(services);
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final loading = model.loadGroupInfo(group);
    await restStarted.future;
    await GroupMembershipSyncService.instance.applyOptimisticNotice(
      groupId: group,
      notice: 'Saved notice',
    );
    restResponse.complete();
    await loading;
    expect(GroupLocalStore.instance.readCached(groupId: group)?.notice,
        'Saved notice');
    expect(model.groupInfo?.notification, 'Saved notice');
  });

  test('failed save leaves the existing notice unchanged', () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) =>
          handler.reject(DioError(requestOptions: request)),
    ));
    final result = await GroupMembershipSyncService.instance.updateGroupInfo(
      info: V2TimGroupInfo(
        groupID: group,
        groupType: 'Community',
        notification: 'Rejected notice',
      ),
    );
    expect(result.code, isNot(0));
    expect(GroupLocalStore.instance.readCached(groupId: group)?.notice,
        'Old notice');
  });

  for (final notice in ['Saved notice', '']) {
    test('unversioned SDK metadata preserves confirmed notice "$notice"', () {
      final saved = GroupLocalStore.instance
          .readCached(groupId: group)!
          .copyWith(
              notice: notice,
              noticeUpdatedAt: 2000000,
              noticeUpdatedBy: owner,
              updatedAt: 2000000);
      final merged = MeGroupRecord.fromV2TimGroupInfo(
        V2TimGroupInfo(
          groupID: group,
          groupType: 'Community',
          notification: 'Old notice',
          groupName: 'SDK name',
          memberCount: 12,
        ),
        preserveFrom: saved,
      );
      expect(merged.notice, notice);
      expect(merged.noticeUpdatedAt, saved.noticeUpdatedAt);
      expect(merged.noticeUpdatedBy, owner);
      expect(merged.groupName, saved.groupName);
      expect(merged.memberCount, 12);
    });
  }
}
