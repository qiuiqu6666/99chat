part of 'tui_chat_global_model.dart';

class _BoundedHistorySession {
  _BoundedHistorySession(this.scope);
  final HistoryWindowScope scope;
  int generation = 0;
  int? snapshot;
  HistoryWindowTrimTicket? trim;
  bool revealDeferredAtLatest = false;
}

class _BoundedHistoryState {
  final sessions = LinkedHashMap<String, _BoundedHistorySession>();
  int sessionSequence = 0;
  int mutationSequence = 0;
  final pendingProjections = <String, Set<String>>{};
  final completedProjections = <String>{};
  final nonce = DateTime.now().microsecondsSinceEpoch;
}

final _boundedHistoryModels = Expando<_BoundedHistoryState>();

/// A bounded working window backed by independently persisted pages. The
/// repository contains no UI objects; this extension keeps at most four scopes
/// and one short-lived trim per scope. SDK callbacks await durable admission.
extension BoundedChatHistory on TUIChatGlobalModel {
  _BoundedHistoryState get _boundedHistory =>
      _boundedHistoryModels[this] ??= _BoundedHistoryState();

  HistoryWindowScope? historyWindowScopeFor(String conversationID) {
    final writerScope = _messageReconciliationWriter.configuredScope;
    if (HistoryWindowRepositoryProvider.repository == null ||
        writerScope == null ||
        writerScope.normalizedOwnerUserID.isEmpty) return null;
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conversationID);
    if (key.isEmpty) return null;
    final epoch = messageDeltaClearEpochFor(key);
    final state = _boundedHistory;
    var session = state.sessions[key];
    if (session != null &&
        (session.scope.ownerUserID != writerScope.normalizedOwnerUserID ||
            session.scope.accountGeneration != writerScope.accountGeneration ||
            session.scope.domainGeneration != writerScope.domainGeneration ||
            session.scope.clearEpoch != epoch)) {
      _closeBoundedHistorySession(state.sessions.remove(key)!);
      session = null;
    }
    if (session == null) {
      while (state.sessions.length >= 4) {
        final victim = state.sessions.keys.firstWhere(
            (entry) => !_isSameConversationID(entry, currentSelectedConv),
            orElse: () => state.sessions.keys.first);
        _closeBoundedHistorySession(state.sessions.remove(victim)!);
      }
      late final HistoryWindowScope newScope;
      newScope = HistoryWindowScope(
        ownerUserID: writerScope.normalizedOwnerUserID,
        accountGeneration: writerScope.accountGeneration,
        domainGeneration: writerScope.domainGeneration,
        conversationID: key,
        clearEpoch: epoch,
        sessionID: '${state.nonce}:${++state.sessionSequence}',
        isCurrent: () => isHistoryWindowScopeCurrent(newScope),
      );
      session = _BoundedHistorySession(newScope);
      state.sessions[key] = session;
    } else {
      state.sessions.remove(key);
      state.sessions[key] = session;
    }
    return session.scope;
  }

  bool isHistoryWindowScopeCurrent(HistoryWindowScope scope) {
    final writer = _messageReconciliationWriter.configuredScope;
    return writer != null &&
        writer.normalizedOwnerUserID == scope.ownerUserID &&
        writer.accountGeneration == scope.accountGeneration &&
        writer.domainGeneration == scope.domainGeneration &&
        messageDeltaClearEpochFor(scope.conversationID) == scope.clearEpoch &&
        identical(_boundedHistory.sessions[scope.conversationID]?.scope, scope);
  }

  void _closeBoundedHistorySession(_BoundedHistorySession session) {
    session.generation++;
    session.trim?.release();
    session.trim = null;
    // The durable bucket retains exact counters. Release inactive hot bodies
    // with the four-scope LRU instead of keeping 120 objects for every chat.
    final unread =
        _inboundUnreadStateFor(session.scope.conversationID, create: false);
    unread.bufferedMessages
      ..clear()
      ..addAll(unread.pendingLegacyMessages.values);
    unread.bufferedMessageKeys
      ..clear()
      ..addAll(unread.pendingLegacyMessages.keys);
    final repository = HistoryWindowRepositoryProvider.repository;
    if (repository != null) {
      unawaited(
          repository.closeSession(session.scope).catchError((Object _) {}));
    }
  }

  void invalidateBoundedHistorySessions() {
    final sessions = _boundedHistory.sessions.values.toList(growable: false);
    _boundedHistory.sessions.clear(); // fence before asynchronous cleanup
    for (final session in sessions) {
      _closeBoundedHistorySession(session);
    }
  }

  bool historyWindowNeedsTrim(String conversationID) {
    if (!ChatMessageWindowPolicy.enabled) {
      return false;
    }
    final scope = historyWindowScopeFor(conversationID);
    return scope != null &&
        (_messageListMap[scope.conversationID]?.length ?? 0) >
            ChatMessageWindowPolicy.targetSize;
  }

  bool historyWindowPaginationBlocked(String conversationID) {
    if (!ChatMessageWindowPolicy.enabled) {
      return false;
    }
    final scope = historyWindowScopeFor(conversationID);
    return scope != null &&
        (_boundedHistory.sessions[scope.conversationID]?.trim != null ||
            (_messageListMap[scope.conversationID]?.length ?? 0) +
                    _messageReconciliationWriter
                        .pendingRealtimeCount(scope.conversationID) >=
                ChatMessageWindowPolicy.paginationHighWater);
  }

  bool historyWindowCanReadNewer(String conversationID) =>
      historyWindowScopeFor(conversationID) != null &&
      memoryWindowMissingNewer(conversationID);

  void noteHistoryWindowSnapshot(String conversationID, int? snapshot) {
    final scope = historyWindowScopeFor(conversationID);
    if (scope == null || snapshot == null) return;
    final session = _boundedHistory.sessions[scope.conversationID]!;
    if (session.snapshot != null && session.snapshot != snapshot) {
      throw StateError('history snapshots cannot be mixed');
    }
    session.snapshot = snapshot;
  }

  Future<List<V2TimMessage>> applyHistoryWindowMutations(
      String conversationID, List<V2TimMessage> messages) async {
    final scope = historyWindowScopeFor(conversationID);
    if (scope == null) return messages;
    final result = await HistoryWindowRepositoryProvider.repository!
        .applyMutations(scope: scope, messages: messages);
    if (!isHistoryWindowScopeCurrent(scope))
      throw const HistoryWindowStaleScope();
    return result;
  }

  bool _shouldProjectHistoryWindowEdit(
      String conversationID, V2TimMessage message) {
    if (HistoryWindowRepositoryProvider.repository == null) return true;
    final msgID = message.msgID?.trim() ?? '';
    final localID = message.id?.trim() ?? '';
    if (isMessageInMemoryWindow(conversationID,
            msgID: msgID,
            seq: message.groupID?.isNotEmpty == true ? message.seq : null) ||
        (localID.isNotEmpty &&
            localID != msgID &&
            isMessageInMemoryWindow(conversationID, msgID: localID)))
      return true;
    // A receipt can replace an existing optimistic outgoing identity. Other
    // off-window edits belong only to the durable authority until paged in.
    return message.isSelf == true &&
        findReplaceableOutgoingIndex(conversationID, message,
                priorTempId: localID) >=
            0;
  }

  String _historyMutationProjectionKey(HistoryWindowScope scope) => jsonEncode([
        scope.ownerUserID,
        scope.accountGeneration,
        scope.domainGeneration,
        scope.conversationID,
        scope.clearEpoch,
      ]);

  /// A failed command stays protected until its UI rollback has also finished.
  /// SQL completion alone must not let an optimistic copy become a page base.
  void finishHistoryWindowMutationProjection({
    required HistoryWindowScope scope,
    required String token,
  }) {
    final state = _boundedHistory;
    if (!state.completedProjections.remove(token)) return;
    final key = _historyMutationProjectionKey(scope);
    final tokens = state.pendingProjections[key];
    if (tokens == null || !tokens.remove(token)) return;
    if (tokens.isEmpty) state.pendingProjections.remove(key);
    _markNeedsNotify(); // retry a capacity-blocked idle trim after the command
  }

  bool _hasPendingHistoryProjection(HistoryWindowScope scope) =>
      _boundedHistory.pendingProjections[_historyMutationProjectionKey(scope)]
          ?.isNotEmpty ??
      false;

  Future<String?> recordHistoryWindowMutation({
    String? conversationID,
    required String msgID,
    required HistoryWindowMutationKind kind,
    V2TimMessage? message,
    String? eventID,
    int revision = 0,
    String? restoreMutationToken,
    HistoryWindowScope? capturedScope,
    bool pending = false,
  }) async {
    final repository = HistoryWindowRepositoryProvider.repository;
    final writer = _messageReconciliationWriter.configuredScope;
    if (repository == null || msgID.trim().isEmpty) return null;
    if (capturedScope != null) {
      if ((kind != HistoryWindowMutationKind.restore &&
              kind != HistoryWindowMutationKind.settle) ||
          restoreMutationToken == null) {
        throw ArgumentError(
            'Captured scope is only valid for an exact-token completion');
      }
      // A failed command must be undone even after its view/account left.
      // The store accepts only the matching existing token and clear epoch;
      // this path never authorizes a new mutation under an old account.
      final token = eventID ??
          'restore:${_boundedHistory.nonce}:${++_boundedHistory.mutationSequence}';
      final completion = HistoryWindowMutation(
          ownerUserID: capturedScope.ownerUserID,
          conversationID: capturedScope.conversationID,
          clearEpoch: capturedScope.clearEpoch,
          eventID: token,
          msgID: msgID,
          kind: kind,
          message: message,
          restoreMutationToken: restoreMutationToken);
      while (true) {
        await SqfliteLifecycleHost.waitUntilWritesAllowed();
        try {
          await repository.recordMutation(completion);
          break;
        } on SqfliteClosedForBackground {
          // A pause can race the foreground gate. Keep the exact completion
          // token until resume; no new command is admitted by this retry.
        } on HistoryWindowStaleScope {
          // Captured completions carry no live session authorization. Their
          // remaining permanent fence is a newer conversation clear epoch,
          // which has already removed the old pending command atomically.
          break;
        }
      }
      if (_boundedHistory
              .pendingProjections[_historyMutationProjectionKey(capturedScope)]
              ?.contains(restoreMutationToken) ==
          true) {
        _boundedHistory.completedProjections.add(restoreMutationToken);
      }
      if (kind == HistoryWindowMutationKind.settle) {
        finishHistoryWindowMutationProjection(
            scope: capturedScope, token: restoreMutationToken);
      }
      return token;
    }
    if (writer == null) return null;
    final key = (conversationID?.trim().isNotEmpty ?? false)
        ? TUIChatGlobalModel.canonicalHistoryStorageKey(conversationID!)
        : null;
    final scope = key == null ? null : historyWindowScopeFor(key);
    bool isCurrent() =>
        _messageReconciliationWriter.configuredScope == writer &&
        (scope == null || isHistoryWindowScopeCurrent(scope));
    final localSequence = ++_boundedHistory.mutationSequence;
    final token = eventID ?? 'local:${_boundedHistory.nonce}:$localSequence';
    // Register before the first await; preparation and its raw snapshot are
    // synchronous, so every saved UI page predates any later optimistic edit.
    final projectionKey =
        pending && scope != null ? _historyMutationProjectionKey(scope) : null;
    if (projectionKey != null) {
      (_boundedHistory.pendingProjections[projectionKey] ??= <String>{})
          .add(token);
    }
    try {
      await repository.recordMutation(HistoryWindowMutation(
        ownerUserID: writer.normalizedOwnerUserID,
        conversationID: key,
        clearEpoch: key == null ? 0 : messageDeltaClearEpochFor(key),
        eventID: token,
        msgID: msgID,
        kind: kind,
        message: message,
        revision: pending ? localSequence : revision,
        pending: pending,
        restoreMutationToken: restoreMutationToken,
        authorizationScope: scope,
        isCurrent: isCurrent,
        sourceKey: pending
            ? 'command:${_boundedHistory.nonce}'
            : revision > 0
                ? 'ingress:${writer.accountGeneration}:${writer.domainGeneration}'
                : null,
      ));
    } catch (_) {
      if (projectionKey != null) {
        final tokens = _boundedHistory.pendingProjections[projectionKey];
        tokens?.remove(token);
        if (tokens?.isEmpty == true) {
          _boundedHistory.pendingProjections.remove(projectionKey);
        }
      }
      rethrow;
    }
    // Pending command callers need the committed token to compensate if their
    // view expires in the gap after SQLite commits and before this resumes.
    if (!isCurrent() && !pending) {
      throw const HistoryWindowStaleScope();
    }
    return token;
  }

  Future<void> clearHistoryWindowData(
      String conversationID, int clearEpoch) async {
    final writer = _messageReconciliationWriter.configuredScope;
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conversationID);
    final session = _boundedHistory.sessions.remove(key);
    if (session != null) _closeBoundedHistorySession(session);
    final stateKey = _inboundStateKey(conversationID);
    _inboundUnreadStateByConversation.remove(stateKey);
    _deferredUntilUserBottomConversations.remove(stateKey);
    if (writer != null) {
      await HistoryWindowRepositoryProvider.repository?.clearConversation(
          ownerUserID: writer.normalizedOwnerUserID,
          conversationID: key,
          clearEpoch: clearEpoch);
    }
  }

  Future<HistoryWindowTrimTicket?> prepareHistoryWindowTrim({
    required String conversationID,
    required String anchorMsgID,
    String? anchorSeq,
  }) async {
    final scope = historyWindowScopeFor(conversationID);
    if (scope == null ||
        !_isSameConversationID(conversationID, currentSelectedConv) ||
        _messageReconciliationWriter.hasActiveRequest(scope.conversationID))
      return null;
    final session = _boundedHistory.sessions[scope.conversationID]!;
    if (session.trim != null || _hasPendingHistoryProjection(scope))
      return null;
    final before = _mergedAliasMessageList(conversationID);
    if (before.length <= ChatMessageWindowPolicy.targetSize ||
        !before.any((message) =>
            message.msgID == anchorMsgID ||
            message.id == anchorMsgID ||
            (anchorSeq?.isNotEmpty == true && message.seq == anchorSeq)))
      return null;
    final trimmed = ChatMessageWindow.trimToWindow(
        list: before,
        anchorMsgID: anchorMsgID,
        anchorSeq: anchorSeq,
        softMax: ChatMessageWindowPolicy.targetSize,
        targetSize: ChatMessageWindowPolicy.targetSize);
    if (!trimmed.didTrim) return null;
    final ticket = HistoryWindowTrimTicket(
        scope: scope,
        conversationID: scope.conversationID,
        rawRevision: messageListRevisionFor(scope.conversationID),
        writerRevision:
            _messageReconciliationWriter.revisionFor(scope.conversationID),
        generation: session.generation,
        anchorMsgID: anchorMsgID,
        anchorSeq: anchorSeq,
        before: before,
        after: trimmed.list,
        wasMissingOlder: memoryWindowMissingOlder(conversationID),
        wasMissingNewer: memoryWindowMissingNewer(conversationID),
        removedOlder: trimmed.trimmedAwayOldestInMemory,
        removedNewer: trimmed.trimmedAwayLatest);
    session.trim = ticket;
    try {
      final chunks = <List<V2TimMessage>>[];
      for (var start = 0; start < before.length; start += 50) {
        chunks.add(before.sublist(start, min(start + 50, before.length)));
      }
      final keys = chunks
          .map((chunk) => 'window:${jsonEncode([
                    _commitSnapshotIdentity(chunk.first),
                    _commitSnapshotIdentity(chunk.last)
                  ])}')
          .toList(growable: false);
      await HistoryWindowRepositoryProvider.repository!.savePages([
        for (var i = 0; i < chunks.length; i++)
          HistoryWindowPage(
            scope: scope,
            pageKey: keys[i],
            messages: chunks[i],
            newerPageKey: i == 0 ? null : keys[i - 1],
            olderPageKey: i + 1 == keys.length ? null : keys[i + 1],
            snapshotMaxSeq: session.snapshot,
          ),
      ]);
      if (!_historyTrimTicketCurrent(ticket, beforeCommit: true)) {
        finishHistoryWindowTrim(ticket);
        return null;
      }
      return ticket;
    } catch (_) {
      finishHistoryWindowTrim(ticket);
      rethrow; // UI keeps the original window and may retry after storage recovers.
    }
  }

  bool _historyTrimTicketCurrent(HistoryWindowTrimTicket ticket,
      {bool beforeCommit = false}) {
    final session = _boundedHistory.sessions[ticket.scope.conversationID];
    return !ticket.finished &&
        isHistoryWindowScopeCurrent(ticket.scope) &&
        identical(session?.trim, ticket) &&
        session!.generation == ticket.generation &&
        _isSameConversationID(ticket.conversationID, currentSelectedConv) &&
        (!beforeCommit ||
            (messageListRevisionFor(ticket.conversationID) ==
                    ticket.rawRevision &&
                _messageReconciliationWriter
                        .revisionFor(ticket.conversationID) ==
                    ticket.writerRevision));
  }

  bool commitHistoryWindowTrim(HistoryWindowTrimTicket ticket) {
    if (!_historyTrimTicketCurrent(ticket, beforeCommit: true)) return false;
    final commit = _messageReconciliationWriter.commitRetainedWindow(
        conversationID: ticket.conversationID,
        expectedRevision: ticket.writerRevision,
        expectedClearEpoch: ticket.scope.clearEpoch,
        expectedScope: _messageReconciliationWriter.configuredScope,
        retainedValues: ticket.after,
        generation: messageDeltaGenerationFor(ticket.conversationID));
    if (commit == null) return false;
    if (ticket.removedOlder)
      markMemoryWindowMissingOlder(ticket.conversationID);
    if (ticket.removedNewer)
      markMemoryWindowMissingNewer(ticket.conversationID);
    setMessageList(ticket.conversationID, ticket.after,
        replace: true,
        needResetNewMessageCount: false,
        applyMemoryWindow: false,
        preserveInFlightOutgoing: false,
        writerCommit: commit,
        historyCommitSource: 'bounded_idle_trim');
    ticket.committed = true;
    return true;
  }

  Future<bool> rollbackHistoryWindowTrim(HistoryWindowTrimTicket ticket) async {
    if (!ticket.committed || !_historyTrimTicketCurrent(ticket)) return false;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_historyTrimTicketCurrent(ticket) ||
          _messageReconciliationWriter.hasActiveRequest(ticket.conversationID))
        return false;
      final revision = messageListRevisionFor(ticket.conversationID);
      final writerRevision =
          _messageReconciliationWriter.revisionFor(ticket.conversationID);
      // A send or callback can add rows after the trim commit. Keep all of
      // those identities, not just replacements of the old membership.
      final combined = {
        for (final message in ticket.before)
          _commitSnapshotIdentity(message): message
      };
      for (final message in _mergedAliasMessageList(ticket.conversationID)) {
        combined[_commitSnapshotIdentity(message)] = message;
      }
      final restored = await applyHistoryWindowMutations(
          ticket.conversationID, combined.values.toList(growable: false));
      if (!_historyTrimTicketCurrent(ticket)) return false;
      if (messageListRevisionFor(ticket.conversationID) != revision ||
          _messageReconciliationWriter.revisionFor(ticket.conversationID) !=
              writerRevision) continue;
      // Do not overwrite a replacement history request or trade a failed
      // viewport restore for an unbounded window. The committed window stays
      // valid and all evicted pages remain durable for subsequent navigation.
      if (restored.length > ChatMessageWindowPolicy.softMax ||
          _messageReconciliationWriter.hasActiveRequest(ticket.conversationID))
        return false;
      final result = setMessageList(ticket.conversationID, restored,
          replace: true,
          needResetNewMessageCount: false,
          applyMemoryWindow: false,
          preserveInFlightOutgoing: false,
          historyCommitSource: 'bounded_trim_rollback');
      if (!isMessageCommitCurrent(result) ||
          result.rawCount != restored.length ||
          _messageReconciliationWriter
                  .recordsFor(ticket.conversationID)
                  .length !=
              restored.length) {
        return false;
      }
      _memoryWindowMissingNewerByConv[ticket.conversationID] =
          ticket.wasMissingNewer;
      _memoryWindowMissingOlderByConv[ticket.conversationID] =
          ticket.wasMissingOlder;
      return true;
    }
    return false;
  }

  void finishHistoryWindowTrim(HistoryWindowTrimTicket ticket) {
    final session = _boundedHistory.sessions[ticket.scope.conversationID];
    if (identical(session?.trim, ticket)) session!.trim = null;
    ticket.release();
  }

  /// Narrows the visible window of the current conversation to a freshly
  /// committed continuous latest window.
  ///
  /// Must be called right after the latest-window batch was committed through
  /// the reconciliation writer, so every row in the merged projection is the
  /// same object instance the writer holds. Rows older than the window that are
  /// not part of it are evicted from memory only; the SDK local database keeps
  /// them and upward pagination reconnects from the window's oldest anchor.
  /// Newer realtime rows, uncorrelated in-flight sends and preserved local
  /// group tips that are not older than the window are retained.
  bool restampVisibleWindowToLatest({
    required String conversationID,
    required List<V2TimMessage> latestWindow,
  }) {
    if (latestWindow.isEmpty) return false;
    final scope = historyWindowScopeFor(conversationID);
    if (scope == null ||
        !_isSameConversationID(conversationID, currentSelectedConv) ||
        _messageReconciliationWriter.hasActiveRequest(scope.conversationID)) {
      return false;
    }
    final session = _boundedHistory.sessions[scope.conversationID];
    if (session == null ||
        session.trim != null ||
        _hasPendingHistoryProjection(scope)) {
      return false;
    }
    final before = _mergedAliasMessageList(conversationID);
    if (before.isEmpty) return true;
    final windowIdentities = <String>{
      for (final message in latestWindow) _commitSnapshotIdentity(message),
    };
    V2TimMessage? newest;
    V2TimMessage? oldest;
    for (final message in latestWindow) {
      if (newest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, newest) >
              0) {
        newest = message;
      }
      if (oldest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, oldest) <
              0) {
        oldest = message;
      }
    }
    final inFlight = Set<V2TimMessage>.identity()
      ..addAll(TUIChatGlobalModel.collectUncorrelatedInFlightOutgoing(
        previous: before,
        incoming: latestWindow,
      ));
    final retained = <V2TimMessage>[];
    for (final row in before) {
      if (windowIdentities.contains(_commitSnapshotIdentity(row)) ||
          inFlight.contains(row) ||
          TUIChatGlobalModel.compareMessagesChronological(row, newest!) > 0 ||
          (TUIChatGlobalModel._isPreservedLocalGroupTip(row) &&
              TUIChatGlobalModel.compareMessagesChronological(row, oldest!) >=
                  0)) {
        retained.add(row);
      }
    }
    if (retained.length == before.length) return true;
    final commit = _messageReconciliationWriter.commitRetainedWindow(
      conversationID: scope.conversationID,
      expectedRevision:
          _messageReconciliationWriter.revisionFor(scope.conversationID),
      expectedClearEpoch: scope.clearEpoch,
      expectedScope: _messageReconciliationWriter.configuredScope,
      retainedValues: retained,
      generation: messageDeltaGenerationFor(scope.conversationID),
    );
    if (commit == null) return false;
    markMemoryWindowMissingOlder(scope.conversationID);
    setMessageList(
      scope.conversationID,
      retained,
      replace: true,
      needResetNewMessageCount: false,
      applyMemoryWindow: false,
      preserveInFlightOutgoing: false,
      writerCommit: commit,
      historyCommitSource: 'latest_window_restamp',
    );
    return true;
  }

  /// Keep SQL admission/ACK and their UI publication in the same conversation
  /// order. Otherwise an ACK can publish an old count after a newer admission.
  Future<T> _serializeHistoryDeferred<T>(String conversationID,
      Future<T> Function(_InboundUnreadState state) operation,
      {bool admission = false}) {
    final state = _inboundUnreadStateFor(conversationID);
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    state.durableOperationCount++;
    if (admission) state.pendingDurableAdmissions++;
    final result = state.deferredOperationTail.then((_) async {
      if (!ownerCurrent() ||
          !identical(
              _inboundUnreadStateFor(conversationID, create: false), state)) {
        throw const HistoryWindowStaleScope();
      }
      return operation(state);
    }).whenComplete(() {
      state.durableOperationCount--;
      if (admission) state.pendingDurableAdmissions--;
    });
    // A failed operation must not poison subsequent retries.
    state.deferredOperationTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  /// Start a presentation visit without acknowledging or deleting old deliveries.
  /// Queue the baseline before any new admission; foreground resume and cache
  /// replacement intentionally do not start another visit.
  Future<void> beginHistoryUnreadVisit(String conversationID) {
    final state = _inboundUnreadStateFor(conversationID);
    final generation = ++state.unreadVisitGeneration;
    state.revealedUnreadMessageIDs.clear();
    // The previous page's reading hold is presentation state, not an ACK.
    // A new page may load a fresh latest window while its old durable backlog
    // is still awaiting coverage. Keep all records/counters below intact.
    _deferredUntilUserBottomConversations
        .remove(_inboundStateKey(conversationID));
    if (historyWindowScopeFor(conversationID) == null) {
      clearReceivedNewMessageCount(conversationID: conversationID);
      return Future<void>.value();
    }
    state.unreadVisitBaselinePending = true;
    state.unreadVisitLegacyKeys
      ..clear()
      ..addAll(state.pendingLegacyMessages.keys);
    state.receivedCount = 0;
    state.durableUnreadCount = 0;
    state.unreadCount = state.lockedEntryUnreadCount;
    return _serializeHistoryDeferred(conversationID, (state) async {
      await _ensureHistoryUnreadVisitBaseline(
          conversationID, state, generation);
      _markNeedsNotify();
    });
  }

  Future<void> _ensureHistoryUnreadVisitBaseline(
      String conversationID, _InboundUnreadState state, int generation) async {
    if (generation != state.unreadVisitGeneration ||
        !state.unreadVisitBaselinePending) return;
    final scope = historyWindowScopeFor(conversationID);
    final repository = HistoryWindowRepositoryProvider.repository;
    if (scope == null || repository == null)
      throw const HistoryWindowStaleScope();
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    // Capture only legacy rows which predate this visit. Synchronous coalescer
    // callbacks can still add new rows while the SQL baseline is being read.
    final oldKeys = state.unreadVisitLegacyKeys.toList(growable: false);
    await _persistCoalescedHistoryDeferred(
        conversationID, state, scope, repository,
        keys: oldKeys);
    final counts = await repository.deferredState(scope);
    if (!ownerCurrent() ||
        !identical(
            _inboundUnreadStateFor(conversationID, create: false), state)) {
      throw const HistoryWindowStaleScope();
    }
    if (generation != state.unreadVisitGeneration) return;
    state.unreadVisitBaselineReceived = counts.receivedCount;
    state.unreadVisitBaselineUnread = counts.unreadCount;
    state.unreadVisitBaselineSequence = counts.lastIngressSequence ??
        (counts.acknowledgedThroughSequence > 0
            ? counts.acknowledgedThroughSequence
            : -1);
    state.unreadVisitBaselinePending = false;
    state.unreadVisitLegacyKeys.clear();
    _publishHistoryDeferredState(conversationID, state, counts);
  }

  void _publishHistoryDeferredState(String conversationID,
      _InboundUnreadState state, HistoryWindowDeferredState counts) {
    state.durableDeferred = counts.receivedCount > 0;
    final holdsCurrentHistoryViewport =
        _isSameConversationID(conversationID, currentSelectedConv) &&
            (isReadingHistory(currentSelectedConv) ||
                isSearchJumpPending(conversationID) ||
                memoryWindowMissingNewer(conversationID));
    if ((state.durableDeferred || state.pendingLegacyMessages.isNotEmpty) &&
        holdsCurrentHistoryViewport) {
      _deferredUntilUserBottomConversations
          .add(_inboundStateKey(conversationID));
    } else {
      _deferredUntilUserBottomConversations
          .remove(_inboundStateKey(conversationID));
    }
    // An older queued admission may finish after a new visit starts. Keep its
    // durable result, but wait for that visit's ordered baseline to publish UI.
    if (state.unreadVisitBaselinePending) return;
    if (state.trueLatestEndAbsorbed &&
        isFollowingLatest(conversationID) &&
        !isReadingHistory(conversationID) &&
        !memoryWindowMissingNewer(conversationID) &&
        !isSearchJumpPending(conversationID)) {
      state.unreadVisitBaselineReceived = counts.receivedCount;
      state.unreadVisitBaselineUnread = counts.unreadCount;
      state.durableDeferred = false;
      state.durableUnreadCount = 0;
      state.receivedCount = 0;
      state.unreadCount = state.lockedEntryUnreadCount;
      return;
    }
    state.durableUnreadCount =
        max(0, counts.unreadCount - state.unreadVisitBaselineUnread);
    final publishedReceived =
        max(0, counts.receivedCount - state.unreadVisitBaselineReceived) +
            state.pendingLegacyMessages.length +
            state.revealedUnreadMessageIDs.length;
    // 看历史时 tongue N 不因滑过已画行 / SQL ACK 而减少；真跟随下以进消息路径为准。
    if (isFollowingLatest(conversationID) &&
        !isReadingHistory(conversationID)) {
      state.receivedCount = publishedReceived;
    } else {
      state.receivedCount = max(state.receivedCount, publishedReceived);
    }
    state.unreadCount = state.lockedEntryUnreadCount +
        state.durableUnreadCount +
        state.pendingLegacyMessages.length +
        state.revealedUnreadMessageIDs.length;
  }

  /// An accepted deletion retires local-only unread identities. Optimistic
  /// removal and memory-window trimming must never call this.
  void retireDeletedLocalIncoming(String conversationID, Iterable<String> ids) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    final removed = ids.where(state.revealedUnreadMessageIDs.contains).toSet();
    if (removed.isEmpty) return;
    state.revealedUnreadMessageIDs.removeAll(removed);
    state.receivedCount = max(0, state.receivedCount - removed.length);
    state.unreadCount = max(state.lockedEntryUnreadCount,
        state.unreadCount - removed.length);
    _markNeedsNotify();
  }

  bool Function() captureHistoryUnreadVisitFence(String conversationID) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    final visit = state.unreadVisitGeneration;
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    return () => ownerCurrent() &&
        identical(_inboundUnreadStateFor(conversationID, create: false), state) &&
        state.unreadVisitGeneration == visit;
  }

  /// A loaded page is not a read receipt. Consume only identities behind the
  /// measured reading edge; keep earlier visits' baseline for final proof.
  Future<bool> acknowledgeVisibleHistoryMessages(
    String conversationID,
    Iterable<V2TimMessage> visibleMessages, {
    required bool Function() isCurrent,
  }) {
    final state = _inboundUnreadStateFor(conversationID, create: false);
    final visit = state.unreadVisitGeneration;
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    final ids = visibleMessages
        .map((message) => (message.msgID?.trim().isNotEmpty ?? false)
            ? message.msgID!.trim()
            : message.id?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    bool ownerAndVisitCurrent() =>
        ownerCurrent() &&
        identical(_inboundUnreadStateFor(conversationID, create: false), state) &&
        state.unreadVisitGeneration == visit;
    bool current() => isCurrent() && ownerAndVisitCurrent();
    if (ids.isEmpty || !current()) return Future<bool>.value(false);
    var consumedHot = false;
    void consumeVisibleHot() {
      final visibleHot = ids.where(state.revealedUnreadMessageIDs.contains).toSet();
      if (visibleHot.isEmpty) return;
      consumedHot = true;
      state.revealedUnreadMessageIDs.removeAll(visibleHot);
      state.bufferedMessages.removeWhere((message) => visibleHot.contains(
          (message.msgID?.trim().isNotEmpty ?? false)
              ? message.msgID!.trim() : message.id?.trim() ?? ''));
      state.bufferedMessageKeys
        ..clear()
        ..addAll(state.bufferedMessages.map(TUIChatGlobalModel.messageDedupKey));
      state.unreadCount = max(state.lockedEntryUnreadCount,
          state.unreadCount - visibleHot.length);
      _markNeedsNotify();
    }
    // A pending admission may be moving this same identity from local memory
    // to SQL. Consume after that ordered move, never briefly clear then revive it.
    if (state.pendingDurableAdmissions == 0 && !state.unreadVisitBaselinePending) {
      consumeVisibleHot();
    }
    if (!state.durableDeferred && state.pendingLegacyMessages.isEmpty &&
        state.pendingDurableAdmissions == 0 && !state.unreadVisitBaselinePending) {
      return Future<bool>.value(consumedHot);
    }
    return _serializeHistoryDeferred(conversationID, (state) async {
      if (!current()) return false;
      await _ensureHistoryUnreadVisitBaseline(conversationID, state, visit);
      final scope = historyWindowScopeFor(conversationID);
      final repository = HistoryWindowRepositoryProvider.repository;
      if (!current() || scope == null || repository == null) return false;
      await _persistCoalescedHistoryDeferred(
          conversationID, state, scope, repository);
      if (!current()) return false;
      consumeVisibleHot();
      final receipt = await repository.acknowledgeVisibleDeferred(
          scope: scope,
          messageIDs: ids,
          afterIngressSequence: state.unreadVisitBaselineSequence,
          isCurrent: current);
      // The transaction has committed. Publish its result for this owner/visit
      // even if the viewport moved while its Future was completing.
      if (!ownerAndVisitCurrent()) return false;
      final consumed = receipt.acknowledgedMessageIDs;
      if (consumed.isEmpty) return consumedHot;
      state.bufferedMessages.removeWhere((message) => consumed.contains(
          (message.msgID?.trim().isNotEmpty ?? false)
              ? message.msgID!.trim()
              : message.id?.trim() ?? ''));
      state.bufferedMessageKeys
        ..clear()
        ..addAll(state.bufferedMessages.map(TUIChatGlobalModel.messageDedupKey));
      _publishHistoryDeferredState(conversationID, state, receipt.state);
      _markNeedsNotify();
      return true;
    });
  }

  Future<void> _persistCoalescedHistoryDeferred(
      String conversationID,
      _InboundUnreadState state,
      HistoryWindowScope scope,
      HistoryWindowRepository repository,
      {List<String>? keys}) async {
    // A short coalescer/reveal batch can cross the reader's scroll boundary
    // after initial admission. Persist it before capturing any latest watermark.
    final ownerCurrent = captureMessageOwnerFence(conversationID);
    final pendingKeys = keys ??
        (state.unreadVisitBaselinePending
            ? state.unreadVisitLegacyKeys.toList(growable: false)
            : state.pendingLegacyMessages.keys.toList(growable: false));
    for (final key in pendingKeys) {
      final message = state.pendingLegacyMessages[key];
      if (message == null) continue;
      final receipt = await repository.appendDeferred(
        scope: scope,
        eventID: 'received:$key',
        ingressSequence: 0,
        hasStableIngressSequence: false,
        message: message,
      );
      if (!ownerCurrent() ||
          !identical(
              _inboundUnreadStateFor(conversationID, create: false), state)) {
        throw const HistoryWindowStaleScope();
      }
      state.pendingLegacyMessages.remove(key);
      _publishHistoryDeferredState(conversationID, state, receipt.state);
    }
  }

  Future<bool> _admitBoundedHistoryIncoming(V2TimMessage message,
      {String? eventID,
      int? ingressSequence,
      bool allowLatestReveal = true}) async {
    if (message.isSelf == true) return false;
    final conversation = _messageConversationID(message);
    if (conversation == null ||
        !_isSameConversationID(conversation, currentSelectedConv)) return false;
    if (historyWindowScopeFor(conversation) == null) return false;
    // Geometry belongs to the mounted route, rather than the SDK's bare peer ID.
    final viewConversation = currentSelectedConv;
    _syncHistoryPositionFromActiveScroll(viewConversation);
    if (_chatAppForeground && !_isHistoryGapDeferral(viewConversation)) {
      return false;
    }
    final visitGeneration =
        _inboundUnreadStateFor(conversation).unreadVisitGeneration;
    return _serializeHistoryDeferred(conversation, (state) async {
      await _ensureHistoryUnreadVisitBaseline(
          conversation, state, visitGeneration);
      final ownerCurrent = captureMessageOwnerFence(conversation);
      final scope = historyWindowScopeFor(conversation);
      final repository = HistoryWindowRepositoryProvider.repository;
      if (scope == null || repository == null)
        throw const HistoryWindowStaleScope();
      await _persistCoalescedHistoryDeferred(
          conversation, state, scope, repository);
      final receipt = await repository.appendDeferred(
          scope: scope,
          eventID: eventID ??
              'received:${TUIChatGlobalModel.messageDedupKey(message)}',
          ingressSequence: ingressSequence ?? 0,
          hasStableIngressSequence: ingressSequence != null,
          message: message);
      if (!ownerCurrent() ||
          !identical(
              _inboundUnreadStateFor(conversation, create: false), state)) {
        throw const HistoryWindowStaleScope();
      }
      // A local-only delivery can later arrive through the durable ingress
      // path. Move its counting responsibility to SQL instead of counting it
      // twice; the exact visible consumer is shared by both paths.
      final id = (message.msgID?.trim().isNotEmpty ?? false)
          ? message.msgID!.trim() : message.id?.trim() ?? '';
      state.revealedUnreadMessageIDs.remove(id);
      _publishHistoryDeferredState(conversation, state, receipt.state);
      // Cache eviction may release the bodies while SQL is completing. Exact
      // scalar state still belongs to this owner; do not revive evicted bodies.
      if (receipt.inserted && isHistoryWindowScopeCurrent(scope)) {
        if (state.bufferedMessageKeys
            .add(TUIChatGlobalModel.messageDedupKey(message))) {
          state.bufferedMessages.add(message);
        }
        while (state.bufferedMessages.length > 120) {
          state.bufferedMessageKeys.remove(TUIChatGlobalModel.messageDedupKey(
              state.bufferedMessages.removeAt(0)));
        }
        final session = _boundedHistory.sessions[scope.conversationID]!;
        if (session.revealDeferredAtLatest &&
            (!allowLatestReveal ||
                !canRevealDurableIncomingAfterLatestReturn(conversation))) {
          // A held/hidden delivery creates a new projection gap. Merely closing
          // an overlay must not let the next delivery jump across that gap.
          session.revealDeferredAtLatest = false;
        }
        if (allowLatestReveal &&
            canRevealDurableIncomingAfterLatestReturn(conversation)) {
          if (receipt.state.receivedCount > 120 ||
              rawMessageCount(conversation) >=
                  ChatMessageWindowPolicy.historyReadSoftMax) {
            // Once a row cannot join this window, revoke the permission for all
            // later rows too. Otherwise a later callback could jump that gap.
            session.revealDeferredAtLatest = false;
          } else {
            setMessageList(conversation, <V2TimMessage>[message],
                needResetNewMessageCount: false, applyMemoryWindow: false);
            if (!(rawMessageList(conversation) ?? const <V2TimMessage>[])
                .any((row) => _historyDeferredMessageID(row) ==
                    _historyDeferredMessageID(message))) {
              session.revealDeferredAtLatest = false;
            }
          }
        }
      }
      _markNeedsNotify();
      return true;
    }, admission: true);
  }

  bool hasDurableHistoryDeferred(String conversationID) {
    if (HistoryWindowRepositoryProvider.repository == null) return false;
    final state = _inboundUnreadStateFor(conversationID, create: false);
    return state.durableDeferred ||
        state.unreadVisitBaselinePending ||
        state.pendingDurableAdmissions > 0 ||
        state.pendingLegacyMessages.isNotEmpty;
  }

  /// A latest SDK page plus its complete local tail forms one connected window.
  /// This permission belongs to that session and never overrides a new history
  /// window, background state, context menu, or a reader who left the bottom.
  bool canRevealDurableIncomingAfterLatestReturn(String conversationID) {
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conversationID);
    return _boundedHistory.sessions[key]?.revealDeferredAtLatest == true &&
        _isSameConversationID(conversationID, currentSelectedConv) &&
        _chatAppForeground &&
        !isMessageContextMenuOverlayOpen &&
        !shouldLockChatScrollForMediaPreview &&
        !isRestoringScrollAfterMediaPreview &&
        !isContextMenuViewportRestoreActive(conversationID) &&
        !isSearchJumpPending(conversationID) &&
        !memoryWindowMissingNewer(conversationID) &&
        !isHistoryReadingWindowActive(conversationID) &&
        (isUserScrollToBottomInProgress(conversationID) ||
            isFollowingLatest(conversationID));
  }

  /// Publish one bounded snapshot received after a successful latest reload.
  /// Keep the durable ledger until the viewport confirms these identities.
  /// Never attach just the tail of a larger backlog across an unknown gap.
  Future<bool> revealDurableIncomingAfterLatestReturn(String conversationID,
      {required bool Function() isCurrent}) {
    return _serializeHistoryDeferred(conversationID, (state) async {
      final scope = historyWindowScopeFor(conversationID);
      final repository = HistoryWindowRepositoryProvider.repository;
      if (scope == null || repository == null || !isCurrent()) return false;
      await _persistCoalescedHistoryDeferred(
          conversationID, state, scope, repository);
      final counts = await repository.deferredState(scope);
      if (!isCurrent() || !isHistoryWindowScopeCurrent(scope)) return false;
      if (counts.receivedCount > 120) return false;
      final tail = await repository.readDeferredTail(scope: scope, limit: 120);
      final pendingIDs = await repository.readDeferredMessageIDs(scope: scope);
      if (!isCurrent() || !isHistoryWindowScopeCurrent(scope)) return false;
      // The store may keep identity/counters only. Preserve bounded hot bodies
      // admitted after the reload watermark instead of requiring SQL payloads.
      final rowsByID = <String, V2TimMessage>{
        for (final row in <V2TimMessage>[...state.bufferedMessages, ...tail])
          if (pendingIDs.contains(_historyDeferredMessageID(row)))
            _historyDeferredMessageID(row): row,
      };
      if (pendingIDs.length != counts.receivedCount ||
          !rowsByID.keys.toSet().containsAll(pendingIDs)) return false;
      final existingIDs = (rawMessageList(conversationID) ??
          const <V2TimMessage>[]).map(_historyDeferredMessageID).toSet();
      if (existingIDs.union(pendingIDs).length >
          ChatMessageWindowPolicy.historyReadSoftMax) return false;
      final session = _boundedHistory.sessions[scope.conversationID]!;
      session.revealDeferredAtLatest = true;
      if (!canRevealDurableIncomingAfterLatestReturn(conversationID)) {
        session.revealDeferredAtLatest = false;
        return false;
      }
      if (rowsByID.isNotEmpty) {
        setMessageList(conversationID, rowsByID.values.toList(growable: false),
            needResetNewMessageCount: false, applyMemoryWindow: false);
        final installedKeys = (rawMessageList(conversationID) ??
            const <V2TimMessage>[]).map(_historyDeferredMessageID).toSet();
        if (!installedKeys.containsAll(pendingIDs)) {
          session.revealDeferredAtLatest = false;
          return false;
        }
        _markNeedsNotify();
      }
      ChatHistoryTrace.log('latest_return_deferred_revealed',
          conversationID: conversationID,
          extras: <String, Object?>{
            'tailCount': rowsByID.length,
            'receivedCount': counts.receivedCount,
          });
      return true;
    });
  }

  String _historyDeferredMessageID(V2TimMessage row) =>
      (row.msgID?.trim().isNotEmpty ?? false)
          ? row.msgID!.trim()
          : row.id?.trim() ?? '';

  Future<int?> beginHistoryWindowReturnToLatest(String conversationID) async {
    if (historyWindowScopeFor(conversationID) == null) return null;
    final visitGeneration =
        _inboundUnreadStateFor(conversationID).unreadVisitGeneration;
    return _serializeHistoryDeferred(conversationID, (state) async {
      await _ensureHistoryUnreadVisitBaseline(
          conversationID, state, visitGeneration);
      final scope = historyWindowScopeFor(conversationID);
      if (scope == null) throw const HistoryWindowStaleScope();
      final session = _boundedHistory.sessions[scope.conversationID]!;
      session.revealDeferredAtLatest = false;
      session.generation++; // cancels old trim/replay before a latest reload
      session.trim?.release();
      session.trim = null;
      final repository = HistoryWindowRepositoryProvider.repository!;
      await _persistCoalescedHistoryDeferred(
          conversationID, state, scope, repository);
      final counts = await repository.deferredState(scope);
      final tail = counts.receivedCount > 0
          ? await repository.readDeferredTail(scope: scope, limit: 120)
          : const <V2TimMessage>[];
      if (!isHistoryWindowScopeCurrent(scope))
        throw const HistoryWindowStaleScope();
      state.returnDeferredWatermark = counts.lastIngressSequence;
      V2TimMessage? newestPending = tail.isEmpty ? null : tail.first;
      // Arrival order can differ from message order. Keep the newest surviving
      // pending message as the content boundary for this exact reload snapshot.
      for (final candidate in tail.skip(1)) {
        final anchor = newestPending!;
        final candidateSeq = int.tryParse(candidate.seq ?? '') ?? 0;
        final anchorSeq = int.tryParse(anchor.seq ?? '') ?? 0;
        if ((candidate.groupID?.isNotEmpty == true &&
                candidateSeq > 0 &&
                anchorSeq > 0 &&
                candidateSeq > anchorSeq) ||
            (candidate.timestamp ?? 0) > (anchor.timestamp ?? 0)) {
          newestPending = candidate;
        }
      }
      state.returnDeferredMessageKey = newestPending == null
          ? counts.lastMessageID
          : ((newestPending.msgID?.isNotEmpty ?? false)
              ? newestPending.msgID
              : newestPending.id);
      state.returnDeferredSeq = newestPending == null
          ? counts.lastGroupMessageSeq
          : (newestPending.groupID?.isNotEmpty == true
              ? int.tryParse(newestPending.seq ?? '') ?? 0
              : 0);
      state.returnDeferredTimestamp =
          newestPending?.timestamp ?? counts.lastMessageTimestamp;
      _publishHistoryDeferredState(conversationID, state, counts);
      return counts.lastIngressSequence;
    });
  }

  /// A non-empty SDK success can still be an old page. Retire a pending
  /// snapshot only once its content boundary is present or has been passed.
  bool historyWindowReturnCoversDeferred(String conversationID, int? watermark,
      {List<V2TimMessage>? visibleMessages}) {
    if (watermark == null) return true;
    final state = _inboundUnreadStateFor(conversationID, create: false);
    if (state.returnDeferredWatermark != watermark) return false;
    final anchorID = state.returnDeferredMessageKey;
    // LRU may discard payloads while counters and IDs remain. Unknown content
    // cannot prove the newest boundary, so preserve the reminder for retry.
    if (anchorID == null || anchorID.isEmpty) return false;
    final anchorSeq = state.returnDeferredSeq;
    final anchorTime = state.returnDeferredTimestamp;
    for (final row in visibleMessages ??
        rawMessageList(conversationID) ??
        const <V2TimMessage>[]) {
      if (row.msgID == anchorID || row.id == anchorID) return true;
      // Optimistic self rows have not proved the server's newest boundary.
      if (row.isSelf == true && (row.status == 1 || (row.msgID ?? '').isEmpty))
        continue;
      final seq = int.tryParse(row.seq ?? '') ?? 0;
      if (row.groupID?.isNotEmpty == true && anchorSeq > 0 && seq > anchorSeq)
        return true;
      if (anchorTime > 0 && (row.timestamp ?? 0) > anchorTime) return true;
    }
    return false;
  }

  Future<bool> confirmHistoryWindowReturnCoversDeferred(
      String conversationID, int? watermark,
      {List<V2TimMessage>? visibleMessages}) async {
    if (historyWindowReturnCoversDeferred(conversationID, watermark,
        visibleMessages: visibleMessages)) return true;
    if (watermark == null) return true;
    final scope = historyWindowScopeFor(conversationID);
    final repository = HistoryWindowRepositoryProvider.repository;
    if (scope == null || repository == null) return false;
    final allDeleted =
        await repository.areDeferredMessagesAuthoritativelyDeleted(
            scope: scope, throughIngressSequence: watermark);
    if (!isHistoryWindowScopeCurrent(scope))
      throw const HistoryWindowStaleScope();
    return allDeleted;
  }

  /// Called only after a successful newest reload and acknowledgement of its
  /// captured watermark. Opaque history must start a fresh snapshot thereafter.
  Future<void> resetHistoryWindowAfterLatest(String conversationID) async {
    await _serializeHistoryDeferred(conversationID, (_) async {
      final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conversationID);
      final old = _boundedHistory.sessions.remove(key);
      if (old == null) return;
      final unread = _inboundUnreadStateFor(key, create: false);
      final hot = List<V2TimMessage>.of(unread.bufferedMessages);
      _closeBoundedHistorySession(old);
      final scope = historyWindowScopeFor(key);
      if (scope == null) return;
      unread.bufferedMessages
        ..clear()
        ..addAll(hot);
      unread.bufferedMessageKeys
        ..clear()
        ..addAll(hot.map(TUIChatGlobalModel.messageDedupKey));
    });
  }

  Future<void> acknowledgeHistoryWindowReturnToLatest(
      String conversationID, int? throughSequence) async {
    if (throughSequence == null ||
        historyWindowScopeFor(conversationID) == null) return;
    await _serializeHistoryDeferred(conversationID, (state) async {
      final scope = historyWindowScopeFor(conversationID);
      if (scope == null) throw const HistoryWindowStaleScope();
      final repository = HistoryWindowRepositoryProvider.repository!;
      final before = await repository.deferredState(scope);
      await repository.acknowledgeDeferred(
          scope: scope, throughIngressSequence: throughSequence);
      final counts = await repository.deferredState(scope);
      final tail = await repository.readDeferredTail(scope: scope, limit: 120);
      final pendingIDs = await repository.readDeferredMessageIDs(scope: scope);
      final survivingHot = <String, V2TimMessage>{
        for (final row in <V2TimMessage>[...state.bufferedMessages, ...tail])
          if (pendingIDs.contains(_historyDeferredMessageID(row)))
            _historyDeferredMessageID(row): row,
      }.values.toList(growable: false);
      if (!isHistoryWindowScopeCurrent(scope))
        throw const HistoryWindowStaleScope();
      // ACK consumes the oldest prefix first, including a previous visit's
      // baseline. A partial/late ACK must not hide new visits' surviving rows.
      state.unreadVisitBaselineReceived = max(
          0,
          state.unreadVisitBaselineReceived -
              max(0, before.receivedCount - counts.receivedCount));
      state.unreadVisitBaselineUnread = max(
          0,
          state.unreadVisitBaselineUnread -
              max(0, before.unreadCount - counts.unreadCount));
      _publishHistoryDeferredState(conversationID, state, counts);
      final hotByKey = <String, V2TimMessage>{
        for (final row in <V2TimMessage>[
          ...survivingHot, ...state.pendingLegacyMessages.values,
        ]) TUIChatGlobalModel.messageDedupKey(row): row,
      };
      final hot = hotByKey.values.toList(growable: false);
      state.bufferedMessages
        ..clear()
        ..addAll(hot.skip(max(0, hot.length - 120)));
      state.bufferedMessageKeys
        ..clear()
        ..addAll(state.bufferedMessages.map(TUIChatGlobalModel.messageDedupKey));
      _markNeedsNotify();
    });
  }
}
