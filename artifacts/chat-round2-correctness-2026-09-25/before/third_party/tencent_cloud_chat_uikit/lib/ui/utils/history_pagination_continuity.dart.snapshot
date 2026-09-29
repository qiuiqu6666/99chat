/// Continuity checks for history pagination merges.
///
/// Lists are **newest-first** (index 0 = newest), matching
/// `TUIChatGlobalModel.sortMessagesNewestFirst` / in-memory chat lists.
///
/// Older-page invariant: an older page may change the contiguous spine only
/// when it is proven to abut that spine; otherwise it may only produce gap
/// metadata.
class ContinuityDecision {
  const ContinuityDecision({
    required this.canMerge,
    required this.reason,
    this.existingMinSeq = 0,
    this.incomingMinSeq = 0,
    this.incomingMaxSeq = 0,
    this.missingLowerSeq = 0,
    this.missingUpperSeq = 0,
    this.olderAnchorSeq = 0,
    this.newerAnchorSeq = 0,
    this.overlapByMsgId = false,
    this.overlapBySeq = false,
  });

  final bool canMerge;
  final String reason;
  final int existingMinSeq;
  final int incomingMinSeq;
  final int incomingMaxSeq;

  /// Closed missing interval `[missingLowerSeq, missingUpperSeq]`.
  final int missingLowerSeq;
  final int missingUpperSeq;
  final int olderAnchorSeq;
  final int newerAnchorSeq;
  final bool overlapByMsgId;
  final bool overlapBySeq;

  bool get hasClosedGap =>
      missingLowerSeq > 0 &&
      missingUpperSeq > 0 &&
      missingLowerSeq <= missingUpperSeq;

  Map<String, Object?> toTraceExtras() => <String, Object?>{
        'canMerge': canMerge,
        'reason': reason,
        'existingMinSeq': existingMinSeq,
        'incomingMinSeq': incomingMinSeq,
        'incomingMaxSeq': incomingMaxSeq,
        'missingLowerSeq': missingLowerSeq,
        'missingUpperSeq': missingUpperSeq,
        'olderAnchorSeq': olderAnchorSeq,
        'newerAnchorSeq': newerAnchorSeq,
        'overlapByMsgId': overlapByMsgId,
        'overlapBySeq': overlapBySeq,
        'hasClosedGap': hasClosedGap,
      };
}

class HistoryPaginationContinuity {
  HistoryPaginationContinuity._();

  /// Conservative cloud deleted-seq slack. Never use pageSize as the bound.
  static const int defaultMaxCloudSeqGap = 5;

  /// Whether [incomingNewerNewestFirst] may be prepended onto
  /// [existingNewestFirst].
  ///
  /// Newer-side loads still trust the SDK cursor for direction only; group
  /// older-page continuity is enforced by [canAppendOlderBatch].
  static bool canPrependNewerBatch({
    required List<({int? seq, int? timestamp})> existingNewestFirst,
    required List<({int? seq, int? timestamp})> incomingNewerNewestFirst,
    int timeAbutSec = 0,
    ({int? seq, int? timestamp})? requestedAnchor,
    bool isGroup = false,
  }) {
    // Validate against the immutable request cursor, not the live head which
    // can advance while this request is pending. Otherwise a valid page
    // containing message 2 is rejected after realtime message 3 arrives.
    if (requestedAnchor != null) {
      return incomingNewerNewestFirst.every((message) {
        final anchorSeq = requestedAnchor.seq ?? 0;
        final seq = message.seq ?? 0;
        if (isGroup && anchorSeq > 0 && seq > 0) {
          return seq >= anchorSeq;
        }
        final anchorTs = requestedAnchor.timestamp ?? 0;
        final timestamp = message.timestamp ?? 0;
        return anchorTs <= 0 || timestamp <= 0 || timestamp >= anchorTs;
      });
    }
    if (incomingNewerNewestFirst.isEmpty || existingNewestFirst.isEmpty) {
      return true;
    }

    final existingNewest = existingNewestFirst.first;
    final incomingOldest = incomingNewerNewestFirst.last;

    final existingTs = existingNewest.timestamp ?? 0;
    final incomingTs = incomingOldest.timestamp ?? 0;
    if (existingTs > 0 && incomingTs > 0 && incomingTs < existingTs) {
      return false;
    }
    return true;
  }

