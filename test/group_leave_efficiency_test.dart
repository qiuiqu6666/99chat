import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

MeGroupRecord group(String id) => MeGroupRecord(
    groupId: id,
    groupType: 'Work',
    groupName: id,
    displayAlias: '',
    avatarUrl: '',
    notice: '',
    memberCount: 1,
    myRole: 200,
    myNameCard: '',
    joinedAt: 1,
    updatedAt: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var requests = 0;
  const owner = 'leave-efficiency';
  const id = '@TGS#leave-efficiency';
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      handler.reject(DioError(requestOptions: request));
    }));
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });
  setUp(() async {
    SessionIdentityService.instance.invalidate();
    requests = 0;
    GroupMembershipSyncService.instance.clearExplicitGroupRemovalForTest(id);
    await GroupLocalStore.instance
        .upsert(ownerUserId: owner, record: group(id));
    await GroupLocalStore.instance
        .upsert(ownerUserId: owner, record: group('keep'));
    await GroupMemberLocalStore.instance
        .upsertMany(ownerUserId: owner, groupId: id, records: [
      GroupMemberRecord(
          userId: owner,
          nickname: 'self',
          avatarUrl: '',
          friendRemark: '',
          nameCard: '',
          role: 200,
          joinedAt: 1,
          isSelf: true)
    ]);
  });
  tearDown(() {
    GroupMembershipSyncService.instance.clearExplicitGroupRemovalForTest(id);
    SessionIdentityService.instance.invalidate();
  });

  test(
      'visible removal returns before members/history cleanup, preserving other groups',
      () async {
    final service = GroupMembershipSyncService.instance;
    await Future.wait([
      service.onSelfRemovedFromGroup(id),
      service.onSelfRemovedFromGroup(id)
    ]);
    expect(await GroupLocalStore.instance.read(ownerUserId: owner, groupId: id),
        isNull);
    expect(
        await GroupLocalStore.instance
            .read(ownerUserId: owner, groupId: 'keep'),
        isNotNull);
    expect(
        await GroupMemberLocalStore.instance
            .readAll(ownerUserId: owner, groupId: id),
        hasLength(1));
    expect(service.isExplicitlyRemovedGroup(id), isTrue);
    expect(requests, 0);
  });

  for (final action in ['member_left', 'member_removed', 'group_dismissed']) {
    test(
        '$action stops at confirmed removal without membership refresh fan-out',
        () async {
      await GroupSyncService.instance.handleRealtimeEvent(FriendRealtimeEvent(
          event: 'group_changed',
          fromUserId: owner,
          toUserId: owner,
          groupId: id,
          action: action,
          memberUserIds: [owner]));
      await GroupMembershipSyncService.instance
          .syncMembersAfterMembershipChange(id);
      expect(GroupSyncService.instance.lastChanged.value?.action, action);
      expect(requests, 0);
      expect(
          await GroupLocalStore.instance.read(ownerUserId: owner, groupId: id),
          isNull);
    });
  }
}
