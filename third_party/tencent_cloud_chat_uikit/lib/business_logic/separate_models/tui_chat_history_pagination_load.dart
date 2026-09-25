part of 'tui_chat_separate_view_model.dart';

/// Mechanical extract of history load loops. Same library as the view model so
/// private helpers remain accessible without widening API surface.
class HistoryPaginationLoadRunner {
  HistoryPaginationLoadRunner(this.model, this.pagination);

  final TUIChatSeparateViewModel model;
  final HistoryPaginationController pagination;

  // C2C timestamps have second precision and seq is not a global ordering key.
  // Retain scanned IDs at the accepted filtered tail's timestamp so SDK older
  // responses can traverse a same-second run without cycling through it.
  V2TimMessage? _filteredSdkTail;
  final Set<String> _filteredSdkSameTimeIds = <String>{};

  Future<bool?> _tryLoadHistoryWindowPage({
    required LoadDirection direction,
    required int count,
    required bool Function() requestIsCurrent,
  }) async {
    final global = model.globalModel;
    final repository = HistoryWindowRepositoryProvider.repository;
    final scope = global.historyWindowScopeFor(model.conversationID);
    final current = _aliasAwareInMemoryList(model);
    if (repository == null || scope == null || current.isEmpty) return null;
    bool isCurrent() =>
        requestIsCurrent() && global.isHistoryWindowScopeCurrent(scope);
    V2TimMessage? edge;
    final cursor =
        direction == LoadDirection.latest ? model.historyNewerPageCursor : null;
    final rows = cursor != null
        ? [cursor]
        : (direction == LoadDirection.latest ? current : current.reversed);
    for (final row in rows) {
      if (row.elemType == 11 ||
          HistoryPaginationAnchor.isLocalInjectedMessage(row) ||
          (row.msgID?.trim().isEmpty ?? true)) continue;
      edge = row;
      break;
    }
    if (edge == null) return null;
    final msgID = edge.msgID!.trim();
    final boundary = HistoryWindowBoundary(msgID: msgID, seq: edge.seq);
    final continuation = pagination.cacheReadContinuations[direction];
    final readBoundary = continuation != null &&
            continuation.sessionID == scope.sessionID &&
            continuation.anchorID == msgID
        ? continuation.boundary
        : boundary;
    final result = await repository.readAdjacent(
        scope: scope,
        boundary: readBoundary,
        direction: direction == LoadDirection.latest
            ? HistoryWindowDirection.newer
            : HistoryWindowDirection.older,
        limit: count.clamp(1, 50));
    if (!isCurrent()) return false;
    if (result.status == HistoryWindowReadStatus.stale) return false;
    if (result.scanLimitReached && result.continuationBoundary != null) {
      pagination.cacheReadContinuations[direction] = (
        sessionID: scope.sessionID,
        anchorID: msgID,
        boundary: result.continuationBoundary!
      );
    } else {
      pagination.cacheReadContinuations.remove(direction);
    }
    if (result.status == HistoryWindowReadStatus.hit &&
        result.messages.isNotEmpty) {
      return _commitHistoryWindowPage(result.messages,
          scope: scope,
          snapshot: result.snapshotMaxSeq,
          direction: direction,
          isCurrent: isCurrent);
    }
    if (result.scanLimitReached) {
      if (direction == LoadDirection.latest)
        pagination.haveMoreLatestData = true;
      else
        pagination.haveMoreData = true;
      return false;
    }
    // A missing cached edge is not an exhausted remote timeline. The SDK
    // cursor remains the only message-history continuation source.
    return null;
  }

  Future<bool> _commitHistoryWindowPage(
    List<V2TimMessage> page, {
    required HistoryWindowScope scope,
    required int? snapshot,
    required LoadDirection direction,
    required bool Function() isCurrent,
  }) async {
    final global = model.globalModel;
    if (!isCurrent()) return false;
    global.noteHistoryWindowSnapshot(model.conversationID, snapshot);
    final filtered =
        await global.applyHistoryWindowMutations(model.conversationID, page);
    if (!isCurrent()) return false;
    final combined = _combineMessageList(
        List<V2TimMessage>.of(_aliasAwareInMemoryList(model)), filtered);
    final processed =
        await model.lifeCycle?.didGetHistoricalMessageList(combined) ??
            combined;
    final finalList = await global.applyHistoryWindowMutations(
        model.conversationID, processed);
    if (!isCurrent() ||
        global.historyWindowPaginationBlocked(model.conversationID))
      return false;
    final request = global.beginHistoryReconciliation(
        conversationID: model.conversationID,
        requestedSource: MessageReconciliationSource.local,
        networkState: global.messageReconciliationNetworkState);
    var committed = false;
    try {
      final commit = global.completeHistoryReconciliation(
          request: request,
          history: finalList,
          actualSource: MessageReconciliationSource.local,
          networkState: global.messageReconciliationNetworkState,
          applyMemoryWindow: false,
          historyCommitSource: 'history_window_cache:${direction.name}',
          batchKind: direction == LoadDirection.latest
              ? MessageHistoryBatchKind.newerCatchUp
              : MessageHistoryBatchKind.olderPage,
          historyIsFinished: false,
          clearEpoch: scope.clearEpoch);
      committed = commit != null;
      if (committed) {
        if (direction == LoadDirection.latest) {
          model._acceptHistoryNewerPage(filtered);
          pagination.haveMoreLatestData = true;
        } else
          pagination.haveMoreData = true;
        pagination.lastEmptyBatchAt = null;
        model._notify();
      }
      return committed;
    } finally {
      if (!committed)
        global.failHistoryReconciliation(
            request: request, reason: 'history_window_cache_rejected');
    }
  }

  /// K.2：拉空批自动 fallback 到 LOCAL_OLDER_MSG 的去重窗口。
  /// 短时间内不重复 fallback，避免 SDK cloud 持续返回空时抖动。
  DateTime? _lastEmptyBatchLocalFallbackAt;
  static const Duration _emptyBatchLocalFallbackWindow = Duration(seconds: 5);
  static bool _coverageDiagVersionLogged = false;

  void _markRetryableHistoryFailure({String? detail, String? errorType}) {
    pagination.haveMoreData = true;
    pagination.lastEmptyBatchAt = DateTime.now();
    final resolvedType = errorType ??
        model.globalModel.lastHistoryErrorType(model.conversationID);
    final showNotice =
        HistoryPaginationController.shouldShowHistoryFailureNotice(
            resolvedType);
    if (showNotice) {
      pagination.setArchiveHistoryNotice('历史记录加载失败，请再次上滑重试');
    } else {
      // Clear an earlier notice while retaining retry state and diagnostics.
      pagination.setArchiveHistoryNotice(null);
    }
    ChatHistoryTrace.log(
      'history_load_retryable',
      conversationID: model.conversationID,
      extras: <String, Object?>{
        'detail': detail,
        'errorType': resolvedType,
        'userNotice': showNotice,
        'availability': pagination.olderAvailability.name,
        'cursorNotAdvanced': true,
      },
    );
    model._notify();
  }

