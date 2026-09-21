import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/platform/uikit_user_profile_local_bridge.dart';
import 'package:tencent_cloud_chat_demo/src/services/c2c_friend_message_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/utils/friend_display_fields_merge.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_demo/utils/user_display_profile.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/profile/user_profile_local_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const owner = 'chatremarkowner';
  const peer = 'chatremarkpeer';
  final profiles = UserProfileLocalService.instance;
  final profileStore = UserProfileLocalStore.instance;
  final friends = FriendLocalStore.instance;
  late Interceptor relationResponse;

  setUp(() async {
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await profiles.clearSession();
    await profileStore.clearForOwner(owner);
    await friends.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
    C2cFriendMessageGuard.debugReset();
    UikitUserProfileLocalBridge.install();
    relationResponse = InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/me/friends/$peer/relation') {
        handler
            .resolve(Response(requestOptions: options, statusCode: 200, data: {
          'peerUserId': peer,
          'isFriend': true,
          'inMyFriendList': true,
          'canMessage': true,
          'peerDeletedMe': false,
        }));
      } else {
        handler.reject(
            DioError(requestOptions: options, error: 'Unexpected request'));
      }
    });
    ApiClient.instance.dio.interceptors.insert(0, relationResponse);
  });

  tearDown(() async {
    ApiClient.instance.dio.interceptors.remove(relationResponse);
    await profiles.clearSession();
    await profileStore.clearForOwner(owner);
    await friends.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
    C2cFriendMessageGuard.debugReset();
    UserProfileLocalBridge.clear();
  });

  test(
      'chat permission lookup and public profile refresh retain cold-start remark',
      () async {
    await profileStore.upsert(
        record: UserProfileRecord(userId: peer, nickname: 'Public Nick'));
    DisplayNameStore.instance.setC2C(peer, 'Saved Remark', notify: false);
    expect(FriendDisplayName.resolveC2C(userId: peer), 'Saved Remark');

    final permission =
        await C2cFriendMessageGuard.refreshUiSnapshot(peer, forceNetwork: true);
    expect(permission.decision, C2cSendPermissionDecision.allowed);
    await profiles.read(peer);
    await FriendSyncService.instance
        .warmupC2cDisplayNamesFromLocalStore(friendUserIds: [peer]);
    await UserProfileLocalBridge.saveUserInfo(
        V2TimUserFullInfo(userID: peer, nickName: 'New Public Nick'));

    expect(DisplayNameStore.instance.c2c(peer), 'Saved Remark');
    expect(FriendDisplayName.resolveC2C(userId: peer), 'Saved Remark');
    expect(
        FriendDisplayName.resolveLocalFirst(
            userId: peer, localProfile: profiles.readCached(peer)),
        'Saved Remark');
    expect(UserDisplayProfile.nameOfFriend(V2TimFriendInfo(userID: peer)),
        'Saved Remark');
  });

  test('contacts and C2C agree before the hosted remark is warmed', () async {
    await profiles.saveUserFullInfo(
        V2TimUserFullInfo(userID: peer, nickName: 'Public Nick'));
    DisplayNameStore.instance.setC2C(peer, 'Saved Remark', notify: false);
    expect(UserDisplayProfile.nameOfFriend(V2TimFriendInfo(userID: peer)),
        'Saved Remark');
    expect(FriendDisplayName.resolveC2C(userId: peer), 'Saved Remark');
  });

  test('explicit clear remains authoritative after reloading from disk',
      () async {
    await profiles.saveUserFullInfo(
        V2TimUserFullInfo(userID: peer, nickName: 'Public Nick'));
    await profiles.saveFriendRemark(userId: peer, remark: '');
    await profiles.clearSession();
    await profiles.read(peer);
    expect(profiles.isFriendRemarkConfirmed(peer), isTrue);
    expect(
        FriendDisplayName.resolveFriendRemark(
            userId: peer, imRemark: 'Old Remark'),
        '');
    expect(
        FriendDisplayName.resolveC2C(
            userId: peer, conversationShowName: 'Old Remark'),
        'Public Nick');
  });

  test('a captured chat profile cannot override a newer warmed remark',
      () async {
    await profiles.saveUserFullInfo(
        V2TimUserFullInfo(userID: peer, nickName: 'Public Nick'));
    final captured = profiles.readCached(peer);
    profiles.hydrateFromFriendRecords([
      MeFriendRecord(
        friendUserId: peer,
        remark: 'Saved Remark',
        friendNickname: 'Public Nick',
        friendAvatarUrl: '',
        addedAt: 0,
        peerDeletedMe: false,
        canMessage: true,
      )
    ]);
    expect(
        FriendDisplayName.resolveLocalFirst(
            userId: peer, localProfile: captured),
        'Saved Remark');
  });

  test('relation shell stays unknown after disk reload and profile event',
      () async {
    await C2cFriendMessageGuard.refreshUiSnapshot(peer, forceNetwork: true);
    await friends.closeIfOpen();
    final shell = (await friends.readByIds(friendUserIds: [peer])).single;
    expect(shell.remarkKnown, isFalse);
    expect((await friends.readAll()).single.remarkKnown, isFalse);
    DisplayNameStore.instance.setC2C(peer, 'Saved Remark', notify: false);
    await FriendSyncService.instance
        .applyListChanged(FriendRealtimeEvent.fromJson({
      'event': 'friend_list_changed',
      'action': 'profile_updated',
      'peerUserId': peer,
      'peerNickname': 'Updated Nick',
    }));
    expect(profiles.isFriendRemarkConfirmed(peer), isFalse);
    expect(DisplayNameStore.instance.c2c(peer), 'Saved Remark');
    final merged = await profiles.mergeHostedFriendRemark(
        peer, V2TimFriendInfo(userID: peer, friendRemark: 'Saved Remark'));
    expect(merged?.friendRemark, 'Saved Remark');
  });

  test('batch profile hydration cannot promote an unknown remark to a clear',
      () async {
    await profiles.saveFriendRemark(userId: peer, remark: 'Saved Remark');
    final unknown = MeFriendRecord.fromJson({
      'friendUserId': peer,
      'nickname': 'Updated Nick',
    });
    await profiles.saveFriendRecords([unknown]);
    expect(profiles.readCached(peer)?.friendRemark, 'Saved Remark');
    await profiles.clearSession();
    expect((await profiles.read(peer))?.friendRemark, 'Saved Remark');
    expect(profiles.isFriendRemarkConfirmed(peer), isTrue);
  });

  test('explicit clear of a relation shell persists in both stores', () async {
    await C2cFriendMessageGuard.refreshUiSnapshot(peer, forceNetwork: true);
    await profiles.saveBackendProfile(userId: peer, nickname: 'Public Nick');
    DisplayNameStore.instance.setC2C(peer, 'Old Remark', notify: false);
    expect(
        await friends.updateRemark(
            ownerUserId: owner, friendUserId: peer, remark: ''),
        isTrue);
    await profiles.saveFriendRecord(
        (await friends.readByIds(friendUserIds: [peer])).single);
    await profiles.clearSession();
    await friends.closeIfOpen();
    await profileStore.closeIfOpen();
    expect((await friends.readAll()).single.remarkKnown, isTrue);
    await profiles.read(peer);
    expect(
        FriendDisplayName.resolveFriendRemark(
            userId: peer, imRemark: 'Old Remark'),
        '');
    expect(
        UserDisplayProfile.nameOfFriend(
            V2TimFriendInfo(userID: peer, friendRemark: 'Old Remark')),
        'Public Nick');
  });

  test(
      'public-only contacts use the current nickname when no remark is available',
      () async {
    await profiles.saveBackendProfile(userId: peer, nickname: 'Current Nick');
    expect(UserDisplayProfile.nameOfFriend(V2TimFriendInfo(userID: peer)),
        'Current Nick');
    expect(
        UserDisplayProfile.nameOfFriend(V2TimFriendInfo(
            userID: peer,
            userProfile:
                V2TimUserFullInfo(userID: peer, nickName: 'Old Nick'))),
        'Current Nick');
  });

  test(
      'a profile-only merge does not manufacture an authoritative empty remark',
      () {
    final unknown = MeFriendRecord.fromJson(
        {'friendUserId': peer, 'nickname': 'Public Nick'});
    expect(unknown.remarkKnown, isFalse);
    expect(
        FriendDisplayFieldsMerge.merge(
                incoming: unknown,
                profile:
                    UserProfileRecord(userId: peer, nickname: 'Public Nick'))
            .remarkKnown,
        isFalse);
    expect(
        MeFriendRecord.fromJson({'friendUserId': peer, 'remark': ''})
            .remarkKnown,
        isTrue);
  });
}
