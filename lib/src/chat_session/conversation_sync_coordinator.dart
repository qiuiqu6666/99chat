import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_demo/src/chat_session/chat_session_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';

class ConversationSyncCoordinator {
  ConversationSyncCoordinator._();
  static final instance = ConversationSyncCoordinator._();

  Future<void> patchConversationLastMessage({
    required String conversationID,
    required V2TimMessage message,
  }) =>
      ConversationSyncService.instance.patchConversationLastMessage(
        conversationID: conversationID,
        message: message,
      );

  Future<void> refreshConversationItem(String conversationID) =>
      ConversationSyncService.instance.refreshConversationItem(conversationID);

  void schedulePostPopCoalesceWindow({String? conversationID}) =>
      ConversationSyncService.instance.schedulePostPopCoalesceWindow(
        conversationID: conversationID,
      );

  Future<bool> patchConversationAfterChatLeave(
    String conversationID, {
    String reason = 'chat_leave',
  }) =>
      ChatSessionController.instance.patchConversationAfterChatLeave(
        conversationID,
        reason: reason,
      );

  void flushDeferredUiNotifyIfNeeded({String reason = 'scroll_end'}) =>
      ChatSessionController.instance.flushDeferredUiNotifyIfNeeded(
        reason: reason,
      );
}
