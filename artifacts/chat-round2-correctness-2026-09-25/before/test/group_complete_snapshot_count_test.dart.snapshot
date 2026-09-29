import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_group_profile_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

GroupMemberRecord member(int n) => GroupMemberRecord(
    userId: 'member$n',
    nickname: '',
    avatarUrl: '',
    friendRemark: '',
    nameCard: '',
    role: 200,
    joinedAt: n,
    isSelf: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = GroupMemberLocalStore.instance;
  const owner = 'complete-member-count-owner';
  const group = '@TGS#_mcCount123';
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await ApiClient.instance.saveToken('test-token', userId: owner);
  });
  setUp(() async {
    ApiClient.instance.dio.interceptors.clear();
    await store.clearForOwner(owner);
    await GroupLocalStore.instance.clearForOwner(owner);
  });
  tearDown(() async {
    ApiClient.instance.dio.interceptors.clear();
    await store.clearForOwner(owner);
    await GroupLocalStore.instance.clearForOwner(owner);
  });

  Future<void> putMetadata(int count, {int updatedAt = 2000}) =>
      GroupLocalStore.instance
          .upsert(
              ownerUserId: owner,
              record: MeGroupRecord.fromJson({
                'groupId': group,
                'groupName': 'Committed group',
                'memberCount': count,
                'updatedAt': updatedAt,
              }))
          .then((_) {});

  test('detail repairs name while member title keeps newer committed count',
      () async {
    await putMetadata(1403);
    var detailCalls = 0;
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) {
        detailCalls++;
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'data': {
            'groupId': group,
            'groupName': 'Current REST name',
            'memberCount': 1418,
            'updatedAt': 1999
          }
        }));
      },
    ));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);
    expect(detailCalls, 1);
    expect(model.groupInfo!.groupName, 'Current REST name');
    expect(model.groupInfo!.memberCount, 1403);
    expect(model.displayedMemberCount(), 1403);
    expect(await store.readCompleteSnapshotCount(groupId: group), isNull);
  });

  test('ID-only detail uses Store-merged fields and count commits notify page',
      () async {
    await putMetadata(1403);
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (request, handler) => handler
          .resolve(Response(requestOptions: request, statusCode: 200, data: {
        'data': {'groupId': group, 'updatedAt': 2001}
      })),
    ));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    await model.loadGroupInfo(group);
    expect(model.groupInfo!.groupName, 'Committed group');
    expect(model.displayedMemberCount(), 1403);
    var notifications = 0;
    model.addListener(() => notifications++);
    await putMetadata(0, updatedAt: 2002);
    expect(notifications, greaterThan(0));
    expect(model.displayedMemberCount(), 0);
    model.groupInfo = V2TimGroupInfo(
        groupID: group, groupType: 'Community', memberCount: 1418);
    expect(model.displayedMemberCount(), 1418);
  });

  test('partial pages cannot become totals; complete empty snapshot is zero',
      () async {
    await store.upsertMany(
        ownerUserId: owner, groupId: group, records: List.generate(10, member));
    expect(await store.readCompleteSnapshotCount(groupId: group), isNull);
    await store
        .replaceSnapshot(ownerUserId: owner, groupId: group, records: []);
    expect(await store.readCompleteSnapshotCount(groupId: group), 0);
    expect(
        await store.readCompleteSnapshotCount(
            groupId: group, ownerUserId: 'another-owner'),
        isNull);
  });

  test('profile total follows complete snapshot without expanding ten-row page',
      () async {
    await store.replaceSnapshot(
        ownerUserId: owner,
        groupId: group,
        records: List.generate(118, member));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    model.groupMemberList = List.generate(
        10, (i) => V2TimGroupMemberFullInfo(userID: member(i).userId));
    model.groupInfo =
        V2TimGroupInfo(groupID: group, groupType: 'Public', memberCount: 203);
    await model.refreshMemberCountFromLocalSnapshot();
    expect(await store.readCompleteSnapshotCount(groupId: group), 118);
    expect(model.displayedMemberCount(cachedCount: 103), 203);
    expect(model.groupMemberList.length, 10);
    await store.deleteUsers(
        ownerUserId: owner, groupId: group, userIds: ['member117']);
    await model.refreshMemberCountFromLocalSnapshot();
    expect(await store.readCompleteSnapshotCount(groupId: group), 117);
    expect(model.displayedMemberCount(cachedCount: 103), 203);
    expect(model.groupMemberList.length, 10);
    await store
        .replaceSnapshot(ownerUserId: owner, groupId: group, records: []);
    await model.refreshMemberCountFromLocalSnapshot();
    expect(await store.readCompleteSnapshotCount(groupId: group), 0);
    expect(model.displayedMemberCount(cachedCount: 103), 203);
    await store.clearGroup(ownerUserId: owner, groupId: group);
    await model.refreshMemberCountFromLocalSnapshot();
    expect(await store.readCompleteSnapshotCount(groupId: group), isNull);
    expect(model.displayedMemberCount(cachedCount: 103), 203);
  });

  test('late count from previous group cannot update reused profile', () async {
    await store.replaceSnapshot(
        ownerUserId: owner, groupId: group, records: List.generate(20, member));
    final model = TUIGroupProfileModel()..groupID = group;
    addTearDown(model.dispose);
    final pending = model.refreshMemberCountFromLocalSnapshot();
    model.groupID = '@TGS#_mcOther123';
    await pending;
    await model.refreshMemberCountFromLocalSnapshot();
    model.groupInfo = V2TimGroupInfo(
        groupID: '@TGS#_mcOther123', groupType: 'Community', memberCount: 3);
    expect(model.displayedMemberCount(cachedCount: 99), 3);
  });
}
