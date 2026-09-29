import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_message_tooltip.dart';

void main() {
  test('mobile action menu uses only the rows required by its options', () {
    expect(TIMUIKitMessageTooltipState.mobileTooltipRowCount(1), 1);
    expect(TIMUIKitMessageTooltipState.mobileTooltipRowCount(5), 1);
    expect(TIMUIKitMessageTooltipState.mobileTooltipRowCount(6), 2);
    expect(
      TIMUIKitMessageTooltipState.estimateTelegramActionMenuHeight(5),
      68,
    );
    expect(
      TIMUIKitMessageTooltipState.estimateTelegramActionMenuHeight(6),
      120,
    );
  });

  test('mobile message context menu follows WeChat interaction contract', () {
    final detector = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_telegram_message_context_controller.dart',
    ).readAsStringSync();
    final tooltip = File(
      'third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_message_tooltip.dart',
    ).readAsStringSync();

    expect(detector, contains('const Duration(milliseconds: 500)'));
    expect(detector, contains('The live selected message remains'));
    expect(detector, isNot(contains('_buildExtractedMessageRow(extracted')));
    expect(tooltip, contains('scrollDirection: Axis.horizontal'));
    expect(tooltip, contains('mobileTooltipRows = 2'));
    expect(tooltip, contains('mobileTooltipItemsPerPage'));
    expect(tooltip, contains('mobileTooltipRowCount(children.length)'));
    expect(tooltip, contains('height: contentHeight'));
    expect(tooltip, contains('TUIKitInfoToast.show'));
    expect(tooltip, contains('TextAlign.center'));
  });
}
