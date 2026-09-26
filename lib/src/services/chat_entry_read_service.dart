import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';

import 'conversation_local/conversation_local_store.dart';
import 'conversation_local/conversation_unread_aggregate.dart';
import 'conversation_unread_clear_service.dart';
import 'conversation_unread_trace.dart';
import 'im/conversation_read_policy.dart';
import 'im/read_outbox_store.dart';
import 'im/tencent_conversation_read_service.dart';
import 'session_identity.dart';

class _EntryReadFlight {
  const _EntryReadFlight(this.isCurrent, this.boundary, this.future);
  final bool Function() isCurrent;
  final String boundary;
  final Future<bool> future;
}

/// A normal chat entry explicitly clears that conversation once. Durable
/// retries retain the captured boundary, never a replayable "clear all" flag.
class ChatEntryReadService {
  static final Map<String, _EntryReadFlight> _flights = {};

  static String _sdkConversationID(V2TimConversation conversation) {
    final id = conversation.conversationID.trim();
    if (id.startsWith('group_') || id.startsWith('c2c_')) return id;
    final group = conversation.groupID?.trim() ?? '';
    final peer = conversation.userID?.trim() ?? '';
    if ((id == 'c2c' || id == 'group') && group.isEmpty && peer.isEmpty) {
      return '';
    }
    if (conversation.type == 2 || group.isNotEmpty) {
      final raw = group.isNotEmpty ? group : id;
      return raw.startsWith('group_') ? raw : 'group_$raw';
    }
    final raw = peer.isNotEmpty ? peer : id;
    return raw.startsWith('c2c_') ? raw : 'c2c_$raw';
  }

  static Future<bool> clearOnEntry({
    required V2TimConversation conversation,
    required bool Function() isCurrent,
  }) {
    final id = _sdkConversationID(conversation);
    final owner = ConversationLocalStore.instance.resolvedOwnerUserId();
    final identity =
        SessionIdentityService.instance.capture(ownerUserId: owner);
    bool current() =>
        SessionIdentityService.instance
            .isGenerationCurrent(identity.generation) &&
        isCurrent();
    if (owner.isEmpty ||
        !current() ||
        !ConversationReadPolicy.validTarget(id, 0, 0,
            explicitConversationClear: true)) {
      return Future.value(false);
    }
    // Capture synchronously. A mutable preview can advance during a database
    // write; retries must never pick up messages newer than this entry.
    final message = conversation.lastMessage;
    final messageID = message?.msgID ?? '';
    final isGroup = id.startsWith('group_');
    final rawTime = message?.timestamp ?? 0;
    // C2C clean timestamps are inclusive seconds: an offline retry must not
    // consume a message received after leaving but in the same second.
    final timestamp =
        isGroup ? 0 : ConversationReadPolicy.conservativeTimestamp(rawTime);
    final sequence = isGroup ? int.tryParse(message?.seq ?? '') ?? 0 : 0;
    return _enqueueEntryClear(
        id, identity, current, messageID, timestamp, sequence);
  }

  static Future<bool> _enqueueEntryClear(
    String id,
    SessionIdentity identity,
    bool Function() current,
    String messageID,
    int timestamp,
    int sequence,
  ) {
    final key = '${identity.generation}|${identity.ownerUserId}|$id';
    final boundary = '$timestamp|$sequence|$messageID';
    final running = _flights[key];
    if (running != null) {
      if (running.isCurrent() && running.boundary == boundary) {
        return running.future;
      }
      // A fresh visit or newer notification cannot inherit an older request:
      // that native request may have already completed before the new arrival.
      // Keep the caller's captured retry boundary across this wait.
      return running.future.then((_) async => current()
          ? await _enqueueEntryClear(
              id, identity, current, messageID, timestamp, sequence)
          : false);
    }
    late final Future<bool> task;
    task = _clear(id, identity, current, messageID, timestamp, sequence)
        .whenComplete(() {
      if (identical(_flights[key]?.future, task)) _flights.remove(key);
    });
    _flights[key] = _EntryReadFlight(current, boundary, task);
    return task;
  }

