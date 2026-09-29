import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_local_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_membership_sync_service.dart';

void main() {
  group('cached group metadata reuse', () {
    test(
        'reuses a known row when avatar and member count are legitimately empty',
        () {
      final record = MeGroupRecord.fromJson({
        'groupId': '@TGS#_known-empty',
        'groupName': 'Known group',
        'groupType': '',
        'displayAlias': '@TGS#_known-empty',
        'avatarUrl': '',
        'memberCount': 0,
        'updatedAt': 1789069002315,
      });
      expect(
        GroupMembershipSyncService.isReusableCachedGroupMetadata(record),
        isTrue,
      );
    });

    test('does not treat an identity-free optimistic shell as reusable', () {
      final record = MeGroupRecord(
        groupId: '@TGS#_new-shell',
        groupName: '',
        groupType: '',
        displayAlias: '',
        avatarUrl: '',
        memberCount: 0,
        myRole: 200,
        myNameCard: '',
        notice: '',
        joinedAt: 0,
        updatedAt: 1789069002315,
      );
      expect(
        GroupMembershipSyncService.isReusableCachedGroupMetadata(record),
        isFalse,
      );
    });

    test('does not treat an ID-only persisted shell as reusable', () {
      final record = MeGroupRecord.fromJson({
        'groupId': '@TGS#_id-only-shell',
        'groupName': '',
        'groupType': '',
        'displayAlias': '@TGS#_id-only-shell',
        'avatarUrl': '',
        'memberCount': 0,
        'updatedAt': 1789069002315,
      });
      expect(
        GroupMembershipSyncService.isReusableCachedGroupMetadata(record),
        isFalse,
      );
    });
  });

  group('shouldSkipNetworkSyncFullDecision', () {
    test('skips when process already synced once', () {
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'native_post_home_after_quiet',
        localCount: 3001,
        groupListSyncedOnce: true,
        metaAtMs: 0,
        metaCount: 0,
        nowMs: 1,
      );
      expect(skip, isTrue);
    });

    test('skips when meta fresh and count matches', () {
      const now = 1000000;
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'tcp_auth_ok',
        localCount: 3001,
        groupListSyncedOnce: false,
        metaAtMs: now - 60000,
        metaCount: 3001,
        nowMs: now,
      );
      expect(skip, isTrue);
    });

    test('group page completion does not trust partial startup state', () {
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'my_group_list_background',
        localCount: 3001,
        groupListSyncedOnce: true,
        metaAtMs: 0,
        metaCount: 0,
        nowMs: 1,
      );
      expect(skip, isFalse);
    });

    test('does not skip refresh:true', () {
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: true,
        reason: 'native_post_home',
        localCount: 3001,
        groupListSyncedOnce: true,
        metaAtMs: 1,
        metaCount: 3001,
        nowMs: 2,
      );
      expect(skip, isFalse);
    });

    test('does not skip idle_reconcile reason', () {
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'idle_reconcile',
        localCount: 3001,
        groupListSyncedOnce: true,
        metaAtMs: 1,
        metaCount: 3001,
        nowMs: 2,
      );
      expect(skip, isFalse);
    });

    test('does not skip when meta count mismatches', () {
      const now = 1000000;
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'native_post_home',
        localCount: 3001,
        groupListSyncedOnce: false,
        metaAtMs: now - 60000,
        metaCount: 2990,
        nowMs: now,
      );
      expect(skip, isFalse);
    });

    test('does not skip when meta older than max age', () {
      const now = 1000000000;
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'native_post_home',
        localCount: 3001,
        groupListSyncedOnce: false,
        metaAtMs: now - GroupLocalPerfFlags.fullSyncMaxAge.inMilliseconds - 1,
        metaCount: 3001,
        nowMs: now,
      );
      expect(skip, isFalse);
    });

    test('does not skip below localCompleteMinCount', () {
      final skip = GroupMembershipSyncService.shouldSkipNetworkSyncFullDecision(
        refresh: false,
        reason: 'native_post_home',
        localCount: GroupLocalPerfFlags.localCompleteMinCount - 1,
        groupListSyncedOnce: true,
        metaAtMs: 1,
        metaCount: 50,
        nowMs: 2,
      );
      expect(skip, isFalse);
    });
  });
}
