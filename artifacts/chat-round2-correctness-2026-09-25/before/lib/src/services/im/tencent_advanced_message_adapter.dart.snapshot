import 'dart:async'; //同步消息服务
import 'dart:collection';
import 'dart:convert';

import 'coalesced_ui_progress.dart';
import 'receipt_recovery_compat.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_withdraw_ledger.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_download_progress.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_download_progress.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

typedef ImAdvancedEventSink = FutureOr<void> Function(
  EventEnvelope<dynamic> event,
);

typedef ImAdvancedIngestFailureSink = void Function(
  ImIngressDraft<dynamic> draft,
  Object error,
  StackTrace stackTrace, {
  required int attempt,
  required bool dropped,
});

/// Read-only lifecycle and queue state captured only when ingress fails.
class ImAdvancedIngressDiagnostics {
  const ImAdvancedIngressDiagnostics({
    required this.queueLength,
    required this.queueCapacity,
    required this.activeMailboxCount,
    required this.inFlightCount,
    required this.isClosed,
    required this.isDisposed,
    required this.currentAccountGeneration,
    required this.currentDomainGeneration,
    this.readyMailboxCount = 0,
    this.idleMailboxCount = 0,
    this.oldestInflightMs = 0,
    this.mailboxEvictionCount = 0,
    this.mailboxLimitHitCount = 0,
  });

  final int queueLength;
  final int queueCapacity;
  final int activeMailboxCount;
  final int inFlightCount;
  final bool isClosed;
  final bool isDisposed;
  final int currentAccountGeneration;
  final int currentDomainGeneration;
  final int readyMailboxCount;
  final int idleMailboxCount;
  final int oldestInflightMs;
  final int mailboxEvictionCount;
  final int mailboxLimitHitCount;
}

typedef ImAdvancedIngressDiagnosticsProvider = ImAdvancedIngressDiagnostics
    Function();

class _FailedIngressDraft {
  const _FailedIngressDraft({
    required this.draft,
    required this.error,
    required this.stackTrace,
    required this.attempt,
    required this.nextAttemptAtMs,
  });

  final ImIngressDraft<dynamic> draft;
  final Object error;
  final StackTrace stackTrace;
  final int attempt;
  final int nextAttemptAtMs;
}

class _UiProgressAttempt {
  _UiProgressAttempt(this.id);
  final int id;
  bool terminal = false;
}

class ImMessageRevokedEvent {
  const ImMessageRevokedEvent({
    required this.msgID,
    this.isAdmin = false,
    this.revoker,
  });

  final String msgID;
  final bool isAdmin;
  final V2TimUserFullInfo? revoker;
}

class ImReadReceiptBatch {
  ImReadReceiptBatch(Iterable<V2TimMessageReceipt> receipts,
      {this.applyC2CWatermark = false})
      : receipts = List<V2TimMessageReceipt>.unmodifiable(receipts);
  final List<V2TimMessageReceipt> receipts;
  final bool applyC2CWatermark;

  void applyTo(TUIChatGlobalModel model) {
    if (applyC2CWatermark) {
      final c2c = receipts
          .where((receipt) => (receipt.groupID?.trim() ?? '').isEmpty)
          .toList(growable: false);
      if (c2c.isNotEmpty) model.applyAppC2CReadReceipts(c2c);
    }
    model.applyAppMessageReadReceipts(receipts);
  }
}

class ImMessageProgressEvent {
  const ImMessageProgressEvent(
      {required this.message,
      required this.progress,
      this.attemptKey,
      this.attemptId});

  final V2TimMessage message;
  final int progress;
  final String? attemptKey;
  final int? attemptId;
}

class ImMessageDownloadProgressEvent {
  const ImMessageDownloadProgressEvent(this.progress,
      {this.attemptKey, this.attemptId});

  final V2TimMessageDownloadProgress progress;
  final String? attemptKey;
  final int? attemptId;
}

/// Adapter event source for ordinary chat. Call signaling deliberately does
/// not use this class and remains in its own SDK listener namespace.
class TencentAdvancedMessageAdapter {
  TencentAdvancedMessageAdapter({
    required this.messageService,
    required this.ingress,
    required this.ownerUserId,
    required this.accountGeneration,
    required this.domainGeneration,
    required this.onEvent,
    this.onIngestFailure,
    this.ingressDiagnostics,
    this.onUiProgress,
    this.isUiProgressLifecycleCurrent,
    this.onSdkRealtimeEvent,
    this.sdkRealtimeClearEpoch,
  });

  final MessageService messageService;
  final DurableIngressGateway ingress;
  final String ownerUserId;
  final int accountGeneration;
  final int domainGeneration;
  final ImAdvancedEventSink onEvent;

  /// SDK-owned message bodies need only a live projection. The sequence in
  /// this namespace orders this adapter's mailbox and is never a durable fence.
  static const sdkRealtimeNamespace = 'sdk_realtime';
  final ImAdvancedEventSink? onSdkRealtimeEvent;
  final int Function(AccountScopedConversationKey scope)? sdkRealtimeClearEpoch;
  int _sdkRealtimeSequence = 0;
  final _sdkRealtimePending = <String, Future<void>>{};
  final _sdkRealtimeDelivered = LinkedHashSet<String>();

