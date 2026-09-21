import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/my_group_az_skeleton.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  test('my group entry restores group identity omitted by SDK conversation',
      () {
    const groupId = '@TGS#_mc2SX4NMM62CZ';
    const groupName = '测试群';
    final skeleton = const MyGroupAzSkeleton(
      groupId: groupId,
      groupType: 'Community',
      groupName: groupName,
      avatarUrl: '',
      memberCount: 1403,
      myRole: 0,
      indexTag: 'C',
    );

    final merged = skeleton.toConversation(
      sdkConversation: V2TimConversation(
        // Some SDK conversation responses use the bare, valid group ID and
        // omit groupID; that is the production failure this covers.
        conversationID: groupId,
        type: 2,
      ),
    );

    expect(merged.conversationID, groupId);
    expect(merged.groupID, groupId);
    expect(merged.type, 2);
    expect(merged.groupType, 'Community');
    expect(merged.showName, groupName);
  });
}
