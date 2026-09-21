import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_message_display.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';

void main() {
  group('IM 20007 peer blacklist send fail', () {
    test('SEND_FAIL from 20007 has no delivery check', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
        ),
        isFalse,
      );
    });

    test('20007 SEND_FAIL is not lifted by self echo SEND_SUCC', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      );
    });

    test('code 0 SEND_SUCC still shows delivery check', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        isTrue,
      );
    });
  });
}
