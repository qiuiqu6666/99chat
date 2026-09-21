import 'dart:async';

import 'package:flutter/foundation.dart';

/// Serializes SDK send dispatch and completion per conversation.
///
/// A timed-out native call releases the queue after [dispatchTimeout]; the
/// native operation itself may still complete later and must be reconciled by
/// the caller as an unknown outcome.
class OutgoingMessageSendQueue {
  OutgoingMessageSendQueue._();

  static final OutgoingMessageSendQueue instance = OutgoingMessageSendQueue._();

  /// A native media upload may never complete when the platform channel or
  /// socket is interrupted. The timeout does not cancel the native operation;
  /// callers must treat [TimeoutException] as an unknown outcome and reconcile
  /// it through the outgoing identity contract before offering a retry.
  static const Duration defaultDispatchTimeout = Duration(minutes: 3);

  final Map<String, Future<void>> _tailByConversation = {};

  static String conversationKey({
    required String receiver,
    required String groupID,
  }) {
    final group = groupID.trim();
    if (group.isNotEmpty) {
      return 'group:$group';
    }
    return 'c2c:${receiver.trim()}';
  }

  Future<T> runSerial<T>(
    String conversationKey,
    Future<T> Function() action, {
    Duration dispatchTimeout = defaultDispatchTimeout,
  }) {
    final previous =
        _tailByConversation[conversationKey] ?? Future<void>.value();
    final result = Completer<T>();
    late final Future<void> tail;
    tail = previous.catchError((_) {}).then<void>((_) async {
      final dispatch = Future<T>.sync(action);
      final bounded = dispatchTimeout > Duration.zero
          ? dispatch.timeout(dispatchTimeout)
          : dispatch;
      try {
        final value = await bounded;
        if (!result.isCompleted) {
          result.complete(value);
        }
      } catch (error, stackTrace) {
        if (!result.isCompleted) {
          result.completeError(error, stackTrace);
        }
      }
    });
    _tailByConversation[conversationKey] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_tailByConversation[conversationKey], tail)) {
        _tailByConversation.remove(conversationKey);
      }
    }));
    return result.future;
  }

  /// Releases completed tails at an account boundary. In-flight SDK calls
  /// cannot be cancelled here; their caller must also enforce session identity.
  void clearSession() {
    _tailByConversation.clear();
  }

  @visibleForTesting
  void resetForTesting() {
    clearSession();
  }

  @visibleForTesting
  bool hasPending(String conversationKey) {
    return _tailByConversation.containsKey(conversationKey);
  }
}
