import 'runtime_protocol.dart';

enum RuntimeViewPhase {
  reading,
  loadingLatest,
  waitingLayout,
  waitingScroll,
  followingLatest,
  closed
}

class RuntimeViewportProof {
  RuntimeViewportProof(
      {required this.scope,
      required this.conversationKey,
      required this.clearEpoch,
      required this.visitID,
      required this.operation,
      required this.windowRevision,
      required this.layoutRevision,
      required Iterable<String> coveredMessageIDs,
      required this.atTargetEdge})
      : coveredMessageIDs = Set<String>.unmodifiable(coveredMessageIDs);
  final RuntimeAccountScope scope;
  final String conversationKey;
  final int clearEpoch;
  final int visitID;
  final int operation;
  final int windowRevision;
  final int layoutRevision;
  final Set<String> coveredMessageIDs;
  final bool atTargetEdge;
}

class RuntimeReadConfirmation {
  RuntimeReadConfirmation(this.view, Iterable<String> coveredMessageIDs)
      : coveredMessageIDs = Set<String>.unmodifiable(coveredMessageIDs);
  final RuntimeViewSession view;
  final Set<String> coveredMessageIDs;
}

/// Immutable, per-visit UI state. Message facts are shared by the actor; search
/// anchors, window/layout revisions and finite return goals are never shared.
class RuntimeViewSession {
  RuntimeViewSession(
      {required this.scope,
      required this.conversationKey,
      required this.clearEpoch,
      required this.visitID})
      : operation = 0,
        phase = RuntimeViewPhase.reading,
        windowRevision = 0,
        layoutRevision = 0,
        targetMessageID = null,
        capturedUnreadIDs = const {},
        installedIDs = const {},
        searchAnchor = null {
    if (conversationKey.trim().isEmpty || clearEpoch < 0 || visitID < 1) {
      throw ArgumentError('Invalid view identity');
    }
  }

  RuntimeViewSession._(
      {required this.scope,
      required this.conversationKey,
      required this.clearEpoch,
      required this.visitID,
      required this.operation,
      required this.phase,
      required this.windowRevision,
      required this.layoutRevision,
      required this.targetMessageID,
      required this.capturedUnreadIDs,
      required this.installedIDs,
      required this.searchAnchor});

  final RuntimeAccountScope scope;
  final String conversationKey;
  final int clearEpoch;
  final int visitID;
  final int operation;
  final RuntimeViewPhase phase;
  final int windowRevision;
  final int layoutRevision;
  final String? targetMessageID;
  final Set<String> capturedUnreadIDs;
  final Set<String> installedIDs;
  final String? searchAnchor;

  RuntimeViewSession beginReturn(
      {required String targetMessageID,
      required Iterable<String> unreadMessageIDs}) {
    if (phase == RuntimeViewPhase.closed) throw StateError('View is closed');
    if (targetMessageID.trim().isEmpty) {
      throw ArgumentError.value(targetMessageID);
    }
    return _copy(
        operation: operation + 1,
        phase: RuntimeViewPhase.loadingLatest,
        target: targetMessageID,
        unread: Set.unmodifiable(unreadMessageIDs),
        clearSearch: true);
  }

  RuntimeViewSession beginSearch(String anchor) {
    if (phase == RuntimeViewPhase.closed) throw StateError('View is closed');
    if (anchor.trim().isEmpty) throw ArgumentError.value(anchor);
    return _copy(
        operation: operation + 1,
        phase: RuntimeViewPhase.reading,
        searchAnchor: anchor,
        clearTarget: true,
        unread: const {});
  }

  RuntimeViewSession installWindow(
      {required int expectedOperation,
      required int revision,
      required Iterable<String> messageIDs}) {
    if (phase == RuntimeViewPhase.closed ||
        expectedOperation != operation ||
        revision <= windowRevision) {
      return this;
    }
    final ids = Set<String>.unmodifiable(messageIDs);
    return _copy(
        windowRevision: revision,
        installed: ids,
        phase: targetMessageID == null
            ? phase
            : ids.contains(targetMessageID)
                ? RuntimeViewPhase.waitingLayout
                : RuntimeViewPhase.loadingLatest);
  }

  RuntimeViewSession acknowledgeLayout(
      {required int expectedOperation,
      required int expectedWindowRevision,
      required int revision}) {
    if (phase != RuntimeViewPhase.waitingLayout ||
        expectedOperation != operation ||
        expectedWindowRevision != windowRevision ||
        revision <= layoutRevision) {
      return this;
    }
    return _copy(
        layoutRevision: revision, phase: RuntimeViewPhase.waitingScroll);
  }

  RuntimeReadConfirmation? confirmReturn(RuntimeViewportProof proof) {
    if (phase != RuntimeViewPhase.waitingScroll ||
        proof.scope != scope ||
        proof.conversationKey != conversationKey ||
        proof.clearEpoch != clearEpoch ||
        proof.visitID != visitID ||
        proof.operation != operation ||
        proof.windowRevision != windowRevision ||
        proof.layoutRevision != layoutRevision ||
        !proof.atTargetEdge ||
        !proof.coveredMessageIDs.contains(targetMessageID) ||
        !installedIDs.containsAll(proof.coveredMessageIDs)) {
      return null;
    }
    // A new arrival after the captured goal is never silently acknowledged.
    return RuntimeReadConfirmation(
        _copy(phase: RuntimeViewPhase.followingLatest),
        proof.coveredMessageIDs.intersection(capturedUnreadIDs));
  }

  RuntimeViewSession close() =>
      _copy(operation: operation + 1, phase: RuntimeViewPhase.closed);

  RuntimeViewSession _copy(
          {int? operation,
          RuntimeViewPhase? phase,
          int? windowRevision,
          int? layoutRevision,
          String? target,
          Set<String>? unread,
          Set<String>? installed,
          String? searchAnchor,
          bool clearSearch = false,
          bool clearTarget = false}) =>
      RuntimeViewSession._(
          scope: scope,
          conversationKey: conversationKey,
          clearEpoch: clearEpoch,
          visitID: visitID,
          operation: operation ?? this.operation,
          phase: phase ?? this.phase,
          windowRevision: windowRevision ?? this.windowRevision,
          layoutRevision: layoutRevision ?? this.layoutRevision,
          targetMessageID: clearTarget ? null : target ?? targetMessageID,
          capturedUnreadIDs: unread ?? capturedUnreadIDs,
          installedIDs: installed ?? installedIDs,
          searchAnchor: clearSearch ? null : searchAnchor ?? this.searchAnchor);
}
