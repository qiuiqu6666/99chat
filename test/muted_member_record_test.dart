import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';

void main() {
  test('muted member retains nickname and avatar from business response', () {
    final dynamic record = MutedGroupMemberRecord.fromJson({
      'userId': '@alice',
      'muteUntilSec': 123,
      'nameCard': '群名片',
      'imRole': 'member',
      'nickname': '真实昵称',
      'avatarUrl': 'https://example.test/alice.png',
    });
    expect(record.userId, 'alice');
    expect(record.nickname, '真实昵称');
    expect(record.avatarUrl, 'https://example.test/alice.png');
  });
  test('missing profile fields differ from explicit empty strings', () {
    final dynamic old = MutedGroupMemberRecord.fromJson({'userId': 'alice'});
    final dynamic empty = MutedGroupMemberRecord.fromJson({
      'userId': 'alice',
      'nickname': '',
      'avatarUrl': '',
    });
    expect(old.nickname, isNull);
    expect(old.avatarUrl, isNull);
    expect(empty.nickname, '');
    expect(empty.avatarUrl, '');
  });
}
