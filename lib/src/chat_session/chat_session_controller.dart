import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'conversation_preview_store.dart';
import 'chat_history_state.dart';
import 'conversation_projection_writer.dart';
import 'conversation_projection_reason.dart';
import 'conversation_projection_fingerprint.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_mutation_event.dart';
import 'chat_projection_deferred_state.dart';
import 'chat_session_window_state.dart';
import 'chat_session_window_controller.dart';
import 'conversation_window_slide_result.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_flags.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_perf_gate_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_leave_trace.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_preview_text_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_feed_perf.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_tab_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_aggregate.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_unread_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_pin_flicker_log.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_unread_utils.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/src/utils/revoked_message_preview.dart';
import 'package:tencent_cloud_chat_demo/utils/conversation_last_message_prefer.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/calling_message/calling_message_data_provider.dart';
import 'package:tencent_cloud_chat_demo/utils/custom_message/custom_last_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/services/display_name_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/outgoing_visible_probe.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitConversation/archived_conversation_store.dart';

class ChatSessionController extends ChangeNotifier {
  ChatSessionController._() {
    windowController = ChatSessionWindowController(
      state: windowState,
      host: _ControllerWindowHost(this),
    );
  }
  static final instance = ChatSessionController._();

  /// Stable row fingerprint exposed at the session boundary. Feed widgets use
  /// this value to skip rebuilding rows whose visible state did not change.
  static int conversationUiFingerprintHash(V2TimConversation conversation) =>
      ConversationProjectionFingerprint.hash(conversation);

  /// String fingerprint kept for non-hot-path integrations and tests.
  static String conversationUiFingerprint(V2TimConversation conversation) =>
      ConversationProjectionFingerprint.string(conversation);

