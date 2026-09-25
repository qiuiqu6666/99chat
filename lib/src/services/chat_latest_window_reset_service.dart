import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_peek_bootstrap.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_history_recovery_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_latest_window_trust.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_viewport/chat_viewport_collection.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_peek_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_sdk_relationship_sync_anchor.dart';
import 'package:tencent_cloud_chat_demo/src/services/network_status_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_demo/src/utils/conversation_preview_history_sync.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_image_message_prefetch.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/constants/history_message_constant.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_history_trace.dart';

/// Terminal state of one latest-window reset operation.
enum LatestWindowResetOutcome {
  /// Continuous latest window installed, edge aligned with the preview and
  /// freshness proven. Trust + 30s recovery success written.
  trusted,

  /// Window installed and edge aligned, but the operation ended (page or
  /// session became invalid) before a fresh proof was obtained.
  installedProvisional,

  /// Confirmed offline: fresh LOCAL continuous window shown. Never trusted.
  offlineProvisional,

  /// In-page only: the user is reading history / offline; nothing changed.
  deferred,

  /// Not applicable (no key, cannot peek, no reset needed, superseded).
  skipped,

  /// Nothing could be installed before the operation became invalid.
  failed,
}

/// Every external dependency the reset needs. Production reads the live
/// singletons; tests override through [ChatLatestWindowResetService.debugEnvironment].
class LatestWindowResetEnvironment {
  LatestWindowResetEnvironment({
    int Function()? recoveryEpoch,
    bool Function()? transportReady,
    bool Function()? serverSyncPending,
    ValueListenable<NetworkReachability>? networkStatus,
    Future<ConversationPeekLoadResult> Function(V2TimConversation)? loadCloud,
    Future<ConversationPeekLoadResult> Function(V2TimConversation)? loadLocal,
    bool Function(SessionIdentity identity)? isIdentityCurrent,
    List<Duration>? fastRetryDelays,
    List<Duration>? slowRetryDelays,
    Duration? inPagePollInterval,
  })  : recoveryEpoch = recoveryEpoch ?? (() => ImConnectStatusService.recoveryEpoch),
        transportReady =
            transportReady ?? (() => ImConnectStatusService.isTransportReady),
        serverSyncPending = serverSyncPending ??
            (() => ImSdkRelationshipSyncAnchor.serverSyncPending),
        networkStatus = networkStatus ?? NetworkStatusService.instance.status,
        loadCloud = loadCloud ?? ConversationPeekService.loadForChatEntry,
        loadLocal = loadLocal ?? ConversationPeekService.loadLocalForChatEntry,
        isIdentityCurrent = isIdentityCurrent ??
            ((identity) => SessionIdentityService.instance.isCurrent(identity)),
        fastRetryDelays = fastRetryDelays ?? defaultFastRetryDelays,
        slowRetryDelays = slowRetryDelays ?? defaultSlowRetryDelays,
        inPagePollInterval =
            inPagePollInterval ?? const Duration(milliseconds: 500);

  static const List<Duration> defaultFastRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 800),
    Duration(seconds: 2),
  ];

  /// After the fast attempts the operation stays alive: 5s / 15s / 60s, then
  /// every 60s, until a window is trusted or the page / session is gone. A
  /// roaming sync finish wakes the next attempt immediately.
  static const List<Duration> defaultSlowRetryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 60),
  ];

  final int Function() recoveryEpoch;
  final bool Function() transportReady;
  final bool Function() serverSyncPending;
  final ValueListenable<NetworkReachability> networkStatus;
  final Future<ConversationPeekLoadResult> Function(V2TimConversation) loadCloud;
  final Future<ConversationPeekLoadResult> Function(V2TimConversation) loadLocal;
  final bool Function(SessionIdentity identity) isIdentityCurrent;
  final List<Duration> fastRetryDelays;
  final List<Duration> slowRetryDelays;
  final Duration inPagePollInterval;

  bool get networkOnline => networkStatus.value == NetworkReachability.online;
  bool get networkOffline => networkStatus.value == NetworkReachability.offline;
}

class _ResetOperation {
  _ResetOperation({
    required this.id,
    required this.conversationKey,
    required this.openGeneration,
    required this.identity,
    required this.inPage,
    required this.conversation,
    required this.globalModel,
  });

