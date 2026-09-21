import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/back_to_bottom_capsule_policy.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/true_latest_end.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/unread_tongue_policy.dart';

class TIMUIKitHistoryMessageListTongueContainer extends StatefulWidget {
  final TongueItemBuilder? tongueItemBuilder;
  final List<V2TimGroupAtInfo?>? groupAtInfoList;
  final List<V2TimMessage?> messageList;

  /// Returns true only when the @ target was centered (or already on screen).
  final Future<bool> Function(String targetSeq) scrollToIndexBySeq;
  final Future<bool> Function(int unreadCount) scrollToFirstUnread;
  final bool Function()? beginWindowTransition;
  final Future<void> Function()? finishWindowTransition;
  final AutoScrollController scrollController;
  final TUIChatSeparateViewModel model;
  final V2TimConversation conversation;

  /// Open-chat page SSOT for list position; when set, tongue prefers this over
  /// Global notify fan-out for position-only updates.
  final ValueListenable<HistoryMessagePosition>? pageHistoryPosition;

  /// Whether the trailing edge of the newest rendered row is in the viewport.
  /// This corrects transient/stale scroll extents after asynchronous row
  /// re-layout (images, long text, keyboard and continuous inbound pushes).
  final ValueListenable<bool>? latestMessageVisible;

  /// Re-measures the row edge at acknowledgement time. The listenable above
  /// may still describe the preceding frame while rows or the keyboard move.
  final bool Function()? verifyLatestMessageVisible;

