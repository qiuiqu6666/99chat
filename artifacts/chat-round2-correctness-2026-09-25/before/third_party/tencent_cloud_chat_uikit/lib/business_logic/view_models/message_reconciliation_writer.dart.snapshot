import 'dart:collection';

import 'message_reconciliation_coordinator.dart';
import 'message_reconciliation_identity.dart';
import 'message_history_coverage.dart';
import 'message_delta.dart';

/// Read-only value projection over the Writer's records. This owns no second
/// message array; SDK payload objects keep their established row identities.
class MessageReconciliationValues<T> extends ListBase<T> {
  MessageReconciliationValues(this._records);
  final List<MessageReconciliationRecord<T>> _records;
  @override
  int get length => _records.length;
  @override
  T operator [](int index) => _records[index].value;
  @override
  set length(int value) =>
      throw UnsupportedError('Writer owns message structure');
  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Writer owns message structure');
}

/// Scope captured by a MessageCore owner.
class MessageReconciliationWriterScope {
  const MessageReconciliationWriterScope({
    required this.ownerUserID,
    required this.accountGeneration,
    required this.domainGeneration,
  })  : assert(accountGeneration >= 0),
        assert(domainGeneration >= 0);

  final String ownerUserID;
  final int accountGeneration;
  final int domainGeneration;

  String get normalizedOwnerUserID => ownerUserID.trim();

  @override
  bool operator ==(Object other) {
    return other is MessageReconciliationWriterScope &&
        other.normalizedOwnerUserID == normalizedOwnerUserID &&
        other.accountGeneration == accountGeneration &&
        other.domainGeneration == domainGeneration;
  }

  @override
  int get hashCode =>
      Object.hash(normalizedOwnerUserID, accountGeneration, domainGeneration);
}

class MessageReconciliationWriterCommit<T> {
  const MessageReconciliationWriterCommit({
    required this.conversationKey,
    required this.generation,
    required this.revision,
    required this.clearEpoch,
    required this.ownerUserID,
    required this.accountGeneration,
    required this.domainGeneration,
    required this.records,
    required this.missingSeqRanges,
    required this.seqIdentityConflicts,
  });

  final String conversationKey;
  final int generation;
  final int revision;
  final int clearEpoch;
  final String? ownerUserID;
  final int? accountGeneration;
  final int? domainGeneration;
  final List<MessageReconciliationRecord<T>> records;
  final List<MessageSeqRange> missingSeqRanges;
  final List<MessageSeqIdentityConflict> seqIdentityConflicts;
}

class _MessageReconciliationWriterState<T> {
  _MessageReconciliationWriterState();

  int revision = 0;
  Object authority = Object();
  int clearEpoch = 0;
  String? ownerUserID;
  int? accountGeneration;
  int? domainGeneration;
  int lastDeltaGeneration = 0;
  bool trackSeqGaps = false;
  MessageReconciliationRequest? activeRequest;
  List<MessageReconciliationRecord<T>> _committed =
      <MessageReconciliationRecord<T>>[];
  MessageReconciliationValues<T>? publishedValues;
  List<MessageReconciliationRecord<T>> get committed => _committed;
  set committed(List<MessageReconciliationRecord<T>> records) {
    if (!identical(_committed, records)) publishedValues = null;
    _committed = records;
  }

  final List<MessageDelta<T>> pendingDeltas = <MessageDelta<T>>[];
  final Set<String> appliedDeltaEventIDs = <String>{};
  final Set<String> serverTombstones = <String>{};
  final Set<String> retiredLocalIDs = <String>{};

  /// Revoke rows remain visible as a local placeholder while their server
  /// identity is tombstoned. Ordinary deletes do not add to this set.
  final Set<String> retainedTombstoneOverlays = <String>{};
  final Map<String, MessageReconciliationRecord<T>> authoritativeOverlays =
      <String, MessageReconciliationRecord<T>>{};
}

/// Serializes history completions and realtime callbacks into one authoritative
/// commit per active reconciliation generation.
///
/// This class deliberately does not fetch data or notify UI listeners. The
/// caller publishes [MessageReconciliationWriterCommit.records] through the
/// existing message-list writer and therefore keeps one revision boundary.
class MessageReconciliationWriter<T> {
  MessageReconciliationWriter({
    required Comparator<MessageReconciliationRecord<T>> comparator,
    MessageReconciliationCoordinator? coordinator,
    MessageReconciliationWriterScope? scope,
  })  : _comparator = comparator,
        coordinator = coordinator ?? MessageReconciliationCoordinator(),
        _configuredScope = scope;

  final Comparator<MessageReconciliationRecord<T>> _comparator;
  final MessageReconciliationCoordinator coordinator;
  final Map<String, _MessageReconciliationWriterState<T>> _states =
      <String, _MessageReconciliationWriterState<T>>{};
  MessageReconciliationWriterScope? _configuredScope;
  static const int _maxRememberedServerMutations = 512;

