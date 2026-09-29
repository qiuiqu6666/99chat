import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formal UIKit history callers route through IM-06', () {
    const formalFiles = <String>[
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'separate_models/tui_chat_history_pagination_load.dart',
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'separate_models/tui_chat_separate_view_model.dart',
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'view_models/tui_chat_global_model.dart',
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
          'view_models/tui_search_view_model.dart',
    ];
    for (final path in formalFiles) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r'_messageService\.getHistoryMessageList(?:WithComplete)?\(')
            .allMatches(source),
        isEmpty,
        reason: path,
      );
      expect(source, contains('getHistoryMessageListThroughIm06('));
    }
  });

  test('all history and search SDK calls stay inside audited adapters', () {
    const allowed = <String>{
      'lib/src/services/archive_im_local_persist_service.dart',
      'lib/src/services/conversation_local/conversation_sync_service.dart',
      'lib/src/services/im/history_search_coordinator.dart',
      'lib/src/services/im/tencent_message_adapter.dart',
      'lib/src/services/platform_official_account_service.dart',
      'lib/src/services/web_message_loader.dart',
      'third_party/tencent_cloud_chat_uikit/lib/data_services/message/'
          'message_history_peek_loader.dart',
      'third_party/tencent_cloud_chat_uikit/lib/data_services/message/'
          'message_service_implement.dart',
    };
    final directCall = RegExp(
      r'\.(?:getHistoryMessageList(?:V2|WithComplete)?|'
      r'searchLocalMessages|searchCloudMessages)\(',
    );
    final actual = <String>{};
    for (final root in <String>[
      'lib',
      'third_party/tencent_cloud_chat_uikit/lib'
    ]) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (directCall.hasMatch(entity.readAsStringSync())) actual.add(path);
      }
    }
    expect(actual.difference(allowed), isEmpty);
    expect(allowed.difference(actual), isEmpty);
  });
}
