import 'dart:async';

import 'package:flutter/foundation.dart';

import 'outgoing_media_work_queue.dart';

/// Serializes ordinary sends, while a selected media batch shares three slots.
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
  final Map<String, _MediaSendBatch> _mediaBatches = {};

  final _imageUploads = OutgoingMediaWorkQueue(maxConcurrent: 3);
  final _videoUploads = OutgoingMediaWorkQueue(maxConcurrent: 1);
  final _fileUploads = OutgoingMediaWorkQueue(maxConcurrent: 2);

  /// Media admission is independent of conversation FIFO and display order.
  /// Slots span batches/conversations so selecting again cannot exceed limits.
  Future<T> runMedia<T>(
    String kind,
    Future<T> Function() action, {
    Duration dispatchTimeout = defaultDispatchTimeout,
  }) {
    final slots = switch (kind) {
      'image' => _imageUploads,
      'video' => _videoUploads,
      'file' => _fileUploads,
      _ => throw ArgumentError.value(kind, 'kind'),
    };
    return slots.run(() async {
      final dispatch = Future<T>.sync(action);
      return dispatchTimeout > Duration.zero
          ? await dispatch.timeout(dispatchTimeout)
          : await dispatch;
    });
  }

  /// Selection order belongs to the message's batch metadata, not upload
  /// completion order. Ordinary sends remain barriers between media batches.
  Future<T> runMediaBatch<T>(
    String conversationKey,
    String batchId,
    Future<T> Function() action, {
    Duration dispatchTimeout = defaultDispatchTimeout,
  }) {
    if (batchId.trim().isEmpty) {
      return runSerial(conversationKey, action,
          dispatchTimeout: dispatchTimeout);
    }
    final previous =
        _tailByConversation[conversationKey] ?? Future<void>.value();
    var batch = _mediaBatches[conversationKey];
    if (batch == null || batch.id != batchId) {
      batch = _MediaSendBatch(batchId, previous);
      _mediaBatches[conversationKey] = batch;
    }
    final currentBatch = batch;
    final result = currentBatch.slots.run(() async {
      await currentBatch.predecessor;
      final dispatch = Future<T>.sync(action);
      return dispatchTimeout > Duration.zero
          ? await dispatch.timeout(dispatchTimeout)
          : await dispatch;
    });
    // Observe failures without poisoning the barrier or hiding them from the
    // caller. A late completion after timeout never dispatches the item again.
    final settled =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    final tail = Future.wait<void>([previous, settled]).then<void>((_) {});
    _tailByConversation[conversationKey] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_tailByConversation[conversationKey], tail)) {
        _tailByConversation.remove(conversationKey);
        if (identical(_mediaBatches[conversationKey], currentBatch)) {
          _mediaBatches.remove(conversationKey);
        }
      }
    }));
    return result;
  }

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
    _mediaBatches.remove(conversationKey);
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
    _mediaBatches.clear();
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

class _MediaSendBatch {
  _MediaSendBatch(this.id, this.predecessor);

  final String id;
  final Future<void> predecessor;
  final slots = OutgoingMediaWorkQueue(maxConcurrent: 3);
}
