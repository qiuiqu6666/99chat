import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_directory.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';
import 'package:tencent_cloud_chat_demo/src/services/peer_profile_refresh_bus.dart';
import 'package:tencent_cloud_chat_demo/src/services/user_profile_local/user_profile_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const ownerUserId = 'owner_a';
  const peerUserId = 'b123456';

  setUp(() async {
    FriendSyncService.instance.debugOwnerUserId = ownerUserId;
    FriendSyncService.instance.debugSkipBecameFriendsSideEffects = true;
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
    PeerProfileRefreshBus.instance.clear();
    await FriendLocalStore.instance.clearForOwner(ownerUserId);
    await UserProfileLocalStore.instance.clearForOwner(ownerUserId);
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: ownerUserId,
      records: [
        MeFriendRecord(
          friendUserId: peerUserId,
          remark: '旧备注',
          friendNickname: '小明',
          friendAvatarUrl: 'https://example.com/a.png',
          addedAt: 1718452800000,
          peerDeletedMe: false,
          canMessage: true,
        ),
      ],
    );
  });

  tearDown(() {
    FriendSyncService.instance.debugOwnerUserId = null;
    FriendSyncService.instance.debugSkipBecameFriendsSideEffects = false;
  });

  test('FriendRealtimeEvent parses presence_changed payload', () {
    final event = FriendRealtimeEvent.fromJson(<String, dynamic>{
      'type': 'event',
      'event': 'presence_changed',
      'peerUserId': peerUserId,
      'lastActiveAt': 1718592000000,
      'lastActiveVisibility': 'hidden',
      'online': true,
      'ts': 1718592000123,
    });

    expect(event.event, 'presence_changed');
    expect(event.peerUserId, peerUserId);
    expect(event.lastActiveAt, 1718592000000);
    expect(event.lastActiveVisibility, 'hidden');
    expect(event.online, isTrue);
  });

  test('replaceAll atomically replaces the owner friend snapshot', () async {
    const nextPeerUserId = 'c654321';
    await FriendLocalStore.instance.replaceAll(
      ownerUserId: ownerUserId,
      records: [
        MeFriendRecord(
          friendUserId: nextPeerUserId,
          remark: '新备注',
          friendNickname: '新好友',
          friendAvatarUrl: 'https://example.com/b.png',
          addedAt: 1718592000000,
          peerDeletedMe: true,
          canMessage: false,
          inMyFriendList: false,
          isFriend: false,
        ),
      ],
    );

    final friends = await FriendLocalStore.instance.readAll(
      ownerUserId: ownerUserId,
    );
    expect(friends, hasLength(1));
    expect(friends.single.friendUserId, nextPeerUserId);
    expect(friends.single.remark, '新备注');
    expect(friends.single.friendNickname, '新好友');
    expect(friends.single.friendAvatarUrl, 'https://example.com/b.png');
    expect(friends.single.addedAt, 1718592000000);
    expect(friends.single.peerDeletedMe, isTrue);
    expect(friends.single.canMessage, isFalse);
    expect(friends.single.inMyFriendList, isFalse);
    expect(friends.single.isFriend, isFalse);
  });

  test('FriendRealtimeEvent parses remark_updated payload', () {
    final event = FriendRealtimeEvent.fromJson(<String, dynamic>{
      'type': 'event',
      'event': 'friend_list_changed',
      'action': 'remark_updated',
      'peerUserId': peerUserId,
      'peerNickname': '小明',
      'peerAvatarUrl': 'https://example.com/a.png',
      'remark': '备注名',
      'inMyFriendList': true,
      'isFriend': true,
      'peerDeletedMe': false,
      'canMessage': true,
      'ts': 1718452800000,
    });

    expect(event.event, 'friend_list_changed');
    expect(event.action, 'remark_updated');
    expect(event.peerUserId, peerUserId);
    expect(event.remark, '备注名');
  });

  test('applyListChanged remark_updated updates local friend remark', () async {
    final changed = await FriendSyncService.instance.applyListChanged(
      FriendRealtimeEvent.fromJson(<String, dynamic>{
        'type': 'event',
        'event': 'friend_list_changed',
        'action': 'remark_updated',
        'peerUserId': peerUserId,
        'remark': '备注名',
      }),
    );

    expect(changed, isTrue);
    final friends = await FriendLocalStore.instance.readAll(
      ownerUserId: ownerUserId,
    );
    expect(friends.single.remark, '备注名');
    expect(friends.single.friendNickname, '小明');
    expect(PeerProfileRefreshBus.instance.matches(peerUserId), isTrue);
  });

  test(
    'applyListChanged remark_updated clears remark when payload is empty',
    () async {
      final changed = await FriendSyncService.instance.applyListChanged(
        FriendRealtimeEvent.fromJson(<String, dynamic>{
          'type': 'event',
          'event': 'friend_list_changed',
          'action': 'remark_updated',
          'peerUserId': peerUserId,
          'remark': '',
        }),
      );

      expect(changed, isTrue);
      final friends = await FriendLocalStore.instance.readAll(
        ownerUserId: ownerUserId,
      );
      expect(friends.single.remark, '');
    },
  );

  test('applyListChanged remark_updated skips publish when remark unchanged',
      () async {
    await FriendLocalStore.instance.updateRemark(
      ownerUserId: ownerUserId,
      friendUserId: peerUserId,
      remark: '已有备注',
    );
    FriendSyncService.instance.debugRemarkDisplayPublishCount = 0;
    final changed = await FriendSyncService.instance.applyListChanged(
      FriendRealtimeEvent.fromJson(<String, dynamic>{
        'type': 'event',
        'event': 'friend_list_changed',
        'action': 'remark_updated',
        'peerUserId': peerUserId,
        'remark': '已有备注',
      }),
    );
    expect(changed, isTrue);
    expect(FriendSyncService.instance.debugRemarkDisplayPublishCount, 0);
  });

  test('onBecameFriends upserts peer into local store', () async {
    const newPeer = 'new_friend_99';
    await FriendSyncService.instance.onBecameFriends(
      peerUserId: newPeer,
      nickname: '新同学',
      avatarUrl: 'https://example.com/new.png',
      reason: 'test_became_friends',
    );

    final friends = await FriendLocalStore.instance.readAll(
      ownerUserId: ownerUserId,
    );
    final match = friends.where((e) => e.friendUserId == newPeer).toList();
    expect(match, hasLength(1));
    expect(match.single.friendNickname, '新同学');
    expect(match.single.friendAvatarUrl, 'https://example.com/new.png');
    expect(match.single.isFriend, isTrue);
    expect(match.single.inMyFriendList, isTrue);
  });

  test('confirmed friend add updates the live contact directory immediately',
      () async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: const [],
    );

    await FriendSyncService.instance.onBecameFriends(
      peerUserId: 'instant_friend',
      nickname: '新好友',
      reason: 'test_immediate_contact',
    );

    expect(directory.friend('instant_friend')?.displayName, '新好友');
  });

  test('confirmed friend delete removes the live contact immediately',
      () async {
    final directory = ImSdkRelationshipDirectory.instance;
    directory.reset();
    addTearDown(directory.reset);
    directory.applyFriendSnapshot(
      captureId: directory.beginFriendCapture(),
      entries: [
        RelationshipFriendEntry(
          userId: peerUserId,
          displayName: '小明',
          faceUrl: '',
          remark: '',
          sortKey: ImSdkRelationshipDirectory.sortKeyFor(
            id: peerUserId,
            displayName: '小明',
            azTag: 'X',
          ),
        ),
      ],
    );

    await FriendSyncService.instance.applyOptimisticDelete(peerUserId);

    expect(directory.friend(peerUserId), isNull);
  });

  test(
    'onBecameFriends keeps new peer visible when local store already has friends',
    () async {
      const newPeer = 'visible_after_auto';
      final before = await FriendSyncService.instance.loadFriendsForUIKit();
      expect(before.map((e) => e.userID), contains(peerUserId));
      expect(before.map((e) => e.userID), isNot(contains(newPeer)));

      await FriendSyncService.instance.onBecameFriends(
        peerUserId: newPeer,
        nickname: '自动通过',
        avatarUrl: 'https://example.com/auto.png',
        reason: 'friend_auto_accepted',
      );

      final after = await FriendSyncService.instance.loadFriendsForUIKit();
      expect(after.map((e) => e.userID), contains(peerUserId));
      expect(after.map((e) => e.userID), contains(newPeer));
    },
  );

  test(
    'onBecameFriends second call with empty nickname does not wipe existing',
    () async {
      await FriendSyncService.instance.onBecameFriends(
        peerUserId: peerUserId,
        nickname: '',
        avatarUrl: '',
        reason: 'test_idempotent',
      );

      final friends = await FriendLocalStore.instance.readAll(
        ownerUserId: ownerUserId,
      );
      expect(friends.single.friendNickname, '小明');
      expect(friends.single.friendAvatarUrl, 'https://example.com/a.png');
      expect(friends.single.remark, '旧备注');
    },
  );
}