  MessageReconciliationWriterScope? get configuredScope => _configuredScope;

  /// Opaque authority changes on publication, trimming, reset and scope reset.
  /// The projection may retain this token, but cannot manufacture one from a
  /// UI revision (which can be coalesced across several Writer publications).
  Object authorityFor(String conversationID) =>
      _stateFor(conversationID).authority;

  /// Avoid reseeding a window already published by this Writer. Values are
  /// mutable SDK objects: identity alone is insufficient, so the caller also
  /// checks the immutable identity fields captured in each record. Validate
  /// order afresh to catch SDK timestamp/sequence edits before a history read.
  bool ownsAuthoritativeWindow({
    required String conversationID,
    required Object? expectedAuthority,
    required List<T> values,
    required bool Function(MessageReconciliationRecord<T>, T) matchesRecord,
    required bool trackSeqGaps,
    required int clearEpoch,
  }) {
    final state = _states[_canonicalKey(conversationID)];
    if (state == null ||
        !identical(expectedAuthority, state.authority) ||
        state.clearEpoch != clearEpoch ||
        state.trackSeqGaps != trackSeqGaps ||
        state.committed.length != values.length) {
      return false;
    }
    for (var index = 0; index < values.length; index++) {
      final record = state.committed[index];
      if (!identical(record.value, values[index]) ||
          !matchesRecord(record, values[index]) ||
          (index > 0 && _comparator(state.committed[index - 1], record) > 0)) {
        return false;
      }
    }
    return true;
  }

  /// Changes of owner or SDK session cannot share the previous Writer state.
  void configureScope(MessageReconciliationWriterScope scope) {
    final scopeConflicts = _states.values.any(
      (state) =>
          (state.ownerUserID != null &&
              state.ownerUserID != scope.normalizedOwnerUserID) ||
          (state.accountGeneration != null &&
              state.accountGeneration != scope.accountGeneration) ||
          (state.domainGeneration != null &&
              state.domainGeneration != scope.domainGeneration),
    );
    if ((_configuredScope != null && _configuredScope != scope) ||
        scopeConflicts) {
      resetAll();
    }
    _configuredScope = scope;
    for (final state in _states.values) {
      state.ownerUserID ??= scope.normalizedOwnerUserID;
      state.accountGeneration ??= scope.accountGeneration;
      state.domainGeneration ??= scope.domainGeneration;
    }
  }

  void seedAuthoritative({
    required String conversationID,
    required Iterable<MessageReconciliationRecord<T>> records,
    bool trackSeqGaps = false,
    int? clearEpoch,
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final state = _stateFor(conversationID);
    _adoptOrValidateScope(
      state,
      ownerUserID: ownerUserID,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
    );
    if (clearEpoch != null && clearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, clearEpoch);
    }
    state.trackSeqGaps = trackSeqGaps;
    state.committed = _mergeAndSort(
      _applyRememberedAuthority(state, records),
      trackSeqGaps: state.trackSeqGaps,
    ).records;
    state.authority = Object();
  }

  MessageReconciliationRequest beginInitialHistory({
    required String conversationID,
    required MessageReconciliationSource requestedSource,
    required MessageReconciliationNetworkState networkState,
    int? clearEpoch,
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final state = _stateFor(conversationID);
    _adoptOrValidateScope(
      state,
      ownerUserID: ownerUserID,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
    );
    final effectiveClearEpoch = clearEpoch ?? state.clearEpoch;
    if (effectiveClearEpoch < state.clearEpoch) {
      throw StateError('History request uses an older clear epoch.');
    }
    if (effectiveClearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, effectiveClearEpoch);
    }
    final request = coordinator.beginInitialHistory(
      conversationID: conversationID,
      requestedSource: requestedSource,
      networkState: networkState,
      ownerUserID: state.ownerUserID,
      accountGeneration: state.accountGeneration ?? 0,
      domainGeneration: state.domainGeneration ?? 0,
      clearEpoch: state.clearEpoch,
    );
    state.activeRequest = request;
    state.lastDeltaGeneration = request.generation;
    return request;
  }

  MessageReconciliationRequest beginCloudCatchUp({
    required String conversationID,
    required MessageReconciliationNetworkState networkState,
    int? clearEpoch,
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final state = _stateFor(conversationID);
    _adoptOrValidateScope(
      state,
      ownerUserID: ownerUserID,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
    );
    final effectiveClearEpoch = clearEpoch ?? state.clearEpoch;
    if (effectiveClearEpoch < state.clearEpoch) {
      throw StateError('History request uses an older clear epoch.');
    }
    if (effectiveClearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, effectiveClearEpoch);
    }
    final request = coordinator.beginCloudCatchUp(
      conversationID: conversationID,
      networkState: networkState,
      ownerUserID: state.ownerUserID,
      accountGeneration: state.accountGeneration ?? 0,
      domainGeneration: state.domainGeneration ?? 0,
      clearEpoch: state.clearEpoch,
    );
    state.activeRequest = request;
    state.lastDeltaGeneration = request.generation;
    return request;
  }

