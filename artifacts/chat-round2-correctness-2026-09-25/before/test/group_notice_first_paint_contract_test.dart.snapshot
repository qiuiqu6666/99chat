import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group notice page distinguishes loading from an empty inbox', () {
    final source =
        File('lib/src/all_group_application_list.dart').readAsStringSync();

    expect(source, contains('required bool isLoading,'));
    expect(source, contains('if (isLoading) {'));
    expect(
        source, contains('child: CircularProgressIndicator(strokeWidth: 2.5)'));
    expect(
      source,
      contains(
        '_joinApplicationService.isLoading || _systemNoticeService.isLoading',
      ),
    );
  });

  test('system notices restore local projection before remote refresh', () {
    final source = File(
      'lib/src/services/group_system_notice_service.dart',
    ).readAsStringSync();
    final projected =
        source.indexOf('final projected = await _loadProjectedNotices(');
    final remote = source.indexOf(
      'final page = await GroupNoticeApi.instance.fetchMyGroupNotices(',
      projected,
    );

    expect(projected, greaterThanOrEqualTo(0));
    expect(remote, greaterThan(projected));
    expect(source, contains('final localNext = _filterDismissed('));
  });

  test('friend and group notices share action and status components', () {
    final group =
        File('lib/src/all_group_application_list.dart').readAsStringSync();
    final single =
        File('lib/src/pages/group_self_hosted_join_application_list_page.dart')
            .readAsStringSync();
    final sdk = File('third_party/tencent_cloud_chat_uikit/lib/ui/views/'
            'TIMUIKitGroup/tim_uikit_group_application_list.dart')
        .readAsStringSync();

    for (final source in [group, single, sdk]) {
      expect(source, contains('DirectoryActionButton('));
      expect(source, contains('DirectoryStatusBadge('));
      expect(source, contains('DirectoryStatusKind.accepted'));
      expect(source, contains('DirectoryStatusKind.rejected'));
    }
    expect(group, contains('DirectoryStatusKind.pending'));
    expect(group, contains('DirectoryStatusKind.notice'));
    expect(single, contains('DirectoryActionTone.secondary'));
    expect(sdk, contains('DirectoryActionTone.secondary'));
  });

  test('pending group applications never render a blank approval state', () {
    final list =
        File('lib/src/all_group_application_list.dart').readAsStringSync();
    final service = File('lib/src/services/group_join_application_service.dart')
        .readAsStringSync();
    final single =
        File('lib/src/pages/group_self_hosted_join_application_list_page.dart')
            .readAsStringSync();

    final statusStart = list.indexOf('Widget _buildStatusWidget(');
    final statusEnd = list.indexOf('Widget _buildPill(', statusStart);
    final status = list.substring(statusStart, statusEnd);
    expect(status, contains('isPendingApplication(applicationInfo)'));
    expect(status, contains("zhHans: '待审核'"));
    expect(status, contains("zhHans: '审核'"));
    expect(
        status, contains('_openApplicationDetail(context, applicationInfo)'));
    expect(status, isNot(contains('applicationInfo.handleStatus != 0')));

    expect(service,
        contains('await GroupMembershipSyncService.instance.adminGroupIds()'));
    expect(
        service,
        isNot(contains(
            'await GroupMembershipSyncService.instance.adminSelfHostedGroupIds()')));
    expect(single, contains("zhHans: '待审核'"));
  });

  test('approval page upgrades a passive refresh to authoritative role sync',
      () {
    final page =
        File('lib/src/all_group_application_list.dart').readAsStringSync();
    final service = File('lib/src/services/group_join_application_service.dart')
        .readAsStringSync();

    expect(page, contains('_joinApplicationService.refresh(force: true)'));
    expect(service, contains('_refreshInFlightSyncsMembership'));
    expect(service, contains('final existingTail = _refreshCoalesceTail'));
    expect(service, contains('refresh: force'));
  });
}
