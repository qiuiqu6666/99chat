import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const owner = 'owner_contacts_v2';
  const peer = 'u_contacts_v2';

  late List<({String cursor, String? revision})> snapshotCalls;
  late List<({String afterRevision, String cursor})> changesCalls;
  late List<SyncSnapshotPage> snapshotPages;
  late List<SyncChangesPage> changesPages;
  late int changesThrowAt;
  late ContactsProtocolSyncService service;

  RestoreWorkPacer pacer() => RestoreWorkPacer(
        isScrolling: () => false,
        isForeground: () => true,
        canStartBackgroundWork: () => true,
        hasOpenChat: () => false,
        delay: (_) async {},
      );

  setUp(() async {
    snapshotCalls = <({String cursor, String? revision})>[];
    changesCalls = <({String afterRevision, String cursor})>[];
    snapshotPages = <SyncSnapshotPage>[];
    changesPages = <SyncChangesPage>[];
    changesThrowAt = -1;
    FriendSyncService.instance.debugOwnerUserId = owner;
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
    await FriendLocalStore.instance.clearForOwner(owner);
    await FriendLocalStore.instance.clearSyncJob(ownerUserId: owner);
    await FriendLocalStore.instance.clearProtocolEvents(ownerUserId: owner);
    await FriendLocalStore.instance.clearProtocolStaging(ownerUserId: owner);
    await UserProfileLocalStore.instance.clearForOwner(owner);
    service = ContactsProtocolSyncService.forTest(
      fetchSnapshot: ({
        required String domain,
        String cursor = '',
        String? snapshotRevision,
        int limit = 200,
      }) async {
        snapshotCalls.add((cursor: cursor, revision: snapshotRevision));
        if (snapshotPages.isEmpty) {
          throw StateError('no snapshot pages');
        }
        return snapshotPages.removeAt(0);
      },
      fetchChanges: ({
        required String domain,
        String afterRevision = '',
        String cursor = '',
        int limit = 200,
      }) async {
        changesCalls.add((afterRevision: afterRevision, cursor: cursor));
        if (changesThrowAt == changesCalls.length) {
          throw const SyncProtocolException('SNAPSHOT_REQUIRED');
        }
        if (changesPages.isEmpty) {
          return const SyncChangesPage(
            snapshotRevision: 'R1',
            toRevision: 'R1',
            opaqueCursor: '',
            hasMore: false,
            events: <SyncChangeEvent>[],
          );
        }
        return changesPages.removeAt(0);
      },
      pacer: pacer(),
      captureIdentity: () => SessionIdentity(
        ownerUserId: owner,
        generation: SessionIdentityService.instance.generation,
      ),
    );
  });

  tearDown(() {
    FriendSyncService.instance.debugOwnerUserId = null;
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
  });

  SyncProtocolItem item({
    required String id,
    required int version,
    String? remark,
    String nickname = 'n',
  }) {
    return SyncProtocolItem(
      id: id,
      itemVersion: version,
      updatedAt: 1,
      data: <String, dynamic>{
        if (remark != null) 'remark': remark,
        'friendNickname': nickname,
        'friendAvatarUrl': '',
      },
    );
  }

  SyncChangeEvent event({
    required String eventId,
    required int version,
    String? remark,
    String? nickname,
    bool includeRemark = true,
  }) {
    return SyncChangeEvent.fromJson(<String, dynamic>{
      'eventId': eventId,
      'peerUserId': peer,
      'itemVersion': version,
      'operation': 'upsert',
      if (includeRemark) 'remark': remark,
      if (nickname != null) 'nickname': nickname,
    });
  }

  test('no watermark runs snapshot then changes with empty first cursor',
      () async {
    snapshotPages.add(
      SyncSnapshotPage(
        snapshotRevision: 'R1',
        opaqueCursor: 'snap-1',
        hasMore: true,
        items: [item(id: peer, version: 1, remark: 'A')],
      ),
    );
    snapshotPages.add(
      const SyncSnapshotPage(
        snapshotRevision: 'R1',
        opaqueCursor: '',
        hasMore: false,
        items: [],
      ),
    );
    changesPages.add(
      const SyncChangesPage(
        snapshotRevision: 'R1',
        toRevision: 'R2',
        opaqueCursor: '',
        hasMore: false,
        events: <SyncChangeEvent>[],
      ),
    );

    await service.sync(reason: 'test');

    expect(snapshotCalls.map((call) => call.cursor), ['', 'snap-1']);
    expect(changesCalls, isNotEmpty);
    expect(changesCalls.first.afterRevision, 'R1');
    expect(changesCalls.first.cursor, '');
    final job = await FriendLocalStore.instance.readSyncJob(ownerUserId: owner);
    expect(job!['snapshot_revision'], 'R2');
    expect(job['next_cursor'], '');
    expect(job['state'], 'completed');
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'A');
  });

  test('TCP A@11 then v2 A@12 advances version without republishing', () async {
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: owner,
      records: [
        MeFriendRecord(
          friendUserId: peer,
          remark: 'A',
          remarkKnown: true,
          friendNickname: 'n',
          friendAvatarUrl: '',
          itemVersion: 11,
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
    await FriendLocalStore.instance.saveSyncJob(
      ownerUserId: owner,
      snapshotRevision: 'R1',
      nextCursor: '',
      hasMore: false,
      persistedCount: 1,
      state: 'completed',
    );
    changesPages.add(
      SyncChangesPage(
        snapshotRevision: 'R1',
        toRevision: 'R2',
        opaqueCursor: '',
        hasMore: false,
        events: [event(eventId: 'e12', version: 12, remark: 'A')],
      ),
    );

    await service.sync(reason: 'test');

    expect(snapshotCalls, isEmpty);
    expect(changesCalls.single.cursor, '');
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'A');
    expect(rows.single.itemVersion, 12);
    expect(FriendSyncService.instance.debugRemarkDisplayPublishCount, 0);
  });

  test('known null remark publishes a clear', () async {
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: owner,
      records: [
        MeFriendRecord(
          friendUserId: peer,
          remark: 'A',
          remarkKnown: true,
          friendNickname: 'n',
          friendAvatarUrl: '',
          itemVersion: 12,
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
    await FriendLocalStore.instance.saveSyncJob(
      ownerUserId: owner,
      snapshotRevision: 'R1',
      nextCursor: '',
      hasMore: false,
      persistedCount: 1,
      state: 'completed',
    );
    changesPages.add(
      SyncChangesPage(
        snapshotRevision: 'R1',
        toRevision: 'R2',
        opaqueCursor: '',
        hasMore: false,
        events: [event(eventId: 'e13', version: 13, remark: null)],
      ),
    );

    await service.sync(reason: 'test');

    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, '');
    expect(rows.single.remarkKnown, isTrue);
    expect(rows.single.itemVersion, 13);
    expect(FriendSyncService.instance.debugRemarkDisplayPublishCount, 1);
  });

  test('duplicate eventId does not republish', () async {
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: owner,
      records: [
        MeFriendRecord(
          friendUserId: peer,
          remark: 'old',
          remarkKnown: true,
          friendNickname: 'n',
          friendAvatarUrl: '',
          itemVersion: 1,
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
    await FriendLocalStore.instance.saveSyncJob(
      ownerUserId: owner,
      snapshotRevision: 'R1',
      nextCursor: '',
      hasMore: false,
      persistedCount: 1,
      state: 'completed',
    );
    final first = event(eventId: 'same', version: 2, remark: 'new');
    changesPages.add(
      SyncChangesPage(
        snapshotRevision: 'R1',
        toRevision: 'R2',
        opaqueCursor: '',
        hasMore: false,
        events: [first],
      ),
    );
    await service.sync(reason: 'test');
    expect(FriendSyncService.instance.debugRemarkDisplayPublishCount, 1);

    await FriendLocalStore.instance.saveSyncJob(
      ownerUserId: owner,
      snapshotRevision: 'R2',
      nextCursor: '',
      hasMore: false,
      persistedCount: 1,
      state: 'completed',
    );
    changesPages.add(
      SyncChangesPage(
        snapshotRevision: 'R2',
        toRevision: 'R3',
        opaqueCursor: '',
        hasMore: false,
        events: [first],
      ),
    );
    await service.sync(reason: 'test');
    expect(FriendSyncService.instance.debugRemarkDisplayPublishCount, 1);
    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'new');
  });

  test('410 clears watermarks but keeps friends and resnapshots once', () async {
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: owner,
      records: [
        MeFriendRecord(
          friendUserId: peer,
          remark: 'A',
          remarkKnown: true,
          friendNickname: 'n',
          friendAvatarUrl: '',
          itemVersion: 4,
          addedAt: 1,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
    await FriendLocalStore.instance.saveSyncJob(
      ownerUserId: owner,
      snapshotRevision: 'OLD',
      nextCursor: '',
      hasMore: false,
      persistedCount: 1,
      state: 'completed',
    );
    changesThrowAt = 1;
    snapshotPages.add(
      SyncSnapshotPage(
        snapshotRevision: 'NEW',
        opaqueCursor: '',
        hasMore: false,
        items: [item(id: peer, version: 4, remark: 'A')],
      ),
    );
    changesPages.add(
      const SyncChangesPage(
        snapshotRevision: 'NEW',
        toRevision: 'NEW',
        opaqueCursor: '',
        hasMore: false,
        events: <SyncChangeEvent>[],
      ),
    );

    await service.sync(reason: 'test');

    final rows = await FriendLocalStore.instance.readByIds(
      ownerUserId: owner,
      friendUserIds: <String>[peer],
    );
    expect(rows.single.remark, 'A');
    final job = await FriendLocalStore.instance.readSyncJob(ownerUserId: owner);
    expect(job!['snapshot_revision'], 'NEW');
    expect(snapshotCalls, isNotEmpty);
  });

  test('logout clearSession keeps completed revision', () async {
    snapshotPages.add(
      SyncSnapshotPage(
        snapshotRevision: 'R1',
        opaqueCursor: '',
        hasMore: false,
        items: [item(id: peer, version: 1, remark: 'A')],
      ),
    );
    changesPages.add(
      const SyncChangesPage(
        snapshotRevision: 'R1',
        toRevision: 'R2',
        opaqueCursor: '',
        hasMore: false,
        events: <SyncChangeEvent>[],
      ),
    );
    await service.sync(reason: 'first');
    expect(snapshotCalls, hasLength(1));
    await service.clearSession(ownerUserId: owner);
    changesPages.add(
      const SyncChangesPage(
        snapshotRevision: 'R2',
        toRevision: 'R3',
        opaqueCursor: '',
        hasMore: false,
        events: <SyncChangeEvent>[],
      ),
    );
    await service.sync(reason: 'relogin');
    expect(snapshotCalls, hasLength(1));
    expect(changesCalls, hasLength(2));
    final job = await FriendLocalStore.instance.readSyncJob(ownerUserId: owner);
    expect(job!['snapshot_revision'], 'R3');
  });
}
