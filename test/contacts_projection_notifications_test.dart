import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'projection_notification_test';
  final store = FriendLocalStore.instance;
  final bus = PeerProfileRefreshBus.instance;
  late ContactsProtocolSyncService service;
  var events = <SyncChangeEvent>[];
  var snapshotRequired = false;
  var snapshotItems = <SyncProtocolItem>[];
  final ids = List.generate(200, (i) => 'peer_$i');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ImSdkRelationshipDirectory.instance.reset();
    bus.clear();
    FriendSyncService.instance.debugOwnerUserId = owner;
    await store.clearForOwner(owner);
    await store.clearProtocolEvents(ownerUserId: owner);
    await store.clearProtocolStaging(ownerUserId: owner);
    await store.replaceAll(ownerUserId: owner, records: [
      for (final id in ids)
        MeFriendRecord(
            friendUserId: id,
            remark: '',
            friendNickname: id,
            friendAvatarUrl: '',
            itemVersion: 1,
            addedAt: 1000,
            peerDeletedMe: false,
            canMessage: true),
    ]);
    await store.saveSyncJob(
        ownerUserId: owner,
        snapshotRevision: 'R1',
        nextCursor: '',
        hasMore: false,
        persistedCount: ids.length,
        state: 'completed');
    events = [];
    snapshotRequired = false;
    snapshotItems = [];
    service = ContactsProtocolSyncService.forTest(
      captureIdentity: () => SessionIdentity(
          ownerUserId: owner,
          generation: SessionIdentityService.instance.generation),
      pacer: RestoreWorkPacer(
          isScrolling: () => false,
          isForeground: () => true,
          canStartBackgroundWork: () => true,
          hasOpenChat: () => false,
          delay: (_) async {}),
      fetchSnapshot: (
              {required String domain,
              String cursor = '',
              String? snapshotRevision,
              int limit = 200}) async =>
          SyncSnapshotPage(
              snapshotRevision: 'R3',
              opaqueCursor: '',
              hasMore: false,
              items: snapshotItems),
      fetchChanges: (
          {required String domain,
          String afterRevision = '',
          String cursor = '',
          int limit = 200}) async {
        if (snapshotRequired) {
          snapshotRequired = false;
          throw const SyncProtocolException('SNAPSHOT_REQUIRED');
        }
        final batch = events;
        events = [];
        return SyncChangesPage(
            snapshotRevision: 'R1',
            toRevision: 'R2',
            opaqueCursor: '',
            hasMore: false,
            events: batch);
      },
    );
    await service.sync(reason: 'initial_projection');
  });
  tearDown(() async {
    await service.clearSession(ownerUserId: owner);
    FriendSyncService.instance.debugOwnerUserId = null;
  });

  test('200 changes emit one profile notification containing all touched IDs',
      () async {
    final previousRevision = bus.revision.value;
    events = [
      for (final id in ids)
        SyncChangeEvent.fromJson({
          'eventId': 'change-$id',
          'peerUserId': id,
          'itemVersion': 2,
          'operation': 'upsert',
          'nickname': 'new-$id',
        })
    ];
    await service.sync(reason: 'one_page');
    expect(bus.revision.value - previousRevision, 1);
    expect(bus.latestChangedUserIds, ids.toSet());
    for (final id in ids) {
      expect(
          ImSdkRelationshipDirectory.instance.friend(id)?.nickname, 'new-$id');
    }
    final after = bus.revision.value;
    await service.sync(reason: 'empty_changes');
    expect(bus.revision.value, after);
  });

  test('authoritative resnapshot excludes unchanged peers and retains removals',
      () async {
    final previousRevision = bus.revision.value;
    snapshotItems = [
      for (final id in ids.skip(1))
        SyncProtocolItem(
          id: id,
          itemVersion: 3,
          updatedAt: 1,
          data: {
            'remark': '',
            'friendNickname': id,
            'friendAvatarUrl': '',
            'addedAt': 1,
            'canMessage': true,
            'peerDeletedMe': false,
          },
        )
    ];
    snapshotRequired = true;
    await service.sync(reason: 'resnapshot');
    expect(ImSdkRelationshipDirectory.instance.friend(ids.first), isNull);
    expect(bus.revision.value - previousRevision, 1);
    expect(bus.latestChangedUserIds, {ids.first});
  });
}
