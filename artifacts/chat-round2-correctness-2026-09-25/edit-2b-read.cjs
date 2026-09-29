const fs=require('fs');
function edit(path, fn) { const original=fs.readFileSync(path,'utf8'); const nl=original.includes('\r\n')?'\r\n':'\n'; let s=original.replace(/\r\n/g,'\n'); const r=(a,b)=>{if(!s.includes(a))throw Error(path+' missing '+a.slice(0,100));s=s.replace(a,b);}; fn(r,()=>s,v=>s=v); fs.writeFileSync(path,s.replace(/\n/g,nl)); }
edit('lib/src/services/im/read_outbox_store.dart',(r,get,set)=>{
 r("import 'package:flutter/foundation.dart';","import 'package:flutter/foundation.dart';\nimport 'conversation_read_policy.dart';");
 r('    required this.nextRetryAtMs,','    required this.nextRetryAtMs,\n    this.retryReason = \'\',\n    this.createdAtMs = 0,');
 r('  final int nextRetryAtMs;','  final int nextRetryAtMs;\n  final String retryReason;\n  final int createdAtMs;');
 r("      if (!names.contains('clean_timestamp')) {", "      if (!names.contains('retry_reason')) {\n        await db.execute(\"ALTER TABLE $_table ADD COLUMN retry_reason TEXT NOT NULL DEFAULT ''\");\n      }\n      if (!names.contains('clean_timestamp')) {");
 r('          nextRetryAtMs: 0,\n        );','          nextRetryAtMs: 0,\n          createdAtMs: now,\n        );');
 r('final effectiveReadAt = lastReadAtMs == null &&\n              current != null &&','final effectiveReadAt = current != null &&');
 r('          lastReadAtMs == null && currentReadAt >= requestedReadAt','          currentReadAt >= requestedReadAt');
 r('          lastReadAtMs: readAt,','          lastReadAtMs: current != null && current.lastReadAtMs >= readAt ? current.lastReadAtMs + 1 : readAt,\n          createdAtMs: now,');
 r('        final createdAt = current.isEmpty', '        final effectiveReadAt = currentReadAt >= readAt ? currentReadAt + 1 : readAt;\n        final createdAt = current.isEmpty');
 r('<Object?>[owner, id, readAt, createdAt, now]', '<Object?>[owner, id, effectiveReadAt, createdAt, now]');
 r('row.ownerUserId == owner && row.nextRetryAtMs <= now','row.ownerUserId == owner && row.nextRetryAtMs >= 0 && row.nextRetryAtMs <= now');
 r("where: 'owner_user_id = ? AND next_retry_at <= ?',","where: 'owner_user_id = ? AND next_retry_at >= 0 AND next_retry_at <= ?',");
 r('if (row.ownerUserId != owner) continue;','if (row.ownerUserId != owner || row.nextRetryAtMs < 0) continue;');
 r("'WHERE owner_user_id = ?',\n        <Object?>[owner],", "'WHERE owner_user_id = ? AND next_retry_at >= 0',\n        <Object?>[owner],");
 r('  Future<void> markRetry(ConversationReadOutboxRecord record) async {','  Future<void> markRetry(ConversationReadOutboxRecord record, {int? sdkCode, String? reason}) async {');
 r('    final next = now + _backoffMs(attempt);',`    var cause = reason ?? ConversationReadPolicy.failureReason(sdkCode ?? -1);
    if (cause.startsWith('transient:') && record.createdAtMs > 0 &&
        now - record.createdAtMs >= const Duration(minutes: 15).inMilliseconds) {
      cause = 'reconnect:retry_window_elapsed';
    }
    final next = cause.startsWith('transient:') ? now + _backoffMs(attempt) : -1;`);
 r('        nextRetryAtMs: next,','        nextRetryAtMs: next,\n        retryReason: cause,\n        createdAtMs: record.createdAtMs,');
 r("          'next_retry_at': next,","          'next_retry_at': next,\n          'retry_reason': cause,");
 r('  Future<void> clearOwner(String ownerUserId) async {',`  Future<void> resumeAfterReconnect(String ownerUserId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      for (final entry in _webRows.entries.toList()) {
        final row = entry.value;
        if (row.ownerUserId != ownerUserId || !row.retryReason.startsWith('reconnect:')) continue;
        _webRows[entry.key] = ConversationReadOutboxRecord(ownerUserId: row.ownerUserId,
          conversationId: row.conversationId, lastReadMessageId: row.lastReadMessageId,
          cleanTimestamp: row.cleanTimestamp, cleanSequence: row.cleanSequence,
          lastReadAtMs: row.lastReadAtMs, attemptCount: 0, nextRetryAtMs: 0, createdAtMs: now);
      }
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction((db) => db.update(_table,
      {'next_retry_at': 0, 'attempt_count': 0, 'retry_reason': '', 'created_at': now},
      where: "owner_user_id = ? AND retry_reason LIKE 'reconnect:%'", whereArgs: [ownerUserId]));
  }

  Future<void> clearOwner(String ownerUserId) async {`);
 r("    nextRetryAtMs: row['next_retry_at'] as int? ?? 0,","    nextRetryAtMs: row['next_retry_at'] as int? ?? 0,\n    retryReason: row['retry_reason'] as String? ?? '',\n    createdAtMs: row['created_at'] as int? ?? 0,");
});
edit('lib/src/services/im/tencent_conversation_read_service.dart',(r)=>{
 r("import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';","import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';\nimport 'conversation_read_policy.dart';");
 r('    if (!allowFullTypeClean && cleanTimestamp <= 0 && cleanSequence <= 0) {', '    if (!ConversationReadPolicy.validTarget(id, cleanTimestamp, cleanSequence, explicitTypeClear: allowFullTypeClean)) {');
});
edit('lib/src/services/conversation_unread_clear_service.dart',(r,get,set)=>{
 r("import 'dart:async';","import 'dart:async';\nimport 'package:tencent_cloud_chat_demo/src/services/im/conversation_read_policy.dart';");
 r('rawTimestamp > 9999999999 ? rawTimestamp ~/ 1000 : rawTimestamp,','ConversationReadPolicy.conservativeTimestamp(rawTimestamp),');
 r('      if (row == null || (row.cleanTimestamp <= 0 && row.cleanSequence <= 0)) {', '      if (row != null && row.nextRetryAtMs < 0) return;\n      if (row != null && row.lastReadMessageId.isNotEmpty &&\n          row.cleanTimestamp <= 0 && row.cleanSequence <= 0) {');
 r('      if (useFullConversationFallback && !allowFullConversationFallback) {','      if (useFullConversationFallback) {');
 r('await ConversationReadOutboxStore.instance.markRetry(row);','await ConversationReadOutboxStore.instance.markRetry(row, reason: \'blocked:watermark_unavailable\');');
 r('await ConversationReadOutboxStore.instance.markRetry(row);','await ConversationReadOutboxStore.instance.markRetry(row, sdkCode: lastCode);');
 r('  static Future<void> recoverPendingReadOutbox() {','  static Future<void> recoverPendingReadOutbox({bool afterReconnect = false}) {');
 r('    task = _recoverPendingReadOutbox().whenComplete(() {',`    task = (() async {
      if (afterReconnect) await ConversationReadOutboxStore.instance.resumeAfterReconnect(
          SessionIdentityService.instance.capture().ownerUserId);
      await _recoverPendingReadOutbox();
    })().whenComplete(() {`);
});
edit('lib/src/services/im_connect_status_service.dart',(r)=>{
 r('ConversationUnreadClearService.recoverPendingReadOutbox().catchError(', 'ConversationUnreadClearService.recoverPendingReadOutbox(afterReconnect: true).catchError(');
});
