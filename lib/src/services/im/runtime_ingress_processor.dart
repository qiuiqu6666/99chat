import 'dart:async';
import 'im_ingress_store.dart';

/// Ordered host commit protocol for both live ingress and Inbox recovery.
/// Owns stage ordering only: persistence, projection and Outbox implementations
/// retain their identities. A failed stage remains recoverable at its last
/// durable checkpoint. No projection is allowed before metadata acknowledgement.
class RuntimeIngressProcessor {
  const RuntimeIngressProcessor();

  Future<bool> run({
    required ImInboxStatus status,
    required bool Function() isCurrent,
    required Future<void> Function() applyMetadata,
    required Future<void> Function() flushMetadata,
    required Future<bool> Function(ImInboxStatus from, ImInboxStatus to)
        advance,
    required Future<bool> Function() adoptOutgoing,
    required Future<void> Function() publish,
    required Future<void> Function() completeOutgoing,
  }) async {
    if (!isCurrent()) return false;
    if (status == ImInboxStatus.completed) return true;
    if (status != ImInboxStatus.processing &&
        status != ImInboxStatus.metadataCommitted &&
        status != ImInboxStatus.projectionPublished) {
      throw StateError('Ingress must be claimed before runtime processing');
    }
    if (status == ImInboxStatus.processing) {
      await applyMetadata();
      if (!isCurrent()) return false;
      await flushMetadata();
      if (!isCurrent()) return false;
      if (!await advance(
          ImInboxStatus.processing, ImInboxStatus.metadataCommitted)) {
        return false;
      }
      status = ImInboxStatus.metadataCommitted;
    }
    if (!isCurrent()) return false;
    final outgoing = await adoptOutgoing();
    if (!isCurrent()) return false;
    if (status == ImInboxStatus.metadataCommitted) {
      await publish();
      if (!isCurrent()) return false;
      if (!await advance(
          ImInboxStatus.metadataCommitted, ImInboxStatus.projectionPublished)) {
        return false;
      }
    }
    if (!isCurrent()) return false;
    if (outgoing) {
      await completeOutgoing();
      if (!isCurrent()) return false;
    }
    return advance(ImInboxStatus.projectionPublished, ImInboxStatus.completed);
  }
}
