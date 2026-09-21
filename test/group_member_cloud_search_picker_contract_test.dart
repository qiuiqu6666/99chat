import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      'manage': File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
        'TIMUIKitGroupProfile/widgets/tim_uikit_group_manage.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      'delete': File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/'
        'TIMUIKitGroupProfile/group_member/tui_delete_group_member.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      'transfer': File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/widgets/'
        'transimit_group_owner_select.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      'at': File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
        'TIMUIKitTextField/tim_uikit_at_text.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      'complaint': File(
        'lib/src/pages/complaint/complaint_member_pick_page.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
      'call': File(
        'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
        'TIMUIKitTextField/tim_uikit_call_invite_list.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
    };
  });

  test('six member pickers wire GroupMemberCloudSearch', () {
    for (final entry in sources.entries) {
      expect(
        entry.value.contains('GroupMemberCloudSearch'),
        isTrue,
        reason: '${entry.key} must use GroupMemberCloudSearch',
      );
    }
  });

  test('empty keyword still uses existing member pagination', () {
    expect(sources['manage']!, contains('widget.model.loadMoreGroupMembers()'));
    expect(sources['delete']!, contains('await widget.model.loadMoreGroupMembers()'));
    expect(sources['transfer']!, contains('await widget.model.loadMoreGroupMembers()'));
    expect(sources['complaint']!, contains('await widget.model.loadMoreGroupMembers()'));
    expect(sources['at']!, contains('Future<void> _loadMoreMembers()'));
    expect(sources['call']!, contains('Future<void> _loadMoreMembers()'));
  });
}
