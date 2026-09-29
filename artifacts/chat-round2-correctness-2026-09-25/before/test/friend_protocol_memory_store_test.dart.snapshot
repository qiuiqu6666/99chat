import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';

void main() {
  test(
      'memory snapshots stage every page and replace absent contacts on publication',
      () async {
    final store = FriendLocalStore.memoryForTest();
    const owner = 'memory_owner';
    for (final id in ['peer1', 'peer2']) {
      await store.stageProtocolItems(
          ownerUserId: owner,
          snapshotRevision: '10',
          items: [
            SyncProtocolItem(
                id: id,
                itemVersion: 1,
                updatedAt: 1,
                data: {'friendNickname': id}),
          ]);
    }
    expect(await store.readAll(ownerUserId: owner), isEmpty);
    final staged = await store.readProtocolStaging(
        ownerUserId: owner, snapshotRevision: '10');
    expect(staged, hasLength(2));
    await store.publishProtocolSnapshot(
        ownerUserId: owner,
        snapshotRevision: '10',
        records: staged,
        replaceAbsent: true);
    await store.saveSyncJob(
        ownerUserId: owner,
        snapshotRevision: '10',
        nextCursor: '',
        hasMore: false,
        persistedCount: 2,
        state: 'completed');
    expect((await store.readSyncJob(ownerUserId: owner))!['snapshot_revision'],
        '10');
    expect(await store.readAll(ownerUserId: owner), hasLength(2));
    await store.publishProtocolSnapshot(
        ownerUserId: owner,
        snapshotRevision: '11',
        records: [],
        replaceAbsent: true);
    expect(await store.readAll(ownerUserId: owner), isEmpty);
    expect(
        await store.readProtocolStaging(
            ownerUserId: owner, snapshotRevision: '10'),
        isEmpty);
  });
}
