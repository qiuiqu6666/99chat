import 'dart:async';

import 'package:flutter/foundation.dart';

/// 发布版可见：进入聊天页耗时追踪。过滤关键字：`[ChatOpenPerf]`
///
/// 用法：Xcode / `flutter logs` / Android logcat 搜 `ChatOpenPerf`。
/// 每条含 `elapsedMs`（距点击）与 `deltaMs`（距上一里程碑），以及 `region` 中文阶段名。
/// Debug 和 Profile 默认输出，Release 永不输出。
class ChatOpenPerfLog {
  ChatOpenPerfLog._();

  /// Debug 构建仍采集账本，便于测试与必要时重开控制台。
  static const bool enabled = kDebugMode;

  /// Profile 构建关闭控制台；需要真机采样时再改回 true。
  static const bool enabledInProfile = false;

  /// 高频控制台输出开关。关闭后仍写 debugSink / 计数器。
  static const bool consoleOutputEnabled = false;

  static bool get isEnabled =>
      !kReleaseMode && (enabled || (kProfileMode && enabledInProfile));

  /// Tests can capture the exact line without scraping stdout.
  @visibleForTesting
  static void Function(String line)? debugSink;

  @visibleForTesting
  static Duration settleSummaryDelay = const Duration(milliseconds: 2000);

  static const int _maxLedgers = 16;
  static final List<_ChatOpenTraceLedger> _ledgers = <_ChatOpenTraceLedger>[];
  static final _ChatOpenTraceLedger _detached = _ChatOpenTraceLedger(
    sessionId: '-',
    convId: '',
    t0Ms: 0,
  );
  static _ChatOpenTraceLedger? _current;

  static int? _hydrateOwnerRequestId;
  static int lastPrepareRequestId = 0;
  static final List<ChatOpenPrepareWorkSnapshot> _prepareSnaps =
      <ChatOpenPrepareWorkSnapshot>[];

  static int get prepareCount => _current?.prepareCount ?? 0;
  static int get actualHydrateCount => _current?.actualHydrateCount ?? 0;
  static int get hydrateJoinCount => _current?.hydrateJoinCount ?? 0;
  static int get hydrateReuseCount => _current?.hydrateReuseCount ?? 0;
  static int get hydrateStartedCount => _current?.hydrateStartedCount ?? 0;
  static int get hydrateCommitCount => _current?.hydrateCommitCount ?? 0;
  static int get hydrateAbortedCount => _current?.hydrateAbortedCount ?? 0;
  static int get ignoredPrepareCount => _current?.ignoredPrepareCount ?? 0;
  static int get ignoredAfterDbRead => _current?.ignoredAfterDbRead ?? 0;
  static int get ignoredAfterSdkRead => _current?.ignoredAfterSdkRead ?? 0;
  static int get ignoredAfterCommit => _current?.ignoredAfterCommit ?? 0;
  static int get attachCount => _current?.attachCount ?? 0;
  static int get attachBumpCount => _current?.attachBumpCount ?? 0;
  static int get attachSkipCount => _current?.attachSkipCount ?? 0;
  static int get generationRejectCount => _current?.generationRejectCount ?? 0;
  static int get appBootstrapProducerCount =>
      _current?.appBootstrapProducerCount ?? 0;
  static int get reloadIfEmptyCount => _current?.reloadIfEmptyCount ?? 0;
  static int get uikitProducerCount => _current?.uikitProducerCount ?? 0;
  static String get lastIgnoredReason => _current?.lastIgnoredReason ?? '';
  static String get lastRejectReason => _current?.lastRejectReason ?? '';