  const TIMUIKitHistoryMessageListTongueContainer({
    Key? key,
    this.tongueItemBuilder,
    this.groupAtInfoList,
    required this.messageList,
    required this.conversation,
    required this.scrollToIndexBySeq,
    required this.scrollToFirstUnread,
    required this.scrollController,
    this.beginWindowTransition,
    this.finishWindowTransition,
    required this.model,
    this.pageHistoryPosition,
    this.latestMessageVisible,
    this.verifyLatestMessageVisible,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      TIMUIKitHistoryMessageListTongueContainerState();
}

class _TongueUnreadSelectorData {
  final HistoryMessagePosition messageListPosition;
  final bool followingLatest;
  final int unreadRemaining;
  final bool unreadBelow;
  final int lockedUnreadCount;
  final bool haveMoreLatestData;
  final bool memoryWindowMissingNewer;
  final bool durableDeferred;
  final bool returningToBottom;
  final int dismissedEntryUnread;

  /// 仍在缓冲区、尚未接入可见列表的新消息条数。
  final int bufferedCount;
  final int remainingLiveIncomingCount;

  const _TongueUnreadSelectorData({
    required this.messageListPosition,
    required this.followingLatest,
    required this.unreadRemaining,
    required this.unreadBelow,
    required this.lockedUnreadCount,
    required this.haveMoreLatestData,
    required this.memoryWindowMissingNewer,
    required this.durableDeferred,
    required this.returningToBottom,
    required this.dismissedEntryUnread,
    required this.bufferedCount,
    required this.remainingLiveIncomingCount,
  });
}

class TIMUIKitHistoryMessageListTongueContainerState
    extends TIMUIKitState<TIMUIKitHistoryMessageListTongueContainer> {
  bool isFinishJumpToAt = false;
  List<V2TimGroupAtInfo?>? groupAtInfoList = [];
  final TUIChatGlobalModel globalModel = serviceLocator<TUIChatGlobalModel>();
  bool isClickShowPrevious = false;
  bool _jumpingToFirstUnread = false;
  bool _entryUnreadCapsuleDismissed = false;
  bool _scrollFrameCallbackScheduled = false;
  ScrollPosition? _scrollEndListenerPosition;
  bool _showScrollToBottomCapsule = false;
  bool _scrollingToBottomInFlight = false;
  Completer<void>? _bottomReturnCancellation;
  static const _bottomReturnTimeout = Duration(seconds: 25);
  bool _userDraggedSinceLastSettle = false;
  int _conversationWidgetGeneration = 0;
  int _bottomScrollTransactionToken = 0;
  int _unreadJumpTransactionToken = 0;

  /// 用户主动上滑并超出一屏后为 true；贴底后清零。用来区分 list-push 程序滚动。
  bool _userLeftBottomIntentionally = false;
  HistoryMessagePosition? _lastReportedPosition;
  int _entryUnreadCount = 0;
  String _lastTongueDiagnosticState = '';

  /// 「回到底部」仅在离开底部超过约一屏时出现。
  static const double _capsuleShowViewportRatio =
      BackToBottomCapsulePolicy.showViewportRatio;

  /// 隐藏滞后，避免在阈值附近闪烁。
  static const double _capsuleHideViewportRatio =
      BackToBottomCapsulePolicy.hideViewportRatio;
  static const double _bottomEpsilon = TrueLatestEnd.geometryEpsilon;
  static const Duration _capsuleFadeDuration = Duration(milliseconds: 160);

  int get _previousUnreadCount =>
      _entryUnreadCapsuleDismissed ? 0 : _entryUnreadCount;

  int _resolveEntryUnreadCount() {
    final count =
        widget.model.initialUnreadCount ?? widget.conversation.unreadCount ?? 0;
    return count > 0 ? count : 0;
  }

  bool get _hasMissingNewer => TrueLatestEnd.hasMissingNewer(
        haveMoreLatestData: widget.model.haveMoreLatestData,
        memoryWindowMissingNewer:
            globalModel.memoryWindowMissingNewer(widget.model.conversationID),
        historyKnownTipMissing: widget.model.hasHistoryKnownTipMissing,
      );

  String _messageIdentity(V2TimMessage? message) {
    if (message == null) {
      return '';
    }
    final msgID = message.msgID?.trim() ?? '';
    if (msgID.isNotEmpty) {
      return msgID;
    }
    return message.id?.trim() ?? '';
  }

  V2TimMessage? _newestNonTimeDivider(Iterable<V2TimMessage?> messages) {
    for (final message in messages) {
      if (message != null && message.elemType != 11) {
        return message;
      }
    }
    return null;
  }

  V2TimMessage? _newestConfirmed(Iterable<V2TimMessage?> messages) {
    for (final message in messages) {
      if (message != null &&
          TUIChatGlobalModel.isConfirmedProjectionMessage(message)) {
        return message;
      }
    }
    return null;
  }

  bool get _latestRowMaterialized {
    final conv = widget.model.conversationID;
    final displayedNewest = _newestConfirmed(widget.messageList);
    final rawNewest = _newestConfirmed(
      globalModel.rawMessageList(conv) ?? const <V2TimMessage>[],
    );
    final displayedId = _messageIdentity(displayedNewest);
    final rawId = _messageIdentity(rawNewest);
    final latestConfirmedIdentityInBuiltList = displayedId.isNotEmpty &&
        (rawId.isEmpty || displayedId == rawId);
    return TrueLatestEnd.isLatestRowMaterialized(
      latestConfirmedIdentityInBuiltList: latestConfirmedIdentityInBuiltList,
    );
  }

  bool _atTrueLatestEndNow() {
    final conv = widget.model.conversationID;
    if (globalModel.deferredIncomingBufferedCount(conv) > 0 ||
        globalModel.unadmittedRemainingLiveCountFor(conv) > 0) {
      return false;
    }
    return TrueLatestEnd.atTrueLatestEnd(
      atListEnd: TrueLatestEnd.atListEndFromPosition(
        _singleScrollPositionOrNull(),
      ),
      latestRowMaterialized: _latestRowMaterialized,
      hasMissingNewer: _hasMissingNewer,
    );
  }

  ScrollPosition? _singleScrollPositionOrNull() {
    if (!widget.scrollController.hasClients ||
        widget.scrollController.positions.length != 1) {
      return null;
    }
    return widget.scrollController.position;
  }

  bool _isProgrammaticScrollToBottomActive() {
    return _scrollingToBottomInFlight ||
        globalModel.isUserScrollToBottomInProgress(widget.model.conversationID);
  }

  bool _isCurrentConversationGeneration(
    String conversationID,
    int conversationGeneration,
  ) {
    return mounted &&
        conversationGeneration == _conversationWidgetGeneration &&
        TUIChatGlobalModel.isSameConversationIdForHistory(
          widget.model.conversationID,
          conversationID,
        );
  }

  void _cancelScrollActivity(AutoScrollController controller) {
    if (!controller.hasClients) {
      return;
    }
    for (final position in controller.positions.toList()) {
      if (position.hasPixels) {
        // jumpTo the current pixels cancels an old animateTo future before the
        // reused controller can be driven by the next conversation.
        position.jumpTo(position.pixels);
      }
    }
  }

  void _cancelBottomReturn({bool stopScroll = true}) {
    final cancellation = _bottomReturnCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
      final position = _singleScrollPositionOrNull();
      // A drag already owns its activity. Stop only programmatic motion;
      // jumping here during a drag would kill the gesture.
      if (stopScroll && position != null &&
          position.userScrollDirection == ScrollDirection.idle) {
        _cancelScrollActivity(widget.scrollController);
      }
    }
  }

  void _settleLiveUnreadAtTrueLatestEnd() {
    _commitOverallFollowIfReady();
    _userLeftBottomIntentionally = false;
    if (mounted) {
      setState(() {
        _showScrollToBottomCapsule = false;
      });
    }
  }

  void _settleAtTrueLatestEnd() {
    _commitOverallFollowIfReady();
    _userLeftBottomIntentionally = false;
    widget.model.markMessageAsRead(force: true);
    if (mounted) {
      setState(() {
        _showScrollToBottomCapsule = false;
        _entryUnreadCapsuleDismissed = true;
        _entryUnreadCount = 0;
      });
    }
  }

  bool _commitOverallFollowIfReady() =>
      widget.model.commitFollowAfterVisibleLatestConfirm();

  Future<void> scrollToLatestAndDismissUnreadCapsule() async {
    if (_atTrueLatestEndNow()) {
      _settleAtTrueLatestEnd();
      return;
    }
    if (_scrollingToBottomInFlight) {
      ChatJitterDiag.logFollowingLatest(
        action: 'return_to_latest_skipped',
        conv: widget.model.conversationID,
        extras: <String, Object?>{
          'reason': 'in_flight',
          ...globalModel.stickToLatestDiagSnapshot(widget.model.conversationID),
        },
      );
      return;
    }
    final model = widget.model;
    final conversationID = model.conversationID;
    ChatJitterDiag.logFollowingLatest(
      action: 'return_to_latest_begin',
      conv: conversationID,
      extras: <String, Object?>{
        'hasMissingNewer': _hasMissingNewer,
        ...globalModel.stickToLatestDiagSnapshot(conversationID),
      },
    );
    final conversationGeneration = _conversationWidgetGeneration;
    final ownsConversation =
        globalModel.captureMessageOwnerFence(conversationID);
    bool ownsUI() =>
        ownsConversation() &&
        _isCurrentConversationGeneration(
            conversationID, conversationGeneration);
    final transactionToken = ++_bottomScrollTransactionToken;
    final scrollController = widget.scrollController;
    // The tap owns the next movement. Stop inertia left by the previous gesture
    // before opening the transaction, so it cannot masquerade as a new drag.
    _cancelScrollActivity(scrollController);
    final cancellation = Completer<void>();
    _bottomReturnCancellation = cancellation;
    bool isCurrent() => ownsUI() &&
        transactionToken == _bottomScrollTransactionToken &&
        !cancellation.isCompleted;
    final deadline = Timer(_bottomReturnTimeout, () {
      if (!cancellation.isCompleted) {
        ChatJitterDiag.logFollowingLatest(action: 'return_to_latest_timeout',
            conv: conversationID);
        cancellation.complete();
        if (ownsUI() && transactionToken == _bottomScrollTransactionToken) {
          _cancelScrollActivity(scrollController);
        }
      }
    });
    var returnedSuccessfully = false;
    _scrollingToBottomInFlight = true;
    var transitionStarted = false;
    var transitionFinished = false;
    var newestTargetReached = false;
    bool latestRenderedEdgeVisible() => _atTrueLatestEndNow();
    final finishTransition = widget.finishWindowTransition;
    Future<void> performReturn() async {
      final replaceWindow = _hasMissingNewer;

      // A disjoint latest-window reload may retain the old viewport while the
      // network result is laid out. Ordinary long-distance returns stay live so
      // users see the list accelerating toward the latest message.
      transitionStarted = replaceWindow;
      if (transitionStarted) {
        widget.beginWindowTransition?.call();
      }

      // Keep incoming messages visible for the whole return transaction. If
      // they are routed back into the away-from-bottom buffer, the target
      // keeps changing and continuous traffic can prevent this action from
      // ever reaching the latest row.
      globalModel.beginUserScrollToBottom(
        conversationID,
        lockMilliseconds: 2000,
      );
      if (mounted) {
        setState(() {
          _showScrollToBottomCapsule = false;
          _userLeftBottomIntentionally = false;
          isClickShowPrevious = false;
        });
      }
      // 内存窗口开启时，「回到底部」必须重拉最新一页。
      // 仅 animateTo(minExtent) 只会停在窗口内的假底部。
      if (_hasMissingNewer) {
        globalModel.beginUserScrollToBottom(
          conversationID,
          lockMilliseconds: 8000,
        );

        // A successful reload proves its finite captured watermark. Later
        // arrivals must not move that goal and starve the actual scroll.
        // Retry only failed/stale pages; surviving arrivals are revealed below.
        const maxNewestReloadAttempts = 3;
        var reloadedNewest = false;
        for (var attempt = 0; attempt < maxNewestReloadAttempts; attempt++) {
          try {
            reloadedNewest = await model.reloadNewestMessageWindow(
              allowWhileReadingHistory: true,
              cancelWhen: cancellation.future,
            );
          } catch (e) {
            reloadedNewest = false;
          }
          if (!isCurrent()) {
            return;
          }
          if (reloadedNewest) {
            await WidgetsBinding.instance.endOfFrame;
            if (!isCurrent()) {
              return;
            }
            newestTargetReached = true;
            break;
          }

          if (attempt + 1 < maxNewestReloadAttempts) {
            ChatJitterDiag.logFollowingLatest(
              action: 'bottom_capsule_reload_newest_retry',
              conv: conversationID,
              extras: <String, Object?>{'attempt': attempt + 1},
            );
            // Give the SDK callback / durable admission queued behind this
            // request one event-loop turn to publish its newest boundary.

            await Future<void>.delayed(const Duration(milliseconds: 80));
            if (!isCurrent()) {
              return;
            }
          }
        }
        if (!reloadedNewest) {
          if (mounted) {
            setState(() => _showScrollToBottomCapsule = true);
          }
          return;
        }
        await globalModel.revealDurableIncomingAfterLatestReturn(
          conversationID,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return;
      }

      // Reveal deferred rows before resolving the bottom scroll target. Doing
      // this after the scroll uses the old list extent and can leave the newly
      // revealed rows below the viewport. A notification is required because
      // projection-only reveals do not otherwise rebuild the message list.
      globalModel.flushPendingIncomingMessagesForUserBottom(conversationID);

      await WidgetsBinding.instance.endOfFrame;
      if (!isCurrent()) {
        return;
      }

      // Reveal the newly installed latest window before moving it. Keeping the
      // retained snapshot above animateTo would hide the scroll and look like
      // an instantaneous jump when the handoff finishes.
      if (transitionStarted) {
        await finishTransition?.call();
        transitionFinished = true;
        if (!isCurrent()) {
          return;
        }
      }

      // Flushing 5 displayed unread rows can expose 20 authoritative rows, and
      // more may arrive while scrolling. Re-resolve the latest edge after each
      // layout instead of animating once toward a stale geometry snapshot.
      const maxSettleAttempts = 6;
      for (var attempt = 0; attempt < maxSettleAttempts; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!isCurrent()) {
          return;
        }
        final position = _singleScrollPositionOrNull();
        if (position == null ||
            !position.hasPixels ||
            !position.hasContentDimensions) {
          break;
        }
        final target = position.minScrollExtent;
        final distance = (position.pixels - target).abs();

        if (distance <= 1.0) {
          // Require another completed frame at the edge. This catches rows
          // whose real height replaces a text/media placeholder one frame late.

          await WidgetsBinding.instance.endOfFrame;
          if (!isCurrent()) {
            return;
          }
          final verification = _singleScrollPositionOrNull();
          if (verification != null &&
              verification.hasPixels &&
              verification.hasContentDimensions &&
              (verification.pixels - verification.minScrollExtent).abs() <=
                  _bottomEpsilon) {
            break;
          }
          continue;
        }
        // Avoid restarting a long animation for tiny layout drift. Repeated
        // animations fighting list relayout are perceived as a shake.
        if (distance <= 8.0) {
          position.jumpTo(target);
          continue;
        }
        final animationMs = attempt == 0
            ? (180 + distance * 0.28).clamp(180.0, 420.0).round()
            : 100;
        globalModel.beginUserScrollToBottom(
          conversationID,
          lockMilliseconds: animationMs + 500,
        );
        try {
          await scrollController.animateTo(
            target,
            duration: Duration(milliseconds: animationMs),
            curve: Curves.easeInCubic,
          );
        } catch (_) {}
        if (!isCurrent()) {
          return;
        }
      }

      // A continuous stream can invalidate every animated attempt. Finish with
      // one short, frame-aligned animation; jumpTo here causes a visible flash
      // when message heights settle during the return transaction.

      await WidgetsBinding.instance.endOfFrame;
      if (!isCurrent()) {
        return;
      }
      final finalPosition = _singleScrollPositionOrNull();
      if (finalPosition != null &&
          finalPosition.hasPixels &&
          finalPosition.hasContentDimensions &&
          (finalPosition.pixels - finalPosition.minScrollExtent).abs() >
              _bottomEpsilon) {
        final correctionDistance =
            (finalPosition.pixels - finalPosition.minScrollExtent).abs();
        final correctionMs =
            (100 + correctionDistance * 0.2).clamp(100.0, 220.0).round();
        try {
          await scrollController.animateTo(
            finalPosition.minScrollExtent,
            duration: Duration(milliseconds: correctionMs),
            curve: Curves.easeInCubic,
          );
        } catch (_) {}
        if (!isCurrent()) {
          return;
        }

        await WidgetsBinding.instance.endOfFrame;
        if (!isCurrent()) {
          return;
        }
      }

      final settledPosition = _singleScrollPositionOrNull();
      final reachedBottom = settledPosition != null &&
          settledPosition.hasPixels &&
          settledPosition.hasContentDimensions &&
          (settledPosition.pixels - settledPosition.minScrollExtent).abs() <=
              _bottomEpsilon;
      if (!reachedBottom) {
        if (mounted) {
          setState(() {
            _showScrollToBottomCapsule = true;
          });
        }
        return;
      }

      // A coalescer timer or a late layout callback may have delivered another
      // batch after the first drain. Drain once more while the transaction gate
      // is still held, then let the final geometry settle before clearing read
      // state. This prevents buffered rows from being cleared as "read".
      final drainedAfterScroll =
          globalModel.flushPendingIncomingMessagesForUserBottom(conversationID);
      if (drainedAfterScroll) {
        await WidgetsBinding.instance.endOfFrame;
        if (!isCurrent()) {
          return;
        }
        final postDrainPosition = _singleScrollPositionOrNull();
        if (postDrainPosition != null &&
            postDrainPosition.hasPixels &&
            postDrainPosition.hasContentDimensions &&
            (postDrainPosition.pixels - postDrainPosition.minScrollExtent)
                    .abs() >
                _bottomEpsilon) {
          try {
            await scrollController.animateTo(
              postDrainPosition.minScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInCubic,
            );
          } catch (_) {}
          if (!isCurrent()) {
            return;
          }

          await WidgetsBinding.instance.endOfFrame;
          if (!isCurrent()) {
            return;
          }
        }
      }

      if (_atTrueLatestEndNow()) {
        _settleAtTrueLatestEnd();
        returnedSuccessfully = true;
        return;
      }

      if (newestTargetReached &&
          globalModel.canRevealDurableIncomingAfterLatestReturn(conversationID)) {
        final displayedRevision =
            globalModel.messageListRevisionFor(conversationID);
        // A raw row may still be excluded by the current page projection.
        // Only identities actually installed in this list can prove reading.
        final displayed = widget.messageList.whereType<V2TimMessage>().toList();
        final displayedIDs = displayed.map((message) => message.msgID).toList();
        // Capture before requesting layout, then require that very revision to
        // remain installed. An arrival committed after this frame is not read.
        await WidgetsBinding.instance.endOfFrame;
        if (!isCurrent()) return;
        try {
          await globalModel.acknowledgeVisibleHistoryMessages(
            conversationID,
            displayed,
            isCurrent: () {
              final position = _singleScrollPositionOrNull();
              return isCurrent() &&
                  globalModel.canRevealDurableIncomingAfterLatestReturn(
                    conversationID,
                  ) &&
                  globalModel.messageListRevisionFor(conversationID) ==
                      displayedRevision &&
                  listEquals(
                    displayedIDs,
                    widget.messageList
                        .whereType<V2TimMessage>()
                        .map((message) => message.msgID)
                        .toList(),
                  ) &&
                  TrueLatestEnd.atListEndFromPosition(position);
            },
          );
        } catch (_) {
          // Layout/owner changes invalidate this reading proof. The durable
          // ledger remains authoritative and the reminder stays retryable.
        }
        if (!isCurrent()) return;
      }
      if (_hasMissingNewer) {
        returnedSuccessfully = newestTargetReached;
        if (globalModel
            .canRevealDurableIncomingAfterLatestReturn(conversationID)) {
          _commitOverallFollowIfReady();
        }
        setState(() => _showScrollToBottomCapsule = true);
        return;
      }

      ChatJitterDiag.logFollowingLatest(
        action: 'return_to_latest_ok',
        conv: conversationID,
        extras: globalModel.stickToLatestDiagSnapshot(conversationID),
      );
      _settleAtTrueLatestEnd();
      globalModel.unlockEntryUnreadForTongue(
        conversationID: conversationID,
        notify: false,
      );
      var dismissedUnreadCount = _entryUnreadCount;
      if (globalModel.unreadCountForTongue > dismissedUnreadCount) {
        dismissedUnreadCount = globalModel.unreadCountForTongue;
      }
      final currentRemaining =
          globalModel.getUnreadTongueRemaining(conversationID);
      if (currentRemaining > dismissedUnreadCount) {
        dismissedUnreadCount = currentRemaining;
      }
      globalModel.markEntryUnreadTongueDismissed(
        conversationID: conversationID,
        unreadCount: dismissedUnreadCount,
        notify: false,
      );
      globalModel.clearUnreadTongueMetrics(
        conversationID,
        notify: false,
      );
      changePositionStateForConversation(
        conversationID,
        HistoryMessagePosition.bottom,
      );
      returnedSuccessfully = true;
    }
    try {
      await Future.any<void>([performReturn(), cancellation.future]);
    } catch (_) {
      if (ownsUI()) {
        final keepAfford = !_atTrueLatestEndNow();
        setState(() {
          _showScrollToBottomCapsule = keepAfford;
          if (keepAfford) {
            _userLeftBottomIntentionally = true;
          }
        });
      }
      rethrow;
    } finally {
      deadline.cancel();
      if (!cancellation.isCompleted) cancellation.complete();
      try {
        if (transitionStarted && !transitionFinished) {
          await finishTransition?.call().timeout(const Duration(seconds: 1),
              onTimeout: () {});
        }
      } finally {
        if (identical(_bottomReturnCancellation, cancellation)) {
          _bottomReturnCancellation = null;
        }
        if (transactionToken == _bottomScrollTransactionToken) {
          if (mounted) {
            final atEnd = _atTrueLatestEndNow();
            setState(() {
              _scrollingToBottomInFlight = false;
              if (atEnd) {
                _showScrollToBottomCapsule = false;
                _userLeftBottomIntentionally = false;
              } else if (!returnedSuccessfully) {
                _showScrollToBottomCapsule = true;
                _userLeftBottomIntentionally = true;
              }
            });
          } else {
            _scrollingToBottomInFlight = false;
          }
        }
        if (transactionToken == _bottomScrollTransactionToken && ownsUI()) {
          globalModel.endUserScrollToBottom(conversationID);
        }
      }
    }
  }

  Future<void> _jumpToFirstUnreadMessage(int unreadCount) async {
    if (_jumpingToFirstUnread ||
        unreadCount < UnreadTonguePolicy.entryMinUnreadCount) {
      return;
    }
    final conversationID = widget.model.conversationID;
    final conversationGeneration = _conversationWidgetGeneration;
    final ownsConversation =
        globalModel.captureMessageOwnerFence(conversationID);
    final transactionToken = ++_unreadJumpTransactionToken;
    _jumpingToFirstUnread = true;
    try {
      final didScroll = await widget.scrollToFirstUnread(unreadCount);
      if (!ownsConversation() ||
          !_isCurrentConversationGeneration(
            conversationID,
            conversationGeneration,
          )) {
        return;
      }
      if (!didScroll) {
        return;
      }
      // 点过入口「xxx条未读」后：提示立刻消失；离底时底部只保留「回到底部」，
      // 不再把同一批入口未读改成右下角「xxx条新消息」。
      var dismissedUnreadCount = unreadCount;
      if (_entryUnreadCount > dismissedUnreadCount) {
        dismissedUnreadCount = _entryUnreadCount;
      }
      if (globalModel.unreadCountForTongue > dismissedUnreadCount) {
        dismissedUnreadCount = globalModel.unreadCountForTongue;
      }
      final remaining = globalModel.getUnreadTongueRemaining(conversationID);
      if (remaining > dismissedUnreadCount) {
        dismissedUnreadCount = remaining;
      }
      globalModel.releaseEntryUnreadReminder(conversationID);
      globalModel.markEntryUnreadTongueDismissed(
        conversationID: conversationID,
        unreadCount: dismissedUnreadCount,
        notify: false,
      );
      globalModel.clearUnreadTongueMetrics(
        conversationID,
        notify: false,
      );
      changePositionStateForConversation(
        conversationID,
        HistoryMessagePosition.awayTwoScreen,
      );
      if (mounted) {
        setState(() {
          isClickShowPrevious = true;
          _entryUnreadCapsuleDismissed = true;
          _entryUnreadCount = 0;
        });
      } else {
        isClickShowPrevious = true;
        _entryUnreadCapsuleDismissed = true;
        _entryUnreadCount = 0;
      }
    } finally {
      if (transactionToken == _unreadJumpTransactionToken) {
        _jumpingToFirstUnread = false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _entryUnreadCount = _resolveEntryUnreadCount();
    _attachScrollListeners();
    groupAtInfoList = widget.groupAtInfoList?.reversed.toList();
  }

  @override
  void didUpdateWidget(
      covariant TIMUIKitHistoryMessageListTongueContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final conversationChanged =
        !TUIChatGlobalModel.isSameConversationIdForHistory(
              oldWidget.model.conversationID,
              widget.model.conversationID,
            ) ||
            oldWidget.conversation.conversationID !=
                widget.conversation.conversationID ||
            !identical(oldWidget.model, widget.model);
    if (conversationChanged) {
      final oldConversationID = oldWidget.model.conversationID;
      _cancelBottomReturn(stopScroll: false);
      if (_scrollingToBottomInFlight) {
        _cancelScrollActivity(oldWidget.scrollController);
      }
      _conversationWidgetGeneration++;
      _bottomScrollTransactionToken++;
      _unreadJumpTransactionToken++;
      globalModel.endUserScrollToBottom(oldConversationID);
      _detachScrollEndListener();
      oldWidget.scrollController.removeListener(_onScrollControllerChanged);
      _scrollingToBottomInFlight = false;
      _userDraggedSinceLastSettle = false;
      isClickShowPrevious = false;
      _jumpingToFirstUnread = false;
      _entryUnreadCapsuleDismissed = false;
      _entryUnreadCount = _resolveEntryUnreadCount();
      _lastReportedPosition = null;
      _lastTongueDiagnosticState = '';
      _showScrollToBottomCapsule = false;
      _userLeftBottomIntentionally = false;
      groupAtInfoList = widget.groupAtInfoList?.reversed.toList();
      _attachScrollListeners();
      return;
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScrollControllerChanged);
      _detachScrollEndListener();
      _attachScrollListeners();
    }
  }

  void changePositionState(HistoryMessagePosition newPosition) {
    changePositionStateForConversation(
        widget.model.conversationID, newPosition);
  }

  void changePositionStateForConversation(
    String conversationID,
    HistoryMessagePosition newPosition,
  ) {
    if (_lastReportedPosition == newPosition) {
      return;
    }
    final before = globalModel.getMessageListPosition(conversationID);
    if (before != newPosition) {
      globalModel.setMessageListPosition(conversationID, newPosition);
      final after = globalModel.getMessageListPosition(conversationID);
      // The global model may reject a transient bottom observation while a
      // pagination prepend is restoring its anchor. Do not cache the rejected
      // value locally or the tongue would suppress the next real update.
      if (after == newPosition) {
        _lastReportedPosition = newPosition;
      }
    }
  }

  double _distanceFromBottom(ScrollPosition position) {
    return position.pixels - position.minScrollExtent;
  }

  double _oneScreenThreshold(ScrollPosition position) {
    final viewport = position.viewportDimension;
    if (viewport <= 0) {
      return 600.0;
    }
    return viewport * _capsuleShowViewportRatio;
  }

  bool _hasScrolledPastDistanceThreshold(ScrollPosition position) {
    return _distanceFromBottom(position) > _oneScreenThreshold(position);
  }

  bool _computeScrollToBottomCapsuleVisible(ScrollPosition position) {
    if (globalModel
            .isInboundPresentationBottomLocked(widget.model.conversationID) ||
        globalModel.isOpenChatBottomCapsuleLocked(widget.model.conversationID)) {
      return false;
    }
    if (_isProgrammaticScrollToBottomActive()) {
      return false;
    }
    if (widget.model.isLoadingChatHistory || widget.messageList.length <= 1) {
      return false;
    }
    if (_atTrueLatestEndNow()) {
      _userLeftBottomIntentionally = false;
      return false;
    }
    if (_hasMissingNewer) {
      return true;
    }
    return BackToBottomCapsulePolicy.shouldShow(
      atTrueLatestEnd: false,
      hasMissingNewer: false,
      distanceFromLatestEdge: _distanceFromBottom(position),
      viewportDimension: position.viewportDimension,
      capsuleCurrentlyVisible: _showScrollToBottomCapsule,
      presentationBottomLocked: false,
      programmaticScrollToBottom: false,
    );
  }

  HistoryMessagePosition _resolveScrollPositionSettled(double offset) {
    final position = _singleScrollPositionOrNull();
    if (position != null &&
        globalModel.isPaginationRestoreTransientNearBottom(
          widget.model.conversationID,
          position,
        )) {
      return globalModel.getMessageListPosition(widget.model.conversationID);
    }
    if (globalModel
        .isInboundPresentationBottomLocked(widget.model.conversationID)) {
      return HistoryMessagePosition.bottom;
    }
    if (position == null) {
      return globalModel.getMessageListPosition(widget.model.conversationID);
    }
    if (offset <= position.minScrollExtent + _bottomEpsilon &&
        !position.outOfRange &&
        !_hasMissingNewer) {
      return HistoryMessagePosition.bottom;
    }
    if (!position.outOfRange) {
      if (_hasScrolledPastDistanceThreshold(position)) {
        return HistoryMessagePosition.awayTwoScreen;
      }
      if (offset > position.minScrollExtent + _bottomEpsilon) {
        return HistoryMessagePosition.inTwoScreen;
      }
    }
    return globalModel.getMessageListPosition(widget.model.conversationID);
  }

  void _setScrollToBottomCapsuleVisible(bool nextVisible) {
    if (_showScrollToBottomCapsule == nextVisible || !mounted) {
      return;
    }
    setState(() {
      _showScrollToBottomCapsule = nextVisible;
    });
  }

  void _applyScrollTick() {
    if (_isProgrammaticScrollToBottomActive() ||
        globalModel
            .isInboundPresentationBottomLocked(widget.model.conversationID) ||
        globalModel.isOpenChatBottomCapsuleLocked(widget.model.conversationID)) {
      _setScrollToBottomCapsuleVisible(false);
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null) {
      return;
    }
    if (globalModel.isChatListUserScrolling) {
      _userDraggedSinceLastSettle = true;
    }
    _setScrollToBottomCapsuleVisible(
      _computeScrollToBottomCapsuleVisible(position),
    );
  }

  void _maybeMarkLatestUnreadOnSettle(double offset) {
    final position = _singleScrollPositionOrNull();
    final reachedBottomByUser =
        (_userDraggedSinceLastSettle || globalModel.isChatListUserScrolling) &&
            position != null &&
            offset <= position.minScrollExtent + _bottomEpsilon;
    _userDraggedSinceLastSettle = false;
    if (reachedBottomByUser) {
      if (_hasMissingNewer) {
        ChatJitterDiag.logFollowingLatest(
          action: 'settle_wait_for_contiguous_page',
          conv: widget.model.conversationID,
          extras: globalModel.stickToLatestDiagSnapshot(
            widget.model.conversationID,
          ),
        );
        // This is the edge of a loaded page, not an explicit request to skip
        // to the live tip. The list owns contiguous newer-page loading.
        return;
      }
      ChatJitterDiag.logFollowingLatest(
        action: 'settle_quiet_restore',
        conv: widget.model.conversationID,
        extras: globalModel.stickToLatestDiagSnapshot(
          widget.model.conversationID,
        ),
      );
      if (globalModel.isAttachingBufferedTowardLatest) {
        ChatJitterDiag.logFollowingLatest(
          action: 'settle_restore_held',
          conv: widget.model.conversationID,
          extras: <String, Object?>{
            'attaching': globalModel.isAttachingBufferedTowardLatest,
            'ready': widget.model.isLiveRestoreDataReady,
            'buffered': globalModel.deferredIncomingBufferedCount(
              widget.model.conversationID,
            ),
          },
        );
        return;
      }
      if (!widget.model.isLiveRestoreDataReady) {
        return;
      }
      final conversationID = widget.model.conversationID;
      if (globalModel.deferredIncomingBufferedCount(conversationID) > 0) {
        widget.model.revealBufferedIncomingTowardLatest(skipCooldown: true);
        return;
      }
      _commitOverallFollowIfReady();
      final lockedBefore =
          globalModel.lockedEntryUnreadCountFor(conversationID);
      globalModel.unlockEntryUnreadForTongue(
        conversationID: conversationID,
        notify: false,
      );
      var dismissedUnreadCount = _entryUnreadCount;
      if (globalModel.unreadCountForTongue > dismissedUnreadCount) {
        dismissedUnreadCount = globalModel.unreadCountForTongue;
      }
      final currentRemaining =
          globalModel.getUnreadTongueRemaining(conversationID);
      if (currentRemaining > dismissedUnreadCount) {
        dismissedUnreadCount = currentRemaining;
      }
      globalModel.markEntryUnreadTongueDismissed(
        conversationID: conversationID,
        unreadCount: dismissedUnreadCount,
        notify: false,
      );
      globalModel.clearUnreadTongueMetrics(conversationID, notify: false);
      ChatJitterDiag.logFollowingLatest(
        action: 'settle_quiet_unlock',
        conv: conversationID,
        extras: <String, Object?>{
          'lockedBefore': lockedBefore,
          'lockedAfter': globalModel.lockedEntryUnreadCountFor(conversationID),
          'dismissed': dismissedUnreadCount,
        },
      );
      _userLeftBottomIntentionally = false;
      if (mounted) {
        setState(() {
          _entryUnreadCapsuleDismissed = true;
          _entryUnreadCount = 0;
          _showScrollToBottomCapsule = false;
        });
      }
      widget.model.markMessageAsRead(force: true);
      globalModel.notifyListeners();
      return;
    }
    // A user return reloads missing newer data through the transaction above.
    // A layout-only observation of an older window edge cannot mark it read.
    if (_hasMissingNewer) return;
    final conversationUnreadCount = widget.model.getConversationUnreadCount();
    final shouldKeepEntryUnreadCapsule =
        (globalModel.hasLockedEntryUnreadFor(widget.model.conversationID) ||
                _previousUnreadCount > 0) &&
            !isClickShowPrevious;
    if (offset > 0.0 ||
        conversationUnreadCount == 0 ||
        globalModel.isChatListUserScrolling ||
        shouldKeepEntryUnreadCapsule ||
        globalModel.hasLockedEntryUnreadFor(widget.model.conversationID)) {
      return;
    }
    globalModel.unlockEntryUnreadForTongue(
      conversationID: widget.model.conversationID,
      notify: false,
    );
    globalModel.flushDeferredIncomingMessages(
      widget.model.conversationID,
      notify: false,
    );
    globalModel.clearReceivedUnreadState(
      conversationID: widget.model.conversationID,
      notify: false,
    );
    widget.model.markMessageAsRead(force: true);
  }

  void _applyScrollSettledState() {
    if (!mounted || _isProgrammaticScrollToBottomActive()) {
      return;
    }
    if (globalModel
        .isInboundPresentationBottomLocked(widget.model.conversationID)) {
      changePositionState(HistoryMessagePosition.bottom);
      _setScrollToBottomCapsuleVisible(false);
      return;
    }
    if (globalModel.isOpenChatBottomCapsuleLocked(widget.model.conversationID)) {
      _setScrollToBottomCapsuleVisible(false);
      return;
    }
    final position = _singleScrollPositionOrNull();
    if (position == null) {
      return;
    }
    final offset = position.pixels;
    if (globalModel.isPaginationRestoreTransientNearBottom(
      widget.model.conversationID,
      position,
    )) {
      // isScrollingNotifier can settle during the temporary zero-pixels
      // layout gap. Avoid marking unread as read or changing the logical
      // position until the pagination transaction has a real viewport.
      ChatHistoryTrace.log(
        'tongue_settle_ignored_pagination_restore',
        conversationID: widget.model.conversationID,
        extras: <String, Object?>{
          'pixels': offset.toStringAsFixed(1),
          'minExtent': position.minScrollExtent.toStringAsFixed(1),
          'maxExtent': position.maxScrollExtent.toStringAsFixed(1),
        },
      );
      return;
    }
    _maybeMarkLatestUnreadOnSettle(offset);
    changePositionState(_resolveScrollPositionSettled(offset));
    _setScrollToBottomCapsuleVisible(
      _computeScrollToBottomCapsuleVisible(position),
    );
  }

  void _onScrollingActivityChanged() {
    final position = _scrollEndListenerPosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    _applyScrollSettledState();
  }

  void _attachScrollEndListener(ScrollPosition position) {
    if (_scrollEndListenerPosition == position) {
      return;
    }
    _detachScrollEndListener();
    _scrollEndListenerPosition = position;
    position.isScrollingNotifier.addListener(_onScrollingActivityChanged);
  }

  void _detachScrollEndListener() {
    _scrollEndListenerPosition?.isScrollingNotifier
        .removeListener(_onScrollingActivityChanged);
    _scrollEndListenerPosition = null;
  }

  void _attachScrollListeners() {
    widget.scrollController.addListener(_onScrollControllerChanged);
    final position = _singleScrollPositionOrNull();
    if (position != null) {
      _attachScrollEndListener(position);
    }
  }

  void _detachScrollListeners() {
    _detachScrollEndListener();
    widget.scrollController.removeListener(_onScrollControllerChanged);
  }

  void _onScrollControllerChanged() {
    final position = _singleScrollPositionOrNull();
    // userScrollDirection also remains non-idle during old ballistic motion.
    // Inspect the activity to distinguish a fresh drag from inertia/animateTo.
    if (position != null &&
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        position.activity is DragScrollActivity) {
      _cancelBottomReturn();
    }
    if (position != null) {
      _attachScrollEndListener(position);
    }
    if (_scrollFrameCallbackScheduled) {
      return;
    }
    _scrollFrameCallbackScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _scrollFrameCallbackScheduled = false;
      if (mounted) {
        _applyScrollTick();
      }
    });
  }

