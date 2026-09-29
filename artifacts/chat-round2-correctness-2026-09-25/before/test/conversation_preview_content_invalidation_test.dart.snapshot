import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_row_view.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_fingerprint.dart';

V2TimMessage _textMessage(String text) => V2TimMessage.fromJson({
      'message_msg_id': 'same-text-id',
      'message_server_time': 1700000000,
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..textElem = V2TimTextElem(text: text);

void main() {
  test('content fingerprint survives in-place SDK edits by value', () {
    final message = _textMessage('before');
    final captured = conversationPreviewFingerprint(message);
    final sameContent = _textMessage('before');
    expect(conversationPreviewFingerprint(sameContent), captured);
    message.textElem!.text = 'after';
    expect(conversationPreviewFingerprint(message), isNot(captured));
  });

  test('revocation details invalidate cache even with unchanged status', () {
    final message = _textMessage('revoked text')
      ..msgID = 'revoked'
      ..revokerInfo = (V2TimUserFullInfo()
        ..userID = 'admin'
        ..nickName = 'old name');
    final row = V2TimConversation(
        conversationID: 'group_preview', lastMessage: message);
    final before = ConversationRowView.fromConversation(row);
    final status = message.status;
    message.revokerInfo!.nickName = 'new name';
    expect(message.status, status);
    expect(ConversationRowView.fromConversation(row), isNot(before));
  });

  test('same custom message identity invalidates immutable row view on edit',
      () {
    final message = V2TimMessage.fromJson({
      'message_msg_id': 'same-id',
      'message_server_time': 1700000000,
      'message_risk_type_identified': 0,
    })
      ..elemType = 2
      ..customElem = V2TimCustomElem(data: '{"text":"before"}');
    final row = V2TimConversation(
      conversationID: 'c2c_preview',
      type: 1,
      userID: 'preview',
      lastMessage: message,
    );
    final before = ConversationRowView.fromConversation(row);
    message.customElem!.data = '{"text":"after"}';
    final after = ConversationRowView.fromConversation(row);
    expect(after, isNot(before));
    expect(ConversationRowView.fromConversation(row), after);
  });
}
