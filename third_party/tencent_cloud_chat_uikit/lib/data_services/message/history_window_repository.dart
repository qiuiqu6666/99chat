import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';

/// Cached pages are always newest-first. Links prove adjacency; sequence ranges
/// alone never prove that two pages are contiguous.
enum HistoryWindowDirection { older, newer }

enum HistoryWindowReadStatus { hit, miss, stale }

enum HistoryWindowMutationKind { edit, revoke, delete, restore, settle }

class HistoryWindowScope {
  const HistoryWindowScope({
    required this.ownerUserID,
    required this.accountGeneration,
    required this.domainGeneration,
    required this.conversationID,
    required this.clearEpoch,
    required this.sessionID,
    this.isCurrent,
  });
  final String ownerUserID;
  final int accountGeneration;
  final int domainGeneration;
  final String conversationID;
  final int clearEpoch;
  final String sessionID;

  /// Process-local lease; never serialized into the durable identity.
  final bool Function()? isCurrent;
}

class HistoryWindowBoundary {
  const HistoryWindowBoundary(
      {required this.msgID, this.seq, this.pageKey, this.ordinal});
  final String msgID;
  final String? seq;

  /// Store continuation position; permits progress even for anonymous/deleted rows.
  final String? pageKey;
  final int? ordinal;
}

class HistoryWindowPage {
  const HistoryWindowPage({
    required this.scope,
    required this.pageKey,
    required this.messages,
    this.newerPageKey,
    this.olderPageKey,
    this.requestCursor,
    this.nextOlderCursor,
    this.snapshotMaxSeq,
    this.pageChecksum,
    this.isReplayRoot = false,
  });
  final HistoryWindowScope scope;
  final String pageKey;

  /// Newest first, preserving the transport's stable ordering for ties.
  final List<V2TimMessage> messages;
  final String? newerPageKey;
  final String? olderPageKey;
  final String? requestCursor;
  final String? nextOlderCursor;
  final int? snapshotMaxSeq;
  final String? pageChecksum;
  final bool isReplayRoot;
}

class HistoryWindowReadResult {
  const HistoryWindowReadResult({
    required this.status,
    this.messages = const [],
    this.pageKeys = const [],
    this.pages = const [],
    this.snapshotMaxSeq,
    this.boundary,
    this.missingDirection,
    this.continuationBoundary,
    this.scanLimitReached = false,
    this.scannedRows = 0,
  });
  final HistoryWindowReadStatus status;
  final List<V2TimMessage> messages;
  final List<String> pageKeys;

  /// Bounded page metadata, including opaque cursors for a genuine miss.
  final List<HistoryWindowPage> pages;
  final int? snapshotMaxSeq;
  final HistoryWindowBoundary? boundary;
  final HistoryWindowDirection? missingDirection;

  /// Last examined raw row, including deleted rows, for the next bounded scan.
  final HistoryWindowBoundary? continuationBoundary;
  final bool scanLimitReached;
  final int scannedRows;
}

class HistoryWindowMutation {
  const HistoryWindowMutation({
    required this.ownerUserID,
    this.conversationID,
    required this.clearEpoch,
    required this.eventID,
    required this.msgID,
    required this.kind,
    this.message,
    this.revision = 0,
    this.restoreMutationToken,
    this.authorizationScope,
    this.isCurrent,
    this.sourceKey,
    this.pending = false,
  });
  final String ownerUserID;

  /// Null is an account-wide mutation when the native revoke omits its scope.
  final String? conversationID;
  final int clearEpoch;
  final String eventID;
  final String msgID;
  final HistoryWindowMutationKind kind;
  final V2TimMessage? message;

  /// Optional same-source revision. SQL insertion order is the total order;
  /// this is compared only against the persisted watermark for [sourceKey].
  final int revision;
  final String? sourceKey;

  /// A bounded local command which must later settle or restore by token.
  /// Its optimistic projection survives database closes in the same process.
  /// A new process invalidates unconfirmed commands and their cached copies;
  /// only settled or SDK-confirmed authority survives a process restart.
  final bool pending;
  final HistoryWindowScope? authorizationScope;
  final bool Function()? isCurrent;

  /// Restore only undoes the edit/revoke/delete with this exact event ID.
  final String? restoreMutationToken;
}

class HistoryWindowDeferredState {
  const HistoryWindowDeferredState({
    this.acknowledgedThroughSequence = 0,
    this.receivedCount = 0,
    this.unreadCount = 0,
    this.firstIngressSequence,
    this.lastIngressSequence,
    this.firstMessageID,
    this.lastMessageID,
    this.lastMessageTimestamp = 0,
    this.lastGroupMessageSeq = 0,
  });