  static const Set<String> _plaintextKeys = <String>{
    'session',
    'chatopentraceid',
    'requestid',
    'prepareid',
    'opengeneration',
    'ticketgeneration',
    'currentopengeneration',
    'sessiongeneration',
    'accountgeneration',
    'source',
    'reason',
    'outcome',
    'kind',
    'producer',
    'joined',
    'owned',
    'ignoredreason',
    'stalereason',
    'ticketaccepted',
    'ticketrejectedreason',
    'hydratekind',
    'work',
    'dbread',
    'sdkread',
    'committed',
    'hasinflight',
    'waitms',
    'timeoutms',
    'gracems',
    'durationus',
    'durationms',
    'preparecount',
    'actualhydratecount',
    'hydratejoincount',
    'hydratereusecount',
    'hydratestartedcount',
    'hydratecommitcount',
    'hydrateabortedcount',
    'ignoredpreparecount',
    'ignoredafterdbread',
    'ignoredaftersdkread',
    'ignoredaftercommit',
    'attachcount',
    'attachbumpcount',
    'attachskipcount',
    'generationrejectcount',
    'appbootstrapproducercount',
    'reloadifemptycount',
    'uikitproducercount',
    'tabindex',
    'tabname',
    'convtype',
    'scope',
    'caller',
    'action',
    'result',
    'beforefirstframe',
    'localonly',
    'rawcount',
    'localcount',
    'cachedraw',
    'initialloaded',
    'ready',
    'coverage',
    'phase',
    'iscurrent',
    'sameconversationcache',
    'uiattached',
    'previousgeneration',
    'attachsource',
    'gracehit',
    'historyposition',
    'note',
    'region',
    'elapsedms',
    'deltams',
    'prev',
    'totalms',
    'type',
    'entryunread',
    'completewindow',
    'emptyconfirmed',
    'mayhaveolder',
    'continuouscount',
    'extent',
    'target',
    'needslatestrepair',
    'bootstrapping',
    'messagecount',
    'waitedms',
    'applied',
    'coldstart',
    'iscurrenttab',
  };

  static String get sessionId => _current?.sessionId ?? '';

  static String get chatOpenTraceId {
    final id = _current?.sessionId ?? '';
    return id.isEmpty ? '-' : id;
  }

  static ChatOpenTraceContext captureCurrent({
    int? requestId,
    String? conversationKey,
  }) {
    final current = _current;
    if (current == null) {
      return ChatOpenTraceContext(
        session: '-',
        chatOpenTraceId: '-',
        requestId: requestId ?? lastPrepareRequestId,
        conversationKey: (conversationKey ?? '').trim(),
        t0Ms: 0,
      );
    }
    return ChatOpenTraceContext(
      session: current.sessionId,
      chatOpenTraceId: current.sessionId,
      requestId: requestId ?? lastPrepareRequestId,
      conversationKey: (conversationKey ?? current.convId).trim(),
      t0Ms: current.t0Ms,
    );
  }

