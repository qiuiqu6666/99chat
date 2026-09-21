import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

import '../services/conversation_local/conversation_local_store.dart';
import '../services/conversation_local/conversation_tab_store.dart';
import '../services/conversation_pin_flicker_log.dart';

/// Session and viewport coordination for the SDK conversation window.
/// Rows, loaded indices and paging cursors belong to ConversationTabStore.
class ChatSessionWindowState {
  ChatSessionWindowState._();

  static final ChatSessionWindowState instance = ChatSessionWindowState._();

  /// Monotonic identity for the currently bound account/session. Keeping it in
  /// the window state makes every window operation observe the same generation
  /// during logout and account switching.
  int sessionGeneration = 0;

  String get currentOwnerUserId =>
      ConversationLocalStore.instance.resolvedOwnerUserId();

  bool isCurrentSession(String ownerUserId, int generation) {
    return generation == sessionGeneration && ownerUserId == currentOwnerUserId;
  }

  int advanceSessionGeneration() => ++sessionGeneration;

  bool slidingWindowUserExpanded = false;
  Future<void>? hydrateInFlight;
  int hydrateRequestSerial = 0;
  Future<void>? uiPageLoadInFlight;
  // Pagination is type-specific. A single global gate lets a C2C request
  // suppress a group request during fast tab/list switching.
  final Map<int, Future<void>> typeUiPageLoadInFlight = <int, Future<void>>{};
  Future<void>? reloadInFlight;
  bool reloadDirty = false;
  String? reloadDirtyReason;
  double? Function()? listScrollOffsetProvider;
  bool Function()? isFeedScrolling;
  String? viewportAnchorConversationId;
  int hotHeadPhase2Generation = 0;
  ConversationPinReorderScrollHint? pinReorderScrollHint;
  bool pinReorderDeferred = false;

  /// SDK list indices are relative to the currently loaded typed window.
  int hydratedStartOffsetForType(int convType) => 0;

  int hydratedLengthForType(int convType) {
    if (convType != 1 && convType != 2) return 0;
    return ConversationTabStore.instance.countForType(convType);
  }

  int hydratedEndOffsetForType(int convType) {
    return hydratedLengthForType(convType);
  }

  bool isTypeIndexLiveHydrated(int convType, int index) {
    if ((convType != 1 && convType != 2) || index < 0) return false;
    return index < ConversationTabStore.instance.countForType(convType);
  }

  int? typeIndexOfConversationId(int convType, String conversationId) {
    final id = conversationId.trim();
    if (id.isEmpty || (convType != 1 && convType != 2)) return null;
    return ConversationTabStore.instance.typeIndexOf(convType, id);
  }

  int totalCountForType(int convType) {
    if (convType != 1 && convType != 2) return 0;
    final tabStore = ConversationTabStore.instance;
    final count = tabStore.countForType(convType);
    if (count <= 0) return 0;
    return tabStore.finishedForType(convType)
        ? count
        : count + ConversationTabStore.defaultPageSize;
  }

  V2TimConversation? conversationAtTypeIndex(int convType, int index) {
    if ((convType != 1 && convType != 2) || index < 0) return null;
    return ConversationTabStore.instance.atTypeIndex(convType, index);
  }

  void updateViewportAnchor(String? conversationID) {
    final id = conversationID?.trim() ?? '';
    viewportAnchorConversationId = id.isEmpty ? null : id;
  }

  static bool shouldBlockSnapshotWindowReload({
    required bool userExpanded,
    required bool scrolling,
    required bool pageLoadInFlight,
    required bool windowNonEmpty,
  }) {
    if (!windowNonEmpty) return false;
    return userExpanded || scrolling || pageLoadInFlight;
  }

  void reset() {
    slidingWindowUserExpanded = false;
    hydrateInFlight = null;
    hydrateRequestSerial = 0;
    uiPageLoadInFlight = null;
    typeUiPageLoadInFlight.clear();
    reloadInFlight = null;
    reloadDirty = false;
    reloadDirtyReason = null;
    listScrollOffsetProvider = null;
    isFeedScrolling = null;
    viewportAnchorConversationId = null;
    hotHeadPhase2Generation = 0;
    pinReorderScrollHint = null;
    pinReorderDeferred = false;
  }
}
