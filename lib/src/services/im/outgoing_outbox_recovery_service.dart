import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_external_message_sender.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_payload_cipher.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_media_staging.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_message_recreator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_activity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im_connect_status_service.dart';
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
  OutgoingOutboxRecoveryService._()
      : _leaseContext = (() => ConversationSyncService.instance
            .messageCoreLeaseForOutgoingSend());

  @visibleForTesting
  OutgoingOutboxRecoveryService.forTesting({
    required Future<ImMessageCoreLeaseContext?> Function() leaseContext,
  }) : _leaseContext = leaseContext;

  final Future<ImMessageCoreLeaseContext?> Function() _leaseContext;

  @visibleForTesting
  Future<void> recoverOnceForTesting() =>
      _recover(SessionIdentityService.instance.capture());

  static final OutgoingOutboxRecoveryService instance =
      OutgoingOutboxRecoveryService._();

  Future<void>? _inFlight;
  Timer? _wakeTimer;
  DateTime? _wakeAt;
  SessionIdentity? _scanIdentity;
  String? _continuationOperationId;
  bool _rescanRequested = false;
  bool _runDeferred = false;
  Duration _nextWakeDelay = const Duration(minutes: 1);

  /// A normal send will attempt dispatch immediately after Prepared commits.
  /// This delayed check covers a lost handoff without racing that foreground
  /// dispatch on the same event-loop turn.
  void wakeAfterPreparedCommit() {
    if (_inFlight != null) {
      _rescanRequested = true;
      return;
    }
    _armWake(const Duration(seconds: 1));
  }

  void _armWake(Duration delay) {
    final identity = SessionIdentityService.instance.capture();
    if (identity.ownerUserId.isEmpty) return;
    final target = DateTime.now().add(delay);
    if (_wakeTimer?.isActive == true &&
        _wakeAt != null &&
        !_wakeAt!.isAfter(target)) return;
    _wakeTimer?.cancel();
    _wakeAt = target;
    _wakeTimer = Timer(delay, () {
      _wakeTimer = null;
      _wakeAt = null;
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      if (!ImConnectStatusService.isTransportReady) {
        _armWake(const Duration(minutes: 1));
        return;
      }
      unawaited(recoverPending().catchError((Object error) {
        debugPrint(
            'OUTBOX_RECOVERY wake failed errorType=${error.runtimeType}');
      }));
    });
  }

  Future<void> recoverPending() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _wakeAt = null;
    final running = _inFlight;
    if (running != null) {
      _rescanRequested = true;
      return running;
    }
    final identity = SessionIdentityService.instance.capture();
    if (_scanIdentity != identity) {
      _scanIdentity = identity;
      _continuationOperationId = null;
      _rescanRequested = false;
    }
    late final Future<void> task;
    task = _recover(identity).catchError((Object error, StackTrace stack) {
      _runDeferred = true;
      _nextWakeDelay = const Duration(seconds: 5);
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      if (!identical(_inFlight, task)) return;
      _inFlight = null;
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      if (_runDeferred) {
        _armWake(_nextWakeDelay);
      } else if (_continuationOperationId != null) {
        _armWake(const Duration(milliseconds: 100));
      } else if (_rescanRequested) {
        _rescanRequested = false;
        _armWake(Duration.zero);
      } else {
        _armWake(_nextWakeDelay);
      }
    });
    _inFlight = task;
    return task;
  }

  Future<void> _recover(SessionIdentity identity) async {
    _runDeferred = false;
    _nextWakeDelay = const Duration(minutes: 1);
    if (identity.ownerUserId.isEmpty) return;
    var context = await _leaseContext();
    for (var attempt = 0; context == null && attempt < 5; attempt++) {
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      await Future<void>.delayed(
        Duration(milliseconds: 100 * (1 << attempt)),
      );
      context = await _leaseContext();
    }
    if (context == null || context.ownerUserId != identity.ownerUserId) {
      _runDeferred = true;
      _nextWakeDelay = const Duration(seconds: 5);
      return;
    }
    final persistence = Im05Persistence(store: context.store);
    var cursor = _continuationOperationId ?? '';
    for (var page = 0; page < 10; page++) {
      final rows = await persistence.listOutboxesForRecovery(
        ownerUserId: identity.ownerUserId,
        states: const <ImOutboxState>[
          ImOutboxState.prepared,
          ImOutboxState.dispatchIntent,
          ImOutboxState.sending,
        ],
        limit: 100,
        afterOperationId: cursor,
      );
      if (rows.isEmpty) {
        _continuationOperationId = null;
        await _cleanupOrphansAfterScan(identity, persistence);
        return;
      }
      var stateAdvancedCount = 0;
      var activeSkippedCount = 0;
      for (final row in rows) {
        if (!SessionIdentityService.instance.isCurrent(identity)) return;
        cursor = row.operationId;
        // Reconnect and the delayed Prepared wake can run while the SDK is
        // still uploading. Only orphaned dispatches need reconciliation.
        if (OutgoingSendActivity.instance.isActive(context, row.operationId)) {
          activeSkippedCount++;
          continue;
        }
        if (row.state != ImOutboxState.prepared) {
          if (await persistence.recordOutcomeUnknown(
            ownerUserId: identity.ownerUserId,
            operationId: row.operationId,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: DateTime.now().millisecondsSinceEpoch,
            resultCode: 'recovered_after_dispatch_intent',
          )) stateAdvancedCount++;
          continue;
        }
        final plaintext = await OutboxPayloadCipher.instance.reveal(
          ownerUserId: identity.ownerUserId,
          value: row.payloadReference,
        );
        final envelope = plaintext == null ? null : _decodeEnvelope(plaintext);
        if (envelope == null) {
          if (await persistence.markPreparedOutboxManualRequired(
            ownerUserId: identity.ownerUserId,
            operationId: row.operationId,
            reason: plaintext == null
                ? 'payload_key_unavailable_or_ciphertext_invalid'
                : 'payload_envelope_invalid',
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          )) stateAdvancedCount++;
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
          if (await persistence.markPreparedOutboxManualRequired(
            ownerUserId: identity.ownerUserId,
            operationId: row.operationId,
            reason: 'message_recreation_failed',
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          )) stateAdvancedCount++;
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
        if (result.state != ExternalMessageSendState.blocked) {
          stateAdvancedCount++;
        }
        if (result.state == ExternalMessageSendState.blocked) {
          debugPrint(
            'OUTBOX_RECOVERY blocked operationId=${row.operationId}',
          );
        }
      }
      debugPrint('OUTBOX_RECOVERY scanned=${rows.length} '
          'advanced=$stateAdvancedCount activeSkipped=$activeSkippedCount '
          'page=$page');
      if (rows.length < 100) {
        _continuationOperationId = null;
        await _cleanupOrphansAfterScan(identity, persistence);
        return;
      }
      _continuationOperationId = cursor;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _cleanupOrphansAfterScan(
    SessionIdentity identity,
    Im05Persistence persistence,
  ) async {
    if (!SessionIdentityService.instance.isCurrent(identity)) return;
    try {
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
      if (!SessionIdentityService.instance.isCurrent(identity)) return;
      // A capped reference set is not safe evidence for file deletion.
      if (activeRows.length >= 5000) return;
      await OutgoingMediaStager.instance.cleanupOrphans(
        activeRootPaths: activeRows.map((row) => row.mediaLocalRef),
      );
      await OutgoingMediaStager.instance.cleanupLiveOrphans();
    } catch (error) {
      debugPrint('OUTBOX_RECOVERY orphan cleanup deferred '
          'errorType=${error.runtimeType}');
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
