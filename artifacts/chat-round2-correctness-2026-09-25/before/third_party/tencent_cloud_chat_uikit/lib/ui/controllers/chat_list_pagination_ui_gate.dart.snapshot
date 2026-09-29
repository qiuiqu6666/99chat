import 'dart:async';

enum ChatPreviousLoadDecision { ready, wait, needsGesture, discard }

/// One pending older-page intent. Waiting for a lock owns no viewport/trim lock.
/// Updating an intent keeps its first deadline; a completion never queues a page.
class ChatPreviousLoadQueue {
  static const retryDelay =
      Duration(milliseconds: ChatListPaginationUiGate.loadPreviousDebounceMs);
  Timer? _timer;
  ({
    ChatPreviousLoadDecision Function() evaluate,
    Future<void> Function() load,
    void Function(ChatPreviousLoadDecision) onDecision,
    bool userGesture,
  })? _pending;
  bool _admitted = false;
  bool _disposed = false;

  bool get isPending => _pending != null;
  bool get isAdmitted => _pending != null && _admitted;

  void request({
    required ChatPreviousLoadDecision Function() evaluate,
    required Future<void> Function() load,
    required void Function(ChatPreviousLoadDecision) onDecision,
    required bool userGesture,
  }) {
    if (_disposed) return;
    final previousDecision = _pending?.evaluate();
    if (previousDecision == ChatPreviousLoadDecision.discard ||
        previousDecision == ChatPreviousLoadDecision.needsGesture) {
      cancel();
    }
    // Automatic fill/prefetch cannot downgrade a deliberate waiting gesture.
    if (_pending?.userGesture == true && !userGesture) return;
    final decision = evaluate();
    if (decision == ChatPreviousLoadDecision.discard ||
        decision == ChatPreviousLoadDecision.needsGesture) {
      onDecision(decision);
      return;
    }
    _pending = (
      evaluate: evaluate,
      load: load,
      onDecision: onDecision,
      userGesture: userGesture,
    );
    _admitted = decision == ChatPreviousLoadDecision.ready;
    onDecision(decision);
    _timer ??= Timer(retryDelay, _attempt);
  }

