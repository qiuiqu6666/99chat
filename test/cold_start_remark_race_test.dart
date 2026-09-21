import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final service = UserProfileLocalService.instance;
  final store = UserProfileLocalStore.instance;
  const owner = 'cold_remark_owner';
  const peer = 'cold_remark_peer';
  MeFriendRecord friend(String remark) => MeFriendRecord(
        friendUserId: peer,
        remark: remark,
        friendNickname: '公开昵称',
        friendAvatarUrl: '',
        addedAt: 0,
        peerDeletedMe: false,
        canMessage: true,
      );
  String visibleName() => FriendDisplayName.resolveC2C(userId: peer);

  setUp(() async {
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await service.clearSession();
    await store.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
  });

  tearDown(() async {
    await service.clearSession();
    await store.clearForOwner(owner);
    DisplayNameStore.instance.clear(notify: false);
  });

  test('pending profile read returns the remark warmed during its await',
      () async {
    await store.upsert(
        record: UserProfileRecord(userId: peer, nickname: '旧昵称'));
    final pending = service.read(peer);
    service.hydrateFromFriendRecords([friend('好友备注')]);
    expect(visibleName(), '好友备注');
    expect((await pending)?.friendRemark, '好友备注');
    expect(visibleName(), '好友备注');
  });

  test('SDK profile completing after warmup cannot erase its remark', () async {
    final pending = service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '更新昵称'),
    );
    service.hydrateFromFriendRecords([friend('好友备注')]);
    expect(visibleName(), '好友备注');
    await pending;
    expect(visibleName(), '好友备注');
    expect(service.readCached(peer)?.nickname, '更新昵称');
    expect(DisplayNameStore.instance.c2c(peer), '好友备注');
    expect((await store.read(userId: peer))?.friendRemark, '好友备注');
  });

  test('warmup repairs a public profile already occupying the cache', () async {
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '更新昵称'),
    );
    service.hydrateFromFriendRecords([friend('好友备注')]);
    expect(visibleName(), '好友备注');
    expect(service.readCached(peer)?.nickname, '更新昵称');
  });

  test('an explicit clear survives warmup and public profile refresh',
      () async {
    await service.saveFriendRemark(userId: peer, remark: '');
    service.hydrateFromFriendRecords([friend('旧备注')]);
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '更新昵称'),
    );
    expect(service.readCached(peer)?.friendRemark, '');
    expect(visibleName(), '更新昵称');
  });

  test('remark warmed during a pending public save is persisted too', () async {
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '原昵称'),
    );
    final pending = service.saveBackendProfile(userId: peer, nickname: '新昵称');
    // Let the cached read finish and the asynchronous write start.
    await Future<void>.value();
    service.hydrateFromFriendRecords([friend('好友备注')]);
    await pending;
    expect(visibleName(), '好友备注');
    expect((await store.read(userId: peer))?.friendRemark, '好友备注');
    await service.clearSession();
    expect((await service.read(peer))?.friendRemark, '好友备注');
  });

  test('reseed publishes the confirmed clear instead of an old friend snapshot',
      () async {
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '当前昵称'),
    );
    await service.saveFriendRemark(userId: peer, remark: '');
    await FriendSyncService.instance.seedC2cDisplayNamesFromFriendRecords([
      friend('旧备注'),
    ]);
    expect(visibleName(), '当前昵称');
    expect(DisplayNameStore.instance.c2c(peer), '当前昵称');
  });

  test('public profile save cannot erase an existing Store remark', () async {
    DisplayNameStore.instance.setC2C(peer, '好友备注', notify: false);
    await service.saveUserFullInfo(
      V2TimUserFullInfo(userID: peer, nickName: '更新昵称'),
    );
    expect(visibleName(), '好友备注');
    expect(DisplayNameStore.instance.c2c(peer), '好友备注');
  });

  test('disk public nickname does not beat Store remark after read', () async {
    await store.upsert(
        record: UserProfileRecord(userId: peer, nickname: '旧昵称'));
    DisplayNameStore.instance.setC2C(peer, '好友备注', notify: false);
    await service.read(peer);
    expect(visibleName(), '好友备注');
  });

  test('first public profile save overlays the hosted friend remark',
      () async {
    await FriendLocalStore.instance.clearForOwner(owner);
    await FriendLocalStore.instance.upsert(
      ownerUserId: owner,
      record: friend('好友备注'),
    );
    try {
      await service.saveUserFullInfo(
        V2TimUserFullInfo(userID: peer, nickName: '真名'),
      );
      expect(service.readCached(peer)?.friendRemark, '好友备注');
      expect(service.readCached(peer)?.nickname, '真名');
      expect(DisplayNameStore.instance.c2c(peer), '好友备注');
    } finally {
      await FriendLocalStore.instance.clearForOwner(owner);
    }
  });
}