  /// Whether an older page may be appended onto the current contiguous spine.
  ///
  /// Group allow rules:
  /// 1. msgID overlap
  /// 2. seq range intersection: incomingMinSeq <= existingMinSeq <= incomingMaxSeq
  /// 3. incomingMaxSeq == existingMinSeq - 1
  /// 4. cloud-backed only: deleted-seq gap in (0, [maxCloudSeqGap]]
  ///
  /// Reject when incomingMaxSeq < existingMinSeq - 1 without cloud relaxation.
  /// Do not treat incomingMaxSeq >= existingMinSeq alone as mergeable.
  static ContinuityDecision canAppendOlderBatch({
    required List<({int? seq, String? msgID})> existingNewestFirst,
    required List<({int? seq, String? msgID})> incomingOlderNewestFirst,
    required bool isGroup,
    required bool olderCloudBacked,
    int maxCloudSeqGap = defaultMaxCloudSeqGap,
  }) {
    if (incomingOlderNewestFirst.isEmpty) {
      return const ContinuityDecision(
        canMerge: true,
        reason: 'empty_incoming',
      );
    }
    if (existingNewestFirst.isEmpty) {
      return const ContinuityDecision(
        canMerge: true,
        reason: 'empty_existing',
      );
    }
    if (!isGroup) {
      return const ContinuityDecision(
        canMerge: true,
        reason: 'c2c_trust_sdk',
      );
    }

    final existingIds = <String>{};
    var existingMinSeq = 0;
    for (final row in existingNewestFirst) {
      final id = row.msgID?.trim() ?? '';
      if (_isLocalInjectedMsgId(id)) {
        continue;
      }
      if (id.isNotEmpty) {
        existingIds.add(id);
      }
      final seq = row.seq ?? 0;
      if (seq > 0 && (existingMinSeq == 0 || seq < existingMinSeq)) {
        existingMinSeq = seq;
      }
    }

    var incomingMinSeq = 0;
    var incomingMaxSeq = 0;
    var overlapByMsgId = false;
    for (final row in incomingOlderNewestFirst) {
      final id = row.msgID?.trim() ?? '';
      if (_isLocalInjectedMsgId(id)) {
        continue;
      }
      if (id.isNotEmpty && existingIds.contains(id)) {
        overlapByMsgId = true;
      }
      final seq = row.seq ?? 0;
      if (seq <= 0) {
        continue;
      }
      if (incomingMinSeq == 0 || seq < incomingMinSeq) {
        incomingMinSeq = seq;
      }
      if (seq > incomingMaxSeq) {
        incomingMaxSeq = seq;
      }
    }

    final overlapBySeq = existingMinSeq > 0 &&
        incomingMinSeq > 0 &&
        incomingMaxSeq > 0 &&
        incomingMinSeq <= existingMinSeq &&
        existingMinSeq <= incomingMaxSeq;
    final abut =
        existingMinSeq > 0 && incomingMaxSeq > 0 && incomingMaxSeq == existingMinSeq - 1;
    final deletedGap = existingMinSeq > 0 && incomingMaxSeq > 0
        ? existingMinSeq - incomingMaxSeq - 1
        : 0;
    final cloudRelax = olderCloudBacked &&
        deletedGap > 0 &&
        deletedGap <= maxCloudSeqGap;

    if (overlapByMsgId || overlapBySeq || abut || cloudRelax) {
      return ContinuityDecision(
        canMerge: true,
        reason: overlapByMsgId
            ? 'overlap_msg_id'
            : overlapBySeq
                ? 'overlap_seq'
                : abut
                    ? 'abut_seq'
                    : 'cloud_deleted_seq_relax',
        existingMinSeq: existingMinSeq,
        incomingMinSeq: incomingMinSeq,
        incomingMaxSeq: incomingMaxSeq,
        olderAnchorSeq: incomingMaxSeq,
        newerAnchorSeq: existingMinSeq,
        overlapByMsgId: overlapByMsgId,
        overlapBySeq: overlapBySeq,
      );
    }

    if (existingMinSeq <= 0 || incomingMaxSeq <= 0) {
      // No comparable group seq: local pages stay out; cloud pages keep SDK trust.
      if (olderCloudBacked) {
        return ContinuityDecision(
          canMerge: true,
          reason: 'no_seq_cloud_trust',
          existingMinSeq: existingMinSeq,
          incomingMinSeq: incomingMinSeq,
          incomingMaxSeq: incomingMaxSeq,
          olderAnchorSeq: incomingMaxSeq,
          newerAnchorSeq: existingMinSeq,
          overlapByMsgId: overlapByMsgId,
          overlapBySeq: overlapBySeq,
        );
      }
      return ContinuityDecision(
        canMerge: false,
        reason: 'no_seq_local_reject',
        existingMinSeq: existingMinSeq,
        incomingMinSeq: incomingMinSeq,
        incomingMaxSeq: incomingMaxSeq,
        olderAnchorSeq: incomingMaxSeq,
        newerAnchorSeq: existingMinSeq,
        overlapByMsgId: overlapByMsgId,
        overlapBySeq: overlapBySeq,
      );
    }

    if (incomingMaxSeq < existingMinSeq - 1) {
      final missingLower = incomingMaxSeq + 1;
      final missingUpper = existingMinSeq - 1;
      return ContinuityDecision(
        canMerge: false,
        reason: olderCloudBacked
            ? 'seq_disconnected_cloud'
            : 'seq_disconnected_local',
        existingMinSeq: existingMinSeq,
        incomingMinSeq: incomingMinSeq,
        incomingMaxSeq: incomingMaxSeq,
        missingLowerSeq: missingLower,
        missingUpperSeq: missingUpper,
        olderAnchorSeq: incomingMaxSeq,
        newerAnchorSeq: existingMinSeq,
        overlapByMsgId: overlapByMsgId,
        overlapBySeq: overlapBySeq,
      );
    }

    // incomingMaxSeq >= existingMinSeq without intersection means the page
    // does not cover the spine edge; do not invent a closed gap.
    return ContinuityDecision(
      canMerge: false,
      reason: 'seq_no_intersection',
      existingMinSeq: existingMinSeq,
      incomingMinSeq: incomingMinSeq,
      incomingMaxSeq: incomingMaxSeq,
      olderAnchorSeq: incomingMaxSeq,
      newerAnchorSeq: existingMinSeq,
      overlapByMsgId: overlapByMsgId,
      overlapBySeq: overlapBySeq,
    );
  }

  static bool _isLocalInjectedMsgId(String msgID) {
    return msgID.startsWith('ce_') ||
        msgID.startsWith('local_gt_') ||
        msgID.startsWith('local_') ||
        msgID.startsWith('gap_');
  }
}