  void _attempt() {
    _timer = null;
    final pending = _pending;
    if (_disposed || pending == null) return;
    final decision = pending.evaluate();
    if (decision == ChatPreviousLoadDecision.wait) {
      _admitted = false;
      pending.onDecision(decision);
      _timer = Timer(retryDelay, _attempt);
      return;
    }
    _pending = null;
    _admitted = false;
    pending.onDecision(decision);
    if (decision == ChatPreviousLoadDecision.ready) {
      unawaited(pending.load());
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _admitted = false;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

/// Transient UI locks for top/bottom history pagination on the message list.
class ChatListPaginationUiGate {
  static const loadLatestCooldownMs = 300;
  static const loadPreviousDebounceMs = 120;
  static const loadPreviousCooldownMs = 320;
  static const historyScrollProtectMs = 520;
  static const loadPreviousScrollUnlockMs = 360;
  static const scrollPaginationCompensationMs = 1200;
  static const incomingWhileReadingCompensationMs = 800;
  static const readingHistoryThresholdPx = 80.0;
  static const loadPreviousTopReachResetPx = 320.0;
  static const loadPreviousTopNearPx = 160.0;
  static const loadPreviousOverscrollTolerancePx = 2.0;
  static const minTopHistoryLoadingVisibleMs = 280;

  bool isLoadingPrevious = false;
  bool silentTopHistoryLoading = false;
  bool triedPreviousAfterNoMore = false;
  int lastLoadPreviousCompletedAtMs = 0;
  int ignoreScrollLoadPrevious = 0;
  int historyScrollProtectUntilMs = 0;
  String? previousLoadInFlightAnchorKey;
  bool previousLoadConsumedThisTopReach = false;
  bool previousRetryNeedsUserGesture = false;
  String? lastTopReachConsumedAnchorKey;
  int lastScrollBlockLogMs = 0;
  Future<void>? loadPreviousTask;
  bool isLoadingLatest = false;
  int lastLoadLatestCompletedAtMs = 0;
  int topHistoryLoadingShownAtMs = 0;
  int previousUserGestureSequence = 0;
  int previousLoadGestureSequence = -1;
  Timer? loadLatestDebounce;
  Timer? loadingIndicatorTimer;
  int latestLoadSuppressedUntilMs = 0;
  int scrollPaginationCompensationUntilMs = 0;
  int scrollPaginationCompensationGeneration = 0;

  /// 上拉分页前列表最老可翻页消息，用于 prepend 后贴顶时按消息恢复视口。
  String? paginationRestoreAnchorMsgID;
  int? paginationRestoreAnchorSeq;

  /// 贴顶上拉：滚动补偿完成前隐藏新 prepend 行，避免历史条直接跳出来。
  bool paginationPrependRevealPending = false;

  /// [paginationPrependRevealPending] 时，globalIndex >= 该值的行暂不可见。
  int paginationPrependRevealFromGlobalIndex = 0;

  bool isHistoryScrollProtected({
    required bool mediaPreviewRestoring,
    int? nowMs,
  }) {
    if (mediaPreviewRestoring) {
      return false;
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return isLoadingPrevious ||
        ignoreScrollLoadPrevious > 0 ||
        now < historyScrollProtectUntilMs;
  }

  void beginHistoryScrollProtection({int? milliseconds, int? nowMs}) {
    final protectMs = milliseconds ?? historyScrollProtectMs;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final until = now + protectMs;
    if (until > historyScrollProtectUntilMs) {
      historyScrollProtectUntilMs = until;
    }
  }

  bool canScheduleLoadPrevious({
    required bool searchJumpStabilizing,
    required bool historyScrollProtected,
    int? nowMs,
  }) {
    if (isLoadingPrevious || searchJumpStabilizing || historyScrollProtected) {
      return false;
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return now - lastLoadPreviousCompletedAtMs >= loadPreviousCooldownMs;
  }

  /// 本次贴顶是否已消费过上拉分页。
  /// 离开顶部或成功翻页后再允许；零增长页须等待新的用户拖动。
  bool shouldAllowLoadPreviousAtTopReach({
    bool bypassTopReachConsumed = false,
    String? anchorKey,
  }) {
    releasePreviousRetryForChangedAnchor(anchorKey);
    if (previousRetryNeedsUserGesture) {
      return false;
    }
    if (bypassTopReachConsumed) {
      return true;
    }
    return !previousLoadConsumedThisTopReach;
  }

  void markTopReachConsumedForPreviousLoad(String anchorKey) {
    previousLoadGestureSequence = previousUserGestureSequence;
    previousLoadConsumedThisTopReach = true;
    lastTopReachConsumedAnchorKey = anchorKey;
  }

  void resetTopReachConsumedIfScrolledAway({
    required double pixels,
    required double maxScrollExtent,
  }) {
    // Programmatic window moves must retain the failed cursor until it can be
    // compared with the next window's cursor (or a real input retries it).
    if (previousRetryNeedsUserGesture) return;
    if (maxScrollExtent <= 0) {
      return;
    }
    if (pixels < maxScrollExtent - loadPreviousTopReachResetPx) {
      previousLoadConsumedThisTopReach = false;
      lastTopReachConsumedAnchorKey = null;
    }
  }

  /// 分页请求结束：只清 in-flight，保留贴顶消费位（防同顶连拉）。
  void finishPreviousLoadInFlight() {
    previousLoadInFlightAnchorKey = null;
  }

  /// 成功翻到更早一页且模型仍有更早历史：放开同一次贴顶消费位。
  /// 已确认到底的空批仍保持消费位（见 [finishPreviousLoadInFlight]）。
  void releaseTopReachConsumedAfterSuccessfulPage({
    required bool haveMoreData,
  }) {
    previousRetryNeedsUserGesture = false;
    if (!haveMoreData) {
      return;
    }
    previousLoadConsumedThisTopReach = false;
    lastTopReachConsumedAnchorKey = null;
  }

  /// Keep a zero-growth request latched until the next real user drag.
  /// Cooldowns alone do not stop rebuilds/viewport fill from retrying forever.
  void releaseTopReachConsumedAfterRetryableNoGrowth({
    required bool haveMoreData,
  }) {
    previousLoadConsumedThisTopReach = true;
    previousRetryNeedsUserGesture = haveMoreData;
  }

  void onUserDragStart() {
    previousUserGestureSequence++;
    if (!previousRetryNeedsUserGesture ||
        isLoadingPrevious ||
        loadPreviousTask != null) {
      return;
    }
    previousRetryNeedsUserGesture = false;
    previousLoadConsumedThisTopReach = false;
    lastTopReachConsumedAnchorKey = null;
  }

  void releasePreviousRetryForChangedAnchor(String? anchorKey) {
    if (!previousRetryNeedsUserGesture ||
        anchorKey == null ||
        lastTopReachConsumedAnchorKey == null ||
        anchorKey == lastTopReachConsumedAnchorKey) {
      return;
    }
    previousRetryNeedsUserGesture = false;
    previousLoadConsumedThisTopReach = false;
    lastTopReachConsumedAnchorKey = null;
  }

  bool canScheduleLoadLatest({int? nowMs}) {
    if (isLoadingLatest) {
      return false;
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return now - lastLoadLatestCompletedAtMs >= loadLatestCooldownMs;
  }

  void armLoadLatestDebounce({
    required Duration delay,
    required void Function() onFire,
  }) {
    loadLatestDebounce?.cancel();
    loadLatestDebounce = Timer(delay, onFire);
  }

  void disposeTimers() {
    loadLatestDebounce?.cancel();
    loadLatestDebounce = null;
    loadingIndicatorTimer?.cancel();
    loadingIndicatorTimer = null;
  }

}
