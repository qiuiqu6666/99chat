import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/group_join_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/join_group_application_page.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';

V2TimGroupInfo _group({int? memberCount}) => V2TimGroupInfo(
      groupID: '@TGS#joinPreview',
      groupType: 'Public',
      groupName: '测试群',
      memberCount: memberCount,
    );

void main() {
  group('joinGroupPreviewMemberCount', () {
    test('keeps a positive detail count', () {
      expect(
        joinGroupPreviewMemberCount(
          incoming: _group(memberCount: 3),
          detail: _group(memberCount: 12),
          storedCount: 8,
        ),
        12,
      );
    });

    test('falls back to incoming when detail is missing or zero', () {
      expect(
        joinGroupPreviewMemberCount(
          incoming: _group(memberCount: 9),
          detail: null,
        ),
        9,
      );
      expect(
        joinGroupPreviewMemberCount(
          incoming: _group(memberCount: 9),
          detail: _group(memberCount: 0),
        ),
        9,
      );
    });

    test('falls back to local store when lookup and detail are zero', () {
      expect(
        joinGroupPreviewMemberCount(
          incoming: _group(memberCount: 0),
          detail: _group(memberCount: 0),
          storedCount: 8,
        ),
        8,
      );
    });

    test('stays zero only when every source is empty', () {
      expect(
        joinGroupPreviewMemberCount(
          incoming: _group(),
          detail: null,
        ),
        0,
      );
    });
  });

  group('GroupJoinApi.groupInfoFromLookup', () {
    test('carries the channel marker into the subscribe preview', () {
      final channel = GroupJoinApi.groupInfoFromLookup(<String, dynamic>{
        'groupId': 'channel-1',
        'groupType': 'Community',
        'channel': true,
      });
      final group = GroupJoinApi.groupInfoFromLookup(<String, dynamic>{
        'groupId': 'group-1',
        'groupType': 'Community',
      });
      expect(channel?.customInfo?['isChannel'], 'true');
      expect(group?.customInfo?['isChannel'], isNull);
    });

    test('reads camelCase and snake_case member counts for every join entry',
        () {
      expect(
        GroupJoinApi.groupInfoFromLookup(<String, dynamic>{
          'groupId': 'g1',
          'memberCount': 4,
        })?.memberCount,
        4,
      );
      expect(
        GroupJoinApi.groupInfoFromLookup(<String, dynamic>{
          'group_id': 'g2',
          'member_count': 7,
        })?.memberCount,
        7,
      );
      expect(
        GroupJoinApi.groupInfoFromLookup(<String, dynamic>{
          'groupID': 'g3',
          'member_num': '11',
        })?.memberCount,
        11,
      );
    });
  });
}