  static bool listsEqualForUi(
    List<V2TimConversation> a,
    List<V2TimConversation> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (conversationUiFingerprintHash(a[i]) !=
          conversationUiFingerprintHash(b[i])) {
        return false;
      }
    }
    return true;
  }

  final ConversationTabStore _tabStore = ConversationTabStore.instance;
  final ChatProjectionDeferredState deferredState =
      ChatProjectionDeferredState.instance;
  final ChatSessionWindowState windowState = ChatSessionWindowState.instance;
  late final ChatSessionWindowController windowController;

  /// Narrow notification channels used by the conversation feed migration.
  final ValueNotifier<int> feedRevision = ValueNotifier<int>(0);
  // Selected business folders may contain SDK rows outside the main window.
  // Forward account-listener deletions even when there is no main row to remove.
  final ValueNotifier<List<String>> sdkDeletedConversationIds =
      ValueNotifier<List<String>>(const []);
  final Map<String, ValueNotifier<int>> _rowRevisions =
      <String, ValueNotifier<int>>{};
  final Map<String, VoidCallback> _rowViewBridges = <String, VoidCallback>{};
  Map<String, int> _publishedSdkFingerprints = <String, int>{};
  ConversationProjectionDiff? _pendingSdkProjectionDiff;
  bool _pendingSdkFullDiff = false;
  bool _sdkProjectionPublicationPending = false;
  bool _tabStoreProjectionDirty = false;
  bool _pendingTabStoreStructureChanged = false;
  final Set<String> _pendingTabStoreChangedIds = <String>{};
  int _tabStoreProjectionAdoptions = 0;

  @visibleForTesting
  int get tabStoreProjectionAdoptionsForTest => _tabStoreProjectionAdoptions;

  @override
  void notifyListeners() {
    _flushPendingTabStoreProjection();
    // SDK paging bypasses ConversationProjectionWriter. Publish its changes
    // to the same narrow channels the mounted feed/rows actually listen to,
    // after the existing scroll and active-chat notification gates permit it.
    if (_sdkProjectionPublicationPending) {
      _sdkProjectionPublicationPending = false;
      final directDiff = _pendingSdkFullDiff ? null : _pendingSdkProjectionDiff;
      _pendingSdkFullDiff = false;
      _pendingSdkProjectionDiff = null;
      if (directDiff != null) {
        for (final id in {
          ...directDiff.rowChangedIds,
          ...directDiff.insertedIds,
        }) {
          final row = _tabStore.conversationForId(id);
          if (row != null) {
            _publishedSdkFingerprints[id] = conversationUiFingerprintHash(row);
          }
        }
        _publishProjectionDiff(
          directDiff,
          reason: 'sdk_projection_delta',
        );
        super.notifyListeners();
        return;
      }
      final next = <String, int>{
        for (final row in conversations)
          row.conversationID.trim(): conversationUiFingerprintHash(row),
      };
      final previous = _publishedSdkFingerprints;
      _publishedSdkFingerprints = next;
      _publishProjectionDiff(
        ConversationProjectionDiff(
          insertedIds: next.keys.toSet().difference(previous.keys.toSet()),
          removedIds: previous.keys.toSet().difference(next.keys.toSet()),
          rowChangedIds: {
            for (final entry in next.entries)
              if (previous.containsKey(entry.key) &&
                  previous[entry.key] != entry.value)
                entry.key,
          },
          orderChanged: !listEquals(previous.keys.toList(), next.keys.toList()),
        ),
        reason: 'sdk_projection_pending',
      );
    }
    super.notifyListeners();
  }

  ValueListenable<int> rowRevisionOf(String conversationId) {
    final id = conversationId.trim();
    return _rowRevisions.putIfAbsent(id, () {
      final notifier = ValueNotifier<int>(0);
      void onRowView() {
        notifier.value++;
      }

      _rowViewBridges[id] = onRowView;
      ConversationTabStore.instance.rowViewListenable(id).addListener(onRowView);
      return notifier;
    });
  }

  /// Visible feed slots cache their child until this notifier or the
  /// fingerprint changes. Identity commits that do not patch the SDK row
  /// still need this bump so AnimatedBuilder repaints.
  void bumpRowRevisions(Iterable<String> conversationIds) {
    for (final raw in conversationIds) {
      final id = raw.trim();
      if (id.isEmpty) {
        continue;
      }
      _rowRevisions[id]?.value++;
    }
  }

  void _disposeRowRevision(String id) {
    final bridge = _rowViewBridges.remove(id);
    if (bridge != null) {
      ConversationTabStore.instance.rowViewListenable(id).removeListener(bridge);
    }
    _rowRevisions.remove(id)?.dispose();
  }

  V2TimConversation? currentConversationById(String conversationId) =>
      _tabStore.conversationForId(conversationId);

  void _publishProjectionDiff(
    ConversationProjectionDiff diff, {
    String reason = 'unspecified',
  }) {
    final rowOnly = diff.rowChangedIds
        .difference(diff.insertedIds)
        .difference(diff.removedIds);
    ConversationFeedPerf.increment('projection_diff', reason: reason);
    ConversationFeedPerf.increment(
      'projection_inserted',
      amount: diff.insertedIds.length,
    );
    ConversationFeedPerf.increment(
      'projection_removed',
      amount: diff.removedIds.length,
    );
    ConversationFeedPerf.increment(
      'projection_row_only',
      amount: rowOnly.length,
    );
    if (diff.visibilityChanged) {
      ConversationFeedPerf.increment('projection_visibility_changed');
    }
    if (diff.orderChanged) {
      ConversationFeedPerf.increment('projection_order_changed');
    }
    for (final id in diff.removedIds) {
      _disposeRowRevision(id);
    }
    if (diff.feedChanged) {
      feedRevision.value++;
      ConversationFeedPerf.increment('feed_revision', reason: reason);
      ConversationFeedPerf.gauge('feedRevision', feedRevision.value);
    }
    for (final id in rowOnly) {
      _rowRevisions[id]?.value++;
    }
    ConversationFeedPerf.gauge(
      'structureRevision',
      _tabStore.structureRevision,
    );
  }

  bool _firstScreenReady = false;
  bool _tabStoreBridgeAttached = false;
  int _notifySuppressDepth = 0;
  bool _notifyPendingWhileSuppressed = false;
  int _lastPeerDisplayAppliedRevision = -1;
  bool _archiveListenersAttached = false;
  Future<void>? _archiveSyncInFlight;
  final Set<String> _pendingArchiveRestoredIds = <String>{};
  final Set<String> _pendingArchiveRemovedIds = <String>{};

  List<V2TimConversation> get conversations {
    _flushPendingTabStoreProjection();
    return _tabStore.conversations;
  }

  int get structureRevision {
    _flushPendingTabStoreProjection();
    return _tabStore.structureRevision;
  }

  int get contentRevision {
    _flushPendingTabStoreProjection();
    return _tabStore.contentRevision;
  }

  bool get hasLocalData {
    _flushPendingTabStoreProjection();
    return _tabStore.hasLocalData;
  }

  bool get slidingWindowUserExpanded => windowState.slidingWindowUserExpanded;
  bool get isDeferringPinReorder => windowState.pinReorderDeferred;
  @visibleForTesting
  bool get isDeferringPinReorderForTest => isDeferringPinReorder;
  @visibleForTesting
  int get canonicalLookupFallbacksForTest => 0;
  bool get firstScreenReady => _firstScreenReady;

  /// Window-facing API. Window algorithms, lifecycle state, and projection
  /// reads all live behind this session boundary.
  int hydratedStartOffsetForType(int convType) {
    _flushPendingTabStoreProjection();
    return windowState.hydratedStartOffsetForType(convType);
  }

  int hydratedLengthForType(int convType) {
    _flushPendingTabStoreProjection();
    return windowState.hydratedLengthForType(convType);
  }

  int hydratedEndOffsetForType(int convType) {
    _flushPendingTabStoreProjection();
    return windowState.hydratedEndOffsetForType(convType);
  }

  bool isTypeIndexLiveHydrated(int convType, int index) {
    _flushPendingTabStoreProjection();
    return windowState.isTypeIndexLiveHydrated(convType, index);
  }

  int? typeIndexOfConversationId(int convType, String conversationId) =>
      _windowTypeIndexOfConversationId(convType, conversationId);

  int totalCountForType(int convType) => _windowTotalCountForType(convType);

  V2TimConversation? conversationAtTypeIndex(int convType, int index) =>
      _windowConversationAtTypeIndex(convType, index);

  int? _windowTypeIndexOfConversationId(int convType, String conversationId) {
    {
      _ensureTabStoreBridgeAttached();
    }
    _flushPendingTabStoreProjection();
    return windowState.typeIndexOfConversationId(convType, conversationId);
  }

  int _windowTotalCountForType(int convType) {
    {
      _ensureTabStoreBridgeAttached();
    }
    _flushPendingTabStoreProjection();
    return windowState.totalCountForType(convType);
  }

  V2TimConversation? _windowConversationAtTypeIndex(int convType, int index) {
    {
      _ensureTabStoreBridgeAttached();
    }
    _flushPendingTabStoreProjection();
    return windowState.conversationAtTypeIndex(convType, index);
  }

  bool get isUiPageLoadInFlight => windowState.uiPageLoadInFlight != null;

  bool get isFeedScrollingNow => windowState.isFeedScrolling?.call() ?? false;

  double? Function()? get listScrollOffsetProvider =>
      windowState.listScrollOffsetProvider;
  set listScrollOffsetProvider(double? Function()? value) =>
      windowState.listScrollOffsetProvider = value;

  bool Function()? get isFeedScrolling => windowState.isFeedScrolling;
  set isFeedScrolling(bool Function()? value) =>
      windowState.isFeedScrolling = value;

  bool shouldAdmitToUiWindow(
    V2TimConversation incoming, {
    List<V2TimConversation>? current,
  }) =>
      _shouldAdmitToUiWindow(incoming, current ?? conversations);

  bool get shouldBlockSnapshotWindowReloadNow =>
      ChatSessionWindowState.shouldBlockSnapshotWindowReload(
        userExpanded: windowState.slidingWindowUserExpanded,
        scrolling: isFeedScrollingNow,
        pageLoadInFlight: windowState.uiPageLoadInFlight != null,
        windowNonEmpty: conversations.isNotEmpty,
      );

  static bool shouldBlockSnapshotWindowReload({
    required bool userExpanded,
    required bool scrolling,
    required bool pageLoadInFlight,
    required bool windowNonEmpty,
  }) {
    return ChatSessionWindowState.shouldBlockSnapshotWindowReload(
      userExpanded: userExpanded,
      scrolling: scrolling,
      pageLoadInFlight: pageLoadInFlight,
      windowNonEmpty: windowNonEmpty,
    );
  }

  String? get viewportAnchorConversationId =>
      windowState.viewportAnchorConversationId;

  void updateViewportAnchor(String? conversationID) {
    windowState.updateViewportAnchor(conversationID);
  }

  Future<void> ensureTypeIndexHydrated({
    required int convType,
    required int centerIndex,
    bool forceReload = false,
    bool allowWindowJump = false,
    bool forceNotify = false,
  }) {
    return windowController.ensureTypeIndexHydrated(
      convType: convType,
      centerIndex: centerIndex,
      forceReload: forceReload,
      allowWindowJump: allowWindowJump,
      forceNotify: forceNotify,
    );
  }

  Future<void> refreshTypeTotals() => windowController.refreshTypeTotals();

  /// Explicitly attaches the SDK-primary reconciliation bridge. Normal
  /// production entry points attach it lazily; this public boundary is kept
  /// for page/test integrations that seed TabStore before the first read.
  void ensureTabStoreBridgeAttached() => _ensureTabStoreBridgeAttached();

  ConversationPinReorderScrollHint? takePinReorderScrollHint() =>
      _takePinReorderScrollHint();

  ConversationPinReorderScrollHint? _takePinReorderScrollHint() {
    final hint = windowState.pinReorderScrollHint;
    windowState.pinReorderScrollHint = null;
    return hint;
  }

  Future<void> applySdkProjectionPatch({
    required ConversationStoreProjectionReason reason,
    required List<V2TimConversation> upserted,
    List<String> deletedIds = const [],
    Set<String> forceAdmitIds = const <String>{},
    Map<String, Set<ConversationMutationField>> changedFieldMasks =
        const <String, Set<ConversationMutationField>>{},
  }) =>
      applyProjectionBatch(
        reason: reason.name,
        upserted: upserted,
        deletedIds: deletedIds,
        forceAdmitIds: forceAdmitIds,
        changedFieldMasks: changedFieldMasks,
      );

  /// Restore the SDK projection after an explicit local mirror purge.
  Future<void> refreshSdkProjectionAfterPurge() => restoreSdkWindow(
        reason: ConversationStoreProjectionReason.localPurge,
      );

  void beginSuppressNotify() {
    _notifySuppressDepth++;
  }

  void endSuppressNotify() {
    if (_notifySuppressDepth <= 0) return;
    _notifySuppressDepth--;
    if (_notifySuppressDepth != 0 || !_notifyPendingWhileSuppressed) return;
    _notifyPendingWhileSuppressed = false;
    _notifyControllerProjection(reason: 'end_suppress');
  }

  V2TimConversation? findConversationByLastMessageId(String messageId) {
    final target = messageId.trim();
    if (target.isEmpty) return null;
    bool matches(V2TimMessage message) {
      if (lastMessageMatchesRevokeTarget(message, target)) return true;
      final localId = message.id?.toString().trim() ?? '';
      return localId.isNotEmpty && localId == target;
    }

    for (final conversation in conversations) {
      final last = conversation.lastMessage;
      if (last != null && matches(last)) return conversation;
    }
    {
      for (final type in const [1, 2]) {
        for (final conversation
            in ConversationTabStore.instance.itemsForType(type)) {
          final last = conversation.lastMessage;
          if (last != null && matches(last)) return conversation;
        }
      }
    }
    return null;
  }

  Future<void> refreshEmptySdkPrimaryTypeProjection({
    required int convType,
    String reason = 'empty_sdk_type',
  }) async {
    final type = convType == 2 ? 2 : 1;
    _ensureTabStoreBridgeAttached();
    final tabStore = ConversationTabStore.instance;
    if (tabStore.countForType(type) > 0) return;
    // Explicit SDK recovery never depends on whether its SQLite mirror is ready.
    await tabStore.loadFirstPage(convType: type);
  }

  @visibleForTesting
  Future<void> refreshEmptySdkPrimaryTypeProjectionForTest({
    required int convType,
    String reason = 'test',
  }) {
    return refreshEmptySdkPrimaryTypeProjection(
      convType: convType,
      reason: reason,
    );
  }

  void ensureArchiveChangeListenersAttached() {
    _ensureTabStoreBridgeAttached();
    if (_archiveListenersAttached) return;
    _archiveListenersAttached = true;
    archivedConversationC2cIDsNotifier.addListener(_onArchivedIdsChanged);
    archivedConversationGroupIDsNotifier.addListener(_onArchivedIdsChanged);
  }

  void _onArchivedIdsChanged() {
    unawaited(syncMainListAfterArchiveChange(reason: 'archived_ids_changed'));
  }

  bool get isPostChatLeaveQuiet {
    final until = deferredState.postChatLeaveQuietUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration get postChatLeaveQuietRemaining {
    final until = deferredState.postChatLeaveQuietUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> restoreProjection({
    required ConversationStoreProjectionReason reason,
    int? visibleConvType,
  }) async {
    StartupPerfLog.markTagged(
      'restoreProjection_enter',
      category: 'cold_start',
      details: <String, Object>{
        'reason': reason.name,
        'visibleConvType': visibleConvType ?? 0,
      },
    );
    // Never seed the first frame from the application SQLite mirror. Its
    // contents may lag the IM SDK after a fresh launch. Ask the SDK-backed
    // TabStore for the first page and let realtime callbacks fill it in.
    final generation = windowState.sessionGeneration;
    if (archivedConversationPersistToDisk) {
      await ensureArchivedConversationIDsLoaded();
      if (generation != windowState.sessionGeneration) return;
    }
    await _primeSdkWindowDirect(
      reason: reason,
      visibleConvType: visibleConvType,
    );
    if (generation != windowState.sessionGeneration) return;
    final tabs = ConversationTabStore.instance;
    _firstScreenReady = visibleConvType == 1 || visibleConvType == 2
        ? tabs.primedForType(visibleConvType!)
        : tabs.primedForType(1) && tabs.primedForType(2);
  }

  Future<void> syncMainListAfterArchiveChange({
    Iterable<String> restoredIds = const [],
    Iterable<String> removedIds = const [],
    String reason = 'archive_change',
  }) {
    if (!ConversationPerfFlags.archiveChangeMainListSyncEnabled &&
        !ConversationPerfFlags.purgeUiOnArchiveChangeEnabled) {
      return Future<void>.value();
    }
    for (final raw in restoredIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      _pendingArchiveRestoredIds.add(id);
      _pendingArchiveRemovedIds.remove(id);
    }
    for (final raw in removedIds) {
      final id = raw.trim();
      if (id.isEmpty || _pendingArchiveRestoredIds.contains(id)) continue;
      _pendingArchiveRemovedIds.add(id);
    }
    final existing = _archiveSyncInFlight;
    if (ConversationPerfFlags.archiveChangeSyncSingleFlight &&
        existing != null) {
      return existing;
    }
    final task = _runArchiveMainListSync(reason: reason);
    _archiveSyncInFlight = task;
    return task.whenComplete(() {
      if (identical(_archiveSyncInFlight, task)) _archiveSyncInFlight = null;
    });
  }

  @visibleForTesting
  bool get archiveSyncInFlightForTest => _archiveSyncInFlight != null;

  @visibleForTesting
  int get pendingArchiveRestoredCountForTest =>
      _pendingArchiveRestoredIds.length;

  Future<void> _runArchiveMainListSync({required String reason}) async {
    var loops = 0;
    do {
      loops++;
      final restored = _pendingArchiveRestoredIds.toList(growable: false);
      final removed = _pendingArchiveRemovedIds.toList(growable: false);
      _pendingArchiveRestoredIds.clear();
      _pendingArchiveRemovedIds.clear();
      {
        _ensureTabStoreBridgeAttached();
        final tabStore = ConversationTabStore.instance;
        tabStore.purgeArchived();
        if (removed.isNotEmpty) tabStore.applyDeleted(removed);
        var restoredApplied = 0;
        if (restored.isNotEmpty) {
          try {
            restoredApplied =
                await tabStore.restoreSdkConversationsByIds(restored);
          } catch (error, stack) {
            debugPrint('archive restore sdk-primary failed: $error\n$stack');
          }
        }
        await refreshTypeTotals();
        ConversationPerfGateLog.log(
          'archive_main_sync',
          extras: <String, Object?>{
            'reason': reason,
            'loop': loops,
            'sdkPrimary': true,
            'restoredReq': restored.length,
            'restoredApplied': restoredApplied,
            'removedHint': removed.length,
          },
        );
      }
    } while (_pendingArchiveRestoredIds.isNotEmpty ||
        _pendingArchiveRemovedIds.isNotEmpty);
  }

  void applyPeerDisplayNameFromStore(
    String userId, {
    int? busRevision,
  }) {
    if (busRevision != null) {
      if (busRevision == _lastPeerDisplayAppliedRevision) return;
      _lastPeerDisplayAppliedRevision = busRevision;
    }
    final id = ChatIdFormat.rawUserUid(userId);
    if (id.isEmpty) return;
    final name = DisplayNameStore.instance.c2c(id)?.trim() ?? '';
    if (name.isEmpty) return;
    applyC2cShowNamesBatch(<String, String>{'c2c_$id': name});
  }

  Future<void> applyCommittedProjection(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    Set<String> forceAdmitIds = const <String>{},
  }) =>
      applyProjectionBatch(
        reason: 'committed_batch',
        upserted: batch.upsertedSnapshots,
        deletedIds: batch.deletedCanonicalIds,
        forceAdmitIds: forceAdmitIds,
        changedFieldMasks: batch.changedFieldMasks,
        committedUnreadDeltas:
            batch.unreadProjectionComplete == null ? null : batch.unreadDeltas,
        unreadProjectionComplete: batch.unreadProjectionComplete,
      );

  /// Test seam for callers that used the retired Notifier write API. Keeping
  /// this seam at the session boundary lets tests exercise the same writer as
  /// production without making the compatibility adapter a write owner.
  @visibleForTesting
  Future<void> applyConversationsFromStoreForTest({
    required List<V2TimConversation> upserted,
    List<String> deletedIds = const [],
    Set<String> forceAdmitIds = const <String>{},
  }) {
    return applyProjectionBatch(
      reason: 'test_apply',
      upserted: upserted,
      deletedIds: deletedIds,
      forceAdmitIds: forceAdmitIds,
    );
  }

  @visibleForTesting
  Future<void> applyCommittedBatchForTest(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    Set<String> forceAdmitIds = const <String>{},
  }) {
    return applyCommittedProjection(batch, forceAdmitIds: forceAdmitIds);
  }

  @visibleForTesting
  Future<void> applyWindowPatchesForTest({
    required List<V2TimConversation> upserted,
    List<String> deletedIds = const [],
  }) {
    return applyProjectionBatch(
      reason: 'window_patch',
      upserted: upserted,
      deletedIds: deletedIds,
    );
  }

  /// Test fixtures seed the same SDK adapter used by the production feed.
  @visibleForTesting
  void replaceProjectionForTest(List<V2TimConversation> value) {
    clearSessionProjection(notify: false);
    final store = ConversationTabStore.instance;
    beginSuppressNotify();
    store.clear();
    store.notifyColdStartEnded();
    _ensureTabStoreBridgeAttached();
    for (final type in const [1, 2]) {
      // This entire method is the test fixture adapter.
      // ignore: invalid_use_of_visible_for_testing_member
      store.setItemsForTest(
        convType: type,
        items: value
            .where((row) =>
                (ConversationUnreadUtils.isGroupConversation(row) ? 2 : 1) ==
                type)
            .toList(),
        finished: true,
      );
    }
    endSuppressNotify();
  }

  /// Test-only naming compatibility for fixtures that seed a session
  /// projection. Production callers must use [applyProjectionBatch].
  @visibleForTesting
  void setConversationsForTest(List<V2TimConversation> value) {
    replaceProjectionForTest(value);
  }

  /// Single projection write boundary. Legacy callers can still enter through
  /// the notifier adapter during migration, but the writer and projection
  /// state are owned here.
  Future<void> applyProjectionBatch({
    required String reason,
    required List<V2TimConversation> upserted,
    List<String> deletedIds = const [],
    Set<String> forceAdmitIds = const <String>{},
    Map<String, Set<ConversationMutationField>> changedFieldMasks =
        const <String, Set<ConversationMutationField>>{},
    List<ConversationUiUnreadDelta>? committedUnreadDeltas,
    bool? unreadProjectionComplete,
    Set<String> explicitDraftIds = const <String>{},
  }) {
    {
      _ensureTabStoreBridgeAttached();
      final isDraftRelated = explicitDraftIds.isNotEmpty ||
          changedFieldMasks.values.any(
            (fields) => fields.contains(ConversationMutationField.draft),
          );
      String focusedConversationId = '';
      String? focusedDraftText;
      var focusedDraftLen = -1;
      if (isDraftRelated) {
        for (final row in upserted) {
          if (ConversationDraftLeaveTrace.isFocused(row.conversationID)) {
            focusedConversationId = row.conversationID;
            focusedDraftText = row.draftText;
            focusedDraftLen = row.draftText == null
                ? -1
                : row.draftText!.trim().length;
            break;
          }
        }
        if (focusedConversationId.isEmpty && upserted.isNotEmpty) {
          focusedConversationId = upserted.first.conversationID;
        }
        ConversationDraftLeaveTrace.stage(
          'apply_projection_batch_start',
          conversationId: focusedConversationId,
          draftText: focusedDraftText,
          extras: <String, Object?>{
            'reason': reason,
            'explicitDraft': explicitDraftIds.length,
            'draftLen': focusedDraftLen,
          },
        );
      }
      ConversationTabStore.instance.applyCommittedViewBatch(
        ConversationUiSnapshotBatch<V2TimConversation>(
          upsertedSnapshots: upserted,
          deletedCanonicalIds: deletedIds,
          structureChanged: deletedIds.isNotEmpty,
          changedFieldMasks: changedFieldMasks,
          commitGeneration: 0,
          unreadDeltas:
              committedUnreadDeltas ?? const <ConversationUiUnreadDelta>[],
          unreadProjectionComplete: unreadProjectionComplete,
        ),
        forceAdmitIds: forceAdmitIds,
        explicitDraftIds: explicitDraftIds,
      );
      if (isDraftRelated) {
        ConversationDraftLeaveTrace.stage(
          'apply_projection_batch_done',
          conversationId: focusedConversationId,
          draftText: focusedDraftText,
          extras: <String, Object?>{
            'reason': reason,
            'explicitDraft': explicitDraftIds.length,
            'draftLen': focusedDraftLen,
          },
        );
      }
      return Future<void>.value();
    }
  }

  /// Applies a realtime SDK snapshot to the pending UI overlay before its
  /// durable commit completes. This is intentionally a controller boundary:
  /// callers must not write [ConversationTabStore] directly. The following
  /// committed batch reconciles the same row through the projection writer.
  void applyPendingRealtimeProjection(
    List<V2TimConversation> conversations, {
    required String reason,
    bool preserveOrder = false,
  }) {
    if (conversations.isEmpty) return;

    _ensureTabStoreBridgeAttached();
    // 项 7：仅在冷启动期（_coldStartWindowActive=true）让 SDK push 直塞路径
    // 不重排，避免冷启动期间 SDK 大量推送导致双路并发 sort。
    // 稳态期保持 false，确保新消息立刻跳顶（用户感知不变）。
    final effectivePreserveOrder =
        preserveOrder || ConversationTabStore.instance.isColdStartWindowActive;
    ConversationUnreadAggregate.instance.applySdkConversations(conversations);
    ConversationTabStore.instance.applyPatches(
      conversations,
      reason: reason,
      explicitUnreadIds: conversations
          .map((conversation) => conversation.conversationID)
          .toSet(),
      allowNew: true,
      preserveOrder: effectivePreserveOrder,
    );
  }

  /// Removes SDK-deleted conversations from the visible projection before
  /// the durable mirror commit finishes. The later committed delete is
  /// idempotent and only confirms this optimistic projection.
  void applyPendingRealtimeDeletion(List<String> conversationIds) {
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return;
    _ensureTabStoreBridgeAttached();
    ConversationTabStore.instance.applyDeleted(ids);
    sdkDeletedConversationIds.value = List<String>.unmodifiable(ids);
  }

  /// Local business edits update the SDK adapter and publish one row change.
  void applyRecvOptLocally({
    required String conversationID,
    required int recvOpt,
    V2TimConversation? snapshot,
  }) {
    final id = conversationID.trim();
    if (id.isEmpty) return;
    final row = _tabStore.conversationForId(id) ?? snapshot;
    if (row == null) return;
    _ensureTabStoreBridgeAttached();
    _tabStore.applyPatches([
      _cloneConversationWithRecvOpt(row, recvOpt: recvOpt),
    ], reason: 'recv_opt_local', preserveOrder: true);
  }

  void applyShowNameLocally({
    required String conversationID,
    required String showName,
  }) {
    final id = conversationID.trim();
    final name = showName.trim();
    if (id.isEmpty || name.isEmpty) return;
    final unchanged = conversations.any(
      (row) =>
          MessageConversationId.sameConversation(row.conversationID, id) &&
          (row.showName?.trim() ?? '') == name,
    );
    if (unchanged) return;
    applyC2cShowNamesBatch(<String, String>{id: name});
  }

  void applyC2cShowNamesBatch(Map<String, String> names) {
    if (names.isEmpty) return;
    final rows = <V2TimConversation>[];
    final ids = <String>{};
    for (final entry in names.entries) {
      final name = entry.value.trim();
      final row = _tabStore.conversationForId(entry.key);
      if (row == null || name.isEmpty) continue;
      ids.add(row.conversationID);
      rows.add(_cloneConversationWithShowName(row, showName: name));
    }
    if (rows.isEmpty) return;
    _ensureTabStoreBridgeAttached();
    final revision = _tabStore.contentRevision;
    _tabStore.applyPatches(rows,
        reason: 'c2c_show_name_batch', preserveOrder: true);
    // DisplayNameStore can change the cell even if the SDK row text agrees.
    if (_tabStore.contentRevision == revision) {
      _tabStore.notifyDisplayFields(ids, reason: 'c2c_show_name_batch_store');
    }
  }

  void applyFaceUrlLocally(
      {required String conversationID, required String faceUrl}) {
    final row = _tabStore.conversationForId(conversationID);
    final url = faceUrl.trim();
    if (row == null || url.isEmpty) return;
    _ensureTabStoreBridgeAttached();
    _tabStore.applyPatches([_cloneConversationWithFaceUrl(row, faceUrl: url)],
        reason: 'face_url_local', preserveOrder: true);
  }

  void _applyPinnedWithDeferredReorderFromController({
    required String conversationID,
    required bool isPinned,
    V2TimConversation? snapshot,
    Duration reorderDelay = const Duration(milliseconds: 180),
    double? listScrollOffset,
    bool forceDeferred = false,
  }) {
    final id = conversationID.trim();
    final row = _tabStore.conversationForId(id) ?? snapshot;
    if (id.isEmpty || row == null) return;
    _ensureTabStoreBridgeAttached();
    var orderKey = row.orderkey;
    if (!isPinned) {
      final active = ConversationLocalStore.activeTimeMs(row);
      if (active > 0) orderKey = active;
    }
    _tabStore.setPinReorderDeferred(true);
    _tabStore.applyPatches([
      _cloneConversationWithPin(row, isPinned: isPinned, orderkey: orderKey),
    ], reason: 'pin_local', preserveOrder: true);
    deferredState.deferredPinConversationId = id;
    deferredState.deferredPinTargetPinned = isPinned;
    if (!(forceDeferred || ConversationPerfFlags.pinDeferredReorderEnabled) ||
        reorderDelay <= Duration.zero) {
      deferredState.deferredPinReorderTimer?.cancel();
      _flushDeferredPinReorder();
      return;
    }
    _scheduleDeferredPinReorder(reorderDelay);
  }

  void _scheduleDeferredPinReorder(Duration delay) {
    deferredState.deferredPinReorderTimer?.cancel();
    windowState.pinReorderDeferred = true;
    deferredState.deferredPinReorderTimer = Timer(
        delay <= Duration.zero ? Duration.zero : delay,
        _flushDeferredPinReorder);
  }

  void _flushDeferredPinReorder() {
    deferredState.deferredPinReorderTimer = null;
    windowState.pinReorderDeferred = false;
    final id = deferredState.deferredPinConversationId ?? '';
    final pinned = deferredState.deferredPinTargetPinned == true;
    deferredState.deferredPinConversationId = null;
    deferredState.deferredPinTargetPinned = null;
    final from =
        ConversationPinFlickerLog.indexOfConversation(conversations, id);
    _tabStore.setPinReorderDeferred(false);
    final to = ConversationPinFlickerLog.indexOfConversation(conversations, id);
    windowState.pinReorderScrollHint = from >= 0 && to >= 0 && from != to
        ? ConversationPinReorderScrollHint(
            conversationID: id,
            fromIndex: from,
            toIndex: to,
            isPinned: pinned,
            scrollMode: ConversationPinScrollMode.keepViewport)
        : null;
    _notifyControllerProjection(reason: 'pin_phase_reorder');
  }

  Future<void> _applyCommittedPinProjectionFromController(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    required String conversationID,
    required bool isPinned,
    double? listScrollOffset,
  }) {
    if (batch.isEmpty) return Future<void>.value();
    final id = conversationID.trim();
    V2TimConversation? snapshot;
    for (final row in batch.upsertedSnapshots) {
      if (MessageConversationId.sameConversation(row.conversationID, id)) {
        snapshot = row;
        break;
      }
    }
    if (snapshot == null ||
        batch.upsertedSnapshots.length != 1 ||
        batch.deletedCanonicalIds.isNotEmpty) {
      return applyProjectionBatch(
        reason: 'committed_batch',
        upserted: batch.upsertedSnapshots,
        deletedIds: batch.deletedCanonicalIds,
        changedFieldMasks: batch.changedFieldMasks,
        committedUnreadDeltas:
            batch.unreadProjectionComplete == null ? null : batch.unreadDeltas,
        unreadProjectionComplete: batch.unreadProjectionComplete,
      );
    }
    applyPinnedWithDeferredReorder(
      conversationID: id,
      isPinned: isPinned,
      snapshot: snapshot,
      listScrollOffset: listScrollOffset,
    );
    return Future<void>.value();
  }

  void applyPinnedWithDeferredReorder({
    required String conversationID,
    required bool isPinned,
    V2TimConversation? snapshot,
    Duration reorderDelay = const Duration(milliseconds: 180),
    double? listScrollOffset,
    bool forceDeferred = false,
  }) {
    _applyPinnedWithDeferredReorderFromController(
      conversationID: conversationID,
      isPinned: isPinned,
      snapshot: snapshot,
      reorderDelay: reorderDelay,
      listScrollOffset: listScrollOffset,
      forceDeferred: forceDeferred,
    );
  }

  Future<void> applyCommittedPinProjection(
    ConversationUiSnapshotBatch<V2TimConversation> batch, {
    required String conversationID,
    required bool isPinned,
    double? listScrollOffset,
  }) {
    return _applyCommittedPinProjectionFromController(
      batch,
      conversationID: conversationID,
      isPinned: isPinned,
      listScrollOffset: listScrollOffset,
    );
  }

  bool replaceLastMessageAfterDeleteLocally({
    required String conversationID,
    required Set<String> deletedMessageIds,
    V2TimMessage? replacement,
  }) {
    final id = conversationID.trim();
    final targets = deletedMessageIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (id.isEmpty || targets.isEmpty) return false;
    V2TimConversation? source;
    for (final target in targets) {
      final match = findConversationByLastMessageId(target);
      if (match != null &&
          MessageConversationId.sameConversation(match.conversationID, id)) {
        source = match;
        break;
      }
    }
    if (source == null) return false;
    final patched = _cloneConversationWithPin(
      source,
      isPinned: source.isPinned == true,
    )..lastMessage = replacement;
    _ensureTabStoreBridgeAttached();
    _tabStore.applyPatches([patched],
        reason: 'last_message_delete_optimistic',
        explicitLastMessageIds: {id},
        preserveOrder: true);
    return true;
  }

  void clearLastMessageLocally(String conversationID) {
    final row = _tabStore.conversationForId(conversationID);
    if (row == null || row.lastMessage == null) return;
    final order = ConversationLocalStore.displayTimestampMs(row);
    final patched = _cloneConversationWithPin(row,
        isPinned: row.isPinned == true,
        orderkey: order > 0 ? order : row.orderkey)
      ..lastMessage = null;
    _ensureTabStoreBridgeAttached();
    _tabStore.applyPatches([patched],
        reason: 'clear_last_message_local',
        explicitLastMessageIds: {row.conversationID},
        preserveOrder: true);
  }

  void clearSessionProjection({bool notify = true}) {
    sdkDeletedConversationIds.value = const [];
    _pendingSdkFullDiff = false;
    _publishedSdkFingerprints.clear();
    _pendingSdkProjectionDiff = null;
    _sdkProjectionPublicationPending = false;
    _tabStoreProjectionDirty = false;
    _pendingTabStoreStructureChanged = false;
    _tabStoreProjectionAdoptions = 0;
    _firstScreenReady = false;
    _notifySuppressDepth = 0;
    _notifyPendingWhileSuppressed = false;
    _lastPeerDisplayAppliedRevision = -1;
    _pendingArchiveRestoredIds.clear();
    _pendingArchiveRemovedIds.clear();
    for (final id in _rowRevisions.keys.toList()) {
      _disposeRowRevision(id);
    }
    feedRevision.value++;
    ConversationFeedPerf.increment(
      'feed_revision',
      reason: 'clear_session_projection',
    );
    ConversationFeedPerf.gauge('feedRevision', feedRevision.value);
    _archiveSyncInFlight = null;
    if (_tabStoreBridgeAttached) {
      ConversationTabStore.instance.removeListener(_onTabStoreChanged);
      _tabStoreBridgeAttached = false;
    }
    ConversationTabStore.instance.clear();
    deferredState.coalescedNotifyTimer?.cancel();
    deferredState.coalescedNotifyTimer = null;
    deferredState.coalescedNotifyReason = null;
    deferredState.scrollUiNotifyMaxDeferTimer?.cancel();
    deferredState.scrollUiNotifyMaxDeferTimer = null;
    deferredState.activeChatUiNotifyMaxDeferTimer?.cancel();
    deferredState.activeChatUiNotifyMaxDeferTimer = null;
    deferredState.activeChatDirtyCatchUpTimer?.cancel();
    deferredState.activeChatDirtyCatchUpTimer = null;
    deferredState.activeChatDirtyCatchUpInFlight = false;
    deferredState.activeChatDirtyIds.clear();
    deferredState.chatLeavePatchGeneration = 0;
    deferredState.lastChatLeavePatchedId = null;
    deferredState.lastChatLeavePatchedAt = null;
    deferredState.postChatLeaveQuietUntil = null;
    deferredState.uiNotifyPendingWhileScrolling = false;
    deferredState.uiNotifyPendingWhileActiveChat = false;
    deferredState.deferredPinConversationId = null;
    deferredState.deferredPinTargetPinned = null;
    windowState.advanceSessionGeneration();
    windowState.reset();
    ConversationUnreadGuard.clearAllOptimisticUnread();
    ConversationUnreadAggregate.instance.clearSession();
    if (notify) {
      notifyListeners();
    }
  }

  void zeroUnreadLocally(String conversationID) {
    zeroUnreadLocallyMany(<String>[conversationID]);
  }

  void zeroUnreadLocallyMany(
    Iterable<String> conversationIds, {
    bool forceAggregateRefresh = false,
  }) {
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      if (forceAggregateRefresh) {
        ConversationUnreadAggregate.instance.scheduleRefresh(
          reason: 'zero_unread_many_empty',
        );
      }
      return;
    }
    ConversationUnreadGuard.clearOptimisticUnreadMany(ids);
    {
      _ensureTabStoreBridgeAttached();
      ConversationTabStore.instance.zeroUnreadLocallyMany(ids);
      if (forceAggregateRefresh) {
        ConversationUnreadAggregate.instance.scheduleRefresh(
          reason: 'zero_unread_many_sdk_primary',
        );
      }
      return;
    }
  }

  void _bumpWindowRevisions(
      {required bool orderOrMembershipChanged, String reason = 'unspecified'}) {
    _tabStore.invalidateDisplay(structureChanged: orderOrMembershipChanged);
  }

  Future<void> restoreSdkWindow({
    ConversationStoreProjectionReason reason =
        ConversationStoreProjectionReason.sdkProjectionRestore,
    int? visibleConvType,
  }) =>
      windowController.restoreSdkWindow(
        reason: reason,
        visibleConvType: visibleConvType,
      );

  /// Prime missing SDK pages while preserving loaded rows and paging cursors.
  Future<void> _primeSdkWindowDirect({
    ConversationStoreProjectionReason? reason,
    int? visibleConvType,
  }) async {
    _ensureTabStoreBridgeAttached();
    final types = visibleConvType == 1 || visibleConvType == 2
        ? <int>[visibleConvType!]
        : const <int>[1, 2];
    final tabStore = ConversationTabStore.instance;
    final generation = windowState.sessionGeneration;
    for (final type in types) {
      if (generation != windowState.sessionGeneration) return;
      final loadedBefore = tabStore.countForType(type);
      final finishedBefore = tabStore.finishedForType(type);
      final cursorBefore = tabStore.pageCursorForType(type)?.conversationID;
      final action =
          loadedBefore == 0 && !finishedBefore ? 'prime' : 'preserve';
      await tabStore.ensurePrimed(convType: type, caller: 'restoreProjection');
      if (generation != windowState.sessionGeneration) return;
      ConversationPerfGateLog.log(
        'sdk_primary_restore_preserve_view',
        extras: <String, Object?>{
          'reason': reason?.name ?? 'sdk_primary_direct',
          'convType': type,
          'generation': windowState.sessionGeneration,
          'currentGeneration': windowState.sessionGeneration,
          'action': action,
          'loadedBefore': loadedBefore,
          'loadedAfter': tabStore.countForType(type),
          'finishedBefore': finishedBefore,
          'finishedAfter': tabStore.finishedForType(type),
          'cursorBefore': cursorBefore,
          'cursorAfter': tabStore.pageCursorForType(type)?.conversationID,
          'ownerBound': false,
        },
      );
    }
  }

  Future<bool> patchConversationAfterChatLeave(
    String conversationId, {
    String reason = 'chat_leave',
  }) async {
    final leftId = conversationId.trim();
    final now = DateTime.now();
    if (ConversationPerfFlags.chatLeaveFlushDedupeEnabled &&
        leftId.isNotEmpty &&
        deferredState.lastChatLeavePatchedId == leftId &&
        deferredState.lastChatLeavePatchedAt != null &&
        now.difference(deferredState.lastChatLeavePatchedAt!) <
            const Duration(seconds: 2)) {
      ConversationPerfGateLog.log(
        'chat_leave_flush_skipped_dedupe',
        extras: <String, Object?>{'leftId': leftId, 'reason': reason},
      );
      ConversationDraftLeaveTrace.stage(
        'leave_overlay_skipped',
        conversationId: leftId,
        extras: const <String, Object?>{'reason': 'dedupe'},
      );
      return false;
    }
    deferredState.chatLeavePatchGeneration++;
    deferredState.lastChatLeavePatchedId = leftId.isEmpty ? null : leftId;
    deferredState.lastChatLeavePatchedAt = now;
    deferredState.postChatLeaveQuietUntil = now.add(
      ConversationPerfFlags.postChatLeaveCatchUpDelay >
              const Duration(milliseconds: 400)
          ? ConversationPerfFlags.postChatLeaveCatchUpDelay
          : const Duration(milliseconds: 1200),
    );
    final hadPendingNotify = deferredState.uiNotifyPendingWhileScrolling ||
        deferredState.uiNotifyPendingWhileActiveChat;
    deferredState.scrollUiNotifyMaxDeferTimer?.cancel();
    deferredState.scrollUiNotifyMaxDeferTimer = null;
    deferredState.activeChatUiNotifyMaxDeferTimer?.cancel();
    deferredState.activeChatUiNotifyMaxDeferTimer = null;
    deferredState.uiNotifyPendingWhileActiveChat = false;
    _ensureTabStoreBridgeAttached();
    ConversationTabStore.instance.flushDeferredCommittedProjection(
      reason: reason,
    );

    if (!ConversationPerfFlags.chatLeavePatchLeftOnlyEnabled) {
      flushDeferredUiNotifyIfNeeded(reason: reason);
      return true;
    }
    ConversationPerfGateLog.log(
      'chat_leave_patch_left',
      extras: <String, Object?>{
        'leftId': leftId,
        'reason': reason,
        'dirty': deferredState.activeChatDirtyIds.length,
        'generation': deferredState.chatLeavePatchGeneration,
      },
    );
    if (leftId.isNotEmpty) {
      deferredState.activeChatDirtyIds.removeWhere(
        (id) => MessageConversationId.sameConversation(id, leftId),
      );
      V2TimConversation? projected =
          conversations.cast<V2TimConversation?>().firstWhere(
                (row) =>
                    row != null &&
                    MessageConversationId.sameConversation(
                        row.conversationID, leftId),
                orElse: () => null,
              );
      V2TimConversation? persisted;
      final needsPersistedDraft = projected == null ||
          (projected.draftText?.trim().isEmpty ?? true);
      if (needsPersistedDraft) {
        try {
          persisted =
              await ConversationLocalStore.instance.conversationById(leftId);
        } catch (_) {
          persisted = null;
        }
      }
      final local = overlayDraftForChatLeave(
        projected: projected,
        persisted: persisted,
      );
      final explicitDraftIds = local == null
          ? const <String>{}
          : explicitDraftIdsForChatLeave(
              conversationId: leftId,
              snapshot: local,
            );
      ConversationDraftLeaveTrace.stage(
        'leave_overlay',
        conversationId: leftId,
        draftText: local?.draftText,
        extras: <String, Object?>{
          'projectedEmpty': projected == null ||
              (projected.draftText?.trim().isEmpty ?? true),
          'persistedEmpty': persisted == null ||
              (persisted.draftText?.trim().isEmpty ?? true),
          'overlayEmpty':
              local == null || (local.draftText?.trim().isEmpty ?? true),
          'willExplicit': explicitDraftIds.isNotEmpty,
        },
      );
      if (local != null) {
        await applyProjectionBatch(
          reason: 'chat_leave',
          upserted: <V2TimConversation>[local],
          explicitDraftIds: explicitDraftIds,
        );
      } else {
        _notifyControllerProjection(reason: 'chat_leave_left_miss');
      }
    }
    ConversationUnreadAggregate.instance.scheduleRefresh(
      reason: 'chat_leave_left_only',
    );
    _flushPendingUiNotifyAfterChatLeave(
      reason: reason,
      hadPendingNotify: hadPendingNotify,
    );
    _scheduleActiveChatDirtyCatchUp();
    return true;
  }

  void _flushPendingUiNotifyAfterChatLeave({
    required String reason,
    required bool hadPendingNotify,
  }) {
    deferredState.coalescedNotifyTimer?.cancel();
    deferredState.coalescedNotifyTimer = null;
    deferredState.coalescedNotifyReason = null;
    deferredState.uiNotifyPendingWhileScrolling = false;
    deferredState.uiNotifyPendingWhileActiveChat = false;
    if (hadPendingNotify) {
      _bumpWindowRevisions(
        orderOrMembershipChanged: true,
        reason: 'chat_leave_pending_notify',
      );
    }
    ConversationPerfGateLog.log(
      'chat_leave_flush_pending_notify',
      extras: <String, Object?>{
        'reason': reason,
        'hadPending': hadPendingNotify ? 1 : 0,
        'count': conversations.length,
      },
    );
    notifyListeners();
  }

  void flushDeferredUiNotifyIfNeeded({String reason = 'scroll_end'}) {
    final isChatLeave = reason.startsWith('chat_leave');
    if (isChatLeave && ConversationPerfFlags.chatLeavePatchLeftOnlyEnabled) {
      deferredState.activeChatUiNotifyMaxDeferTimer?.cancel();
      deferredState.activeChatUiNotifyMaxDeferTimer = null;
      deferredState.uiNotifyPendingWhileActiveChat = false;
      ConversationPerfGateLog.log(
        'ui_notify_flush_redirect_leave',
        extras: <String, Object?>{'reason': reason},
      );
      return;
    }
    deferredState.scrollUiNotifyMaxDeferTimer?.cancel();
    deferredState.scrollUiNotifyMaxDeferTimer = null;
    deferredState.activeChatUiNotifyMaxDeferTimer?.cancel();
    deferredState.activeChatUiNotifyMaxDeferTimer = null;
    final pending = deferredState.uiNotifyPendingWhileScrolling ||
        deferredState.uiNotifyPendingWhileActiveChat;
    if (!pending) return;
    deferredState.uiNotifyPendingWhileScrolling = false;
    deferredState.uiNotifyPendingWhileActiveChat = false;
    ConversationPerfGateLog.log(
      'ui_notify_flush',
      extras: <String, Object?>{'reason': reason},
    );
    notifyListeners();
    if (reason == 'scroll_end' &&
        ConversationPerfFlags.activeChatDirtyCatchUpEnabled &&
        deferredState.activeChatDirtyIds.isNotEmpty &&
        !ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat) {
      _scheduleActiveChatDirtyCatchUp(forceNow: true);
    }
  }

  /// Chat 页 pop 发起瞬间（过渡动画之前）同步交还列表 UI：刷出聊天期间被
  /// `deferTabStoreProjectionWhileActiveChat` 缓冲的投影与被
  /// `deferUiNotifyWhileActiveChat` 挂起的通知，让返回动画第一帧就是新预览。
  ///
  /// 不 `leave` 注册表、不触碰 chat_leave 的 dedupe / 草稿状态：dispose 里
  /// 「草稿落库后再 patch」的兜底链路必须原样执行。
  void flushDeferredListUiBeforeChatLeave({
    required String conversationId,
    String reason = 'chat_pop_started',
  }) {
    final leftId = conversationId.trim();
    _ensureTabStoreBridgeAttached();
    final tabStore = ConversationTabStore.instance;
    final hadDeferredProjection = tabStore.hasDeferredCommittedProjection;
    if (hadDeferredProjection) {
      tabStore.flushDeferredCommittedProjection(reason: reason);
    }
    // 投影 flush 可能经 _onTabStoreChanged 再次置 pending，需在其后读取。
    final pendingAfter = deferredState.uiNotifyPendingWhileActiveChat ||
        deferredState.uiNotifyPendingWhileScrolling;
    if (!hadDeferredProjection && !pendingAfter) {
      ConversationPerfGateLog.log(
        'chat_pop_flush_noop',
        extras: <String, Object?>{'leftId': leftId, 'reason': reason},
      );
      return;
    }
    deferredState.activeChatUiNotifyMaxDeferTimer?.cancel();
    deferredState.activeChatUiNotifyMaxDeferTimer = null;
    deferredState.uiNotifyPendingWhileActiveChat = false;
    deferredState.uiNotifyPendingWhileScrolling = false;
    _bumpWindowRevisions(orderOrMembershipChanged: true, reason: reason);
    ConversationPerfGateLog.log(
      'chat_pop_flush_pending_notify',
      extras: <String, Object?>{
        'leftId': leftId,
        'reason': reason,
        'hadProjection': hadDeferredProjection ? 1 : 0,
        'hadPending': pendingAfter ? 1 : 0,
      },
    );
    if (_notifySuppressDepth > 0) {
      _notifyPendingWhileSuppressed = true;
      return;
    }
    notifyListeners();
  }

  void _scheduleActiveChatDirtyCatchUp({bool forceNow = false}) {
    if (!ConversationPerfFlags.activeChatDirtyCatchUpEnabled) {
      deferredState.activeChatDirtyIds.clear();
      return;
    }
    if (deferredState.activeChatDirtyIds.isEmpty) return;
    deferredState.activeChatDirtyCatchUpTimer?.cancel();
    final delay = forceNow
        ? Duration.zero
        : ConversationPerfFlags.postChatLeaveCatchUpDelay;
    deferredState.activeChatDirtyCatchUpTimer = Timer(delay, () {
      deferredState.activeChatDirtyCatchUpTimer = null;
      unawaited(_runActiveChatDirtyCatchUp());
    });
  }

  Future<void> _runActiveChatDirtyCatchUp() async {
    if (deferredState.activeChatDirtyCatchUpInFlight ||
        deferredState.activeChatDirtyIds.isEmpty) {
      return;
    }
    if (ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat ||
        isFeedScrollingNow) {
      _scheduleActiveChatDirtyCatchUp();
      return;
    }
    deferredState.activeChatDirtyCatchUpInFlight = true;
    final dirty = deferredState.activeChatDirtyIds.toList(growable: false);
    deferredState.activeChatDirtyIds.clear();
    final size = ConversationPerfFlags.activeChatDirtyCatchUpBatchSize > 0
        ? ConversationPerfFlags.activeChatDirtyCatchUpBatchSize
        : 20;
    try {
      for (var offset = 0; offset < dirty.length; offset += size) {
        if (ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat ||
            isFeedScrollingNow) {
          deferredState.activeChatDirtyIds.addAll(dirty.skip(offset));
          _scheduleActiveChatDirtyCatchUp();
          break;
        }
        final end = math.min(offset + size, dirty.length);
        final ids = dirty.sublist(offset, end);
        final rows = await ConversationLocalStore.instance.conversationsByIds(
          ids,
          caller: 'active_chat_dirty_catch_up_controller',
        );
        if (rows.isNotEmpty) {
          await applyProjectionBatch(
            reason: 'active_chat_dirty_catch_up',
            upserted: rows,
            explicitDraftIds: ids.toSet(),
          );
        }
        if (end < dirty.length) await Future<void>.delayed(Duration.zero);
      }
    } catch (error, stack) {
      debugPrint('activeChatDirtyCatchUp failed: $error\n$stack');
    } finally {
      deferredState.activeChatDirtyCatchUpInFlight = false;
    }
  }

  Future<int> historyClearedAtMs(String id) =>
      ChatHistoryState.instance.clearedAtMs(id);

  Future<V2TimConversation?> conversationById(String id) =>
      ConversationPreviewStore.instance.conversationById(id);

  static int messageTimestampMs(V2TimMessage? message) =>
      ConversationPreviewStore.messageTimestampMs(message);

  Future<void> patchConversationLastMessage({
    required String conversationID,
    required V2TimMessage message,
  }) =>
      ConversationSyncService.instance.patchConversationLastMessage(
        conversationID: conversationID,
        message: message,
      );

  Future<void> refreshConversationItem(String id) =>
      ConversationSyncService.instance.refreshConversationItem(id);

  void _applyToCompatibilityTabStore({
    required String conversationID,
    required V2TimMessage message,
    required bool bumpUnread,
    required bool updateUnreadAggregate,
  }) {
    for (final type in const [1, 2]) {
      final rows = ConversationTabStore.instance.itemsForType(type).where(
            (candidate) => MessageConversationId.sameConversation(
              candidate.conversationID,
              conversationID,
            ),
          );
      if (rows.isEmpty) continue;
      final existing = rows.first;
      var preferred = ConversationLastMessagePrefer.preferLastMessage(
        existing: existing.lastMessage,
        incoming: message,
      );
      if (_isHistoryVisibleLocalCallBubble(message) &&
          (existing.lastMessage == null ||
              (message.timestamp ?? 0) >=
                  (existing.lastMessage!.timestamp ?? 0))) {
        preferred = message;
      }
      if (preferred == null ||
          !ConversationUnreadGuard.lastMessageAdvanced(
            before: existing.lastMessage,
            after: preferred,
          )) {
        return;
      }
      final patched = _cloneConversationWithPin(
        existing,
        isPinned: existing.isPinned == true,
        orderkey: (preferred.timestamp ?? 0) > 0
            ? preferred.timestamp
            : existing.orderkey,
      );
      patched.lastMessage = preferred;
      final oldNotifiable = _notifiableUnreadForRow(existing);
      if (bumpUnread &&
          ConversationUnreadGuard.shouldOptimisticBumpUnread(
            conversationId: conversationID,
            message: message,
          )) {
        patched.unreadCount = (patched.unreadCount ?? 0) + 1;
        ConversationUnreadGuard.recordOptimisticUnread(
          conversationId: conversationID,
          message: message,
          unreadCount: patched.unreadCount ?? 0,
        );
      }
      ConversationTabStore.instance.applyPatches(
        <V2TimConversation>[patched],
        reason: 'last_message_local',
        explicitLastMessageIds: <String>{conversationID},
      );
      final newNotifiable = _notifiableUnreadForRow(patched);
      if (updateUnreadAggregate && oldNotifiable != newNotifiable) {
        ConversationUnreadAggregate.instance.applyNotifiableDeltas(
          <ConversationUnreadDelta>[
            ConversationUnreadDelta(
              conversationKey: patched.conversationID,
              isGroup: type == 2,
              oldNotifiable: oldNotifiable,
              newNotifiable: newNotifiable,
            ),
          ],
        );
      }
      return;
    }
    OutgoingVisibleProbe.log(
      'preview_apply_skip',
      conversationID: conversationID,
      message: message,
      extras: <String, Object?>{'reason': 'empty_legacy_list'},
    );
  }

  int _notifiableUnreadForRow(V2TimConversation conversation) {
    return ConversationUnreadUtils.notifiableUnreadForAggregate(
      conversation,
      archivedC2c: archivedConversationC2cIDsNotifier.value,
      archivedGroup: archivedConversationGroupIDsNotifier.value,
    );
  }

  void _putStrongPreviewCache(String conversationID, V2TimMessage message) {
    if (!ConversationLastMessagePrefer.isStrongLastMessage(message)) return;
    final preview = strongConversationPreviewTextForCache(message);
    if (preview == null || preview.isEmpty) return;
    ConversationPreviewTextCache.instance.putStrong(
      conversationID,
      preview,
      messageKey: conversationPreviewCacheMessageKey(message),
    );
  }

  static bool _isLocalCallBubble(V2TimMessage message) {
    final id = message.msgID?.trim() ?? '';
    return id.startsWith('local_call_bubble_');
  }

  static bool _isHistoryVisibleLocalCallBubble(V2TimMessage message) {
    if (!_isLocalCallBubble(message)) {
      return false;
    }
    try {
      return CallingMessageDataProvider(message).shouldDisplayInHistory;
    } catch (_) {
      return false;
    }
  }

  static bool conversationNeedsUiReorderAfterPatch(
    List<V2TimConversation> list,
    int index,
  ) {
    if (index < 0 || index >= list.length) return false;
    final current = list[index];
    if (index > 0 &&
        ConversationLocalStore.compareConversationsForUi(
              current,
              list[index - 1],
            ) <
            0) {
      return true;
    }
    if (index + 1 < list.length &&
        ConversationLocalStore.compareConversationsForUi(
              current,
              list[index + 1],
            ) >
            0) {
      return true;
    }
    return false;
  }

  /// Leave-patch snapshot: keep the in-memory lastMessage/unread row, but take
  /// a persisted SQLite draft when the live projection still has none.
  /// Passing an empty in-memory row with [explicitDraftIds] would otherwise
  /// publish a blank draft while `local_draft_text` already has the text
  /// (visible only after a cold start).
  @visibleForTesting
  static V2TimConversation? overlayDraftForChatLeave({
    V2TimConversation? projected,
    V2TimConversation? persisted,
  }) {
    final base = projected ?? persisted;
    if (base == null) {
      return null;
    }
    final persistedDraft = persisted?.draftText?.trim() ?? '';
    if (persistedDraft.isEmpty) {
      return base;
    }
    if ((projected?.draftText?.trim() ?? '') == persistedDraft) {
      return base;
    }
    final cloned = _cloneConversationWithPin(
      base,
      isPinned: base.isPinned == true,
      orderkey: base.orderkey,
    );
    cloned.draftText = persisted!.draftText;
    cloned.draftTimestamp = persisted.draftTimestamp;
    return cloned;
  }

  @visibleForTesting
  static Set<String> explicitDraftIdsForChatLeave({
    required String conversationId,
    required V2TimConversation snapshot,
  }) {
    final id = conversationId.trim();
    if (id.isEmpty || (snapshot.draftText?.trim().isEmpty ?? true)) {
      return const <String>{};
    }
    return <String>{id};
  }

  static V2TimConversation _cloneConversationWithPin(
    V2TimConversation source, {
    required bool isPinned,
    int? orderkey,
  }) {
    final cloned = V2TimConversation(
      conversationID: source.conversationID,
      type: source.type,
      userID: source.userID,
      groupID: source.groupID,
      showName: source.showName,
      faceUrl: source.faceUrl,
      recvOpt: source.recvOpt,
      unreadCount: source.unreadCount ?? 0,
      lastMessage: source.lastMessage,
      draftText: source.draftText,
      draftTimestamp: source.draftTimestamp,
      isPinned: isPinned,
      orderkey: orderkey ?? source.orderkey,
      groupType: source.groupType,
      groupAtInfoList: source.groupAtInfoList,
      c2cReadTimestamp: source.c2cReadTimestamp,
      groupReadSequence: source.groupReadSequence,
    );
    cloned.c2cReadTimestamp = source.c2cReadTimestamp;
    cloned.groupReadSequence = source.groupReadSequence;
    return cloned;
  }

  static V2TimConversation _cloneConversationWithRecvOpt(
    V2TimConversation source, {
    required int recvOpt,
  }) {
    final cloned = _cloneConversationWithPin(
      source,
      isPinned: source.isPinned == true,
      orderkey: source.orderkey,
    );
    cloned.recvOpt = recvOpt;
    return cloned;
  }

  static V2TimConversation _cloneConversationWithShowName(
    V2TimConversation source, {
    required String showName,
  }) {
    final cloned = _cloneConversationWithPin(
      source,
      isPinned: source.isPinned == true,
      orderkey: source.orderkey,
    );
    cloned.showName = showName;
    return cloned;
  }

  static V2TimConversation _cloneConversationWithFaceUrl(
    V2TimConversation source, {
    required String faceUrl,
  }) {
    final cloned = _cloneConversationWithPin(
      source,
      isPinned: source.isPinned == true,
      orderkey: source.orderkey,
    );
    cloned.faceUrl = faceUrl;
    return cloned;
  }

  void applyLastMessageLocally({
    required String conversationID,
    required V2TimMessage message,
    bool bumpUnread = false,
    bool updateUnreadAggregate = true,
    bool allowReorder = true,
  }) {
    ConversationFeedPerf.increment('last_message_apply');
    final id = conversationID.trim();
    if (id.isEmpty) {
      ConversationFeedPerf.increment(
        'last_message_outcome',
        reason: 'empty_id',
      );
      OutgoingVisibleProbe.log(
        'preview_apply_skip',
        conversationID: id,
        message: message,
        extras: <String, Object?>{'reason': 'empty_id'},
      );
      return;
    }

    final current = conversations;
    if (current.isEmpty) {
      ConversationFeedPerf.increment(
        'last_message_outcome',
        reason: 'compatibility_store',
      );
      _applyToCompatibilityTabStore(
        conversationID: id,
        message: message,
        bumpUnread: bumpUnread,
        updateUnreadAggregate: updateUnreadAggregate,
      );
      return;
    }

    final patchedIndex = _tabStore.displayIndexOf(id);
    if (patchedIndex < 0) {
      ConversationFeedPerf.increment(
        'last_message_outcome',
        reason: 'missing_conversation',
      );
      OutgoingVisibleProbe.log(
        'preview_apply_noop',
        conversationID: id,
        message: message,
        extras: const <String, Object?>{'reason': 'missing_conversation'},
      );
      return;
    }
    final source = current[patchedIndex];
    final existing = source.lastMessage;
    var preferred = ConversationLastMessagePrefer.preferLastMessage(
      existing: existing,
      incoming: message,
    );
    if (_isHistoryVisibleLocalCallBubble(message) &&
        (existing == null ||
            (message.timestamp ?? 0) >= (existing.timestamp ?? 0))) {
      preferred = message;
    }
    if (preferred == null) {
      ConversationFeedPerf.increment(
        'last_message_outcome',
        reason: 'noop',
      );
      return;
    }
    final beforeRevokeFp = revokedLastMessageFingerprint(existing);
    final afterRevokeFp = revokedLastMessageFingerprint(preferred);
    if (existing != null &&
        identical(preferred, existing) &&
        beforeRevokeFp == afterRevokeFp &&
        !isRevokedMessage(message)) {
      ConversationFeedPerf.increment(
        'last_message_outcome',
        reason: 'noop',
      );
      OutgoingVisibleProbe.log(
        'preview_apply_noop',
        conversationID: id,
        message: message,
      );
      return;
    }

    final patched = _cloneConversationWithPin(
      source,
      isPinned: source.isPinned == true,
      orderkey: allowReorder && (preferred.timestamp ?? 0) > 0
          ? preferred.timestamp
          : source.orderkey,
    );
    patched.lastMessage = preferred;
    ConversationUnreadDelta? unreadDelta;
    final oldNotifiable = _notifiableUnreadForRow(source);
    if (bumpUnread &&
        ConversationUnreadGuard.lastMessageAdvanced(
          before: existing,
          after: preferred,
        ) &&
        ConversationUnreadGuard.shouldOptimisticBumpUnread(
          conversationId: id,
          message: message,
        )) {
      patched.unreadCount = (patched.unreadCount ?? 0) + 1;
      ConversationUnreadGuard.recordOptimisticUnread(
        conversationId: id,
        message: message,
        unreadCount: patched.unreadCount ?? 0,
      );
      final newNotifiable = _notifiableUnreadForRow(patched);
      if (oldNotifiable != newNotifiable) {
        unreadDelta = ConversationUnreadDelta(
          conversationKey: patched.conversationID,
          isGroup: ConversationUnreadUtils.isGroupConversation(patched),
          oldNotifiable: oldNotifiable,
          newNotifiable: newNotifiable,
        );
      }
    }
    _putStrongPreviewCache(id, preferred);
    _ensureTabStoreBridgeAttached();
    _tabStore.applyPatches(
      [patched],
      reason: 'last_message_local',
      preserveOrder: !allowReorder,
      explicitLastMessageIds: <String>{id},
    );
    if (updateUnreadAggregate && unreadDelta != null) {
      ConversationUnreadAggregate.instance.applyNotifiableDeltas(
        <ConversationUnreadDelta>[unreadDelta],
      );
    }
  }

  void schedulePostPopCoalesceWindow({String? conversationID}) =>
      ConversationSyncService.instance
          .schedulePostPopCoalesceWindow(conversationID: conversationID);

  Future<ConversationWindowSlideResult> appendOlderFromLocal({
    int? convType,
    bool protectVirtualViewport = false,
  }) =>
      windowController.appendOlderFromLocal(
        convType: convType,
        protectVirtualViewport: protectVirtualViewport,
      );

  void _ensureTabStoreBridgeAttached() {
    if (_tabStoreBridgeAttached) return;
    _tabStoreBridgeAttached = true;
    ConversationTabStore.instance.addListener(_onTabStoreChanged);
  }

  void _onTabStoreChanged() {
    final reason = ConversationTabStore.instance.lastApplyPatchesReason;
    final appendOnly = ConversationTabStore.instance.lastNotificationAppendOnly;
    final changedIds = _tabStore.lastNotificationChangedIds;
    _tabStoreProjectionDirty = true;
    _sdkProjectionPublicationPending = true;
    _pendingTabStoreStructureChanged |=
        ConversationTabStore.instance.lastNotificationStructureChanged;
    _pendingTabStoreChangedIds.addAll(changedIds);
    if (appendOnly) {
      final previous = _pendingSdkProjectionDiff;
      _pendingSdkProjectionDiff = ConversationProjectionDiff(
        insertedIds: {
          ...?previous?.insertedIds,
          ...changedIds,
        },
        removedIds: {...?previous?.removedIds},
        rowChangedIds: {...?previous?.rowChangedIds},
        visibilityChanged: previous?.visibilityChanged ?? false,
        orderChanged: previous?.orderChanged ?? false,
      );
    } else {
      _pendingSdkFullDiff |= _tabStore.lastNotificationStructureChanged;
    }
    if (ConversationPerfFlags.tabStoreNotifyCoalesceEnabled &&
        reason.startsWith('sdk_realtime')) {
      _scheduleTabStoreNotify();
      return;
    }
    final structureChanged = _pendingTabStoreStructureChanged;
    _flushPendingTabStoreProjection();
    _notifyControllerProjection(
      reason: reason == 'sdk_page' ? 'sdk_page' : 'tab_store',
      contentOnly: !structureChanged,
    );
  }

  /// Coalesce the actual projection work, while synchronous row/window reads
  /// can demand the latest committed SDK view before its notification timer.
  void _flushPendingTabStoreProjection() {
    if (!_tabStoreProjectionDirty) return;
    final structureChanged = _pendingTabStoreStructureChanged;
    final ids = Set<String>.of(_pendingTabStoreChangedIds);
    _tabStoreProjectionDirty = false;
    _pendingTabStoreStructureChanged = false;
    _pendingTabStoreChangedIds.clear();
    final pendingInserts =
        _pendingSdkProjectionDiff?.insertedIds ?? const <String>{};
    if (pendingInserts.isNotEmpty && !_pendingSdkFullDiff) {
      return;
    }
    if (structureChanged || _pendingSdkFullDiff) {
      _pendingSdkProjectionDiff = null;
      return;
    }
    if (ids.isEmpty) return;
    _pendingSdkProjectionDiff = ConversationProjectionDiff(rowChangedIds: {
      ...?_pendingSdkProjectionDiff?.rowChangedIds,
      ...ids,
    });
  }

  void _scheduleTabStoreNotify() {
    deferredState.coalescedNotifyReason = 'tab_store';
    deferredState.tabStoreCoalescePendingCount++;
    // Keep a bounded publication interval during initial SDK roaming. A
    // trailing debounce can postpone every frame while batches keep arriving.
    if (deferredState.coalescedNotifyTimer != null) return;
    deferredState.coalescedNotifyTimer = Timer(
      ConversationPerfFlags.tabStoreNotifyCoalesceDelay,
      () {
        deferredState.coalescedNotifyTimer = null;
        deferredState.tabStoreCoalescePendingCount = 0;
        _notifyControllerProjection(reason: 'tab_store');
      },
    );
  }

  bool _shouldAdmitToUiWindow(
    V2TimConversation incoming,
    List<V2TimConversation> current,
  ) {
    if (incoming.isPinned == true || (incoming.unreadCount ?? 0) > 0) {
      return true;
    }
    if (current.isNotEmpty &&
        ConversationLocalStore.activeTimeMs(incoming) >
            ConversationLocalStore.activeTimeMs(current.first)) {
      return true;
    }
    if (!ConversationPerfFlags.uiWindowHardCapEnabled &&
        ConversationPerfFlags.sdkSyncAdmitColdConversations) {
      return true;
    }
    final isGroup = ConversationUnreadUtils.isGroupConversation(incoming);
    final typeCount = current
        .where((row) =>
            ConversationUnreadUtils.isGroupConversation(row) == isGroup)
        .length;
    final typeFloor = isGroup
        ? ConversationPerfFlags.uiSnapshotGroupLimit
        : ConversationPerfFlags.uiSnapshotC2cLimit;
    if (typeCount < typeFloor) return true;
    if (!ConversationPerfFlags.uiWindowHardCapEnabled) return false;
    if (current.length < ConversationPerfFlags.uiWindowHardCap ||
        current.isEmpty) {
      return true;
    }
    return ConversationLocalStore.activeTimeMs(incoming) >=
        ConversationLocalStore.activeTimeMs(current.last);
  }

  /// Publishes one already-reduced projection while respecting the same
  /// scroll/active-chat gates used by the feed. The writer must not bypass
  /// these gates, otherwise a committed SDK batch can still rebuild
  /// the whole feed during a gesture or while a chat is open.
  void _notifyControllerProjection({
    required String reason,
    bool contentOnly = false,
  }) {
    if (_notifySuppressDepth > 0) {
      _notifyPendingWhileSuppressed = true;
      ConversationPerfGateLog.log(
        'ui_notify_suppressed',
        extras: <String, Object?>{
          'reason': reason,
          'source': 'controller',
          'depth': _notifySuppressDepth,
        },
      );
      return;
    }
    if (reason != 'sdk_page' &&
        ConversationPerfFlags.deferUiNotifyWhileFeedScrolling &&
        isFeedScrollingNow) {
      deferredState.uiNotifyPendingWhileScrolling = true;
      _armScrollUiNotifyMaxDefer();
      ConversationPerfGateLog.log(
        'ui_notify_deferred_scroll',
        extras: <String, Object?>{'reason': reason, 'source': 'controller'},
      );
      return;
    }
    if (reason != 'sdk_page' &&
        !contentOnly &&
        ConversationPerfFlags.deferUiNotifyWhileActiveChat &&
        ActiveChatRegistry.instance.canDeferListUpdatesForOpenChat) {
      deferredState.uiNotifyPendingWhileActiveChat = true;
      _armActiveChatUiNotifyMaxDefer();
      ConversationPerfGateLog.log(
        'ui_notify_deferred_active_chat',
        extras: <String, Object?>{'reason': reason, 'source': 'controller'},
      );
      return;
    }
    notifyListeners();
  }

  void _armScrollUiNotifyMaxDefer() {
    if (deferredState.scrollUiNotifyMaxDeferTimer?.isActive == true) return;
    final delay = ConversationPerfFlags.feedScrollUiNotifyMaxDefer;
    if (delay <= Duration.zero) return;
    deferredState.scrollUiNotifyMaxDeferTimer = Timer(delay, () {
      deferredState.scrollUiNotifyMaxDeferTimer = null;
      flushDeferredUiNotifyIfNeeded(reason: 'scroll_max_defer');
    });
  }

  void _armActiveChatUiNotifyMaxDefer() {
    if (deferredState.activeChatUiNotifyMaxDeferTimer?.isActive == true) {
      return;
    }
    final delay = ConversationPerfFlags.activeChatUiNotifyMaxDefer;
    if (delay <= Duration.zero) return;
    deferredState.activeChatUiNotifyMaxDeferTimer = Timer(delay, () {
      deferredState.activeChatUiNotifyMaxDeferTimer = null;
      if (ConversationPerfFlags.activeChatMaxDeferFullFlushEnabled) {
        flushDeferredUiNotifyIfNeeded(reason: 'active_chat_max_defer');
      }
    });
  }

  void _scheduleCoalescedNotify(String reason) {
    deferredState.coalescedNotifyReason = reason;
    deferredState.coalescedNotifyTimer?.cancel();
    final delay = (reason == 'append_older' ||
            reason == 'prepend_newer' ||
            reason == 'restore_hot_head_phase2')
        ? ConversationPerfFlags.appendUiNotifyCoalesceDelay
        : (reason == 'tab_store'
            ? ConversationPerfFlags.tabStoreNotifyCoalesceDelay
            : const Duration(milliseconds: 48));
    deferredState.coalescedNotifyTimer = Timer(
      delay <= Duration.zero ? const Duration(milliseconds: 48) : delay,
      () {
        deferredState.coalescedNotifyTimer = null;
        final flushReason = deferredState.coalescedNotifyReason ?? reason;
        deferredState.coalescedNotifyReason = null;
        _notifyControllerProjection(reason: flushReason);
      },
    );
  }

  @visibleForTesting
  bool get uiNotifyPendingWhileScrollingForTest =>
      deferredState.uiNotifyPendingWhileScrolling;

  @visibleForTesting
  void scheduleCoalescedNotifyForTest(String reason) {
    _scheduleCoalescedNotify(reason);
  }

  @visibleForTesting
  void notifyIfAllowedForTest(String reason) {
    if (_notifySuppressDepth > 0) {
      _notifyPendingWhileSuppressed = true;
      return;
    }
    if (reason == 'apply_store' ||
        reason == 'apply_store_defer' ||
        reason == 'reload_from_local' ||
        reason == 'end_suppress') {
      _scheduleCoalescedNotify(reason);
      return;
    }
    _notifyControllerProjection(reason: reason);
  }
}

/// Projection-writer host owned by the session boundary.
///
/// Compatibility policies and virtual-window mutation primitives are hosted by
/// the session boundary, keeping the write lifecycle attached to the user
/// session.
class _ControllerWindowHost implements ChatSessionWindowHost {
  _ControllerWindowHost(this.controller);
  final ChatSessionController controller;
  @override
  bool get firstScreenReady => controller.firstScreenReady;
  @override
  bool get isFeedScrolling => controller.isFeedScrollingNow;
  @override
  String get currentOwnerUserId => controller.windowState.currentOwnerUserId;
  @override
  int get sessionGeneration => controller.windowState.sessionGeneration;
  @override
  bool isCurrentSession(String ownerUserId, int generation) =>
      controller.windowState.isCurrentSession(ownerUserId, generation);
  @override
  void ensureTabStoreBridgeAttached() =>
      controller._ensureTabStoreBridgeAttached();
  @override
  Future<void> primeSdkWindow(
          {required ConversationStoreProjectionReason reason,
          int? visibleConvType}) =>
      controller._primeSdkWindowDirect(
          reason: reason, visibleConvType: visibleConvType);
}
