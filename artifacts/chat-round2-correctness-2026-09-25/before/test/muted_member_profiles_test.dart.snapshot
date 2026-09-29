import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/muted_member_profiles.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart';

void main() {
  test('management page compiles with profile enrichment', () {
    expect(GroupProfileGroupManagePage, isA<Type>());
  });
  test('fills nickname and avatar without changing mute authority', () {
    final muted = V2TimGroupMemberFullInfo(userID: 'alice', muteUntil: 999,
        role: 200, nameCard: '群名片');
    final profile = V2TimGroupMemberFullInfo(userID: 'alice', nickName: '昵称',
        faceUrl: 'https://example.test/avatar.png', muteUntil: 0,
        role: 400, nameCard: '旧名片');
    final result = mergeMutedMemberProfiles([muted], [profile]).single;
    expect(result.nickName, '昵称');
    expect(result.faceUrl, profile.faceUrl);
    expect(result.nameCard, '群名片');
    expect(result.muteUntil, 999);
    expect(result.role, 200);
    expect(muted.nickName, isNull);
  });
  test('late profile response does not restore an unmuted member', () {
    final profile = V2TimGroupMemberFullInfo(userID: 'alice', nickName: '昵称');
    expect(mergeMutedMemberProfiles([], [profile]), isEmpty);
    final bob = V2TimGroupMemberFullInfo(userID: 'bob');
    expect(mergeMutedMemberProfiles([bob], [profile]).single.userID, 'bob');
  });
  test('empty profile fields preserve already visible identity', () {
    final muted = V2TimGroupMemberFullInfo(userID: 'alice', nickName: '昵称',
        faceUrl: 'avatar', friendRemark: '备注');
    final result = mergeMutedMemberProfiles([muted], [
      V2TimGroupMemberFullInfo(userID: 'alice', nickName: '  ', faceUrl: '')
    ]).single;
    expect(result.nickName, '昵称');
    expect(result.faceUrl, 'avatar');
    expect(result.friendRemark, '备注');
  });
}
