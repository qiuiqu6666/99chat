import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_message_recreator.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_priority_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// Recovers only operations that never crossed DispatchIntent.
///
/// Prepared is safe to dispatch because the Coordinator writes
/// DispatchIntent immediately before the SDK call. dispatchIntent/sending are
/// OutcomeUnknown and are never automatically resent.
class OutgoingOutboxRecoveryService {
  OutgoingOutboxRecoveryService._();

  static final OutgoingOutboxRecoveryService instance =
      OutgoingOutboxRecoveryService._();

  Future<void>? _inFlight;

  Future<void> recoverPending() {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> task;
    task = _recover().whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
    _inFlight = task;
    return task;
  }

  Future<void> _recover() async {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    var context = await ConversationSyncService.instance
        .messageCoreLeaseForOutgoingSend();
    for (var attempt = 0; context == null && attempt < 5; attempt++) {
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      await Future<void>.delayed(
        Duration(milliseconds: 100 * (1 << attempt)),
      );
      context = await ConversationSyncService.instance
          .messageCoreLeaseForOutgoingSend();
    }
    if (context == null || context.ownerUserId != identity.ownerUserId) return;
    final persistence = Im05Persistence(store: context.store);
    final activeRows = await persistence.listOutboxesForRecovery(
      ownerUserId: identity.ownerUserId,
      states: const <ImOutboxState>[
        ImOutboxState.created,
        ImOutboxState.preparing,
        ImOutboxState.prepared,
        ImOutboxState.dispatchIntent,
        ImOutboxState.sending,
        ImOutboxState.outcomeUnknown,
        ImOutboxState.retryable,
        ImOutboxState.acknowledged,
        ImOutboxState.manualRequired,
        ImOutboxState.pausedByLogout,
      ],
      limit: 5000,
    );
    // If the safety scan hit its cap, preserve everything instead of deleting
    // a directory whose Outbox row may be beyond this page.
    if (activeRows.length < 5000) {
      await OutgoingMediaStager.instance.cleanupOrphans(
        activeRootPaths: activeRows.map((row) => row.mediaLocalRef),
      );
      await OutgoingMediaStager.instance.cleanupLiveOrphans();
    }
    for (var page = 0; page < 10; page++) {
      final rows = await persistence.listOutboxesForRecovery(
        ownerUserId: identity.ownerUserId,
        states: const <ImOutboxState>[
          ImOutboxState.prepared,
          ImOutboxState.dispatchIntent,
          ImOutboxState.sending,
        ],
        limit: 100,
      );
      if (rows.isEmpty) return;
      var madeProgress = false;
      for (final row in rows) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        if (row.state != ImOutboxState.prepared) {
          madeProgress = await persistence.recordOutcomeUnknown(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
                resultCode: 'recovered_after_dispatch_intent',
              ) ||
              madeProgress;
          continue;
        }
        final plaintext = await OutboxPayloadCipher.instance.reveal(
          ownerUserId: identity.ownerUserId,
          value: row.payloadReference,
        );
        final envelope = plaintext == null ? null : _decodeEnvelope(plaintext);
        if (envelope == null) {
          madeProgress = await persistence.markPreparedOutboxManualRequired(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                reason: plaintext == null
                    ? 'payload_key_unavailable_or_ciphertext_invalid'
                    : 'payload_envelope_invalid',
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
              ) ||
              madeProgress;
          debugPrint(
            'OUTBOX_RECOVERY manual required for prepared payload '
            'operationId=${row.operationId}',
          );
          continue;
        }
        final recreated = await recreateOutgoingMessage(
          serviceLocator<MessageService>(),
          envelope.message,
        );
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        if (recreated?.messageInfo == null ||
            (recreated?.id?.trim().isEmpty ?? true)) {
          madeProgress = await persistence.markPreparedOutboxManualRequired(
                ownerUserId: identity.ownerUserId,
                operationId: row.operationId,
                reason: 'message_recreation_failed',
                leaseOwnerId: context.lease.leaseOwnerId,
                fencingToken: context.lease.fencingToken,
                nowMs: DateTime.now().millisecondsSinceEpoch,
              ) ||
              madeProgress;
          debugPrint(
            'OUTBOX_RECOVERY manual required; cannot recreate payload '
            'operationId=${row.operationId}',
          );
          continue;
        }
        final result =
            await ChatExternalMessageSender.sendCreatedMessageDetailed(
          messageInfo: recreated!.messageInfo,
          receiverUserId: envelope.receiver,
          groupId: envelope.groupId,
          reason: 'outbox_prepared_recovery',
          isExcludedFromUnreadCount: envelope.isExcludedFromUnreadCount,
          priority: envelope.priority,
          onlineUserOnly: envelope.onlineUserOnly,
          needReadReceipt: envelope.needReadReceipt,
          offlinePushInfo: envelope.offlinePushInfo,
          cloudCustomData: envelope.cloudCustomData,
          localCustomData: envelope.localCustomData,
          recoverPreparedOutbox: true,
          operationIdOverride: row.operationId,
          clientCorrelationIdOverride: row.clientCorrelationId,
        );
        madeProgress =
            result.state != ExternalMessageSendState.blocked || madeProgress;
        if (result.state == ExternalMessageSendState.blocked) {
          debugPrint(
            'OUTBOX_RECOVERY blocked operationId=${row.operationId}',
          );
        }
      }
      if (rows.length < 100 || !madeProgress) return;
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _RecoveredOutgoingEnvelope {
  const _RecoveredOutgoingEnvelope({
    required this.message,
    required this.receiver,
    required this.groupId,
    required this.isExcludedFromUnreadCount,
    required this.priority,
    required this.onlineUserOnly,
    required this.needReadReceipt,
    required this.offlinePushInfo,
    required this.cloudCustomData,
    required this.localCustomData,
  });

  final V2TimMessage message;
  final String receiver;
  final String groupId;
  final bool isExcludedFromUnreadCount;
  final MessagePriorityEnum priority;
  final bool onlineUserOnly;
  final bool needReadReceipt;
  final OfflinePushInfo? offlinePushInfo;
  final String? cloudCustomData;
  final String? localCustomData;
}

_RecoveredOutgoingEnvelope? _decodeEnvelope(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['schemaVersion'] != 1) return null;
    final messageJson = decoded['message'];
    if (messageJson is! Map) return null;
    final message = V2TimMessage.fromJson(
      Map<String, dynamic>.from(messageJson),
    );
    final storedLocalId = decoded['sdkLocalId']?.toString().trim() ?? '';
    final messageLocalId = message.id?.trim() ?? '';
    if (storedLocalId.isEmpty ||
        (messageLocalId.isNotEmpty && messageLocalId != storedLocalId)) {
      return null;
    }
    if (messageLocalId.isEmpty) message.id = storedLocalId;
    final receiver = decoded['receiver']?.toString().trim() ?? '';
    final groupId = decoded['groupID']?.toString().trim() ?? '';
    if ((receiver.isEmpty && groupId.isEmpty) ||
        (receiver.isNotEmpty && groupId.isNotEmpty)) {
      return null;
    }
    final priorityIndex = decoded['priority'] is int
        ? decoded['priority'] as int
        : MessagePriorityEnum.V2TIM_PRIORITY_NORMAL.index;
    final priority =
        priorityIndex >= 0 && priorityIndex < MessagePriorityEnum.values.length
            ? MessagePriorityEnum.values[priorityIndex]
            : MessagePriorityEnum.V2TIM_PRIORITY_NORMAL;
    final pushJson = decoded['offlinePushInfo'];
    return _RecoveredOutgoingEnvelope(
      message: message,
      receiver: receiver,
      groupId: groupId,
      isExcludedFromUnreadCount: decoded['isExcludedFromUnreadCount'] == true,
      priority: priority,
      onlineUserOnly: decoded['onlineUserOnly'] == true,
      needReadReceipt: decoded['needReadReceipt'] == true,
      offlinePushInfo: pushJson is Map
          ? OfflinePushInfo.fromJson(Map<String, dynamic>.from(pushJson))
          : null,
      cloudCustomData: decoded['businessCloudCustomData']?.toString(),
      localCustomData: decoded['localCustomData']?.toString(),
    );
  } catch (_) {
    return null;
  }
}