  static Future<bool> _clear(
    String id,
    SessionIdentity identity,
    bool Function() current,
    String messageID,
    int timestamp,
    int sequence,
  ) async {
    final outbox = ConversationReadOutboxStore.instance;
    ConversationReadOutboxRecord? target;
    try {
      await outbox.enqueue(
        ownerUserId: identity.ownerUserId,
        conversationId: id,
        lastReadMessageId: messageID,
        cleanTimestamp: timestamp,
        cleanSequence: sequence,
        retryPausedOnUserAction: true,
      );
      target = await outbox.find(
          ownerUserId: identity.ownerUserId, conversationId: id);
    } catch (error) {
      // Persistence failure must not disable an online explicit SDK read.
      debugPrint(
          'entry read persistence failed errorType=${error.runtimeType}');
    }
    if (!current()) return false;
    if (target != null &&
        target.nextRetryAtMs > DateTime.now().millisecondsSinceEpoch) {
      // A fresh entry must not bypass a persisted SDK frequency cooldown.
      ConversationUnreadTrace.log('chat_entry_read_deferred',
          conversationID: id, extras: {'nextRetryAtMs': target.nextRetryAtMs});
      try {
        await ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: id,
          trigger: SdkUnreadCleanTrigger.recovery,
        );
      } catch (error) {
        debugPrint('entry read deferral failed errorType=${error.runtimeType}');
      }
      return false;
    }
    ConversationUnreadTrace.log('chat_entry_read_start',
        conversationID: id,
        extras: {'retryTimestamp': timestamp, 'retrySequence': sequence});
    V2TimCallback result;
    try {
      result = await TencentConversationReadService.cleanUnread(
        conversationID: id,
        capturedIdentity: identity,
        cleanTimestamp: 0,
        cleanSequence: 0,
        allowFullConversationClean: true,
      ).timeout(const Duration(seconds: 8));
    } catch (error) {
      result = V2TimCallback(code: 6012, desc: 'entry_read_request_failed');
    }
    if (!SessionIdentityService.instance
        .isGenerationCurrent(identity.generation)) {
      return false;
    }
    ConversationUnreadTrace.log('chat_entry_read_done',
        conversationID: id,
        extras: {'sdkCode': result.code, 'stillVisible': current()});
    try {
      if (result.code == 0) {
        if (target != null) {
          await outbox.acknowledge(
            ownerUserId: identity.ownerUserId,
            conversationId: id,
            lastReadAtMs: target.lastReadAtMs,
          );
        }
        // Counts stay SDK-owned even if its callback is late or absent.
        if (!SessionIdentityService.instance
            .isGenerationCurrent(identity.generation)) {
          return false;
        }
        ConversationUnreadAggregate.instance
            .scheduleRefresh(reason: 'sdk_read_confirmed');
      } else if (target != null) {
        await outbox.markRetry(target,
            sdkCode: result.code,
            reason: result.code == -10113 ||
                    ConversationReadPolicy.validTarget(
                        id, target.cleanTimestamp, target.cleanSequence)
                ? null
                : 'blocked:watermark_unavailable',
            notBeforeAtMs: result.code == -10113
                ? DateTime.now().millisecondsSinceEpoch + 12000
                : null);
        // This coordinator may retry only the saved sequence/timestamp. It
        // cannot issue another 0/0 request after the user leaves this page.
        if (!SessionIdentityService.instance
            .isGenerationCurrent(identity.generation)) {
          return false;
        }
        await ConversationUnreadClearService.scheduleSdkUnreadClean(
          conversationID: id,
          trigger: SdkUnreadCleanTrigger.recovery,
        );
      }
    } catch (error) {
      debugPrint('entry read completion failed errorType=${error.runtimeType}');
    }
    return result.code == 0;
  }
}
