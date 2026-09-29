import 'package:flutter/widgets.dart';

import 'chat_jitter_diag.dart';

/// 聊天历史上拉分页专用 ScrollPhysics。
///
/// 在 [ScrollPhysics.adjustPositionForNewDimensions] 阶段补偿 maxScrollExtent
/// 变化，使视口内消息在「头部插入旧消息 / 异步撑高 / spacer 变化」时保持
/// 相对位置。这是 Flutter 推荐的 scroll 维持方式，等同
/// maintainVisibleContentPosition 的内部机制，不依赖 post-frame jumpTo。
class HistoryPaginationScrollPhysics extends ScrollPhysics {
  const HistoryPaginationScrollPhysics({
    super.parent,
    this.shouldCompensate,
    this.shouldPreserveNewestInsertExtent,
    this.lastSeenMaxExtent,
    this.onMaxExtentObserved,
    this.newestInsertRoom,
    this.onNewestInsertApplied,
    this.revealGrowthPending,
    this.newestInsertAnchorCorrection,
    this.pinnedNearTopTolerancePx = 160.0,
  });

  /// 返回 true 时启用补偿（上拉分页加载窗口内）。
  final bool Function()? shouldCompensate;

  /// A reverse chat list inserts newest messages at its minimum scroll edge.
  /// Compensating max-extent growth here keeps existing rows fixed before the
  /// frame is painted (used when a context menu flushes buffered messages).
  final bool Function()? shouldPreserveNewestInsertExtent;

  /// 上一次 layout 观测到的 maxScrollExtent。oldPosition 在连续多帧中会冻在
  /// 同一个旧快照上，用它算增量会让同一段增长被重复补偿。
  final double? Function()? lastSeenMaxExtent;

  /// 每次 layout 变化后回写观测值，供下一帧作为基准。
  final void Function(double maxScrollExtent)? onMaxExtentObserved;

  /// 本批最新端插入的真实高度余额。maxScrollExtent 带着随视口移动的外推
  /// 误差，不能用它当补偿依据；预算用完即停，反馈环由此断开。
  final double? Function()? newestInsertRoom;

  /// 回报本次实际补偿量，用于扣减余额。
  final void Function(double applied)? onNewestInsertApplied;

  /// Marks a progressive reveal for diagnostics. It does not turn the lazy
  /// sliver's estimated total extent into a measurement of the inserted row.
  final bool Function()? revealGrowthPending;

  /// A measured row anchor takes precedence over estimated sliver extents.
  /// Null means no active transaction; zero means the row has not moved.
  final double? Function(ScrollMetrics metrics)? newestInsertAnchorCorrection;

  /// 与上拉触发阈值一致：贴顶时不做 extent+=growth（会落到新批次最旧一条），改由消息锚点恢复。
  final double pinnedNearTopTolerancePx;

  // 诊断状态。physics 是 const 且 applyTo 会重建实例，存不住实例字段，
  // 只能用静态量。不参与 pixels 计算。
  static const int _diagBurstGapUs = 8000;
  static int _diagLastCallAtUs = 0;
  static int _diagBurstSeq = 0;
  static int _diagCallInBurst = 0;
  static double _diagBurstApplied = 0.0;
  static double _diagBurstSkippedShrink = 0.0;
  static double _diagBurstStartOldMax = 0.0;