  /// Publishes immediately even while a history request is active. The same
  /// delta stays queued so history completion can merge without dropping it.
  MessageReconciliationWriterCommit<T>? enqueueRealtime({
    required String conversationID,
    required String eventID,
    required Iterable<MessageReconciliationRecord<T>> records,
  }) {
    final incoming = records.toList(growable: false);
    if (incoming.isEmpty) return null;
    final state = _stateFor(conversationID);
    return applyDelta(
      MessageDelta<T>(
        conversationKey: conversationID,
        eventID: eventID,
        kind: MessageDeltaKind.realtimeUpsert,
        source: MessageDeltaSource.sdkRealtime,
        generation: coordinator.stateFor(conversationID).requestGeneration,
        clearEpoch: state.clearEpoch,
        ownerUserID: state.ownerUserID,
        accountGeneration: state.accountGeneration,
        domainGeneration: state.domainGeneration,
        replace: false,
        upserts: incoming,
      ),
    );
  }

  /// Applies every authoritative non-history mutation through one writer.
  ///
    /// Deltas that arrive during a history request stay queued for the history
    /// merge. Realtime and send-pipeline deltas are also published immediately
    /// so a long history read cannot block incoming or outgoing messages.
    /// Deletions
  /// install server-ID tombstones before merge, while edits/revokes install
  /// overlays that stale history cannot overwrite.
  MessageReconciliationWriterCommit<T>? applyDelta(
    MessageDelta<T> delta, {
    bool publishDuringHistory = false,
  }) {
    final conversationID = _canonicalKey(delta.conversationKey);
    final state = _stateFor(conversationID);
    if (!delta.hasMutation || delta.clearEpoch < state.clearEpoch) {
      return null;
    }
    if (!_scopeMatches(
      state,
      ownerUserID: delta.ownerUserID,
      accountGeneration: delta.accountGeneration,
      domainGeneration: delta.domainGeneration,
    )) {
      return null;
    }
    if (delta.generation < state.lastDeltaGeneration) {
      return null;
    }
    if (!state.appliedDeltaEventIDs.add(delta.eventID)) {
      return null;
    }
    while (
        state.appliedDeltaEventIDs.length > _maxRememberedServerMutations * 2) {
      state.appliedDeltaEventIDs.remove(state.appliedDeltaEventIDs.first);
    }
    if (delta.clearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, delta.clearEpoch);
    }
    state.lastDeltaGeneration = delta.generation;

    final first = delta.upserts.isEmpty ? null : delta.upserts.first;
    if (delta.kind == MessageDeltaKind.realtimeUpsert) {
      final accepted = coordinator.noteRealtimePending(
        conversationID: conversationID,
        eventID: delta.eventID,
        msgID: first?.serverIdentity,
        seq: first?.numericSeq,
      );
      if (!accepted) return null;
    }

