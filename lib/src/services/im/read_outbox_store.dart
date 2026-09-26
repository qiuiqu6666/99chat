import 'package:flutter/foundation.dart';
import 'conversation_read_policy.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';

class ConversationReadOutboxRecord {
  const ConversationReadOutboxRecord({
    required this.ownerUserId,
    required this.conversationId,
    required this.lastReadMessageId,
    required this.cleanTimestamp,
    required this.cleanSequence,
    required this.lastReadAtMs,
    required this.attemptCount,
    required this.nextRetryAtMs,
    this.retryReason = '',
    this.createdAtMs = 0,
    this.readEventAtMs = 0,
  });

  final String ownerUserId;
  final String conversationId;
  final String lastReadMessageId;
  final int cleanTimestamp;
  final int cleanSequence;
  final int lastReadAtMs;
  final int attemptCount;
  final int nextRetryAtMs;
  final String retryReason;
  final int createdAtMs;
  final int readEventAtMs;
}

/// Durable conversation mark-read queue, scoped by account.
class ConversationReadOutboxStore {
  ConversationReadOutboxStore._();

  static final ConversationReadOutboxStore instance =
      ConversationReadOutboxStore._();
  static const _table = 'conversation_read_outbox';
  final Map<String, ConversationReadOutboxRecord> _webRows =
      <String, ConversationReadOutboxRecord>{};
  Future<void>? _schemaInFlight;
  bool _schemaReady = false;

