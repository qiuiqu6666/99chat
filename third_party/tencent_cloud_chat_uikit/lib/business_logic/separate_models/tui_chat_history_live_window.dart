part of 'tui_chat_separate_view_model.dart';

/// One connected reading window. Outgoing retention and realtime delivery are
/// separate stores: neither is allowed to advance this SDK pagination cursor.
class _HistoryLiveWindow {
  String? conversationID;
  V2TimMessage? newerCursor;
  V2TimMessage? expectedLatest;
  int revision = 0;
  Future<bool>? confirming;
  int attachBufferedTowardLatestAtMs = 0;
}

extension HistoryLiveWindow on TUIChatSeparateViewModel {
  /// A frozen reading cursor can still be connected to the live tail.
  /// Geometry/follow state never decides whether that connection exists.
  bool canAppendIncomingToReadingWindow() =>
      !haveMoreLatestData &&
      !_historyKnownTipMissing &&
      !globalModel.memoryWindowMissingNewer(conversationID) &&
      !globalModel.isSearchJumpPending(conversationID);

  void didAppendIncomingToReadingWindow(List<V2TimMessage> messages) {
    if (canAppendIncomingToReadingWindow()) {
      _acceptHistoryNewerPage(messages);
    }
  }

  bool get hasHistoryReadingWindow =>
      _historyLiveWindow.conversationID == conversationID &&
      _historyLiveWindow.newerCursor != null;

  int get historyReadingWindowRevision => _historyLiveWindow.revision;

  V2TimMessage? get historyNewerPageCursor =>
      hasHistoryReadingWindow ? _historyLiveWindow.newerCursor : null;

  V2TimMessage? _newestHistoryRow(Iterable<V2TimMessage> rows) {
    V2TimMessage? newest;
    for (final row in rows) {
      if (row.status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
          row.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL ||
          row.elemType == 11 ||
          row.elemType == 101 ||
          HistoryPaginationAnchor.isLocalInjectedMessage(row) ||
          !HistoryPaginationAnchor.canUseForSdkPagination(row)) continue;
      if (newest == null ||
          TUIChatGlobalModel.compareMessagesChronological(row, newest) > 0) {
        newest = row;
      }
    }
    return newest;
  }

  bool isOutgoingLocalOverlayRow(V2TimMessage message) {
    if (message.isSelf != true) {
      return false;
    }
    return message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING ||
        message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
  }

  bool shouldAttachOutgoingLocalOverlayToVisibleTimeline() {
    if (!hasHistoryReadingWindow) {
      return false;
    }
    final conv = conversationID;
    if (conv.isEmpty) {
      return false;
    }
    if (haveMoreLatestData) {
      return false;
    }
    if (globalModel.isSearchJumpPending(conv)) {
      return false;
    }
    if (globalModel.memoryWindowMissingNewer(conv)) {
      return false;
    }
    if (globalModel.getMessageListPosition(conv) ==
        HistoryMessagePosition.notShowLatest) {
      return false;
    }
    return true;
  }

  bool isVisibleOnReadingTimeline(V2TimMessage message) {
    final cursor = historyNewerPageCursor;
    if (cursor == null) {
      return true;
    }
    if (isMessageInHistoryReadingWindow(message)) {
      return true;
    }
    if (!shouldAttachOutgoingLocalOverlayToVisibleTimeline()) {
      return false;
    }
    if (isOutgoingLocalOverlayRow(message)) {
      return true;
    }
    return message.isSelf == true &&
        message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC &&
        readOutgoingStableId(message) != null;
  }

  void admitOwnConfirmedOutgoingToHistoryWindow(V2TimMessage message) {
    if (!hasHistoryReadingWindow) {
      return;
    }
    if (!shouldAttachOutgoingLocalOverlayToVisibleTimeline()) {
      return;
    }
    if (message.isSelf != true || isOutgoingLocalOverlayRow(message)) {
      return;
    }
    if (!HistoryPaginationAnchor.canUseForSdkPagination(message)) {
      return;
    }
    _acceptHistoryNewerPage(<V2TimMessage>[message]);
  }

