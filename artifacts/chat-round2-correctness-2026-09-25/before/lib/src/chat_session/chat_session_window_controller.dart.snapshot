import 'dart:async';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

import 'chat_session_window_state.dart';
import 'conversation_projection_reason.dart';
import 'conversation_window_slide_result.dart';
import '../services/conversation_local/conversation_perf_gate_log.dart';
import '../services/conversation_local/conversation_local_store.dart';
import '../services/conversation_local/conversation_perf_flags.dart';
import '../services/conversation_local/conversation_tab_store.dart';
import '../services/sqflite_lock_profile_log.dart';
import '../utils/message_conversation_id.dart';

/// Session and notification wiring for SDK pagination. Conversation rows and
/// paging cursors are read and updated exclusively through ConversationTabStore.
abstract interface class ChatSessionWindowHost {
  bool get firstScreenReady;

  bool get isFeedScrolling;
  String get currentOwnerUserId;
  int get sessionGeneration;
  bool isCurrentSession(String ownerUserId, int generation);
  void ensureTabStoreBridgeAttached();
  Future<void> primeSdkWindow({
    required ConversationStoreProjectionReason reason,
    int? visibleConvType,
  });
}

class ChatSessionWindowController {
  ChatSessionWindowController({
    required this.state,
    required this.host,
  });

  final ChatSessionWindowState state;
  final ChatSessionWindowHost host;

  // 修复"快速滑动时显示已划过的内容"：
  // 滚动期间合并相邻 hydrate 请求的节流器。
  Timer? _hydrateThrottleTimer;
  static const Duration _hydrateThrottleWindow = Duration(milliseconds: 60);

  void _scheduleHydrateThrottleFlush({
    required int convType,
    required int centerIndex,
    required bool forceReload,
    required bool allowWindowJump,
    required bool forceNotify,
  }) {
    _hydrateThrottleTimer?.cancel();
    _hydrateThrottleTimer = Timer(_hydrateThrottleWindow, () {
      _hydrateThrottleTimer = null;
      // 滚动期间或停滑都立即触发 hydrate（避开递归等待的死锁）。
      // 节流的目的只是合并连续的同帧请求，不是禁止 hydrate。
      // SDK 分页请求由 hydrateRequestSerial 串行化。
      unawaited(
        _throttledEnsureTypeIndexHydrated(
          convType: convType,
          centerIndex: centerIndex,
          forceReload: forceReload,
          allowWindowJump: allowWindowJump,
          forceNotify: forceNotify,
        ),
      );
    });
  }

  // 节流窗口到期后调用：重新走 ensureTypeIndexHydrated 的常规路径，
  // 但此时 isFeedScrolling 已可能变化，用 try-catch 兜底 host 检查。
  Future<void> _throttledEnsureTypeIndexHydrated({
    required int convType,
    required int centerIndex,
    required bool forceReload,
    required bool allowWindowJump,
    required bool forceNotify,
  }) async {
    try {
      final serial = ++state.hydrateRequestSerial;
      final gate = Completer<void>();
      final previous = state.hydrateInFlight;
      state.hydrateInFlight = gate.future;
      final ownerUserId = host.currentOwnerUserId;
      final generation = host.sessionGeneration;
      try {
        if (previous != null) await previous;
        if (serial != state.hydrateRequestSerial ||
            ownerUserId.isEmpty ||
            !host.isCurrentSession(ownerUserId, generation)) {
          return;
        }
        await _ensureTypeIndexHydratedAlgorithm(
          convType: convType,
          centerIndex: centerIndex,
          forceReload: forceReload,
          allowWindowJump: allowWindowJump,
          forceNotify: forceNotify,
          ownerUserId: ownerUserId,
          generation: generation,
        );
      } finally {
        if (identical(state.hydrateInFlight, gate.future)) {
          state.hydrateInFlight = null;
        }
        if (!gate.isCompleted) gate.complete();
      }
    } catch (e, st) {
      ConversationPerfGateLog.log(
        'throttled_hydrate_failed',
        extras: <String, Object?>{
          'convType': convType,
          'centerIndex': centerIndex,
          'error': e.toString(),
          'stack': st.toString(),
        },
      );
    }
  }

  void disposeHydrateThrottle() {
    _hydrateThrottleTimer?.cancel();
    _hydrateThrottleTimer = null;
  }

