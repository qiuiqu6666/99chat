import 'conversation_preview_store.dart';

class ChatHistoryState {
  ChatHistoryState._();
  static final instance = ChatHistoryState._();
  Future<int> clearedAtMs(String conversationId) =>
      ConversationPreviewStore.instance.historyClearedAtMs(conversationId);
}
