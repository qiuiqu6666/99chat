import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group member surfaces have no alphabet index or name sorting', () {
    final sharedList = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/group_member_list.dart',
    ).readAsStringSync();
    final conversationPicker = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitSearch/'
      'tim_uikit_conversation_member_picker_page.dart',
    ).readAsStringSync();

    expect(sharedList, isNot(contains('final bool isShowIndexBar')));
    expect(sharedList, isNot(contains('memberSuspensionIndexTag')));
    expect(sharedList, isNot(contains('.name.compareTo')));
    expect(conversationPicker, isNot(contains('memberSuspensionIndexTag')));
    expect(conversationPicker, isNot(contains('SuspensionUtil.sortList')));
  });
}
