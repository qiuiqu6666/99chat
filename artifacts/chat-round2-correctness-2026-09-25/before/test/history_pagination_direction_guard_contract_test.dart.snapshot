import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official SDK tail cursor covers C2C and groups', () {
    final pagination = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_history_pagination_load.dart',
    ).readAsStringSync();
    final model = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_separate_view_model.dart',
    ).readAsStringSync();

    expect(pagination.contains('useOfficialOlderCursor'), isTrue);
    expect(
      pagination.contains(
        'lastSdkPageTail: model._sdkOlderPageTail',
      ),
      isTrue,
    );
    expect(
      pagination.contains('getHistoryMessageListThroughIm06('),
      isTrue,
    );
    expect(
      pagination.contains('actualRequestLastMsgID'),
      isTrue,
    );
    expect(pagination.contains('load_previous_direction_mismatch'), isTrue);
    expect(model.contains('_rememberSdkOlderPage(messages)'), isTrue);
    expect(model.contains('_sdkOlderPageTail'), isTrue);
  });
}