  /// Selects a bounded set of rows for a soft refresh around the viewport.
  /// This keeps the refresh path from materializing/parsing the whole account
  /// when the visible window is larger than the configured cap.
  static List<String> selectSoftReloadConversationIds({
    required List<V2TimConversation> window,
    String? anchorId,
    List<String> extraIds = const <String>[],
    int? maxIds,
  }) {
    final cap = maxIds ?? ConversationPerfFlags.softReloadByIdsMax;
    final extras = extraIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (window.isEmpty) return extras;
    if (cap <= 0 || window.length <= cap) {
      return <String>{
        ...window
            .map((c) => c.conversationID.trim())
            .where((id) => id.isNotEmpty),
        ...extras,
      }.toList(growable: false);
    }

    SqfliteLockProfileLog.event(
      'conversationsByIds_capped',
      extras: <String, Object?>{
        'countBefore': window.length,
        'countAfter': cap,
        'anchor': anchorId ?? '-',
      },
    );
    final selected = <String>{};
    void addId(String raw) {
      final id = raw.trim();
      if (id.isNotEmpty) selected.add(id);
    }

    for (final extra in extras) {
      addId(extra);
    }
    final pinnedReserve = ConversationPerfFlags.uiSlidingWindowPinnedReserve;
    var pinnedAdded = 0;
    for (final conversation in window) {
      if (conversation.isPinned != true) continue;
      addId(conversation.conversationID);
      if (++pinnedAdded >= pinnedReserve) break;
    }

    var anchorIndex = -1;
    final anchor = anchorId?.trim() ?? '';
    if (anchor.isNotEmpty) {
      for (var i = 0; i < window.length; i++) {
        if (MessageConversationId.sameConversation(
          window[i].conversationID,
          anchor,
        )) {
          anchorIndex = i;
          break;
        }
      }
    }
    if (anchorIndex < 0) anchorIndex = window.length ~/ 2;

    var radius = 0;
    while (selected.length < cap &&
        (anchorIndex - radius >= 0 || anchorIndex + radius < window.length)) {
      if (anchorIndex - radius >= 0) {
        addId(window[anchorIndex - radius].conversationID);
      }
      if (selected.length >= cap) break;
      if (radius > 0 && anchorIndex + radius < window.length) {
        addId(window[anchorIndex + radius].conversationID);
      }
      radius++;
    }
    return selected.take(cap).toList(growable: false);
  }

  /// Trims a sorted window around an anchor while reserving pinned/unread
  /// rows. The returned offsets are based on the original sorted list.
  static ({
    List<V2TimConversation> list,
    int trimmedFromStart,
    int trimmedFromEnd,
  }) trimAroundViewportAnchor(
    List<V2TimConversation> sorted, {
    String? anchorId,
    int? budget,
    int? pinnedReserve,
  }) {
    final cap = budget ?? ConversationPerfFlags.uiSlidingWindowBudget;
    if (cap <= 0 || sorted.length <= cap) {
      return (
        list: List<V2TimConversation>.from(sorted),
        trimmedFromStart: 0,
        trimmedFromEnd: 0,
      );
    }

    var anchorIndex = -1;
    final anchor = anchorId?.trim() ?? '';
    if (anchor.isNotEmpty) {
      for (var i = 0; i < sorted.length; i++) {
        if (MessageConversationId.sameConversation(
          sorted[i].conversationID,
          anchor,
        )) {
          anchorIndex = i;
          break;
        }
      }
    }
    if (anchorIndex < 0) anchorIndex = sorted.length ~/ 2;

    final half = cap ~/ 2;
    var start = anchorIndex - half;
    if (start < 0) start = 0;
    var end = start + cap;
    if (end > sorted.length) {
      end = sorted.length;
      start = end - cap;
      if (start < 0) start = 0;
    }

    final kept = <String>{};
    final out = <V2TimConversation>[];
    void take(V2TimConversation conversation) {
      final id = conversation.conversationID.trim();
      if (id.isEmpty || kept.contains(id) || out.length >= cap) return;
      out.add(conversation);
      kept.add(id);
    }

    final pinLimit =
        pinnedReserve ?? ConversationPerfFlags.uiSlidingWindowPinnedReserve;
    var pinnedTaken = 0;
    for (final conversation in sorted) {
      if (conversation.isPinned != true) continue;
      take(conversation);
      if (++pinnedTaken >= pinLimit) break;
    }
    final unreadReserve = ConversationPerfFlags.uiSlidingWindowUnreadReserve;
    if (unreadReserve > 0) {
      var unreadTaken = 0;
      for (final conversation in sorted) {
        if ((conversation.unreadCount ?? 0) <= 0) continue;
        take(conversation);
        if (++unreadTaken >= unreadReserve || out.length >= cap) break;
      }
    }
    for (var i = start; i < end; i++) {
      take(sorted[i]);
    }

    var radius = 0;
    while (out.length < cap &&
        (anchorIndex - radius >= 0 || anchorIndex + radius < sorted.length)) {
      if (anchorIndex - radius >= 0) take(sorted[anchorIndex - radius]);
      if (out.length >= cap) break;
      if (radius > 0 && anchorIndex + radius < sorted.length) {
        take(sorted[anchorIndex + radius]);
      }
      radius++;
    }
    out.sort(ConversationLocalStore.compareConversationsForUi);
    return (
      list: out,
      trimmedFromStart: start,
      trimmedFromEnd: sorted.length - end,
    );
  }

