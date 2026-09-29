import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';

class ConversationPreviewStore {
  ConversationPreviewStore._();
  static final instance = ConversationPreviewStore._();

  Future<int> historyClearedAtMs(String conversationId) =>
      ConversationLocalStore.instance.historyClearedAtMs(conversationId);

  Future<V2TimConversation?> conversationById(String conversationId) async {
    return ConversationLocalStore.instance.conversationById(conversationId);
  }

  static int messageTimestampMs(V2TimMessage? message) {
    return ConversationLocalStore.messageTimestampMs(message);
  }
}
