const fs = require('fs');
const file = 'lib/src/services/im/im05_persistence.dart';
let s = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
function replaceMethod(start, end, body) {
 const a=s.indexOf(start), b=s.indexOf(end,a);
 if(a<0||b<0)throw Error('missing method boundary '+start);
 s=s.slice(0,a)+body+s.slice(b);
}
replaceMethod('  Future<bool> adoptOutboxProviderSucceeded({', '  Future<bool> recordOutboxSdkFailed({', `  Future<bool> adoptOutboxProviderSucceeded({
    required String ownerUserId, required String operationId,
    required String clientCorrelationId, required String conversationId,
    required String payloadHash, required String leaseOwnerId,
    required int fencingToken, required int nowMs,
    String? sdkLocalId, String? serverMsgId,
  }) async {
    final result = await _recordOutboxSdkResult(
      ownerUserId: ownerUserId, operationId: operationId,
      leaseOwnerId: leaseOwnerId, fencingToken: fencingToken, nowMs: nowMs,
      nextMainState: ImOutboxState.acknowledged, providerEvidence: true,
      expectedCorrelationId: clientCorrelationId,
      expectedConversationId: conversationId, expectedPayloadHash: payloadHash,
      sdkLocalId: sdkLocalId, serverMsgId: serverMsgId,
      resultCode: 'provider_observed',
    );
    return result.accepted && result.deliveryConfirmed;
  }

`);
// Keep the bool compatibility APIs; their result now means the requested
// result was adopted/idempotent, rather than merely that the row is completed.
for(const start of ['  Future<bool> recordOutboxSdkSucceeded({','  Future<bool> recordOutboxSdkFailed({']) {
 const a=s.indexOf(start),b=s.indexOf('\n  }\n',a);
 let part=s.slice(a,b);
 const ending=part.lastIndexOf('    );');
 if(ending<0)throw Error('wrapper ending');
 part=part.slice(0,ending)+'    ).then((result) => result.accepted);'+part.slice(ending+6);
 s=s.slice(0,a)+part+s.slice(b);
}
replaceMethod('  Future<bool> _recordOutboxSdkResult({','  Future<ImOutboxDispatchAssessment> recoverOutbox({',`  Future<ImOutboxResultVerdict> _recordOutboxSdkResult({
    required String ownerUserId, required String operationId,
    required String leaseOwnerId, required int fencingToken, required int nowMs,
    required ImOutboxState nextMainState,
    String? sdkLocalId, String? serverMsgId, String? resultCode,
    String? expectedAttemptId, bool providerEvidence = false,
    String? expectedCorrelationId, String? expectedConversationId,
    String? expectedPayloadHash,
  }) async {
    if (nextMainState != ImOutboxState.acknowledged &&
        nextMainState != ImOutboxState.failedTerminal) {
      throw ArgumentError.value(nextMainState, 'nextMainState');
    }
    final result = await _store.transaction<ImOutboxResultVerdict>((transaction) async {
      if (!await _hasCurrentLease(transaction, ownerUserId, leaseOwnerId, fencingToken, nowMs)) {
        return const ImOutboxResultVerdict(decision: ImOutboxResultDecision.fencingRejected,
            reason: 'writer_lease_rejected');
      }
      final main = await transaction.findOutbox(ownerUserId: ownerUserId, operationId: operationId);
      final copy = await transaction.findOutboxRecovery(ownerUserId: ownerUserId, operationId: operationId);
      ImOutboxResultVerdict verdict(ImOutboxResultDecision decision, String reason) =>
          ImOutboxResultVerdict(decision: decision, main: main, recoveryCopy: copy,
              eventAttemptId: expectedAttemptId, reason: reason);
      if (main == null || copy == null) return verdict(ImOutboxResultDecision.missing, 'outbox_missing');
      if (!_sameOutboxIdentity(main, copy) ||
          (main.dispatchAttemptId != null && copy.dispatchAttemptId != null &&
              main.dispatchAttemptId != copy.dispatchAttemptId) ||
          (providerEvidence && (main.clientCorrelationId != expectedCorrelationId ||
              main.conversationId != expectedConversationId || main.payloadHash != expectedPayloadHash))) {
        return verdict(ImOutboxResultDecision.identityConflict, 'outbox_identity_conflict');
      }
      if (!providerEvidence && expectedAttemptId != null && main.dispatchAttemptId != expectedAttemptId) {
        return verdict(ImOutboxResultDecision.staleAttempt, 'stale_dispatch_attempt');
      }
      if (main.state == ImOutboxState.acknowledged || main.state == ImOutboxState.completed) {
        return verdict(nextMainState == ImOutboxState.acknowledged
            ? ImOutboxResultDecision.duplicate : ImOutboxResultDecision.superseded,
            'delivery_already_confirmed');
      }
      if (main.state == nextMainState &&
          (copy.state == ImOutboxCopyState.resultRecorded || copy.state == ImOutboxCopyState.reconciled)) {
        return verdict(ImOutboxResultDecision.duplicate, 'result_already_recorded');
      }
      // A late dispatch callback is never a recovery query. Exact provider
      // evidence may settle an older attempt of the SAME business operation.
      final providerCanSettle = providerEvidence && <ImOutboxState>{
        ImOutboxState.sending, ImOutboxState.dispatchIntent,
        ImOutboxState.outcomeUnknown, ImOutboxState.failedTerminal,
        ImOutboxState.abandonedByUser,
      }.contains(main.state);
      if (!providerCanSettle && main.state != ImOutboxState.sending) {
        return verdict(ImOutboxResultDecision.deferred, 'state_requires_recovery_evidence');
      }
      if (!<ImOutboxCopyState>{ImOutboxCopyState.dispatchIntent,
          ImOutboxCopyState.outcomeUnknown, ImOutboxCopyState.resultRecorded,
          ImOutboxCopyState.reconciled}.contains(copy.state)) {
        return verdict(ImOutboxResultDecision.identityConflict, 'recovery_state_conflict');
      }
      final resultCopy = ImOutboxRecoveryRecord(
        ownerUserId: copy.ownerUserId, operationId: copy.operationId,
        clientCorrelationId: copy.clientCorrelationId, conversationId: copy.conversationId,
        messageType: copy.messageType, recoveryRevision: copy.recoveryRevision + 1,
        state: copy.state == ImOutboxCopyState.outcomeUnknown || copy.state == ImOutboxCopyState.reconciled
            ? ImOutboxCopyState.reconciled : ImOutboxCopyState.resultRecorded,
        dispatchAttemptId: copy.dispatchAttemptId, dispatchIntentAtMs: copy.dispatchIntentAtMs,
        payloadReferenceOrCiphertext: copy.payloadReferenceOrCiphertext,
        payloadHash: copy.payloadHash, checksum: copy.checksum,
        sdkLocalId: copy.sdkLocalId ?? sdkLocalId, serverMsgId: serverMsgId ?? copy.serverMsgId,
        resultCode: resultCode ?? copy.resultCode, updatedAtMs: nowMs,
      );
      final changedCopy = await transaction.updateOutboxRecoveryIfCurrent(
        record: resultCopy, expectedState: copy.state, leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken, nowMs: nowMs);
      if (!changedCopy) throw StateError('Outbox result copy CAS rejected');
      final resultMain = main.copyWith(state: nextMainState,
        sdkMessageId: main.sdkMessageId ?? sdkLocalId, serverMsgId: serverMsgId,
        resultCode: resultCode, updatedAtMs: nowMs, leaseOwnerId: leaseOwnerId, fencingToken: fencingToken);
      final changedMain = await transaction.updateOutboxIfCurrent(
        record: resultMain, expectedState: main.state, leaseOwnerId: leaseOwnerId,
        fencingToken: fencingToken, nowMs: nowMs);
      // Throw, rather than committing only one side of the transaction.
      if (!changedMain) throw StateError('Outbox result main CAS rejected');
      return ImOutboxResultVerdict(decision: ImOutboxResultDecision.accepted,
          main: resultMain, recoveryCopy: resultCopy, eventAttemptId: expectedAttemptId,
          reason: providerEvidence ? 'provider_observed' : 'sdk_result');
    });
    return _publishResult(result);
  }

`);
fs.writeFileSync(file,s);
