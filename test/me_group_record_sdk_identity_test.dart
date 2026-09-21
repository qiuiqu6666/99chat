import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';

void main() {
  test('SDK non-empty name and faceUrl are kept', () {
    final record = MeGroupRecord.fromV2TimGroupInfo(
      V2TimGroupInfo(
        groupID: '@TGS#_mcSdkId',
        groupType: 'Work',
        groupName: 'SDK name',
        faceUrl: 'https://im.test/face.png',
        lastInfoTime: 1700000000,
      ),
      preserveFrom: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': '@TGS#_mcSdkId',
        'groupName': 'Local name',
        'avatarUrl': 'https://local.test/old.png',
        'updatedAt': 1,
      }),
    );
    expect(record.groupName, 'SDK name');
    expect(record.avatarUrl, 'https://im.test/face.png');
    expect(record.updatedAt, 1700000000 * 1000);
  });

  test('SDK empty identity falls back to preserveFrom and lastInfoTime', () {
    final record = MeGroupRecord.fromV2TimGroupInfo(
      V2TimGroupInfo(
        groupID: '@TGS#_mcSdkId',
        groupType: 'Work',
        groupName: '',
        faceUrl: '',
      ),
      preserveFrom: MeGroupRecord.fromJson(<String, dynamic>{
        'groupId': '@TGS#_mcSdkId',
        'groupName': 'Local name',
        'avatarUrl': 'https://local.test/old.png',
        'updatedAt': 42,
      }),
    );
    expect(record.groupName, 'Local name');
    expect(record.avatarUrl, 'https://local.test/old.png');
    expect(record.updatedAt, 42 * 1000);
  });
}
