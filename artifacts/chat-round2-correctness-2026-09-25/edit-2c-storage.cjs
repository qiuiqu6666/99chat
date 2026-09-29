const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const r=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,100));s=s.replace(a,b);}; fn(r,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
edit('lib/src/services/im/im_ingress_store.dart',(r)=>{
 r("import 'outbox_state_version_schema.dart';","import 'outbox_state_version_schema.dart';\nimport 'outbox_draft_submission.dart';");
 r('class _SqliteImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {','class _SqliteImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction, ImDraftTransaction {');
 r('  final DatabaseExecutor _db;',`  final DatabaseExecutor _db;

  @override
  Future<Map<String, Object?>?> findDraftHead(String owner, String conversation) async {
    final rows = await _db.query('message_draft_head', where: 'owner_user_id = ? AND conversation_id = ?', whereArgs: [owner, conversation]);
    return rows.isEmpty ? null : rows.single;
  }
  @override
  Future<void> saveDraftHead(ImDraftAcceptance draft) async {
    final existing = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (existing?['draft_id'] == draft.draftId && existing?['accepted_operation_id'] != null) return;
    await _db.insert('message_draft_head', {'owner_user_id': draft.ownerUserId,
      'conversation_id': draft.conversationId, 'draft_id': draft.draftId,
      'protected_text': draft.protectedText}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  @override
  Future<void> acceptDraft(ImDraftAcceptance draft, String operationId) async {
    final old = await _db.query('message_draft_acceptance',
      where: 'owner_user_id = ? AND conversation_id = ? AND draft_id = ?',
      whereArgs: [draft.ownerUserId, draft.conversationId, draft.draftId]);
    if (old.isNotEmpty && old.single['operation_id'] != operationId) throw StateError('draft already accepted by another operation');
    await _db.insert('message_draft_acceptance', {'owner_user_id': draft.ownerUserId,
      'conversation_id': draft.conversationId, 'draft_id': draft.draftId,
      'operation_id': operationId}, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (await findDraftHead(draft.ownerUserId, draft.conversationId) == null) await saveDraftHead(draft);
    await _db.update('message_draft_head', {'accepted_operation_id': operationId},
      where: 'owner_user_id = ? AND conversation_id = ? AND draft_id = ?',
      whereArgs: [draft.ownerUserId, draft.conversationId, draft.draftId]);
  }
`);
 r('  final Map<String, ImInboxRecord> inbox', '  final Map<String, Map<String, Object?>> draftHeads = {};\n  final Map<String, String> draftAcceptances = {};\n  final Map<String, ImInboxRecord> inbox');
 r('        capture(checkpoints); capture(effects); capture(outboxes); capture(outboxRecoveryCopies);', '        capture(checkpoints); capture(effects); capture(outboxes); capture(outboxRecoveryCopies);\n        capture(draftHeads); capture(draftAcceptances);');
 r('class _MemoryImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {','class _MemoryImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction, ImDraftTransaction {');
 r('  final InMemoryImIngressStore _store;',`  final InMemoryImIngressStore _store;
  @override
  Future<Map<String, Object?>?> findDraftHead(String owner, String conversation) async => _store.draftHeads[owner + '|' + conversation];
  @override
  Future<void> saveDraftHead(ImDraftAcceptance draft) async {
    final existing = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (existing?['draft_id'] == draft.draftId && existing?['accepted_operation_id'] != null) return;
    _store.draftHeads[draft.ownerUserId + '|' + draft.conversationId] = {
      'draft_id': draft.draftId, 'protected_text': draft.protectedText};
  }
  @override
  Future<void> acceptDraft(ImDraftAcceptance draft, String operationId) async {
    final key = draft.ownerUserId + '|' + draft.conversationId + '|' + draft.draftId;
    final old = _store.draftAcceptances[key];
    if (old != null && old != operationId) throw StateError('draft already accepted by another operation');
    _store.draftAcceptances[key] = operationId;
    var head = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (head == null) { await saveDraftHead(draft); head = await findDraftHead(draft.ownerUserId, draft.conversationId); }
    if (head!['draft_id'] == draft.draftId) _store.draftHeads[draft.ownerUserId + '|' + draft.conversationId] = {...head, 'accepted_operation_id': operationId};
  }
`);
});
edit('lib/src/services/im/im_ingress_store_platform_web.dart',(r)=>{
 r("import 'im05_persistence.dart';","import 'im05_persistence.dart';\nimport 'outbox_draft_submission.dart';");
 r('class _WebImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction {','class _WebImIngressTransaction with ImOutboxCommitTracking implements ImIngressTransaction, ImDraftTransaction {');
 r('  final IDBObjectStore _store;',`  final IDBObjectStore _store;
  @override
  Future<Map<String, Object?>?> findDraftHead(String owner, String conversation) async => _decodeMap(await _get('draft|' + owner + '|' + conversation));
  @override
  Future<void> saveDraftHead(ImDraftAcceptance draft) async {
    final old = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (old?['draft_id'] == draft.draftId && old?['accepted_operation_id'] != null) return;
    await _put('draft|' + draft.ownerUserId + '|' + draft.conversationId,
      jsonEncode({'draft_id': draft.draftId, 'protected_text': draft.protectedText}));
  }
  @override
  Future<void> acceptDraft(ImDraftAcceptance draft, String operationId) async {
    final key = 'draft-accepted|' + draft.ownerUserId + '|' + draft.conversationId + '|' + draft.draftId;
    final old = await _get(key);
    if (old != null && old != operationId) throw StateError('draft already accepted by another operation');
    await _put(key, operationId);
    var head = await findDraftHead(draft.ownerUserId, draft.conversationId);
    if (head == null) { await saveDraftHead(draft); head = await findDraftHead(draft.ownerUserId, draft.conversationId); }
    if (head!['draft_id'] == draft.draftId) await _put('draft|' + draft.ownerUserId + '|' + draft.conversationId,
      jsonEncode({...head, 'accepted_operation_id': operationId}));
  }
`);
});
edit('lib/src/services/im/im05_persistence.dart',(r,get,set)=>{
 r("import 'package:flutter/foundation.dart';","import 'package:flutter/foundation.dart';\nimport 'outbox_draft_submission.dart';");
 const start=get().indexOf('  Future<ImOutboxDispatchAssessment> prepareOutbox('),end=get().indexOf('  Future<ImOutboxDispatchAssessment>',start+8);
 let part=get().slice(start,end);
 part=part.replace('    required int nowMs,','    required int nowMs,\n    ImDraftAcceptance? draftAcceptance,');
 part=part.replace('      return _assess(',`      if (draftAcceptance != null) {
        if (draftAcceptance.ownerUserId != main.ownerUserId ||
            main.conversationId != main.ownerUserId + '|' + draftAcceptance.conversationId ||
            transaction is! ImDraftTransaction) throw StateError('draft acceptance scope mismatch');
        await (transaction as ImDraftTransaction).acceptDraft(draftAcceptance, main.operationId);
      }
      return _assess(`);
 set(get().slice(0,start)+part+get().slice(end));
});
