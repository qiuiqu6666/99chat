/// Conversation-sync flags for relationship reconcile fallback.
/// Kept out of ConversationSyncService to avoid import cycles.
class ImSdkRelationshipSyncAnchor {
  ImSdkRelationshipSyncAnchor._();

  static bool serverSyncPending = false;
  static bool hasHandledFinish = false;

  static void reset() {
    serverSyncPending = false;
    hasHandledFinish = false;
  }
}
