import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';

FriendRealtimeEvent _remarkUpdatedEvent({
  required String peerUserId,
  required String remark,
}) {
  return FriendRealtimeEvent(
    event: 'friend_list_changed',
    fromUserId: '',
    toUserId: '',
    action: 'remark_updated',
    peerUserId: peerUserId,
    remark: remark,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const owner = 'remark_fallback_owner';
  const peer = 'peer_no_record';

  // 测试进程无登录态，MeFriendApi.cachedByUserId 的默认 owner 为空；
  // 断言统一按显式 owner 读 FriendLocalStore，与写入路径一致。
  Future<MeFriendRecord?> readByOwner(String friendUserId) async {
    final matches = await FriendLocalStore.instance.readByIds(
      friendUserIds: <String>[friendUserId],
      ownerUserId: owner,
    );
    return matches.isEmpty ? null : matches.first;
  }

  setUp(() {
    FriendSyncService.instance.debugProtocolSync = (_) async {};
    DisplayNameStore.instance.clear(notify: false);
    PeerProfileRefreshBus.instance.clear();
    UserProfileLocalService.instance.clearSession();
    FriendSyncService.instance.debugOwnerUserId = owner;
  });

  tearDown(() async {
    FriendSyncService.instance.debugProtocolSync = null;
    FriendSyncService.instance.debugOwnerUserId = null;
    DisplayNameStore.instance.clear(notify: false);
    PeerProfileRefreshBus.instance.clear();
    UserProfileLocalService.instance.clearSession();
    await FriendLocalStore.instance.delete(
      ownerUserId: owner,
      friendUserId: peer,
      force: true,
    );
    await FriendLocalStore.instance.delete(
      ownerUserId: owner,
      friendUserId: 'peer_existing',
      force: true,
    );
  });

  group('remark hints cannot invent relationship records', () {
    test('remark save requests confirmation instead of creating a shell',
        () async {
      final before = await readByOwner(peer);
      expect(before, isNull);

      await FriendSyncService.instance.applyOptimisticRemark(
        friendUserId: peer,
        remark: '新备注',
      );

      final after = await readByOwner(peer);
      expect(after, isNull);
      expect(DisplayNameStore.instance.c2c(peer), isNull);
    });

    test('delayed remark event cannot resurrect a missing friend', () async {
      final changed = await FriendSyncService.instance.applyListChanged(
        _remarkUpdatedEvent(peerUserId: peer, remark: '事件备注'),
      );

      expect(changed, isTrue);
      final after = await readByOwner(peer);
      expect(after, isNull);
      expect(DisplayNameStore.instance.c2c(peer), isNull);
    });

    test('existing relationship waits for versioned confirmation', () async {
      const existingPeer = 'peer_existing';
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final seed = MeFriendRecord(
        friendUserId: existingPeer,
        remark: '旧备注',
        friendNickname: '昵称',
        friendAvatarUrl: '',
        addedAt: now,
        peerDeletedMe: false,
        canMessage: true,
      );
      await FriendLocalStore.instance.upsert(
        ownerUserId: owner,
        record: seed,
      );
      final seeded = await readByOwner(existingPeer);
      expect(seeded!.addedAt, now);

      await FriendSyncService.instance.applyOptimisticRemark(
        friendUserId: existingPeer,
        remark: '改名备注',
      );

      final after = await readByOwner(existingPeer);
      expect(after, isNotNull);
      expect(after!.remark, '旧备注');
      // Unconfirmed input cannot overwrite the persisted relationship.
      expect(after.addedAt, now);
      expect(after.friendNickname, '昵称');
    });
  });
}