  final int id;
  final String conversationKey;
  final int openGeneration;
  final SessionIdentity identity;
  final bool inPage;
  final V2TimConversation conversation;
  final TUIChatGlobalModel globalModel;
  final Completer<LatestWindowResetOutcome> completer =
      Completer<LatestWindowResetOutcome>();
  Completer<void>? syncWake;

  /// One wipe per operation, whoever performs it.
  bool windowCleared = false;
  bool installedProvisional = false;

  Future<LatestWindowResetOutcome> get future => completer.future;
}

class _ResetContext {
  const _ResetContext(this.conversation, this.globalModel);
  final V2TimConversation conversation;
  final TUIChatGlobalModel globalModel;
}

/// Owns the "continuous latest window" recovery after a real reconnect.
///
/// One operation per conversation key. A first-open operation never shows a
/// stale cache and installs only a validated window; an in-page operation
/// re-checks the user's position before any visible change and narrows the
/// visible window through `restampVisibleWindowToLatest`. The operation stays
/// alive (fast then slow retries) until a window is trusted or the page /
/// session it belongs to is gone; the skeleton is never left without an owner.
class ChatLatestWindowResetService {
  ChatLatestWindowResetService._();

  static final ChatLatestWindowResetService instance =
      ChatLatestWindowResetService._();

  @visibleForTesting
  static LatestWindowResetEnvironment? debugEnvironment;

  LatestWindowResetEnvironment get _env =>
      debugEnvironment ?? _defaultEnvironment;
  static final LatestWindowResetEnvironment _defaultEnvironment =
      LatestWindowResetEnvironment();

  final Map<String, _ResetOperation> _inFlightByKey = <String, _ResetOperation>{};

  /// Conversations whose current visible window was installed without proof
  /// (installedProvisional / offlineProvisional) or never installed after a
  /// failed open. They need a reset even when the epoch has not moved.
  final Set<String> _provisionalKeys = <String>{};

  /// Last conversation/global model seen per key so a network transition can
  /// re-run the reset for the currently open page without page cooperation.
  final Map<String, _ResetContext> _contextByKey = <String, _ResetContext>{};
  int _opSequence = 0;
  ValueListenable<NetworkReachability>? _listenedNetwork;
  NetworkReachability? _lastNetwork;

  @visibleForTesting
  int debugWipeInvocations = 0;