  /// Disposable intermediate progress bypasses Inbox sequence/transactions.
  /// The owner must fence this callback to the captured account/domain.
  final FutureOr<void> Function(Object progress)? onUiProgress;
  final bool Function()? isUiProgressLifecycleCurrent;
  CoalescedUiProgress<Object>? _uiProgress;
  final _progressAttempts = LinkedHashMap<String, _UiProgressAttempt>();
  final int _progressSessionId = DateTime.now().microsecondsSinceEpoch;
  int _nextProgressAttempt = 0;
  final _receiptSubmissions = <String>{};
  final _recentReceiptIds = LinkedHashSet<String>();
  final ImAdvancedIngestFailureSink? onIngestFailure;
  final ImAdvancedIngressDiagnosticsProvider? ingressDiagnostics;

  V2TimAdvancedMsgListener? _listener;
  Future<void>? _registerInFlight;
  bool _registered = false;
  static const int _failedIngressCap = 512;
  static const int _failedIngressBatchSize = 32;
  static const int _failedIngressAttemptLimit = 10;
  final LinkedHashMap<String, _FailedIngressDraft> _failedIngress =
      LinkedHashMap<String, _FailedIngressDraft>();
  Timer? _failedIngressRetryTimer;
  bool _failedIngressDrainActive = false;
  int _ingestFailureCount = 0;
  int _ingestDroppedCount = 0;
  int _retrySuccessCount = 0;
  DateTime? _lastFullFailureLogAt;
  DateTime? _lastFailureSummaryAt;
  int _suppressedFailureLogs = 0;
  static const Duration _failureFullStackInterval = Duration(seconds: 8);

  bool get isRegistered => _registered;

  int get ingestFailureCount => _ingestFailureCount;

  int get ingestDroppedCount => _ingestDroppedCount;

  int get retrySuccessCount => _retrySuccessCount;

  int get pendingFailedIngressCount => _failedIngress.length;

