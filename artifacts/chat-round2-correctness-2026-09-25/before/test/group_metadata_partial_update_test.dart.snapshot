import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';

MeGroupRecord fullRecord() => MeGroupRecord.fromJson({
      'groupId': '@TGS#_mcPartial123',
      'groupType': 'Community',
      'groupName': 'Confirmed name',
      'avatarUrl': 'https://example.com/avatar.png',
      'memberCount': 1418,
      'notice': 'Notice',
      'myRole': 300,
      'isAllMuted': true,
      'gameEnabled': true,
      'myNameCard': 'Card',
      'joinedAt': 1000,
      'updatedAt': 2000,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = GroupLocalStore.instance;
  const owner = 'partial-metadata-tests';
  final id = fullRecord().groupId;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await store.clearForOwner(owner);
    await store.upsert(ownerUserId: owner, record: fullRecord());
  });
  tearDown(() => store.clearForOwner(owner));

  Future<void> expectPreserved() async {
    final row = (await store.read(ownerUserId: owner, groupId: id))!;
    expect(row.groupName, 'Confirmed name');
    expect(row.avatarUrl, 'https://example.com/avatar.png');
    expect(row.memberCount, 1418);
    expect(row.notice, 'Notice');
    expect(row.isAllMuted, isTrue);
    expect(row.gameEnabled, isTrue);
    expect(store.readCached(ownerUserId: owner, groupId: id)?.groupName,
        'Confirmed name');
  }

  for (final mode in ['single', 'page', 'snapshot']) {
    test('$mode ID-only success preserves confirmed metadata in disk and UI',
        () async {
      final partial =
          MeGroupRecord.fromJson({'groupId': id, 'updatedAt': 2001});
      if (mode == 'single') {
        await store.upsert(ownerUserId: owner, record: partial);
      } else if (mode == 'page') {
        await store.upsertAll(ownerUserId: owner, records: [partial]);
      } else {
        await store.replaceAll(ownerUserId: owner, records: [partial]);
      }
      await expectPreserved();
    });
  }

  test('explicit empty, zero and false remain authoritative updates', () async {
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': id,
          'notice': '',
          'avatarUrl': '',
          'memberCount': 0,
          'isAllMuted': false,
          'gameEnabled': false,
          'updatedAt': 2001,
        }));
    final row = (await store.read(ownerUserId: owner, groupId: id))!;
    expect(row.groupName, 'Confirmed name');
    expect(row.notice, isEmpty);
    expect(row.avatarUrl, isEmpty);
    expect(row.memberCount, 0);
    expect(row.isAllMuted, isFalse);
    expect(row.gameEnabled, isFalse);
  });

  test(
      'trusted detail repairs an identity-only old shell without losing notice',
      () async {
    final shell = MeGroupRecord.fromJson({
      'groupId': id,
      'groupType': '',
      'groupName': '',
      'displayAlias': id,
      'notice': 'keep this notice',
      'noticeUpdatedAt': 1710000000000,
      'memberCount': 0,
      'updatedAt': 3000000,
    });
    await store.clearForOwner(owner);
    await store.upsert(ownerUserId: owner, record: shell);

    final detail = MeGroupRecord.fromJson({
      'groupId': id,
      'groupType': 'Community',
      'groupName': 'Recovered name',
      'memberCount': 1403,
      // Older than the bad shell: the narrow repair must still accept it.
      'updatedAt': 2000000,
    });
    expect(
      GroupLocalStore.isIdentityOnlyMetadataRepair(
        existing: shell,
        incoming: detail,
      ),
      isTrue,
    );
    // The repair is opt-in: ordinary callers retain the timestamp fence.
    expect(await store.upsert(ownerUserId: owner, record: detail), isFalse);
    expect(
      await store.upsert(
        ownerUserId: owner,
        record: detail,
        allowIdentityOnlyRepair: true,
      ),
      isTrue,
    );

    final row = (await store.read(ownerUserId: owner, groupId: id))!;
    expect(row.groupType, 'Community');
    expect(row.groupName, 'Recovered name');
    expect(row.memberCount, 1403);
    expect(row.notice, 'keep this notice');
    expect(row.noticeUpdatedAt, 1710000000000);
    expect(row.updatedAt, shell.updatedAt);
  });

  test('partial copyWith supplies its explicit patch without erasing others',
      () async {
    final partial = MeGroupRecord.fromJson({'groupId': id})
        .copyWith(myNameCard: 'New card', updatedAt: 2001000);
    await store.upsert(ownerUserId: owner, record: partial);
    await expectPreserved();
    expect((await store.read(ownerUserId: owner, groupId: id))!.myNameCard,
        'New card');
  });

  test('optimistic shell cannot replace an existing equivalent group',
      () async {
    final changed = await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord(
            groupId: '@TGS#_mcPartial123',
            groupType: 'Work',
            groupName: '',
            displayAlias: '',
            avatarUrl: '',
            notice: '',
            memberCount: 0,
            myRole: 200,
            myNameCard: '',
            joinedAt: 3000000,
            updatedAt: 3000000),
        onlyIfAbsent: true);
    expect(changed, isFalse);
    await expectPreserved();
  });

  test('shell rollback cannot delete a subsequently confirmed record',
      () async {
    final shell = fullRecord();
    await store.upsert(
        ownerUserId: owner,
        record:
            shell.copyWith(groupName: 'Confirmed later', updatedAt: 3000000));
    await store.delete(ownerUserId: owner, groupId: id, onlyIfUnchanged: shell);
    expect((await store.read(ownerUserId: owner, groupId: id))!.groupName,
        'Confirmed later');
    expect(store.readCached(ownerUserId: owner, groupId: id)!.groupName,
        'Confirmed later');
  });

  test('shell rollback removes its unchanged row', () async {
    await store.delete(
        ownerUserId: owner, groupId: id, onlyIfUnchanged: fullRecord());
    expect(await store.read(ownerUserId: owner, groupId: id), isNull);
    expect(store.readCached(ownerUserId: owner, groupId: id), isNull);
  });

  test('old partial response does not override a newer explicit value',
      () async {
    await store.upsert(
        ownerUserId: owner,
        record: MeGroupRecord.fromJson({
          'groupId': id,
          'groupName': 'Old name',
          'updatedAt': 1999,
        }));
    await expectPreserved();
  });
}
