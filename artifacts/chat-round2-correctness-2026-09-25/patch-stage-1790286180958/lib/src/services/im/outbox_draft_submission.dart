import 'dart:async';

/// Opaque edit identity, independent of text equality and process-local counters.
class ImDraftAcceptance {
  const ImDraftAcceptance(
      {required this.ownerUserId,
      required this.conversationId,
      required this.draftId,
      required this.protectedText});
  final String ownerUserId;
  final String conversationId;
  final String draftId;
  final String protectedText;
}

abstract interface class ImDraftTransaction {
  Future<Map<String, Object?>?> findDraftHead(
      String owner, String conversation);
  Future<void> saveDraftHead(ImDraftAcceptance draft);
  Future<void> acceptDraft(ImDraftAcceptance draft, String operationId);
}

abstract interface class ImDurableTextSubmission {
  ImDraftSubmissionContext? get durableContext;
}

/// Carries acceptance through existing async SDK-create/send calls without a
/// second coordinator. No UI clear occurs until prepareOutbox has committed.
class ImDraftSubmissionContext {
  ImDraftSubmissionContext({required this.prepare, required this.isCurrent});
  final Future<ImDraftAcceptance> Function() prepare;
  final bool Function() isCurrent;
  static final Object _zoneKey = Object();
  static ImDraftSubmissionContext? get current =>
      Zone.current[_zoneKey] as ImDraftSubmissionContext?;
  String? acceptedOperationId;
  void Function()? _onAccepted;
  final List<void Function()> _acceptedListeners = [];
  void onAccepted(void Function() listener) => _acceptedListeners.add(listener);
  Future<T> run<T>(Future<T> Function() action, void Function() onAccepted) {
    _onAccepted = onAccepted;
    return runZoned(action, zoneValues: {_zoneKey: this});
  }

  void accepted(String operationId) {
    if (acceptedOperationId != null) return;
    acceptedOperationId = operationId;
    for (final listener in _acceptedListeners) {
      listener();
    }
    _acceptedListeners.clear();
    _onAccepted?.call();
  }
}