  int _resolveDisplayUnreadCount(
      int unreadRemaining, int liveUnreadCount) {
    var result = unreadRemaining;
    if (UnreadTonguePolicy.isLiveNewMessageTongueEnabled(
          unreadCount: liveUnreadCount,
        ) &&
        liveUnreadCount > result) {
      result = liveUnreadCount;
    }
    if (globalModel.hasLockedEntryUnreadFor(widget.model.conversationID)) {
      final locked = globalModel.lockedEntryUnreadCount;
      if (locked > result) {
        result = locked;
      }
    }
    final previous = _previousUnreadCount;
    if (previous > result) {
      result = previous;
    }
    return result;
  }

  MessageListTongueType _getTongueValueType(
    HistoryMessagePosition messageListPosition,
    List<V2TimGroupAtInfo?>? groupAtInfoList, {
    required int unreadRemaining,
    required int liveUnreadCount,
    required bool unreadBelow,
  }) {
    if (messageListPosition == HistoryMessagePosition.notShowLatest &&
        globalModel.hasPendingScrollRestore(widget.model.conversationID)) {
      return MessageListTongueType.none;
    }
    if (groupAtInfoList != null &&
        groupAtInfoList.isNotEmpty &&
        !isFinishJumpToAt) {
      if (groupAtInfoList[0]!.atType == 1) {
        return MessageListTongueType.atMe;
      } else {
        return MessageListTongueType.atAll;
      }
    }

    final entryTipActive = !_entryUnreadCapsuleDismissed &&
        globalModel.getDismissedEntryUnreadTongueCount(
                widget.model.conversationID) <
            _entryUnreadCount &&
        !isClickShowPrevious &&
        UnreadTonguePolicy.isEntryUnreadEnabled(
          widget.conversation,
          _entryUnreadCount,
        ) &&
        (globalModel.hasLockedEntryUnreadFor(widget.model.conversationID) ||
            _previousUnreadCount > 0 ||
            unreadRemaining > 0);

    // 入口「xxx条未读」未点掉前：始终按入口未读处理。
    // 绝不能因上滑把同一批未读改成右下角「xxx条新消息」。
    if (entryTipActive) {
      return MessageListTongueType.showPrevious;
    }

    if (UnreadTonguePolicy.isLiveNewMessageTongueEnabled(
          unreadCount: liveUnreadCount,
        ) &&
        liveUnreadCount > 0 &&
        messageListPosition != HistoryMessagePosition.bottom) {
      return MessageListTongueType.showUnread;
    }

    return MessageListTongueType.none;
  }

