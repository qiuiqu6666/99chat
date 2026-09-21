import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live custom tip refreshes only this group via IM SDK group info', () {
    final source = File(
      'lib/src/services/group_local/group_membership_sync_service.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<void> applyInboundGroupDisplayFromMessage(',
    );
    final end = source.indexOf(
      'Future<void> applyInboundMembershipTipFromMessage(',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('message.isSelf == true'));
    expect(body, contains('isLocalGroupTips(message)'));
    expect(body, contains('isGroupProfileRefreshTipAction(action)'));
    expect(body, contains('refreshGroupDetail(groupId, refresh: true)'));
    expect(body, contains('applyOptimisticGroupName('));
    expect(body, contains('extractGroupTipDisplayFields('));
    expect(body, isNot(contains('MeGroupApi.instance.fetchGroupDetail')));
    expect(body, isNot(contains('fetchGroupMembersPage(')));
    expect(body, isNot(contains('loadGroupMemberPage(')));
    expect(body, isNot(contains('applyTargetedMemberCorrection(')));
    expect(body, isNot(contains('syncMembersAfterMembershipChange(')));
  });

  test('conversation sync does not scan historical lastMessage tips', () {
    final source = File(
      'lib/src/services/conversation_local/conversation_sync_service.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('applyInboundGroupDisplayFromMessage')));
  });
}
