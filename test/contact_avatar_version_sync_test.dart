import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/contacts_protocol_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/restore_work_pacer.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = 'avatar_version_sync';
  const peer = 'avatar_peer';
  const url = 'https://avatar.test/unchanged.png';
  final store = FriendLocalStore.instance;
  final profiles = UserProfileLocalService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FriendSyncService.instance.debugOwnerUserId = owner;
    ImSdkRelationshipDirectory.instance.reset();
    await profiles.clearSession();
    await store.clearForOwner(owner);
    await store.clearProtocolEvents(ownerUserId: owner);
    await store.clearProtocolStaging(ownerUserId: owner);
    final old = MeFriendRecord(
      friendUserId: peer,
      remark: '',
      friendNickname: 'Peer',
      friendAvatarUrl: url,
      friendAvatarVersion: 1,
      itemVersion: 1,
      addedAt: 0,
      peerDeletedMe: false,
      canMessage: true,
    );
    await store.replaceAll(ownerUserId: owner, records: [old]);
    await profiles.saveFriendRecord(old);
    await store.saveSyncJob(
        ownerUserId: owner,
        snapshotRevision: 'R1',
        nextCursor: '',
        hasMore: false,
        persistedCount: 1,
        state: 'completed');
  });

  tearDown(() async {
    FriendSyncService.instance.debugOwnerUserId = null;
    await profiles.clearSession();
  });

  for (final snapshot in [false, true]) {
    test(
        'same URL avatar version reaches profile via ${snapshot ? 'snapshot' : 'delta'}',
        () async {
      final data = <String, dynamic>{
        'friendNickname': 'Peer',
        'friendAvatarUrl': url,
        'friendAvatarVersion': 2,
        'remark': '',
      };
      if (snapshot) await store.clearSyncJob(ownerUserId: owner);
      final service = ContactsProtocolSyncService.forTest(
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
                snapshotRevision: 'R2',
                opaqueCursor: '',
                hasMore: false,
                items: [
              SyncProtocolItem(
                  id: peer, itemVersion: 2, updatedAt: 1, data: data)
            ]),
        fetchChanges: (
                {required String domain,
                String afterRevision = '',
                String cursor = '',
                int limit = 200}) async =>
            SyncChangesPage(
                snapshotRevision: 'R1',
                toRevision: 'R2',
                opaqueCursor: '',
                hasMore: false,
                events: snapshot
                    ? []
                    : [
                        SyncChangeEvent.fromJson({
                          ...data,
                          'eventId': 'avatar-v2',
                          'peerUserId': peer,
                          'itemVersion': 2,
                          'operation': 'upsert',
                        })
                      ]),
      );
      try {
        await service.sync(reason: 'avatar_version_regression');
        final rows = await store.readAll(ownerUserId: owner);
        expect(rows.single.friendAvatarVersion, 2);
        expect(profiles.readCached(peer)?.avatarUrl, url);
        expect(profiles.readCached(peer)?.avatarVersion, 2);
      } finally {
        await service.clearSession();
      }
    });
  }
}