  MessageListTongueType _bottomCapsuleTypeWhenScrolledUp(int receivedCount) {
    // Entry reminders and messages received after entry are independent.
    return receivedCount > 0
        ? MessageListTongueType.showUnread
        : MessageListTongueType.toLatest;
  }

  int _liveCapsuleDisplayCount(_TongueUnreadSelectorData data) {
    return data.remainingLiveIncomingCount;
  }

  Future<void> _onBottomCapsuleTap(
    MessageListTongueType bottomType,
    int unreadCount,
  ) async {
    ChatJitterDiag.logFollowingLatest(
      action: 'capsule_tap',
      conv: widget.model.conversationID,
      extras: <String, Object?>{
        'bottomType': bottomType.name,
        'unreadCount': unreadCount,
        ...globalModel.stickToLatestDiagSnapshot(widget.model.conversationID),
      },
    );
    if (bottomType == MessageListTongueType.showPrevious) {
      await _jumpToFirstUnreadMessage(unreadCount);
      return;
    }
    await scrollToLatestAndDismissUnreadCapsule();
  }

  Widget _buildTongue({
    required MessageListTongueType valueType,
    required int previousCount,
    required int unreadCount,
    required VoidCallback onClick,
    String atNum = '',
  }) {
    return TIMUIKitHistoryMessageListTongue(
      previousCount: previousCount,
      tongueItemBuilder: widget.tongueItemBuilder,
      unreadCount: unreadCount,
      onClick: onClick,
      atNum: atNum,
      valueType: valueType,
    );
  }