  @override
  HistoryPaginationScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HistoryPaginationScrollPhysics(
      parent: buildParent(ancestor),
      shouldCompensate: shouldCompensate,
      shouldPreserveNewestInsertExtent: shouldPreserveNewestInsertExtent,
      lastSeenMaxExtent: lastSeenMaxExtent,
      onMaxExtentObserved: onMaxExtentObserved,
      newestInsertRoom: newestInsertRoom,
      onNewestInsertApplied: onNewestInsertApplied,
      revealGrowthPending: revealGrowthPending,
      newestInsertAnchorCorrection: newestInsertAnchorCorrection,
      pinnedNearTopTolerancePx: pinnedNearTopTolerancePx,
    );
  }

  /// 上拉分页 prepend 后，按加载前 scroll 与 max 的差值补偿 extent 增长。
  static double? computeExtentDeltaRestorePixels({
    required double anchorPixels,
    required double anchorMaxExtent,
    required double newMaxScrollExtent,
    required double minScrollExtent,
  }) {
    if (anchorMaxExtent <= 0) {
      return null;
    }
    final delta = newMaxScrollExtent - anchorMaxExtent;
    if (delta <= 0.5) {
      return null;
    }
    return (anchorPixels + delta).clamp(minScrollExtent, newMaxScrollExtent);
  }

  /// 加载触发时是否处于 iOS 回弹 overscroll（pixels 超过 max）。
  static bool wasOverscrollingPastTop({
    required double anchorPixels,
    required double anchorMaxExtent,
    double tolerancePx = 2.0,
  }) {
    return anchorMaxExtent > 0 && anchorPixels > anchorMaxExtent + tolerancePx;
  }

  /// Converts a visible row's viewport drift into scroll pixels while
  /// respecting reverse scroll axes.
  static double restorePixelsForViewportAnchor({
    required AxisDirection axisDirection,
    required double currentPixels,
    required double currentAnchorTop,
    required double desiredAnchorTop,
    required double minScrollExtent,
    required double maxScrollExtent,
  }) {
    final viewportDrift = currentAnchorTop - desiredAnchorTop;
    final scrollDelta = switch (axisDirection) {
      AxisDirection.down || AxisDirection.right => viewportDrift,
      AxisDirection.up || AxisDirection.left => -viewportDrift,
    };
    return (currentPixels + scrollDelta).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    var pixels = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    final trackedMax = lastSeenMaxExtent?.call();
    final referenceMax = trackedMax ?? oldPosition.maxScrollExtent;
    // 必须早于所有 return：漏掉任何一帧的回写，下次补偿窗打开时基准又是旧值。
    onMaxExtentObserved?.call(newPosition.maxScrollExtent);
    final anchorCorrection = newestInsertAnchorCorrection?.call(newPosition);
    if (anchorCorrection != null) {
      return (newPosition.pixels + anchorCorrection)
          .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
    }
    final compensatePagination = shouldCompensate?.call() ?? false;
    // A configured anchor provider owns reverse insertion geometry, including
    // when it cannot currently measure a row. Never switch to total-extent
    // estimates on that path: they can grow or shrink without a real insert.
    final preserveNewestInsert = newestInsertAnchorCorrection == null &&
        (shouldPreserveNewestInsertExtent?.call() ?? false);
    if (!compensatePagination && !preserveNewestInsert) {
      return pixels;
    }
    final basePixels = pixels;
    var appliedNewestInsert = false;
    var appliedPagination = false;
    final newestRoom = newestInsertRoom?.call();
    final revealPending = revealGrowthPending?.call() ?? false;
    var appliedDelta = 0.0;

    // 上拉分页窗口内：即使用户仍在拖拽，也要补偿 prepend 带来的 extent 增长，
    // 否则 Web 上 load 常在 isScrolling==true 时完成，视口会跳到更旧消息。
    // Keyboard resizing changes the extent without inserting any messages.
    // Compensate only content growth, otherwise keyboard and pagination both
    // move the viewport for the same geometry change.
    final viewportDelta =
        newPosition.viewportDimension - oldPosition.viewportDimension;
    final maxGrowth =
        newPosition.maxScrollExtent - referenceMax + viewportDelta;
    final pinnedToOldMax = oldPosition.maxScrollExtent > 0 &&
        oldPosition.pixels >=
            oldPosition.maxScrollExtent - pinnedNearTopTolerancePx;
    // Chat history uses `reverse: true` (AxisDirection.up). Older rows are
    // appended at the visual top, so maxExtent grows without moving the
    // existing rows relative to the viewport. Adding the growth to pixels in
    // this direction would move the reader toward the newly inserted page.
    final growsTowardViewportEnd =
        newPosition.axisDirection == AxisDirection.down ||
            newPosition.axisDirection == AxisDirection.right;
    final newestGrowsFromMinEdge =
        newPosition.axisDirection == AxisDirection.up ||
            newPosition.axisDirection == AxisDirection.left;
    // Production always supplies a room callback. 0.0 means "no real insert"
    // and must not fall back to maxGrowth (media/layout noise + skipped
    // reverse shrink ratchets the user onto the newest edge). Null room
    // (tests / callers without a budget) still uses maxGrowth.
    // A positive room is one-shot and capped by this frame's content growth.
    var newestApplied = 0.0;
    if (newestRoom == null) {
      newestApplied = maxGrowth > 0.5 ? maxGrowth : 0.0;
    } else if (newestRoom > 0.5 && maxGrowth > 0.5) {
      newestApplied = newestRoom < maxGrowth ? newestRoom : maxGrowth;
    }
    if (preserveNewestInsert && newestApplied > 0.5 && newestGrowsFromMinEdge) {
      // `reverse: true`: new rows grow from the visual bottom/min edge. Move
      // pixels by the same extent before paint so every existing row remains
      // at its previous viewport coordinate.
      pixels += newestApplied;
      onNewestInsertApplied?.call(newestApplied);
      appliedNewestInsert = true;
      appliedDelta = newestApplied;
    } else if (compensatePagination &&
        maxGrowth > 0.5 &&
        !pinnedToOldMax &&
        growsTowardViewportEnd) {
      // 中部上翻：同步补偿 prepend 高度，视口内消息不动、新历史从顶部插入。
      pixels += maxGrowth;
      appliedPagination = true;
      appliedDelta = maxGrowth;
    }

    final maxShrink = -maxGrowth;
    // A reverse chat list grows and shrinks at its visual top. Existing rows
    // therefore keep their viewport coordinates without a pixels correction.
    // Applying the normal-list shrink correction here visibly kicks the list
    // while media rows settle or a pagination placeholder disappears.
    if (compensatePagination && maxShrink > 0.5 && growsTowardViewportEnd) {
      pixels -= maxShrink;
    }

    final result = pixels.clamp(
      newPosition.minScrollExtent,
      newPosition.maxScrollExtent,
    );
    _logPhysicsAdjust(
      oldPixels: oldPosition.pixels,
      basePixels: basePixels,
      outPixels: result,
      oldMax: oldPosition.maxScrollExtent,
      referenceMax: referenceMax,
      trackedMax: trackedMax,
      newMax: newPosition.maxScrollExtent,
      maxGrowth: maxGrowth,
      viewportDelta: viewportDelta,
      room: newestRoom,
      appliedDelta: appliedDelta,
      preserveNewestInsert: preserveNewestInsert,
      revealPending: revealPending,
      compensatePagination: compensatePagination,
      appliedNewestInsert: appliedNewestInsert,
      appliedPagination: appliedPagination,
      growsTowardViewportEnd: growsTowardViewportEnd,
      newestGrowsFromMinEdge: newestGrowsFromMinEdge,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    return result;
  }

  /// 棘轮取证：只记真正改了 pixels 的调用，以及被 reverse 分支吞掉的负增长。
  /// 同一 burst 内 burstApplied 远大于 burstNetMax 即为棘轮累积。
  static void _logPhysicsAdjust({
    required double oldPixels,
    required double basePixels,
    required double outPixels,
    required double oldMax,
    required double referenceMax,
    required double? trackedMax,
    required double newMax,
    required double maxGrowth,
    required double viewportDelta,
    required double? room,
    required double appliedDelta,
    required bool preserveNewestInsert,
    required bool revealPending,
    required bool compensatePagination,
    required bool appliedNewestInsert,
    required bool appliedPagination,
    required bool growsTowardViewportEnd,
    required bool newestGrowsFromMinEdge,
    required bool isScrolling,
    required double velocity,
  }) {
    if (!ChatJitterDiag.followingLatestEnabled) {
      return;
    }
    final shrinkSwallowed =
        compensatePagination && maxGrowth < -0.5 && !growsTowardViewportEnd;
    // 预算制下最新端不再回退负增长，这是设计决定，单独记以便观察被跳过的量。
    final newestShrinkSkipped =
        preserveNewestInsert && maxGrowth < -0.5 && newestGrowsFromMinEdge;
    if (!appliedNewestInsert &&
        !appliedPagination &&
        !shrinkSwallowed &&
        !newestShrinkSkipped) {
      return;
    }
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (nowUs - _diagLastCallAtUs > _diagBurstGapUs) {
      _diagBurstSeq++;
      _diagCallInBurst = 0;
      _diagBurstApplied = 0.0;
      _diagBurstSkippedShrink = 0.0;
      _diagBurstStartOldMax = oldMax;
    }
    _diagLastCallAtUs = nowUs;
    _diagCallInBurst++;
    if (appliedNewestInsert || appliedPagination) {
      _diagBurstApplied += appliedDelta;
    }
    if (shrinkSwallowed) {
      _diagBurstSkippedShrink += maxGrowth;
    }
    ChatJitterDiag.logFollowingLatest(
      action: 'physics_adjust',
      extras: <String, Object?>{
        'burst': _diagBurstSeq,
        'call': _diagCallInBurst,
        'appliedKind': appliedNewestInsert
            ? 'newest'
            : (appliedPagination
                ? 'pagination'
                : (shrinkSwallowed
                    ? 'swallowed_shrink'
                    : 'newest_shrink_skipped')),
        'oldPixels': oldPixels.toStringAsFixed(1),
        'basePixels': basePixels.toStringAsFixed(1),
        'outPixels': outPixels.toStringAsFixed(1),
        'oldMax': oldMax.toStringAsFixed(1),
        'referenceMax': referenceMax.toStringAsFixed(1),
        if (trackedMax == null) 'trackedMaxMissing': true,
        'newMax': newMax.toStringAsFixed(1),
        'maxGrowth': maxGrowth.toStringAsFixed(1),
        'applied': appliedDelta.toStringAsFixed(1),
        if (room != null) 'room': room.toStringAsFixed(1),
        'viewportDelta': viewportDelta.toStringAsFixed(1),
        'burstApplied': _diagBurstApplied.toStringAsFixed(1),
        'burstSkippedShrink': _diagBurstSkippedShrink.toStringAsFixed(1),
        'burstStartOldMax': _diagBurstStartOldMax.toStringAsFixed(1),
        'burstNetMax': (newMax - _diagBurstStartOldMax).toStringAsFixed(1),
        'preserveNewestInsert': preserveNewestInsert,
        'revealPending': revealPending,
        'compensatePagination': compensatePagination,
        'isScrolling': isScrolling,
        'velocity': velocity.toStringAsFixed(1),
      },
    );
  }
}
