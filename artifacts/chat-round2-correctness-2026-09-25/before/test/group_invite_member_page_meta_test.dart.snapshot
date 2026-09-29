import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/utils/group_invite_member_page_meta.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_join_application_service.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';

void main() {
  test('parses pending-invitees payload and sorts user ids', () {
    final ids = GroupJoinApi.parsePendingInviteeUserIds(<String, dynamic>{
      'userIds': <String>['friend09', 'friend02', 'friend02'],
    });
    expect(ids, <String>['friend02', 'friend09']);
  });

  test('collects pending invitee ids for target group only', () {
    final applications = <V2TimGroupApplication>[
      V2TimGroupApplication(
        groupID: '@TGS#demo',
        fromUser: 'inviter',
        toUser: 'invitee-1',
        addTime: 100,
        type: 2,
        handleStatus: 0,
        handleResult: 0,
        authentication:
            '${GroupJoinApplicationService.applicationAuthPrefix}1',
      ),
      V2TimGroupApplication(
        groupID: '@TGS#other',
        fromUser: 'inviter',
        toUser: 'invitee-2',
        addTime: 100,
        type: 2,
        handleStatus: 0,
        handleResult: 0,
        authentication:
            '${GroupJoinApplicationService.applicationAuthPrefix}2',
      ),
      V2TimGroupApplication(
        groupID: '@TGS#demo',
        fromUser: 'done-user',
        toUser: 'done-invitee',
        addTime: 100,
        type: 2,
        handleStatus: 1,
        handleResult: 1,
        authentication:
            '${GroupJoinApplicationService.applicationAuthPrefix}3',
      ),
    ];

    final pending = GroupInviteMemberPageMeta.collectPendingInviteeUserIds(
      applications: applications,
      groupId: '@TGS#demo',
    );
    final handled = GroupInviteMemberPageMeta.collectHandledInviteeUserIds(
      applications: applications,
      groupId: '@TGS#demo',
    );

    expect(pending, {'invitee-1'});
    expect(handled, {'done-invitee'});
  });

  test('existingMemberUserIds returns empty without lookup when candidates empty',
      () async {
    final ids = await GroupInviteMemberPageMeta.existingMemberUserIds(
      '@TGS#demo',
      candidateUserIds: const <String>[],
    );
    expect(ids, isEmpty);
  });

  test('memberUserIdsFromLookup normalizes @ and c2c_ to the same uid', () {
    final found = <V2TimGroupMemberFullInfo>[
      V2TimGroupMemberFullInfo(userID: '@alice'),
      V2TimGroupMemberFullInfo(userID: 'c2c_alice'),
      V2TimGroupMemberFullInfo(userID: 'alice'),
    ];
    expect(
      GroupInviteMemberPageMeta.memberUserIdsFromLookup(found),
      {'alice'},
    );
  });
}
