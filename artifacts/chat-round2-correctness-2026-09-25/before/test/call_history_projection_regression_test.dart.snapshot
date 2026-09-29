import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_custom_elem.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

V2TimMessage _callCustomMessage(String dataJson) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_server_time': 1784077600,
    'message_is_from_self': false,
    'message_status': 2,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message.elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
  message.customElem = V2TimCustomElem(data: dataJson);
  message.timestamp = 1784077600;
  message.userID = 'peer_a';
  message.sender = 'peer_a';
  message.isSelf = false;
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  V2TimMessage row(String id, String action) {
    return _callCustomMessage(jsonEncode({
      'businessID': 'lk_call',
      'callId': id,
      'action': action,
      'callerId': 'self_a',
      'calleeId': 'peer_a',
      'duration': 12,
    }))
      ..msgID = 'im_' + id;
  }

  test('different call IDs with equal duration both remain visible', () {
    final messages = [row('distinct-a', 'hangup'), row('distinct-b', 'hangup')];
    expect(
        CallBubbleDedupe.normalizeCallHistoryMessages(messages), hasLength(2));
  });

  test('unchanged IM payload is reprojected after canonical state changes', () {
    const id = 'projection-revision';
    final repository = CallResultRepository.instance;
    repository.save(CallResultRecord.fromSignaling(
      callId: id,
      action: 'invite',
      conversationId: 'c2c_peer_a',
    ));
    final messages = [row(id, 'hangup')];
    expect(CallBubbleDedupe.normalizeCallHistoryMessages(messages), isEmpty);
    repository.save(CallResultRecord.fromCallEnd(
      callId: id,
      conversationId: 'c2c_peer_a',
      callerUserId: 'self_a',
      operatorUserId: 'self_a',
      peerUserId: 'peer_a',
      reasonName: 'hangup',
      durationSec: 12,
    ));
    expect(
        CallBubbleDedupe.normalizeCallHistoryMessages(messages), hasLength(1));
  });
  test('completed cache does not turn an old invite into a terminal message', () {
    const id = 'old-invite-final-cache';
    CallResultRepository.instance.save(CallResultRecord.fromCallEnd(
      callId: id, conversationId: 'c2c_peer_a', callerUserId: 'self_a',
      operatorUserId: 'self_a', peerUserId: 'peer_a',
      reasonName: 'hangup', durationSec: 12,
    ));
    final invite = row(id, 'invite');
    expect(CallingMessageDataProvider(invite).shouldDisplayInHistory, isFalse);
    expect(CallBubbleDedupe.normalizeCallHistoryMessages([invite]), isEmpty);
  });

}
