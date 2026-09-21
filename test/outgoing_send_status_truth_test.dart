import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_send_status.dart';

void main() {
  group('OutgoingSendStatus.normalize', () {
    test('empty status is unconfirmed, never success', () {
      expect(OutgoingSendStatus.normalize(status: null), 0);
      expect(OutgoingSendStatus.normalize(status: 0), 0);
      expect(
        OutgoingSendStatus.normalize(status: null, fallback: 0),
        OutgoingSendStatus.unconfirmed,
      );
    });

    test('client msgID does not promote SENDING to success', () {
      expect(
        OutgoingSendStatus.normalize(
          status: MessageStatus.V2TIM_MSG_STATUS_SENDING,
          msgID: 'server-id',
        ),
        MessageStatus.V2TIM_MSG_STATUS_SENDING,
      );
    });

    test('keeps explicit success and fail', () {
      expect(
        OutgoingSendStatus.normalize(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      );
      expect(
        OutgoingSendStatus.normalize(
          status: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      );
    });
  });

  group('OutgoingSendStatus.mergeSelf', () {
    test('local FAIL is not lifted by echo SEND_SUCC', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
      );
    });

    test('local FAIL flips to SUCC only from final send code==0', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          fromFinalSendSuccess: true,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      );
    });

    test('SENDING plus SDK SEND_SUCC may reconcile to success', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: MessageStatus.V2TIM_MSG_STATUS_SENDING,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      );
    });

    test('UNKNOWN plus SDK SEND_SUCC may reconcile to success', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: OutgoingSendStatus.unconfirmed,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      );
    });

    test('confirmed SUCC is not regressed by SENDING echo', () {
      expect(
        OutgoingSendStatus.mergeSelf(
          previous: MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
          incoming: MessageStatus.V2TIM_MSG_STATUS_SENDING,
        ),
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
      );
    });
  });
}
