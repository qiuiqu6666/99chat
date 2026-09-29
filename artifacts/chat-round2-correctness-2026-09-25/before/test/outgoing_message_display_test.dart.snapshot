import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_message_display.dart';

void main() {
  group('OutgoingMessageDisplay.shouldShowDeliveryCheck', () {
    test('shows check only for SEND_SUCC', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        isTrue,
      );
    });

    test('hides check for SEND_FAIL even when client assigned msgID existed', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
        ),
        isFalse,
      );
    });

    test('hides check for SENDING and status 0', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
        ),
        isFalse,
      );
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(status: 0),
        isFalse,
      );
    });

    test('SENDING plus msgID still has no delivery check', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
        ),
        isFalse,
      );
    });
  });

  group('OutgoingMessageDisplay.shouldShowReadUpgrade', () {
    test('group SEND_SUCC with 0/0 receipt stays single check', () {
      expect(
        OutgoingMessageDisplay.shouldShowDeliveryCheck(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        isTrue,
      );
      expect(
        OutgoingMessageDisplay.shouldShowReadUpgrade(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          groupReadCount: 0,
          groupUnreadCount: 0,
        ),
        isFalse,
      );
    });

    test('group all-read upgrades to double check', () {
      expect(
        OutgoingMessageDisplay.shouldShowReadUpgrade(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          groupReadCount: 3,
          groupUnreadCount: 0,
        ),
        isTrue,
      );
    });

    test('C2C peer read upgrades only after SEND_SUCC', () {
      expect(
        OutgoingMessageDisplay.shouldShowReadUpgrade(
          status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
          isC2cPeerRead: true,
        ),
        isFalse,
      );
      expect(
        OutgoingMessageDisplay.shouldShowReadUpgrade(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          isC2cPeerRead: true,
        ),
        isTrue,
      );
    });
  });
}