  /// Persisted arrival ordinal acknowledged by the visible newest snapshot.
  /// This is independent from any transport's formal ingress sequence.
  final int acknowledgedThroughSequence;
  final int receivedCount;
  final int unreadCount;

  /// Arrival ordinals used to capture and acknowledge a newest-window snapshot.
  final int? firstIngressSequence;
  final int? lastIngressSequence;
  final String? firstMessageID;
  final String? lastMessageID;

  /// Small newest-boundary facts survive hot payload eviction.
  final int lastMessageTimestamp;
  final int lastGroupMessageSeq;
}

class HistoryWindowDeferredReceipt {
  const HistoryWindowDeferredReceipt({
    required this.inserted,
    required this.state,
  });
  final bool inserted;
  final HistoryWindowDeferredState state;
}

class HistoryWindowVisibleReceipt {
  const HistoryWindowVisibleReceipt({
    required this.acknowledgedMessageIDs,
    required this.state,
  });
  final Set<String> acknowledgedMessageIDs;
  final HistoryWindowDeferredState state;
}

abstract interface class HistoryWindowRepository {
  /// Await success before trimming in-memory history. A failed write throws.
  Future<void> savePage(HistoryWindowPage page);

  /// Atomically saves linked pages; any failure rolls back every page and link.
  Future<void> savePages(List<HistoryWindowPage> pages);
  Future<HistoryWindowReadResult> readAdjacent({
    required HistoryWindowScope scope,
    required HistoryWindowBoundary boundary,
    required HistoryWindowDirection direction,
    int limit = 50,
  });
  Future<HistoryWindowReadResult> readPage({
    required HistoryWindowScope scope,
    required String pageKey,
  });
  Future<HistoryWindowReadResult> readReplayRoot(HistoryWindowScope scope);
  Future<void> recordMutation(HistoryWindowMutation mutation);
  Future<List<V2TimMessage>> applyMutations({
    required HistoryWindowScope scope,
    required List<V2TimMessage> messages,
  });

  /// Durable append; callers increment UI scalars only after this succeeds.
  /// [ingressSequence] is a stable, ordered transport sequence by default.
  /// With [hasStableIngressSequence] false it is ignored for replay protection;
  /// the store assigns an arrival ordinal without advancing the formal fence.
  /// Returned state exposes arrival ordinals, not the transport sequence.
  Future<HistoryWindowDeferredReceipt> appendDeferred({
    required HistoryWindowScope scope,
    required String eventID,
    required int ingressSequence,
    bool hasStableIngressSequence = true,
    required V2TimMessage message,
  });

  /// True only when every delivery through this snapshot has a committed delete
  /// fact (or has already been retired). Pending local deletes do not qualify.
  Future<bool> areDeferredMessagesAuthoritativelyDeleted({
    required HistoryWindowScope scope,
    required int throughIngressSequence,
  });

  Future<HistoryWindowDeferredState> deferredState(HistoryWindowScope scope);

  /// Exact identities for a bounded pending tail, including rows whose payload
  /// was evicted. Callers must compare the full received count before claiming
  /// that this bounded set covers the complete pending bucket.
  Future<Set<String>> readDeferredMessageIDs({
    required HistoryWindowScope scope,
    int limit = 120,
  });

  /// Bounded newest-first tail; never materializes the complete backlog.
  Future<List<V2TimMessage>> readDeferredTail({
    required HistoryWindowScope scope,
    int limit = 120,
  });
  Future<void> acknowledgeDeferred({
    required HistoryWindowScope scope,
    required int throughIngressSequence,
  });

  /// Retire only the identities actually read during this presentation visit.
  /// Arrival order is not message order, so this never acknowledges a prefix.
  Future<HistoryWindowVisibleReceipt> acknowledgeVisibleDeferred({
    required HistoryWindowScope scope,
    required List<String> messageIDs,
    required int afterIngressSequence,
    bool Function()? isCurrent,
  });
  /// Highest clear epoch this store has recorded for the conversation, or 0.
  /// Lets the in-memory scope adopt a clear barrier it never learned about
  /// (coverage row lost) instead of being fenced as stale forever.
  Future<int> persistedClearEpoch({
    required String ownerUserID,
    required String conversationID,
  });
  Future<void> clearConversation({
    required String ownerUserID,
    required String conversationID,
    required int clearEpoch,
  });
  Future<void> closeSession(HistoryWindowScope scope);
}

class HistoryWindowRepositoryProvider {
  static HistoryWindowRepository? repository;
}

class HistoryWindowStaleScope implements Exception {
  const HistoryWindowStaleScope();
  @override
  String toString() => 'HistoryWindowStaleScope';
}

class HistoryWindowPendingLimit implements Exception {
  const HistoryWindowPendingLimit();
  @override
  String toString() => 'HistoryWindowPendingLimit';
}
