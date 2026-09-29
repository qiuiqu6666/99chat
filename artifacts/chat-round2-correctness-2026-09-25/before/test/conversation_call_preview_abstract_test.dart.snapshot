import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/call_result_repository.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_text_elem.dart';

V2TimMessage _text({
  required String id,
  required String text,
  required int ts,
  String userID = 'preview_peer',
}) {
  final message = V2TimMessage.fromJson(<String, dynamic>{
    'message_msg_id': id,
    'message_server_time': ts,
    'message_is_from_self': true,
    'message_status': 2,
    'message_custom_str': '',
    'message_risk_type_identified': 0,
    'message_sender_group_member_info': <String, dynamic>{},
    'message_group_at_user_array': <String>[],
  });
  message
    ..msgID = id
    ..elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT
    ..textElem = V2TimTextElem(text: text)
    ..timestamp = ts
    ..userID = userID;
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty lastMessage shell uses outgoing cancel preview', () {
    CallResultRepository.instance.save(
      CallResultRecord(
        callId: 'abstract_cancel_1',
        conversationId: 'c2c_preview_peer',
        callerUserId: 'self',
        operatorUserId: 'self',
        peerUserId: 'preview_peer',
        protocolType: CallProtocolType.cancel,
        durationSec: 0,
        endedAtMs: 1700000000000,
        isOutgoing: true,
      ),
    );
    final shell = _text(id: 'shell', text: '', ts: 1700000000);
    expect(
      conversationCallPreviewIfAuthoritative(shell),
      anyOf('已取消', 'Cancelled'),
    );
    expect(
      conversationListLastMessageAbstract(shell, const []),
      anyOf('已取消', 'Cancelled'),
    );
  });

  test('newer plain text is not replaced by an older call result', () {
    CallResultRepository.instance.save(
      CallResultRecord(
        callId: 'abstract_cancel_old',
        conversationId: 'c2c_preview_peer_new',
        callerUserId: 'self',
        operatorUserId: 'self',
        peerUserId: 'preview_peer_new',
        protocolType: CallProtocolType.cancel,
        durationSec: 0,
        endedAtMs: 1000000000000,
        isOutgoing: true,
      ),
    );
    final newer = _text(
      id: 'txt',
      text: 'hello',
      ts: 1800000000,
      userID: 'preview_peer_new',
    );
    expect(conversationCallPreviewIfAuthoritative(newer), isNull);
    expect(conversationListLastMessageAbstract(newer, const []), isNull);
  });

  test('ringing record does not override plain text preview', () {
    CallResultRepository.instance.save(
      CallResultRecord.fromSignaling(
        callId: 'abstract_ringing_1',
        action: 'invite',
        conversationId: 'c2c_preview_peer_ringing',
        callerUserId: 'self',
        calleeUserId: 'preview_peer_ringing',
        peerUserId: 'preview_peer_ringing',
        isOutgoing: true,
      ),
    );
    final text = _text(
      id: 'txt_ringing',
      text: 'hello',
      ts: 1800000000,
      userID: 'preview_peer_ringing',
    );
    expect(
      conversationCallPreviewIfAuthoritative(
        text,
        conversationId: 'c2c_preview_peer_ringing',
      ),
      isNull,
    );
    expect(conversationListLastMessageAbstract(text, const []), isNull);
  });
}
