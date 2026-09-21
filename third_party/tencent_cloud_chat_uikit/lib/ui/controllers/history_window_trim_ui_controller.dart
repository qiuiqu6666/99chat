import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_pagination_scroll_physics.dart';

enum HistoryWindowTrimUiOutcome {
  skipped,
  restored,
  rolledBack,
  rollbackFailed,
  keptCommitted
}

/// Serializes the UI half of a durable history-window trim. Membership is
/// committed only after persistence and a fresh interaction/route check. A
/// successful scroll write is not success: [restore] must measure the anchor
/// on a subsequent frame and report its actual viewport error <= 1 pixel.
class HistoryWindowTrimUiController<T extends Object, A extends Object> {
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isBusy => _busy;
  bool get isDisposed => _disposed;

  /// Invalidates an outstanding prepare or restore without pretending its
  /// asynchronous work has completed. The run policy decides whether an
  /// already committed window is retained or rolled back.
  void cancel() => _generation++;

  void dispose() {
    _disposed = true;
    cancel();
  }

  Future<HistoryWindowTrimUiOutcome> run({
    required bool Function() isCurrentAndIdle,
    required A? Function() capture,
    required Future<T?> Function(A anchor) prepare,
    required bool Function(T ticket) commit,
    required Future<void> Function() nextFrame,
    required bool Function(A anchor, int attempt) restore,
    required Future<bool> Function(T ticket) rollback,
    required void Function(T ticket) finish,
    void Function()? onWindowSettled,
    bool Function()? beginVisualUpdate,
    Future<void> Function()? endVisualUpdate,
    int maxRestoreFrames = 8,
    // A durable, bounded window remains usable even if its pixel anchor cannot
    // be restored. Interactive trims must not wait for storage rollback.
    bool rollbackOnRestoreFailure = true,
  }) async {
    if (_disposed || _busy || !isCurrentAndIdle()) {
      return HistoryWindowTrimUiOutcome.skipped;
    }
    final anchor = capture();
    if (anchor == null) return HistoryWindowTrimUiOutcome.skipped;
    _busy = true;
    final generation = ++_generation;
    bool current() =>
        !_disposed && generation == _generation && isCurrentAndIdle();
    T? ticket;
    var committed = false;
    var visualUpdateStarted = false;
    var restored = false;
    var outcome = HistoryWindowTrimUiOutcome.skipped;
    try {
      ticket = await prepare(anchor);
      if (ticket != null && current()) {
        if (beginVisualUpdate != null) {
          visualUpdateStarted = beginVisualUpdate();
          if (!visualUpdateStarted) return HistoryWindowTrimUiOutcome.skipped;
        }
        committed = commit(ticket);
        if (committed) {
          outcome = HistoryWindowTrimUiOutcome.rolledBack;
          for (var attempt = 0; attempt < maxRestoreFrames; attempt++) {
            await nextFrame();
            if (!current()) break;
            if (restore(anchor, attempt)) {
              restored = true;
              outcome = HistoryWindowTrimUiOutcome.restored;
              break;
            }
          }
        }
      }
    } catch (_) {
      // Storage/layout failures must not strand either a half-trimmed window
      // or its before/after message references. The caller can retry at idle.
      outcome = committed
          ? HistoryWindowTrimUiOutcome.rolledBack
          : HistoryWindowTrimUiOutcome.skipped;
    } finally {
      try {
        if (ticket != null &&
            committed &&
            !restored &&
            !rollbackOnRestoreFailure) {
          outcome = HistoryWindowTrimUiOutcome.keptCommitted;
        } else if (ticket != null && committed && !restored) {
          final rolledBack = await rollback(ticket);
          if (!rolledBack) outcome = HistoryWindowTrimUiOutcome.rollbackFailed;
          if (rolledBack && current()) {
            for (var attempt = 0; attempt < maxRestoreFrames; attempt++) {
              await nextFrame();
              if (!current() || restore(anchor, attempt)) break;
            }
          }
        }
      } catch (_) {
        outcome = HistoryWindowTrimUiOutcome.rollbackFailed;
      } finally {
        try {
          try {
            if (ticket != null) finish(ticket);
          } finally {
            // A failed rollback leaves the committed, smaller window in use.
            // Reconcile its cursors after releasing the transaction, even when
            // the pixel restore failed or a gesture cancelled the operation.
            if (committed) onWindowSettled?.call();
          }
        } finally {
          try {
            if (visualUpdateStarted) await endVisualUpdate?.call();
          } finally {
            _busy = false;
          }
        }
      }
    }
    return outcome;
  }
}

/// One bounded restoration step shared by the chat's real lazy sliver and
/// widget tests. [targetIndex] is resolved afresh from identity after each
/// layout, never copied from the pre-trim snapshot.
class HistoryWindowTrimViewportRestorer {
  static bool restore({
    required int? targetIndex,
    required double viewportTop,
    required ScrollPosition? position,
    required BuildContext? Function(int index) contextForIndex,
    required Iterable<int> mountedIndices,
    required void Function(double pixels) jumpTo,
    void Function()? correctMountedAnchor,
  }) {
    if (targetIndex == null ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return false;
    }
    bool ready(RenderObject? object) {
      if (object is! RenderBox || !object.attached || !object.hasSize) {
        return false;
      }
      var needsLayout = false;
      assert(() {
        needsLayout = object.debugNeedsLayout;
        return true;
      }());
      return !needsLayout;
    }

    final context = contextForIndex(targetIndex);
    final target = context?.findRenderObject();
    final viewport = context == null
        ? null
        : Scrollable.maybeOf(context)?.context.findRenderObject();
    if (ready(target) && ready(viewport)) {
      final top = (target as RenderBox)
          .localToGlobal(Offset.zero, ancestor: viewport as RenderBox)
          .dy;
      if ((top - viewportTop).abs() <= 1) return true;
      if (correctMountedAnchor != null) {
        correctMountedAnchor();
      } else {
        jumpTo(HistoryPaginationScrollPhysics.restorePixelsForViewportAnchor(
          axisDirection: position.axisDirection,
          currentPixels: position.pixels,
          currentAnchorTop: top,
          desiredAnchorTop: viewportTop,
          minScrollExtent: position.minScrollExtent,
          maxScrollExtent: position.maxScrollExtent,
        ));
      }
      // Verify after a real layout; issuing a clamped jump proves nothing.
      return false;
    }
    var closestDistance = double.infinity;
    double? estimate;
    for (final rowIndex in mountedIndices) {
      final row = contextForIndex(rowIndex)?.findRenderObject();
      if (!ready(row)) continue;
      final distance = (rowIndex - targetIndex).abs().toDouble();
      if (distance >= closestDistance) continue;
      closestDistance = distance;
      estimate = position.pixels +
          (targetIndex - rowIndex) *
              math.max(24, (row as RenderBox).size.height);
    }
    if (estimate != null) {
      jumpTo(
          estimate.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    return false;
  }
}