  bool get _historyKnownTipMissing {
    final cursor = historyNewerPageCursor;
    final tip = _historyLiveWindow.expectedLatest;
    return cursor != null &&
        tip != null &&
        TUIChatGlobalModel.compareMessagesChronological(cursor, tip) < 0;
  }

  bool isMessageInHistoryReadingWindow(V2TimMessage message) {
    final cursor = historyNewerPageCursor;
    if (cursor == null) return true;
    // Keep sending/retained messages in their existing stores, but do not join
    // their newer segment to the middle of the reader's historical window.
    return TUIChatGlobalModel.compareMessagesChronological(message, cursor) <=
        0;
  }

  void _installHistoryReadingWindow(
      List<V2TimMessage> page, V2TimMessage? expectedLatest) {
    _historyLiveWindow
      ..conversationID = conversationID
      ..newerCursor = _newestHistoryRow(page)
      ..expectedLatest = expectedLatest;
    _historyLiveWindow.revision++;
    globalModel.setHistoryReadingWindowActive(conversationID, true);
  }

  /// Freeze the visible newest edge. Existing search/around-seq cursors stay.
  void freezeVisibleHistoryWindowIfNeeded() {
    if (hasHistoryReadingWindow) {
      return;
    }
    final page =
        globalModel.rawMessageList(conversationID) ?? const <V2TimMessage>[];
    _installHistoryReadingWindow(page, _conversationLastMessageHint());
  }

  void resumeVisibleLiveWindow() {
    _resumeVisibleLiveWindow(conversationID);
  }

  bool get hasHistoryKnownTipMissing => _historyKnownTipMissing;

  /// 数据允许接入。N/buffer 非空不能当门槛，也不能单独用来 COMMIT。
  bool get isLiveRestoreDataReady {
    final conv = conversationID;
    if (conv.isEmpty) {
      return false;
    }
    return !haveMoreLatestData &&
        !globalModel.memoryWindowMissingNewer(conv) &&
        !globalModel.hasDurableHistoryDeferred(conv) &&
        !globalModel.isSearchJumpPending(conv) &&
        !(hasHistoryReadingWindow && _historyKnownTipMissing);
  }

  /// 兼容名：只表示 [isLiveRestoreDataReady]。
  bool get hasCaughtUpToLiveLatest => isLiveRestoreDataReady;

  bool get didAttachBufferedTowardLatestRecently {
    final attachedAt = _historyLiveWindow.attachBufferedTowardLatestAtMs;
    return attachedAt > 0 &&
        DateTime.now().millisecondsSinceEpoch - attachedAt <
            ChatListPaginationUiGate.loadLatestCooldownMs;
  }

