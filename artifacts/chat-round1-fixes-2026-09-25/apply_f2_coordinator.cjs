const fs=require('fs');
const file='lib/src/services/im/outgoing_send_coordinator.dart';
let s=fs.readFileSync(file,'utf8');
const a=s.indexOf('    var providerConfirmed = false;');
const b=s.indexOf('\n  Future<bool> completeSuccessfulProjection(',a);
if(a<0||b<0)throw Error('coordinator result boundary');
s=s.slice(0,a)+`    ImOutboxResultVerdict? verdict;
    var localStatePending = false;
    if (persistOutbox) {
      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        if (sdk.isOutcomeUnknown) {
          await persistence.recordOutcomeUnknown(
            ownerUserId: context.ownerUserId, operationId: identity.operationId,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken, nowMs: now,
            resultCode: callback.code.toString(),
          );
          verdict = await persistence.readOutboxResult(
              ownerUserId: context.ownerUserId, operationId: identity.operationId);
        } else {
          verdict = await persistence.adjudicateOutboxSdkResult(
            ownerUserId: context.ownerUserId, operationId: identity.operationId,
            expectedAttemptId: dispatchAttemptId, succeeded: sdk.isSuccess,
            leaseOwnerId: context.lease.leaseOwnerId,
            fencingToken: context.lease.fencingToken, nowMs: now,
            sdkLocalId: sendLocalId, serverMsgId: formalIdentity.serverMsgId,
            resultCode: callback.code.toString(),
          );
        }
      } catch (error) {
        // A valid SDK success remains success. A failed local transaction is
        // pending repair, never permission to dispatch this operation again.
        localStatePending = true;
        debugPrint('[IM_SEND_COORDINATOR] result persistence pending: ' + error.runtimeType.toString());
      }
    }
    return ImCoordinatedSendResult(
      sdkResult: callback, usedOutbox: persistOutbox, identity: formalIdentity,
      accountGeneration: context.accountGeneration,
      domainGeneration: context.domainGeneration,
      outcomeUnknown: sdk.isOutcomeUnknown,
      outboxResult: verdict, resultView: resultView,
      localStatePending: localStatePending,
    );
  }
`+s.slice(b);
fs.writeFileSync(file,s);
