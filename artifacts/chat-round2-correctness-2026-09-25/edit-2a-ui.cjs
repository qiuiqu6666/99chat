const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const r=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,100));s=s.replace(a,b);}; fn(r,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
edit('lib/src/services/im/im_ingress_store.dart',(r,get,set)=>{
 set(get().replace(/(Future<bool> updateOutbox(?:Recovery)?IfCurrent\(\{[\s\S]*?\}\) async \{)/g,'$1\n    observedOutboxes.add((record.ownerUserId, record.operationId));'));
});
edit('lib/src/services/im/im_ingress_store_platform_web.dart',(r,get,set)=>{
 r("import 'im05_contracts.dart';","import 'im05_contracts.dart';\nimport 'im05_persistence.dart';");
 r('class WebImIngressStore implements ImIngressStore {','class WebImIngressStore implements ImIngressStore, ImOutboxObservationScope {\n  static final Object _observationScope = Object();\n  @override\n  Object get outboxObservationScope => _observationScope;');
 r('      await completion;\n      return result;','      final snapshots = await transaction.committedOutboxes();\n      await completion;\n      for (final (main, copy) in snapshots) {\n        Im05Persistence.publishCommitted(outboxObservationScope, main, copy);\n      }\n      return result;');
 r('class _WebImIngressTransaction implements ImIngressTransaction {','class _WebImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {');
 r('    final map = _decodeMap(await _get(_outboxKey(ownerUserId, operationId)));\n    return map == null ? null : imOutboxFromStorageMap(map);',"    observedOutboxes.add((ownerUserId, operationId));\n    final map = _decodeMap(await _get(_outboxKey(ownerUserId, operationId)));\n    if (map == null || map['owner_user_id'] != ownerUserId) return null;\n    return imOutboxFromStorageMap(map);");
 r('      jsonEncode(imOutboxToStorageMap(record)),','      jsonEncode(imOutboxToStorageMap(record.copyWith(stateVersion: current.stateVersion + 1))),');
 r('    return map == null ? null : imOutboxRecoveryFromStorageMap(map);',"    return map == null || map['owner_user_id'] != ownerUserId ? null : imOutboxRecoveryFromStorageMap(map);");
 r('    await _put(key, jsonEncode(imOutboxRecoveryToStorageMap(record)));','    await _put(key, jsonEncode(imOutboxRecoveryToStorageMap(record)));\n    await _bumpMainVersion(record);');
 r('      jsonEncode(imOutboxRecoveryToStorageMap(record)),\n    );','      jsonEncode(imOutboxRecoveryToStorageMap(record)),\n    );\n    await _bumpMainVersion(record);');
 r('  Future<bool> _hasCurrentLease(',`  Future<void> _bumpMainVersion(ImOutboxRecoveryRecord copy) async {
    final main = await findOutbox(ownerUserId: copy.ownerUserId, operationId: copy.operationId);
    if (main != null) await _put(_outboxKey(main.ownerUserId, main.operationId),
      jsonEncode(imOutboxToStorageMap(main.copyWith(stateVersion: main.stateVersion + 1))));
  }

  Future<bool> _hasCurrentLease(`);
});
edit('third_party/tencent_cloud_chat_uikit/lib/business_logic/view_models/tui_chat_global_model.dart',(r)=>{
 r("import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';","import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';\nimport 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_sync_service.dart';");
 r('  bool applyOutgoingSendResult(',`  final Map<String, VoidCallback> _outboxResultSubscriptions = {};

  void _observeOutgoingResult(ImCoordinatedSendResult live, String convID,
      String clientId, ConvType convType, GroupReceiptAllowType? groupType) {
    final view = live.resultView;
    final identity = live.identity;
    if (view == null || identity == null || live.currentOutboxResult?.deliveryConfirmed == true) return;
    final key = identity.scope.ownerUserId + '|' + identity.operationId;
    if (_outboxResultSubscriptions.containsKey(key)) return;
    void remove() { _outboxResultSubscriptions.remove(key)?.call(); }
    void changed() {
      final snapshot = live.snapshot();
      if (!snapshot.isCurrentSession) { remove(); return; }
      if (snapshot.outcomeUnknown) return;
      final applied = applyOutgoingSendResult(snapshot.sdkResult, convID,
          clientId, convType, groupType, null, coordinatedResult: snapshot);
      if (snapshot.currentOutboxResult?.deliveryConfirmed == true) {
        remove();
        final message = snapshot.sdkResult.data;
        if (applied && message != null) {
          // Projection only: do not replay messageDidSend or clear input.
          final session = snapshot.accountGeneration == null ? null : SessionIdentity(
            ownerUserId: identity.scope.ownerUserId, generation: snapshot.accountGeneration!);
          unawaited(ConversationSyncService.instance.patchConversationLastMessage(
            conversationID: identity.scope.conversationId, message: message, identity: session)
              .catchError((Object error) { outputLogger.i('outbox preview repair: ' + error.runtimeType.toString()); }));
        }
      }
    }
    view.addListener(changed);
    _outboxResultSubscriptions[key] = () => view.removeListener(changed);
  }

  bool applyOutgoingSendResult(`);
 r('    if (coordinatedResult != null) {\n      final identity = coordinatedResult.identity;','    if (coordinatedResult != null) {\n      _observeOutgoingResult(coordinatedResult, convID, clientId, convType, groupType);\n      coordinatedResult = coordinatedResult.snapshot();\n      final identity = coordinatedResult.identity;');
 r('  clearData() {\n    invalidateBoundedHistorySessions();','  clearData() {\n    for (final cancel in _outboxResultSubscriptions.values) { cancel(); }\n    _outboxResultSubscriptions.clear();\n    invalidateBoundedHistorySessions();');
 r('if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {','if (isEditStatusMessage == false) {');
});
edit('third_party/tencent_cloud_chat_uikit/lib/business_logic/separate_models/tui_chat_separate_view_model.dart',(r)=>{
 r('if (isEditStatusMessage == false && !coordinatedSend.outcomeUnknown) {','if (isEditStatusMessage == false) {');
});
