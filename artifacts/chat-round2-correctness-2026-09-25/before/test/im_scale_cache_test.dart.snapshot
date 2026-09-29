import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/friend_search_cache.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/bounded_lru_map.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/group_member_store.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';

void main() {
  test('LRU refreshes reads and normalizes putIfAbsent values', () {
    final cache = BoundedLruMap<String, int>(2);
    cache['a'] = 1;
    cache['b'] = 2;
    expect(cache['a'], 1);
    cache['c'] = 3;
    expect(cache.containsKey('b'), isFalse);
    expect(cache.evictions, 1);
    final nested = BoundedLruMap<String, Map<String, int>>(2,
        normalize: (value) => BoundedLruMap<String, int>(2)..addAll(value));
    final bucket = nested.putIfAbsent('g', () => <String, int>{});
    bucket.addAll({'a': 1, 'b': 2, 'c': 3});
    expect(nested['g']!.length, 2);
  });

  test('20k contacts reuse pinyin across keystrokes and invalidate rename', () {
    var conversions = 0;
    final cache = FriendSearchCache(toPinyin: (name) {
      conversions++;
      return name == '小明' ? 'xiao ming' : name;
    });
    for (final query in ['x', 'xi', 'xiao']) {
      for (var i = 0; i < 20000; i++) {
        cache.matches('$i', i == 0 ? '小明' : 'name$i', query);
      }
    }
    expect(conversions, 20000);
    expect(cache.matches('0', '小明', 'xiao'), isTrue);
    expect(cache.matches('0', 'renamed', 'xiao'), isFalse);
    expect(conversions, 20001);
    cache.clear();
    expect(cache.length, 0);
  });

  test('100 groups of 30000 senders retain a bounded cache, no listeners', () {
    final store = GroupMemberStore.instance;
    store.clear(notify: false);
    for (var g = 0; g < 100; g++) {
      store.putMembers(
          'g$g',
          Iterable.generate(
              30000,
              (i) => V2TimGroupMemberFullInfo(
                  userID: 'u$i', nickName: 'User $i')));
    }
    expect(store.cachedGroupCount,
        lessThanOrEqualTo(GroupMemberStore.groupCapacity));
    expect(
        store.cachedMemberCount,
        lessThanOrEqualTo(GroupMemberStore.groupCapacity *
            GroupMemberStore.membersPerGroupCapacity));
    expect(store.dormantAvatarCount, 0);
    expect(store.avatarSubscriptionCount, 0);
    expect(store.memberOf('g99', 'u29999'), isNotNull);
    store.clear(notify: false);
  });

  test('membership removals reach subscribers even after cache eviction',
      () async {
    final store = GroupMemberStore.instance;
    store.clear(notify: false);
    final events = <String>[];
    final subscription =
        store.removals.listen((event) => events.addAll(event.userIDs));
    store.removeMembers('evicted-group', ['removed-user'], notify: false);
    expect(events, ['removed-user']);
    await subscription.cancel();
    store.removeMembers('evicted-group', ['other-user'], notify: false);
    expect(events, ['removed-user']);
  });

  test('removed members stay tombstoned until cleared', () {
    final store = GroupMemberStore.instance;
    store.clear(notify: false);
    store.putMembers('g1', [
      V2TimGroupMemberFullInfo(userID: 'u1', nickName: 'One'),
    ]);
    store.removeMembers('g1', ['u1'], notify: false);
    expect(store.memberOf('g1', 'u1'), isNull);
    expect(store.isRemovalTombstoned('g1', 'u1'), isTrue);
    store.putMembers('g1', [
      V2TimGroupMemberFullInfo(userID: 'u1', nickName: 'One'),
    ]);
    store.putMember('g1', V2TimGroupMemberFullInfo(userID: 'u1', nickName: 'One'));
    expect(store.memberOf('g1', 'u1'), isNull);
    store.clearRemovalTombstones('g1', ['u1']);
    store.putMembers('g1', [
      V2TimGroupMemberFullInfo(userID: 'u1', nickName: 'One'),
    ]);
    expect(store.memberOf('g1', 'u1')?.nickName, 'One');
    store.clear(notify: false);
  });

  test('avatar subscriptions survive cache pressure and release on detach', () {
    final store = GroupMemberStore.instance;
    store.clear(notify: false);
    final avatar = store.avatarListenable('active', 'u');
    var notifications = 0;
    void changed() => notifications++;
    avatar.addListener(changed);
    for (var i = 0; i < 2000; i++) {
      store.avatarListenable('offscreen', '$i');
    }
    expect(store.dormantAvatarCount, lessThanOrEqualTo(256));
    store.notifyChatAvatarRefreshForUsers('active', ['u']);
    expect(notifications, 1);
    store.clear();
    expect(notifications, 2);
    avatar.removeListener(changed);
    expect(store.avatarSubscriptionCount, 0);
    expect(store.dormantAvatarCount, 0);
  });
}
