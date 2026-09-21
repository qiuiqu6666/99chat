import 'receipt_recovery_compat.dart';
import 'dart:async';

import 'im_inbox_recovery_query.dart';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_demo/src/services/startup_perf_log.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';

/// SQLite owner for the realtime message core.
///
/// This database intentionally contains only ingress, lease, journal,
/// projection and outbox state.  Conversation indexes and contact snapshots
/// remain in their existing databases, so a large sync write cannot hold the
/// realtime writer transaction open.
class MessageCoreStore {
  MessageCoreStore._();

  static final MessageCoreStore instance = MessageCoreStore._();

  static const String dbName = 'message_core.db';
  static const int _dbVersion = 1;

  static const List<String> _coreTables = <String>[
    'message_event_inbox',
    'message_writer_lease',
    'message_ingress_counter',
    'message_commit_journal',
    'message_projection_checkpoint',
    'message_commit_effect',
    'message_outbox',
    'message_outbox_recovery_copy',
    // These two durable P0 queues are created lazily by their stores, but are
    // part of the message-core failure domain as well.
    'read_receipt_outbox',
    'conversation_read_outbox',
  ];

  Database? _db;
  Future<Database>? _openInFlight;
  bool _factoryReady = false;

  Future<void> _ensureFactory() async {
    if (_factoryReady) return;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryReady = true;
  }