  /// The total is derived from the SDK window on every read. Archive removal
  /// uses the Store's normal delta notification instead of a second count cache.
  Future<void> refreshTypeTotals() async {
    final owner = host.currentOwnerUserId;
    final generation = host.sessionGeneration;
    if (owner.isEmpty || !host.isCurrentSession(owner, generation)) {
      return;
    }

    host.ensureTabStoreBridgeAttached();
    ConversationTabStore.instance.purgeArchived();
  }

  /// Restores the SDK conversation window without replacing an expanded
  /// viewport. A restore is single-flight per user session; a write arriving
  /// during the flight only schedules one follow-up pass.
  Future<void> restoreSdkWindow({
    ConversationStoreProjectionReason reason =
        ConversationStoreProjectionReason.sdkProjectionRestore,
    int? visibleConvType,
  }) async {
    ConversationPerfGateLog.log(
      'store_projection_reload_allowlist',
      extras: <String, Object?>{
        'reason': reason.name,
        if (visibleConvType != null) 'visibleConvType': visibleConvType,
      },
    );
    final existing = state.reloadInFlight;
    if (existing != null) {
      state.reloadDirty = true;
      state.reloadDirtyReason = reason.name;
      await existing;
      return;
    }
    final owner = host.currentOwnerUserId;
    final generation = host.sessionGeneration;
    if (owner.isEmpty || !host.isCurrentSession(owner, generation)) return;

    final task = _restoreSdkWindowOnce(
      ownerUserId: owner,
      generation: generation,
      reason: reason,
      visibleConvType: visibleConvType,
    );
    state.reloadInFlight = task;
    var rerun = false;
    try {
      await task;
    } finally {
      if (identical(state.reloadInFlight, task)) {
        state.reloadInFlight = null;
        rerun = state.reloadDirty && host.isCurrentSession(owner, generation);
        state.reloadDirty = false;
        state.reloadDirtyReason = null;
      }
    }
    if (rerun) {
      await restoreSdkWindow(
        reason: reason,
        visibleConvType: visibleConvType,
      );
    }
  }

  Future<void> _restoreSdkWindowOnce({
    required String ownerUserId,
    required int generation,
    required ConversationStoreProjectionReason reason,
    int? visibleConvType,
  }) async {
    {
      await host.primeSdkWindow(
        reason: reason,
        visibleConvType: visibleConvType,
      );
      return;
    }
  }