  Future<void> _ensureSchema() {
    if (kIsWeb || _schemaReady) return Future<void>.value();
    final running = _schemaInFlight;
    if (running != null) return running;
    final task = MessageCoreStore.instance.runTransaction<void>((db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          owner_user_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          last_read_message_id TEXT NOT NULL DEFAULT '',
          clean_timestamp INTEGER NOT NULL DEFAULT 0,
          clean_sequence INTEGER NOT NULL DEFAULT 0,
          last_read_at INTEGER NOT NULL DEFAULT 0,
          attempt_count INTEGER NOT NULL DEFAULT 0,
          next_retry_at INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (owner_user_id, conversation_id)
        )
      ''');
      final columns = await db.rawQuery('PRAGMA table_info($_table)');
      final names = columns.map((row) => row['name']?.toString()).toSet();
      if (!names.contains('read_event_at')) {
        await db.execute(
            'ALTER TABLE $_table ADD COLUMN read_event_at INTEGER NOT NULL DEFAULT 0');
        await db.execute('UPDATE $_table SET read_event_at = last_read_at');
      }
      if (!names.contains('retry_reason')) {
        await db.execute(
            "ALTER TABLE $_table ADD COLUMN retry_reason TEXT NOT NULL DEFAULT ''");
      }
      if (!names.contains('clean_timestamp')) {
        await db.execute(
          'ALTER TABLE $_table ADD COLUMN clean_timestamp INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (!names.contains('clean_sequence')) {
        await db.execute(
          'ALTER TABLE $_table ADD COLUMN clean_sequence INTEGER NOT NULL DEFAULT 0',
        );
      }
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_conversation_read_outbox_due
        ON $_table(owner_user_id, next_retry_at)
      ''');
    });
    _schemaInFlight = task;
    return task.then((_) {
      _schemaReady = true;
    }).whenComplete(() {
      if (identical(_schemaInFlight, task)) _schemaInFlight = null;
    });
  }

  Future<void> enqueue({
    required String ownerUserId,
    required String conversationId,
    String lastReadMessageId = '',
    int cleanTimestamp = 0,
    int cleanSequence = 0,
    int? lastReadAtMs,
    // Only a fresh user read action may restart a paused failure. Passive
    // leave/recovery/snapshot updates must preserve its retry policy.
    bool retryPausedOnUserAction = false,
  }) async {
    final owner = ownerUserId.trim();
    final conversation = conversationId.trim();
    if (owner.isEmpty || conversation.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final requestedReadAt = lastReadAtMs ?? now;
    ConversationReadOutboxRecord? merge(ConversationReadOutboxRecord? current) {
      if (current != null && current.readEventAtMs > requestedReadAt)
        return null;
      final timestamp = cleanTimestamp > (current?.cleanTimestamp ?? 0)
          ? cleanTimestamp
          : current?.cleanTimestamp ?? 0;
      final sequence = cleanSequence > (current?.cleanSequence ?? 0)
          ? cleanSequence
          : current?.cleanSequence ?? 0;
      final messageId = lastReadMessageId.trim().isEmpty
          ? current?.lastReadMessageId ?? ''
          : lastReadMessageId.trim();
      final targetAdvanced = current != null &&
          (timestamp > current.cleanTimestamp ||
              sequence > current.cleanSequence);
      final repairedWatermark = targetAdvanced &&
          current.retryReason == 'blocked:watermark_unavailable' &&
          ConversationReadPolicy.validTarget(conversation, timestamp, sequence);
      final restartPaused = retryPausedOnUserAction &&
          current != null &&
          current.nextRetryAtMs < 0 &&
          requestedReadAt > current.readEventAtMs &&
          ConversationReadPolicy.validTarget(
              conversation, cleanTimestamp, cleanSequence);
      if (!restartPaused &&
          current != null &&
          current.cleanTimestamp == timestamp &&
          current.cleanSequence == sequence &&
          current.lastReadMessageId == messageId) {
        return null;
      }
      final revision =
          current != null && current.lastReadAtMs >= requestedReadAt
              ? current.lastReadAtMs + 1
              : requestedReadAt;
      return ConversationReadOutboxRecord(
          ownerUserId: owner,
          conversationId: conversation,
          lastReadMessageId: messageId,
          cleanTimestamp: timestamp,
          cleanSequence: sequence,
          lastReadAtMs: revision,
          readEventAtMs: requestedReadAt,
          attemptCount: restartPaused ? 0 : current?.attemptCount ?? 0,
          nextRetryAtMs: repairedWatermark || restartPaused
              ? now
              : current?.nextRetryAtMs ?? 0,
          retryReason: repairedWatermark || restartPaused
              ? ''
              : current?.retryReason ?? '',
          createdAtMs: restartPaused ? now : current?.createdAtMs ?? now);
    }

    if (kIsWeb) {
      final key = '$owner|$conversation';
      final record = merge(_webRows[key]);
      if (record != null) _webRows[key] = record;
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      final rows = await db.query(_table,
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: [owner, conversation],
          limit: 1);
      final record = merge(rows.isEmpty ? null : _recordFromRow(rows.single));
      if (record == null) return;
      await db.rawInsert('''INSERT OR REPLACE INTO $_table (
        owner_user_id, conversation_id, last_read_message_id, clean_timestamp, clean_sequence,
        last_read_at, read_event_at, attempt_count, next_retry_at, retry_reason,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
        owner,
        conversation,
        record.lastReadMessageId,
        record.cleanTimestamp,
        record.cleanSequence,
        record.lastReadAtMs,
        record.readEventAtMs,
        record.attemptCount,
        record.nextRetryAtMs,
        record.retryReason,
        record.createdAtMs,
        now
      ]);
    });
  }

  Future<void> enqueueMany({
    required String ownerUserId,
    required Iterable<String> conversationIds,
    int? lastReadAtMs,
  }) async {
    final owner = ownerUserId.trim();
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (owner.isEmpty || ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final readAt = lastReadAtMs ?? now;
    if (kIsWeb) {
      for (final id in ids) {
        final key = '$owner|$id';
        final current = _webRows[key];
        if (current != null) continue;
        _webRows[key] = ConversationReadOutboxRecord(
          ownerUserId: owner,
          conversationId: id,
          lastReadMessageId: '',
          cleanTimestamp: 0,
          cleanSequence: 0,
          lastReadAtMs: current != null && current.lastReadAtMs >= readAt
              ? current.lastReadAtMs + 1
              : readAt,
          attemptCount: 0,
          nextRetryAtMs: 0,
          createdAtMs: now,
          readEventAtMs: readAt,
        );
      }
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      for (final id in ids) {
        final current = await db.query(
          _table,
          columns: <String>['last_read_at', 'created_at'],
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: <Object?>[owner, id],
          limit: 1,
        );
        final currentReadAt = current.isEmpty
            ? -1
            : (current.first['last_read_at'] as int? ?? -1);
        if (current.isNotEmpty) continue;
        final effectiveReadAt =
            currentReadAt >= readAt ? currentReadAt + 1 : readAt;
        final createdAt = current.isEmpty
            ? now
            : (current.first['created_at'] as int? ?? now);
        await db.rawInsert(
          '''
          INSERT OR REPLACE INTO $_table (
            owner_user_id, conversation_id, last_read_message_id,
            clean_timestamp, clean_sequence, last_read_at, read_event_at, attempt_count,
            next_retry_at, created_at, updated_at
          ) VALUES (?, ?, '', 0, 0, ?, ?, 0, 0, ?, ?)
        ''',
          <Object?>[owner, id, effectiveReadAt, readAt, createdAt, now],
        );
      }
    });
  }

  Future<void> acknowledge({
    required String ownerUserId,
    required String conversationId,
    required int lastReadAtMs,
  }) async {
    final owner = ownerUserId.trim();
    final conversation = conversationId.trim();
    if (owner.isEmpty || conversation.isEmpty) return;
    if (kIsWeb) {
      final key = '$owner|$conversation';
      final current = _webRows[key];
      if (current != null && current.lastReadAtMs <= lastReadAtMs) {
        _webRows.remove(key);
      }
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      await db.delete(
        _table,
        where:
            'owner_user_id = ? AND conversation_id = ? AND last_read_at <= ?',
        whereArgs: <Object?>[owner, conversation, lastReadAtMs],
      );
    });
  }

  Future<ConversationReadOutboxRecord?> find({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final owner = ownerUserId.trim();
    final conversation = conversationId.trim();
    if (owner.isEmpty || conversation.isEmpty) return null;
    if (kIsWeb) return _webRows['$owner|$conversation'];
    await _ensureSchema();
    return MessageCoreStore.instance
        .runTransaction<ConversationReadOutboxRecord?>((db) async {
      final rows = await db.query(
        _table,
        where: 'owner_user_id = ? AND conversation_id = ?',
        whereArgs: <Object?>[owner, conversation],
        limit: 1,
      );
      return rows.isEmpty ? null : _recordFromRow(rows.first);
    });
  }

  Future<void> acknowledgeMany({
    required String ownerUserId,
    required Iterable<String> conversationIds,
    required int lastReadAtMs,
  }) async {
    final owner = ownerUserId.trim();
    final ids = conversationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (owner.isEmpty || ids.isEmpty) return;
    if (kIsWeb) {
      for (final id in ids) {
        final key = '$owner|$id';
        final current = _webRows[key];
        if (current != null && current.lastReadAtMs <= lastReadAtMs) {
          _webRows.remove(key);
        }
      }
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      for (final id in ids) {
        await db.delete(
          _table,
          where:
              'owner_user_id = ? AND conversation_id = ? AND last_read_at <= ?',
          whereArgs: <Object?>[owner, id, lastReadAtMs],
        );
      }
    });
  }

  Future<List<ConversationReadOutboxRecord>> listDue({
    required String ownerUserId,
    int limit = 500,
    String? afterConversationId,
  }) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty || limit <= 0)
      return const <ConversationReadOutboxRecord>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      final rows = _webRows.values
          .where((row) =>
              row.ownerUserId == owner &&
              row.nextRetryAtMs >= 0 &&
              row.nextRetryAtMs <= now &&
              (afterConversationId == null ||
                  row.conversationId.compareTo(afterConversationId) > 0))
          .toList(growable: false);
      if (afterConversationId != null) {
        rows.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      }
      return rows.take(limit).toList(growable: false);
    }
    await _ensureSchema();
    return MessageCoreStore.instance
        .runTransaction<List<ConversationReadOutboxRecord>>((db) async {
      final rows = await db.query(
        _table,
        where: 'owner_user_id = ? AND next_retry_at >= 0 AND next_retry_at <= ?'
            '${afterConversationId == null ? '' : ' AND conversation_id > ?'}',
        whereArgs: <Object?>[
          owner,
          now,
          if (afterConversationId != null) afterConversationId
        ],
        orderBy: afterConversationId == null
            ? 'next_retry_at ASC, updated_at ASC'
            : 'conversation_id ASC',
        limit: limit,
      );
      return rows.map(_recordFromRow).toList(growable: false);
    });
  }

  Future<int?> earliestNextRetryAt({required String ownerUserId}) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return null;
    if (kIsWeb) {
      int? earliest;
      for (final row in _webRows.values) {
        if (row.ownerUserId != owner || row.nextRetryAtMs < 0) continue;
        if (earliest == null || row.nextRetryAtMs < earliest) {
          earliest = row.nextRetryAtMs;
        }
      }
      return earliest;
    }
    await _ensureSchema();
    return MessageCoreStore.instance.runTransaction<int?>((db) async {
      final rows = await db.rawQuery(
        'SELECT MIN(next_retry_at) AS earliest FROM $_table '
        'WHERE owner_user_id = ? AND next_retry_at >= 0',
        <Object?>[owner],
      );
      return rows.isEmpty ? null : rows.first['earliest'] as int?;
    });
  }

  Future<void> markRetry(ConversationReadOutboxRecord record,
      {int? sdkCode, String? reason, int? notBeforeAtMs}) async {
    final attempt = record.attemptCount + 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    var cause = reason ?? ConversationReadPolicy.failureReason(sdkCode ?? -1);
    if (cause.startsWith('transient:') &&
        record.createdAtMs > 0 &&
        now - record.createdAtMs >=
            const Duration(minutes: 15).inMilliseconds) {
      cause = 'reconnect:retry_window_elapsed';
    }
    final backoffAt = now + _backoffMs(attempt);
    final next = cause.startsWith('transient:')
        ? (notBeforeAtMs != null && notBeforeAtMs > backoffAt
            ? notBeforeAtMs
            : backoffAt)
        : -1;
    if (kIsWeb) {
      final key = '${record.ownerUserId}|${record.conversationId}';
      final current = _webRows[key];
      if (current == null || current.lastReadAtMs != record.lastReadAtMs) {
        return;
      }
      _webRows[key] = ConversationReadOutboxRecord(
        ownerUserId: record.ownerUserId,
        conversationId: record.conversationId,
        lastReadMessageId: record.lastReadMessageId,
        cleanTimestamp: record.cleanTimestamp,
        cleanSequence: record.cleanSequence,
        lastReadAtMs: record.lastReadAtMs,
        attemptCount: attempt,
        nextRetryAtMs: next,
        retryReason: cause,
        createdAtMs: record.createdAtMs,
        readEventAtMs: record.readEventAtMs,
      );
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      await db.update(
        _table,
        <String, Object?>{
          'attempt_count': attempt,
          'next_retry_at': next,
          'retry_reason': cause,
          'updated_at': now,
        },
        where: 'owner_user_id = ? AND conversation_id = ? AND last_read_at = ?',
        whereArgs: <Object?>[
          record.ownerUserId,
          record.conversationId,
          record.lastReadAtMs,
        ],
      );
    });
  }

  /// Persists a verified in-memory cooldown without spending another SDK
  /// attempt. The target revision is checked so an older scan cannot delay W3.
  Future<void> deferUntilIfCurrent(
    ConversationReadOutboxRecord record,
    int notBeforeAtMs,
  ) async {
    if (notBeforeAtMs <= DateTime.now().millisecondsSinceEpoch) return;
    if (kIsWeb) {
      final key = '${record.ownerUserId}|${record.conversationId}';
      final current = _webRows[key];
      if (current == null ||
          current.lastReadAtMs != record.lastReadAtMs ||
          current.nextRetryAtMs < 0 ||
          current.nextRetryAtMs >= notBeforeAtMs) return;
      _webRows[key] = ConversationReadOutboxRecord(
        ownerUserId: current.ownerUserId,
        conversationId: current.conversationId,
        lastReadMessageId: current.lastReadMessageId,
        cleanTimestamp: current.cleanTimestamp,
        cleanSequence: current.cleanSequence,
        lastReadAtMs: current.lastReadAtMs,
        attemptCount: current.attemptCount,
        nextRetryAtMs: notBeforeAtMs,
        retryReason: 'transient:frequency_cooldown',
        createdAtMs: current.createdAtMs,
        readEventAtMs: current.readEventAtMs,
      );
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      await db.update(
        _table,
        <String, Object?>{
          'next_retry_at': notBeforeAtMs,
          'retry_reason': 'transient:frequency_cooldown',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'owner_user_id = ? AND conversation_id = ? AND last_read_at = ? '
            'AND next_retry_at >= 0 AND next_retry_at < ?',
        whereArgs: <Object?>[
          record.ownerUserId,
          record.conversationId,
          record.lastReadAtMs,
          notBeforeAtMs,
        ],
      );
    });
  }

  Future<void> resumeAfterReconnect(String ownerUserId) async {
    if (kIsWeb) {
      for (final entry in _webRows.entries.toList()) {
        final row = entry.value;
        if (row.ownerUserId != ownerUserId ||
            !row.retryReason.startsWith('reconnect:')) continue;
        _webRows[entry.key] = ConversationReadOutboxRecord(
            ownerUserId: row.ownerUserId,
            conversationId: row.conversationId,
            lastReadMessageId: row.lastReadMessageId,
            cleanTimestamp: row.cleanTimestamp,
            cleanSequence: row.cleanSequence,
            lastReadAtMs: row.lastReadAtMs,
            readEventAtMs: row.readEventAtMs,
            attemptCount: row.attemptCount,
            nextRetryAtMs: 0,
            createdAtMs: row.createdAtMs);
      }
      return;
    }
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction((db) => db.update(
        _table,
        {
          'next_retry_at': 0,
          'retry_reason': '',
        },
        where: "owner_user_id = ? AND retry_reason LIKE 'reconnect:%'",
        whereArgs: [ownerUserId]));
  }

  Future<void> clearOwner(String ownerUserId) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return;
    _webRows.removeWhere((key, _) => key.startsWith('$owner|'));
    if (kIsWeb) return;
    await _ensureSchema();
    await MessageCoreStore.instance.runTransaction<void>((db) async {
      await db.delete(
        _table,
        where: 'owner_user_id = ?',
        whereArgs: <Object?>[owner],
      );
    });
  }
}

ConversationReadOutboxRecord _recordFromRow(Map<String, Object?> row) {
  return ConversationReadOutboxRecord(
    ownerUserId: row['owner_user_id']?.toString() ?? '',
    conversationId: row['conversation_id']?.toString() ?? '',
    lastReadMessageId: row['last_read_message_id']?.toString() ?? '',
    cleanTimestamp: row['clean_timestamp'] as int? ?? 0,
    cleanSequence: row['clean_sequence'] as int? ?? 0,
    lastReadAtMs: row['last_read_at'] as int? ?? 0,
    attemptCount: row['attempt_count'] as int? ?? 0,
    nextRetryAtMs: row['next_retry_at'] as int? ?? 0,
    retryReason: row['retry_reason'] as String? ?? '',
    createdAtMs: row['created_at'] as int? ?? 0,
    readEventAtMs:
        row['read_event_at'] as int? ?? row['last_read_at'] as int? ?? 0,
  );
}

int _backoffMs(int attempt) {
  final exponent = attempt > 6 ? 6 : attempt;
  return (1 << exponent) * 1000;
}
