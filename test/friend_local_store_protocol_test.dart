import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_mapper.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const owner = 'owner_protocol_a';
  const peer = 'u_protocol';

  setUp(() async {
    FriendSyncService.instance.debugOwnerUserId = owner;
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
    await FriendLocalStore.instance.clearForOwner(owner);
    await FriendLocalStore.instance.clearSyncJob(ownerUserId: owner);
    await FriendLocalStore.instance.clearProtocolEvents(ownerUserId: owner);
    await FriendLocalStore.instance.clearProtocolStaging(ownerUserId: owner);
    await UserProfileLocalStore.instance.clearForOwner(owner);
  });

  tearDown(() {
    FriendSyncService.instance.debugOwnerUserId = null;
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
  });

  Future<void> seed({
    required String remark,
    required int version,
    String nickname = '小明',
  }) async {
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: owner,
      records: [
        MeFriendRecord(
          friendUserId: peer,
          remark: remark,
          remarkKnown: true,
          friendNickname: nickname,
          friendAvatarUrl: 'https://example.com/a.png',
          itemVersion: version,
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
  }

  test('partial upsert without remark keeps SQLite remark', () async {
    await seed(remark: '老婆', version: 10);
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'ev_nick',
      'peerUserId': peer,
      'itemVersion': 11,
      'operation': 'upsert',
      'nickname': '新昵称',
    });
    final record = meFriendRecordFromSyncChangeEvent(event);
    expect(record!.remarkKnown, isFalse);
    final applied = await FriendLocalStore.instance.applyProtocolChange(
      ownerUserId: owner,
      event: event,
      record: record,
    );
    expect(applied, isTrue);
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, '老婆');
    expect(rows.single.remarkKnown, isTrue);
    expect(rows.single.itemVersion, 11);
    expect(rows.single.friendNickname, '新昵称');
  });

  test('TCP A@11 then v2 A@12 advances version without clearing remark',
      () async {
    await seed(remark: 'A', version: 11);
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'ev_same',
      'peerUserId': peer,
      'itemVersion': 12,
      'operation': 'upsert',
      'remark': 'A',
    });
    final record = meFriendRecordFromSyncChangeEvent(event);
    final applied = await FriendLocalStore.instance.applyProtocolChange(
      ownerUserId: owner,
      event: event,
      record: record,
    );
    expect(applied, isTrue);
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'A');
    expect(rows.single.itemVersion, 12);
  });

  test('known null remark clears SQLite remark', () async {
    await seed(remark: 'A', version: 12);
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'ev_clear',
      'peerUserId': peer,
      'itemVersion': 13,
      'operation': 'upsert',
      'remark': null,
    });
    final record = meFriendRecordFromSyncChangeEvent(event);
    expect(record!.remarkKnown, isTrue);
    expect(record.remark, '');
    final applied = await FriendLocalStore.instance.applyProtocolChange(
      ownerUserId: owner,
      event: event,
      record: record,
    );
    expect(applied, isTrue);
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, '');
    expect(rows.single.remarkKnown, isTrue);
    expect(rows.single.itemVersion, 13);
  });

  test('duplicate eventId is rejected', () async {
    await seed(remark: 'A', version: 1);
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'ev_dup',
      'peerUserId': peer,
      'itemVersion': 2,
      'operation': 'upsert',
      'remark': 'B',
    });
    final record = meFriendRecordFromSyncChangeEvent(event);
    expect(
      await FriendLocalStore.instance.applyProtocolChange(
        ownerUserId: owner,
        event: event,
        record: record,
      ),
      isTrue,
    );
    expect(
      await FriendLocalStore.instance.applyProtocolChange(
        ownerUserId: owner,
        event: event,
        record: record,
      ),
      isFalse,
    );
  });

  test('lower itemVersion is rejected', () async {
    await seed(remark: 'A', version: 10);
    final event = SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': 'ev_old',
      'peerUserId': peer,
      'itemVersion': 9,
      'operation': 'upsert',
      'remark': 'Z',
    });
    final applied = await FriendLocalStore.instance.applyProtocolChange(
      ownerUserId: owner,
      event: event,
      record: meFriendRecordFromSyncChangeEvent(event),
    );
    expect(applied, isFalse);
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'A');
    expect(rows.single.itemVersion, 10);
  });
  test('delete and re-add reject reordered events and preserve tombstones',
      () async {
    await seed(remark: 'initial', version: 17);
    Future<bool> apply(String eventId, int version, bool deleted) {
      final event = SyncChangeEvent.fromJson({
        'eventId': eventId,
        'id': peer,
        'itemVersion': version,
        'operation': deleted ? 'delete' : 'upsert',
        'deleted': deleted,
        'friendNickname': 'confirmed',
        'remark': 'v$version',
      });
      return FriendLocalStore.instance.applyProtocolChange(
          ownerUserId: owner,
          event: event,
          record: deleted ? null : meFriendRecordFromSyncChangeEvent(event));
    }

    expect(await apply('delete-18', 18, true), isTrue);
    expect(await apply('late-add-17', 17, false), isFalse);
    expect(
        await FriendLocalStore.instance.readAll(ownerUserId: owner), isEmpty);
    expect(await apply('re-add-19', 19, false), isTrue);
    expect(await apply('late-delete-18', 18, true), isFalse);
    expect(
        (await FriendLocalStore.instance.readAll(ownerUserId: owner))
            .single
            .itemVersion,
        19);
  });
}
