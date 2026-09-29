import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_patch_hydrator.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

void main() {
  test('only patches missing authoritative unread or preview need hydration',
      () {
    V2TimConversation patch({int? unread, V2TimMessage? lastMessage}) =>
        V2TimConversation(
          conversationID: 'c2c_peer',
          type: 1,
          userID: 'peer',
          unreadCount: unread,
          lastMessage: lastMessage,
        );

    expect(
      ConversationPatchHydrator.needsHydration(patch()),
      isTrue,
    );
    expect(
      ConversationPatchHydrator.needsHydration(patch(unread: 0)),
      isFalse,
    );
    expect(
      ConversationPatchHydrator.needsHydration(patch(unread: 1)),
      isTrue,
    );
    expect(
      ConversationPatchHydrator.needsHydration(
        patch(
          unread: 1,
          lastMessage: V2TimMessage.fromJson(<String, dynamic>{
            'message_msg_id': 'm1',
            'message_server_time': 1,
            'message_risk_type_identified': 0,
          }),
        ),
      ),
      isFalse,
    );
  });
}
