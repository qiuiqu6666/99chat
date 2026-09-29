import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_search_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const owner = 'search_dir_group_owner';
  final store = GroupLocalStore.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    store.debugOwnerUserIdOverride = owner;
  });

  tearDown(() async {
    await store.clearForOwner(owner);
    store.debugClearOwnerOverride();
  });

  test('directory membership rejects all when snapshot complete with 0 friends',
      () {
    expect(
      keepSearchFriendByDirectoryMembership(
        userId: 'u1',
        containsFriend: (_) => true,
        snapshotComplete: true,
        friendCount: 0,
      ),
      isFalse,
    );
  });

  test('directory membership does not treat incomplete snapshot as 0 friends',
      () {
    expect(
      keepSearchFriendByDirectoryMembership(
        userId: 'u1',
        containsFriend: (id) => id == 'u1',
        snapshotComplete: false,
        friendCount: 0,
      ),
      isTrue,
    );
    expect(
      keepSearchFriendByDirectoryMembership(
        userId: 'u2',
        containsFriend: (id) => id == 'u1',
        snapshotComplete: false,
        friendCount: 0,
      ),
      isFalse,
    );
  });

  test('directory membership keeps only current friends after snapshot', () {
    expect(
      keepSearchFriendByDirectoryMembership(
        userId: 'u1',
        containsFriend: (id) => id == 'u1',
        snapshotComplete: true,
        friendCount: 2,
      ),
      isTrue,
    );
    expect(
      keepSearchFriendByDirectoryMembership(
        userId: 'left',
        containsFriend: (id) => id == 'u1',
        snapshotComplete: true,
        friendCount: 2,
      ),
      isFalse,
    );
  });

  test('friend and group upsert merge by id without wiping earlier hits', () {
    final friends = <String, V2TimFriendInfoResult>{};
    upsertFriendSearchResult(
      friends,
      V2TimFriendInfoResult(
        resultCode: 0,
        resultInfo: '',
        relation: 0,
        friendInfo: V2TimFriendInfo(
          userID: 'u1',
          friendRemark: '本地',
          userProfile: V2TimUserFullInfo(userID: 'u1', nickName: '本地'),
        ),
      ),
    );
    upsertFriendSearchResult(
      friends,
      V2TimFriendInfoResult(
        resultCode: 0,
        resultInfo: '',
        relation: 0,
        friendInfo: V2TimFriendInfo(
          userID: 'u2',
          friendRemark: '补充',
          userProfile: V2TimUserFullInfo(userID: 'u2', nickName: '补充'),
        ),
      ),
    );
    upsertFriendSearchResult(
      friends,
      V2TimFriendInfoResult(
        resultCode: 0,
        resultInfo: '',
        relation: 0,
        friendInfo: V2TimFriendInfo(
          userID: 'u1',
          friendRemark: 'IM更新',
          userProfile: V2TimUserFullInfo(userID: 'u1', nickName: 'IM更新'),
        ),
      ),
    );
    expect(friends.keys, unorderedEquals(<String>['u1', 'u2']));
    expect(friends['u1']?.friendInfo?.friendRemark, 'IM更新');

    final groups = <String, V2TimGroupInfo>{};
    upsertGroupSearchResult(
      groups,
      V2TimGroupInfo(groupID: 'g1', groupType: 'Public', groupName: '本地群'),
    );
    upsertGroupSearchResult(
      groups,
      V2TimGroupInfo(groupID: 'g2', groupType: 'Public', groupName: '补充群'),
    );
    expect(groups.keys, unorderedEquals(<String>['g1', 'g2']));
  });

  test('joined whitelist: empty set drops IM groups, null skips filter', () {
    final incoming = <V2TimGroupInfo>[
      V2TimGroupInfo(groupID: 'left', groupType: 'Public', groupName: '已退'),
      V2TimGroupInfo(groupID: 'kept', groupType: 'Public', groupName: '仍在'),
    ];
    expect(
      filterGroupInfosByJoinedIds(incoming, <String>{}),
      isEmpty,
    );
    expect(
      filterGroupInfosByJoinedIds(incoming, <String>{'kept'}).map((g) => g.groupID),
      ['kept'],
    );
  });

  test('GroupLocalStore SQL empty without full cache is empty set, not skip-filter null',
      () async {
    await store.clearForOwner(owner);
    expect(store.isOwnerFullyCached(ownerUserId: owner), isFalse);
    final ids = await store.readJoinedGroupIdsForSearch(ownerUserId: owner);
    expect(ids, isNotNull);
    expect(ids, isEmpty);
  });

  test('GroupLocalStore ready with 0 groups returns empty set', () async {
    await store.clearForOwner(owner);
    store.debugMarkOwnerFullyCached(ownerUserId: owner);
    final ids = await store.readJoinedGroupIdsForSearch(ownerUserId: owner);
    expect(ids, isNotNull);
    expect(ids, isEmpty);
  });

  test('GroupLocalStore SQL ids without full cache drop a deleted leftover group',
      () async {
    await store.clearForOwner(owner);
    await store.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': 'g_keep',
        'groupName': '仍在',
        'groupType': 'Public',
        'memberCount': 2,
        'updatedAt': 1,
      }),
    );
    await store.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': 'g_left',
        'groupName': '已退',
        'groupType': 'Public',
        'memberCount': 2,
        'updatedAt': 1,
      }),
    );
    expect(store.isOwnerFullyCached(ownerUserId: owner), isFalse);
    var ids = await store.readJoinedGroupIdsForSearch(ownerUserId: owner);
    expect(ids, unorderedEquals(<String>['g_keep', 'g_left']));

    await store.delete(ownerUserId: owner, groupId: 'g_left');
    ids = await store.readJoinedGroupIdsForSearch(ownerUserId: owner);
    expect(ids, unorderedEquals(<String>['g_keep']));
    expect(
      filterGroupInfosByJoinedIds(
        [
          V2TimGroupInfo(groupID: 'g_keep', groupType: 'Public', groupName: '仍在'),
          V2TimGroupInfo(groupID: 'g_left', groupType: 'Public', groupName: '已退'),
        ],
        ids!,
      ).map((g) => g.groupID),
      ['g_keep'],
    );
    expect(
      searchJoinedGroupIdSetContains(ids, 'g_left'),
      isFalse,
    );
  });

  test('GroupLocalStore ready with groups returns those ids', () async {
    await store.clearForOwner(owner);
    store.debugPutCachedRecord(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': 'g_keep',
        'groupName': '带你的群',
        'groupType': 'Public',
        'memberCount': 2,
        'updatedAt': 1,
      }),
    );
    store.debugMarkOwnerFullyCached(ownerUserId: owner);
    final ids = await store.readJoinedGroupIdsForSearch(ownerUserId: owner);
    expect(ids, contains('g_keep'));
    expect(
      filterGroupInfosByJoinedIds(
        [
          V2TimGroupInfo(groupID: 'g_keep', groupType: 'Public', groupName: '带你的群'),
          V2TimGroupInfo(groupID: 'g_left', groupType: 'Public', groupName: '已退'),
        ],
        ids!,
      ).map((g) => g.groupID),
      ['g_keep'],
    );
  });

  test('search view model no longer uses ViewModel lists as membership source',
      () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_search_view_model.dart',
    ).readAsStringSync();
    expect(source.contains('_localFriendsForSearch'), isFalse);
    expect(source.contains('_localGroupsForSearch'), isFalse);
    expect(source.contains('friendList = apiResults'), isFalse);
    expect(source.contains('groupList = apiResults'), isFalse);
    expect(source.contains('friendOrderedIds'), isFalse);
    expect(source.contains('readJoinedGroupIdsForSearch'), isTrue);
    expect(source.contains('_keepExternalGroupSearchHit'), isTrue);
    expect(source.contains('_addDirectoryGroupHits'), isTrue);
    expect(source.contains('groupDirectoryMatchesSearchKeyword'), isTrue);
    expect(source.contains('keepSearchFriendByDirectoryMembership'), isTrue);
    expect(source.contains('searchFriendsLocal'), isTrue);
    expect(source.contains('_isCurrentGeneration'), isTrue);
    expect(
      source.contains('friendshipModel.groupList'),
      isFalse,
    );
  });

  test('groupDirectoryMatchesSearchKeyword uses the same rules as 我的群聊', () {
    expect(
      groupDirectoryMatchesSearchKeyword(
        groupName: '秋天来看秋叶+编10252+拉10237',
        groupId: 'jd_1',
        keyword: '秋',
      ),
      isTrue,
    );
    expect(
      groupDirectoryMatchesSearchKeyword(
        groupName: '一叶知秋+编10205+拉9751',
        groupId: 'jd_2',
        keyword: '秋',
      ),
      isTrue,
    );
    expect(
      groupDirectoryMatchesSearchKeyword(
        groupName: '京东对接小群',
        groupId: 'jd_3',
        keyword: '秋',
      ),
      isFalse,
    );
  });

  test('searchGroupIds hits my_groups names when search index is empty',
      () async {
    await store.clearForOwner(owner);
    await store.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': 'g_leaf',
        'groupName': '秋天来看秋叶+编10252+拉10237',
        'groupType': 'Public',
        'memberCount': 18,
        'updatedAt': 1,
      }),
    );
    await store.upsert(
      ownerUserId: owner,
      record: MeGroupRecord.fromJson({
        'groupId': 'g_wind',
        'groupName': '秋风+编10676+拉9328',
        'groupType': 'Public',
        'memberCount': 18,
        'updatedAt': 1,
      }),
    );
    await store.debugClearSearchIndexForOwner(owner);
    final page = await store.searchGroupIds(
      keyword: '秋',
      ownerUserId: owner,
    );
    expect(page.ids, unorderedEquals(<String>['g_leaf', 'g_wind']));
  });
}