  bool needsLatestWindowReset(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty) return false;
    return ChatLatestWindowTrust.instance.needsLatestWindowReset(
      conversationKey: key,
      currentEpoch: _env.recoveryEpoch(),
      provisionalRegistered: _provisionalKeys.contains(key),
    );
  }

  bool isResetInFlight(String conversationKey) =>
      _inFlightByKey.containsKey(conversationKey.trim());

  @visibleForTesting
  Future<LatestWindowResetOutcome>? inFlightFutureFor(String conversationKey) =>
      _inFlightByKey[conversationKey.trim()]?.future;

  bool isProvisional(String conversationKey) =>
      _provisionalKeys.contains(conversationKey.trim());

  void clearSession() {
    _provisionalKeys.clear();
    _contextByKey.clear();
    for (final op in _inFlightByKey.values) {
      op.syncWake?.complete();
    }
  }

  @visibleForTesting
  void resetForTest() {
    clearSession();
    _inFlightByKey.clear();
    _listenedNetwork?.removeListener(_onNetworkStatusChanged);
    _listenedNetwork = null;
    _lastNetwork = null;
    debugWipeInvocations = 0;
  }

  /// First open after a real reconnect: (wipe unless the caller already did),
  /// fetch, validate, install. Returns `skipped` when no reset is needed.
  Future<LatestWindowResetOutcome> runForOpen({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    bool windowAlreadyCleared = false,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) {
    return _run(
      conversation: conversation,
      globalModel: globalModel,
      openGeneration: openGeneration,
      lifeCycle: lifeCycle,
      inPage: false,
      reason: 'open',
      windowAlreadyCleared: windowAlreadyCleared,
      onFirstWindowCommitted: onFirstWindowCommitted,
    );
  }

  /// Reconnect / network recovery while the page is open. Waits (polling)
  /// until the user is at the bottom, then repairs.
  Future<LatestWindowResetOutcome> runInPage({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    required String reason,
    ChatLifeCycle? lifeCycle,
  }) {
    return _run(
      conversation: conversation,
      globalModel: globalModel,
      openGeneration: openGeneration,
      lifeCycle: lifeCycle,
      inPage: true,
      reason: reason,
    );
  }

  Future<LatestWindowResetOutcome> _run({
    required V2TimConversation conversation,
    required TUIChatGlobalModel globalModel,
    required int openGeneration,
    required bool inPage,
    required String reason,
    bool windowAlreadyCleared = false,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = ConversationPreviewHistorySync.conversationMessageCacheKey(
      conversation,
    );
    if (key == null || key.isEmpty) return LatestWindowResetOutcome.skipped;
    if (!ConversationPeekService.canPeek(conversation)) {
      return LatestWindowResetOutcome.skipped;
    }
    _ensureNetworkListener();
    _contextByKey[key] = _ResetContext(conversation, globalModel);
    if (!needsLatestWindowReset(key)) return LatestWindowResetOutcome.skipped;
    final existing = _inFlightByKey[key];
    if (existing != null) {
      if (_opIsCurrent(existing)) return existing.future;
      // A reopened page must not wait for a request bound to the page it left.
      // That request still checks its generation before publishing a response.
      final wake = existing.syncWake;
      if (wake != null && !wake.isCompleted) wake.complete();
    }

    final op = _ResetOperation(
      id: ++_opSequence,
      conversationKey: key,
      openGeneration: openGeneration,
      identity: SessionIdentityService.instance.capture(),
      inPage: inPage,
      conversation: conversation,
      globalModel: globalModel,
    )..windowCleared = windowAlreadyCleared;
    _inFlightByKey[key] = op;
    _trace('latest_window_reset_start', op, extras: <String, Object?>{
      'reason': reason,
      'inPage': inPage,
      'windowAlreadyCleared': windowAlreadyCleared,
      'rawCount': globalModel.rawMessageCount(key),
    });
    void wake() => op.syncWake?.complete();
    globalModel.addRoamingSyncListener(wake);
    LatestWindowResetOutcome outcome = LatestWindowResetOutcome.failed;
    try {
      outcome = await _execute(
        op: op,
        lifeCycle: lifeCycle,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('latest_window_reset error key=$key $error\n$stack');
      }
      outcome = LatestWindowResetOutcome.failed;
    } finally {
      globalModel.removeRoamingSyncListener(wake);
      if (identical(_inFlightByKey[key], op)) _inFlightByKey.remove(key);
      _trace('latest_window_reset_done', op, extras: <String, Object?>{
        'outcome': outcome.name,
      });
      if (!op.completer.isCompleted) op.completer.complete(outcome);
    }
    return outcome;
  }

  // ---------------------------------------------------------------------------
  // Network recovery while a provisional page is open
  // ---------------------------------------------------------------------------

  void _ensureNetworkListener() {
    final status = _env.networkStatus;
    if (identical(_listenedNetwork, status)) return;
    _listenedNetwork?.removeListener(_onNetworkStatusChanged);
    _listenedNetwork = status;
    _lastNetwork = status.value;
    status.addListener(_onNetworkStatusChanged);
  }

  void _onNetworkStatusChanged() {
    final status = _listenedNetwork;
    if (status == null) return;
    final previous = _lastNetwork;
    final next = status.value;
    _lastNetwork = next;
    if (next != NetworkReachability.online || previous == next) return;
    // Wake every sleeping operation: an offline-deferred attempt can retry now.
    for (final op in _inFlightByKey.values) {
      op.syncWake?.complete();
    }
    final collection = ChatViewportCollection.instance;
    final openKey = collection.conversationKey ?? '';
    if (openKey.isEmpty || !collection.uiAttached) return;
    if (!needsLatestWindowReset(openKey) || isResetInFlight(openKey)) return;
    final context = _contextByKey[openKey];
    if (context == null) return;
    unawaited(runInPage(
      conversation: context.conversation,
      globalModel: context.globalModel,
      openGeneration: collection.openGeneration,
      reason: 'network_online',
    ));
  }

  // ---------------------------------------------------------------------------
  // Validity / position checks
  // ---------------------------------------------------------------------------

  bool _opIsCurrent(_ResetOperation op) {
    if (!_env.isIdentityCurrent(op.identity)) return false;
    final collection = ChatViewportCollection.instance;
    if (collection.isOpenGenerationAbandoned(
      op.conversationKey,
      op.openGeneration,
    )) {
      return false;
    }
    if (op.openGeneration > 0) {
      // A newer open (same or other conversation) took over the collection.
      if ((collection.conversationKey ?? '') != op.conversationKey) {
        return false;
      }
      if (collection.openGeneration != op.openGeneration) return false;
    }
    if (op.inPage && !collection.uiAttached) return false;
    return true;
  }

  /// In-page only. The user must still be following the latest edge and no
  /// other history owner may be mid-flight.
  bool _userAllowsVisibleReset(_ResetOperation op) {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    if (!_opIsCurrent(op)) return false;
    if (globalModel.getMessageListPosition(key) !=
        HistoryMessagePosition.bottom) {
      return false;
    }
    if (globalModel.isChatListUserScrolling) return false;
    if (!globalModel.isFollowingLatest(key)) return false;
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    if (globalModel.hasActiveHistoryReconciliation(key)) return false;
    return true;
  }

  /// Second check after the network round trip. Identical to the entry check
  /// minus the "no active request" rule, because the active request is ours.
  bool _userAllowsVisibleResetAfterFetch(_ResetOperation op) {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    if (!_opIsCurrent(op)) return false;
    if (globalModel.getMessageListPosition(key) !=
        HistoryMessagePosition.bottom) {
      return false;
    }
    if (globalModel.isChatListUserScrolling) return false;
    if (!globalModel.isFollowingLatest(key)) return false;
    if (globalModel.getSearchJumpStatus(key) != SearchJumpStatus.idle) {
      return false;
    }
    return true;
  }

  Future<bool> _waitUntilUserAllowsReset(_ResetOperation op) async {
    var logged = false;
    while (true) {
      if (!_opIsCurrent(op)) return false;
      if (_userAllowsVisibleReset(op)) return true;
      if (!logged) {
        logged = true;
        _trace('latest_window_reset_defer_reading_history', op);
      }
      await Future<void>.delayed(_env.inPagePollInterval);
    }
  }

  // ---------------------------------------------------------------------------
  // Main flow
  // ---------------------------------------------------------------------------

  void _wipeOnce(_ResetOperation op) {
    if (op.windowCleared) return;
    op.windowCleared = true;
    final globalModel = op.globalModel;
    final key = op.conversationKey;
    if (globalModel.rawMessageCount(key) > 0 ||
        globalModel.hasInitialHistoryLoaded(key)) {
      _trace('latest_window_reset_wipe_stale', op, extras: <String, Object?>{
        'rawCount': globalModel.rawMessageCount(key),
      });
      debugWipeInvocations++;
      globalModel.removeMessageList(key);
    }
  }

  Future<LatestWindowResetOutcome> _execute({
    required _ResetOperation op,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    if (!_opIsCurrent(op)) return LatestWindowResetOutcome.skipped;

    if (_env.networkOffline) {
      if (op.inPage) {
        // Nothing can be proven offline; the provisional flag keeps the reset
        // armed and the network listener re-runs it on the online transition.
        _provisionalKeys.add(key);
        return LatestWindowResetOutcome.deferred;
      }
      final offline = await _installOfflineProvisional(
        op: op,
        lifeCycle: lifeCycle,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
      // The first-open operation ends here; the network listener owns the
      // online transition for the page that is now showing this window.
      return offline;
    }

    if (!op.inPage) {
      // Never show a stale window, even briefly (unless the coordinator
      // already cleared it synchronously before locking the first frame).
      _wipeOnce(op);
    }

    final isGroup = _isGroup(op.conversation);
    var attempt = 0;
    while (true) {
      final delay = _delayForAttempt(attempt);
      if (delay > Duration.zero) {
        await _delayOrWake(op, delay);
      }
      attempt++;
      if (!_opIsCurrent(op)) return _endInvalid(op);
      if (_env.networkOffline) {
        // Went offline mid-operation. Keep the operation alive; the network
        // listener wakes it as soon as the device is online again.
        _trace('latest_window_reset_wait_network', op, extras: <String, Object?>{
          'attempt': attempt,
        });
        continue;
      }
      if (op.inPage) {
        if (!await _waitUntilUserAllowsReset(op)) return _endInvalid(op);
      } else if (op.globalModel.hasActiveHistoryReconciliation(key)) {
        // Another owner is mid-flight; give it a tick before taking the lane
        // rather than nesting request lifecycles.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!_opIsCurrent(op)) return _endInvalid(op);
        if (op.globalModel.hasActiveHistoryReconciliation(key)) {
          op.globalModel.cancelHistoryReconciliation(key);
        }
      }

      final attemptOutcome = await _attemptCloudLatestWindow(
        op: op,
        attempt: attempt,
        lifeCycle: lifeCycle,
        isGroup: isGroup,
        onFirstWindowCommitted: onFirstWindowCommitted,
      );
      switch (attemptOutcome) {
        case _AttemptOutcome.trusted:
          return LatestWindowResetOutcome.trusted;
        case _AttemptOutcome.installedProvisional:
          op.installedProvisional = true;
          _provisionalKeys.add(key);
          continue;
        case _AttemptOutcome.deferred:
          _provisionalKeys.add(key);
          return LatestWindowResetOutcome.deferred;
        case _AttemptOutcome.superseded:
          return _endInvalid(op);
        case _AttemptOutcome.retry:
          continue;
      }
    }
  }

  LatestWindowResetOutcome _endInvalid(_ResetOperation op) {
    // The page / session this operation belonged to is gone. Whatever it had
    // installed stays provisional, unless a newer operation has taken over.
    if (identical(_inFlightByKey[op.conversationKey], op)) {
      _provisionalKeys.add(op.conversationKey);
    }
    return op.installedProvisional
        ? LatestWindowResetOutcome.installedProvisional
        : LatestWindowResetOutcome.skipped;
  }

  Duration _delayForAttempt(int attempt) {
    final fast = _env.fastRetryDelays;
    if (attempt < fast.length) return fast[attempt];
    final slow = _env.slowRetryDelays;
    if (slow.isEmpty) return fast.isEmpty ? Duration.zero : fast.last;
    final index = attempt - fast.length;
    return slow[index < slow.length ? index : slow.length - 1];
  }

  /// Returns true when woken early (roaming sync finish / network online).
  Future<bool> _delayOrWake(_ResetOperation op, Duration delay) async {
    final wake = Completer<void>();
    op.syncWake = wake;
    try {
      await wake.future.timeout(delay);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      if (identical(op.syncWake, wake)) op.syncWake = null;
    }
  }

  Future<_AttemptOutcome> _attemptCloudLatestWindow({
    required _ResetOperation op,
    required int attempt,
    required bool isGroup,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    final conversation = op.conversation;
    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
    final networkBefore = globalModel.messageReconciliationNetworkState;
    final syncPendingBefore = _env.serverSyncPending();
    final epochBefore = _env.recoveryEpoch();

    // Single request lifecycle: this service is the only owner.
    final request = globalModel.beginHistoryReconciliation(
      conversationID: key,
      requestedSource: MessageReconciliationSource.cloud,
      networkState: networkBefore,
    );
    final ConversationPeekLoadResult result;
    try {
      result = await _env.loadCloud(conversation);
    } catch (error) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_load_failed',
      );
      _trace('latest_window_reset_retry_error', op, extras: <String, Object?>{
        'attempt': attempt,
        'error': error.toString(),
      });
      return _opIsCurrent(op)
          ? _AttemptOutcome.retry
          : _AttemptOutcome.superseded;
    }
    final networkAfter = globalModel.messageReconciliationNetworkState;
    final syncPendingAfter = _env.serverSyncPending();
    final provenance = MessageReconciliationProvenance.resolve(
      requestedSource: MessageReconciliationSource.cloud,
      beforeRequest: networkBefore,
      afterResponse: networkAfter,
    );
    final epochAfter = _env.recoveryEpoch();
    final fresh = result.receivedCloudResponse &&
        freshnessProven(
          cloudTransportConfirmed: provenance.cloudTransportConfirmed,
          networkOnline: _env.networkOnline,
          transportReady: _env.transportReady(),
          serverSyncPendingBefore: syncPendingBefore,
          serverSyncPendingAfter: syncPendingAfter,
        ) &&
        epochBefore == epochAfter;

    if (!_opIsCurrent(op)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_superseded',
      );
      return _AttemptOutcome.superseded;
    }
    if (op.inPage && !_userAllowsVisibleResetAfterFetch(op)) {
      // Second position check: the user moved into history while the request
      // was in flight. Do not touch the visible timeline.
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_user_left_bottom',
      );
      _trace('latest_window_reset_defer_after_fetch', op);
      return _AttemptOutcome.deferred;
    }

    final raw = List<V2TimMessage>.from(result.messages);
    final preview = conversation.lastMessage;

    if (raw.isEmpty) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_empty',
      );
      if (preview == null && result.receivedCloudResponse && fresh) {
        // Genuinely empty conversation confirmed by the server.
        globalModel.markLocalInitialHistoryVisible(key);
        globalModel.markInitialHistoryMayHaveOlder(key, mayHaveOlder: false);
        globalModel.setMessageListPosition(
          key,
          HistoryMessagePosition.bottom,
          notify: true,
        );
        _markTrusted(op, epochAfter);
        onFirstWindowCommitted?.call();
        return _AttemptOutcome.trusted;
      }
      _trace('latest_window_reset_retry_empty', op, extras: <String, Object?>{
        'attempt': attempt,
        'receivedCloudResponse': result.receivedCloudResponse,
        'fresh': fresh,
      });
      return _AttemptOutcome.retry;
    }

    // 1. Validate the RAW window first. The preview is the target, never part
    //    of the data being validated.
    final edge = latestEdgeMatchesPreview(preview: preview, rawWindow: raw);
    final contiguous = windowIsSelfContiguous(rawWindow: raw, isGroup: isGroup);
    // SDK pages omit deleted/unavailable messages, so numeric seq gaps do not
    // prove that a fresh latest-page response is incomplete. Keep the strict
    // continuity check for unverified/local fallback data. A missing preview
    // is also not a stale edge: the fresh SDK page can establish that edge.
    final edgeAccepted = edge.matched ||
        (preview == null && fresh && rawConfirmedLatest(raw) != null);
    final windowAccepted = contiguous || fresh;
    if (!edgeAccepted || !windowAccepted) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: !edgeAccepted
            ? 'latest_window_reset_edge_mismatch'
            : 'latest_window_reset_not_contiguous',
      );
      _trace('latest_window_reset_reject_raw', op, extras: <String, Object?>{
        'attempt': attempt,
        'edgeMatched': edge.matched,
        'edgeAccepted': edgeAccepted,
        'contiguous': contiguous,
        'fresh': fresh,
        'rawNewestSeq': raw.first.seq,
        'previewSeq': preview?.seq,
        'previewMsgID': preview?.msgID,
        ...ChatHistoryTrace.windowSummary(raw, prefix: 'raw'),
      });
      return _AttemptOutcome.retry;
    }

    // 2. Only now transform and splice UI-retained items.
    var messages = raw;
    if (lifeCycle?.didGetHistoricalMessageList != null) {
      messages = await lifeCycle!.didGetHistoricalMessageList(messages);
    }
    if (clearedAt > 0 || ArchiveHistoryProvider.isInHistoryClearGrace(key)) {
      messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: key,
        messages: messages,
      );
    }
    if (!_opIsCurrent(op) ||
        (op.inPage && !_userAllowsVisibleResetAfterFetch(op))) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_stale_before_commit',
      );
      return op.inPage ? _AttemptOutcome.deferred : _AttemptOutcome.superseded;
    }
    if (messages.isEmpty) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_filtered_empty',
      );
      return _AttemptOutcome.retry;
    }
    if (!op.inPage) {
      await ChatImageMessagePrefetch.prepareFirstWindowMedia(
        messages,
        budget: ChatImageMessagePrefetch.initialMediaBudget,
        onMessageResolved: globalModel.mergeMessageMediaMetadata,
      );
    }
    final window = _spliceSelfLastMessageIfMissing(
      last: preview,
      messages: isGroup
          ? CallBubbleDedupe.prepareOpenHistoryMessages(messages)
          : TUIChatGlobalModel.dedupeMessages(messages),
    );

    // 3. INSTALL. The request's clearEpoch must still be the one it began
    //    with; a wipe or clear in between makes the commit stale.
    if (clearedAt != await ArchiveHistoryProvider.historyClearedAtMs(key)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_reset_clear_epoch_changed',
      );
      return _AttemptOutcome.retry;
    }
    final batch = result.toBatch(
      conversationKey: key,
      requestedSource: MessageReconciliationSource.cloud,
      actualSource: provenance.actualSource,
      requestGeneration: request.generation,
      clearEpoch: clearedAt,
      cloudResponseProven: provenance.cloudTransportConfirmed,
      batchKind: MessageHistoryBatchKind.latestWindow,
      messages: window,
    );
    final commit = globalModel.completeHistoryBatch(
      request: request,
      batch: batch,
      networkState: provenance.networkState,
      clearEpoch: clearedAt,
      memoryWindowPreferLatest: true,
      historyCommitSource:
          op.inPage ? 'latest_window_reset_in_page' : 'latest_window_reset_open',
    );
    if (commit == null) {
      _trace('latest_window_reset_commit_rejected', op, extras: <String, Object?>{
        'attempt': attempt,
      });
      return _AttemptOutcome.retry;
    }
    if (op.inPage) {
      final restamped = globalModel.restampVisibleWindowToLatest(
        conversationID: key,
        latestWindow: batch.messages.toList(growable: false),
      );
      if (!restamped) {
        // completeHistoryBatch for a latest window intentionally keeps older
        // rows; if restamp cannot narrow (no scope / active request), force the
        // validated continuous window alone so we never leave a holey merge.
        globalModel.setMessageList(
          key,
          batch.messages.toList(growable: false),
          replace: true,
          needResetNewMessageCount: false,
          applyMemoryWindow: false,
          memoryWindowPreferLatest: true,
          historyCommitSource: 'latest_window_reset_force_narrow',
        );
        globalModel.markMemoryWindowMissingOlder(key);
      }
      _trace('latest_window_reset_restamp', op, extras: <String, Object?>{
        'restamped': restamped,
        'forcedNarrow': !restamped,
      });
    }

    final canCertify = result.receivedCloudResponse &&
        provenance.cloudTransportConfirmed &&
        _env.networkOnline &&
        _env.transportReady() &&
        !_env.serverSyncPending();
    if (canCertify) {
      globalModel.markCloudInitialHistoryVerified(key);
    } else {
      globalModel.markLocalInitialHistoryVisible(key);
    }
    globalModel.markInitialHistoryMayHaveOlder(
      key,
      mayHaveOlder: result.hasMoreOlder ||
          window.length >= HistoryMessageDartConstant.initialOpenFetchCount,
    );
    globalModel.setMessageListPosition(
      key,
      HistoryMessagePosition.bottom,
      notify: !op.inPage,
    );
    onFirstWindowCommitted?.call();
    _trace('latest_window_reset_installed', op, extras: <String, Object?>{
      'attempt': attempt,
      'fresh': fresh,
      'previewUnverifiable': edge.previewUnverifiable,
      'certified': canCertify,
      'rawCount': commit.rawCount,
      'hasMoreOlder': result.hasMoreOlder,
    });

    // 4. TRUST only with freshness proof.
    if (fresh) {
      _markTrusted(op, epochAfter);
      return _AttemptOutcome.trusted;
    }
    return _AttemptOutcome.installedProvisional;
  }

  void _markTrusted(_ResetOperation op, int epoch) {
    final key = op.conversationKey;
    _provisionalKeys.remove(key);
    ChatLatestWindowTrust.instance.markTrusted(key, epoch);
    ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(
      MessageConversationId.normalizeComparableKey(key),
    );
    ChatHistoryRecoveryCoordinator.instance.recordSuccessfulRecovery(key);
  }

  // ---------------------------------------------------------------------------
  // Offline provisional
  // ---------------------------------------------------------------------------

  Future<LatestWindowResetOutcome> _installOfflineProvisional({
    required _ResetOperation op,
    ChatLifeCycle? lifeCycle,
    void Function()? onFirstWindowCommitted,
  }) async {
    final key = op.conversationKey;
    final globalModel = op.globalModel;
    final conversation = op.conversation;
    final isGroup = _isGroup(conversation);
    // Never reuse the stale cache as the offline window either.
    _wipeOnce(op);
    _provisionalKeys.add(key);
    final clearedAt = await ArchiveHistoryProvider.historyClearedAtMs(key);
    final networkState = globalModel.messageReconciliationNetworkState;
    final request = globalModel.beginHistoryReconciliation(
      conversationID: key,
      requestedSource: MessageReconciliationSource.local,
      networkState: networkState,
    );
    final local = await _env.loadLocal(conversation);
    if (!_opIsCurrent(op)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: 'latest_window_offline_superseded',
      );
      return LatestWindowResetOutcome.skipped;
    }
    var messages = List<V2TimMessage>.from(local.messages);
    if (messages.isNotEmpty && lifeCycle?.didGetHistoricalMessageList != null) {
      messages = await lifeCycle!.didGetHistoricalMessageList(messages);
    }
    if (clearedAt > 0 || ArchiveHistoryProvider.isInHistoryClearGrace(key)) {
      messages = await ArchiveHistoryProvider.filterMessagesAfterHistoryClear(
        conversationID: key,
        messages: messages,
      );
    }
    final window = TUIChatGlobalModel.sortMessagesNewestFirst(
      isGroup
          ? CallBubbleDedupe.prepareOpenHistoryMessages(messages)
          : TUIChatGlobalModel.dedupeMessages(messages),
    );
    // Only this page's own continuity is validated; nothing about the server.
    // A local page with a seq hole is not a continuous window at all.
    if (window.isEmpty ||
        !windowIsSelfContiguous(rawWindow: window, isGroup: isGroup)) {
      globalModel.failHistoryReconciliation(
        request: request,
        reason: window.isEmpty
            ? 'latest_window_offline_local_empty'
            : 'latest_window_offline_local_not_contiguous',
      );
      _trace('latest_window_offline_no_local_window', op, extras: <String, Object?>{
        'localCount': window.length,
      });
      // Empty + offline state; skeleton/empty, never a patched old cache.
      return LatestWindowResetOutcome.failed;
    }
    final batch = local.toBatch(
      conversationKey: key,
      requestedSource: MessageReconciliationSource.local,
      actualSource: MessageReconciliationSource.local,
      requestGeneration: request.generation,
      clearEpoch: clearedAt,
      cloudResponseProven: false,
      batchKind: MessageHistoryBatchKind.localSnapshot,
      messages: window,
    );
    final commit = globalModel.completeHistoryBatch(
      request: request,
      batch: batch,
      networkState: networkState,
      clearEpoch: clearedAt,
      historyCommitSource: 'latest_window_offline_provisional',
    );
    if (commit == null) {
      _trace('latest_window_offline_commit_rejected', op);
      return LatestWindowResetOutcome.failed;
    }
    globalModel.markLocalInitialHistoryVisible(key);
    globalModel.markInitialHistoryMayHaveOlder(
      key,
      mayHaveOlder: ChatHistoryPeekBootstrap.localFirstImpliesMayHaveOlder(
        localCount: window.length,
        localReportedHasMoreOlder: local.hasMoreOlder,
      ),
    );
    globalModel.setMessageListPosition(
      key,
      HistoryMessagePosition.bottom,
      notify: true,
    );
    onFirstWindowCommitted?.call();
    _trace('latest_window_offline_installed', op, extras: <String, Object?>{
      'count': window.length,
      'localCount': local.messages.length,
    });
    return LatestWindowResetOutcome.offlineProvisional;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _isGroup(V2TimConversation conversation) {
    return (conversation.groupID?.trim().isNotEmpty ?? false) ||
        conversation.type == 2;
  }

  /// Same semantics as the bootstrap splice: a self-sent preview tip missing
  /// from the (already validated) window is appended at the newest end.
  static List<V2TimMessage> _spliceSelfLastMessageIfMissing({
    required V2TimMessage? last,
    required List<V2TimMessage> messages,
  }) {
    if (last == null || last.isSelf != true) return messages;
    if (ConversationPreviewHistorySync.isMessageVisibleInList(last, messages)) {
      return messages;
    }
    return TUIChatGlobalModel.sortMessagesNewestFirst(
      TUIChatGlobalModel.dedupeMessages(<V2TimMessage>[last, ...messages]),
    );
  }

  void _trace(
    String event,
    _ResetOperation op, {
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    ChatHistoryTrace.log(
      event,
      conversationID: op.conversationKey,
      extras: <String, Object?>{
        'op': op.id,
        'openGeneration': op.openGeneration,
        ...extras,
      },
    );
  }
}

enum _AttemptOutcome { trusted, installedProvisional, deferred, superseded, retry }