    _rememberDeltaAuthority(state, delta);
    if (state.activeRequest != null) {
      state.pendingDeltas.add(delta);
      // Sending must remain interactive while older history is loading. Keep
      // the delta for the final history merge, but publish it immediately so
      // optimistic rows and SDK success/failure adoption are never held behind
      // a slow or stuck history request.
      if (publishDuringHistory ||
          delta.source == MessageDeltaSource.sendPipeline ||
          delta.source == MessageDeltaSource.sdkRealtime) {
        return _publish(
          conversationID: conversationID,
          state: state,
          input: _applyDeltaRecords(state.committed, <MessageDelta<T>>[delta]),
          generation: delta.generation,
        );
      }
      return null;
    }
    return _publish(
      conversationID: conversationID,
      state: state,
      input: _applyDeltaRecords(state.committed, <MessageDelta<T>>[delta]),
      generation: delta.generation,
    );
  }

  /// Publishes a revoke delta immediately, bypassing the active history
  /// request barrier.
  ///
  /// Revoke is a user-visible command; UX requires the bubble to refresh
  /// without waiting for the in-flight history transaction to complete. All
  /// other consistency checks (scope, generation, clearEpoch, eventID dedup,
  /// tombstone persistence) still run before publish so that history cannot
  /// resurrect a recalled row.
  MessageReconciliationWriterCommit<T>? applyRevokeDelta(
    MessageDelta<T> delta,
  ) {
    if (delta.kind != MessageDeltaKind.revoke) {
      return null;
    }
    final conversationID = _canonicalKey(delta.conversationKey);
    final state = _stateFor(conversationID);
    if (!delta.hasMutation || delta.clearEpoch < state.clearEpoch) {
      return null;
    }
    if (!_scopeMatches(
      state,
      ownerUserID: delta.ownerUserID,
      accountGeneration: delta.accountGeneration,
      domainGeneration: delta.domainGeneration,
    )) {
      return null;
    }
    if (delta.generation < state.lastDeltaGeneration) {
      return null;
    }
    if (!state.appliedDeltaEventIDs.add(delta.eventID)) {
      return null;
    }
    while (
        state.appliedDeltaEventIDs.length > _maxRememberedServerMutations * 2) {
      state.appliedDeltaEventIDs.remove(state.appliedDeltaEventIDs.first);
    }
    if (delta.clearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, delta.clearEpoch);
    }
    state.lastDeltaGeneration = delta.generation;

    _rememberDeltaAuthority(state, delta);
    return _publish(
      conversationID: conversationID,
      state: state,
      input: _applyDeltaRecords(state.committed, <MessageDelta<T>>[delta]),
      generation: delta.generation,
    );
  }

  /// A stale completion is ignored and cannot consume realtime messages that
  /// belong to the newer generation.
  MessageReconciliationWriterCommit<T>? completeHistory({
    required MessageReconciliationRequest request,
    required Iterable<MessageReconciliationRecord<T>> history,
    required MessageReconciliationSource actualSource,
    required MessageReconciliationNetworkState networkState,
    int? clearEpoch,
    bool cloudHasMoreNewer = false,
    MessageHistoryBatchKind batchKind = MessageHistoryBatchKind.olderPage,
    MessageHistoryProofKind proofKind = MessageHistoryProofKind.none,
    bool? historyIsFinished,
    Iterable<MessageReconciliationRecord<T>>? authoritativeBase,
    Iterable<String> explicitDeletes = const <String>[],
    Iterable<String> tombstones = const <String>[],
  }) {
    final state = _stateFor(request.conversationKey);
    if (state.activeRequest?.generation != request.generation ||
        state.clearEpoch != request.clearEpoch ||
        (clearEpoch != null && clearEpoch != request.clearEpoch) ||
        !_scopeMatchesRequest(state, request)) {
      return null;
    }

    final batchDeletes = <String>{
      ...explicitDeletes.map((id) => id.trim()).where((id) => id.isNotEmpty),
      ...tombstones.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };
    if (batchDeletes.isNotEmpty) {
      for (final id in batchDeletes) {
        state.serverTombstones.add(id);
        if (!state.retainedTombstoneOverlays.contains(id)) {
          state.authoritativeOverlays.remove(id);
        }
      }
      _trimRememberedAuthority(state);
    }

    final merged = _mergeAndSort(
      _applyRememberedAuthority(
        state,
        _applyDeltaRecords(<MessageReconciliationRecord<T>>[
          ...history,
          ...(authoritativeBase ?? state.committed),
        ], state.pendingDeltas,
            // An older-page request owns the complete history window. A
            // queued compatibility snapshot (preview/hydrate) must not clear
            // the freshly fetched older rows while it is merged at commit.
            preserveBaseOnReplace:
                batchKind == MessageHistoryBatchKind.olderPage),
      ),
      trackSeqGaps: state.trackSeqGaps,
    );
    final lastConfirmed = _lastConfirmedMsgID(merged.records);
    final accepted = coordinator.completeRequest(
      request: request,
      actualSource: actualSource,
      networkState: networkState,
      resultCount: merged.records.length,
      lastConfirmedMsgID: lastConfirmed,
      oldestSeq: merged.oldestSeq,
      newestSeq: merged.newestSeq,
      missingSeqRanges: merged.missingSeqRanges,
      cloudHasMoreNewer: cloudHasMoreNewer,
      batchKind: batchKind,
      proofKind: proofKind,
      historyIsFinished: historyIsFinished,
    );
    if (!accepted) return null;

    state.activeRequest = null;
    state.pendingDeltas.clear();
    state.committed = merged.records;
    state.authority = Object();
    state.revision += 1;
    return _commitFromMerge(
      request.conversationKey,
      state,
      request.generation,
      state.revision,
      merged,
    );
  }

  /// Failure releases queued realtime messages instead of leaving the visible
  /// list frozen behind a failed history request.
  MessageReconciliationWriterCommit<T>? failHistory({
    required MessageReconciliationRequest request,
    required String reason,
    required MessageReconciliationNetworkState networkState,
  }) {
    final state = _stateFor(request.conversationKey);
    if (state.activeRequest?.generation != request.generation ||
        state.clearEpoch != request.clearEpoch ||
        !_scopeMatchesRequest(state, request)) {
      return null;
    }
    if (!coordinator.failRequest(
      request: request,
      reason: reason,
      networkState: networkState,
    )) {
      return null;
    }
    state.activeRequest = null;
    if (state.pendingDeltas.isEmpty) return null;
    final pending = List<MessageDelta<T>>.of(state.pendingDeltas);
    state.pendingDeltas.clear();
    return _publish(
      conversationID: request.conversationKey,
      state: state,
      input: _applyDeltaRecords(state.committed, pending),
      generation: request.generation,
    );
  }

  List<MessageReconciliationRecord<T>> recordsFor(String conversationID) {
    return UnmodifiableListView(_stateFor(conversationID).committed);
  }

  /// Stable shared read view until the next Writer publication or trim.
  MessageReconciliationValues<T> valuesFor(String conversationID) {
    final state = _stateFor(conversationID);
    final cached = state.publishedValues;
    if (cached != null && identical(cached._records, state.committed))
      return cached;
    return state.publishedValues = MessageReconciliationValues(state.committed);
  }

  /// Shrinks the retained working set after its matching UI commit. This is
  /// eviction, not deletion: authority overlays and tombstones are unchanged,
  /// so a later SDK page can restore an evicted row normally.
  ///
  /// A stale projection or an in-flight history request cannot evict the
  /// current writer state. Only existing record values may be retained.
  bool retainCommittedWindow({
    required String conversationID,
    required int expectedRevision,
    required int expectedClearEpoch,
    required MessageReconciliationWriterScope? expectedScope,
    required Iterable<T> retainedValues,
  }) {
    final state = _stateFor(conversationID);
    if (_configuredScope != expectedScope ||
        state.activeRequest != null ||
        state.revision != expectedRevision ||
        state.clearEpoch != expectedClearEpoch) {
      return false;
    }
    final selected = Set<T>.identity()..addAll(retainedValues);
    final retained = state.committed
        .where((record) => selected.contains(record.value))
        .toList(growable: false);
    if (retained.length != selected.length) return false;
    state.committed = retained;
    state.authority = Object();
    return true;
  }

  int revisionFor(String conversationID) => _stateFor(conversationID).revision;

  /// Publishes a retained subset without pulling off-window authority overlays
  /// back into the working set. Their facts remain available for future pages.
  MessageReconciliationWriterCommit<T>? commitRetainedWindow({
    required String conversationID,
    required int expectedRevision,
    required int expectedClearEpoch,
    required MessageReconciliationWriterScope? expectedScope,
    required Iterable<T> retainedValues,
    required int generation,
  }) {
    if (!retainCommittedWindow(
        conversationID: conversationID,
        expectedRevision: expectedRevision,
        expectedClearEpoch: expectedClearEpoch,
        expectedScope: expectedScope,
        retainedValues: retainedValues)) return null;
    final state = _stateFor(conversationID);
    final merged =
        _mergeAndSort(state.committed, trackSeqGaps: state.trackSeqGaps);
    state.committed = merged.records;
    state.revision++;
    state.authority = Object();
    return _commitFromMerge(_canonicalKey(conversationID), state, generation,
        state.revision, merged);
  }

  int clearEpochFor(String conversationID) =>
      _stateFor(conversationID).clearEpoch;

  /// Advances the clear barrier without publishing a message snapshot.
  /// Older history and realtime inputs are rejected after this point.
  void clearConversation({
    required String conversationID,
    required int clearEpoch,
  }) {
    final state = _stateFor(conversationID);
    if (clearEpoch > state.clearEpoch) {
      _advanceClearEpoch(state, clearEpoch);
    }
  }

  int pendingRealtimeCount(String conversationID) => _stateFor(conversationID)
      .pendingDeltas
      .where((delta) => delta.kind == MessageDeltaKind.realtimeUpsert)
      .fold<int>(0, (count, delta) => count + delta.upserts.length);

  int pendingDeltaCount(String conversationID) =>
      _stateFor(conversationID).pendingDeltas.length;

  /// Admits a legacy full-list publication into the same Writer boundary.
  ///
  /// Old UIKit callers can still provide an already merged snapshot, while
  /// the Writer remains the only component that decides replacement, identity
  /// deduplication and revision ordering. A snapshot is not allowed to race
  /// an active history request; that request owns the next publication.
  MessageReconciliationWriterCommit<T>? applyCompatibilitySnapshot({
    required String conversationID,
    required String eventID,
    required Iterable<MessageReconciliationRecord<T>> records,
    required int generation,
    required int clearEpoch,
    bool replace = false,

    /// Only a confirmed destructive replacement may infer deletes from rows
    /// absent in the incoming list. Ordinary history/window replacements are
    /// partial views; absence there must never become a server tombstone.
    bool tombstoneMissing = false,
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final key = _canonicalKey(conversationID);
    final state = _stateFor(key);
    if (state.activeRequest != null) {
      return null;
    }
    final incoming = records.toList(growable: false);
    final incomingServerIDs = incoming
        .map((record) => record.serverIdentity)
        .whereType<String>()
        .toSet();
    final explicitDeletes = replace && tombstoneMissing
        ? state.committed
            .map((record) => record.serverIdentity)
            .whereType<String>()
            .where((id) => !incomingServerIDs.contains(id))
            .toSet()
        : const <String>{};
    return applyDelta(
      MessageDelta<T>(
        conversationKey: key,
        eventID: eventID,
        kind: MessageDeltaKind.compatibilitySnapshot,
        source: MessageDeltaSource.compatibilityProjection,
        generation: generation,
        clearEpoch: clearEpoch,
        ownerUserID: ownerUserID,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        replace: replace,
        upserts: incoming,
        explicitDeletes: explicitDeletes,
      ),
    );
  }

  Set<String> tombstonesFor(String conversationID) =>
      Set<String>.unmodifiable(_stateFor(conversationID).serverTombstones);

  void releaseTombstones(String conversationID, Iterable<String> msgIDs) {
    final state = _stateFor(conversationID);
    final normalizedIDs =
        msgIDs.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    for (final id in normalizedIDs) {
      final normalized = id.trim();
      if (normalized.isEmpty) continue;
      state.serverTombstones.remove(normalized);
      state.retainedTombstoneOverlays.remove(normalized);
      state.authoritativeOverlays.remove(normalized);
    }
    // A delete/revoke can be accepted while a history request is in flight.
    // If the SDK operation fails, discard the queued removal before publishing
    // the rollback upsert; otherwise the same tombstone would be re-applied
    // when history completes.
    state.pendingDeltas.removeWhere((delta) {
      final affected = <String>{...delta.explicitDeletes, ...delta.tombstones};
      return affected.any(normalizedIDs.contains);
    });
  }

  bool hasActiveRequest(String conversationID) =>
      _stateFor(conversationID).activeRequest != null;

  void reset(String conversationID) {
    final key = _canonicalKey(conversationID);
    // Flush pending realtime messages before clearing state so they are
    // not silently lost when the conversation is torn down.
    final state = _states[key];
    if (state != null && state.pendingDeltas.isNotEmpty) {
      final pending = List<MessageDelta<T>>.of(state.pendingDeltas);
      state.pendingDeltas.clear();
      if (state.activeRequest == null) {
        _publish(
          conversationID: conversationID,
          state: state,
          input: _applyDeltaRecords(state.committed, pending),
          generation: coordinator.stateFor(conversationID).requestGeneration,
        );
      }
    }
    _states.remove(key);
    coordinator.reset(key);
  }

  void resetAll() {
    final keys = _states.keys.toList(growable: false);
    for (final key in keys) {
      reset(key);
    }
  }

  void _adoptOrValidateScope(
    _MessageReconciliationWriterState<T> state, {
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final configured = _configuredScope;
    final incomingOwner = ownerUserID?.trim();
    final effectiveOwner = incomingOwner ?? configured?.normalizedOwnerUserID;
    final effectiveAccount = accountGeneration ?? configured?.accountGeneration;
    final effectiveDomain = domainGeneration ?? configured?.domainGeneration;
    if (effectiveOwner != null) {
      _requireMatchingScopeValue(
        state.ownerUserID,
        effectiveOwner,
        'ownerUserID',
      );
      state.ownerUserID ??= effectiveOwner;
    }
    if (effectiveAccount != null) {
      _requireMatchingScopeValue(
        state.accountGeneration,
        effectiveAccount,
        'accountGeneration',
      );
      state.accountGeneration ??= effectiveAccount;
    }
    if (effectiveDomain != null) {
      _requireMatchingScopeValue(
        state.domainGeneration,
        effectiveDomain,
        'domainGeneration',
      );
      state.domainGeneration ??= effectiveDomain;
    }
  }

  bool _scopeMatches(
    _MessageReconciliationWriterState<T> state, {
    String? ownerUserID,
    int? accountGeneration,
    int? domainGeneration,
  }) {
    final incomingOwner = ownerUserID?.trim();
    final configured = _configuredScope;
    if (configured != null) {
      if (incomingOwner != null &&
          incomingOwner != configured.normalizedOwnerUserID) {
        return false;
      }
      if (accountGeneration != null &&
          accountGeneration != configured.accountGeneration) {
        return false;
      }
      if (domainGeneration != null &&
          domainGeneration != configured.domainGeneration) {
        return false;
      }
    }
    if (incomingOwner != null &&
        state.ownerUserID != null &&
        incomingOwner != state.ownerUserID) {
      return false;
    }
    if (accountGeneration != null &&
        state.accountGeneration != null &&
        accountGeneration != state.accountGeneration) {
      return false;
    }
    if (domainGeneration != null &&
        state.domainGeneration != null &&
        domainGeneration != state.domainGeneration) {
      return false;
    }
    _adoptOrValidateScope(
      state,
      ownerUserID: ownerUserID,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
    );
    return true;
  }

  bool _scopeMatchesRequest(
    _MessageReconciliationWriterState<T> state,
    MessageReconciliationRequest request,
  ) {
    return _scopeMatches(
      state,
      ownerUserID: request.ownerUserID,
      accountGeneration: request.accountGeneration,
      domainGeneration: request.domainGeneration,
    );
  }

  void _requireMatchingScopeValue<TValue>(
    TValue? current,
    TValue incoming,
    String name,
  ) {
    if (current != null && current != incoming) {
      throw StateError('Message Writer scope mismatch: $name.');
    }
  }

  void _advanceClearEpoch(
    _MessageReconciliationWriterState<T> state,
    int nextClearEpoch,
  ) {
    if (nextClearEpoch <= state.clearEpoch) return;
    state.clearEpoch = nextClearEpoch;
    // A clear is a visibility barrier. Any history request from the previous
    // barrier must be released without consuming its queued realtime events.
    state.activeRequest = null;
    state.committed = <MessageReconciliationRecord<T>>[];
    state.authority = Object();
    state.pendingDeltas.clear();
    state.serverTombstones.clear();
    state.retiredLocalIDs.clear();
    state.retainedTombstoneOverlays.clear();
    state.authoritativeOverlays.clear();
    state.lastDeltaGeneration = 0;
  }

  MessageReconciliationWriterCommit<T> _publish({
    required String conversationID,
    required _MessageReconciliationWriterState<T> state,
    required Iterable<MessageReconciliationRecord<T>> input,
    required int generation,
  }) {
    final merged = _mergeAndSort(
      _applyRememberedAuthority(state, input),
      trackSeqGaps: state.trackSeqGaps,
    );
    state.committed = merged.records;
    state.authority = Object();
    state.revision += 1;
    return _commitFromMerge(
      _canonicalKey(conversationID),
      state,
      generation,
      state.revision,
      merged,
    );
  }

  MessageReconciliationWriterCommit<T> _commitFromMerge(
    String conversationKey,
    _MessageReconciliationWriterState<T> state,
    int generation,
    int revision,
    MessageIdentityMergeResult<T> merged,
  ) {
    return MessageReconciliationWriterCommit<T>(
      conversationKey: conversationKey,
      generation: generation,
      revision: revision,
      clearEpoch: state.clearEpoch,
      ownerUserID: state.ownerUserID,
      accountGeneration: state.accountGeneration,
      domainGeneration: state.domainGeneration,
      records: merged.records,
      missingSeqRanges: merged.missingSeqRanges,
      seqIdentityConflicts: merged.seqIdentityConflicts,
    );
  }

  MessageIdentityMergeResult<T> _mergeAndSort(
    Iterable<MessageReconciliationRecord<T>> records, {
    required bool trackSeqGaps,
  }) {
    final merged = MessageReconciliationIdentity.merge(records);
    final sorted = List<MessageReconciliationRecord<T>>.of(merged.records);
    // Most receipts and older-page appends preserve the committed order.
    // Replacements may change the sort key, so verify adjacent rows before
    // skipping the full sort rather than relying on the delta's source/kind.
    for (var index = 1; index < sorted.length; index++) {
      if (_comparator(sorted[index - 1], sorted[index]) > 0) {
        sorted.sort(_comparator);
        break;
      }
    }
    return MessageIdentityMergeResult<T>(
      records: List<MessageReconciliationRecord<T>>.unmodifiable(sorted),
      oldestSeq: merged.oldestSeq,
      newestSeq: merged.newestSeq,
      missingSeqRanges:
          trackSeqGaps ? merged.missingSeqRanges : const <MessageSeqRange>[],
      seqIdentityConflicts: merged.seqIdentityConflicts,
    );
  }

  Iterable<MessageReconciliationRecord<T>> _applyDeltaRecords(
    Iterable<MessageReconciliationRecord<T>> base,
    Iterable<MessageDelta<T>> deltas, {
    bool preserveBaseOnReplace = false,
  }) sync* {
    final records = <MessageReconciliationRecord<T>>[...base];
    final deleted = <String>{};
    final retainedRevokes = <String>{};
    final upserts = <MessageReconciliationRecord<T>>[];
    for (final delta in deltas) {
      if (delta.replace && !preserveBaseOnReplace) {
        records.clear();
        deleted.clear();
        retainedRevokes.clear();
        upserts.clear();
      }
      deleted.addAll(delta.explicitDeletes);
      deleted.addAll(delta.tombstones);
      for (final id in {...delta.explicitDeletes, ...delta.tombstones}) {
        if (delta.kind == MessageDeltaKind.revoke &&
            !delta.explicitDeletes.contains(id)) {
          retainedRevokes.add(id);
        } else {
          retainedRevokes.remove(id);
        }
      }
      upserts.addAll(delta.upserts);
    }
    for (final record in records) {
      final id = record.serverIdentity;
      // Keep an in-window recall's identity for authority substitution below,
      // including duplicate revoke notifications that omit their payload.
      if (id == null || !deleted.contains(id) || retainedRevokes.contains(id)) {
        yield record;
      }
    }
    yield* upserts;
  }

  Iterable<MessageReconciliationRecord<T>> _applyRememberedAuthority(
    _MessageReconciliationWriterState<T> state,
    Iterable<MessageReconciliationRecord<T>> base,
  ) sync* {
    // Remembered edits/receipts/live messages update rows admitted by this
    // window. They must never append rows from another (e.g. latest) window.
    // Retain the overlays themselves so paging back to a row restores its
    // authoritative content without treating a window switch as deletion.
    final windowIDs = <String>{};
    for (final record in base) {
      if (record.serverIdentity == null &&
          (state.retiredLocalIDs.contains(record.optimisticIdentity) ||
              state.retiredLocalIDs.contains(record.localID))) {
        continue;
      }
      final id = record.serverIdentity;
      if (id != null) windowIDs.add(id);
      if (id == null || !state.serverTombstones.contains(id)) {
        yield record;
      }
    }
    for (final overlay in state.authoritativeOverlays.values) {
      final id = overlay.serverIdentity;
      if (id != null &&
          windowIDs.contains(id) &&
          (!state.serverTombstones.contains(id) ||
              state.retainedTombstoneOverlays.contains(id))) {
        yield overlay;
      }
    }
  }

  void _rememberDeltaAuthority(
    _MessageReconciliationWriterState<T> state,
    MessageDelta<T> delta,
  ) {
    if (delta.kind == MessageDeltaKind.delete &&
        delta.source == MessageDeltaSource.sendPipeline) {
      state.retiredLocalIDs.addAll(delta.localDeletes);
      while (state.retiredLocalIDs.length > _maxRememberedServerMutations) {
        state.retiredLocalIDs.remove(state.retiredLocalIDs.first);
      }
    }
    final removals = <String>{...delta.explicitDeletes, ...delta.tombstones};
    for (final id in removals) {
      state.serverTombstones.add(id);
      // Repeated revoke notifications can omit the message body. Keep the
      // previously committed recall notice; an explicit delete still removes it.
      if (delta.kind == MessageDeltaKind.revoke &&
          !delta.explicitDeletes.contains(id) &&
          state.retainedTombstoneOverlays.contains(id)) {
        continue;
      }
      state.retainedTombstoneOverlays.remove(id);
      state.authoritativeOverlays.remove(id);
    }
    for (final record in delta.upserts) {
      final id = record.serverIdentity;
      if (id == null) continue;
      if (state.serverTombstones.contains(id) &&
          delta.kind != MessageDeltaKind.revoke) {
        final reclaim = delta.source == MessageDeltaSource.sendPipeline &&
            (delta.kind == MessageDeltaKind.optimisticInsert ||
                delta.kind == MessageDeltaKind.optimisticAdoption);
        if (!reclaim) {
          continue;
        }
        state.serverTombstones.remove(id);
        state.retainedTombstoneOverlays.remove(id);
      }
      if (delta.kind == MessageDeltaKind.revoke) {
        state.serverTombstones.add(id);
        state.retainedTombstoneOverlays.add(id);
      }
      if (delta.kind == MessageDeltaKind.edit ||
          delta.kind == MessageDeltaKind.revoke ||
          delta.kind == MessageDeltaKind.optimisticAdoption ||
          delta.kind == MessageDeltaKind.realtimeUpsert ||
          delta.kind == MessageDeltaKind.readReceipt ||
          delta.kind == MessageDeltaKind.localMetadata) {
        state.authoritativeOverlays.remove(id);
        state.authoritativeOverlays[id] = record;
      }
    }
    _trimRememberedAuthority(state);
  }

  void _trimRememberedAuthority(_MessageReconciliationWriterState<T> state) {
    while (state.serverTombstones.length > _maxRememberedServerMutations) {
      final oldest = state.serverTombstones.first;
      state.serverTombstones.remove(oldest);
      state.retainedTombstoneOverlays.remove(oldest);
    }
    while (state.authoritativeOverlays.length > _maxRememberedServerMutations) {
      state.authoritativeOverlays.remove(
        state.authoritativeOverlays.keys.first,
      );
    }
    while (state.retainedTombstoneOverlays.length >
        _maxRememberedServerMutations) {
      state.retainedTombstoneOverlays.remove(
        state.retainedTombstoneOverlays.first,
      );
    }
  }

  _MessageReconciliationWriterState<T> _stateFor(String conversationID) {
    return _states.putIfAbsent(
      _canonicalKey(conversationID),
      _MessageReconciliationWriterState<T>.new,
    );
  }

  static String _canonicalKey(String conversationID) {
    final key = conversationID.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(conversationID, 'conversationID');
    }
    return key;
  }

  static String? _lastConfirmedMsgID<T>(
    List<MessageReconciliationRecord<T>> records,
  ) {
    for (final record in records.reversed) {
      final id = record.serverIdentity;
      if (id != null) return id;
    }
    return null;
  }
}
