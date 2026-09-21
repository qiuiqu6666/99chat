import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stuck-message recovery cannot convert OutcomeUnknown to retryable UI',
      () {
    final source = File(
      'lib/src/services/chat_failed_message_retry_service.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('current?.state == ImOutboxState.outcomeUnknown'),
    );
    expect(source, contains('if (!shouldSettleAsFailed) continue;'));
  });

  test('sending indicator requires explicit user abandonment', () {
    final item = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/'
      'TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart',
    ).readAsStringSync();
    final model = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/'
      'tui_chat_global_model.dart',
    ).readAsStringSync();
    expect(item, contains('showOutcomeUnknownDialog(context)'));
    expect(item, contains('.abandonOutcomeUnknownMessage('));
    expect(model, contains('.abandonOutcomeUnknown('));
    expect(model, contains("reason: 'outcome_unknown_abandoned_by_user'"));
  });
}