  /// 防止 SDK 返回全空 msgID 时 _shortMsgId 仍能工作。
  String? _firstNonEmptyId(List<V2TimMessage> list) {
    for (final m in list) {
      final id = m.msgID?.trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  int? _emptyBatchAgeMs(DateTime? last) {
    if (last == null) return -1;
    return DateTime.now().difference(last).inMilliseconds;
  }

  MessageHistoryBounds _returnedBounds(Iterable<V2TimMessage> messages) {
    V2TimMessage? oldest;
    V2TimMessage? newest;
    for (final message in messages) {
      if ((message.msgID?.trim() ?? '').isEmpty) continue;
      if (oldest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, oldest) <
              0) {
        oldest = message;
      }
      if (newest == null ||
          TUIChatGlobalModel.compareMessagesChronological(message, newest) >
              0) {
        newest = message;
      }
    }
    return MessageHistoryBounds(
      oldestMsgID: oldest?.msgID,
      newestMsgID: newest?.msgID,
      oldestSeq: int.tryParse(oldest?.seq?.trim() ?? ''),
      newestSeq: int.tryParse(newest?.seq?.trim() ?? ''),
    );
  }

  MessageHistoryCursor? _requestedCursor({
    required LoadDirection direction,
    required String? lastMsgID,
    required int lastMsgSeq,
  }) {
    if (lastMsgID == null && lastMsgSeq <= 0) return null;
    return MessageHistoryCursor(
      direction: direction == LoadDirection.latest
          ? MessageHistoryCursorDirection.newer
          : MessageHistoryCursorDirection.older,
      lastMsgID: lastMsgID,
      lastMsgSeq: lastMsgSeq > 0 ? lastMsgSeq : null,
    );
  }

  Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,
    bool forceReloadNewest = false,
  }) async {
    // All supported conversations use SDK cursors after a cache miss.
    final sdkPagination = !forceReloadNewest &&
        (lastMsgID != null || lastMsgSeq > 0 || lastMsg != null);
    count = count.clamp(1, 50);
    if (!forceReloadNewest &&
        sdkPagination &&
        model.globalModel
            .historyWindowPaginationBlocked(model.conversationID)) {
      return false;
    }
    final DateTime _enteredAt = DateTime.now();
    ChatHistoryTrace.log(
      'load_chat_record_opened',
      conversationID: model.conversationID,
      extras: <String, Object?>{
        ...ChatHistoryTrace.initDiagSummary(
          conversationID: model.conversationID,
          usesOfficialSdkHistory: model.usesOfficialSdkHistory,
          isCommunity: model.usesOfficialSdkHistory ? false : true,
          haveMoreData: pagination.haveMoreData,
          haveMoreLatestData: pagination.haveMoreLatestData,
          olderAvailabilityIndex: pagination.olderAvailability.index,
          archiveOlderExhausted: pagination.archiveOlderExhausted,
          archiveOlderActive: pagination.archiveOlderActive,
          suppressArchiveUntilSdkHistory:
              pagination.suppressArchiveUntilSdkHistory,
          historyLoadingKeysSize: pagination.historyLoadingKeys.length,
          previousPaginationInFlight: pagination.previousPaginationInFlight,
          lastEmptyBatchAt: pagination.lastEmptyBatchAt,
        ),
        'direction': direction.name,
        'inLastMsgID': lastMsgID,
        'inLastSeq': lastMsgSeq,
        'hasFullAnchor': lastMsg != null,
        'count': count,
        'forceReloadNewest': forceReloadNewest,
      },
    );
    // DIAG: loadChatRecord 入口 - 锚点决策后 / SDK 调用前的状态。
    ChatHistoryTrace.log(
      'diag_load_record_enter',
      conversationID: model.conversationID,
      extras: <String, Object?>{
        'direction': direction.name,
        'count': count,
        'inLastMsgID': lastMsgID ?? '',
        'inLastMsgSeq': lastMsgSeq,
        'forceReloadNewest': forceReloadNewest,
        'haveMoreData': pagination.haveMoreData,
        'olderAvailabilityIndex': pagination.olderAvailability.index,
        'archiveOlderExhausted': pagination.archiveOlderExhausted,
        'archiveOlderActive': pagination.archiveOlderActive,
        'isLoadingChatHistory': pagination.isLoadingChatHistory,
        'lastEmptyBatchAtMs':
            pagination.lastEmptyBatchAt?.millisecondsSinceEpoch,
        'emptyBatchLatchExpired': pagination.emptyBatchLatchExpired,
      },
    );
    // Clear sticky failure before a new older-page attempt; true failures
    // re-arm the notice after the request settles.
    if (direction == LoadDirection.previous) {
      pagination.setArchiveHistoryNotice(null);
    }
    final requestKey = model._historyRequestKey(
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      count: count,
      lastMsgID: lastMsgID,
      direction: direction,
    );
    // Re-arm haveMoreData if the empty-batch latch has expired (30s).
    if (direction == LoadDirection.previous &&
        !pagination.haveMoreData &&
        pagination.emptyBatchLatchExpired) {
      pagination.haveMoreData = true;
      pagination.lastEmptyBatchAt = null;
      ChatHistoryTrace.log(
        'load_chat_record_empty_batch_retry',
        conversationID: model.conversationID,
      );
    }
    if (pagination.historyLoadingKeys.contains(requestKey)) {
      ChatHistoryTrace.log(
        'load_chat_record_deduped',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'requestKey': requestKey,
          'direction': direction.name,
          'haveMoreData': pagination.haveMoreData,
        },
      );
      // A duplicate did not commit a page for this caller. The older-page UI
      // uses this result as its commit signal, not as a has-more flag.
      return direction == LoadDirection.latest
          ? pagination.haveMoreLatestData
          : false;
    }
    final isPreviousPagination =
        (lastMsgID != null || lastMsgSeq > 0 || lastMsg != null) &&
            direction == LoadDirection.previous;
    ChatHistoryTrace.log(
      'load_chat_record_start',
      conversationID: model.conversationID,
      extras: <String, Object?>{
        'direction': direction.name,
        'getType': getType?.name,
        'lastMsgID': lastMsgID,
        'lastMsgSeq': lastMsgSeq,
        'count': count,
        'forceReloadNewest': forceReloadNewest,
        'requestKey': requestKey,
        'isPaginated': isPreviousPagination,
        'haveMoreData': pagination.haveMoreData,
        'emptyBatchAt': pagination.lastEmptyBatchAt?.toIso8601String(),
        'position':
            model.globalModel.getMessageListPosition(model.conversationID).name,
        ...ChatHistoryTrace.windowSummary(
          _aliasAwareInMemoryList(model),
          prefix: 'memory',
        ),
      },
    );
    if (isPreviousPagination && pagination.previousPaginationInFlight) {
      ChatHistoryTrace.log(
        'load_chat_record_previous_in_flight',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'lastMsgID': lastMsgID,
          'lastMsgSeq': lastMsgSeq,
          'haveMoreData': pagination.haveMoreData,
        },
      );
      // Another older cursor owns the active request. Reporting has-more as a
      // successful load would release the UI edge latch without adding rows.
      return false;
    }
    pagination.historyLoadingKeys.add(requestKey);
    if (pagination.historyLoadingKeys.length == 1) {
      model._notify();
    }
    if (isPreviousPagination) {
      pagination.previousPaginationInFlight = true;
    }
    if (isPreviousPagination) {
      // Tell the background verifier that a user is actively reading older
      // history. The verifier will yield, and the IM-06 coordinator will put
      // this older-page request ahead of queued warm/latest reads.
      ConversationHistorySyncCoordinator.instance
          .beginUserOlderPagination(model.conversationID);
    }
    // 在捕获任何 fence / scope 之前采纳窗口库的清空 epoch，
    // 否则 stale 的窗口读会在调用 SDK 之前就把这次分页判死。
    await model.globalModel
        .syncHistoryClearEpochFromWindowStore(model.conversationID);
    final publicationIsCurrent = model._historyPublicationFence();
    final windowGenAtStart = model._historyWindowGeneration;
    final searchRequestAtStart =
        model.globalModel.searchJumpRequestFor(model.conversationID);
    final windowScopeAtStart =
        model.globalModel.historyWindowScopeFor(model.conversationID);
    bool windowRequestIsCurrent() =>
        publicationIsCurrent() &&
        windowGenAtStart == model._historyWindowGeneration &&
        (windowScopeAtStart == null ||
            model.globalModel
                .isHistoryWindowScopeCurrent(windowScopeAtStart)) &&
        model.globalModel.isCurrentSearchJumpRequest(
            model.conversationID, searchRequestAtStart);
    MessageReconciliationRequest? reconciliationRequest;
    var reconciliationCommitted = false;
    try {
      var previousListGrew = false;
      final isPaginatedLoad = sdkPagination;
      if (!forceReloadNewest && isPaginatedLoad) {
        final cached = await _tryLoadHistoryWindowPage(
            direction: direction,
            count: count,
            requestIsCurrent: windowRequestIsCurrent);
        if (cached != null) return cached;
        if (!windowRequestIsCurrent()) return false;
      }
      if (direction == LoadDirection.latest &&
          !model.globalModel.historyWindowCanReadNewer(model.conversationID) &&
          SearchJumpLatestGate.shouldSkipLatestWhileReadingHistory(
            isReadingHistory: model.globalModel.isReadingHistory(
              model.conversationID,
            ),
            haveMoreLatestData: pagination.haveMoreLatestData ||
                model.globalModel
                    .hasDurableHistoryDeferred(model.conversationID),
            memoryWindowMissingNewer: model.globalModel
                .memoryWindowMissingNewer(model.conversationID),
            forceReloadNewest: forceReloadNewest,
          )) {
        ChatHistoryTrace.log(
          'load_chat_record_skip_latest_reading_history',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
            'haveMoreLatestData': pagination.haveMoreLatestData,
            'position': model.globalModel
                .getMessageListPosition(model.conversationID)
                .name,
          },
        );
        return pagination.haveMoreLatestData;
      }
      if (!forceReloadNewest && lastMsgID == null && lastMsgSeq <= 0) {
        final existing = _aliasAwareInMemoryList(model);
        if (existing.length >= count) {
          pagination.haveMoreData = true;
          return pagination.haveMoreData;
        }
      }
      bool tempHaveMoreData = pagination.haveMoreData;
      // latest 补拉只更新 latest 状态，不能污染 older 分页开关。
      if (direction != LoadDirection.latest) {
        tempHaveMoreData = false;
      }

      // 上拉/带锚点分页必须保留请求发起时用户正在阅读的窗口。须走别名合并
      // （c2c_ / 裸 id），否则 baseline 为空会把整表 replace 成 SDK 短批次。
      final inMemoryAtRequest = _aliasAwareInMemoryList(model);
      final previousPaginationBaseline = isPaginatedLoad
          ? List<V2TimMessage>.of(inMemoryAtRequest)
          : const <V2TimMessage>[];
      if (isPaginatedLoad) {
        _logPreviousPaginationStage(
          model.conversationID,
          stage: 'request_start',
          extras: <String, Object?>{
            'direction': direction.name,
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
            'baselineCount': previousPaginationBaseline.length,
            'aliasMergedCount': inMemoryAtRequest.length,
            'position': model.globalModel
                .getMessageListPosition(model.conversationID)
                .name,
            'memorySuppressed': model.globalModel.isMemoryWindowSuppressed(
              model.conversationID,
            ),
          },
        );
      }

      // 调用MessageService获取聊天记录
      final HistoryMsgGetTypeEnum resolvedGetType = getType ??
          (direction == LoadDirection.previous
              ? HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG
              : HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG);
      final requestedHistorySource = resolvedGetType ==
                  HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG ||
              resolvedGetType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG
          ? MessageReconciliationSource.local
          : MessageReconciliationSource.cloud;
      final networkBeforeHistoryRequest =
          model.globalModel.messageReconciliationNetworkState;

      final String? historyUserID =
          model.conversationType == ConvType.c2c ? model.conversationID : null;
      final String? historyGroupID = model.conversationType == ConvType.group
          ? model.conversationID
          : null;
      final paginationAnchor = (lastMsgID != null || lastMsgSeq > 0)
          ? (lastMsg ??
              model._resolvePaginationAnchorInMemory(
                lastMsgID: lastMsgID,
                lastMsgSeq: lastMsgSeq,
              ))
          : null;

      V2TimMessageListResult? response;
      var actualRequestLastMsgID = lastMsgID;
      var actualRequestLastMsgSeq = lastMsgSeq;
      var actualRequestAnchor = paginationAnchor;
      List<V2TimMessage> withAcceptedSdkBoundary(List<V2TimMessage> window) {
        final acceptedTail = model._sdkOlderPageTail;
        return acceptedTail != null &&
                identical(actualRequestAnchor, acceptedTail)
            ? [...window, acceptedTail]
            : window;
      }
      var cloudResponseProvenByIm06 = false;
      var selectedHistorySource = requestedHistorySource;
      reconciliationRequest = model.globalModel.beginHistoryReconciliation(
        conversationID: model.conversationID,
        requestedSource: requestedHistorySource,
        networkState: networkBeforeHistoryRequest,
      );
      final useOfficialCloudOnly =
          (sdkPagination || model.usesOfficialSdkHistory) &&
              direction == LoadDirection.previous &&
              !forceReloadNewest &&
              // The local-only route deliberately asks the SDK for its local
              // cache during the first frame.  Standard C2C/group pagination
              // is cloud-authoritative after that point, but must not rewrite
              // this explicit local request into a cloud request.
              !(model.localOnlyInitialOpen &&
                  getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG);
      // Community groups still paginate against Tencent's SDK.  Keep a
      // per-view-model SDK tail for them as well; otherwise the UI can resend
      // its stale anchor after a page was committed and receive the same page
      // forever (the server response is older than the requested anchor but
      // not older than the already committed window).
      final useOfficialOlderCursor =
          (useOfficialCloudOnly || model.conversationType == ConvType.group) &&
              isPreviousPagination;
      if (useOfficialCloudOnly || (getType == null && isPreviousPagination)) {
        var effectiveLastMsgID = lastMsgID;
        var effectiveLastMsgSeq = lastMsgSeq;
        var effectiveAnchor = paginationAnchor;
        var anchorRewroteVia = 'no_rewrite';
        final tipLikeId = effectiveLastMsgID != null &&
            (effectiveLastMsgID.startsWith('ce_') ||
                effectiveLastMsgID.startsWith('local_gt_') ||
                effectiveLastMsgID.startsWith('local_'));
        final tipAnchor = effectiveAnchor != null &&
            HistoryPaginationAnchor.isLocalInjectedMessage(effectiveAnchor);
        // 上拉绝不用本地 tip 当 SDK 锚点。
        if (tipLikeId || tipAnchor) {
          // K.8：群聊先尝试用 seq 锚点重写（更稳定）。
          if (model.conversationType == ConvType.group) {
            final seqAnchor = HistoryPaginationAnchor.oldestSdkPaginationAnchor(
              inMemoryAtRequest,
            );
            final parsedSeq =
                int.tryParse(seqAnchor?.seq?.toString() ?? '') ?? -1;
            if (parsedSeq > 0) {
              effectiveLastMsgID = null;
              effectiveLastMsgSeq = parsedSeq;
              effectiveAnchor = seqAnchor;
              anchorRewroteVia = 'seq_fallback_after_tip';
              ChatHistoryTrace.log(
                'load_chat_record_seq_fallback_after_tip',
                conversationID: model.conversationID,
                extras: <String, Object?>{
                  'fromMsgID': effectiveLastMsgID ?? '',
                  'toSeq': parsedSeq,
                },
              );
            }
          }
          if (anchorRewroteVia != 'seq_fallback_after_tip') {
            final repaired = HistoryPaginationAnchor.oldestSdkPaginationAnchor(
              inMemoryAtRequest,
            );
            ChatHistoryTrace.log(
              'load_chat_record_reject_tip_anchor',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'fromMsgID': effectiveLastMsgID,
                'toMsgID': repaired?.msgID ?? '',
                'toSeq': repaired?.seq ?? '',
              },
            );
            if (repaired != null) {
              effectiveLastMsgID = repaired.msgID;
              effectiveLastMsgSeq =
                  int.tryParse(repaired.seq?.toString() ?? '') ?? -1;
              effectiveAnchor = repaired;
              anchorRewroteVia = 'tip_rejected';
            } else {
              // tip-only without a usable SDK anchor cannot safely paginate.
              effectiveLastMsgID = null;
              effectiveLastMsgSeq = -1;
              effectiveAnchor = null;
              anchorRewroteVia = 'tip_only_without_sdk_anchor';
            }
          }
        }
        // Continue C2C and group pagination from the tail of the last SDK page
        // that was actually committed. Recomputing from a merged window can
        // skip a hole or repeat the same group page.
        if (useOfficialOlderCursor && model._sdkOlderPageTail != null) {
          // Only advance from the tail of a page that was actually committed.
          // When the view model was recreated, the caller's SDK cursor is the
          // only trusted anchor; falling back to the first 20 in-memory rows
          // can repeatedly request the same C2C page or skip a hole.
          final official = HistoryPaginationAnchor.officialOlderCursor(
            newestFirstWindow: inMemoryAtRequest,
            lastSdkPageTail: model._sdkOlderPageTail,
            requestedAnchor: effectiveAnchor,
          );
          if (official != null) {
            ChatHistoryTrace.log(
              'load_chat_record_sdk_cursor',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'fromMsgID': effectiveLastMsgID,
                'toMsgID': official.msgID ?? '',
              },
            );
            // K.3：群聊优先用 seq 锚点（更稳定），仅单聊用 msgID。
            if (model.conversationType == ConvType.group) {
              final parsedSeq =
                  int.tryParse(official.seq?.toString() ?? '') ?? -1;
              if (parsedSeq > 0) {
                effectiveLastMsgID = null;
                effectiveLastMsgSeq = parsedSeq;
              } else {
                effectiveLastMsgID = official.msgID;
                effectiveLastMsgSeq = -1;
              }
            } else {
              effectiveLastMsgID = official.msgID;
              effectiveLastMsgSeq = -1;
            }
            effectiveAnchor = official;
            anchorRewroteVia = 'official_cursor';
          }
        } else if (effectiveAnchor != null &&
            !HistoryPaginationAnchor.canUseForSdkPagination(effectiveAnchor)) {
          final repaired = HistoryPaginationAnchor.oldestSdkPaginationAnchor(
            inMemoryAtRequest,
          );
          if (repaired != null) {
            ChatHistoryTrace.log(
              'load_chat_record_repair_anchor',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'fromMsgID': effectiveLastMsgID,
                'toMsgID': repaired.msgID,
                'toSeq': repaired.seq,
                'toTs': repaired.timestamp,
              },
            );
            effectiveLastMsgID = repaired.msgID;
            effectiveLastMsgSeq =
                int.tryParse(repaired.seq?.toString() ?? '') ?? -1;
            effectiveAnchor = repaired;
            anchorRewroteVia = 'repair_anchor';
          }
        }

        actualRequestLastMsgID = effectiveLastMsgID;
        actualRequestLastMsgSeq = effectiveLastMsgSeq;
        actualRequestAnchor = effectiveAnchor;
        ChatHistoryTrace.log(
          'load_chat_record_anchor_path',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            ...ChatHistoryTrace.anchorDecision(
              path: anchorRewroteVia,
              fromMsgId: lastMsgID,
              fromSeq: lastMsgSeq > 0 ? lastMsgSeq : null,
              toMsgId: effectiveLastMsgID,
              toSeq: effectiveLastMsgSeq > 0 ? effectiveLastMsgSeq : null,
            ),
          },
        );
        var peekResult = useOfficialCloudOnly
            ? await model.globalModel.getHistoryMessageListThroughIm06(
                count: count,
                getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
                userID: historyUserID,
                groupID: historyGroupID,
                lastMsgID: effectiveLastMsgID,
                lastMsgSeq: effectiveLastMsgSeq,
                lastMsg: effectiveAnchor,
              )
            : await MessageHistoryPeekLoader.loadOlderLocalThenCloudResult(
                messageService: model._messageService,
                count: count,
                userID: historyUserID,
                groupID: historyGroupID,
                lastMsgID: effectiveLastMsgID,
                lastMsgSeq: effectiveLastMsgSeq,
                lastMsg: effectiveAnchor,
              );
        // A recreated C2C view model can retain a caller cursor that no longer
        // matches the oldest SDK row in memory. Retry once with that row when
        // the first response is empty or contains no new server IDs. This is
        // deliberately bounded so an exhausted/invalid SDK cursor cannot loop.
        if (useOfficialCloudOnly) {
          final recoveryAnchor =
              HistoryPaginationAnchor.oldestSdkPaginationAnchor(
            inMemoryAtRequest,
          );
          final recoveryID = recoveryAnchor?.msgID?.trim() ?? '';
          final effectiveID =
              (effectiveLastMsgID ?? effectiveAnchor?.msgID)?.trim() ?? '';
          final knownIDs = inMemoryAtRequest
              .map((message) => message.msgID?.trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          final responseHasNewID = peekResult?.messageList.any((message) {
                final id = message.msgID?.trim() ?? '';
                return id.isEmpty || !knownIDs.contains(id);
              }) ??
              false;
          if (recoveryID.isNotEmpty &&
              recoveryID != effectiveID &&
              !responseHasNewID &&
              // A committed filtered tail can be older than every visible row.
              // An empty cloud response must fall back from that same cursor,
              // not rewind to the visible edge and repeat the filtered page.
              !(identical(effectiveAnchor, model._sdkOlderPageTail) &&
                  !knownIDs.contains(effectiveAnchor?.msgID?.trim()))) {
            ChatHistoryTrace.log(
              'load_chat_record_cursor_recovery',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'fromMsgID': effectiveLastMsgID,
                'toMsgID': recoveryID,
                'firstBatchCount': peekResult?.messageList.length ?? 0,
              },
            );
            effectiveLastMsgID = recoveryAnchor!.msgID;
            effectiveLastMsgSeq = model.conversationType == ConvType.group
                ? int.tryParse(recoveryAnchor.seq?.toString() ?? '') ?? -1
                : -1;
            effectiveAnchor = recoveryAnchor;
            actualRequestLastMsgID = effectiveLastMsgID;
            actualRequestLastMsgSeq = effectiveLastMsgSeq;
            actualRequestAnchor = effectiveAnchor;
            peekResult =
                await model.globalModel.getHistoryMessageListThroughIm06(
              count: count,
              getType: HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
              userID: historyUserID,
              groupID: historyGroupID,
              lastMsgID: effectiveLastMsgID,
              lastMsgSeq: effectiveLastMsgSeq,
              lastMsg: effectiveAnchor,
            );
          }
        }
        ChatHistoryTrace.log(
          'load_chat_record_sdk_response',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'effectiveLastMsgID': effectiveLastMsgID,
            'effectiveLastMsgSeq': effectiveLastMsgSeq,
            ...(peekResult == null
                ? <String, Object?>{
                    'errorType': model.globalModel.lastHistoryErrorMetadata(
                            model.conversationID)?['errorType'] ??
                        'history_result_unavailable',
                    'errorCode': model.globalModel.lastHistoryErrorMetadata(
                        model.conversationID)?['errorCode'],
                    'errorDescription': model.globalModel
                            .lastHistoryErrorMetadata(
                                model.conversationID)?['description'] ??
                        'history result unavailable',
                  }
                : ChatHistoryTrace.sdkResponseSummary(
                    returnedCount: peekResult.messageList.length,
                    isFinished: peekResult.isFinished,
                    actualSource: 'see_history_response_provenance',
                    newestMsgId: peekResult.messageList.isNotEmpty
                        ? _firstNonEmptyId(peekResult.messageList)
                        : null,
                    newestSeq: peekResult.messageList.isNotEmpty
                        ? int.tryParse(
                            peekResult.messageList.first.seq?.trim() ?? '')
                        : null,
                    newestTs: peekResult.messageList.isNotEmpty
                        ? peekResult.messageList.first.timestamp
                        : null,
                    oldestMsgId: peekResult.messageList.isNotEmpty
                        ? peekResult.messageList.last.msgID
                        : null,
                    oldestSeq: peekResult.messageList.isNotEmpty
                        ? int.tryParse(
                            peekResult.messageList.last.seq?.trim() ?? '')
                        : null,
                    oldestTs: peekResult.messageList.isNotEmpty
                        ? peekResult.messageList.last.timestamp
                        : null,
                  )),
            ...ChatHistoryTrace.paginationGate(
              event: 'after_sdk_response',
              haveMoreData: pagination.haveMoreData,
              haveMoreLatestData: pagination.haveMoreLatestData,
              archiveOlderExhausted: pagination.archiveOlderExhausted,
              archiveOlderActive: pagination.archiveOlderActive,
              suppressArchiveUntilSdkHistory:
                  pagination.suppressArchiveUntilSdkHistory,
              loadingKeysSize: pagination.historyLoadingKeys.length,
              emptyBatchAgeMs:
                  _emptyBatchAgeMs(pagination.lastEmptyBatchAt) ?? 0,
            ),
            'elapsedMsSinceOpened':
                DateTime.now().difference(_enteredAt).inMilliseconds,
          },
        );
        if (peekResult == null) {
          // DIAG: 触发 retryable - peek null 路径
          ChatHistoryTrace.log(
            'diag_load_record_retryable',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'path': 'peek_null',
              'peekResultNull': true,
              'responseIsNull': false,
              'peekIsFinished': false,
              'direction': direction.name,
              'effectiveLastMsgID': effectiveLastMsgID ?? '',
              'effectiveLastMsgSeq': effectiveLastMsgSeq,
              'listLenBefore':
                  model.globalModel.rawMessageCount(model.conversationID),
            },
          );
          _markRetryableHistoryFailure(detail: 'history adapter returned null');
          return false;
        }
        pagination.setArchiveHistoryNotice(null);
        // DIAG: SDK 原始返回（loadChatRecord 主路径） - dump peekResult 原始数据，
        // 不论 useOfficialCloudOnly 还是 union peek 模式都打印。
        ChatHistoryTrace.log(
          'diag_sdk_raw_dump',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'source': useOfficialCloudOnly ? 'cloud_only' : 'local_then_cloud',
            'askCount': count,
            'effectiveLastMsgID': effectiveLastMsgID ?? '',
            'effectiveLastMsgSeq': effectiveLastMsgSeq,
            'returnedCount': peekResult.messageList.length,
            'isFinished': peekResult.isFinished,
            if (peekResult.messageList.isNotEmpty)
              ...ChatHistoryTrace.windowSummary(
                peekResult.messageList,
                prefix: 'peek',
              ),
          },
        );
        cloudResponseProvenByIm06 = useOfficialCloudOnly;
        var mergedMessages = peekResult.messageList;
        var rejectedFallbackPage = false;
        var fallbackCheckedThisAttempt = false;
        // Reuse the completed cloud read and check LOCAL at the same cursor.
        // Retain the cooldown when repeated user gestures find an empty page.
        if (mergedMessages.isEmpty &&
            (_lastEmptyBatchLocalFallbackAt == null ||
                DateTime.now().difference(_lastEmptyBatchLocalFallbackAt!) >=
                    _emptyBatchLocalFallbackWindow)) {
          if (!windowRequestIsCurrent()) return false;
          _lastEmptyBatchLocalFallbackAt = DateTime.now();
          ChatHistoryTrace.log(
            'load_chat_record_local_fallback',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'lastMsgID': effectiveLastMsgID,
              'lastMsgSeq': effectiveLastMsgSeq,
              'reason': 'cloud_empty_batch',
            },
          );
          final localResult =
              await model.globalModel.getHistoryMessageListThroughIm06(
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
            lastMsgID: effectiveLastMsgID,
            lastMsgSeq: effectiveLastMsgSeq,
            lastMsg: effectiveAnchor,
            count: count,
            userID: historyUserID,
            groupID: historyGroupID,
          );
          if (!windowRequestIsCurrent()) return false;
          if (localResult == null) {
            // A failed local read is not a checked empty fallback, even when
            // the earlier cloud response reports an end boundary.
            _markRetryableHistoryFailure(detail: 'local fallback unavailable');
            return false;
          }
          fallbackCheckedThisAttempt = true;
          if (localResult.messageList.isNotEmpty) {
            var admitFallback = true;
            if (model.conversationType == ConvType.group) {
              final continuity =
                  HistoryPaginationContinuity.canAppendOlderBatch(
                existingNewestFirst:
                    _continuityRows(withAcceptedSdkBoundary(inMemoryAtRequest)),
                incomingOlderNewestFirst:
                    _continuityRows(localResult.messageList),
                isGroup: true,
                olderCloudBacked: false,
              );
              if (!continuity.canMerge) {
                admitFallback = false;
                rejectedFallbackPage = true;
                ChatHistoryTrace.log(
                  'union_older_local_rejected_gap',
                  conversationID: model.conversationID,
                  extras: <String, Object?>{
                    ...continuity.toTraceExtras(),
                    'windowCount': inMemoryAtRequest.length,
                    'olderCount': localResult.messageList.length,
                  },
                );
                if (continuity.hasClosedGap) {
                  model.globalModel.noteRejectedOlderPageGap(
                    conversationID: model.conversationID,
                    missingLowerSeq: continuity.missingLowerSeq,
                    missingUpperSeq: continuity.missingUpperSeq,
                  );
                }
              }
            }
            if (admitFallback) {
              mergedMessages = localResult.messageList;
              // The common path below commits peekResult. Preserve the SDK
              // fallback page and its cursor/end flag instead of the empty page.
              peekResult = localResult;
              selectedHistorySource = MessageReconciliationSource.local;
              cloudResponseProvenByIm06 = false;
            }
          }
          // Keep the fallback result visible without re-reading the cloud page.
          ChatHistoryTrace.log(
            'diag_load_record_fallback_done',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'mergedCount': mergedMessages.length,
              'localCount': localResult.messageList.length,
              'fallbackTriggered': true,
              'originalPeekCount': peekResult.messageList.length,
              'originalPeekIsFinished': peekResult.isFinished,
              'effectiveLastMsgID': effectiveLastMsgID ?? '',
              'effectiveLastMsgSeq': effectiveLastMsgSeq,
            },
          );
        }
        if (mergedMessages.isEmpty) {
          if (!windowRequestIsCurrent()) {
            pagination.markHistoryUnknown();
            model._notify();
            return false;
          }
          final invalidAnchor = effectiveAnchor != null &&
              !HistoryPaginationAnchor.canUseForSdkPagination(effectiveAnchor);
          ChatHistoryTrace.log(
            'load_chat_record_empty_batch',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'lastMsgID': effectiveLastMsgID,
              'lastMsgSeq': effectiveLastMsgSeq,
              'count': count,
              'invalidAnchor': invalidAnchor,
            },
          );
          if (invalidAnchor) {
            pagination.markHistoryUnknown();
            tempHaveMoreData = false;
            model._notify();
            return false;
          }
          // End requires a checked fallback with no rejected page. A retry
          // inside the fallback cooldown cannot erase earlier gap evidence.
          // Other outcomes wait for the next user input to retry.
          if (fallbackCheckedThisAttempt &&
              !rejectedFallbackPage &&
              peekResult.isFinished) {
            pagination.haveMoreData = false;
            pagination.lastEmptyBatchAt = null;
          } else {
            pagination.haveMoreData = true;
            pagination.lastEmptyBatchAt = DateTime.now();
          }
          return false;
        }
        response = peekResult;
      } else {
        response = await model.globalModel.getHistoryMessageListThroughIm06(
          count: count,
          getType: resolvedGetType,
          userID: historyUserID,
          groupID: historyGroupID,
          lastMsgID: lastMsgID,
          lastMsgSeq: lastMsgSeq,
          lastMsg: paginationAnchor,
        );
        if (direction == LoadDirection.latest &&
            getType == null &&
            (response == null || response.messageList.isEmpty)) {
          final localLatestResponse =
              await model.globalModel.getHistoryMessageListThroughIm06(
            count: count,
            getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG,
            userID: historyUserID,
            groupID: historyGroupID,
            lastMsgID: lastMsgID,
            lastMsgSeq: lastMsgSeq,
            lastMsg: paginationAnchor,
          );
          if (localLatestResponse != null &&
              localLatestResponse.messageList.isNotEmpty) {
            response = localLatestResponse;
          } else {
            response ??= localLatestResponse;
          }
        }
      }

      if (response == null) {
        final provenance = MessageReconciliationProvenance.resolve(
          requestedSource: requestedHistorySource,
          beforeRequest: networkBeforeHistoryRequest,
          afterResponse: model.globalModel.messageReconciliationNetworkState,
        );
        ChatHistoryTrace.log(
          'history_response_provenance',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'requestedSource': requestedHistorySource.name,
            'actualSource': provenance.actualSource.name,
            'networkState': provenance.networkState.name,
            'cloudProven': provenance.cloudResponseProven,
            'hasResponse': false,
          },
        );
        ChatHistoryTrace.log(
          'load_chat_record_response_empty',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
            'isPaginated': isPaginatedLoad,
          },
        );
        if (direction == LoadDirection.previous) {
          // DIAG: 触发 retryable - sdk response null 路径
          ChatHistoryTrace.log(
            'diag_load_record_retryable',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'path': 'sdk_response_null',
              'peekResultNull': false,
              'responseIsNull': true,
              'peekIsFinished': false,
              'direction': direction.name,
              'lastMsgID': lastMsgID ?? '',
              'lastMsgSeq': lastMsgSeq,
              'isPaginated': isPaginatedLoad,
              'listLenBefore':
                  model.globalModel.rawMessageCount(model.conversationID),
            },
          );
          // A failed search/fallback request is retryable. Do not advance the
          // cursor or latch the scroll gate as exhausted.
          _markRetryableHistoryFailure(detail: 'history response unavailable');
        }
        return false;
      }
      pagination.setArchiveHistoryNotice(null);
      final responseProvenance = MessageReconciliationProvenance.resolve(
        requestedSource: selectedHistorySource,
        beforeRequest: networkBeforeHistoryRequest,
        afterResponse: model.globalModel.messageReconciliationNetworkState,
      );
      ChatHistoryTrace.log(
        'history_response_provenance',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'requestedSource': requestedHistorySource.name,
          'actualSource': responseProvenance.actualSource.name,
          'networkState': responseProvenance.networkState.name,
          'cloudProven': responseProvenance.cloudResponseProven,
          'hasResponse': true,
          'resultCount': response.messageList.length,
          'isFinished': response.isFinished,
          ...ChatHistoryTrace.windowSummary(
            response.messageList,
            prefix: 'response',
          ),
        },
      );
      final coverageResponseMessages = response.messageList;
      if (!_coverageDiagVersionLogged) {
        _coverageDiagVersionLogged = true;
        ChatHistoryTrace.log(
          'local_coverage_diag_version',
          conversationID: model.conversationID,
          extras: const <String, Object?>{'version': 'v3_load_previous'},
        );
      }
      ChatHistoryTrace.log(
        'local_coverage_diag_probe_enter',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'requestedSource': requestedHistorySource.name,
          'actualSource': responseProvenance.actualSource.name,
          'cloudCount': coverageResponseMessages.length,
          'isFinished': response.isFinished,
        },
      );
      if (direction == LoadDirection.previous &&
          responseProvenance.cloudResponseProven &&
          coverageResponseMessages.isNotEmpty) {
        unawaited(
            Future<void>.delayed(const Duration(milliseconds: 80), () async {
          ChatHistoryTrace.log(
            'local_coverage_diag_started',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'cloudReturned': coverageResponseMessages.length,
            },
          );
          try {
            final after =
                await model.globalModel.getHistoryMessageListThroughIm06(
              count: count,
              getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
              userID: historyUserID,
              groupID: historyGroupID,
            );
            ChatHistoryTrace.log(
              'local_coverage_diag_after_cloud',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'cloudReturned': coverageResponseMessages.length,
                'afterLocalCount': after?.messageList.length ?? 0,
                'afterLocalFinished': after?.isFinished,
                'afterResponseNull': after == null,
              },
            );
          } catch (error) {
            ChatHistoryTrace.log(
              'local_coverage_diag_error',
              conversationID: model.conversationID,
              extras: <String, Object?>{'error': error.toString()},
            );
          }
        }));
      }
      final requestedCursor = _requestedCursor(
        direction: direction,
        lastMsgID: actualRequestLastMsgID,
        lastMsgSeq: actualRequestLastMsgSeq,
      );
      final returnedBounds = _returnedBounds(response.messageList);

      // around / 搜索整窗替换后：丢弃替换前发起的在途翻页，防止旧最新页 baseline 污染。
      if (!windowRequestIsCurrent()) {
        ChatHistoryTrace.log(
          'load_chat_record_stale_after_window_replace',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
            'windowGenAtStart': windowGenAtStart,
            'windowGenNow': model._historyWindowGeneration,
            'batchCount': response.messageList.length,
          },
        );
        return false;
      }

      // 运营公众号：云端历史可能为空，回退拉本地缓存。
      if (model.conversationType == ConvType.c2c &&
          model.conversationID.startsWith('@TOA#_') &&
          response.messageList.isEmpty &&
          resolvedGetType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG &&
          lastMsgID == null) {
        final localResponse =
            await model.globalModel.getHistoryMessageListThroughIm06(
          count: count,
          getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
          userID: model.conversationID,
          lastMsgID: lastMsgID,
          lastMsgSeq: lastMsgSeq,
        );
        if (localResponse != null && localResponse.messageList.isNotEmpty) {
          response = localResponse;
        }
      }

      // The native SDK synthesizes isFinished from returnedCount < count.
      // A nonempty older page (including a LOCAL fallback) can therefore be
      // short without reaching the end. Advance its accepted cursor and probe
      // again; only an empty finished response closes the older chain.
      final effectiveIsFinished = response.isFinished &&
          (direction == LoadDirection.latest || response.messageList.isEmpty);
      final pageMessagesAfterFacts = await model.globalModel
          .applyHistoryWindowMutations(
              model.conversationID, response.messageList);
      final rawTail =
          HistoryPaginationAnchor.tailOfCloudOlderPage(response.messageList);
      final followsFilteredTail =
          identical(_filteredSdkTail, actualRequestAnchor);
      bool isBeforeRequest(V2TimMessage message, {required bool strict}) {
        final seq = int.tryParse(message.seq?.trim() ?? '') ?? 0;
        if (model.conversationType == ConvType.group &&
            actualRequestLastMsgSeq > 0 &&
            seq > 0) {
          return strict
              ? seq < actualRequestLastMsgSeq
              : seq <= actualRequestLastMsgSeq;
        }
        final anchorTime = actualRequestAnchor?.timestamp ?? 0;
        final messageTime = message.timestamp ?? 0;
        if (anchorTime <= 0 || messageTime <= 0) return false;
        if (strict && messageTime == anchorTime) {
          // The SDK OLDER response to a full native anchor orders distinct
          // same-second C2C rows. Sender seq cannot establish that ordering.
          return model.conversationType == ConvType.c2c &&
              actualRequestAnchor != null &&
              HistoryPaginationAnchor.canUseForSdkPagination(
                  actualRequestAnchor!) &&
              (!followsFilteredTail ||
                  !_filteredSdkSameTimeIds.contains(message.msgID));
        }
        return strict ? messageTime < anchorTime : messageTime <= anchorTime;
      }

      final rawOlderCursorProgress = useOfficialOlderCursor &&
          direction == LoadDirection.previous &&
          rawTail != null &&
          rawTail.msgID != actualRequestLastMsgID &&
          rawTail.msgID != actualRequestAnchor?.msgID &&
          isBeforeRequest(rawTail, strict: true) &&
          response.messageList
              .where(HistoryPaginationAnchor.canUseForSdkPagination)
              .every((row) => isBeforeRequest(row, strict: false));
      if (!windowRequestIsCurrent()) return false;
      if (direction != LoadDirection.latest) {
        tempHaveMoreData = !effectiveIsFinished;
      }

      // 根据 lastMsgID / lastMsgSeq 判断是否为分页加载。
      if (isPaginatedLoad) {
        List<V2TimMessage> messageList = pageMessagesAfterFacts;
        List<V2TimMessage> newList = [];

        // Rebase on the newest in-memory list after the SDK request completes.
        final mergeBase = _aliasAwareInMemoryList(model);
        if (mergeBase.isEmpty && previousPaginationBaseline.isNotEmpty) {
          mergeBase.addAll(previousPaginationBaseline);
        }

        // 根据加载方向拼接消息列表
        if (direction == LoadDirection.latest) {
          messageList = messageList.reversed.toList();
          final canMerge = HistoryPaginationContinuity.canPrependNewerBatch(
            // A live head is not the cursor of this in-flight request.
            // If the cursor cannot be resolved, admit SDK rows for sorted
            // deduplication rather than discard a potentially missing page.
            existingNewestFirst: const [],
            requestedAnchor: paginationAnchor == null
                ? null
                : (
                    seq: int.tryParse(paginationAnchor.seq?.trim() ?? ''),
                    timestamp: paginationAnchor.timestamp,
                  ),
            isGroup: model.conversationType == ConvType.group,
            incomingNewerNewestFirst: messageList
                .map(
                  (m) => (
                    seq: int.tryParse(m.seq?.trim() ?? ''),
                    timestamp: m.timestamp,
                  ),
                )
                .toList(growable: false),
          );
          if (!canMerge) {
            final existingNewestTs =
                mergeBase.isEmpty ? 0 : (mergeBase.first.timestamp ?? 0);
            final incomingOldestTs =
                messageList.isEmpty ? 0 : (messageList.last.timestamp ?? 0);
            ChatHistoryTrace.log(
              'load_latest_rejected_direction_error',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'mergeBaseCount': mergeBase.length,
                'incomingCount': messageList.length,
                'existingNewestTs': existingNewestTs,
                'incomingOldestTs': incomingOldestTs,
                'lastMsgID': lastMsgID,
                'lastMsgSeq': lastMsgSeq,
              },
            );
            // Direction error only (incoming is older than existing newest).
            // Keep prior window; leave tip-fill available for a later batch.
            pagination.haveMoreLatestData = true;
            model._notify();
            return false;
          }
          newList = _combineMessageList(messageList, mergeBase);
        } else {
          // Group previous must prove abutment with the contiguous spine.
          // Disconnected pages only produce gap metadata — never change the spine.
          if (model.conversationType == ConvType.group) {
            final olderCloudBacked = cloudResponseProvenByIm06 ||
                responseProvenance.cloudResponseProven;
            // Accepted SDK rows still establish continuity when local facts or
            // lifecycle filtering hide them from the visible window. Check the
            // transport page before filtering, from its accepted SDK boundary.
            final continuity = HistoryPaginationContinuity.canAppendOlderBatch(
              existingNewestFirst:
                  _continuityRows(withAcceptedSdkBoundary(mergeBase)),
              incomingOlderNewestFirst: _continuityRows(response.messageList),
              isGroup: true,
              olderCloudBacked: olderCloudBacked,
            );
            if (!continuity.canMerge) {
              ChatHistoryTrace.log(
                'load_previous_rejected_seq_gap',
                conversationID: model.conversationID,
                extras: <String, Object?>{
                  ...continuity.toTraceExtras(),
                  'olderCloudBacked': olderCloudBacked,
                  'mergeBaseCount': mergeBase.length,
                  'incomingCount': messageList.length,
                  'lastMsgID': lastMsgID,
                  'lastMsgSeq': lastMsgSeq,
                },
              );
              if (continuity.hasClosedGap) {
                model.globalModel.noteRejectedOlderPageGap(
                  conversationID: model.conversationID,
                  missingLowerSeq: continuity.missingLowerSeq,
                  missingUpperSeq: continuity.missingUpperSeq,
                );
              }
              ChatHistoryTrace.log(
                'merge_decision',
                conversationID: model.conversationID,
                extras: <String, Object?>{
                  ...ChatHistoryTrace.mergeDecision(
                    decision: 'seq_gap_rejected',
                    commitBaseCount: mergeBase.length,
                    dedupedCount: mergeBase.length,
                    rawBatchCount: response.messageList.length,
                    isFinished: response.isFinished,
                    haveMoreDataAfter: true,
                    currentOldestSeq: continuity.existingMinSeq,
                    responseNewestSeq: continuity.incomingMaxSeq,
                  ),
                  ...continuity.toTraceExtras(),
                },
              );
              // Keep retryable; do not advance official older cursor.
              pagination.haveMoreData = true;
              tempHaveMoreData = true;
              model._notify();
              return false;
            }
          }
          newList = _combineMessageList(mergeBase, messageList);
        }
        if (direction == LoadDirection.previous) {
          final currentOldest =
              HistoryPaginationAnchor.oldestSdkPaginationAnchor(mergeBase);
          final hasStrictlyOlderMessage = currentOldest == null ||
              (model.conversationType == ConvType.c2c &&
                  rawOlderCursorProgress &&
                  !mergeBase.any((row) => row.msgID == rawTail!.msgID)) ||
              messageList.any(
                (message) =>
                    TUIChatGlobalModel.compareMessagesChronological(
                      message,
                      currentOldest,
                    ) <
                    0,
              );
          if (messageList.isNotEmpty && !hasStrictlyOlderMessage) {
            final mismatchBounds = _returnedBounds(messageList);
            ChatHistoryTrace.log(
              'load_previous_direction_mismatch',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                'requestedLastMsgID': lastMsgID,
                'requestedLastMsgSeq': lastMsgSeq,
                'currentOldestMsgID': currentOldest.msgID,
                'currentOldestSeq': currentOldest.seq,
                'responseNewestMsgID': mismatchBounds.newestMsgID,
                'responseNewestSeq': mismatchBounds.newestSeq,
                'responseOldestMsgID': mismatchBounds.oldestMsgID,
                'responseOldestSeq': mismatchBounds.oldestSeq,
                'isFinished': response.isFinished,
              },
            );
            // A rejected page cannot prove the requested history ended.
            // Keep the cursor; the UI waits for a new drag before retrying.
            pagination.markHistoryUnknown();
            tempHaveMoreData = pagination.haveMoreData;
            ChatHistoryTrace.log(
              'merge_decision',
              conversationID: model.conversationID,
              extras: <String, Object?>{
                ...ChatHistoryTrace.mergeDecision(
                  decision: 'direction_mismatch',
                  commitBaseCount: mergeBase.length,
                  dedupedCount: messageList.length,
                  rawBatchCount: response.messageList.length,
                  isFinished: response.isFinished,
                  haveMoreDataAfter: pagination.haveMoreData,
                  currentOldestSeq: int.tryParse(currentOldest.seq ?? ''),
                  responseNewestSeq:
                      int.tryParse(mismatchBounds.newestSeq?.toString() ?? ''),
                ),
              },
            );
            model._notify();
            return false;
          }
          _logPreviousPaginationStage(
            model.conversationID,
            stage: 'after_combine',
            extras: <String, Object?>{
              'mergeBaseCount': mergeBase.length,
              'rawBatchCount': messageList.length,
              'combinedCount': newList.length,
              'aliasMergedCountNow': _aliasAwareInMemoryList(model).length,
              'isFinished': response.isFinished,
            },
          );
        }

        // 处理新获取的消息列表后回调
        final List<V2TimMessage> msgList =
            await model.lifeCycle?.didGetHistoricalMessageList(newList) ??
                newList;
        if (direction == LoadDirection.previous &&
            msgList.length != newList.length) {
          _logPreviousPaginationStage(
            model.conversationID,
            stage: 'lifecycle_mutated',
            extras: <String, Object?>{
              'beforeLifecycle': newList.length,
              'afterLifecycle': msgList.length,
              'delta': msgList.length - newList.length,
            },
          );
        }
        // didGetHistoricalMessageList may itself await application work. Rebase
        // once more so messages received during that callback are not erased by
        // the replace-style atomic commit below.
        final afterLifecycleBase = _aliasAwareInMemoryList(model);
        final stableCommitBase = previousPaginationBaseline.isNotEmpty
            ? _mergeHistoryPage(
                direction: direction,
                existing: previousPaginationBaseline,
                fetched: afterLifecycleBase,
              )
            : afterLifecycleBase;
        final dedupedMsgList = _mergeHistoryPage(
          direction: direction,
          existing: stableCommitBase,
          fetched: msgList,
          validatedOlderTail: rawTail,
        );
        final commitBaseCount = stableCommitBase.length;
        if (!windowRequestIsCurrent()) return false;
        // A fully filtered page can advance the transport cursor without
        // growing the visible list. Duplicates, unorderable rows and wrong-way
        // responses do not establish progress. Publication below must still
        // pass all fences and the normal reconciliation commit.
        final filteredOlderPageProgress = rawOlderCursorProgress &&
            dedupedMsgList.length <= commitBaseCount &&
            !stableCommitBase.any((row) => row.msgID == rawTail!.msgID);
        if (isPaginatedLoad) {
          _logPreviousPaginationStage(
            model.conversationID,
            stage: 'pre_commit_merge',
            extras: <String, Object?>{
              'direction': direction.name,
              'baselineCount': previousPaginationBaseline.length,
              'afterLifecycleAliasCount': afterLifecycleBase.length,
              'stableCommitBaseCount': commitBaseCount,
              'dedupedCount': dedupedMsgList.length,
              'rawBatchCount': response.messageList.length,
              'grew': dedupedMsgList.length > commitBaseCount,
            },
          );
        }

        if (direction == LoadDirection.previous &&
            dedupedMsgList.length <= commitBaseCount &&
            !filteredOlderPageProgress) {
          ChatHistoryTrace.log(
            'load_chat_record_dedupe_no_growth',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'beforeCount': commitBaseCount,
              'afterCount': dedupedMsgList.length,
              'rawBatchCount': response.messageList.length,
              'isFinished': response.isFinished,
              'haveMoreData': pagination.haveMoreData,
              'lastMsgID': lastMsgID,
              'lastMsgSeq': lastMsgSeq,
            },
          );
          ChatHistoryTrace.log(
            'merge_decision',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              ...ChatHistoryTrace.mergeDecision(
                decision: 'no_growth',
                commitBaseCount: commitBaseCount,
                dedupedCount: dedupedMsgList.length,
                rawBatchCount: response.messageList.length,
                isFinished: response.isFinished,
                haveMoreDataAfter: pagination.haveMoreData,
              ),
            },
          );
          // A page with no trustworthy transport progress cannot prove history
          // ended. Retry the same cursor on the next deliberate user drag.
          pagination.markHistoryUnknown();
          tempHaveMoreData = pagination.haveMoreData;
          model._notify();
          // 列表未增长时不算成功加载，避免 UI 误判后停止重试。
          return false;
        }

        previousListGrew = dedupedMsgList.length > commitBaseCount;
        if (previousListGrew &&
            HistoryPaginationAnchor.oldestSdkPaginationAnchor(dedupedMsgList) !=
                null) {
          pagination.suppressArchiveUntilSdkHistory = false;
        }

        var finalList = dedupedMsgList;
        // Perform the final compare-and-merge immediately before committing;
        // SDK callbacks may complete while lifecycle work is in flight.
        final latestBeforeCommit = _aliasAwareInMemoryList(model);
        final stableLatestBeforeCommit = previousPaginationBaseline.isNotEmpty
            ? _mergeHistoryPage(
                direction: direction,
                existing: previousPaginationBaseline,
                fetched: latestBeforeCommit,
              )
            : latestBeforeCommit;
        finalList = _mergeHistoryPage(
          direction: direction,
          existing: stableLatestBeforeCommit,
          fetched: finalList,
          validatedOlderTail: rawTail,
        );
        previousListGrew = finalList.length > stableLatestBeforeCommit.length;
        if (isPaginatedLoad) {
          _logPreviousPaginationStage(
            model.conversationID,
            stage: 'final_before_set_list',
            extras: <String, Object?>{
              'direction': direction.name,
              'baselineCount': previousPaginationBaseline.length,
              'latestAliasCount': latestBeforeCommit.length,
              'stableLatestCount': stableLatestBeforeCommit.length,
              'finalCount': finalList.length,
              'previousListGrew': previousListGrew,
              'applyMemoryWindow': false,
              'isFinished': response.isFinished,
            },
          );
        }
        if (previousPaginationBaseline.isNotEmpty &&
            finalList.length < previousPaginationBaseline.length) {
          _logPreviousPaginationStage(
            model.conversationID,
            stage: 'commit_rejected_shrink',
            extras: <String, Object?>{
              'direction': direction.name,
              'baselineCount': previousPaginationBaseline.length,
              'finalCount': finalList.length,
              'lost': previousPaginationBaseline.length - finalList.length,
              'lastMsgID': lastMsgID,
              'lastMsgSeq': lastMsgSeq,
            },
          );
          ChatHistoryTrace.log(
            'merge_decision',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              ...ChatHistoryTrace.mergeDecision(
                decision: 'shrink_rejected',
                commitBaseCount: previousPaginationBaseline.length,
                dedupedCount: finalList.length,
                rawBatchCount: response.messageList.length,
                isFinished: response.isFinished,
                haveMoreDataAfter: pagination.haveMoreData,
              ),
              'lost': previousPaginationBaseline.length - finalList.length,
            },
          );
          if (direction != LoadDirection.latest) {
            pagination.markHistoryUnknown();
          }
          model._notify();
          return false;
        }

        // 已是完整合并列表，replace 避免再与 previous 拼接出重复项，
        // 并防止一次分页产生两次 layout 跳滚。
        if (!windowRequestIsCurrent()) {
          ChatHistoryTrace.log(
            'load_chat_record_stale_before_commit',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'direction': direction.name,
              'windowGenAtStart': windowGenAtStart,
              'windowGenNow': model._historyWindowGeneration,
              'finalCount': finalList.length,
            },
          );
          return false;
        }
        finalList = await model.globalModel
            .applyHistoryWindowMutations(model.conversationID, finalList);
        if (!windowRequestIsCurrent()) return false;
        if (isPaginatedLoad &&
            model.globalModel
                .historyWindowPaginationBlocked(model.conversationID))
          return false;
        final reconciliationCommit =
            model.globalModel.completeHistoryReconciliation(
          request: reconciliationRequest,
          history: finalList,
          actualSource: responseProvenance.actualSource,
          networkState: responseProvenance.networkState,
          // 上翻提交先保留完整窗口，待 UI 完成视口补偿后再按锚点收束。
          // 旧契约要求此处明确区分 previous，搜索定位也因此不会丢目标行。
          applyMemoryWindow: false,
          memoryWindowPreferLatest:
              direction == LoadDirection.latest || forceReloadNewest,
          historyCommitSource: direction.name,
          batchKind: direction == LoadDirection.latest
              ? MessageHistoryBatchKind.newerCatchUp
              : MessageHistoryBatchKind.olderPage,
          historyIsFinished: effectiveIsFinished,
          clearEpoch: model.globalModel
                  .messageHistoryCoverageFor(model.conversationID)
                  ?.clearEpoch ??
              0,
          requestedCursor: requestedCursor,
          returnedBounds: returnedBounds,
          cloudResponseProven: cloudResponseProvenByIm06 ||
              responseProvenance.cloudResponseProven,
        );
        if (reconciliationCommit == null) {
          ChatHistoryTrace.log(
            'history_commit_rejected',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'direction': direction.name,
              'batchKind': MessageHistoryBatchKind.olderPage.name,
              'historyCount': finalList.length,
              'baselineCount': previousPaginationBaseline.length,
              'lastMsgID': lastMsgID,
              'lastMsgSeq': lastMsgSeq,
              'windowGeneration': windowGenAtStart,
              'windowGenerationNow': model._historyWindowGeneration,
            },
          );
          return false;
        }
        reconciliationCommitted = true;
        ChatHistoryTrace.log(
          'history_commit_applied',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'batchKind': MessageHistoryBatchKind.olderPage.name,
            'historyCount': finalList.length,
            'baselineCount': previousPaginationBaseline.length,
            'rawCount': model.globalModel.rawMessageCount(model.conversationID),
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
          },
        );
        if (direction == LoadDirection.previous) {
          ChatHistoryTrace.log(
            'merge_decision',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              ...ChatHistoryTrace.mergeDecision(
                decision: filteredOlderPageProgress ? 'filtered_progress' : 'grew',
                commitBaseCount: previousListGrew
                    ? previousPaginationBaseline.length
                    : stableLatestBeforeCommit.length,
                dedupedCount: finalList.length,
                rawBatchCount: response.messageList.length,
                isFinished: response.isFinished,
                haveMoreDataAfter: pagination.haveMoreData,
                currentOldestSeq: previousListGrew
                    ? int.tryParse(
                        HistoryPaginationAnchor.oldestSdkPaginationAnchor(
                                    finalList)
                                ?.seq ??
                            '')
                    : null,
                responseNewestSeq:
                    int.tryParse(response.messageList.first.seq?.trim() ?? ''),
              ),
              'previousListGrew': previousListGrew,
              'listTailMsgID': finalList.isNotEmpty ? finalList.last.msgID : '',
            },
          );
        }
        // Only an accepted current-window commit may advance the SDK cursor.
        // A filtered page retains the visible window and returns false below,
        // so its continuation waits for another user drag rather than spinning.
        if (useOfficialOlderCursor &&
            direction == LoadDirection.previous &&
            (previousListGrew || filteredOlderPageProgress)) {
          model._rememberSdkOlderPage(response.messageList);
          if (filteredOlderPageProgress &&
              model.conversationType == ConvType.c2c) {
            if (!followsFilteredTail ||
                rawTail!.timestamp != actualRequestAnchor?.timestamp) {
              _filteredSdkSameTimeIds.clear();
            }
            _filteredSdkSameTimeIds.addAll(response.messageList
                .where((row) => row.timestamp == rawTail!.timestamp)
                .map((row) => row.msgID?.trim() ?? '')
                .where((id) => id.isNotEmpty));
            if (actualRequestAnchor?.timestamp == rawTail!.timestamp &&
                actualRequestAnchor?.msgID != null) {
              _filteredSdkSameTimeIds.add(actualRequestAnchor!.msgID!);
            }
            _filteredSdkTail = model._sdkOlderPageTail;
          }
        }
      } else {
        // 处理新获取的消息列表后回调
        List<V2TimMessage> receivedList =
            await model.lifeCycle?.didGetHistoricalMessageList(
                  pageMessagesAfterFacts,
                ) ??
                pageMessagesAfterFacts;
        receivedList = await model.globalModel
            .applyHistoryWindowMutations(model.conversationID, receivedList);
        if (!windowRequestIsCurrent()) return false;
        model.globalModel.loadingMessage.remove(model.conversationID);

        // An empty/filtered transport response did not replace the old window.
        // It cannot acknowledge the deferred watermark as a successful return.
        if (forceReloadNewest && receivedList.isEmpty) return false;

        if (model.conversationType == ConvType.c2c &&
            model.conversationID.startsWith('@TOA#_') &&
            receivedList.isEmpty) {
          final existing = _aliasAwareInMemoryList(model);
          if (existing.isNotEmpty) {
            model._notify();
            if (direction == LoadDirection.previous) {
              pagination.markHistoryUnknown();
            }
            return pagination.haveMoreData;
          }
        }

        if (receivedList.isEmpty) {
          final existing = _aliasAwareInMemoryList(model);
          if (existing.isNotEmpty) {
            model._notify();
            if (direction == LoadDirection.previous) {
              pagination.markHistoryUnknown();
            } else {
              pagination.haveMoreData = tempHaveMoreData;
            }
            return pagination.haveMoreData;
          }
        }

        // 首屏整表写入前合并拉取期间 upsert 进内存的新消息，避免竞态覆盖。
        final existingInMemory = _aliasAwareInMemoryList(model);
        // 强制回最新窗：丢弃旧窗，直接用最新一页，避免与裁残窗口 merge。
        var mergedList = ChatMainThreadPerf.measure(
          ChatMainThreadPerf.historyMergeMs,
          () => forceReloadNewest
              ? model._dedupeMessages(receivedList)
              : (existingInMemory.isNotEmpty
                  ? _combineMessageList(existingInMemory, receivedList)
                  : model._dedupeMessages(receivedList)),
          count: receivedList.length,
          source: direction.name,
          conversationType: model.conversationType?.name ?? 'none',
        );
        mergedList = await model.globalModel
            .applyHistoryWindowMutations(model.conversationID, mergedList);
        if (!windowRequestIsCurrent()) return false;

        final reconciliationCommit =
            model.globalModel.completeHistoryReconciliation(
          request: reconciliationRequest,
          history: model.usesOfficialSdkHistory ? receivedList : mergedList,
          actualSource: responseProvenance.actualSource,
          networkState: responseProvenance.networkState,
          memoryWindowPreferLatest:
              direction == LoadDirection.latest || forceReloadNewest,
          historyCommitSource: direction.name,
          batchKind: MessageHistoryBatchKind.latestWindow,
          historyIsFinished: effectiveIsFinished,
          clearEpoch: model.globalModel
                  .messageHistoryCoverageFor(model.conversationID)
                  ?.clearEpoch ??
              0,
          requestedCursor: requestedCursor,
          returnedBounds: returnedBounds,
          cloudResponseProven: cloudResponseProvenByIm06 ||
              responseProvenance.cloudResponseProven,
        );
        if (reconciliationCommit == null) {
          ChatHistoryTrace.log(
            'history_commit_rejected',
            conversationID: model.conversationID,
            extras: <String, Object?>{
              'direction': direction.name,
              'batchKind': MessageHistoryBatchKind.latestWindow.name,
              'historyCount': model.usesOfficialSdkHistory
                  ? receivedList.length
                  : mergedList.length,
              'existingCount': existingInMemory.length,
              'lastMsgID': lastMsgID,
              'lastMsgSeq': lastMsgSeq,
              'windowGeneration': windowGenAtStart,
              'windowGenerationNow': model._historyWindowGeneration,
            },
          );
          return false;
        }
        reconciliationCommitted = true;
        if (model.usesOfficialSdkHistory && receivedList.isNotEmpty) {
          model._rememberSdkOlderPage(response.messageList);
        }
        ChatHistoryTrace.log(
          'history_commit_applied',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'direction': direction.name,
            'batchKind': MessageHistoryBatchKind.latestWindow.name,
            'historyCount': model.usesOfficialSdkHistory
                ? receivedList.length
                : mergedList.length,
            'existingCount': existingInMemory.length,
            'rawCount': model.globalModel.rawMessageCount(model.conversationID),
            'lastMsgID': lastMsgID,
            'lastMsgSeq': lastMsgSeq,
          },
        );
        if (forceReloadNewest) {
          model.globalModel.clearMemoryWindowMissingNewer(model.conversationID);
          pagination.haveMoreLatestData = false;
          // 回最新窗是替换而非增长；仍视为成功，供 tongue/回底等待。
          previousListGrew = mergedList.isNotEmpty;
          pagination.haveMoreData = !effectiveIsFinished;
          tempHaveMoreData = pagination.haveMoreData;
        }
        if (mergedList.isNotEmpty &&
            HistoryPaginationAnchor.oldestSdkPaginationAnchor(mergedList) !=
                null) {
          pagination.suppressArchiveUntilSdkHistory = false;
        }
        if (lastMsgID == null && lastMsgSeq <= 0 && mergedList.isNotEmpty) {
          // 首屏请求完成就放开渲染闸门；空结果不在此标记，避免离线登录同步未完成时误判。
          if (mergedList.length >= count || response.isFinished) {
            if (responseProvenance.proofKind ==
                MessageHistoryProofKind.serverContinuity) {
              model.globalModel.markCloudInitialHistoryVerified(
                model.conversationID,
              );
            } else {
              model.globalModel.markLocalInitialHistoryVisible(
                model.conversationID,
              );
            }
          }
        }
      }

      model._notify();

      unawaited(model._ensureGroupInfoLoaded());

      // 上翻历史时不批量拉已读回执，避免与分页争抢网络；新消息/首屏仍走原有逻辑。
      if (model._canUseReadReceipt &&
          response.messageList.isNotEmpty &&
          direction != LoadDirection.previous) {
        model._getMsgReadReceipt(response.messageList);
      }

      if (forceReloadNewest && reconciliationCommitted) {
        model._clearHistoryReadingWindow();
      }
      // 根据加载方向更新是否还能继续加载更多消息
      if (direction == LoadDirection.latest) {
        // Publish availability only after a successful, current-window commit.
        // Exhausting the SDK page proves continuity, not viewport position.
        model._acceptHistoryNewerPage(response.messageList);
        model.haveMoreLatestData =
            !response.isFinished || model._historyKnownTipMissing;
      }

      if (direction == LoadDirection.previous) {
        pagination.haveMoreData = tempHaveMoreData;
      }
      ChatHistoryTrace.log(
        'load_chat_record_done',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'lastMsgID': lastMsgID,
          'lastMsgSeq': lastMsgSeq,
          'batchCount': response.messageList.length,
          'isFinished': response.isFinished,
          'haveMoreData': pagination.haveMoreData,
          'haveMoreLatestData': pagination.haveMoreLatestData,
          'memoryWindowMissingNewer':
              model.globalModel.memoryWindowMissingNewer(model.conversationID),
          'listLen': model.globalModel.rawMessageCount(model.conversationID),
          'previousListGrew': previousListGrew,
        },
      );
      if (direction == LoadDirection.previous) {
        // 有实际新增才视为 loaded=true，供 UI 做 scroll restore；
        // 不能仅用 pagination.haveMoreData（SDK isFinished 时 pagination.haveMoreData=false 但 batch 已写入）。
        return previousListGrew;
      }
      return pagination.haveMoreLatestData;
    } catch (e) {
      ChatHistoryTrace.log(
        'load_chat_record_error',
        conversationID: model.conversationID,
        extras: <String, Object?>{
          'direction': direction.name,
          'lastMsgID': lastMsgID,
          'lastMsgSeq': lastMsgSeq,
          'error': e.toString(),
        },
      );
      // ignore: avoid_print
      outputLogger.i('loadChatRecord error: $e');
      if (direction == LoadDirection.previous) {
        // DIAG: 触发 retryable - catch 异常路径
        ChatHistoryTrace.log(
          'diag_load_record_retryable',
          conversationID: model.conversationID,
          extras: <String, Object?>{
            'path': 'exception',
            'peekResultNull': false,
            // 异常路径下 response 在 try 块内，可能未赋值；用 false 占位，
            // 真正的异常信息已在 errorType / errorMessage 给出。
            'responseIsNull': true,
            'peekIsFinished': false,
            'direction': direction.name,
            'errorType': e.runtimeType.toString(),
            'errorMessage': e.toString(),
            'listLenBefore':
                model.globalModel.rawMessageCount(model.conversationID),
          },
        );
        _markRetryableHistoryFailure(
          detail: e.toString(),
          errorType: 'exception',
        );
      }
      return false;
    } finally {
      final pendingReconciliation = reconciliationRequest;
      if (pendingReconciliation != null && !reconciliationCommitted) {
        model.globalModel.failHistoryReconciliation(
          request: pendingReconciliation,
          reason: 'history_request_not_committed',
        );
      }
      pagination.historyLoadingKeys.remove(requestKey);
      if (pagination.historyLoadingKeys.isEmpty) {
        model._notify();
      }
      if (isPreviousPagination) {
        pagination.previousPaginationInFlight = false;
        ConversationHistorySyncCoordinator.instance
            .endUserOlderPagination(model.conversationID);
      }
    }
  }

  // 拼接聊天记录
  List<V2TimMessage> _mergeHistoryPage({
    required LoadDirection direction,
    required List<V2TimMessage> existing,
    required List<V2TimMessage> fetched,
    V2TimMessage? validatedOlderTail,
  }) {
    if (model.usesOfficialSdkHistory) {
      // Newer catch-up already passed canPrependNewerBatch. Applying the
      // older-page abutment proof here drops it while its cursor advances.
      if (direction == LoadDirection.previous &&
          model.conversationType == ConvType.group &&
          existing.isNotEmpty) {
        // Secondary insurance: only the older-only portion of [fetched] may
        // extend the spine. If that portion cannot abut, keep existing.
        final existingIds = <String>{
          for (final message in existing)
            if ((message.msgID?.trim() ?? '').isNotEmpty) message.msgID!.trim(),
        };
        final olderOnly = fetched
            .where((message) {
              final id = message.msgID?.trim() ?? '';
              return id.isEmpty || !existingIds.contains(id);
            })
            .toList(growable: false);
        if (olderOnly.isNotEmpty) {
          final continuity = HistoryPaginationContinuity.canAppendOlderBatch(
            // The caller has already checked this raw SDK page against the
            // accepted boundary. Its filtered tail still proves traversal.
            existingNewestFirst: _continuityRows([
              ...existing,
              if (validatedOlderTail != null) validatedOlderTail,
            ]),
            incomingOlderNewestFirst: _continuityRows(olderOnly),
            isGroup: true,
            // A2 already enforced local zero-slack; secondary only blocks
            // clearly disconnected pages (gap > defaultMaxCloudSeqGap).
            olderCloudBacked: true,
          );
          if (!continuity.canMerge) {
            ChatHistoryTrace.log(
              'merge_history_page_rejected_seq_gap',
              conversationID: model.conversationID,
              extras: continuity.toTraceExtras(),
            );
            if (continuity.hasClosedGap) {
              model.globalModel.noteRejectedOlderPageGap(
                conversationID: model.conversationID,
                missingLowerSeq: continuity.missingLowerSeq,
                missingUpperSeq: continuity.missingUpperSeq,
              );
            }
            return List<V2TimMessage>.of(existing);
          }
        }
      }
      return TUIChatGlobalModel.mergeC2cOfficialOlderPage(
        existing: existing,
        fetched: fetched,
      );
    }
    return TUIChatGlobalModel.mergeHistoricalWithInMemory(
      existing: existing,
      fetched: fetched,
    );
  }

  List<V2TimMessage> _combineMessageList(
    List<V2TimMessage> first,
    List<V2TimMessage> second,
  ) {
    return TUIChatGlobalModel.sortMessagesNewestFirst(
      model._dedupeMessages([...first, ...second]),
    );
  }
}

List<({int? seq, String? msgID})> _continuityRows(
  List<V2TimMessage> messages,
) {
  return messages
      .map(
        (message) => (
          seq: int.tryParse(message.seq?.trim() ?? ''),
          msgID: message.msgID?.trim(),
        ),
      )
      .toList(growable: false);
}

List<V2TimMessage> _aliasAwareInMemoryList(TUIChatSeparateViewModel model) {
  return model.globalModel.canonicalMessageWindow(model.conversationID);
}

void _logPreviousPaginationStage(
  String conversationID, {
  required String stage,
  Map<String, Object?> extras = const <String, Object?>{},
}) {
  ChatHistoryTrace.log(
    'load_previous_$stage',
    conversationID: conversationID,
    extras: extras,
  );
  ChatJitterDiag.log(
    'history_pagination',
    conv: conversationID,
    extras: <String, Object?>{'stage': stage, ...extras},
  );
}