  Future<Database> _openDb() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) return existing;
    final pending = _openInFlight;
    if (pending != null) return pending;
    final task = _openDbOnce();
    _openInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_openInFlight, task)) _openInFlight = null;
    }
  }

  Future<Database> _openDbOnce() async {
    final stopwatch = Stopwatch()..start();
    var created = false;
    await _ensureFactory();
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (database) async {
        // PRAGMA assignments return a result row on Android SQLite. sqflite
        // therefore requires rawQuery rather than execute; execute closes the
        // database with "Queries can be performed ... only".
        await database.rawQuery('PRAGMA journal_mode=WAL');
        // FFB-2 扩散：iOS sqflite_darwin 启动期 PRAGMA 救火。
        // 失败不阻断 DB open（WAL 已经生效，busy_timeout 失败仅降低并发排队上限）。
        await SqfliteBootstrapHelper.withTag('msg_core')
            .runOnOpenPragmasRawQuery(database);
      },
      onCreate: (database, _) async {
        await _createSchema(database);
        created = true;
      },
      onOpen: (database) async {
        await _ensureInboxRecoveryColumns(database);
        // Keep upgrades/recovered databases safe even when onCreate did not
        // run (for example, a partially restored file).
        if (!created) {
          final rows = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'index')",
          );
          final names = rows.map((row) => row['name']).toSet();
          if (!_schemaObjects.every(names.contains)) {
            await _createSchema(database);
          }
        }
      },
    );
    StartupPerfLog.markTagged('message_core_db_open',
        category: 'cold_start',
        details: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'created': created
        });
    try {
      await _migrateLegacyTablesIfNeeded(db, basePath);
    } catch (_) {
      // The new database remains usable.  The old database is never deleted or
      // modified, and the migration marker is intentionally not written so a
      // later open can retry it.
    }
    try {
      await migratePendingReceiptBatches(db);
    } catch (_) {
      // A failed atomic conversion remains pending for retry. Do not leak an
      // opened handle outside _db or let recovery observe a partial upgrade.
      await SqfliteLifecycleGuard.closeDatabase(db);
      rethrow;
    }
    if (!SqfliteLifecycleGuard.instance.canOpenDatabase) {
      await SqfliteLifecycleGuard.closeDatabase(db);
      _db = null;
      throw const SqfliteClosedForBackground();
    }
    _db = db;
    StartupPerfLog.markTagged('message_core_db_ready',
        category: 'cold_start',
        details: {'durationMs': stopwatch.elapsedMilliseconds});
    return db;
  }

  static const _schemaObjects = <String>{
    'message_event_inbox',
    'idx_message_event_scope',
    'idx_message_event_recovery_operation',
    'idx_message_event_account_sequence',
    'idx_message_event_scope_sequence',
    ImInboxRecoveryQuery.indexName,
    'message_writer_lease',
    'message_ingress_counter',
    'message_commit_journal',
    'message_projection_checkpoint',
    'message_commit_effect',
    'message_outbox',
    'idx_message_outbox_ready',
    'message_outbox_recovery_copy',
    'read_receipt_outbox',
    'idx_read_receipt_outbox_due',
    'conversation_read_outbox',
    'idx_conversation_read_outbox_due',
    'message_core_meta',
  };

  Future<void> _createSchema(DatabaseExecutor db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_event_inbox (
        owner_user_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        event_namespace TEXT NOT NULL,
        conversation_id TEXT NOT NULL DEFAULT '',
        event_kind TEXT NOT NULL,
        operation_id TEXT NOT NULL DEFAULT '',
        account_generation INTEGER NOT NULL,
        domain_generation INTEGER NOT NULL,
        source TEXT NOT NULL,
        authority TEXT NOT NULL,
        view_instance_id TEXT NOT NULL DEFAULT '',
        surface_id TEXT NOT NULL DEFAULT '',
        view_session_generation INTEGER,
        history_request_generation INTEGER,
        send_operation_generation INTEGER,
        clear_epoch INTEGER NOT NULL,
        account_ingress_sequence INTEGER NOT NULL,
        scope_ingress_sequence INTEGER NOT NULL,
        provider_sequence INTEGER,
        source_revision INTEGER,
        membership_revision INTEGER,
        payload_hash TEXT NOT NULL,
        recovery_mode TEXT NOT NULL,
        recovery_ref TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        observed_at INTEGER NOT NULL,
        committed_at INTEGER,
        processing_started_at INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        last_error_class TEXT NOT NULL DEFAULT '',
        recovery_priority INTEGER NOT NULL DEFAULT 2,
        PRIMARY KEY(owner_user_id, event_namespace, event_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_event_scope
      ON message_event_inbox(owner_user_id, conversation_id, status)
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_event_recovery_operation
      ON message_event_inbox(owner_user_id, event_namespace, operation_id)
    ''');
    batch.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_message_event_account_sequence
      ON message_event_inbox(owner_user_id, account_ingress_sequence)
    ''');
    batch.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_message_event_scope_sequence
      ON message_event_inbox(owner_user_id, conversation_id, scope_ingress_sequence)
      WHERE conversation_id <> ''
    ''');
    // Completed/abandoned identities stay durable. Recovery only walks due
    // rows through (status, next_retry_at) matching this partial index.
    batch.execute('''
      CREATE INDEX IF NOT EXISTS ${ImInboxRecoveryQuery.indexName}
      ON message_event_inbox(owner_user_id, account_generation,
                            recovery_priority, next_retry_at)
      WHERE ${ImInboxRecoveryQuery.pendingPredicate}
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_writer_lease (
        owner_user_id TEXT PRIMARY KEY,
        lease_owner_id TEXT NOT NULL,
        fencing_token INTEGER NOT NULL,
        acquired_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        heartbeat_at INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_ingress_counter (
        owner_user_id TEXT NOT NULL,
        scope_key TEXT NOT NULL,
        next_sequence INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, scope_key)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_commit_journal (
        owner_user_id TEXT NOT NULL,
        journal_id TEXT NOT NULL,
        event_namespace TEXT NOT NULL,
        event_id TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT '',
        commit_revision INTEGER NOT NULL,
        state TEXT NOT NULL,
        metadata_revision INTEGER,
        projection_revision INTEGER,
        side_effect_revision INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, journal_id),
        UNIQUE(owner_user_id, event_namespace, event_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_projection_checkpoint (
        owner_user_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        commit_revision INTEGER NOT NULL,
        last_journal_id TEXT NOT NULL,
        coverage_revision INTEGER NOT NULL,
        watermark_revision INTEGER NOT NULL,
        barrier_revision INTEGER NOT NULL,
        projection_version INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, scope)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_commit_effect (
        owner_user_id TEXT NOT NULL,
        effect_id TEXT NOT NULL,
        journal_id TEXT NOT NULL,
        effect_kind TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, effect_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_outbox (
        operation_id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        client_correlation_id TEXT NOT NULL,
        message_type INTEGER NOT NULL,
        payload_reference TEXT NOT NULL,
        media_local_ref TEXT,
        encryption_version INTEGER,
        key_id TEXT,
        cipher_algorithm TEXT,
        nonce TEXT,
        content_checksum TEXT,
        payload_hash TEXT NOT NULL DEFAULT '',
        state TEXT NOT NULL,
        sdk_message_id TEXT,
        server_msg_id TEXT,
        dispatch_attempt_id TEXT,
        dispatch_intent_at INTEGER,
        result_code TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        lease_owner_id TEXT NOT NULL DEFAULT '',
        fencing_token INTEGER NOT NULL DEFAULT 0,
        recovery_lag INTEGER NOT NULL DEFAULT 0,
        recovery_conflict INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_message_outbox_ready
      ON message_outbox(owner_user_id, state, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_outbox_recovery_copy (
        owner_user_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        client_correlation_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        message_type INTEGER NOT NULL,
        recovery_revision INTEGER NOT NULL,
        state TEXT NOT NULL,
        dispatch_attempt_id TEXT,
        dispatch_intent_at INTEGER,
        payload_reference_or_ciphertext TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        checksum TEXT NOT NULL,
        sdk_local_id TEXT,
        server_msg_id TEXT,
        result_code TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, operation_id)
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS read_receipt_outbox (
        owner_user_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, message_id)
      )
    ''');
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_read_receipt_outbox_due
      ON read_receipt_outbox(owner_user_id, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS conversation_read_outbox (
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
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_conversation_read_outbox_due
      ON conversation_read_outbox(owner_user_id, next_retry_at)
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS message_core_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await batch.commit(noResult: true);
  }

  Future<void> _ensureInboxRecoveryColumns(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(message_event_inbox)');
    if (info.isEmpty) return;
    final names = info.map((row) => row['name']?.toString() ?? '').toSet();
    Future<void> add(String column, String spec) async {
      if (names.contains(column)) return;
      await db.execute(
        'ALTER TABLE message_event_inbox ADD COLUMN $column $spec',
      );
    }

    await add('retry_count', 'INTEGER NOT NULL DEFAULT 0');
    await add('next_retry_at', 'INTEGER NOT NULL DEFAULT 0');
    await add('last_error_class', "TEXT NOT NULL DEFAULT ''");
    await add('recovery_priority', 'INTEGER NOT NULL DEFAULT 2');
    await db.execute(
      'DROP INDEX IF EXISTS ${ImInboxRecoveryQuery.legacyIndexName}',
    );
  }

  Future<void> _migrateLegacyTablesIfNeeded(
    Database target,
    String basePath,
  ) async {
    final marker = await target.query(
      'message_core_meta',
      where: 'key = ?',
      whereArgs: const <Object?>['legacy_migration_v1'],
      limit: 1,
    );
    if (marker.isNotEmpty) return;
    final legacyPath = p.join(basePath, 'conversation_local_v1.db');
    if (!await databaseFactory.databaseExists(legacyPath)) {
      await _markLegacyMigrationComplete(target);
      return;
    }

    // ConversationLocalStore may still have the legacy file open while the
    // first realtime transaction starts. Use a separate read-only handle so
    // migration never steals or closes that owner connection.
    final legacy = await openDatabase(
      legacyPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final tables = await legacy.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final available =
          tables.map((row) => row['name']?.toString() ?? '').toSet();
      for (final table in _coreTables) {
        if (!available.contains(table)) {
          continue;
        }
        await _copyTable(legacy, target, table);
      }
      await _markLegacyMigrationComplete(target);
    } finally {
      await SqfliteLifecycleGuard.closeDatabase(legacy);
    }
  }

  Future<void> _markLegacyMigrationComplete(Database target) => target
      .insert(
        'message_core_meta',
        const {'key': 'legacy_migration_v1', 'value': 'complete'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      )
      .then((_) {});

  Future<void> _copyTable(
    Database source,
    Database target,
    String table,
  ) async {
    final sourceInfo = await source.rawQuery('PRAGMA table_info($table)');
    final targetInfo = await target.rawQuery('PRAGMA table_info($table)');
    final targetColumns = targetInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final columns = sourceInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty && targetColumns.contains(name))
        .toList(growable: false);
    if (columns.isEmpty) return;
    final names = columns.map(_quoteIdentifier).join(', ');
    final placeholders = List<String>.filled(columns.length, '?').join(', ');
    var offset = 0;
    while (true) {
      final rows = await source.query(
        table,
        columns: columns,
        limit: 500,
        offset: offset,
      );
      if (rows.isEmpty) break;
      await target.transaction<void>((txn) async {
        final batch = txn.batch();
        for (final row in rows) {
          batch.rawInsert(
            'INSERT OR IGNORE INTO ${_quoteIdentifier(table)} ($names) '
            'VALUES ($placeholders)',
            columns.map((column) => row[column]).toList(growable: false),
          );
        }
        await batch.commit(noResult: true);
      });
      offset += rows.length;
      if (rows.length < 500) break;
    }
  }

  static String _quoteIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  Future<T> runTransaction<T>(
    Future<T> Function(DatabaseExecutor transaction) action, {
    MessagePersistPriority persistPriority =
        MessagePersistPriority.userHistory,
    MessagePersistSource persistSource = MessagePersistSource.userHistory,
    String conversationId = '',
    int accountGeneration = 0,
    int itemCount = 1,
  }) {
    return MessagePersistCoordinator.instance.enqueue<T>(
      priority: persistPriority,
      source: persistSource,
      conversationId: conversationId,
      accountGeneration: accountGeneration,
      itemCount: itemCount,
      run: () async {
        final db = await _openDb();
        return db.transaction<T>((transaction) => action(transaction));
      },
    );
  }

  Future<void> closeIfOpen() async {
    final opening = _openInFlight;
    if (opening != null) {
      try {
        await opening.timeout(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
  }
}
