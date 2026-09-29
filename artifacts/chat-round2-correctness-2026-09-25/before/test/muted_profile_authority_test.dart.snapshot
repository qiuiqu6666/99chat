import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/muted_member_profiles.dart';

void main() {
  test(
      'authoritative business fields including explicit empty resist SDK values',
      () {
    final original = V2TimGroupMemberFullInfo(
        userID: 'alice',
        nickName: '业务昵称',
        faceUrl: '',
        role: 200,
        muteUntil: 99);
    final result = mergeMutedMemberProfiles([
      original
    ], [
      V2TimGroupMemberFullInfo(
          userID: 'alice',
          nickName: 'SDK昵称',
          faceUrl: 'old-avatar',
          role: 400,
          muteUntil: 0)
    ], authoritativeNames: {
      'alice'
    }, authoritativeAvatars: {
      'alice'
    }, acceptEmpty: true)
        .single;
    expect(result.nickName, '业务昵称');
    expect(result.faceUrl, '');
    expect(result.role, 200);
    expect(result.muteUntil, 99);
  });
  test(
      'fresh explicit empty clears stale profile while null preserves known value',
      () {
    final original = V2TimGroupMemberFullInfo(
        userID: 'alice', nickName: '旧昵称', faceUrl: 'known-avatar');
    final result = mergeMutedMemberProfiles([
      original
    ], [
      V2TimGroupMemberFullInfo(userID: 'alice', nickName: '')
    ], acceptEmpty: true)
        .single;
    expect(result.nickName, '');
    expect(result.faceUrl, 'known-avatar');
  });
  test('profile cannot add a member absent from authoritative muted list', () {
    final result = mergeMutedMemberProfiles([
      V2TimGroupMemberFullInfo(userID: 'bob')
    ], [
      V2TimGroupMemberFullInfo(userID: 'alice', nickName: '迟到昵称')
    ], acceptEmpty: true);
    expect(result.map((e) => e.userID), ['bob']);
  });
}