  int get retryOldestAgeMs {
    if (_failedIngress.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var oldest = now;
    for (final pending in _failedIngress.values) {
      final enqueuedAt = pending.nextAttemptAtMs - _retryBackoffMs(pending.attempt);
      if (enqueuedAt < oldest) oldest = enqueuedAt;
    }
    return now - oldest;
  }

  Future<void> register() async {
    final pending = _registerInFlight;
    if (pending != null) {
      await pending;
      return;
    }
    if (_registered) return;
    _uiProgress ??= CoalescedUiProgress<Object>(
      onProgress: (progress) {
        if (isCurrentUiProgress(progress)) return onUiProgress?.call(progress);
      },
      onError: (error, stackTrace) {
        if (kDebugMode) debugPrint('IM UI progress failed: $error');
      },
    );
    final listener = _createListener();
    final task = () async {
      await messageService.addAdvancedMsgListener(listener: listener);
      if (identical(_listener, listener)) {
        _registered = true;
      } else {
        await messageService.removeAdvancedMsgListener(listener: listener);
      }
    }();
    _registerInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_registerInFlight, task)) {
        _registerInFlight = null;
      }
    }
  }

  Future<void> unregister() async {
    final pending = _registerInFlight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final listener = _listener;
    _listener = null;
    _registered = false;
    _failedIngressRetryTimer?.cancel();
    _failedIngressRetryTimer = null;
    _failedIngress.clear();
    _uiProgress?.dispose();
    _uiProgress = null;
    _progressAttempts.clear();
    _recentReceiptIds.clear();
    _receiptSubmissions.clear();
    _sdkRealtimeDelivered.clear();
    if (listener == null) return;
    await messageService.removeAdvancedMsgListener(listener: listener);
  }

  V2TimAdvancedMsgListener _createListener() {
    final listener = V2TimAdvancedMsgListener(
      onRecvNewMessage: (message) {
        _submitMessage(
          eventId: _messageEventId('received', message),
          kind: ImEventKind.realtimeMessage,
          scope: _scopeForMessage(message),
          payload: message,
          // A single SDK message can be delivered more than once with
          // hydrated fields changing between callbacks. The msgID is the
          // durable ingress identity, so do not hash the mutable full object
          // for the duplicate check.
          recoveryMode: ImRecoveryMode.sdkOverlapReplay,
          recoveryRef: _messageRecoveryRef(message),
        );
      },
      onRecvMessageModified: (message) {
        final digest = _payloadDigest(message);
        _submitMessage(
          eventId: 'modified:${message.msgID?.trim() ?? ''}:$digest',
          kind: ImEventKind.messageMutation,
          scope: _scopeForMessage(message),
          payload: message,
          payloadHash: digest,
          recoveryMode: ImRecoveryMode.sdkOverlapReplay,
          recoveryRef: _messageRecoveryRef(message),
        );
      },
      onRecvMessageRevoked: (msgID) {
        _submitRevoked(msgID);
      },
      onRecvMessageRevokedWithInfo: (msgID, operateUser, reason) {
        _submitRevoked(
          msgID,
          isAdmin: _isAdminRevokeReason(reason),
          revoker: operateUser,
        );
      },
      onRecvC2CReadReceipt: (receipts) =>
          _submitReceipts(receipts, applyC2CWatermark: true),
      onRecvMessageReadReceipts: (receipts) => _submitReceipts(receipts),
      onSendMessageProgress: (message, progress) {
        final key = 'send:${message.id ?? message.msgID}';
        final payload =
            ImMessageProgressEvent(message: message, progress: progress);
        final terminal = progress >= 100 ||
            message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC ||
            message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
        if (!terminal) {
          _queueUiProgress(key, payload, restarted: progress <= 0);
          return;
        }
        _submitTerminalProgress(
          key: key,
          eventId:
              'send-progress:${message.id ?? message.msgID}:$progress:${message.status}',
          payload: payload,
          payloadHash:
              '$progress:${message.status}:${_messageRecoveryRef(message)}',
          recoveryRef: 'send-progress:${message.id ?? message.msgID}',
        );
      },
      onMessageDownloadProgressCallback: (progress) {
        final key =
            'download:${progress.msgID}:${progress.type}:${progress.isSnapshot}';
        final payload = ImMessageDownloadProgressEvent(progress);
        if (!progress.isFinish &&
            !progress.isError &&
            progress.errorCode == 0) {
          _queueUiProgress(key, payload, restarted: progress.currentSize <= 0);
          return;
        }
        _submitTerminalProgress(
          key: key,
          eventId:
              '$key:${progress.currentSize}:${progress.isFinish}:${progress.errorCode}',
          payload: payload,
          payloadHash: _payloadDigest(progress),
          recoveryRef: 'download-progress:${progress.msgID}',
        );
      },
      // Extensions and reactions have no app projection or recovery consumer.
      // Keep the SDK defaults instead of journaling ignored notifications.
      onGroupMessagePinned: (groupID, message, isPinned, _) {
        final scope = AccountScopedConversationKey(
          ownerUserId: ownerUserId,
          conversationType: ImConversationType.group,
          conversationId: groupID,
        );
        _submitMessage(
          eventId:
              'group-pinned:$groupID:${message.msgID}:$isPinned:${_payloadDigest(message)}',
          kind: ImEventKind.messageMutation,
          scope: scope,
          payload: message,
          recoveryMode: ImRecoveryMode.commandArguments,
          recoveryRef: 'group-pinned:$groupID:${message.msgID}',
        );
      },
    );
    _listener = listener;
    return listener;
  }

  void _submitMessage({
    required String eventId,
    required ImEventKind kind,
    required AccountScopedConversationKey? scope,
    required V2TimMessage payload,
    String? payloadHash,
    required ImRecoveryMode recoveryMode,
    required String recoveryRef,
  }) {
    if (scope == null) {
      _submitAccountEvent(
        eventId: eventId,
        kind: ImEventKind.notification,
        payload: payload,
        payloadHash: payloadHash ??
            (kind == ImEventKind.realtimeMessage
                ? _messageIdentityPayloadHash(payload)
                : _payloadDigest(payload)),
        recoveryMode: recoveryMode,
        recoveryRef: recoveryRef,
      );
      return;
    }
    final sdkRealtime = onSdkRealtimeEvent != null &&
        kind == ImEventKind.realtimeMessage &&
        usesSdkRealtimeDelivery(payload, scope);
    _submit(
      ImIngressDraft<V2TimMessage>(
        eventId: eventId,
        eventNamespace: sdkRealtime ? sdkRealtimeNamespace : 'chat',
        kind: kind,
        scope: scope,
        ownerUserId: ownerUserId,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        clearEpoch: sdkRealtime ? sdkRealtimeClearEpoch?.call(scope) ?? 0 : 0,
        source: ImEventSource.sdkListener,
        authority: ImEventAuthority.provider,
        observedAtMs: DateTime.now().millisecondsSinceEpoch,
        payloadHash: sdkRealtime
            ? eventId
            : payloadHash ??
                (kind == ImEventKind.realtimeMessage
                    ? _messageIdentityPayloadHash(payload)
                    : _payloadDigest(payload)),
        recoveryMode: recoveryMode,
        recoveryRef: recoveryRef,
        payload: payload,
      ),
    );
  }

  /// Keep custom business messages, membership tips and unresolved outgoing
  /// operations on their existing durable path. Ordinary SDK content has no
  /// application command to recover in addition to the SDK's own history.
  @visibleForTesting
  static bool usesSdkRealtimeDelivery(
      V2TimMessage message, AccountScopedConversationKey scope) {
    if ((message.msgID?.trim() ?? '').isEmpty) return false;
    const ordinaryTypes = <int>{
      MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      MessageElemType.V2TIM_ELEM_TYPE_SOUND,
      MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
      MessageElemType.V2TIM_ELEM_TYPE_FILE,
      MessageElemType.V2TIM_ELEM_TYPE_LOCATION,
      MessageElemType.V2TIM_ELEM_TYPE_FACE,
      MessageElemType.V2TIM_ELEM_TYPE_MERGER,
    };
    if (!ordinaryTypes.contains(message.elemType)) return false;
    return message.isSelf != true ||
        OutgoingIdentityContract.fromCloudCustomData(message.cloudCustomData,
                scope: scope) ==
            null;
  }

  Future<void> _deliverSdkRealtime(ImIngressDraft<dynamic> draft) async {
    if (_listener == null || isUiProgressLifecycleCurrent?.call() == false)
      return;
    final key = '${draft.clearEpoch}:${draft.eventId}';
    if (_sdkRealtimeDelivered.contains(key)) return;
    final pending = _sdkRealtimePending[key];
    if (pending != null) return pending;
    final sequence = ++_sdkRealtimeSequence;
    final listener = _listener;
    final operation = Future<void>.sync(() => onSdkRealtimeEvent!(
          draft.materialize(
              accountIngressSequence: sequence, scopeIngressSequence: sequence),
        ));
    _sdkRealtimePending[key] = operation;
    try {
      await operation;
      if (!identical(listener, _listener)) return;
      _sdkRealtimeDelivered.add(key);
      while (_sdkRealtimeDelivered.length > 512) {
        _sdkRealtimeDelivered.remove(_sdkRealtimeDelivered.first);
      }
    } finally {
      if (identical(_sdkRealtimePending[key], operation)) {
        _sdkRealtimePending.remove(key);
      }
    }
  }

  int _progressAttemptFor(String key, {bool restarted = false}) {
    var attempt = _progressAttempts.remove(key);
    if (restarted && attempt?.terminal == true) attempt = null;
    attempt ??= _UiProgressAttempt(++_nextProgressAttempt);
    _progressAttempts[key] = attempt;
    // Attempt ID and terminal flag must be evicted together. Separate caches
    // let a retry inherit the completed identity after only its flag expired.
    if (_progressAttempts.length > 256) {
      _progressAttempts.remove(_progressAttempts.keys.first);
    }
    return attempt.id;
  }

  Object _progressWithAttempt(Object payload, String key, int attempt) {
    if (payload is ImMessageProgressEvent) {
      return ImMessageProgressEvent(
          message: payload.message,
          progress: payload.progress,
          attemptKey: key,
          attemptId: attempt);
    }
    final download = payload as ImMessageDownloadProgressEvent;
    return ImMessageDownloadProgressEvent(download.progress,
        attemptKey: key, attemptId: attempt);
  }

  /// Applies to both the coalesced lane and terminals waiting in Inbox. An old
  /// transfer must not overwrite a retry that already started on the UI lane.
  bool isCurrentUiProgress(Object payload) {
    if (isUiProgressLifecycleCurrent?.call() == false) return false;
    final String? key;
    final int? attempt;
    if (payload is ImMessageProgressEvent) {
      key = payload.attemptKey;
      attempt = payload.attemptId;
    } else if (payload is ImMessageDownloadProgressEvent) {
      key = payload.attemptKey;
      attempt = payload.attemptId;
    } else {
      return true;
    }
    if (key == null || attempt == null) return true; // legacy recovery
    final current = _progressAttempts[key];
    return current == null || current.id == attempt;
  }

  void _queueUiProgress(String key, Object payload, {required bool restarted}) {
    final attempt = _progressAttemptFor(key, restarted: restarted);
    if (_progressAttempts[key]?.terminal == true) return;
    _uiProgress?.add(key, _progressWithAttempt(payload, key, attempt));
  }

  void _submitTerminalProgress({
    required String key,
    required String eventId,
    required Object payload,
    required String payloadHash,
    required String recoveryRef,
  }) {
    final attempt = _progressAttemptFor(key);
    final stamped = _progressWithAttempt(payload, key, attempt);
    _progressAttempts[key]?.terminal = true;
    final listener = _listener;
    unawaited(() async {
      await _uiProgress?.cancel(key);
      if (listener == null ||
          !identical(listener, _listener) ||
          !isCurrentUiProgress(stamped)) return;
      _submitAccountEvent(
        eventId: '$eventId:attempt:$_progressSessionId:$attempt',
        kind: ImEventKind.notification,
        payload: stamped,
        payloadHash: payloadHash,
        recoveryMode: ImRecoveryMode.ephemeralUi,
        recoveryRef: recoveryRef,
      );
    }());
  }

  void _submitReceipts(List<V2TimMessageReceipt> receipts,
      {bool applyC2CWatermark = false}) {
    final byScope = <String, List<V2TimMessageReceipt>>{};
    final idsByScope = <String, List<String>>{};
    final latestByIdentity = <String, V2TimMessageReceipt>{};
    for (final receipt in receipts) {
      final identity = jsonEncode(<String?>[
        _scopeForReceipt(receipt)?.canonicalConversationId,
        receipt.userID,
        receipt.groupID,
        receipt.msgID?.trim(),
        // Keep an explicit wildcard alongside a positive watermark; the
        // specialized SDK callback historically applies both semantics.
        if (applyC2CWatermark && receipt.timestamp <= 0) 'wildcard',
      ]);
      final previous = latestByIdentity[identity];
      // A watermark covers all messages through its timestamp. Per-message
      // receipt changes instead preserve the SDK's last value in this batch
      // (group counters can change without a timestamp change).
      final watermark = applyC2CWatermark &&
          (receipt.groupID?.trim() ?? '').isEmpty &&
          (receipt.msgID?.trim() ?? '').isEmpty;
      if (watermark &&
          previous != null &&
          previous.timestamp > receipt.timestamp) {
        continue;
      }
      latestByIdentity[identity] = receipt;
    }
    for (final receipt in latestByIdentity.values) {
      // Preserve callback semantics: a generic per-message C2C receipt is not
      // proof that the entire peer conversation was read (Web can send ts=0).
      final snapshot = V2TimMessageReceipt.fromJson(receipt.toJson());
      final digest = _payloadDigest(snapshot);
      final id = '${applyC2CWatermark ? 'watermark' : 'message'}:$digest';
      if (_recentReceiptIds.contains(id) || !_receiptSubmissions.add(id))
        continue;
      // Native publishes C2C first, then the same generic message receipt. The
      // watermark batch applies both projections and subsumes that second call.
      if (applyC2CWatermark) _receiptSubmissions.add('message:$digest');
      final scope = _scopeForReceipt(snapshot)?.canonicalConversationId ?? '';
      (byScope[scope] ??= []).add(snapshot);
      (idsByScope[scope] ??= []).add(id);
    }
    for (final entry in byScope.entries) {
      final sourceIds = idsByScope[entry.key]!;
      final sortedIndexes =
          List<int>.generate(sourceIds.length, (index) => index)
            ..sort((a, b) => sourceIds[a].compareTo(sourceIds[b]));
      final ids = sortedIndexes
          .map((index) => sourceIds[index])
          .toList(growable: false);
      final batch = ImReadReceiptBatch(
          sortedIndexes.map((index) => entry.value[index]),
          applyC2CWatermark: applyC2CWatermark);
      final submissionIds = <String>{
        ...ids,
        if (applyC2CWatermark)
          ...ids.map((id) => id.replaceFirst('watermark:', 'message:')),
      };
      // Inbox compares both hash and recoveryRef, so the durable payload must
      // use the same canonical order as the event identity on SDK replay.
      final digest = _payloadDigest(ids);
      final scope = _scopeForReceipt(batch.receipts.first);
      final operation = '$receiptRecoveryOperationPrefix$digest';
      final observedAtMs = DateTime.now().millisecondsSinceEpoch;
      final copies = legacyReceiptRecoveryCopies(
        operationId: operation,
        receipts: batch.receipts.map((receipt) => receipt.toJson()),
        watermark: batch.applyC2CWatermark,
      );
      final draft = ImIngressDraft<ImReadReceiptBatch>(
        eventId: operation,
        eventNamespace: 'chat',
        kind:
            scope == null ? ImEventKind.notification : ImEventKind.readReceipt,
        scope: scope,
        ownerUserId: ownerUserId,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        clearEpoch: 0,
        source: ImEventSource.sdkListener,
        authority: ImEventAuthority.provider,
        operationId: operation,
        observedAtMs: observedAtMs,
        payloadHash: digest,
        // Both old and new recovery skip this disposable live aggregate.
        // Recovery is fully represented by the atomic legacy-format copies.
        recoveryMode: ImRecoveryMode.ephemeralUi,
        recoveryRef: 'ephemeral:$operation',
        payload: batch,
        recoveryCopies: copies
            .map((copy) => ImIngressDraft<void>(
                  eventId: copy.eventId,
                  eventNamespace: 'chat',
                  kind: scope == null
                      ? ImEventKind.notification
                      : ImEventKind.readReceipt,
                  scope: scope,
                  ownerUserId: ownerUserId,
                  accountGeneration: accountGeneration,
                  domainGeneration: domainGeneration,
                  clearEpoch: 0,
                  operationId: operation,
                  source: ImEventSource.sdkListener,
                  authority: ImEventAuthority.provider,
                  observedAtMs: observedAtMs,
                  payloadHash: _payloadDigest(copy.recoveryRef),
                  recoveryMode: ImRecoveryMode.commandArguments,
                  recoveryRef: copy.recoveryRef,
                ))
            .toList(growable: false),
      );
      unawaited(() async {
        try {
          if (await _attemptSubmit(draft, attempt: 0)) {
            _recentReceiptIds.addAll(submissionIds);
            while (_recentReceiptIds.length > 256) {
              _recentReceiptIds.remove(_recentReceiptIds.first);
            }
          }
        } finally {
          _receiptSubmissions.removeAll(submissionIds);
        }
      }());
    }
  }

  void _submitRevoked(
    String msgID, {
    bool isAdmin = false,
    V2TimUserFullInfo? revoker,
  }) {
    final normalized = msgID.trim();
    if (normalized.isEmpty) return;
    _submitAccountEvent(
      // The SDK can deliver both revoke callbacks for the same message. The
      // message identity, not the callback shape, is the Inbox idempotency key.
      eventId: 'revoked:$normalized',
      kind: ImEventKind.notification,
      payload: ImMessageRevokedEvent(
        msgID: normalized,
        isAdmin: isAdmin,
        revoker: revoker,
      ),
      payloadHash: normalized,
      recoveryMode: ImRecoveryMode.commandArguments,
      recoveryRef: 'revoke:$normalized',
      // Revoke-only fix: pin a conversation scope so the projection layer
      // can route the revoke to the right chat row even when no message body
      // is available in the SDK callback. The scope is best-effort and
      // gracefully falls back to null when the model has not been registered
      // yet or the message is no longer in any memory window.
      scope: _resolveRevokeScope(normalized),
    );
    // IM-08 P0-High B2: 每条撤回事件持久化到本地账本,
    // 防止 SDK listener 回调丢失导致冷启动 UI 残留原消息。
    // IM-08 P0-High B2: 持久化撤回事件,带 isAdmin + revokerID
    // 让 SDK 重启后 UI 仍能恢复"谁撤回"信息。
    final revokerID = revoker?.userID?.trim();
    unawaited(MessageWithdrawLedger.instance.recordRevokedWithInfo(
      msgID: normalized,
      isAdmin: isAdmin,
      revokerID: (revokerID == null || revokerID.isEmpty) ? null : revokerID,
    ));
  }

  /// Reverse-look up the conversation that owns [msgID] from the in-memory
  /// chat model. Returns null when the model is not yet wired, the message
  /// is outside every known window, or an unexpected error is raised. The
  /// projection layer already tolerates a null scope; this helper only adds
  /// accuracy when the lookup succeeds.
  AccountScopedConversationKey? _resolveRevokeScope(String msgID) {
    if (msgID.isEmpty) return null;
    final TUIChatGlobalModel model;
    try {
      model = serviceLocator<TUIChatGlobalModel>();
    } catch (_) {
      return null;
    }
    final Map<String, List<V2TimMessage>?> snapshot;
    try {
      snapshot = model.messageListMap;
    } catch (_) {
      return null;
    }
    String? selectedScope;
    final selectedConv = model.currentSelectedConv.trim();
    if (selectedConv.isNotEmpty && snapshot[selectedConv] != null) {
      for (final message in snapshot[selectedConv]!) {
        if (message.msgID?.trim() == msgID) {
          selectedScope = selectedConv;
          break;
        }
      }
    }
    String? fallbackScope;
    snapshot.forEach((storageKey, messages) {
      if (messages == null || messages.isEmpty) return;
      for (final message in messages) {
        if (message.msgID?.trim() == msgID) {
          fallbackScope = storageKey;
          return;
        }
      }
    });
    final resolved = selectedScope ?? fallbackScope;
    if (resolved == null || resolved.isEmpty) return null;
    final isGroup =
        MessageConversationId.looksLikeGroupConversationId(resolved);
    final isC2c = MessageConversationId.looksLikeC2cConversationId(resolved);
    final ImConversationType type;
    if (isGroup && !isC2c) {
      type = ImConversationType.group;
    } else if (isC2c) {
      type = ImConversationType.c2c;
    } else {
      return null;
    }
    return AccountScopedConversationKey.tryParse(
      ownerUserId: ownerUserId,
      conversationType: type,
      conversationId: resolved,
    );
  }

  void _submitAccountEvent({
    required String eventId,
    required ImEventKind kind,
    required Object? payload,
    required ImRecoveryMode recoveryMode,
    required String recoveryRef,
    AccountScopedConversationKey? scope,
    String? payloadHash,
  }) {
    _submit(
      ImIngressDraft<Object?>(
        eventId: eventId,
        eventNamespace: 'chat',
        kind: kind,
        scope: scope,
        ownerUserId: ownerUserId,
        accountGeneration: accountGeneration,
        domainGeneration: domainGeneration,
        clearEpoch: 0,
        source: ImEventSource.sdkListener,
        authority: ImEventAuthority.provider,
        observedAtMs: DateTime.now().millisecondsSinceEpoch,
        payloadHash: payloadHash ?? _payloadDigest(payload),
        recoveryMode: recoveryMode,
        recoveryRef: recoveryRef,
        payload: payload,
      ),
    );
  }

  void _submit<T>(ImIngressDraft<T> draft) {
    unawaited(_attemptSubmit(draft, attempt: 0));
  }

  Future<bool> _attemptSubmit<T>(
    ImIngressDraft<T> draft, {
    required int attempt,
  }) async {
    try {
      if (draft.eventNamespace == sdkRealtimeNamespace &&
          onSdkRealtimeEvent != null) {
        await _deliverSdkRealtime(draft);
      } else {
        final result = await ingress.append(draft);
        if (result.record.status != ImInboxStatus.completed) {
          await onEvent(result.event);
        }
      }
      _failedIngress.remove(_failedIngressKey(draft));
      if (attempt > 0) _retrySuccessCount++;
      return true;
    } catch (error, stackTrace) {
      _retainFailedIngress(
        draft,
        error: error,
        stackTrace: stackTrace,
        attempt: attempt + 1,
      );
      return false;
    }
  }

  void _retainFailedIngress(
    ImIngressDraft<dynamic> draft, {
    required Object error,
    required StackTrace stackTrace,
    required int attempt,
  }) {
    _ingestFailureCount++;
    final terminal = attempt >= _failedIngressAttemptLimit;
    _reportIngestFailure(
      draft,
      error,
      stackTrace,
      attempt: attempt,
      dropped: terminal,
    );
    if (terminal || _listener == null) {
      if (terminal) _ingestDroppedCount++;
      return;
    }

    final key = _failedIngressKey(draft);
    _failedIngress.remove(key);
    if (_failedIngress.length >= _failedIngressCap) {
      final evictedKey = _evictionCandidateKey();
      final evicted = _failedIngress.remove(evictedKey);
      if (evicted != null) {
        _ingestDroppedCount++;
        _reportIngestFailure(
          evicted.draft,
          evicted.error,
          evicted.stackTrace,
          attempt: evicted.attempt,
          dropped: true,
        );
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _failedIngress[key] = _FailedIngressDraft(
      draft: draft,
      error: error,
      stackTrace: stackTrace,
      attempt: attempt,
      nextAttemptAtMs: now + _retryBackoffMs(attempt),
    );
    _scheduleFailedIngressDrain();
  }

  String _evictionCandidateKey() {
    for (final entry in _failedIngress.entries) {
      if (entry.value.draft.recoveryMode != ImRecoveryMode.commandArguments) {
        return entry.key;
      }
    }
    return _failedIngress.keys.first;
  }

  void _scheduleFailedIngressDrain() {
    if (_listener == null ||
        _failedIngress.isEmpty ||
        _failedIngressDrainActive) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var earliest = _failedIngress.values.first.nextAttemptAtMs;
    for (final pending in _failedIngress.values.skip(1)) {
      if (pending.nextAttemptAtMs < earliest) {
        earliest = pending.nextAttemptAtMs;
      }
    }
    final waitMs = earliest > now ? earliest - now : 0;
    _failedIngressRetryTimer?.cancel();
    _failedIngressRetryTimer = Timer(
      Duration(milliseconds: waitMs),
      () => unawaited(_drainFailedIngress()),
    );
  }

  Future<void> _drainFailedIngress() async {
    if (_listener == null || _failedIngressDrainActive) return;
    _failedIngressDrainActive = true;
    _failedIngressRetryTimer = null;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = _failedIngress.entries
          .where((entry) => entry.value.nextAttemptAtMs <= now)
          .take(_failedIngressBatchSize)
          .toList(growable: false);
      for (final entry in due) {
        if (_listener == null) return;
        final current = _failedIngress[entry.key];
        if (!identical(current, entry.value)) continue;
        _failedIngress.remove(entry.key);
        await _attemptSubmit(
          entry.value.draft,
          attempt: entry.value.attempt,
        );
      }
    } finally {
      _failedIngressDrainActive = false;
      _scheduleFailedIngressDrain();
    }
  }

  void _reportIngestFailure(
    ImIngressDraft<dynamic> draft,
    Object error,
    StackTrace stackTrace, {
    required int attempt,
    required bool dropped,
  }) {
    final payload = draft.payload;
    final message = payload is V2TimMessage ? payload : null;
    ImAdvancedIngressDiagnostics? diagnostics;
    try {
      diagnostics = ingressDiagnostics?.call();
    } catch (diagnosticsError, diagnosticsStackTrace) {
      debugPrint(
        'CHAT_INGRESS_DIAGNOSTICS_FAILURE '
        'error=$diagnosticsError '
        'errorType=${diagnosticsError.runtimeType}\n'
        'stackTrace=$diagnosticsStackTrace',
      );
    }
    final conversationId = draft.scope?.canonicalConversationId ?? '';
    final messageId = message?.msgID?.trim() ?? '';
    final seq = message?.seq?.trim() ?? '';
    final now = DateTime.now();
    final lastFull = _lastFullFailureLogAt;
    final printFull = lastFull == null ||
        now.difference(lastFull) >= _failureFullStackInterval;
    if (printFull) {
      if (_suppressedFailureLogs > 0) {
        debugPrint(
          'CHAT_INGRESS_FAILURE_SUMMARY suppressed=$_suppressedFailureLogs '
          'mailbox_active_count=${diagnostics?.inFlightCount ?? -1} '
          'mailbox_ready_count=${diagnostics?.readyMailboxCount ?? -1} '
          'mailbox_idle_count=${diagnostics?.idleMailboxCount ?? -1} '
          'mailbox_oldest_inflight_ms=${diagnostics?.oldestInflightMs ?? -1} '
          'mailbox_limit_hit_count=${diagnostics?.mailboxLimitHitCount ?? -1} '
          'mailbox_eviction_count=${diagnostics?.mailboxEvictionCount ?? -1} '
          'retry_queue_depth=${_failedIngress.length} '
          'retry_oldest_age_ms=$retryOldestAgeMs '
          'retry_success_count=$_retrySuccessCount '
          'retry_drop_count=$_ingestDroppedCount',
        );
        _suppressedFailureLogs = 0;
      }
      _lastFullFailureLogAt = now;
      _lastFailureSummaryAt = now;
      debugPrint(
        'CHAT_INGRESS_FAILURE kind=${draft.kind.name} '
        'eventId=${draft.eventId} event=${_shortHash(draft.eventId)} '
        'attempt=$attempt dropped=$dropped '
        'conversationId=$conversationId messageId=$messageId seq=$seq '
        'queueLength=${diagnostics?.queueLength ?? -1} '
        'activeMailboxCount=${diagnostics?.activeMailboxCount ?? -1} '
        'inFlightCount=${diagnostics?.inFlightCount ?? -1} '
        'readyMailboxCount=${diagnostics?.readyMailboxCount ?? -1} '
        'retryQueueLength=${_failedIngress.length} '
        'isClosed=${diagnostics?.isClosed ?? (_listener == null)} '
        'isDisposed=${diagnostics?.isDisposed ?? (_listener == null && !_registered)} '
        'generation=${draft.accountGeneration} '
        'domainGeneration=${draft.domainGeneration} '
        'currentAccountGeneration=${diagnostics?.currentAccountGeneration ?? -1} '
        'currentDomainGeneration=${diagnostics?.currentDomainGeneration ?? -1} '
        'ownerUserId=${draft.ownerUserId} '
        'queueCapacity=${diagnostics?.queueCapacity ?? -1} '
        'retryQueueCapacity=$_failedIngressCap\n'
        'error=$error\n'
        'errorType=${error.runtimeType}\n'
        'stackTrace=$stackTrace',
      );
    } else {
      _suppressedFailureLogs++;
      final lastSummary = _lastFailureSummaryAt;
      if (lastSummary == null ||
          now.difference(lastSummary) >= _failureFullStackInterval) {
        _lastFailureSummaryAt = now;
        debugPrint(
          'CHAT_INGRESS_FAILURE_SUMMARY suppressed=$_suppressedFailureLogs '
          'mailbox_active_count=${diagnostics?.inFlightCount ?? -1} '
          'mailbox_ready_count=${diagnostics?.readyMailboxCount ?? -1} '
          'mailbox_idle_count=${diagnostics?.idleMailboxCount ?? -1} '
          'mailbox_oldest_inflight_ms=${diagnostics?.oldestInflightMs ?? -1} '
          'mailbox_limit_hit_count=${diagnostics?.mailboxLimitHitCount ?? -1} '
          'mailbox_eviction_count=${diagnostics?.mailboxEvictionCount ?? -1} '
          'retry_queue_depth=${_failedIngress.length} '
          'retry_oldest_age_ms=$retryOldestAgeMs '
          'retry_success_count=$_retrySuccessCount '
          'retry_drop_count=$_ingestDroppedCount',
        );
        _suppressedFailureLogs = 0;
      }
    }
    try {
      onIngestFailure?.call(
        draft,
        error,
        stackTrace,
        attempt: attempt,
        dropped: dropped,
      );
    } catch (callbackError, callbackStackTrace) {
      debugPrint(
        'CHAT_INGRESS_FAILURE '
        'callbackError=$callbackError '
        'callbackErrorType=${callbackError.runtimeType}\n'
        'stackTrace=$callbackStackTrace',
      ); //runtimeType赋值
    }
  }

  String _failedIngressKey(ImIngressDraft<dynamic> draft) =>
      '${draft.ownerUserId}|${draft.eventNamespace}|${draft.eventId}';

  int _retryBackoffMs(int attempt) {
    final exponent = attempt > 6 ? 6 : attempt;
    return (1 << exponent) * 250;
  }

  //打印日志
  AccountScopedConversationKey? _scopeForMessage(V2TimMessage message) {
    final conversation = MessageConversationId.fromMessage(
      message,
      loginUserId: ownerUserId,
    );
    if (conversation == null) return null;
    final type = conversation.startsWith('group_')
        ? ImConversationType.group
        : ImConversationType.c2c;
    return AccountScopedConversationKey.tryParse(
      ownerUserId: ownerUserId,
      conversationType: type,
      conversationId: conversation,
    );
  }

  AccountScopedConversationKey? _scopeForReceipt(V2TimMessageReceipt receipt) {
    final group = receipt.groupID?.trim() ?? '';
    if (group.isNotEmpty) {
      return AccountScopedConversationKey.tryParse(
        ownerUserId: ownerUserId,
        conversationType: ImConversationType.group,
        conversationId: group,
      );
    }
    final user = receipt.userID.trim();
    if (user.isEmpty) return null;
    return AccountScopedConversationKey.tryParse(
      ownerUserId: ownerUserId,
      conversationType: ImConversationType.c2c,
      conversationId: user,
    );
  }

  String _messageEventId(String prefix, V2TimMessage message) {
    final id = message.msgID?.trim() ?? '';
    if (id.isNotEmpty) return '$prefix:$id';
    return '$prefix:${_payloadDigest(message)}';
  }

  String _messageRecoveryRef(V2TimMessage message) {
    final id = message.msgID?.trim() ?? '';
    return id.isEmpty ? 'sdk-message:${_payloadDigest(message)}' : 'msgID:$id';
  }

  String _messageIdentityPayloadHash(V2TimMessage message) {
    final id = message.msgID?.trim() ?? '';
    if (id.isEmpty) return _payloadDigest(message);
    return sha256.convert(utf8.encode('received:$id')).toString();
  }
}

String _payloadDigest(Object? value) {
  Object? normalized = value;
  if (value is V2TimMessage) {
    normalized = value.toJson();
  } else if (value is V2TimMessageReceipt) {
    normalized = value.toJson();
  } else if (value is Iterable) {
    normalized = value.map(_payloadDigest).toList(growable: false);
  } else if (value is ImMessageRevokedEvent) {
    normalized = <String, Object?>{
      'msgID': value.msgID,
      'isAdmin': value.isAdmin,
      'revoker': value.revoker?.userID,
    };
  } else if (value is ImMessageProgressEvent) {
    normalized = <String, Object?>{
      'message': value.message.msgID ?? value.message.id,
      'progress': value.progress,
    };
  } else if (value is ImMessageDownloadProgressEvent) {
    normalized = value.progress.toJson();
  }
  return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
}

bool _isAdminRevokeReason(String reason) {
  final normalized = reason.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return normalized.contains('admin') || normalized.contains('groupowner');
}

String _shortHash(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 12);
