const fs=require('fs'); const p='lib/src/services/im/read_outbox_store.dart';let s=fs.readFileSync(p,'utf8');
s=s.replace('    this.createdAtMs = 0,','    this.createdAtMs = 0,\n    this.readEventAtMs = 0,').replace('  final int createdAtMs;','  final int createdAtMs;\n  final int readEventAtMs;');
s=s.replace("      if (!names.contains('retry_reason')) {",`      if (!names.contains('read_event_at')) {
        await db.execute('ALTER TABLE $_table ADD COLUMN read_event_at INTEGER NOT NULL DEFAULT 0');
        await db.execute('UPDATE $_table SET read_event_at = last_read_at');
      }
      if (!names.contains('retry_reason')) {`);
const a=s.indexOf('    ConversationReadOutboxRecord buildRecord'), b=s.indexOf('\n  Future<void> enqueueMany',a);
s=s.slice(0,a)+`    ConversationReadOutboxRecord? merge(ConversationReadOutboxRecord? current) {
      if (current != null && current.readEventAtMs > requestedReadAt) return null;
      final timestamp = cleanTimestamp > (current?.cleanTimestamp ?? 0) ? cleanTimestamp : current?.cleanTimestamp ?? 0;
      final sequence = cleanSequence > (current?.cleanSequence ?? 0) ? cleanSequence : current?.cleanSequence ?? 0;
      final messageId = lastReadMessageId.trim().isEmpty ? current?.lastReadMessageId ?? '' : lastReadMessageId.trim();
      if (current != null && current.cleanTimestamp == timestamp && current.cleanSequence == sequence && current.lastReadMessageId == messageId) return null;
      final revision = current != null && current.lastReadAtMs >= requestedReadAt ? current.lastReadAtMs + 1 : requestedReadAt;
      return ConversationReadOutboxRecord(ownerUserId: owner, conversationId: conversation,
        lastReadMessageId: messageId, cleanTimestamp: timestamp, cleanSequence: sequence,
        lastReadAtMs: revision, readEventAtMs: requestedReadAt,
        attemptCount: 0, nextRetryAtMs: 0, createdAtMs: now);
    }
    if (kIsWeb) {
      final key = '$owner|$conversation'; final record = merge(_webRows[key]);
      if (record != null) _webRows[key] = record;
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      final rows = await db.query(_table, where: 'owner_user_id = ? AND conversation_id = ?', whereArgs: [owner, conversation], limit: 1);
      final record = merge(rows.isEmpty ? null : _recordFromRow(rows.single));
      if (record == null) return;
      await db.rawInsert('''INSERT OR REPLACE INTO $_table (
        owner_user_id, conversation_id, last_read_message_id, clean_timestamp, clean_sequence,
        last_read_at, read_event_at, attempt_count, next_retry_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)''', [owner, conversation,
        record.lastReadMessageId, record.cleanTimestamp, record.cleanSequence,
        record.lastReadAtMs, record.readEventAtMs, now, now]);
    });
  }
`+s.slice(b);
// Batch placeholders never erase an existing precise watermark or reset backoff.
s=s.replace('if (current != null && current.lastReadAtMs > readAt) continue;', 'if (current != null) continue;');
s=s.replace('if (currentReadAt > readAt) continue;', 'if (current.isNotEmpty) continue;');
s=s.replace('          createdAtMs: now,\n        );','          createdAtMs: now,\n          readEventAtMs: readAt,\n        );');
s=s.replace('clean_timestamp, clean_sequence, last_read_at, attempt_count,','clean_timestamp, clean_sequence, last_read_at, read_event_at, attempt_count,');
s=s.replace("VALUES (?, ?, '', 0, 0, ?, 0, 0, ?, ?)","VALUES (?, ?, '', 0, 0, ?, ?, 0, 0, ?, ?)");
s=s.replace('[owner, id, effectiveReadAt, createdAt, now]', '[owner, id, effectiveReadAt, readAt, createdAt, now]');
s=s.replace('        createdAtMs: record.createdAtMs,','        createdAtMs: record.createdAtMs,\n        readEventAtMs: record.readEventAtMs,');
s=s.replace('lastReadAtMs: row.lastReadAtMs, attemptCount:', 'lastReadAtMs: row.lastReadAtMs, readEventAtMs: row.readEventAtMs, attemptCount:');
s=s.replace("    createdAtMs: row['created_at'] as int? ?? 0,","    createdAtMs: row['created_at'] as int? ?? 0,\n    readEventAtMs: row['read_event_at'] as int? ?? row['last_read_at'] as int? ?? 0,");
fs.writeFileSync(p,s);
