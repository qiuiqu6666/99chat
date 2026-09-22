import 'dart:io';
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
import 'package:tencent_cloud_chat_uikit/business_logic/listener_model/tui_group_listener_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'sdk-identity-sync-owner';
  const group = '@TGS#_mcSdkIdentity';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  setUp(() async {
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) => handler.resolve(Response(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': {'groupId': group, 'groupName': 'REST name'}
        },
      )),
    ));
    SessionIdentityService.instance.invalidate();
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  test('SDK identity callback refreshes REST name and projects avatar',
      () async {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupType': 'Work',
        'groupName': 'Old name',
        'avatarUrl': 'https://old.test/a.png',
        'updatedAt': 1000,
      }),
    );
    await GroupMembershipSyncService.instance.applySdkGroupIdentity(
      groupId: group,
      groupName: 'SDK name',
      faceUrl: 'https://sdk.test/a.png',
    );
    final stored = GroupLocalStore.instance.readCached(groupId: group);
    expect(stored?.groupName, 'REST name');
    expect(stored?.avatarUrl, 'https://sdk.test/a.png');
  });

  test('name is published before SDK work and retained after refresh', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final nameBlockStart = source.indexOf('if (hasName) {');
    final nameBlock = source.substring(
      nameBlockStart,
      source.indexOf("action: 'group_name_changed'", nameBlockStart),
    );
    expect(nameBlock, contains('_syncIdentityToNativeSdk('));
    expect(nameBlock, contains('groupName: info.groupName'));
    expect(nameBlock, contains('refreshGroupDetail(groupId, refresh: true)'));
    expect(nameBlock, contains('applyOptimisticGroupName('));
    expect(
      nameBlock.indexOf('_syncIdentityToNativeSdk('),
      lessThan(nameBlock.indexOf('refreshGroupDetail(groupId, refresh: true)')),
    );
    expect(
      nameBlock.indexOf('applyOptimisticGroupName('),
      lessThan(nameBlock.indexOf('_syncIdentityToNativeSdk(')),
    );
    expect(
      nameBlock.indexOf('refreshGroupDetail(groupId, refresh: true)'),
      lessThan(nameBlock.lastIndexOf('applyOptimisticGroupName(')),
    );
  });

  test('optimistic group name writes Store then publishes conversation display',
      () async {
    await GroupLocalStore.instance.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': group,
        'groupType': 'Work',
        'groupName': 'Old name',
        'updatedAt': 1000,
      }),
    );
    await GroupMembershipSyncService.instance.applyOptimisticGroupName(
      groupId: group,
      groupName: 'New name',
    );
    final stored = GroupLocalStore.instance.readCached(groupId: group);
    expect(stored?.groupName, 'New name');
    expect(stored!.updatedAt, greaterThan(1000));

    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> applyOptimisticGroupName({');
    final end = source.indexOf('Future<void> applyOptimisticNotice({');
    final body = source.substring(start, end);
    expect(body, contains('GroupLocalStore.instance.upsert('));
    expect(body, contains('publishGroupConversationDisplay('));
    expect(body, isNot(contains('refreshGroupDetail(')));
  });

  test('upsertGroupAvatar writes locally then syncs SDK then refreshes', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> upsertGroupAvatar({');
    final end = source.indexOf('Future<void> applyOptimisticAvatar({');
    final body = source.substring(start, end);
    expect(body, isNot(contains('unawaited(refreshGroupDetail')));
    expect(body, contains('GroupLocalStore.instance.upsert('));
    expect(body, contains('_syncIdentityToNativeSdk('));
    expect(body, contains('faceUrl: normalized'));
    expect(body, contains('publishGroupConversationDisplay('));
    expect(body, contains('refreshGroupDetail(id, refresh: true)'));
    expect(
      body.indexOf('GroupLocalStore.instance.upsert('),
      lessThan(body.indexOf('_syncIdentityToNativeSdk(')),
    );
    expect(
      body.indexOf('_syncIdentityToNativeSdk('),
      lessThan(body.indexOf('publishGroupConversationDisplay(')),
    );
    expect(
      body.indexOf('publishGroupConversationDisplay('),
      lessThan(body.indexOf('refreshGroupDetail(id, refresh: true)')),
    );
  });

  test('self-hosted onGroupInfoChanged projects through the identity hook', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'listener_model/tui_group_listener_model.dart',
    ).readAsStringSync();
    expect(source, contains('onGroupIdentityChanged'));
    expect(source, isNot(contains('if (!SelfHostedGroupBridge.enabled)')));
    expect(
        source, contains('TUIGroupListenerModelHooks.onGroupIdentityChanged'));
    expect(
      File('lib/src/services/group_local/group_membership_sync_service.dart')
          .readAsStringSync(),
      contains('TUIGroupListenerModelHooks.onGroupIdentityChanged ='),
    );
    GroupMembershipSyncService.instance.install();
    expect(TUIGroupListenerModelHooks.onGroupIdentityChanged, isNotNull);
  });
}
