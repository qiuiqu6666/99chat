import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:tencent_cloud_chat_demo/src/models/chat_entry_snapshot.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_readiness.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/open_viewport_cache.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_sync_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// 进聊首窗快照状态机。
///
/// 导航只允许等待本地 fast classify。H0 可以并行启动，但不能成为
/// push 的必经 await。Chat 页第一帧只吃 Collection 锁定的那份 snapshot。
/// 云端 freshness 仍由 ConversationHistorySyncCoordinator 在首帧后负责。
/// 这里不能再把完整云历史绑回进页关键路径。
enum ChatOpenViewportPhase {
  idle,
  preparing,
  prepared,
  viewportReady,
  transitioning,
  visible,
  cancelled,
}

class ChatOpenViewportCoordinator {
  ChatOpenViewportCoordinator._();

  static final ChatOpenViewportCoordinator instance =
      ChatOpenViewportCoordinator._();

  int _requestId = 0;
  String? _activeKey;
  ChatOpenViewportPhase _phase = ChatOpenViewportPhase.idle;
  int get currentRequestId => _requestId;

  ChatOpenViewportPhase get phase => _phase;

  ChatOpenViewportPhase phaseFor(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return ChatOpenViewportPhase.idle;
    }
    return _phase;
  }

  bool isCurrent(int requestId, String conversationKey) {
    final key = conversationKey.trim();
    return requestId == _requestId &&
        key.isNotEmpty &&
        key == (_activeKey ?? '');
  }

  void markTransitioning(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return;
    }
    _phase = ChatOpenViewportPhase.transitioning;
  }

  void markVisible(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty || key != (_activeKey ?? '')) {
      return;
    }
    _phase = ChatOpenViewportPhase.visible;
  }

  void resetForTest() {
    _requestId = 0;
    _activeKey = null;
    _phase = ChatOpenViewportPhase.idle;
  }

  ChatOpenPrepareWorkSnapshot recordPrepareStart({
    required int requestId,
    required String source,
  }) {
    return ChatOpenPerfLog.recordPrepareStart(
      requestId: requestId,
      source: source,
    );
  }

  ChatOpenPrepareWorkSnapshot? snapshotFor(int requestId) {
    return ChatOpenPerfLog.snapshotFor(requestId);
  }

  /// 兼容旧观测埋点的准备预算。实际点击路径另有更短的本地快照交接预算，
  /// 不得扩展到网络 RTT。
  static const Duration prepareTimeout = Duration(milliseconds: 400);

  /// Memory + 本地库 fast budget。云不在这条路径。
  static const Duration localBudget = Duration(milliseconds: 100);

  /// 本地空/洞时允许 H0 latest page 赶上转场的 grace。超时继续转场。
  static const Duration cloudGraceBudget = Duration(milliseconds: 200);

  /// 点击会话时启动一次本地首窗读取。该任务只访问 IM SDK 本地库，
  /// 不访问云端；聊天页和 UIKit 通过同一个 Future 复用结果。
  Future<bool> ensureLocalSnapshotForOpen({
    required V2TimConversation conversation,
    Duration timeout = const Duration(milliseconds: 280),
    ChatOpenTraceContext? logTrace,
    bool windowAlreadyCleared = false,
  }) async {
    final key = _conversationKey(conversation);
    if (key.isEmpty) {
      return false;
    }
    final hydrateTrace = logTrace ??
        ChatOpenPerfLog.captureCurrent(conversationKey: key);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // Search owns its anchor window; a latest-window result cannot satisfy it.
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key)) {
      return _ensureLatestWindowResetForOpen(
        conversation: conversation,
        key: key,
        globalModel: globalModel,
        timeout: timeout,
        logTrace: hydrateTrace,
        windowAlreadyCleared: windowAlreadyCleared,
      );
    }
    if (ConversationPreviewHistorySync.canSkipOpenRebootstrap(
      globalModel: globalModel,
      conversationKey: key,
      preview: conversation.lastMessage,
    )) return true;
    final identity = SessionIdentityService.instance.capture();
    final last = conversation.lastMessage;
    final signature = '${identity.ownerUserId}|${identity.generation}|'
        '${last?.msgID}|${last?.seq}|${last?.timestamp}|'
        '${globalModel.messageDeltaClearEpochFor(key)}';
    final task = ChatOpenPerfLog.withTrace(hydrateTrace, () => globalModel.ensureOpenHydrate(
      key,
      requestSignature: signature,
      canPublish: () =>
          SessionIdentityService.instance.capture() == identity &&
          globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle,
      load: () => ChatHistoryPeekBootstrap.apply(
        conversation: conversation,
        globalModel: globalModel,
        allowCloudVerification: false,
        logTrace: hydrateTrace,
      ),
    ));
    try {
      return (await task.timeout(timeout)).shouldSuppressOrdinaryLoad;
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'local_snapshot_wait_timeout',
        conversationID: key,
        extras: <String, Object?>{'timeoutMs': timeout.inMilliseconds},
        trace: hydrateTrace,
      );
      return false;
    }
  }

  /// First open after a real reconnect. The reset service, not the ordinary
  /// local hydrate, owns the first window: no stale cache is shown and the
  /// open hydrate stays in flight until a validated window is installed.
  Future<bool> _ensureLatestWindowResetForOpen({
    required V2TimConversation conversation,
    required String key,
    required TUIChatGlobalModel globalModel,
    required Duration timeout,
    required ChatOpenTraceContext logTrace,
    required bool windowAlreadyCleared,
  }) async {
    final identity = SessionIdentityService.instance.capture();
    final last = conversation.lastMessage;
    final epoch = ImConnectStatusService.recoveryEpoch;
    final signature = 'latest_window_reset|$epoch|'
        '${identity.ownerUserId}|${identity.generation}|'
        '${last?.msgID}|${last?.seq}|${last?.timestamp}|'
        '${globalModel.messageDeltaClearEpochFor(key)}';
    final openGeneration =
        ChatViewportCollection.instance.openGenerationFor(key);
    if (openGeneration <= 0) {
      // Press-warm / no page attached yet. A reset operation is page-bound
      // (it lives until the page is gone); the real open goes through
      // prepareOpenViewport, which attaches first and then starts it.
      ChatOpenPerfLog.mark(
        'chat_open_latest_window_reset_wait_attach',
        conversationID: key,
        trace: logTrace,
      );
      return false;
    }
    ChatOpenPerfLog.mark(
      'chat_open_latest_window_reset_begin',
      conversationID: key,
      extras: <String, Object?>{
        'epoch': epoch,
        'openGeneration': openGeneration,
        'rawCount': globalModel.rawMessageCount(key),
      },
      trace: logTrace,
    );
    final task = ChatOpenPerfLog.withTrace(logTrace, () => globalModel.ensureOpenHydrate(
      key,
      requestSignature: signature,
      canPublish: () =>
          SessionIdentityService.instance.capture() == identity &&
          ChatViewportCollection.instance.openGenerationFor(key) ==
              openGeneration &&
          !ChatViewportCollection.instance.isOpenGenerationAbandoned(
            key,
            openGeneration,
          ) &&
          globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle,
      load: () async {
        final outcome = await ChatLatestWindowResetService.instance.runForOpen(
          conversation: conversation,
          globalModel: globalModel,
          openGeneration: openGeneration,
          windowAlreadyCleared: windowAlreadyCleared,
        );
        return outcome == LatestWindowResetOutcome.trusted ||
            outcome == LatestWindowResetOutcome.installedProvisional ||
            outcome == LatestWindowResetOutcome.offlineProvisional;
      },
    ));
    try {
      return (await task.timeout(timeout)).shouldSuppressOrdinaryLoad;
    } on TimeoutException {
      ChatOpenPerfLog.mark(
        'latest_window_reset_wait_timeout',
        conversationID: key,
        extras: <String, Object?>{'timeoutMs': timeout.inMilliseconds},
        trace: logTrace,
      );
      return false;
    }
  }

  String _conversationKey(V2TimConversation conversation) {
    return ConversationPreviewHistorySync.conversationMessageCacheKey(
          conversation,
        ) ??
        conversation.conversationID.trim();
  }

  /// 捕获当前本地快照。调用方应 fire-and-forget，返回快照仅用于观测/测试，
  /// 可能 `!isViewportReady`。
  ///
  /// [timeout] 仅保留为兼容的观测参数；不会等待 SDK、云端或完整历史窗口。
  Future<ChatEntrySnapshot> prepareForOpen({
    required V2TimConversation conversation,
    Duration timeout = prepareTimeout,
  }) async {
    final requestId = ++_requestId;
    final cacheKey = ConversationPreviewHistorySync.conversationMessageCacheKey(
          conversation,
        ) ??
        conversation.conversationID.trim();
    final conversationID = conversation.conversationID.trim();
    _activeKey = cacheKey;
    _phase = ChatOpenViewportPhase.preparing;
    // Start local hydration before the route is pushed. The caller can await
    // ensureLocalSnapshotForOpen for a short bounded handoff; this method
    // itself remains non-blocking for existing callers.
    unawaited(ensureLocalSnapshotForOpen(
      conversation: conversation,
      logTrace: ChatOpenPerfLog.captureCurrent(conversationKey: cacheKey),
    ));
    ChatOpenPerfLog.mark(
      'viewport_preparing',
      conversationID: cacheKey,
      extras: <String, Object?>{
        'requestId': requestId,
        'timeoutMs': timeout.inMilliseconds,
      },
    );

    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final snap = ChatEntrySnapshot.capture(
      globalModel: globalModel,
      conversationKey: cacheKey,
      conversationID: conversationID,
      requestId: requestId,
      tip: conversation.lastMessage,
    );

    if (!isCurrent(requestId, cacheKey)) {
      _phase = ChatOpenViewportPhase.cancelled;
      ChatOpenPerfLog.mark(
        'viewport_prepare_stale',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'currentRequestId': _requestId,
        },
      );
      return snap;
    }

    // Prepare 可能在 route 已 transitioning/visible 后完成。不能把状态倒退
    // 回 prepared/viewportReady，否则后续生命周期判断会误以为页面尚未出现。
    final alreadyTransitioning =
        _phase == ChatOpenViewportPhase.transitioning ||
            _phase == ChatOpenViewportPhase.visible;
    if (!alreadyTransitioning) {
      _phase = ChatOpenViewportPhase.prepared;
    }
    final ready = snap.isViewportReady;
    if (ready) {
      if (!alreadyTransitioning) {
        _phase = ChatOpenViewportPhase.viewportReady;
      }
      ChatOpenPerfLog.mark(
        alreadyTransitioning ? 'viewport_ready_background' : 'viewport_ready',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'rawCount': snap.messageCount,
          'completeWindow': snap.completeOpenWindow,
          'emptyConfirmed': snap.emptyConfirmed,
        },
      );
    } else {
      ChatOpenPerfLog.mark(
        'viewport_ready_miss',
        conversationID: cacheKey,
        extras: <String, Object?>{
          'requestId': requestId,
          'rawCount': snap.messageCount,
          'initialLoaded': snap.initialHistoryLoaded,
          'mayHaveOlder': snap.mayHaveOlderHistory,
        },
      );
    }
    return snap;
  }

  /// 导航前准备当前可展示窗口。返回连续视口描述，而不是条数。
  Future<ChatOpenViewportResult> prepareOpenViewport({
    required V2TimConversation conversation,
    double viewportHeight = ChatViewportReadiness.defaultViewportHeight,
    Duration timeout = localBudget,
    Duration cloudGrace = cloudGraceBudget,
    String source = 'unknown',
  }) async {
    final key = _conversationKey(conversation);
    if (key.isEmpty) {
      return ChatViewportReadiness.classify(
        conversationKey: '',
        newestFirst: const <V2TimMessage>[],
        useSeqContiguity: false,
        viewportHeight: viewportHeight,
        source: ChatViewportSource.memory,
      );
    }
    final requestId = ++_requestId;
    _activeKey = key;
    _phase = ChatOpenViewportPhase.preparing;
    final identity = SessionIdentityService.instance.capture();
    final collection = ChatViewportCollection.instance;
    collection.attach(
      conversationKey: key,
      identity: identity,
      attachSource: 'prepare',
    );
    recordPrepareStart(requestId: requestId, source: source);
    final prepareTrace = ChatOpenPerfLog.captureCurrent(
      requestId: requestId,
      conversationKey: key,
    );
    final isGroup = conversation.type == 2 ||
        (conversation.groupID?.trim().isNotEmpty ?? false);
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    Map<String, Object?> prepareExtras([
      Map<String, Object?> more = const <String, Object?>{},
    ]) {
      final snap = snapshotFor(requestId);
      return <String, Object?>{
        'requestId': requestId,
        'prepareId': requestId,
        'source': source,
        'openGeneration': collection.openGeneration,
        'sessionGeneration': identity.generation,
        'owned': snap?.owned ?? false,
        'joined': snap?.joined ?? false,
        'dbRead': snap?.dbRead ?? false,
        'sdkRead': snap?.sdkRead ?? false,
        'committed': snap?.committed ?? false,
        ...more,
      };
    }

    ChatOpenPerfLog.mark(
      'viewport_prepare_start',
      conversationID: key,
      extras: prepareExtras(),
      trace: prepareTrace,
    );

    ChatOpenViewportResult project(ChatViewportSource viewportSource) {
      return collection.project(
        conversationKey: key,
        newestFirst: List<V2TimMessage>.from(
          globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
        ),
        useSeqContiguity: isGroup,
        viewportHeight: viewportHeight,
        source: viewportSource,
        coverage: globalModel.messageHistoryCoverageFor(key),
      );
    }

    void logFirstViewport(ChatOpenViewportResult result) {
      ChatOpenPerfLog.mark(
        'chat_open_first_viewport_extent',
        conversationID: key,
        extras: <String, Object?>{
          'extent': result.estimatedContentExtent,
          'target': result.viewportTargetExtent,
          'ready': result.isViewportReady,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'chat_open_first_viewport_message_count',
        conversationID: key,
        extras: <String, Object?>{
          'continuousCount': result.continuousCount,
          'rawCount': globalModel.rawMessageCount(key),
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'chat_open_first_frame_source',
        conversationID: key,
        extras: <String, Object?>{
          'source': result.source.name,
          'coverage': result.coverageState.name,
          'needsLatestRepair': result.needsLatestRepair,
        },
        trace: prepareTrace,
      );
    }

    void logPrepareEnd(ChatOpenViewportResult result, {required String work}) {
      ChatOpenPerfLog.mark(
        'viewport_prepare_end',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ready': result.isViewportReady,
          'coverage': result.coverageState.name,
          'isCurrent': isCurrent(requestId, key),
          'work': work,
        }),
        trace: prepareTrace,
      );
    }

    bool previewAhead() => ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
      preview: conversation.lastMessage,
      cached: globalModel.rawMessageList(key) ?? const <V2TimMessage>[],
    );

    if (ChatLatestWindowResetService.instance.needsLatestWindowReset(key) &&
        globalModel.getSearchJumpStatus(key) == SearchJumpStatus.idle) {
      // Reconnect-epoch changed: the cache and the in-memory window are not
      // allowed to be the visible first frame. Wipe synchronously so the
      // locked initial snapshot is empty, then let the reset own hydration.
      // The ordinary H0 repair must not compete with the reset request.
      OpenViewportCache.instance.invalidate(key);
      // Single wipe owner: this prepare clears the window once, and tells the
      // reset operation so it never clears again (a second removeMessageList
      // would bump clearEpoch / writer state under the running request). If an
      // operation is already in flight for this key, it owns the window.
      final resetInFlight =
          ChatLatestWindowResetService.instance.isResetInFlight(key);
      if (!resetInFlight &&
          (globalModel.rawMessageCount(key) > 0 ||
              globalModel.hasInitialHistoryLoaded(key))) {
        globalModel.removeMessageList(key);
      }
      unawaited(ensureLocalSnapshotForOpen(
        conversation: conversation,
        timeout: timeout,
        logTrace: prepareTrace,
        windowAlreadyCleared: !resetInFlight,
      ));
      final result = project(ChatViewportSource.memory);
      collection.lockInitial(result);
      collection.markRepair(ChatViewportRepairKind.openViewport);
      if (_phase != ChatOpenViewportPhase.transitioning &&
          _phase != ChatOpenViewportPhase.visible) {
        _phase = ChatOpenViewportPhase.prepared;
      }
      ChatOpenPerfLog.mark(
        'viewport_prepare_latest_window_reset',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'epoch': ImConnectStatusService.recoveryEpoch,
        }),
        trace: prepareTrace,
      );
      logFirstViewport(result);
      logPrepareEnd(result, work: 'latest_window_reset');
      return result;
    }

    final cached = OpenViewportCache.instance.peek(key);
    if (cached != null && cached.isViewportReady && !previewAhead()) {
      ChatOpenPerfLog.mark(
        'chat_open_cache_hit',
        conversationID: key,
        extras: <String, Object?>{
          'requestId': requestId,
          'continuousCount': cached.continuousCount,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'viewport_prepare_cache_hit',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'continuousCount': cached.continuousCount,
        }),
        trace: prepareTrace,
      );
      final fromMemory = project(ChatViewportSource.cache);
      if (fromMemory.isViewportReady) {
        collection.lockInitial(fromMemory);
        _phase = ChatOpenViewportPhase.viewportReady;
        logFirstViewport(fromMemory);
        logPrepareEnd(fromMemory, work: 'cache_hit');
        return fromMemory;
      }
    }

    final localStartedAt = DateTime.now();
    var result = project(ChatViewportSource.memory);
    var localWork = 'memory_hit';
    if (!result.isViewportReady || previewAhead()) {
      ChatOpenPerfLog.mark(
        'viewport_prepare_local_begin',
        conversationID: key,
        extras: prepareExtras(),
        trace: prepareTrace,
      );
      await ensureLocalSnapshotForOpen(
        conversation: conversation,
        timeout: timeout,
        logTrace: prepareTrace,
      );
      result = project(ChatViewportSource.local);
      final snap = snapshotFor(requestId);
      localWork = (snap?.joined ?? false)
          ? 'join'
          : ((snap?.owned ?? false) || (snap?.dbRead ?? false) ? 'real' : 'join');
      ChatOpenPerfLog.mark(
        'viewport_prepare_local_end',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ready': result.isViewportReady,
          'work': localWork,
        }),
        trace: prepareTrace,
      );
    }
    ChatOpenPerfLog.mark(
      'chat_open_local_ready_us',
      conversationID: key,
      extras: <String, Object?>{
        'durationUs':
            DateTime.now().difference(localStartedAt).inMicroseconds,
        'ready': result.isViewportReady,
        'coverage': result.coverageState.name,
      },
      trace: prepareTrace,
    );
    collection.lockInitial(result);
    if (result.isViewportReady && !previewAhead()) {
      _phase = ChatOpenViewportPhase.viewportReady;
      OpenViewportCache.instance.put(key, result);
      logFirstViewport(result);
      logPrepareEnd(result, work: localWork);
      return result;
    }

    if (result.needsLatestRepair || previewAhead()) {
      final ticket = ChatViewportRepairTicket(
        ownerUserId: identity.ownerUserId,
        accountGeneration: identity.generation,
        conversationKey: key,
        openGeneration: collection.openGeneration,
        requestAnchorMsgId: result.anchor?.msgID,
        requestAnchorSeq: result.anchor?.seq,
      );
      ChatOpenPerfLog.mark(
        'chat_open_h0_started',
        conversationID: key,
        extras: <String, Object?>{
          'coverage': result.coverageState.name,
          'continuousCount': result.continuousCount,
          'openGeneration': ticket.openGeneration,
          'graceMs': cloudGrace.inMilliseconds,
          'awaitGrace': false,
        },
        trace: prepareTrace,
      );
      ChatOpenPerfLog.mark(
        'viewport_prepare_h0_begin',
        conversationID: key,
        extras: prepareExtras(<String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'graceMs': cloudGrace.inMilliseconds,
        }),
        trace: prepareTrace,
      );
      collection.markRepair(ChatViewportRepairKind.openViewport);
      // H0 是并行机会：启动 single-flight，但不把 grace 做成 push 的必经 await。
      unawaited(
        ConversationHistorySyncCoordinator.instance.repairOpenViewport(
          conversation: conversation,
          ticket: ticket,
          logTrace: prepareTrace,
        ),
      );
    }

    if (result.isViewportReady) {
      _phase = ChatOpenViewportPhase.viewportReady;
    } else if (_phase != ChatOpenViewportPhase.transitioning &&
        _phase != ChatOpenViewportPhase.visible) {
      _phase = ChatOpenViewportPhase.prepared;
    }
    OpenViewportCache.instance.put(key, result);
    logFirstViewport(result);
    logPrepareEnd(result, work: localWork);
    return result;
  }
}

