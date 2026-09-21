import 'dart:async';

import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_reset_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_cloud_catch_up.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

enum ConversationHistorySyncOutcome {
  verified,
  retryable,
  offline,
  unauthorized,
  stale,
}

class _QueuedHistoryVerification {
  const _QueuedHistoryVerification({
    required this.conversation,
    required this.reason,
    required this.identity,
    required this.lifecycle,
    required this.retryNumber,
    this.logTrace,
  });

  final V2TimConversation conversation;
  final String reason;
  final SessionIdentity identity;
  final int lifecycle;
  final int retryNumber;
  final ChatOpenTraceContext? logTrace;
}

/// Owns the post-first-frame history reconciliation lifecycle.
///
/// The chat page may publish a local SDK snapshot immediately, but it must not
/// also own cloud verification, roaming completion, gap repair, and retries.
/// This coordinator provides one account/session-scoped flight per
/// conversation and routes every remote result through TUIChatGlobalModel's
/// reconciliation writer.
class ConversationHistorySyncCoordinator {
  ConversationHistorySyncCoordinator._();

  static final ConversationHistorySyncCoordinator instance =
      ConversationHistorySyncCoordinator._();

  static const List<Duration> _retryDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 5),
  ];

  // A completed bounded pass that still lacks cloud proof is retried later,
  // but never on an unbounded timer. Reconnect/open events may still trigger
  // an immediate fresh pass and supersede this queue item.
  static const List<Duration> _queueRetryDelays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 60),
    Duration(minutes: 5),
  ];

  // Native IM calls can otherwise keep a conversation in-flight indefinitely
  // on a stalled mobile network. The coordinator releases the flight after
  // this bound and schedules the existing bounded retry path.
  static const Duration _sdkHistoryTimeout = Duration(seconds: 12);

  final Map<String, Future<ConversationHistorySyncOutcome>> _inFlight =
      <String, Future<ConversationHistorySyncOutcome>>{};
  final Map<String, Future<ConversationHistorySyncOutcome>> _h0InFlight =
      <String, Future<ConversationHistorySyncOutcome>>{};
  final Map<String, _QueuedHistoryVerification> _retryQueue =
      <String, _QueuedHistoryVerification>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  final Map<String, int> _retryAttempts = <String, int>{};
  final Set<String> _userOlderPaginationKeys = <String>{};
  final Map<String, Future<void>> _olderPaginationInFlight =
      <String, Future<void>>{};
  final Set<String> _cancelledConversations = <String>{};
  int _lifecycleGeneration = 0;

  void cancelConversation(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isEmpty) return;
    _cancelledConversations.add(key);
    // Keep the Future in the map until it settles. Removing it here would let
    // a route re-entry start a second native request while the old one is
    // still running.
    _retryTimers.removeWhere((k, timer) {
      if (!k.endsWith('|$key')) return false;
      timer.cancel();
      _retryQueue.remove(k);
      _retryAttempts.remove(k);
      return true;
    });
  }

  /// Marks a user-driven older-page request as higher priority than the
  /// background verification pass for the same conversation.
  void beginUserOlderPagination(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isNotEmpty) {
      _userOlderPaginationKeys.add(key);
    }
  }

  void endUserOlderPagination(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isNotEmpty) {
      _userOlderPaginationKeys.remove(key);
    }
  }

  bool isUserOlderPaginationActive(String conversationID) {
    final key = _normalizeConversationKey(conversationID);
    return key.isNotEmpty && _userOlderPaginationKeys.contains(key);
  }

  /// Serializes deliberate upward-page requests for one conversation. UIKit
  /// can emit duplicate edge callbacks while the list is settling; joining
  /// the existing Future avoids concurrent native SDK history calls.
  Future<void> runUserOlderPagination({
    required String conversationID,
    required Future<void> Function() task,
  }) {
    final key = _normalizeConversationKey(conversationID);
    if (key.isEmpty) return task();
    final existing = _olderPaginationInFlight[key];
    if (existing != null) return existing;
    final flight = task().timeout(_sdkHistoryTimeout);
    _olderPaginationInFlight[key] = flight;
    return flight.whenComplete(() {
      if (identical(_olderPaginationInFlight[key], flight)) {
        _olderPaginationInFlight.remove(key);
      }
    });
  }

  String _h0FlightKey(ChatViewportRepairTicket ticket) {
    final conversationKey = _normalizeConversationKey(ticket.conversationKey);
    return '${ticket.ownerUserId}@${ticket.accountGeneration}|$conversationKey|latest';
  }

  String _normalizeConversationKey(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower.startsWith('c2c_')) {
      final user = ChatIdFormat.rawUserUid(value.substring(4));
      return user.isEmpty ? '' : 'c2c_$user';
    }
    if (lower.startsWith('group_')) {
      final group = ChatIdFormat.canonicalGroupStorageId(value.substring(6));
      return group.isEmpty ? '' : 'group_$group';
    }
    if (ChatIdFormat.isIMGroupOrCommunityId(value) ||
        ChatIdFormat.isCommunityShortToken(value)) {
      final group = ChatIdFormat.canonicalGroupStorageId(value);
      return group.isEmpty ? '' : 'group_$group';
    }
    final user = ChatIdFormat.canonicalC2cUserId(value);
    return user.isEmpty ? value : 'c2c_$user';
  }

  Future<bool> _waitForUserOlderPagination(String conversationKey) async {
    // A warm request that has not entered the native SDK yet must yield to a
    // deliberate upward gesture. The bounded wait prevents a stuck UI flight
    // from holding the background verifier forever.
    for (var attempt = 0; attempt < 200; attempt++) {
      if (!isUserOlderPaginationActive(conversationKey)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return !isUserOlderPaginationActive(conversationKey);
  }

  /// H0：只修“当前首屏画不好”。flight key = account + conversation + latest。
  /// 页面退出作废该 openGeneration：不再开始新的 LOCAL/SDK，晚到 callback 不得写窗。
  Future<ConversationHistorySyncOutcome> repairOpenViewport({
    required V2TimConversation conversation,
    required ChatViewportRepairTicket ticket,
    ChatOpenTraceContext? logTrace,
  }) {
    final key = _h0FlightKey(ticket);
    final existing = _h0InFlight[key];
    if (existing != null) {
      return existing;
    }
    final h0Trace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    late final Future<ConversationHistorySyncOutcome> task;
    task = _runOpenViewportRepair(
      conversation: conversation,
      ticket: ticket,
      logTrace: h0Trace,
    ).whenComplete(() {
      if (identical(_h0InFlight[key], task)) {
        _h0InFlight.remove(key);
      }
    });
    _h0InFlight[key] = task;
    return task;
  }

  Future<ConversationHistorySyncOutcome> _runOpenViewportRepair({
    required V2TimConversation conversation,
    required ChatViewportRepairTicket ticket,
    required ChatOpenTraceContext logTrace,
  }) async {
    if (!_isCurrent(
      SessionIdentity(
        ownerUserId: ticket.ownerUserId,
        generation: ticket.accountGeneration,
      ),
      _lifecycleGeneration,
    )) {
      return ConversationHistorySyncOutcome.stale;
    }
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      ticket.conversationKey,
      ticket.openGeneration,
    )) {
      ChatOpenPerfLog.mark(
        'viewport_ticket_rejected',
        extras: <String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
          'ticketRejectedReason': collection.ticketRejectedReason(ticket),
          'sameConversationCache': collection.sameConversationCache(ticket),
          'uiAttached': collection.uiAttached,
        },
        trace: logTrace,
      );
      return ConversationHistorySyncOutcome.stale;
    }
    try {
      final applied = await ChatHistoryPeekBootstrap.apply(
        conversation: conversation,
        globalModel: globalModel,
        retryDelays: const <Duration>[Duration.zero],
        allowCloudVerification: true,
        logTrace: logTrace,
        boundOpenGeneration: ticket.openGeneration,
      ).timeout(_sdkHistoryTimeout);
      ChatOpenPerfLog.mark(
        'viewport_prepare_h0_commit',
        extras: <String, Object?>{
          'applied': applied,
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
        },
        trace: logTrace,
      );
      if (collection.isOpenGenerationAbandoned(
            ticket.conversationKey,
            ticket.openGeneration,
          ) ||
          !collection.acceptsTicket(ticket)) {
        ChatOpenPerfLog.mark(
          'viewport_ticket_rejected',
          extras: <String, Object?>{
            'ticketGeneration': ticket.openGeneration,
            'currentOpenGeneration': collection.openGeneration,
            'ticketRejectedReason': collection.ticketRejectedReason(ticket),
            'sameConversationCache': collection.sameConversationCache(ticket),
            'uiAttached': collection.uiAttached,
          },
          trace: logTrace,
        );
        return ConversationHistorySyncOutcome.stale;
      }
      ChatOpenPerfLog.mark(
        'viewport_ticket_accepted',
        extras: <String, Object?>{
          'ticketGeneration': ticket.openGeneration,
          'currentOpenGeneration': collection.openGeneration,
        },
        trace: logTrace,
      );
      collection.markRepair(ChatViewportRepairKind.none);
      return applied
          ? ConversationHistorySyncOutcome.verified
          : ConversationHistorySyncOutcome.retryable;
    } catch (_) {
      return ConversationHistorySyncOutcome.retryable;
    }
  }

  Future<ConversationHistorySyncOutcome> verifyAfterFirstFrame({
    required V2TimConversation conversation,
    String reason = 'chat_open',
    Duration delay = const Duration(milliseconds: 700),
    ChatOpenTraceContext? logTrace,
    int? boundOpenGeneration,
  }) {
    final verifyTrace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    Future<ConversationHistorySyncOutcome> startVerify() {
      return _verifyAfterFirstFrame(
        conversation: conversation,
        reason: reason,
        delay: delay,
        fromRetry: false,
        logTrace: verifyTrace,
        boundOpenGeneration: boundOpenGeneration,
      );
    }

    final rawConversationKey =
        ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (rawConversationKey == null || rawConversationKey.isEmpty) {
      return startVerify();
    }
    final conversationKey = _normalizeConversationKey(rawConversationKey);
    final identity = SessionIdentityService.instance.capture();
    final h0 = _h0InFlight[_h0FlightKey(
      ChatViewportRepairTicket(
        ownerUserId: identity.ownerUserId,
        accountGeneration: identity.generation,
        conversationKey: conversationKey,
        openGeneration: 0,
      ),
    )];
    if (h0 == null) {
      return startVerify();
    }
    return h0.then((_) => startVerify());
  }

  Future<ConversationHistorySyncOutcome> _verifyAfterFirstFrame({
    required V2TimConversation conversation,
    required String reason,
    required Duration delay,
    required bool fromRetry,
    ChatOpenTraceContext? logTrace,
    int? boundOpenGeneration,
  }) {
    final rawConversationKey =
        ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (rawConversationKey == null || rawConversationKey.isEmpty) {
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    final conversationKey = _normalizeConversationKey(rawConversationKey);
    if (conversationKey.isEmpty) {
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    if (_latestWindowResetOwnsConversation(rawConversationKey)) {
      // After a real reconnect the reset service owns the first cloud read.
      // Do not start (or timer-retry) an ordinary verify pass beside it.
      ChatHistoryTrace.log(
        'verify_skip_latest_window_reset_owner',
        conversationID: rawConversationKey,
        extras: <String, Object?>{'reason': reason},
      );
      return Future<ConversationHistorySyncOutcome>.value(
        ConversationHistorySyncOutcome.retryable,
      );
    }
    final verifyTrace = logTrace ?? ChatOpenPerfLog.captureCurrent();
    final identity = SessionIdentityService.instance.capture();
    final key =
        '${identity.ownerUserId}@${identity.generation}|$conversationKey';
    // An explicit entry makes this conversation active again even while the
    // previous route's delayed native task is still shared. Otherwise that
    // task observes its old cancellation and the new page inherits `stale`
    // without ever reading a first window. Timer retries cannot revive a
    // cancelled route; account/session identity remains part of the key.
    if (!fromRetry) _cancelledConversations.remove(conversationKey);
    final existing = _inFlight[key];
    if (existing != null) {
      if (boundOpenGeneration == null) return existing;
      final lifecycle = _lifecycleGeneration;
      // Join native work, but do not inherit an abandoned page's stale result.
      // The original task removes itself before this continuation runs.
      return existing.then((outcome) {
        if (outcome != ConversationHistorySyncOutcome.stale ||
            !_isCurrent(identity, lifecycle) ||
            _isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return outcome;
        }
        return _verifyAfterFirstFrame(
          conversation: conversation,
          reason: reason,
          delay: Duration.zero,
          fromRetry: fromRetry,
          logTrace: verifyTrace,
          boundOpenGeneration: boundOpenGeneration,
        );
      });
    }
    if (!fromRetry &&
        (reason.contains('reconnect') || reason.contains('resume'))) {
      ChatHistoryPeekBootstrap.invalidateCloudRetry(conversation);
    }
    if (ChatHistoryPeekBootstrap.isCloudRetryDeferred(
        conversation, serviceLocator<TUIChatGlobalModel>())) {
      // Leave the existing bounded retry timer intact on repeated route opens.
      _cancelledConversations.remove(conversationKey);
      _enqueueRetry(
          key: key,
          conversation: conversation,
          reason: reason,
          identity: identity,
          lifecycle: _lifecycleGeneration,
          logTrace: verifyTrace);
      return Future.value(ConversationHistorySyncOutcome.retryable);
    }
    // A cancelled route may be opened again after its old Future settled.
    _cancelledConversations.remove(conversationKey);

    // An explicit open/reconnect request supersedes a delayed retry for the
    // same account and conversation.
    _retryTimers.remove(key)?.cancel();
    _retryQueue.remove(key);
    if (!fromRetry) {
      _retryAttempts.remove(key);
    }

    final lifecycle = _lifecycleGeneration;
    late final Future<ConversationHistorySyncOutcome> task;
    task = _runVerification(
      conversation: conversation,
      conversationKey: conversationKey,
      identity: identity,
      lifecycle: lifecycle,
      reason: reason,
      delay: delay,
      logTrace: verifyTrace,
      boundOpenGeneration: boundOpenGeneration,
    ).then((outcome) {
      if (outcome == ConversationHistorySyncOutcome.retryable ||
          outcome == ConversationHistorySyncOutcome.offline) {
        _enqueueRetry(
          key: key,
          conversation: conversation,
          reason: reason,
          identity: identity,
          lifecycle: lifecycle,
          logTrace: verifyTrace,
        );
      } else {
        _retryAttempts.remove(key);
      }
      return outcome;
    }).whenComplete(() {
      if (identical(_inFlight[key], task)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = task;
    return task;
  }

  Future<ConversationHistorySyncOutcome> reconcileConversation({
    required String conversationID,
    V2TimConversation? conversation,
    String reason = 'reconnect',
  }) async {
    final key = conversationID.trim();
    if (key.isEmpty) {
      return ConversationHistorySyncOutcome.retryable;
    }
    final identity = SessionIdentityService.instance.capture();
    final lifecycle = _lifecycleGeneration;
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    final resetKey = conversation == null
        ? key
        : (ConversationPreviewHistorySync.conversationMessageCacheKey(
              conversation,
            ) ??
            key);
    if (_latestWindowResetOwnsConversation(resetKey)) {
      // The anchor-based cloud catch-up would page forward from a stale
      // anchor. The latest-window reset replaces it for this conversation.
      ChatHistoryTrace.log(
        'reconcile_skip_latest_window_reset_owner',
        conversationID: key,
        extras: <String, Object?>{'reason': reason},
      );
      return ConversationHistorySyncOutcome.retryable;
    }
    // A completely empty in-memory window is not proof that the cloud range
    // is complete. The low-level catch-up intentionally treats an empty
    // memory list as a no-op, so use the conversation-aware bootstrap here to
    // perform the first cloud-backed page and establish coverage.
    if (conversation != null &&
        (globalModel.rawMessageList(key)?.isEmpty ?? true)) {
      return verifyAfterFirstFrame(
        conversation: conversation,
        reason: reason,
        delay: Duration.zero,
      );
    }
    final result = await globalModel.reconcileConversationCloud(
      key,
      reason: reason,
    );
    if (!_isCurrent(identity, lifecycle)) {
      return ConversationHistorySyncOutcome.stale;
    }
    final coverage = await globalModel.ensureMessageHistoryCoverageLoaded(key);
    if (coverage.status == MessageHistoryCoverageStatus.verified &&
        !coverage.hasOpenHoles) {
      return ConversationHistorySyncOutcome.verified;
    }
    // `settled` means the bounded pass stopped safely. It is not proof that
    // the cloud range is complete, so keep mayHaveOlder armed and let the
    // caller/lifecycle retry later.
    final outcome = _outcomeFromCatchUp(result);
    return outcome == ConversationHistorySyncOutcome.verified
        ? ConversationHistorySyncOutcome.retryable
        : outcome;
  }

  bool _latestWindowResetOwnsConversation(String cacheKey) {
    final key = cacheKey.trim();
    if (key.isEmpty) return false;
    final service = ChatLatestWindowResetService.instance;
    return service.needsLatestWindowReset(key) || service.isResetInFlight(key);
  }

  /// Called by logout, account switching, and app teardown.  Native SDK
  /// requests cannot always be cancelled, so this invalidates their commit
  /// authority instead of trying to interrupt them.
  void invalidate() {
    _lifecycleGeneration++;
    ChatHistoryPeekBootstrap.clearSession();
    ChatLatestWindowResetService.instance.clearSession();
    _inFlight.clear();
    _h0InFlight.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryQueue.clear();
    _retryAttempts.clear();
    _userOlderPaginationKeys.clear();
  }

  void _enqueueRetry({
    required String key,
    required V2TimConversation conversation,
    required String reason,
    required SessionIdentity identity,
    required int lifecycle,
    ChatOpenTraceContext? logTrace,
  }) {
    if (!_isCurrent(identity, lifecycle) || _retryTimers.containsKey(key)) {
      return;
    }
    final retryNumber = (_retryAttempts[key] ?? 0) + 1;
    if (retryNumber > _queueRetryDelays.length) {
      _retryQueue.remove(key);
      return;
    }
    _retryAttempts[key] = retryNumber;
    final request = _QueuedHistoryVerification(
      conversation: conversation,
      reason: reason,
      identity: identity,
      lifecycle: lifecycle,
      retryNumber: retryNumber,
      logTrace: logTrace,
    );
    _retryQueue[key] = request;
    _retryTimers[key] = Timer(_queueRetryDelays[retryNumber - 1], () {
      _retryTimers.remove(key);
      final queued = _retryQueue.remove(key);
      if (queued == null || !_isCurrent(queued.identity, queued.lifecycle)) {
        return;
      }
      unawaited(
        _verifyAfterFirstFrame(
          conversation: queued.conversation,
          reason: 'retry_${queued.reason}_${queued.retryNumber}',
          delay: Duration.zero,
          fromRetry: true,
          logTrace: queued.logTrace,
        ),
      );
    });
  }

  Future<ConversationHistorySyncOutcome> _runVerification({
    required V2TimConversation conversation,
    required String conversationKey,
    required SessionIdentity identity,
    required int lifecycle,
    required String reason,
    required Duration delay,
    required ChatOpenTraceContext logTrace,
    int? boundOpenGeneration,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!_isCurrent(identity, lifecycle)) {
      return ConversationHistorySyncOutcome.stale;
    }
    if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
      return ConversationHistorySyncOutcome.stale;
    }

    final globalModel = serviceLocator<TUIChatGlobalModel>();
    // F-fix：warm scheduler 已经标 mayHaveOlder=false（SDK isFinished=true），
    // 且内存里已有数据 → 直接认为已验证，不再重试以免触发 build 风暴。
    if (!globalModel.mayHaveOlderHistory(conversationKey) &&
        globalModel.rawMessageCount(conversationKey) > 0 &&
        !ConversationPreviewHistorySync.isPreviewAheadOfCachedHistory(
          preview: conversation.lastMessage,
          cached: globalModel.rawMessageList(conversationKey) ?? const [],
        )) {
      ChatHistoryTrace.log(
        'verify_after_first_frame_short_circuit_exhausted',
        conversationID: conversationKey,
        extras: <String, Object?>{
          'reason': reason,
          'rawCount': globalModel.rawMessageCount(conversationKey),
        },
      );
      return ConversationHistorySyncOutcome.verified;
    }
    var lastOutcome = ConversationHistorySyncOutcome.retryable;
    for (var index = 0; index < _retryDelays.length; index++) {
      if (index > 0 && _retryDelays[index] > Duration.zero) {
        await Future<void>.delayed(_retryDelays[index]);
      }
      if (!_isCurrent(identity, lifecycle)) {
        return ConversationHistorySyncOutcome.stale;
      }

      if (!await _waitForUserOlderPagination(conversationKey)) {
        return ConversationHistorySyncOutcome.retryable;
      }

      try {
        if (_cancelledConversations
            .contains(_normalizeConversationKey(conversationKey))) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return ConversationHistorySyncOutcome.stale;
        }
        final applied = await ChatHistoryPeekBootstrap.apply(
          conversation: conversation,
          globalModel: globalModel,
          retryDelays: const <Duration>[Duration.zero],
          allowCloudVerification: true,
          logTrace: logTrace,
          boundOpenGeneration: boundOpenGeneration,
        ).timeout(_sdkHistoryTimeout);
        if (!_isCurrent(identity, lifecycle)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (_isBoundOpenAbandoned(conversationKey, boundOpenGeneration)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (!applied &&
            ChatHistoryPeekBootstrap.isCloudRetryDeferred(
                conversation, globalModel)) {
          return ConversationHistorySyncOutcome.retryable;
        }
        if (!applied) {
          lastOutcome = ConversationHistorySyncOutcome.retryable;
          continue;
        }

        final coverage = await globalModel.ensureMessageHistoryCoverageLoaded(
          conversationKey,
        );
        if (!_isCurrent(identity, lifecycle)) {
          return ConversationHistorySyncOutcome.stale;
        }
        if (coverage.status == MessageHistoryCoverageStatus.verified &&
            !coverage.hasOpenHoles) {
          return ConversationHistorySyncOutcome.verified;
        }

        // The latest-window verification and targeted gap repair share the
        // same writer.  Do not fetch a second full history window.
        if (coverage.hasOpenHoles ||
            coverage.status == MessageHistoryCoverageStatus.partial ||
            coverage.status == MessageHistoryCoverageStatus.offlineLocalOnly) {
          final catchUp = await globalModel
              .reconcileConversationCloud(
                conversationKey,
                reason: 'gap_repair_$reason',
              )
              .timeout(_sdkHistoryTimeout);
          lastOutcome = _outcomeFromCatchUp(catchUp);
          if (lastOutcome == ConversationHistorySyncOutcome.verified) {
            return lastOutcome;
          }
        } else {
          lastOutcome = ConversationHistorySyncOutcome.retryable;
        }
      } catch (_) {
        lastOutcome = ConversationHistorySyncOutcome.retryable;
      }
    }
    return lastOutcome;
  }

  bool _isBoundOpenAbandoned(String conversationKey, int? boundOpenGeneration) {
    if (boundOpenGeneration == null) {
      return false;
    }
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      conversationKey,
      boundOpenGeneration,
    )) {
      return true;
    }
    final attachedKey = collection.conversationKey;
    if (attachedKey != null &&
        attachedKey.isNotEmpty &&
        attachedKey != conversationKey) {
      return collection.isOpenGenerationAbandoned(
        attachedKey,
        boundOpenGeneration,
      );
    }
    return false;
  }

  bool _isCurrent(SessionIdentity identity, int lifecycle) {
    return lifecycle == _lifecycleGeneration &&
        SessionIdentityService.instance.isCurrent(identity);
  }

  ConversationHistorySyncOutcome _outcomeFromCatchUp(
    MessageCloudCatchUpResult result,
  ) {
    switch (result.disposition) {
      case MessageCloudCatchUpDisposition.complete:
        return ConversationHistorySyncOutcome.verified;
      case MessageCloudCatchUpDisposition.settled:
        return ConversationHistorySyncOutcome.retryable;
      case MessageCloudCatchUpDisposition.offline:
        return ConversationHistorySyncOutcome.offline;
      case MessageCloudCatchUpDisposition.retry:
      case MessageCloudCatchUpDisposition.continuation:
      case MessageCloudCatchUpDisposition.stalled:
        return ConversationHistorySyncOutcome.retryable;
    }
  }
}
