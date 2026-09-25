import 'dart:async';
import 'dart:convert';
import 'outbox_draft_submission.dart';
import 'outbox_retry_identity.dart';
import 'writer_lease.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';

import 'package:crypto/crypto.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_outbox_recovery_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_message_adapter.dart';
import 'package:tencent_cloud_chat_demo/src/utils/message_conversation_id.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class ImCoordinatedSendResult {
  const ImCoordinatedSendResult({
    required V2TimValueCallback<V2TimMessage> sdkResult,
    required this.usedOutbox,
    this.identity,
    this.accountGeneration,
    this.domainGeneration,
    this.dispatchDecision,
    bool outcomeUnknown = false,
    this.outboxResult,
    this.resultView,
    this.localStatePending = false,
  })  : _sdkResult = sdkResult,
        _outcomeUnknown = outcomeUnknown;

  final V2TimValueCallback<V2TimMessage> _sdkResult;
  final bool usedOutbox;
  final OutgoingIdentityContract? identity;
  final int? accountGeneration;
  final int? domainGeneration;
  final ImOutboxDispatchDecision? dispatchDecision;
  final bool _outcomeUnknown;
  final ImOutboxResultVerdict? outboxResult;
  final ImOutboxResultView? resultView;
  final bool localStatePending;

  /// Capture once at a UI consumption boundary; every derived field then
  /// reads the same committed verdict instead of a changing live view.
  ImCoordinatedSendResult snapshot() => ImCoordinatedSendResult(
      sdkResult: _sdkResult,
      usedOutbox: usedOutbox,
      identity: identity,
      accountGeneration: accountGeneration,
      domainGeneration: domainGeneration,
      dispatchDecision: dispatchDecision,
      outcomeUnknown: _outcomeUnknown,
      outboxResult: currentOutboxResult,
      localStatePending: localStatePending);

  bool get isCurrentSession =>
      identity == null ||
      accountGeneration == null ||
      SessionIdentityService.instance.isCurrent(SessionIdentity(
          ownerUserId: identity!.scope.ownerUserId,
          generation: accountGeneration!));

  ImOutboxResultVerdict? get currentOutboxResult {
    final published = resultView?.current;
    if (published != null &&
        published.stateVersion >= (outboxResult?.stateVersion ?? 0)) {
      return published;
    }
    return outboxResult;
  }

  bool get outcomeUnknown {
    if (!isCurrentSession) return true;
    if (currentOutboxResult?.deliveryConfirmed == true) return false;
    if (localStatePending) return _sdkResult.code != 0;
    final result = currentOutboxResult;
    if (result != null) return !result.deliveryConfirmed && !result.canRetry;
    return _outcomeUnknown;
  }

  /// Downstream consumers receive the adjudicated state, never an old SDK code
  /// that contradicts newer durable evidence for this operation.
  V2TimValueCallback<V2TimMessage> get sdkResult {
    if (!isCurrentSession) {
      return V2TimValueCallback<V2TimMessage>(
          code: -2,
          desc: 'send belongs to an earlier session',
          data: _sdkResult.data);
    }
    final result = currentOutboxResult;
    if (localStatePending &&
        _sdkResult.code == 0 &&
        result?.deliveryConfirmed != true) {
      return _sdkResult;
    }
    if (result == null) return _sdkResult;
    final code = result.deliveryConfirmed
        ? 0
        : result.canRetry
            ? (int.tryParse(result.main?.resultCode ?? '') ?? -1)
            : -2;
    var message = _sdkResult.data;
    final serverId = result.main?.serverMsgId;
    if (message != null && serverId != null && serverId.isNotEmpty) {
      message = _cloneMessageForOutbox(message) ?? message;
      message.msgID = serverId;
      message.id = result.main?.sdkMessageId ?? message.id;
    }
    return V2TimValueCallback<V2TimMessage>(
        code: code,
        desc: result.deliveryConfirmed
            ? 'delivery confirmed'
            : result.canRetry
                ? _sdkResult.desc
                : 'delivery pending reconciliation',
        data: message);
  }

  bool get canCompleteProjection =>
      isCurrentSession &&
      usedOutbox &&
      (!localStatePending || currentOutboxResult?.deliveryConfirmed == true) &&
      identity != null &&
      sdkResult.code == 0;
}

enum ImProviderEvidenceSource { sdkHistory, sdkRealtime, appProjection }

