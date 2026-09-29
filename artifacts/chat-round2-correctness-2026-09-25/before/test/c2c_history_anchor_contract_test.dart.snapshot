import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C2C older pagination preserves the full Tencent message anchor', () {
    final globalModel = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'view_models/tui_chat_global_model.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/src/services/im/history_search_coordinator.dart',
    ).readAsStringSync();
    final adapter = File(
      'lib/src/services/im/tencent_message_adapter.dart',
    ).readAsStringSync();
    final messageList = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart',
    ).readAsStringSync();
    final listContainer = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_history_message_list_container.dart',
    ).readAsStringSync();
    final viewModel = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/'
      'tui_chat_separate_view_model.dart',
    ).readAsStringSync();
    final pagination = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/'
      'tui_chat_history_pagination_load.dart',
    ).readAsStringSync();

    expect(globalModel, contains('lastMessage: lastMsg'));
    expect(coordinator, contains('lastMsg: request.lastMessage'));
    expect(adapter, contains('lastMsg: lastMsg'));
    expect(messageList, contains('anchor.message'));
    expect(listContainer, contains('lastMsg: lastMsg'));
    expect(viewModel, contains('V2TimMessage? lastMsg'));
    expect(pagination, contains('(lastMsg ??'));
  });
}
