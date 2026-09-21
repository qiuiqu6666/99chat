import 'dart:async';

class ChatProjectionDeferredState {
  ChatProjectionDeferredState._();
  static final instance = ChatProjectionDeferredState._();

  bool uiNotifyPendingWhileActiveChat = false;
  bool uiNotifyPendingWhileScrolling = false;
  Timer? coalescedNotifyTimer;
  String? coalescedNotifyReason;
  Timer? scrollUiNotifyMaxDeferTimer;
  Timer? deferredPinReorderTimer;
  String? deferredPinConversationId;
  bool? deferredPinTargetPinned;
  int tabStoreCoalescePendingCount = 0;
  Timer? activeChatUiNotifyMaxDeferTimer;
  Timer? activeChatDirtyCatchUpTimer;
  bool activeChatDirtyCatchUpInFlight = false;
  final Set<String> activeChatDirtyIds = <String>{};
  int chatLeavePatchGeneration = 0;
  String? lastChatLeavePatchedId;
  DateTime? lastChatLeavePatchedAt;
  DateTime? postChatLeaveQuietUntil;

  void reset() {
    activeChatUiNotifyMaxDeferTimer?.cancel();
    activeChatDirtyCatchUpTimer?.cancel();
    coalescedNotifyTimer?.cancel();
    scrollUiNotifyMaxDeferTimer?.cancel();
    deferredPinReorderTimer?.cancel();
    coalescedNotifyTimer = null;
    coalescedNotifyReason = null;
    scrollUiNotifyMaxDeferTimer = null;
    deferredPinReorderTimer = null;
    deferredPinConversationId = null;
    deferredPinTargetPinned = null;
    tabStoreCoalescePendingCount = 0;
    activeChatUiNotifyMaxDeferTimer = null;
    activeChatDirtyCatchUpTimer = null;
    activeChatDirtyCatchUpInFlight = false;
    activeChatDirtyIds.clear();
    chatLeavePatchGeneration = 0;
    lastChatLeavePatchedId = null;
    lastChatLeavePatchedAt = null;
    postChatLeaveQuietUntil = null;
    uiNotifyPendingWhileActiveChat = false;
    uiNotifyPendingWhileScrolling = false;
  }
}
