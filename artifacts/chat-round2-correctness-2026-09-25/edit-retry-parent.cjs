const fs=require('fs');const edit=(p,f)=>{const s=fs.readFileSync(p,'utf8');fs.writeFileSync(p,f(s));};
edit('lib/src/services/im/outbox_state_version_schema.dart',s=>s.replace("  if (!columns.any((row) => row['name'] == 'state_version')) {",`  for (final column in {'retry_of_operation_id': 'TEXT', 'retry_of_state_version': 'INTEGER'}.entries) {
    if (!columns.any((row) => row['name'] == column.key)) await db.execute('ALTER TABLE message_outbox ADD COLUMN \${column.key} \${column.value}');
  }
  if (!columns.any((row) => row['name'] == 'state_version')) {`));
edit('lib/src/services/im/im05_persistence.dart',s=>{
 // Gate both initial prepare and the final dispatch CAS, including recovered children.
 const marker='  /// Persists both sides of the Prepared boundary before any SDK call.';
 const helper=`  Future<bool> _retryParentIsCurrent(ImIngressTransaction tx, ImOutboxRecord child) async {
    final operation = child.retryOfOperationId;
    if (operation == null) return true;
    final parent = await tx.findOutbox(ownerUserId: child.ownerUserId, operationId: operation);
    final copy = await tx.findOutboxRecovery(ownerUserId: child.ownerUserId, operationId: operation);
    if (parent == null || copy == null || !_sameOutboxIdentity(parent, copy) ||
        parent.conversationId != child.conversationId || parent.payloadHash != child.payloadHash ||
        parent.stateVersion != child.retryOfStateVersion) return false;
    return ImOutboxResultVerdict(decision: ImOutboxResultDecision.current,
      main: parent, recoveryCopy: copy, reason: 'retry_parent').canRetry;
  }

`;
 s=s.replace(marker,helper+marker);
 const a=s.indexOf('  Future<ImOutboxDispatchAssessment> prepareOutbox('),b=s.indexOf('\n  /// Returns whether',a);let c=s.slice(a,b);
 c=c.replace('      final currentMain = await transaction.findOutbox(',`      if (!await _retryParentIsCurrent(transaction, main)) return const ImOutboxDispatchAssessment(decision: ImOutboxDispatchDecision.recoveryConflict);
      final currentMain = await transaction.findOutbox(`);
 s=s.slice(0,a)+c+s.slice(b);
 s=s.replace('      if (!assessment.canDispatch) return assessment;',`      if (!assessment.canDispatch) return assessment;
      if (!await _retryParentIsCurrent(transaction, assessment.main!)) return ImOutboxDispatchAssessment(
        decision: ImOutboxDispatchDecision.recoveryConflict, main: assessment.main, recoveryCopy: assessment.recoveryCopy);`);
 return s;
});
edit('lib/src/services/im/outgoing_send_coordinator.dart',s=>{
 s=s.replace('    SessionIdentity? expectedSessionIdentity,','    SessionIdentity? expectedSessionIdentity,\n    String? retryOfSdkLocalId,\n    void Function()? onDispatchGranted,');
 const old='    final operationId = operationIdOverride?.trim().isNotEmpty == true';
 s=s.replace(old,`    ImOutboxRecord? retryParent;
    if (retryOfSdkLocalId != null) {
      retryParent = await persistence.findOutboxBySdkLocalId(ownerUserId: context.ownerUserId,
        conversationId: scope.storageKey, sdkLocalId: retryOfSdkLocalId);
      final verdict = retryParent == null ? null : await persistence.readOutboxResult(
        ownerUserId: context.ownerUserId, operationId: retryParent.operationId);
      if (verdict?.canRetry != true || !persistOutbox) return _blocked(
        fallbackMessage: fallbackMessage, outcomeUnknown: true, desc: 'retry requires current durable failure');
      retryParent = verdict!.main;
    }
    final retryKey = retryParent == null ? null : sha256.convert(utf8.encode(
      '\${context.ownerUserId}|\${retryParent.operationId}|\${retryParent.stateVersion}')).toString();
    final operationId = operationIdOverride?.trim().isNotEmpty == true`);
 s=s.replace(': newOutgoingOperationId();',": retryKey == null ? newOutgoingOperationId() : 'retry_$retryKey';");
 s=s.replace(': newOutgoingClientCorrelationId();',": retryKey == null ? newOutgoingClientCorrelationId() : 'retry_corr_$retryKey';");
 s=s.replace('persistOutbox && !recoverPreparedOutbox)', 'persistOutbox && !recoverPreparedOutbox && retryParent == null)');
 s=s.replace('final plaintextEnvelope = recoveredPrepared == null','final plaintextEnvelope = recoveredPrepared == null && retryParent == null');
 s=s.replace('final payloadEnvelope = recoveredPrepared?.main?.payloadReference ??','final payloadEnvelope = recoveredPrepared?.main?.payloadReference ?? retryParent?.payloadReference ??');
 s=s.replace('final payloadFingerprint = recoveredPrepared?.main?.payloadHash ??','final payloadFingerprint = recoveredPrepared?.main?.payloadHash ?? retryParent?.payloadHash ??');
 s=s.replace('        operationId: identity.operationId,\n        ownerUserId:', '        operationId: identity.operationId,\n        retryOfOperationId: recoveredPrepared?.main?.retryOfOperationId ?? retryParent?.operationId,\n        retryOfStateVersion: recoveredPrepared?.main?.retryOfStateVersion ?? retryParent?.stateVersion,\n        ownerUserId:');
 s=s.replace('recoveredPrepared?.main?.encryptionVersion ??', 'recoveredPrepared?.main?.encryptionVersion ?? retryParent?.encryptionVersion ??');
 s=s.replace('recoveredPrepared?.main?.keyId ??', 'recoveredPrepared?.main?.keyId ?? retryParent?.keyId ??');
 s=s.replace('recoveredPrepared?.main?.cipherAlgorithm ??', 'recoveredPrepared?.main?.cipherAlgorithm ?? retryParent?.cipherAlgorithm ??');
 s=s.replace('recoveredPrepared?.main?.nonce ??', 'recoveredPrepared?.main?.nonce ?? retryParent?.nonce ??');
 s=s.replace('    final sdk = await adapter.send(',`    try { onDispatchGranted?.call(); } catch (error) {
      debugPrint('outbox dispatch UI pending: \${error.runtimeType}');
    }
    final sdk = await adapter.send(`);
 return s;
});
