import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';
import 'package:tencent_cloud_chat_demo/utils/friend_display_name.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const owner = 'migrationremarkowner';
  const peer = 'migrationremarkpeer';
  final friends = FriendLocalStore.instance;
  final profiles = UserProfileLocalService.instance;
  final profileStore = UserProfileLocalStore.instance;
  late Directory fixture;
  late String previousPath;

  setUp(() async {
    previousPath = await getDatabasesPath();
    fixture = await Directory.systemTemp.createTemp('remark_provenance_');
    await databaseFactory.setDatabasesPath(fixture.path);
    await ApiClient.instance.saveToken('test-token', userId: owner);
    await profiles.clearSession();
    DisplayNameStore.instance.clear(notify: false);
  });

  tearDown(() async {
    await friends.closeIfOpen();
    await profileStore.closeIfOpen();
    await profiles.clearSession();
    DisplayNameStore.instance.clear(notify: false);
    await databaseFactory.setDatabasesPath(previousPath);
    await fixture.delete(recursive: true);
  });

  Future<void> createOldFriends(String filename) async {
    final db = await openDatabase('${fixture.path}/$filename', version: 5,
        onCreate: (db, _) async {
      await db.execute('''CREATE TABLE friends (
        owner_user_id TEXT NOT NULL, friend_user_id TEXT NOT NULL,
        friend_nickname TEXT NOT NULL DEFAULT '',
        friend_avatar_url TEXT NOT NULL DEFAULT '', friend_avatar_version INTEGER,
        remark TEXT NOT NULL DEFAULT '', added_at INTEGER NOT NULL DEFAULT 0,
        peer_deleted_me INTEGER NOT NULL DEFAULT 0,
        can_message INTEGER NOT NULL DEFAULT 1,
        in_my_friend_list INTEGER NOT NULL DEFAULT 1,
        is_friend INTEGER NOT NULL DEFAULT 1,
        item_version INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, friend_user_id))''');
    });
    await db
        .insert('friends', {'owner_user_id': owner, 'friend_user_id': peer});
    await db.insert('friends', {
      'owner_user_id': owner,
      'friend_user_id': 'fullrecord',
      'friend_nickname': 'Public Nick',
      'remark': 'Saved Remark',
    });
    await db.insert('friends', {
      'owner_user_id': owner,
      'friend_user_id': 'clearedrecord',
      'friend_nickname': 'Public Nick',
      'remark': '',
    });
    await db.close();
  }

  test('v5 contacts and v2 profiles upgrade without clearing a cached remark',
      () async {
    await createOldFriends('contacts.db');
    final oldProfiles = await openDatabase(
        '${fixture.path}/user_profile_local_v1.db',
        version: 2, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE user_profiles (
        owner_user_id TEXT NOT NULL, user_id TEXT NOT NULL,
        nickname TEXT NOT NULL DEFAULT '', avatar_url TEXT NOT NULL DEFAULT '',
        avatar_version INTEGER NOT NULL DEFAULT 0,
        self_signature TEXT NOT NULL DEFAULT '', friend_remark TEXT NOT NULL DEFAULT '',
        gender INTEGER, birthday INTEGER, updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, user_id))''');
    });
    await oldProfiles.insert('user_profiles', {
      'owner_user_id': owner,
      'user_id': peer,
      'nickname': 'Public Nick',
    });
    await oldProfiles.close();

    DisplayNameStore.instance.setC2C(peer, 'Saved Remark', notify: false);
    await profiles.read(peer);
    await FriendSyncService.instance
        .warmupC2cDisplayNamesFromLocalStore(friendUserIds: [peer]);
    expect(FriendDisplayName.resolveC2C(userId: peer), 'Saved Remark');
    expect(profiles.isFriendRemarkConfirmed(peer), isFalse);
    final rows = {
      for (final row in await friends.readAll()) row.friendUserId: row
    };
    expect(rows[peer]?.remarkKnown, isFalse);
    expect(rows['fullrecord']?.remark, 'Saved Remark');
    expect(rows['fullrecord']?.remarkKnown, isTrue);
    expect(rows['clearedrecord']?.remarkKnown, isTrue);

    await friends.updateRemark(
        ownerUserId: owner, friendUserId: peer, remark: '');
    await profiles.saveFriendRecord(
        (await friends.readByIds(friendUserIds: [peer])).single);
    await profiles.clearSession();
    await profileStore.closeIfOpen();
    await profiles.read(peer);
    expect(profiles.isFriendRemarkConfirmed(peer), isTrue);
    expect(FriendDisplayName.resolveC2C(userId: peer), 'Public Nick');
  });

  test('importing the legacy friend database keeps relation shells unknown',
      () async {
    await createOldFriends('friend_local_v1.db');
    final rows = {
      for (final row in await friends.readAll()) row.friendUserId: row
    };
    expect(rows[peer]?.remarkKnown, isFalse);
    expect(rows['fullrecord']?.remarkKnown, isTrue);
    expect(rows['fullrecord']?.remark, 'Saved Remark');
    expect(rows['clearedrecord']?.remarkKnown, isTrue);
  });
}