  Widget _buildBottomCapsule({
    required bool visible,
    required MessageListTongueType valueType,
    required int displayUnreadCount,
    required Future<void> Function() onTap,
    required String atNum,
  }) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: _capsuleFadeDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.25),
          duration: _capsuleFadeDuration,
          curve: Curves.easeOutCubic,
          child: SafeArea(
            top: false,
            left: false,
            child: _buildTongue(
              previousCount: displayUnreadCount,
              unreadCount: displayUnreadCount,
              onClick: () {
                onTap();
              },
              atNum: atNum,
              valueType: valueType,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelBottomReturn(stopScroll: false);
    _conversationWidgetGeneration++;
    _bottomScrollTransactionToken++;
    _unreadJumpTransactionToken++;
    if (_scrollingToBottomInFlight) {
      _cancelScrollActivity(widget.scrollController);
    }
    globalModel.endUserScrollToBottom(widget.model.conversationID);
    _detachScrollListeners();
    super.dispose();
  }

  Widget _buildTongueSelector({HistoryMessagePosition? pagePosition}) {
    return Selector<TUIChatGlobalModel, _TongueUnreadSelectorData>(
      builder: (context, selectorData, child) {
        final unreadRemaining = selectorData.unreadRemaining;
        // All live presentation uses the visit's unseen identity ledger.
        // The durable/legacy received scalar belongs to data acknowledgement.
        final liveUnreadCount = _liveCapsuleDisplayCount(selectorData);
        final presentationBottomLocked = globalModel
                .isInboundPresentationBottomLocked(widget.model.conversationID) ||
            globalModel
                .isOpenChatBottomCapsuleLocked(widget.model.conversationID);
        final logicalPosition = presentationBottomLocked
            ? HistoryMessagePosition.bottom
            : selectorData.messageListPosition;
        final valueType = _getTongueValueType(
          logicalPosition,
          groupAtInfoList,
          unreadRemaining: unreadRemaining,
          liveUnreadCount: liveUnreadCount,
          unreadBelow: selectorData.unreadBelow,
        );
        final displayUnreadCount = valueType == MessageListTongueType.showUnread
            ? liveUnreadCount
            : valueType == MessageListTongueType.showPrevious
                ? _entryUnreadCount
                : _resolveDisplayUnreadCount(unreadRemaining, liveUnreadCount);
        final isAtTongue = valueType == MessageListTongueType.atMe ||
            valueType == MessageListTongueType.atAll;
        final isEntryUnreadTip =
            valueType == MessageListTongueType.showPrevious;
        // 入口未读：右上角保持「xxx条未读」，上滑也不改成「新消息」。
        // 贴底或轻离底都可点；真正离开底部时右下角另给「回到底部」。
        final showEntryUnreadAtTop = isEntryUnreadTip && !isAtTongue;
        final scrolledUpBottomType =
            _bottomCapsuleTypeWhenScrolledUp(liveUnreadCount);
        final livePosition = _singleScrollPositionOrNull();
        final atListEnd = TrueLatestEnd.atListEndFromPosition(livePosition);
        final latestRowMaterialized = _latestRowMaterialized;
        final missingNewer = _hasMissingNewer;
        final atTrueLatestEnd = TrueLatestEnd.atTrueLatestEnd(
          atListEnd: atListEnd,
          latestRowMaterialized: latestRowMaterialized,
          hasMissingNewer: missingNewer,
        );
        if (atTrueLatestEnd) {
          _userLeftBottomIntentionally = false;
          if (liveUnreadCount > 0 ||
              selectorData.bufferedCount > 0 ||
              !selectorData.followingLatest) {
            final conv = widget.model.conversationID;
            final canAutoSettle =
                !globalModel.isMessageContextMenuOverlayOpen &&
                    !globalModel.isContextMenuViewportRestoreActive(conv) &&
                    !globalModel.isSearchJumpPending(conv) &&
                    !widget.model.isLoadingChatHistory &&
                    !globalModel.shouldLockChatScrollForMediaPreview &&
                    ModalRoute.of(context)?.isCurrent != false;
            if (canAutoSettle) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _atTrueLatestEndNow()) {
                  _settleLiveUnreadAtTrueLatestEnd();
                }
              });
            }
          }
        }
        final showScrolledUpBottomCapsule = !isAtTongue &&
            !presentationBottomLocked &&
            !_isProgrammaticScrollToBottomActive() &&
            BackToBottomCapsulePolicy.shouldShow(
              atTrueLatestEnd: atTrueLatestEnd,
              hasMissingNewer: missingNewer,
              distanceFromLatestEdge: livePosition == null
                  ? 0
                  : (livePosition.pixels - livePosition.minScrollExtent),
              viewportDimension: livePosition?.hasContentDimensions == true
                  ? livePosition!.viewportDimension
                  : 0,
              capsuleCurrentlyVisible: _showScrollToBottomCapsule,
              presentationBottomLocked: presentationBottomLocked,
              programmaticScrollToBottom:
                  _isProgrammaticScrollToBottomActive(),
            );
        final diagnosticState = '${valueType.name}|'
            '${selectorData.messageListPosition.name}|'
            '$displayUnreadCount|$showEntryUnreadAtTop|'
            '$showScrolledUpBottomCapsule|${selectorData.haveMoreLatestData}|'
            '${selectorData.memoryWindowMissingNewer}|$atTrueLatestEnd|'
            '$_userLeftBottomIntentionally|'
            '${livePosition?.hasContentDimensions == true ? livePosition!.viewportDimension.toStringAsFixed(1) : 'n/a'}';
        if (_lastTongueDiagnosticState != diagnosticState) {
          _lastTongueDiagnosticState = diagnosticState;
          final position = _singleScrollPositionOrNull();
          ChatJitterDiag.logInboundFlow(
            action: 'tongue_state',
            conv: widget.model.conversationID,
            extras: <String, Object?>{
              'type': valueType.name,
              'bottomType': scrolledUpBottomType.name,
              'logicalPosition': logicalPosition.name,
              'rawLogicalPosition': selectorData.messageListPosition.name,
              'displayUnread': displayUnreadCount,
              'remaining': unreadRemaining,
              'entryTopVisible': showEntryUnreadAtTop,
              'bottomVisible': showScrolledUpBottomCapsule,
              'haveMoreLatestData': selectorData.haveMoreLatestData,
              'memoryWindowMissingNewer': selectorData.memoryWindowMissingNewer,
              'atTrueLatestEnd': atTrueLatestEnd,
              'atListEnd': atListEnd,
              'latestRowMaterialized': latestRowMaterialized,
              'hasMissingNewer': missingNewer,
              'leftBottomByOneScreen': _userLeftBottomIntentionally,
              'viewportDimension': livePosition?.hasContentDimensions == true
                  ? livePosition!.viewportDimension.toStringAsFixed(1)
                  : 'n/a',
              'presentationLocked':
                  globalModel.isInboundPresentationBottomLocked(
                      widget.model.conversationID),
              'pixels': position?.hasPixels == true
                  ? position!.pixels.toStringAsFixed(1)
                  : 'n/a',
              'minExtent': position?.hasContentDimensions == true
                  ? position!.minScrollExtent.toStringAsFixed(1)
                  : 'n/a',
            },
          );
        }
        final atNum = groupAtInfoList?.length.toString() ?? '';
        return SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (isAtTongue)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.15,
                  right: 0,
                  child: _buildTongue(
                    previousCount: displayUnreadCount,
                    unreadCount: displayUnreadCount,
                    onClick: () async {
                      if (groupAtInfoList == null || groupAtInfoList!.isEmpty) {
                        return;
                      }
                      final atInfo = groupAtInfoList![0];
                      final seq = atInfo?.seq;
                      if (seq == null || seq.trim().isEmpty) {
                        return;
                      }
                      final ok = await widget.scrollToIndexBySeq(seq);
                      if (!mounted || !ok) {
                        return;
                      }
                      setState(() {
                        if (groupAtInfoList!.length <= 1) {
                          groupAtInfoList = [];
                          isFinishJumpToAt = true;
                        } else {
                          groupAtInfoList!.removeAt(0);
                        }
                      });
                    },
                    atNum: atNum,
                    valueType: valueType,
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 16,
                child: _buildBottomCapsule(
                  visible: showScrolledUpBottomCapsule,
                  valueType: scrolledUpBottomType,
                  displayUnreadCount: liveUnreadCount,
                  onTap: () => _onBottomCapsuleTap(
                    scrolledUpBottomType,
                    liveUnreadCount,
                  ),
                  atNum: atNum,
                ),
              ),
            ],
          ),
        );
      },
      selector: (c, model) {
        final conversationID = widget.model.conversationID;
        return _TongueUnreadSelectorData(
          followingLatest: model.isFollowingLatest(conversationID),
          messageListPosition:
              pagePosition ?? model.getMessageListPosition(conversationID),
          unreadRemaining: model.getUnreadTongueRemaining(conversationID),
          unreadBelow: model.getUnreadTongueBelow(conversationID),
          lockedUnreadCount: model.hasLockedEntryUnreadFor(conversationID)
              ? model.lockedEntryUnreadCount
              : 0,
          haveMoreLatestData: widget.model.haveMoreLatestData,
          memoryWindowMissingNewer:
              globalModel.memoryWindowMissingNewer(conversationID),
          durableDeferred: model.hasDurableHistoryDeferred(conversationID),
          returningToBottom: _isProgrammaticScrollToBottomActive(),
          dismissedEntryUnread:
              model.getDismissedEntryUnreadTongueCount(conversationID),
          bufferedCount: model.deferredIncomingBufferedCount(conversationID),
          remainingLiveIncomingCount:
              model.remainingLiveIncomingCountFor(conversationID),
        );
      },
      shouldRebuild: (previous, next) =>
          previous.remainingLiveIncomingCount !=
              next.remainingLiveIncomingCount ||
          previous.bufferedCount != next.bufferedCount ||
          previous.followingLatest != next.followingLatest ||
          previous.messageListPosition != next.messageListPosition ||
          previous.unreadRemaining != next.unreadRemaining ||
          previous.unreadBelow != next.unreadBelow ||
          previous.lockedUnreadCount != next.lockedUnreadCount ||
          previous.haveMoreLatestData != next.haveMoreLatestData ||
          previous.memoryWindowMissingNewer != next.memoryWindowMissingNewer ||
          previous.durableDeferred != next.durableDeferred ||
          previous.returningToBottom != next.returningToBottom ||
          previous.dismissedEntryUnread != next.dismissedEntryUnread,
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    Widget buildForPagePosition() {
      final pageHistory = widget.pageHistoryPosition;
      if (pageHistory == null) {
        return _buildTongueSelector();
      }
      return ValueListenableBuilder<HistoryMessagePosition>(
        valueListenable: pageHistory,
        builder: (context, pagePosition, _) {
          return _buildTongueSelector(pagePosition: pagePosition);
        },
      );
    }

    final latestVisible = widget.latestMessageVisible;
    if (latestVisible == null) {
      return buildForPagePosition();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: latestVisible,
      builder: (context, _, __) {
        return buildForPagePosition();
      },
    );
  }
}
