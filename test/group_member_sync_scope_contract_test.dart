import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home idle omits members while on-demand and repair lanes remain', () {
    final home =
        File('lib/src/bootstrap/home_bootstrap.dart').readAsStringSync();
    final profile = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_group_profile_model.dart',
    ).readAsStringSync();
    final incremental = File(
      'lib/src/services/group_local/group_member_incremental_sync_service.dart',
    ).readAsStringSync();
    final realtime = File(
      'lib/src/services/group_local/group_sync_service.dart',
    ).readAsStringSync();
    final manage = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
      'TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart',
    ).readAsStringSync();
    final walletMemberPicker = File(
      'lib/src/pages/wallet/red_packet/red_packet_member_picker_page.dart',
    ).readAsStringSync();

    expect(home, isNot(contains('idle_group_member_pending')));
    expect(home, isNot(contains('syncPendingEligible')));

    expect(profile, contains('ensureMemberListPage({int count = 50})'));
    expect(profile,
        contains('Future<bool> loadMoreGroupMembers({int count = 50})'));
    expect(profile, contains('Future<void> loadManagementMembers()'));
    expect(profile, contains('loadProfileMemberPreviewPage'));
    expect(profile, contains('memberPreviewRestPageSize'));
    final loadDataStart = profile.indexOf('void loadData(String groupID)');
    expect(loadDataStart, greaterThanOrEqualTo(0));
    final loadSelfStart = profile.indexOf('Future<void> _loadSelfMember');
    expect(loadSelfStart, greaterThan(loadDataStart));
    final loadDataBody = profile.substring(loadDataStart, loadSelfStart);
    expect(loadDataBody, contains('loadProfileMemberPreviewPage('));
    expect(loadDataBody, isNot(contains('loadGroupMemberList(')));
    expect(manage, isNot(contains('ensureMemberListPage(count: 50)')));
    expect(RegExp(r'loadMembersOnEntry:\s*widget\.model\.loadMemberPageOnEntry')
        .hasMatch(manage), isTrue);
    expect(manage, contains('memberListListenable: widget.model'));
    expect(manage, contains('widget.model.loadMoreGroupMembers()'));

    expect(walletMemberPicker, contains('ListView.builder('));
    expect(walletMemberPicker, isNot(contains('AZListViewContainer')));
    expect(walletMemberPicker, isNot(contains('sortListBySuspensionTag')));

    expect(incremental, isNot(contains('Future<void> syncForGroup(')));
    expect(incremental, isNot(contains('syncFullForGroup(')));
    expect(incremental, isNot(contains('syncAllJoined(')));
    expect(incremental, isNot(contains('syncPendingEligible(')));
    expect(incremental, isNot(contains('enqueueGroupMemberSync(')));
    expect(realtime, contains('shouldApplyRealtimeSeq('));
    expect(realtime, contains('noteRealtimeSeq('));
    expect(realtime, contains('_scheduleTargetedMembershipCorrection('));
    expect(realtime, isNot(contains('GroupChangeEventSyncService')));
    expect(profile, isNot(contains('bool fullSync')));
  });

  test('owner and admin member pages load from REST not IM SDK', () {
    final membership = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final restLoaderStart =
        membership.indexOf('_loadOwnerAdminMemberPageFromRest({');
    expect(restLoaderStart, greaterThanOrEqualTo(0));
    final restLoader = membership.substring(restLoaderStart);
    final restLoaderEnd = restLoader.indexOf('_loadLocalMemberPage({');
    expect(restLoaderEnd, greaterThan(0));
    final restBody = restLoader.substring(0, restLoaderEnd);
    expect(restBody, contains('fetchGroupMembersPage('));
    expect(restBody, isNot(contains('_loadGroupMemberPageFromImSdk')));
    expect(membership, contains('MeGroupApi.instance.setMemberRoles('));
  });
}