  Future<void> ensureTypeIndexHydrated({
    required int convType,
    required int centerIndex,
    bool forceReload = false,
    bool allowWindowJump = false,
    bool forceNotify = false,
  }) async {
    // 修复"快速滑动时显示已划过的内容"：
    // 滚动期间合并相邻 hydrate 请求的节流窗口。
    // 滚动期间用 60ms 窗口合并连续的 SDK 分页请求。
    // 滚动期间只允许一个并发 hydrate，停滑后恢复常规路径。
    if (host.isFeedScrolling && !forceReload) {
      // 滚动期间已有 hydrate 在飞：直接丢弃本次请求。
      // 这样避免每帧都 serial++ 阻塞主线程。
      if (state.hydrateInFlight != null) {
        return;
      }
      _scheduleHydrateThrottleFlush(
        convType: convType,
        centerIndex: centerIndex,
        forceReload: forceReload,
        allowWindowJump: allowWindowJump,
        forceNotify: forceNotify,
      );
      return;
    }
    final serial = ++state.hydrateRequestSerial;
    final gate = Completer<void>();
    final previous = state.hydrateInFlight;
    state.hydrateInFlight = gate.future;
    final ownerUserId = host.currentOwnerUserId;
    final generation = host.sessionGeneration;
    try {
      if (previous != null) await previous;
      if (serial != state.hydrateRequestSerial ||
          ownerUserId.isEmpty ||
          !host.isCurrentSession(ownerUserId, generation)) {
        return;
      }
      await _ensureTypeIndexHydratedAlgorithm(
        convType: convType,
        centerIndex: centerIndex,
        forceReload: forceReload,
        allowWindowJump: allowWindowJump,
        forceNotify: forceNotify,
        ownerUserId: ownerUserId,
        generation: generation,
      );
    } finally {
      if (identical(state.hydrateInFlight, gate.future)) {
        state.hydrateInFlight = null;
      }
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<ConversationWindowSlideResult> appendOlderFromLocal({
    int? convType,
    bool protectVirtualViewport = false,
  }) async {
    final int loadKey = convType == 1 || convType == 2 ? convType! : 0;
    if (state.typeUiPageLoadInFlight[loadKey] != null) {
      return ConversationWindowSlideResult.empty;
    }
    state.hotHeadPhase2Generation++;
    final owner = host.currentOwnerUserId;
    final generation = host.sessionGeneration;
    if (owner.isEmpty || !host.isCurrentSession(owner, generation)) {
      return ConversationWindowSlideResult.empty;
    }
    final gate = Completer<void>();
    final pageTask = gate.future;
    state.typeUiPageLoadInFlight[loadKey] = pageTask;
    if (loadKey == 0) state.uiPageLoadInFlight = pageTask;
    try {
      return await _appendOlderAlgorithm(
        convType: convType,
        ownerUserId: owner,
        generation: generation,
      );
    } finally {
      if (identical(state.typeUiPageLoadInFlight[loadKey], pageTask)) {
        state.typeUiPageLoadInFlight.remove(loadKey);
      }
      if (loadKey == 0 && identical(state.uiPageLoadInFlight, pageTask)) {
        state.uiPageLoadInFlight = null;
      }
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<void> _ensureTypeIndexHydratedAlgorithm({
    required int convType,
    required int centerIndex,
    required bool forceReload,
    required bool allowWindowJump,
    required bool forceNotify,
    required String ownerUserId,
    required int generation,
  }) async {
    final tabStore = ConversationTabStore.instance;
    {
      if (!host.firstScreenReady) return;
      host.ensureTabStoreBridgeAttached();
      await tabStore.ensurePrimed(convType: convType);
      if (!host.isCurrentSession(ownerUserId, generation)) return;
      var pageAttempts = 0;
      while (tabStore.atTypeIndex(convType, centerIndex) == null &&
          !tabStore.finishedForType(convType) &&
          pageAttempts < 3) {
        pageAttempts++;
        if (tabStore.countForType(convType) == 0) {
          await tabStore.loadFirstPage(convType: convType);
        } else {
          await tabStore.loadMore(convType: convType);
        }
        if (!host.isCurrentSession(ownerUserId, generation)) return;
      }
      final loaded = tabStore.countForType(convType);
      if (!tabStore.finishedForType(convType) &&
          (forceReload || centerIndex >= (loaded - 8).clamp(0, 1 << 30))) {
        await tabStore.loadMore(convType: convType);
        if (!host.isCurrentSession(ownerUserId, generation)) return;
      }
      return;
    }
  }

  Future<ConversationWindowSlideResult> _appendOlderAlgorithm({
    required int? convType,
    required String ownerUserId,
    required int generation,
  }) async {
    if (!host.isCurrentSession(ownerUserId, generation)) {
      return ConversationWindowSlideResult.empty;
    }
    {
      host.ensureTabStoreBridgeAttached();
      final typeFilter = convType == 1 || convType == 2 ? convType! : null;
      if (typeFilter == null) {
        final before1 = ConversationTabStore.instance.countForType(1);
        final before2 = ConversationTabStore.instance.countForType(2);
        await ConversationTabStore.instance.loadMore(convType: 1);
        if (!host.isCurrentSession(ownerUserId, generation)) {
          return ConversationWindowSlideResult.empty;
        }
        await ConversationTabStore.instance.loadMore(convType: 2);
        if (!host.isCurrentSession(ownerUserId, generation)) {
          return ConversationWindowSlideResult.empty;
        }
        final added =
            (ConversationTabStore.instance.countForType(1) - before1) +
                (ConversationTabStore.instance.countForType(2) - before2);
        return added > 0
            ? ConversationWindowSlideResult(added: added)
            : ConversationWindowSlideResult.empty;
      }
      if (ConversationTabStore.instance.countForType(typeFilter) == 0 &&
          !ConversationTabStore.instance.finishedForType(typeFilter)) {
        await ConversationTabStore.instance.loadFirstPage(convType: typeFilter);
        if (!host.isCurrentSession(ownerUserId, generation)) {
          return ConversationWindowSlideResult.empty;
        }
        final count = ConversationTabStore.instance.countForType(typeFilter);
        return count > 0
            ? ConversationWindowSlideResult(added: count)
            : ConversationWindowSlideResult.empty;
      }
      final before = ConversationTabStore.instance.countForType(typeFilter);
      await ConversationTabStore.instance.loadMore(convType: typeFilter);
      if (!host.isCurrentSession(ownerUserId, generation)) {
        return ConversationWindowSlideResult.empty;
      }
      final added =
          ConversationTabStore.instance.countForType(typeFilter) - before;
      return added > 0
          ? ConversationWindowSlideResult(added: added)
          : ConversationWindowSlideResult.empty;
    }
  }
}
