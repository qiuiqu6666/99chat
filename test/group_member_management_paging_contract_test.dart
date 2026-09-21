import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group management member pickers observe and request member pages', () {
    final manage = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
      'TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart',
    ).readAsStringSync();
    final remove = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
      'TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart',
    ).readAsStringSync();
    final transfer = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/'
      'transimit_group_owner_select.dart',
    ).readAsStringSync();
    final complaint = File(
      'lib/src/pages/complaint/complaint_member_pick_page.dart',
    ).readAsStringSync();

    expect(manage, contains('memberListProvider: availableMembers'));
    expect(manage, contains('memberListListenable: widget.model'));
    expect(manage, contains('widget.model.loadMoreGroupMembers()'));
    expect(remove, contains('animation: widget.model'));
    expect(remove, contains('await widget.model.loadMoreGroupMembers()'));
    expect(transfer, contains('animation: widget.model'));
    expect(transfer, contains('await widget.model.loadMoreGroupMembers()'));
    expect(complaint, contains('animation: widget.model'));
    expect(complaint, contains('await widget.model.loadMoreGroupMembers()'));
  });
}