  bool revealBufferedIncomingTowardLatest({
    int? limit,
    bool skipCooldown = false,
  }) {
    final conv = conversationID;
    if (conv.isEmpty) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!skipCooldown &&
        now - _historyLiveWindow.attachBufferedTowardLatestAtMs <
            ChatListPaginationUiGate.loadLatestCooldownMs) {
      return false;
    }
    final page = globalModel.copyBufferedIncomingPage(
      conv,
      limit: limit != null && limit > 0
          ? limit
          : HistoryMessageDartConstant.revealBufferedTowardLatestFallbackCount,
    );
    if (page.isEmpty) {
      return false;
    }
    _historyLiveWindow.attachBufferedTowardLatestAtMs = now;
    freezeVisibleHistoryWindowIfNeeded();
    globalModel.beginAttachingBufferedTowardLatest();
    _acceptHistoryNewerPage(page);
    globalModel.commitBufferedIncomingReveal(conv, page);
    _notify();
    return true;
  }

  /// Compatibility for callers that previously treated admission as restore.
  /// This API has never committed FOLLOW or returned true.
  @Deprecated('Only reveals rows; use revealBufferedIncomingTowardLatest.')
  bool restoreTowardLatestFromUserScroll({int? revealLimit}) {
    if (!globalModel.isAttachingBufferedTowardLatest &&
        isLiveRestoreDataReady &&
        globalModel.deferredIncomingBufferedCount(conversationID) > 0) {
      revealBufferedIncomingTowardLatest(limit: revealLimit);
    }
    return false;
  }

  /// COMMIT：关窗 + FOLLOW + 迁 coveredIds。不 flush、不插行、不滚动、中间不 notify。
  bool commitLiveFollowRestore({
    required int visit,
    required int restoreOpId,
    required int liveReceiveGeneration,
    @Deprecated('Unused; visible coverage is represented by coveredIds.')
    String? targetTipId,
    required Set<String> coveredIds,
  }) {
    final conv = conversationID;
    if (conv.isEmpty || !isLiveRestoreDataReady) {
      return false;
    }
    if (globalModel.unreadVisitGenerationFor(conv) != visit) {
      return false;
    }
    if (globalModel.currentRestoreOpIdFor(conv) != restoreOpId) {
      return false;
    }
    if (globalModel.liveReceiveGenerationFor(conv) != liveReceiveGeneration) {
      return false;
    }
    if (globalModel.deferredIncomingBufferedCount(conv) > 0) {
      return false;
    }
    if (globalModel.unadmittedRemainingLiveCountFor(conv) > 0) {
      return false;
    }
    _clearHistoryReadingWindow();
    globalModel.setMemoryWindowSuppressed(conv, false);
    globalModel.clearMemoryWindowAnchor(conv);
    globalModel.migrateCoveredRemainingToSeen(conv, coveredIds);
    globalModel.setFollowingLatest(conv, true, notify: false, absorbUnread: false);
    globalModel.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    // The latest edge and every outstanding identity were proved visible for
    // this receive generation. Retire the reading visit's residual counter.
    globalModel.settleAtTrueLatestEnd(conv, notify: false);
    _notify();
    globalModel.notifyListeners();
    return true;
  }

  void _acceptHistoryNewerPage(List<V2TimMessage> page) {
    if (!hasHistoryReadingWindow) return;
    final next = _newestHistoryRow(page);
    final cursor = historyNewerPageCursor!;
    if (next != null &&
        TUIChatGlobalModel.compareMessagesChronological(next, cursor) > 0) {
      _historyLiveWindow.newerCursor = next;
      _historyLiveWindow.revision++;
    }
  }

  /// Rebase on the final window after a disk-backed trim and any rollback.
  /// Failed pixel restoration can still leave the smaller window committed;
  /// replaying newer pages must start at its retained edge in that case too.
  void rebaseHistoryReadingWindowAfterTrim() {
    if (!hasHistoryReadingWindow) return;
    final previous = historyNewerPageCursor!;
    final retained = _newestHistoryRow(
        (globalModel.rawMessageList(conversationID) ?? <V2TimMessage>[])
            .where(isMessageInHistoryReadingWindow));
    if (retained == null ||
        TUIChatGlobalModel.compareMessagesChronological(retained, previous) >=
            0) return;
    final tip = _historyLiveWindow.expectedLatest;
    if (tip == null ||
        TUIChatGlobalModel.compareMessagesChronological(previous, tip) > 0) {
      _historyLiveWindow.expectedLatest = previous;
    }
    _historyLiveWindow.newerCursor = retained;
    _historyLiveWindow.revision++;
    haveMoreLatestData = true;
    _notify();
  }

  void _clearHistoryReadingWindow() {
    final conv = _historyLiveWindow.conversationID ?? conversationID;
    _historyLiveWindow
      ..conversationID = null
      ..newerCursor = null
      ..expectedLatest = null;
    _historyLiveWindow.revision++;
    if (conv != null && conv.isNotEmpty) {
      globalModel.setHistoryReadingWindowActive(conv, false);
    }
  }

  /// The caller has confirmed the latest rendered edge. Keep the unread visit,
  /// receive generation and restore operation snapshot together in the model.
  bool commitFollowAfterVisibleLatestConfirm() =>
      _commitFollowAfterVisibleLatestConfirm(conversationID);

  bool _commitFollowAfterVisibleLatestConfirm(String conv) {
    if (conv.isEmpty || !isLiveRestoreDataReady) {
      return false;
    }
    if (globalModel.deferredIncomingBufferedCount(conv) > 0 ||
        globalModel.unadmittedRemainingLiveCountFor(conv) > 0) {
      return false;
    }
    final visit = globalModel.unreadVisitGenerationFor(conv);
    final receiveGen = globalModel.liveReceiveGenerationFor(conv);
    final op = globalModel.beginLiveFollowRestoreOp(conv);
    return commitLiveFollowRestore(
      visit: visit,
      restoreOpId: op,
      liveReceiveGeneration: receiveGen,
      coveredIds: globalModel.remainingLiveIncomingIdsFor(conv),
    );
  }

  void _resumeVisibleLiveWindow(String conv) {
    _commitFollowAfterVisibleLatestConfirm(conv);
  }

  /// Same durable capture/proof/ACK contract used by an explicit latest reload.
  /// This entry point runs only after the ordinary scroll path has painted the
  /// newest edge. Layout, route, owner and window ownership are rechecked after
  /// each asynchronous read; messages arriving after the capture survive ACK.
  Future<bool> confirmVisibleLatestWindow({
    required List<V2TimMessage> visibleMessages,
    required bool Function() isStillAtLatestEdge,
  }) {
    final pending = _historyLiveWindow.confirming;
    if (pending != null) return pending;
    if (haveMoreLatestData ||
        !isStillAtLatestEdge() ||
        globalModel.isSearchJumpPending(conversationID) ||
        // Durable hot rows are pending proof, not a disconnected page to
        // reveal. Their captured prefix is cleared only after visible coverage
        // succeeds below; blocking on them here would also block their ACK.
        (globalModel.deferredIncomingBufferedCount(conversationID) > 0 &&
            !globalModel.hasDurableHistoryDeferred(conversationID)) ||
        _historyKnownTipMissing ||
        globalModel.isAttachingBufferedTowardLatest ||
        didAttachBufferedTowardLatestRecently ||
        (!hasHistoryReadingWindow &&
            !globalModel.hasDurableHistoryDeferred(conversationID))) {
      return Future<bool>.value(false);
    }
    final conv = conversationID;
    final generation = _historyWindowGeneration;
    final revision = historyReadingWindowRevision;
    final ownerCurrent = globalModel.captureMessageOwnerFence(conv);
    bool current() =>
        !_disposed &&
        conversationID == conv &&
        generation == _historyWindowGeneration &&
        revision == historyReadingWindowRevision &&
        ownerCurrent() &&
        !haveMoreLatestData &&
        isStillAtLatestEdge() &&
        !globalModel.isSearchJumpPending(conv);
    if (!globalModel.hasDurableHistoryDeferred(conv)) {
      final projectedIDs = visibleMessages
          .map(TUIChatGlobalModel.liveIncomingIdentity).toSet();
      if (!projectedIDs.containsAll(globalModel.remainingLiveIncomingIdsFor(conv))) {
        return Future<bool>.value(false);
      }
      if (!current()) return Future<bool>.value(false);
      return Future<bool>.value(_commitFollowAfterVisibleLatestConfirm(conv));
    }
    late final Future<bool> operation;
    operation = (() async {
      try {
        final watermark =
            await globalModel.beginHistoryWindowReturnToLatest(conv);
        if (!current()) return false;
        final covered = await globalModel
            .confirmHistoryWindowReturnCoversDeferred(conv, watermark,
                visibleMessages: visibleMessages);
        if (!current() || !covered) return false;
        await globalModel.acknowledgeHistoryWindowReturnToLatest(
            conv, watermark);
        if (!current()) return false;
        if (!globalModel.hasDurableHistoryDeferred(conv)) {
          return _commitFollowAfterVisibleLatestConfirm(conv);
        }
        return true;
      } catch (_) {
        // Keep the durable state for a later scroll or explicit retry.
        return false;
      }
    })()
        .whenComplete(() {
      if (identical(_historyLiveWindow.confirming, operation)) {
        _historyLiveWindow.confirming = null;
      }
    });
    _historyLiveWindow.confirming = operation;
    return operation;
  }
}
