const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const replace=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,120));s=s.replace(a,b);}; fn(replace,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
if (!fs.readFileSync('lib/src/services/im/im05_contracts.dart','utf8').includes('final int stateVersion;')) edit('lib/src/services/im/im05_contracts.dart',(r)=>{
 r('this.recoveryConflict = false,','this.recoveryConflict = false,\n    this.stateVersion = 1,');
 r('final bool recoveryConflict;','final bool recoveryConflict;\n  final int stateVersion;');
 r('bool? recoveryConflict,','bool? recoveryConflict,\n    int? stateVersion,');
 r('recoveryConflict: recoveryConflict ?? this.recoveryConflict,','recoveryConflict: recoveryConflict ?? this.recoveryConflict,\n      stateVersion: stateVersion ?? this.stateVersion,');
 r("'recovery_conflict': record.recoveryConflict ? 1 : 0,","'recovery_conflict': record.recoveryConflict ? 1 : 0,\n      'state_version': record.stateVersion,");
 r("recoveryConflict: _int(row['recovery_conflict']) != 0,","recoveryConflict: _int(row['recovery_conflict']) != 0,\n      stateVersion: _optionalInt(row['state_version']) ?? 1,");
});
edit('lib/src/services/im/im05_persistence.dart',(r,get,set)=>{
 r("import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';","import 'package:flutter/foundation.dart';\nimport 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';");
 r('  missing,','  missing,\n  unavailable,');
 r('int get stateVersion => recoveryCopy?.recoveryRevision ?? 0;','int get stateVersion => main?.stateVersion ?? 0;');
 r('      recoveryCopy != null &&','      (recoveryCopy != null || main!.state == ImOutboxState.completed ||\n          main!.state == ImOutboxState.acknowledged) &&');
 r('decision != ImOutboxResultDecision.missing;','decision != ImOutboxResultDecision.missing &&\n      decision != ImOutboxResultDecision.unavailable;');
 r('class ImOutboxResultView {','class ImOutboxResultView extends ChangeNotifier {');
 r('  ImOutboxResultVerdict? get current => _current;','  ImOutboxResultVerdict? get current => _current;\n  void _publish(ImOutboxResultVerdict value) {\n    if (_current != null && value.stateVersion <= _current!.stateVersion) return;\n    _current = value;\n    notifyListeners();\n  }');
 r('  ImOutboxResultView watchOutboxResult', '  Object get _viewScope => _store is ImOutboxObservationScope\n      ? (_store as ImOutboxObservationScope).outboxObservationScope : _store;\n\n  ImOutboxResultView watchOutboxResult');
 r('final views = _resultViews[_store] ??= {};','final views = _resultViews[_viewScope] ??= {};');
 const start=get().indexOf('  ImOutboxResultVerdict _publishResult('),end=get().indexOf('  Future<ImOutboxResultVerdict> readOutboxResult',start);
 set(get().slice(0,start)+`  static void publishCommitted(Object scope, ImOutboxRecord main,
      ImOutboxRecoveryRecord? copy) {
    final trusted = copy == null
        ? main.state == ImOutboxState.completed || main.state == ImOutboxState.acknowledged
        : _sameOutboxIdentity(main, copy);
    if (!trusted) return;
    final views = _resultViews[scope];
    views?.removeWhere((_, reference) => reference.target == null);
    views?[main.ownerUserId + '|' + main.operationId]?.target?._publish(
      ImOutboxResultVerdict(decision: ImOutboxResultDecision.current,
        main: main, recoveryCopy: copy, reason: 'committed_snapshot'));
  }

  ImOutboxResultVerdict _publishResult(ImOutboxResultVerdict result) {
    if (result.hasTrustedSnapshot) {
      publishCommitted(_viewScope, result.main!, result.recoveryCopy);
    }
    return result;
  }

`+get().slice(end));
 r('    final result = await _store.transaction<ImOutboxResultVerdict>((tx) async {','    try {\n    final result = await _store.transaction<ImOutboxResultVerdict>((tx) async {');
 r("      if (main == null || copy == null) {\n        return const ImOutboxResultVerdict(\n            decision: ImOutboxResultDecision.missing, reason: 'outbox_missing');\n      }",`      if (main == null) {
        return ImOutboxResultVerdict(decision: copy == null
            ? ImOutboxResultDecision.missing : ImOutboxResultDecision.deferred,
          recoveryCopy: copy, reason: copy == null ? 'no_durable_identity' : 'main_recovery_pending');
      }
      if (copy == null) {
        return ImOutboxResultVerdict(decision:
          main.state == ImOutboxState.completed || main.state == ImOutboxState.acknowledged
            ? ImOutboxResultDecision.current : ImOutboxResultDecision.deferred,
          main: main, reason: 'recovery_material_absent');
      }`);
 r('    return _publishResult(result);\n  }\n\n  Future<ImOutboxResultVerdict> adjudicate',`    return _publishResult(result);
    } catch (error) {
      return ImOutboxResultVerdict(decision: ImOutboxResultDecision.unavailable,
        reason: 'storage_unavailable:' + error.runtimeType.toString());
    }
  }

  Future<ImOutboxResultVerdict> adjudicate`);
 r('        main: intentMain,','        main: await transaction.findOutbox(ownerUserId: ownerUserId, operationId: operationId),');
 r('          main: resultMain,','          main: await transaction.findOutbox(ownerUserId: ownerUserId, operationId: operationId),');
 r("        return const ImOutboxDispatchAssessment(\n          decision: ImOutboxDispatchDecision.recoveryConflict,\n        );\n      }\n      return ImOutboxDispatchAssessment(\n        decision: ImOutboxDispatchDecision.ready,","        throw StateError('Outbox dispatch CAS rejected');\n      }\n      return ImOutboxDispatchAssessment(\n        decision: ImOutboxDispatchDecision.ready,");
});
edit('lib/src/services/im/im_ingress_store.dart',(r,get,set)=>{
 r("import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';", "import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';\nimport 'im05_persistence.dart';\nimport 'outbox_state_version_schema.dart';");
 const marker='class ConversationLocalImIngressStore implements ImIngressStore {';
 r(marker,`abstract interface class ImOutboxObservationScope {
  Object get outboxObservationScope;
}

mixin ImOutboxCommitTracking on ImIngressTransaction {
  final Set<(String, String)> observedOutboxes = {};
  Future<List<(ImOutboxRecord, ImOutboxRecoveryRecord?)>> committedOutboxes() async {
    final result = <(ImOutboxRecord, ImOutboxRecoveryRecord?)>[];
    for (final (owner, operation) in observedOutboxes.toList()) {
      final main = await findOutbox(ownerUserId: owner, operationId: operation);
      if (main != null) result.add((main, await findOutboxRecovery(ownerUserId: owner, operationId: operation)));
    }
    return result;
  }
}

class ConversationLocalImIngressStore implements ImIngressStore, ImOutboxObservationScope {`);
 r('  final MessageCoreStore _core;','  final MessageCoreStore _core;\n  bool _outboxSchemaReady = false;\n  @override\n  Object get outboxObservationScope => _legacyOwner ?? _core;');
 const start=get().indexOf('  @override\n  Future<T> transaction<T>(',get().indexOf('class ConversationLocalImIngressStore')),end=get().indexOf('\n}\n\nclass _SqliteImIngressTransaction',start);
 set(get().slice(0,start)+`  @override
  Future<T> transaction<T>(Future<T> Function(ImIngressTransaction transaction) action, {
    MessagePersistPriority persistPriority = MessagePersistPriority.realtime,
  }) async {
    List<(ImOutboxRecord, ImOutboxRecoveryRecord?)> committed = [];
    Future<T> run(DatabaseExecutor database) async {
      if (!_outboxSchemaReady) await ensureOutboxStateVersionSchema(database);
      final tx = _SqliteImIngressTransaction(database);
      final result = await action(tx);
      committed = await tx.committedOutboxes();
      return result;
    }
    final result = _legacyOwner != null
        ? await _legacyOwner!.runLegacyImIngressTransaction<T>(run)
        : await _core.runTransaction<T>(run, persistPriority: persistPriority,
            persistSource: persistPriority == MessagePersistPriority.realtime
              ? MessagePersistSource.realtime : persistPriority == MessagePersistPriority.userHistory
                ? MessagePersistSource.userHistory : MessagePersistSource.backgroundRepair);
    _outboxSchemaReady = true;
    // The database future includes COMMIT. No notifications escape rollback.
    for (final (main, copy) in committed) {
      Im05Persistence.publishCommitted(outboxObservationScope, main, copy);
    }
    return result;
  }`+get().slice(end));
 // A forwarding mixin cannot use an interface as its superclass constraint.
 r('mixin ImOutboxCommitTracking on ImIngressTransaction {','mixin ImOutboxCommitTracking implements ImIngressTransaction {');
 r('class _SqliteImIngressTransaction implements ImIngressTransaction {','class _SqliteImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {');
 r('class _MemoryImIngressTransaction implements ImIngressTransaction {','class _MemoryImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {');
 // Track reads/insertions; all update paths read the identity in the same transaction.
 set(get().replace(/(Future<ImOutboxRecord\?> findOutbox\(\{[\s\S]*?\}\) async \{)/g,'$1\n    observedOutboxes.add((ownerUserId, operationId));'));
 set(get().replace(/(Future<bool> insertOutboxIfAbsent\(ImOutboxRecord record\) async \{)/g,'$1\n    observedOutboxes.add((record.ownerUserId, record.operationId));'));
 r('(_) => action(_MemoryImIngressTransaction(this)),',`(_) async {
        final snapshots = <Map<dynamic, dynamic>, Map<dynamic, dynamic>>{
          for (final map in [inbox, counters, leases, journals, checkpoints, effects, outboxes, outboxRecoveryCopies]) map: Map.of(map),
        };
        final tx = _MemoryImIngressTransaction(this);
        try {
          final result = await action(tx);
          final committed = await tx.committedOutboxes();
          for (final (main, copy) in committed) {
            Im05Persistence.publishCommitted(this, main, copy);
          }
          return result;
        } catch (_) {
          for (final entry in snapshots.entries) {
            entry.key..clear()..addAll(entry.value);
          }
          rethrow;
        }
      },`);
 const i=get().indexOf('class _MemoryImIngressTransaction');let a=get().slice(0,i),b=get().slice(i);
 b=b.replace('_store.outboxes[record.operationId] = record;\n    return true;\n  }\n\n  @override\n  Future<ImOutboxRecoveryRecord?>','_store.outboxes[record.operationId] = record.copyWith(stateVersion: current.stateVersion + 1);\n    return true;\n  }\n\n  @override\n  Future<ImOutboxRecoveryRecord?>');
 b=b.replaceAll('_store.outboxRecoveryCopies[record.operationId] = record;','_store.outboxRecoveryCopies[record.operationId] = record;\n    final main = _store.outboxes[record.operationId];\n    if (main != null) {\n      _store.outboxes[record.operationId] = main.copyWith(stateVersion: main.stateVersion + 1);\n      observedOutboxes.add((main.ownerUserId, main.operationId));\n    }');
 set(a+b);
});
edit('lib/src/services/chat_failed_message_retry_service.dart',(r)=>{
 r('if (localId.isEmpty) return true;','if (localId.isEmpty) return false;');
 r('if (type == null) return true;','if (type == null) return false;');
 r('if (scope == null) return true;','if (scope == null) return false;');
 r('    return verdict.decision == ImOutboxResultDecision.missing ||\n        verdict.canRetry;','    // Absence alone does not prove that this is a legacy, never-accepted send.\n    return verdict.canRetry;');
});
edit('lib/src/services/im/outgoing_send_coordinator.dart',(r)=>{
 r("import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';","import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';\nimport 'package:tencent_cloud_chat_sdk/enum/message_status.dart';");
 r('      if (message.isSelf != true) continue;', '      if (message.isSelf != true ||\n          message.status != MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC) continue;');
 r('  bool get isCurrentSession =>',`  /// Capture once at a UI consumption boundary; every derived field then
  /// reads the same committed verdict instead of a changing live view.
  ImCoordinatedSendResult snapshot() => ImCoordinatedSendResult(
    sdkResult: _sdkResult, usedOutbox: usedOutbox, identity: identity,
    accountGeneration: accountGeneration, domainGeneration: domainGeneration,
    dispatchDecision: dispatchDecision, outcomeUnknown: _outcomeUnknown,
    outboxResult: currentOutboxResult, localStatePending: localStatePending);

  bool get isCurrentSession =>`);
});