  /// 点会话 / 即将打开聊天时调用，开启一轮会话时钟。
  static void beginOpen({
    required String conversationID,
    required String phase,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    if (!isEnabled) {
      return;
    }
    final id = conversationID.trim();
    final t0Ms = DateTime.now().millisecondsSinceEpoch;
    final sessionId = 'open_${t0Ms.toRadixString(36)}_${_hashId(id)}';
    final ledger = _ChatOpenTraceLedger(
      sessionId: sessionId,
      convId: id,
      t0Ms: t0Ms,
    );
    _ledgers.add(ledger);
    _pruneLedgers(keep: ledger);
    _current = ledger;
    _scheduleSettleSummary(ledger);
    _print(
      'session_begin',
      conversationID: id,
      extras: <String, Object?>{
        'phase': phase,
        'session': sessionId,
        'chatOpenTraceId': sessionId,
        'region': regionOf('session_begin'),
        'elapsedMs': 0,
        'deltaMs': 0,
        ...extras,
      },
    );
  }

  /// 相对 [beginOpen] 的里程碑（含 elapsedMs + deltaMs）。
  static void mark(
    String event, {
    String? conversationID,
    Map<String, Object?> extras = const <String, Object?>{},
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ??
        captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    _tally(ledger, event, extras);
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = ctx.t0Ms > 0 ? now - ctx.t0Ms : -1;
    final delta = ledger.lastMarkMs > 0 ? now - ledger.lastMarkMs : -1;
    final prev = ledger.lastEvent.isEmpty ? '-' : ledger.lastEvent;
    _print(
      event,
      conversationID: conversationID ?? ctx.conversationKey,
      extras: <String, Object?>{
        'session': ctx.session.isEmpty ? '-' : ctx.session,
        'chatOpenTraceId':
            ctx.chatOpenTraceId.isEmpty ? '-' : ctx.chatOpenTraceId,
        'region': regionOf(event),
        'elapsedMs': elapsed,
        'deltaMs': delta,
        'prev': prev,
        ...extras,
      },
    );
    ledger.lastMarkMs = now;
    ledger.lastEvent = event;
  }

  /// 历史列表 Widget 首次 build（可能仍空壳）。每 session 一次。
  static void markHistoryListBuilt({
    required String conversationID,
    required int messageCount,
    required bool initialLoaded,
    bool bootstrapping = false,
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    if (ledger.historyListBuiltLogged) {
      return;
    }
    ledger.historyListBuiltLogged = true;
    mark(
      'history_list_first_build',
      conversationID: conversationID,
      extras: <String, Object?>{
        'messageCount': messageCount,
        'initialLoaded': initialLoaded,
        'bootstrapping': bootstrapping,
      },
      trace: ctx,
    );
  }

  /// 消息列表首次非空并完成一帧绘制。每 session 一次 —— 这是「消息出现」主指标。
  static void markMessagesFirstVisible({
    required String conversationID,
    required int messageCount,
    String source = 'list',
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent(conversationKey: conversationID);
    final ledger = _ledgerFor(ctx);
    if (ledger.firstMessagesVisibleLogged) {
      return;
    }
    if (messageCount <= 0) {
      return;
    }
    ledger.firstMessagesVisibleLogged = true;
    mark(
      'messages_first_visible',
      conversationID: conversationID,
      extras: <String, Object?>{
        'messageCount': messageCount,
        'source': source,
        'note': '首屏消息对用户可见（post-frame）',
      },
      trace: ctx,
    );
    _printSummary(ledger, ctx);
    emitOpenTraceSummary(phase: 'first_visible', trace: ctx);
  }

  static void emitOpenTraceSummary({
    required String phase,
    ChatOpenTraceContext? trace,
  }) {
    if (!isEnabled) {
      return;
    }
    final ctx = trace ?? captureCurrent();
    final ledger = _findLedger(ctx.chatOpenTraceId);
    if (ledger == null || ledger.t0Ms <= 0) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _print(
      'open_trace_summary',
      conversationID: ctx.conversationKey.isEmpty
          ? ledger.convId
          : ctx.conversationKey,
      extras: <String, Object?>{
        'session': ledger.sessionId,
        'chatOpenTraceId': ledger.sessionId,
        'region': regionOf('open_trace_summary'),
        'phase': phase,
        'elapsedMs': now - ledger.t0Ms,
        'prepareCount': ledger.prepareCount,
        'actualHydrateCount': ledger.actualHydrateCount,
        'hydrateJoinCount': ledger.hydrateJoinCount,
        'hydrateReuseCount': ledger.hydrateReuseCount,
        'hydrateStartedCount': ledger.hydrateStartedCount,
        'hydrateCommitCount': ledger.hydrateCommitCount,
        'hydrateAbortedCount': ledger.hydrateAbortedCount,
        'ignoredPrepareCount': ledger.ignoredPrepareCount,
        'ignoredAfterDbRead': ledger.ignoredAfterDbRead,
        'ignoredAfterSdkRead': ledger.ignoredAfterSdkRead,
        'ignoredAfterCommit': ledger.ignoredAfterCommit,
        'attachCount': ledger.attachCount,
        'attachBumpCount': ledger.attachBumpCount,
        'attachSkipCount': ledger.attachSkipCount,
        'generationRejectCount': ledger.generationRejectCount,
        'appBootstrapProducerCount': ledger.appBootstrapProducerCount,
        'reloadIfEmptyCount': ledger.reloadIfEmptyCount,
        'uikitProducerCount': ledger.uikitProducerCount,
        'lastIgnoredReason': ledger.lastIgnoredReason,
        'lastRejectReason': ledger.lastRejectReason,
        'note': phase == 'settle_2s'
            ? '2s 观察窗，不是打开完成态'
            : '打开链路计数快照',
      },
    );
  }

  static void _printSummary(
    _ChatOpenTraceLedger ledger,
    ChatOpenTraceContext ctx,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _print(
      'open_summary',
      conversationID: ctx.conversationKey.isEmpty
          ? ledger.convId
          : ctx.conversationKey,
      extras: <String, Object?>{
        'session': ledger.sessionId,
        'chatOpenTraceId': ledger.sessionId,
        'region': regionOf('open_summary'),
        'totalMs': now - ledger.t0Ms,
        'lastEvent': ledger.lastEvent.isEmpty ? '-' : ledger.lastEvent,
        'note': '从点击会话到消息首次可见',
      },
    );
  }

  static void _scheduleSettleSummary(_ChatOpenTraceLedger ledger) {
    ledger.settleTimer?.cancel();
    ledger.settleTimer = Timer(settleSummaryDelay, () {
      ledger.settleTimer = null;
      emitOpenTraceSummary(phase: 'settle_2s', trace: ledger.toContext());
    });
  }

  static ChatOpenPrepareWorkSnapshot recordPrepareStart({
    required int requestId,
    required String source,
  }) {
    lastPrepareRequestId = requestId;
    final snap = ChatOpenPrepareWorkSnapshot(
      requestId: requestId,
      source: source,
      trace: captureCurrent(requestId: requestId),
    );
    _prepareSnaps.add(snap);
    while (_prepareSnaps.length > 8) {
      _prepareSnaps.removeAt(0);
    }
    return snap;
  }

  static ChatOpenPrepareWorkSnapshot? snapshotFor(int requestId) {
    for (var i = _prepareSnaps.length - 1; i >= 0; i--) {
      if (_prepareSnaps[i].requestId == requestId) {
        return _prepareSnaps[i];
      }
    }
    return null;
  }

  static int _ownedRequestId(ChatOpenTraceContext? trace, int? fallback) {
    if (trace != null && trace.requestId != 0) {
      return trace.requestId;
    }
    return fallback ?? 0;
  }

  static void markHydrateOwner(int requestId, {ChatOpenTraceContext? trace}) {
    final id = _ownedRequestId(trace, requestId);
    _hydrateOwnerRequestId = id;
    snapshotFor(id)?.owned = true;
  }

  static void markHydrateJoined(int requestId, {ChatOpenTraceContext? trace}) {
    final id = _ownedRequestId(trace, requestId);
    snapshotFor(id)?.joined = true;
  }

  static void markOwnedDbRead({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.dbRead = true;
  }

  static void markOwnedSdkRead({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.sdkRead = true;
  }

  static void markOwnedCommit({ChatOpenTraceContext? trace}) {
    final owner = _ownedRequestId(trace, _hydrateOwnerRequestId);
    if (owner == 0) return;
    final snap = snapshotFor(owner);
    if (snap == null) return;
    snap.owned = true;
    snap.committed = true;
  }

  static int? get hydrateOwnerRequestId => _hydrateOwnerRequestId;

  static void _tally(
    _ChatOpenTraceLedger ledger,
    String event,
    Map<String, Object?> extras,
  ) {
    switch (event) {
      case 'viewport_prepare_start':
        ledger.prepareCount += 1;
        break;
      case 'app_hydrate_registered':
        ledger.actualHydrateCount += 1;
        break;
      case 'app_hydrate_join':
        ledger.hydrateJoinCount += 1;
        break;
      case 'app_hydrate_reuse':
        ledger.hydrateReuseCount += 1;
        break;
      case 'app_hydrate_started':
        ledger.hydrateStartedCount += 1;
        break;
      case 'app_hydrate_commit':
        ledger.hydrateCommitCount += 1;
        break;
      case 'app_hydrate_aborted':
        ledger.hydrateAbortedCount += 1;
        break;
      case 'viewport_prepare_ignored':
        ledger.ignoredPrepareCount += 1;
        ledger.lastIgnoredReason = '${extras['ignoredReason'] ?? ''}';
        final owned = extras['owned'] == true;
        if (owned && extras['dbRead'] == true) {
          ledger.ignoredAfterDbRead += 1;
        }
        if (owned && extras['sdkRead'] == true) {
          ledger.ignoredAfterSdkRead += 1;
        }
        if (owned && extras['committed'] == true) {
          ledger.ignoredAfterCommit += 1;
        }
        break;
      case 'viewport_attach_skip':
        ledger.attachCount += 1;
        ledger.attachSkipCount += 1;
        break;
      case 'viewport_attach_bump':
        ledger.attachCount += 1;
        ledger.attachBumpCount += 1;
        break;
      case 'viewport_ticket_rejected':
        ledger.generationRejectCount += 1;
        ledger.lastRejectReason = '${extras['ticketRejectedReason'] ?? ''}';
        break;
      case 'app_bootstrap_commit':
        ledger.appBootstrapProducerCount += 1;
        break;
      case 'chat_reload_if_empty_load':
        ledger.reloadIfEmptyCount += 1;
        break;
      case 'uikit_loadChatRecord_local_started':
        ledger.uikitProducerCount += 1;
        break;
    }
  }

  static _ChatOpenTraceLedger? _findLedger(String chatOpenTraceId) {
    final id = chatOpenTraceId.trim();
    if (id.isEmpty || id == '-') {
      return null;
    }
    for (final ledger in _ledgers) {
      if (ledger.sessionId == id) {
        return ledger;
      }
    }
    return null;
  }

  static _ChatOpenTraceLedger _ledgerFor(ChatOpenTraceContext ctx) {
    final id = ctx.chatOpenTraceId.trim();
    if (id.isEmpty || id == '-') {
      return _detached;
    }
    final existing = _findLedger(id);
    if (existing != null) {
      return existing;
    }
    final rebuilt = _ChatOpenTraceLedger(
      sessionId: id,
      convId: ctx.conversationKey,
      t0Ms: ctx.t0Ms,
    );
    _ledgers.add(rebuilt);
    _pruneLedgers(keep: rebuilt);
    return rebuilt;
  }

  static void _pruneLedgers({_ChatOpenTraceLedger? keep}) {
    while (_ledgers.length > _maxLedgers) {
      var dropIndex = 0;
      if (identical(_ledgers[dropIndex], _current) ||
          identical(_ledgers[dropIndex], keep)) {
        dropIndex = 1;
      }
      if (dropIndex >= _ledgers.length) {
        break;
      }
      _ledgers.removeAt(dropIndex).settleTimer?.cancel();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    for (final ledger in _ledgers) {
      ledger.settleTimer?.cancel();
    }
    _ledgers.clear();
    _detached.settleTimer?.cancel();
    _detached.lastMarkMs = 0;
    _detached.lastEvent = '';
    _current = null;
    _hydrateOwnerRequestId = null;
    lastPrepareRequestId = 0;
    _prepareSnaps.clear();
    settleSummaryDelay = const Duration(milliseconds: 2000);
  }

  /// 阶段中文名，方便在 logcat 里扫。
  static String regionOf(String event) {
    switch (event) {
      case 'session_begin':
        return '①点击会话';
      case 'bootstrap_before_await':
        return '②进页前bootstrap开始';
      case 'bootstrap_peek_start':
        return '②peek拉历史开始';
      case 'bootstrap_peek_done':
        return '②peek拉历史结束';
      case 'bootstrap_url_resolve_done':
        return '②图片URL补全';
      case 'bootstrap_warm_skip':
        return '②暖窗已就绪跳过重灌';
      case 'bootstrap_after_await':
        return '②进页前bootstrap结束';
      case 'cold_bootstrap_timeout_before_push':
        return '②冷开push前bootstrap超时';
      case 'page_bootstrap_warm_skip':
        return '②页内bootstrap暖跳过';
      case 'navigator_push_begin':
        return '③开始push路由';
      case 'navigator_pop_back':
        return '③从聊天返回';
      case 'embedded_chat_switch':
        return '③嵌入态切换会话';
      case 'chat_init_state':
        return '④Chat页initState';
      case 'chat_first_frame':
        return '④Chat页首帧';
      case 'history_gate_warm_shell':
        return '⑤历史gate暖壳';
      case 'history_gate_cold_shell':
        return '⑤历史gate冷壳';
      case 'history_gate_thin_window':
        return '⑤历史gate薄窗';
      case 'history_gate_timeout_1_2s':
        return '⑤历史gate冷开超时1.2s';
      case 'history_gate_thin_timeout_1_2s':
        return '⑤历史gate薄窗超时1.2s';
      case 'history_gate_tips_merge_timeout':
        return '⑤历史gate tip合并超时';
      case 'history_gate_content_ready_skip':
        return '⑤有内容跳过整页gate';
      case 'prepare_gate_after_inflight_wait':
        return '⑤等待inflight结束';
      case 'prepare_gate_complete':
        return '⑤prepareGate完成';
      case 'history_list_first_build':
        return '⑥消息列表首次build';
      case 'opening_placeholder_first_paint':
        return '⑥冷开气泡占位首帧';
      case 'opening_placeholder_removed':
        return '⑦冷开气泡占位移除';
      case 'messages_first_visible':
        return '⑦消息首次可见';
      case 'open_summary':
        return '⑧打开汇总';
      case 'open_trace_summary':
        return '⑧打开链路计数';
      case 'group_member_open_shell':
        return '群成员开页壳';
      case 'group_member_full_load_start':
        return '群成员全量开始';
      case 'avatar_warm_done':
        return '头像预热完成';
      case 'mute_network_fetch_start':
        return '禁言网络拉取开始';
      case 'viewport_prepare_start':
        return '②prepare开始';
      case 'viewport_prepare_cache_hit':
        return '②prepare缓存命中';
      case 'viewport_prepare_local_begin':
        return '②prepare本地开始';
      case 'viewport_prepare_local_end':
        return '②prepare本地结束';
      case 'viewport_prepare_h0_begin':
        return '②prepare H0开始';
      case 'viewport_prepare_h0_commit':
        return '②prepare H0结果';
      case 'viewport_prepare_end':
        return '②prepare结束';
      case 'viewport_prepare_ignored':
        return '②prepare被作废';
      case 'viewport_attach_skip':
        return '④viewport attach跳过';
      case 'viewport_attach_bump':
        return '④viewport attach bump';
      case 'viewport_ticket_accepted':
        return '②H0 ticket接受';
      case 'viewport_ticket_rejected':
        return '②H0 ticket拒收';
      case 'app_hydrate_join':
        return '②hydrate join';
      case 'app_hydrate_reuse':
        return '②hydrate reuse';
      case 'app_hydrate_registered':
        return '②hydrate 注册';
      case 'app_hydrate_started':
        return '②hydrate 开始load';
      case 'app_hydrate_commit':
        return '②hydrate commit';
      case 'app_hydrate_aborted':
        return '②hydrate aborted';
      case 'peek_apply_join':
        return '②peek join';
      case 'peek_apply_local_join':
        return '②peek 本地join';
      case 'peek_apply_local_real':
        return '②peek 本地实读';
      case 'peek_apply_sdk_real':
        return '②peek SDK实读';
      case 'app_bootstrap_commit':
        return '②app写窗';
      case 'uikit_initForEachConversation':
        return '④UIKit init会话';
      case 'uikit_loadData_started':
        return '④UIKit _loadData';
      case 'uikit_hydrate_wait_result':
        return '④UIKit 等hydrate';
      case 'uikit_hydrate_deferred':
        return '④UIKit hydrate延期';
      case 'uikit_loadChatRecord_local_started':
        return '④UIKit LOCAL load';
      case 'uikit_loadChatRecord_local_done':
        return '④UIKit LOCAL 完成';
      case 'uikit_removeMessageList':
        return '④UIKit 清暖窗';
      case 'chat_reload_if_empty_load':
        return '⑤空窗补拉';
      default:
        if (event.startsWith('c2c_')) {
          return '⑤单聊历史/$event';
        }
        if (event.startsWith('bootstrap_')) {
          return '②bootstrap/$event';
        }
        if (event.startsWith('prepare_') || event.startsWith('history_')) {
          return '⑤历史/$event';
        }
        if (event.startsWith('chat_')) {
          return '④Chat/$event';
        }
        if (event.startsWith('viewport_') || event.startsWith('app_hydrate_')) {
          return '②viewport/$event';
        }
        if (event.startsWith('uikit_')) {
          return '④UIKit/$event';
        }
        return event;
    }
  }

  static void _print(
    String event, {
    String? conversationID,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    final buffer = StringBuffer('[ChatOpenPerf] event=$event');
    final id = (conversationID ?? '').trim();
    if (id.isNotEmpty) {
      buffer.write(' convHash=${_hashId(id)}');
    }
    for (final entry in extras.entries) {
      final value = _formatExtra(entry.key, entry.value);
      if (value == null) {
        continue;
      }
      buffer.write(' ${entry.key}=$value');
    }
    final line = buffer.toString();
    final sink = debugSink;
    if (sink != null) {
      sink(line);
    }
    if (consoleOutputEnabled && isEnabled) {
      // ignore: avoid_print
      print(line);
    }
  }

  static String _hashId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }
    // Stable, short process-independent fingerprint; raw IDs never enter logs.
    var hash = 0x811c9dc5;
    for (final codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String? _formatExtra(String key, Object? value) {
    if (value == null) {
      return null;
    }
    final normalizedKey = key.toLowerCase().replaceAll('_', '');
    if (_plaintextKeys.contains(normalizedKey)) {
      return _singleLine(value.toString());
    }
    if (_isSensitiveIdentifierKey(normalizedKey)) {
      return _hashId(value.toString());
    }
    if (_isSensitiveContentKey(normalizedKey)) {
      return '<redacted>';
    }
    return _singleLine(value.toString());
  }

  static bool _isSensitiveIdentifierKey(String key) {
    return key == 'key' ||
        key == 'conversationkey' ||
        key.endsWith('id') ||
        key.contains('convid') ||
        key.contains('conversationid') ||
        key.contains('msgid') ||
        key.contains('messageid') ||
        key.contains('anchor');
  }

  static bool _isSensitiveContentKey(String key) {
    return key == 'lastmessage' ||
        key == 'messagebody' ||
        key == 'content' ||
        key == 'text';
  }

  static String _singleLine(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) {
      return normalized;
    }
    return '${normalized.substring(0, 157)}...';
  }
}

class ChatOpenTraceContext {
  const ChatOpenTraceContext({
    required this.session,
    required this.chatOpenTraceId,
    required this.requestId,
    required this.conversationKey,
    required this.t0Ms,
  });

  final String session;
  final String chatOpenTraceId;
  final int requestId;
  final String conversationKey;
  final int t0Ms;
}

class ChatOpenPrepareWorkSnapshot {
  ChatOpenPrepareWorkSnapshot({
    required this.requestId,
    required this.source,
    this.trace,
  });

  final int requestId;
  final String source;
  final ChatOpenTraceContext? trace;
  bool owned = false;
  bool joined = false;
  bool dbRead = false;
  bool sdkRead = false;
  bool committed = false;
}

class _ChatOpenTraceLedger {
  _ChatOpenTraceLedger({
    required this.sessionId,
    required this.convId,
    required this.t0Ms,
  }) : lastMarkMs = t0Ms;

  final String sessionId;
  final String convId;
  final int t0Ms;
  int lastMarkMs;
  String lastEvent = 'session_begin';
  Timer? settleTimer;
  bool firstMessagesVisibleLogged = false;
  bool historyListBuiltLogged = false;

  int prepareCount = 0;
  int actualHydrateCount = 0;
  int hydrateJoinCount = 0;
  int hydrateReuseCount = 0;
  int hydrateStartedCount = 0;
  int hydrateCommitCount = 0;
  int hydrateAbortedCount = 0;
  int ignoredPrepareCount = 0;
  int ignoredAfterDbRead = 0;
  int ignoredAfterSdkRead = 0;
  int ignoredAfterCommit = 0;
  int attachCount = 0;
  int attachBumpCount = 0;
  int attachSkipCount = 0;
  int generationRejectCount = 0;
  int appBootstrapProducerCount = 0;
  int reloadIfEmptyCount = 0;
  int uikitProducerCount = 0;
  String lastIgnoredReason = '';
  String lastRejectReason = '';

  ChatOpenTraceContext toContext() {
    return ChatOpenTraceContext(
      session: sessionId,
      chatOpenTraceId: sessionId,
      requestId: 0,
      conversationKey: convId,
      t0Ms: t0Ms,
    );
  }
}