class ImOutgoingSendCoordinator {
  ImOutgoingSendCoordinator._()
      : _leaseContext =
            ConversationSyncService.instance.messageCoreLeaseForOutgoingSend;

  @visibleForTesting
  ImOutgoingSendCoordinator.forTesting({
    required Future<ImMessageCoreLeaseContext?> Function() leaseContext,
  }) : _leaseContext = leaseContext;

  final Future<ImMessageCoreLeaseContext?> Function() _leaseContext;

  static final ImOutgoingSendCoordinator instance =
      ImOutgoingSendCoordinator._();

  int _transientIngressSequence = 0;
  int _sendOperationGeneration = 0;

  Future<bool> abandonOutcomeUnknown({
    required String sdkLocalId,
    required String conversationId,
    required ImConversationType conversationType,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty) return false;
    final context = await _leaseContext();
    if (context == null) return false;
    final scope = AccountScopedConversationKey.tryParse(
      ownerUserId: context.ownerUserId,
      conversationType: conversationType,
      conversationId: conversationId,
    );
    if (scope == null) return false;
    final persistence = Im05Persistence(store: context.store);
    // New sends use a UUID operation id, so resolve the durable row by the
    // provider-local id first. Keep the legacy hash fallback for rows written
    // by older app versions.
    final resolved = await persistence.findOutboxBySdkLocalId(
      ownerUserId: context.ownerUserId,
      conversationId: scope.storageKey,
      sdkLocalId: localId,
    );
    final operationId = resolved?.operationId ??
        hashOutgoingOperationId(scope: scope, sdkLocalId: localId);
    final assessment = await persistence.recoverOutbox(
      ownerUserId: context.ownerUserId,
      operationId: operationId,
    );
    final abandoned = await persistence.abandonOutcomeUnknown(
      ownerUserId: context.ownerUserId,
      operationId: operationId,
      leaseOwnerId: context.lease.leaseOwnerId,
      fencingToken: context.lease.fencingToken,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (abandoned) {
      await OutgoingMediaStager.instance.cleanup(
        assessment.main?.mediaLocalRef,
      );
    }
    return abandoned;
  }

  Future<ImCoordinatedSendResult> send({
    required MessageService messageService,
    required String sdkLocalId,
    required String conversationId,
    required ImConversationType conversationType,
    required String receiver,
    required String groupID,
    V2TimMessage? fallbackMessage,
    MessagePriorityEnum priority = MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    bool onlineUserOnly = false,
    bool isExcludedFromUnreadCount = false,
    bool needReadReceipt = false,
    OfflinePushInfo? offlinePushInfo,
    String? businessCloudCustomData,
    String? localCustomData,
    bool isExcludedFromContentModeration = false,
    bool persistOutbox = true,
    bool recoverPreparedOutbox = false,
    String? operationIdOverride,
    String? clientCorrelationIdOverride,
    void Function(String syncMsgID)? onSyncMsgID,
    SessionIdentity? expectedSessionIdentity,
    String? retryOfSdkLocalId,
    void Function()? onDispatchGranted,
  }) async {
    final localId = sdkLocalId.trim();
    if (localId.isEmpty) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'sdkLocalId is required',
      );
    }
    final context = await _leaseContext();
    if (expectedSessionIdentity != null &&
        (!SessionIdentityService.instance.isCurrent(expectedSessionIdentity) ||
            context?.ownerUserId != expectedSessionIdentity.ownerUserId ||
            context?.accountGeneration != expectedSessionIdentity.generation)) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'media send belongs to an earlier session',
      );
    }
    if (context == null) {
      // Keep this diagnostic next to the first pre-SDK return. A visible
      // optimistic bubble with no IM_SEND means the send stopped here.
      print(
          '[IM_SEND_BLOCKED] conversation=$conversationId reason=message_core_lease_unavailable');
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'message core lease unavailable',
      );
    }
    final scope = AccountScopedConversationKey.tryParse(
      ownerUserId: context.ownerUserId,
      conversationType: conversationType,
      conversationId: conversationId,
    );
    if (scope == null) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'invalid outgoing conversation scope',
      );
    }

    if (recoverPreparedOutbox && !persistOutbox) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'prepared recovery requires durable Outbox',
      );
    }
    if (!recoverPreparedOutbox &&
        ((operationIdOverride?.trim().isNotEmpty ?? false) ||
            (clientCorrelationIdOverride?.trim().isNotEmpty ?? false))) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'identity override is only valid for prepared recovery',
      );
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final persistence = Im05Persistence(store: context.store);
    ImOutboxRecord? retryParent;
    if (retryOfSdkLocalId != null) {
      retryParent = await persistence.findOutboxBySdkLocalId(
          ownerUserId: context.ownerUserId,
          conversationId: scope.storageKey,
          sdkLocalId: retryOfSdkLocalId);
      final verdict = retryParent == null
          ? null
          : await persistence.readOutboxResult(
              ownerUserId: context.ownerUserId,
              operationId: retryParent.operationId);
      if (verdict?.canRetry != true || !persistOutbox)
        return _blocked(
            fallbackMessage: fallbackMessage,
            outcomeUnknown: true,
            desc: 'retry requires current durable failure');
      retryParent = verdict!.main;
    }
    final retryKey = retryParent == null ? null : outboxRetryKey(retryParent);
    if (retryParent != null && retryKey == null) {
      return _blocked(
          fallbackMessage: fallbackMessage,
          outcomeUnknown: true,
          desc: 'retry requires a durable failed dispatch attempt');
    }
    final operationId = operationIdOverride?.trim().isNotEmpty == true
        ? operationIdOverride!.trim()
        : retryKey == null
            ? newOutgoingOperationId()
            : 'retry_$retryKey';
    final clientCorrelationId =
        clientCorrelationIdOverride?.trim().isNotEmpty == true
            ? clientCorrelationIdOverride!.trim()
            : retryKey == null
                ? newOutgoingClientCorrelationId()
                : 'retry_corr_$retryKey';
    // The SDK-created local message is already the bubble adopted by the UI.
    // Recreating it here produces a second local id: the SDK sends that second
    // message while the visible bubble stays attached to the first one. This
    // is the root cause of duplicate media bubbles and media/audio rows stuck
    // in SENDING. Normal dispatch must always keep the original local id.
    final sendLocalId = localId;
    final sendMessage = fallbackMessage;
    var outboxMessage = fallbackMessage;
    String? stagedMediaRoot;
    if (persistOutbox && !recoverPreparedOutbox && retryParent == null) {
      // Staging rewrites local paths. Apply that mutation only to a detached
      // Outbox copy so the live SDK/UI message continues to use its original
      // path and identity. Recovery may recreate an SDK message later from
      // this durable copy; the immediate send must not.
      outboxMessage = _cloneMessageForOutbox(fallbackMessage);
      if (fallbackMessage != null && outboxMessage == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          desc: 'outgoing message snapshot failed',
        );
      }
      final staged = await OutgoingMediaStager.instance.stageMessage(
        message: outboxMessage,
        operationId: operationId,
      );
      if (staged.shouldBlock) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          desc: 'outgoing media staging failed',
        );
      }
      stagedMediaRoot = staged.rootPath;
    }
    ImOutboxDispatchAssessment? recoveredPrepared;
    if (recoverPreparedOutbox) {
      recoveredPrepared = await persistence.assessOutboxForDispatch(
        ownerUserId: context.ownerUserId,
        operationId: operationId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: nowMs,
      );
      final recoveredMain = recoveredPrepared.main;
      if (!recoveredPrepared.canDispatch ||
          recoveredMain == null ||
          recoveredMain.state != ImOutboxState.prepared ||
          recoveredMain.operationId != operationId ||
          recoveredMain.clientCorrelationId != clientCorrelationId ||
          recoveredMain.conversationId != scope.storageKey) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          usedOutbox: true,
          decision: recoveredPrepared.decision,
          outcomeUnknown: recoveredPrepared.requiresOutcomeQuery,
          desc: 'prepared Outbox recovery identity rejected',
        );
      }
    }
    final messageKind = _messageKindFor(
      (outboxMessage ?? sendMessage)?.elemType,
    );
    final plaintextEnvelope = recoveredPrepared == null && retryParent == null
        ? _encodeOutgoingEnvelope(
            message: outboxMessage,
            sdkLocalId: sendLocalId,
            conversationId: conversationId,
            receiver: receiver,
            groupID: groupID,
            priority: priority,
            onlineUserOnly: onlineUserOnly,
            isExcludedFromUnreadCount: isExcludedFromUnreadCount,
            needReadReceipt: needReadReceipt,
            offlinePushInfo: offlinePushInfo,
            businessCloudCustomData: businessCloudCustomData,
            localCustomData: localCustomData,
            isExcludedFromContentModeration: isExcludedFromContentModeration,
          )
        : null;
    final protectedPayload =
        persistOutbox && recoveredPrepared == null && plaintextEnvelope != null
            ? await OutboxPayloadCipher.instance.protect(
                ownerUserId: context.ownerUserId,
                plaintext: plaintextEnvelope,
              )
            : null;
    final payloadEnvelope = recoveredPrepared?.main?.payloadReference ??
        retryParent?.payloadReference ??
        (persistOutbox ? protectedPayload?.value : plaintextEnvelope);
    if (persistOutbox && payloadEnvelope == null) {
      await OutgoingMediaStager.instance.cleanup(stagedMediaRoot);
      return _blocked(
        fallbackMessage: fallbackMessage,
        desc: 'durable outgoing payload is unavailable',
      );
    }
    // Hash the canonical plaintext envelope, not the AES-GCM ciphertext.
    // Encryption intentionally uses a fresh nonce on every send, so a
    // ciphertext hash would change even when the logical message is identical.
    final payloadFingerprint = recoveredPrepared?.main?.payloadHash ??
        retryParent?.payloadHash ??
        sha256
            .convert(
                utf8.encode(plaintextEnvelope ?? 'sdkLocalId:$sendLocalId'))
            .toString();
    if (recoveredPrepared != null &&
        recoveredPrepared.main!.payloadHash != payloadFingerprint) {
      return _blocked(
        fallbackMessage: fallbackMessage,
        usedOutbox: true,
        decision: ImOutboxDispatchDecision.identityConflict,
        desc: 'prepared Outbox payload fingerprint rejected',
      );
    }
    final identity = OutgoingIdentityContract(
      scope: scope,
      operationId: operationId,
      clientCorrelationId: clientCorrelationId,
      messageKind: messageKind,
      payloadFingerprint: payloadFingerprint,
      createdAtMs: recoveredPrepared?.main?.createdAtMs ?? nowMs,
      sdkLocalId: sendLocalId,
    );
    final sendGeneration = ++_sendOperationGeneration;
    final dispatchAttemptId =
        'attempt:${identity.operationId}:$sendGeneration:$nowMs';
    final resultView = persistOutbox
        ? persistence.watchOutboxResult(
            context.ownerUserId, identity.operationId)
        : null;

    final draftContext =
        recoverPreparedOutbox ? null : ImDraftSubmissionContext.current;
    final draftAcceptance = persistOutbox && draftContext != null
        ? await draftContext.prepare()
        : null;
    if (persistOutbox) {
      final main = ImOutboxRecord(
        operationId: identity.operationId,
        retryOfOperationId: recoveredPrepared?.main?.retryOfOperationId ??
            retryParent?.operationId,
        retryOfStateVersion: recoveredPrepared?.main?.retryOfStateVersion ??
            retryParent?.stateVersion,
        ownerUserId: context.ownerUserId,
        conversationId: scope.storageKey,
        clientCorrelationId: identity.clientCorrelationId,
        messageType:
            (outboxMessage ?? sendMessage)?.elemType ?? messageKind.index,
        payloadReference: payloadEnvelope!,
        mediaLocalRef: recoveredPrepared?.main?.mediaLocalRef ??
            retryParent?.mediaLocalRef ??
            stagedMediaRoot ??
            _mediaLocalReference(outboxMessage ?? sendMessage),
        encryptionVersion: recoveredPrepared?.main?.encryptionVersion ??
            retryParent?.encryptionVersion ??
            (protectedPayload == null
                ? null
                : ProtectedOutboxPayload.encryptionVersion),
        keyId: recoveredPrepared?.main?.keyId ??
            retryParent?.keyId ??
            protectedPayload?.keyId,
        cipherAlgorithm: recoveredPrepared?.main?.cipherAlgorithm ??
            retryParent?.cipherAlgorithm ??
            (protectedPayload == null
                ? null
                : ProtectedOutboxPayload.cipherAlgorithm),
        nonce: recoveredPrepared?.main?.nonce ??
            retryParent?.nonce ??
            protectedPayload?.nonce,
        payloadHash: identity.payloadFingerprint,
        contentChecksum: identity.payloadFingerprint,
        sdkMessageId: sendLocalId,
        state: ImOutboxState.prepared,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );
      final recovery = ImOutboxRecoveryRecord(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
        clientCorrelationId: identity.clientCorrelationId,
        conversationId: scope.storageKey,
        messageType: main.messageType,
        recoveryRevision: 1,
        state: ImOutboxCopyState.copyPrepared,
        payloadReferenceOrCiphertext: payloadEnvelope,
        payloadHash: identity.payloadFingerprint,
        checksum: identity.payloadFingerprint,
        sdkLocalId: sendLocalId,
        updatedAtMs: nowMs,
      );
      final prepared = recoveredPrepared ??
          await persistence.prepareOutbox(
            main: main,
            recoveryCopy: recovery,
            draftAcceptance: draftAcceptance,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: nowMs,
          );
      if (!prepared.canDispatch) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: prepared.decision,
          outboxResult: ImOutboxResultVerdict.fromDispatchAssessment(prepared),
          resultView: resultView,
          accountGeneration: context.accountGeneration,
          domainGeneration: context.domainGeneration,
          outcomeUnknown: prepared.requiresOutcomeQuery,
          desc: 'outbox dispatch rejected: ${prepared.decision.name}',
        );
      }
      if (!recoverPreparedOutbox) {
        OutgoingOutboxRecoveryService.instance.wakeAfterPreparedCommit();
      }
      // The two Outbox records and draft ownership are committed together.
      // A UI failure cannot undo durable acceptance or trigger another send.
      if (draftContext != null) {
        try {
          draftContext.accepted(identity.operationId);
        } catch (error) {
          debugPrint('draft acceptance projection failed: ' +
              error.runtimeType.toString());
        }
      }
      final dispatch = await persistence.recordDispatchIntent(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
        dispatchAttemptId: dispatchAttemptId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: nowMs,
      );
      if (!dispatch.canDispatch || dispatch.main == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: dispatch.decision,
          outboxResult: ImOutboxResultVerdict.fromDispatchAssessment(dispatch),
          resultView: resultView,
          accountGeneration: context.accountGeneration,
          domainGeneration: context.domainGeneration,
          outcomeUnknown: dispatch.requiresOutcomeQuery,
          desc: 'outbox dispatch rejected: ${dispatch.decision.name}',
        );
      }
      final sending = await persistence.transitionOutbox(
        next: dispatch.main!.copyWith(
          state: ImOutboxState.sending,
          sdkMessageId: sendLocalId,
        ),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (sending == null) {
        return _blocked(
          fallbackMessage: fallbackMessage,
          identity: identity,
          usedOutbox: true,
          decision: ImOutboxDispatchDecision.fencingRejected,
          resultView: resultView,
          accountGeneration: context.accountGeneration,
          domainGeneration: context.domainGeneration,
          desc: 'outbox sending transition rejected',
        );
      }
    }

    if (!SessionIdentityService.instance.isCurrent(SessionIdentity(
        ownerUserId: context.ownerUserId,
        generation: context.accountGeneration))) {
      return ImCoordinatedSendResult(
          sdkResult: V2TimValueCallback<V2TimMessage>(
              code: -2,
              desc: 'session changed before SDK dispatch',
              data: fallbackMessage),
          usedOutbox: persistOutbox,
          identity: identity,
          accountGeneration: context.accountGeneration,
          domainGeneration: context.domainGeneration,
          outcomeUnknown: true);
    }
    final adapter = TencentMessageAdapter(
      port: TUIKitMessageServicePort(messageService),
      platform: ImPlatform.unknown,
      ownerUserId: context.ownerUserId,
      accountGeneration: context.accountGeneration,
      domainGeneration: context.domainGeneration,
      nextAccountIngressSequence: _nextTransientIngressSequence,
      nextScopeIngressSequence: (_) => _nextTransientIngressSequence(),
      onSyncIdentity: (event) {
        final serverId = event.payload?.serverMsgId?.trim() ?? '';
        if (serverId.isNotEmpty) {
          onSyncMsgID?.call(serverId);
        }
      },
    );
    try {
      onDispatchGranted?.call();
    } catch (error) {
      debugPrint('outbox dispatch UI pending: ${error.runtimeType}');
    }
    final sdk = await adapter.send(
      identity: identity,
      sdkLocalId: sendLocalId,
      receiver: receiver,
      groupID: groupID,
      sendOperationGeneration: sendGeneration,
      priority: priority,
      onlineUserOnly: onlineUserOnly,
      isExcludedFromUnreadCount: isExcludedFromUnreadCount,
      needReadReceipt: needReadReceipt,
      offlinePushInfo: offlinePushInfo,
      businessCloudCustomData: businessCloudCustomData,
      localCustomData: localCustomData,
      isExcludedFromContentModeration: isExcludedFromContentModeration,
    );

    final formalIdentity = sdk.data?.identity ?? identity;
    var callback = V2TimValueCallback<V2TimMessage>(
      code: sdk.code ?? (sdk.isSuccess ? 0 : -1),
      desc: sdk.resultDesc ?? '',
      data: sdk.data?.message ?? sendMessage ?? fallbackMessage,
    );
    ImOutboxResultVerdict? verdict;
    var localStatePending = false;
    if (persistOutbox) {
      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        if (sdk.isOutcomeUnknown) {
          await persistence.recordOutcomeUnknown(
            ownerUserId: context.ownerUserId,
            operationId: identity.operationId,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: now,
            resultCode: callback.code.toString(),
          );
          verdict = await persistence.readOutboxResult(
              ownerUserId: context.ownerUserId,
              operationId: identity.operationId);
        } else {
          verdict = await persistence.adjudicateOutboxSdkResult(
            ownerUserId: context.ownerUserId,
            operationId: identity.operationId,
            expectedAttemptId: dispatchAttemptId,
            succeeded: sdk.isSuccess,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: now,
            sdkLocalId: sendLocalId,
            serverMsgId: formalIdentity.serverMsgId,
            resultCode: callback.code.toString(),
          );
        }
      } catch (error) {
        // A valid SDK success remains success. A failed local transaction is
        // pending repair, never permission to dispatch this operation again.
        localStatePending = true;
        debugPrint(
            '[IM_SEND_COORDINATOR] result persistence pending: ${error.runtimeType}');
      }
    }
    return ImCoordinatedSendResult(
      sdkResult: callback,
      usedOutbox: persistOutbox,
      identity: formalIdentity,
      accountGeneration: context.accountGeneration,
      domainGeneration: context.domainGeneration,
      outcomeUnknown: sdk.isOutcomeUnknown,
      outboxResult: verdict,
      resultView: resultView,
      localStatePending: localStatePending,
    );
  }

  Future<bool> completeSuccessfulProjection(
    ImCoordinatedSendResult result,
  ) async {
    final identity = result.identity;
    if (!result.canCompleteProjection || identity == null) return false;
    try {
      final context = await ConversationSyncService.instance
          .messageCoreLeaseForOutgoingSend();
      if (context == null ||
          context.ownerUserId != identity.scope.ownerUserId ||
          context.accountGeneration != result.accountGeneration ||
          context.domainGeneration != result.domainGeneration) {
        return false;
      }
      final persistence = Im05Persistence(store: context.store);
      final assessment = await persistence.recoverOutbox(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
      );
      final completed = await persistence.completeOutboxProjection(
        ownerUserId: context.ownerUserId,
        operationId: identity.operationId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (completed) {
        await OutgoingMediaStager.instance.cleanup(
          assessment.main?.mediaLocalRef,
        );
      }
      return completed;
    } catch (error) {
      debugPrint(
          '[IM_SEND_COORDINATOR] projection checkpoint pending: ${error.runtimeType}');
      return false;
    }
  }

  /// Reconciles durable unknown sends from an already-committed history page.
  /// Only self messages carrying the exact outgoing identity envelope can
  /// advance an Outbox row.
  Future<int> adoptProviderHistory(
    Iterable<V2TimMessage> messages, {
    required ImProviderEvidenceSource source,
  }) async {
    if (source == ImProviderEvidenceSource.appProjection) return 0;
    final context = await _leaseContext();
    if (context == null) return 0;
    final persistence = Im05Persistence(store: context.store);
    var adoptedCount = 0;
    for (final message in messages) {
      if (message.isSelf != true ||
          message.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) continue;
      final sender = message.sender?.trim() ?? '';
      if (sender != context.ownerUserId ||
          (message.msgID?.trim().isEmpty ?? true)) {
        continue;
      }
      final conversationId = MessageConversationId.fromMessage(
        message,
        loginUserId: context.ownerUserId,
      );
      if (conversationId == null) continue;
      final scope = AccountScopedConversationKey.tryParse(
        ownerUserId: context.ownerUserId,
        conversationType: conversationId.startsWith('group_')
            ? ImConversationType.group
            : ImConversationType.c2c,
        conversationId: conversationId,
      );
      if (scope == null) continue;
      final outgoing = OutgoingIdentityContract.fromCloudCustomData(
        message.cloudCustomData,
        scope: scope,
      );
      if (outgoing == null) continue;
      final adopted = await persistence.adoptOutboxProviderSucceeded(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
        clientCorrelationId: outgoing.clientCorrelationId,
        conversationId: scope.storageKey,
        payloadHash: outgoing.payloadFingerprint,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        sdkLocalId: message.id,
        serverMsgId: message.msgID,
      );
      if (!adopted) continue;
      final assessment = await persistence.recoverOutbox(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
      );
      final completed = await persistence.completeOutboxProjection(
        ownerUserId: context.ownerUserId,
        operationId: outgoing.operationId,
        leaseOwnerId: context.lease.leaseOwnerId,
        fencingToken: context.lease.fencingToken,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (completed) {
        await OutgoingMediaStager.instance.cleanup(
          assessment.main?.mediaLocalRef,
        );
        adoptedCount++;
      }
    }
    return adoptedCount;
  }

  int _nextTransientIngressSequence() => ++_transientIngressSequence;
}

ImCoordinatedSendResult _blocked({
  required V2TimMessage? fallbackMessage,
  OutgoingIdentityContract? identity,
  bool usedOutbox = false,
  ImOutboxDispatchDecision? decision,
  bool outcomeUnknown = false,
  ImOutboxResultVerdict? outboxResult,
  ImOutboxResultView? resultView,
  int? accountGeneration,
  int? domainGeneration,
  required String desc,
}) {
  return ImCoordinatedSendResult(
    sdkResult: V2TimValueCallback<V2TimMessage>(
      code: -1,
      desc: desc,
      data: fallbackMessage,
    ),
    usedOutbox: usedOutbox,
    identity: identity,
    dispatchDecision: decision,
    outcomeUnknown: outcomeUnknown,
    outboxResult: outboxResult,
    resultView: resultView,
    accountGeneration: accountGeneration,
    domainGeneration: domainGeneration,
  );
}

V2TimMessage? _cloneMessageForOutbox(V2TimMessage? message) {
  if (message == null) return null;
  try {
    return V2TimMessage.fromJson(
      Map<String, dynamic>.from(message.toJson()),
    );
  } catch (_) {
    return null;
  }
}

String? _encodeOutgoingEnvelope({
  required V2TimMessage? message,
  required String sdkLocalId,
  required String conversationId,
  required String receiver,
  required String groupID,
  required MessagePriorityEnum priority,
  required bool onlineUserOnly,
  required bool isExcludedFromUnreadCount,
  required bool needReadReceipt,
  required OfflinePushInfo? offlinePushInfo,
  required String? businessCloudCustomData,
  required String? localCustomData,
  required bool isExcludedFromContentModeration,
}) {
  if (message == null) return null;
  try {
    return jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'sdkLocalId': sdkLocalId.trim(),
      'conversationId': conversationId.trim(),
      'receiver': receiver.trim(),
      'groupID': groupID.trim(),
      'priority': priority.index,
      'onlineUserOnly': onlineUserOnly,
      'isExcludedFromUnreadCount': isExcludedFromUnreadCount,
      'needReadReceipt': needReadReceipt,
      'offlinePushInfo': offlinePushInfo?.toJson(),
      'businessCloudCustomData': businessCloudCustomData,
      'localCustomData': localCustomData,
      'isExcludedFromContentModeration': isExcludedFromContentModeration,
      // V2TimMessage.fromJson can rebuild the SDK-created local message after
      // a process restart. Media paths are retained separately as well.
      'message': message.toJson(),
    });
  } catch (_) {
    return null;
  }
}

String? _mediaLocalReference(V2TimMessage? message) {
  final candidates = <String?>[
    message?.imageElem?.path,
    message?.videoElem?.videoPath,
    message?.videoElem?.snapshotPath,
    message?.soundElem?.path,
    message?.fileElem?.path,
  ];
  for (final candidate in candidates) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

OutgoingMessageKind _messageKindFor(int? elemType) {
  switch (elemType) {
    case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
      return OutgoingMessageKind.text;
    case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
      return OutgoingMessageKind.image;
    case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
      return OutgoingMessageKind.video;
    case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
      return OutgoingMessageKind.audio;
    default:
      return OutgoingMessageKind.custom;
  }
}
