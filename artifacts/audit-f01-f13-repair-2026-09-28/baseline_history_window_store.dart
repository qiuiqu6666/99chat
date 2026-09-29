import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/common_utils.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';

/// Disk-backed, bounded page cache. Authority facts and deferred delivery are
/// durable business records and deliberately do not participate in cache LRU.
class HistoryWindowStore implements HistoryWindowRepository {
  HistoryWindowStore({
    this.maxPages = 256,
    this.maxRows = 12800,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxSessions = 4,
    this.maxDeferredTail = 120,
    this.maxPendingMutations = 8,
    this.debugDatabasePath,
    String? debugProcessID,
  })  : _processID = debugProcessID ?? _defaultProcessID,
        assert(maxPages > 0 && maxRows > 0 && maxBytes > 0 && maxSessions > 0);

  static final instance = HistoryWindowStore();
  static final String _defaultProcessID =
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';
  final String _processID;
  final int maxPages,
      maxRows,
      maxBytes,
      maxSessions,
      maxDeferredTail,
      maxPendingMutations;
  static const maxPageRows = 50;
  @visibleForTesting
  bool get isOpenForTesting => _db?.isOpen ?? false;
  String? debugDatabasePath;
  Database? _db;
  Future<Database>? _opening;
  Future<void> _serial = Future.value();
  int _clock = 0;
  int _lifecycle = 0;
  bool _factoryReady = false;

  int get _tick =>
      _clock = math.max(_clock + 1, DateTime.now().microsecondsSinceEpoch);
  String _scopeKey(HistoryWindowScope s) => jsonEncode([
        s.ownerUserID,
        s.accountGeneration,
        s.domainGeneration,
        s.conversationID,
        s.clearEpoch,
        s.sessionID,
      ]);
  String _deferredKey(HistoryWindowScope s) => jsonEncode([
        s.ownerUserID,
        s.conversationID,
        s.clearEpoch,
        s.accountGeneration,
        s.domainGeneration
      ]);

  Future<T> _run<T>(
    Future<T> Function(Database db) work, {
    bool write = false,
  }) {
    return _runSerial(work, write: write);
  }

  Future<T> _runSerial<T>(
    Future<T> Function(Database db) work, {
    required bool write,
  }) {
    final lifecycle = _lifecycle;
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        if (lifecycle != _lifecycle) throw const SqfliteClosedForBackground();
        if (write && !SqfliteLifecycleGuard.instance.writesAllowed) {
          throw const SqfliteClosedForBackground();
        }
        final db = await _open();
        if (lifecycle != _lifecycle) throw const SqfliteClosedForBackground();
        completer.complete(await work(db));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<Database> _open() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) return existing;
    return _opening ??= _openOnce().whenComplete(() => _opening = null);
  }

  Future<void> _ensureDatabaseFactory() async {
    if (_factoryReady) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      if (!identical(databaseFactory, databaseFactoryFfi)) {
        databaseFactory = databaseFactoryFfi;
      }
    }
    _factoryReady = true;
  }

  Future<Database> _openOnce() async {
    if (kIsWeb) {
      throw UnsupportedError('HistoryWindowStore requires durable SQLite');
    }
    await _ensureDatabaseFactory();
    final db = await openDatabase(
      debugDatabasePath ??
          p.join(await getDatabasesPath(), 'history_window_v1.db'),
      version: 3,
      onConfigure: (db) async {
        // Must run before any later write: auto_vacuum used to live here and
        // took an exclusive lock on every reopen, colliding with the app,
        // tests, or another window already holding history_window_v1.db.
        await db.rawQuery('PRAGMA busy_timeout=5000');
      },
      onOpen: (db) =>
          SqfliteBootstrapHelper.withTag('history_window').runOnOpenPragmas(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE hw_mutation_terminal ADD COLUMN clear_epoch INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE hw_mutation_versions ADD COLUMN clear_epoch INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE hw_mutation_versions ADD COLUMN is_command INTEGER NOT NULL DEFAULT 0');
          // v1 did not label terminal/source metadata by epoch. Conservatively
          // retain it in the last known epoch until the next genuine clear.
          await db.execute(
              'UPDATE hw_mutation_terminal SET clear_epoch=COALESCE((SELECT epoch FROM hw_clear_epochs e WHERE e.owner=hw_mutation_terminal.owner AND e.conversation=hw_mutation_terminal.conversation),0)');
          await db.execute(
              "UPDATE hw_mutation_versions SET clear_epoch=COALESCE((SELECT epoch FROM hw_clear_epochs e WHERE e.owner=hw_mutation_versions.owner AND e.conversation=hw_mutation_versions.conversation),0), is_command=CASE WHEN source LIKE 'command:%' THEN 1 ELSE 0 END");
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE hw_mutation_pending ADD COLUMN process_id TEXT NOT NULL DEFAULT ''");
          await db.execute(
              'CREATE INDEX hw_pending_process ON hw_mutation_pending(process_id)');
          // Legacy pending rows cannot prove which process produced optimistic
          // page copies. Invalidate only this reconstructible cache on upgrade.
          await db.delete('hw_page_ids');
          await db.delete('hw_pages');
          await db.delete('hw_sessions');
        }
      },
      onCreate: (db, _) async {
        // Incremental vacuum is a create-time header flag. Setting it on every
        // open requires an exclusive lock and fails with SQLITE_BUSY (code 5)
        // when another connection already holds history_window_v1.db.
        await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
        await db.execute('''CREATE TABLE hw_sessions (
          scope TEXT PRIMARY KEY, owner TEXT NOT NULL, conversation TEXT NOT NULL, process_id TEXT NOT NULL,
          account_generation INTEGER NOT NULL, domain_generation INTEGER NOT NULL,
          clear_epoch INTEGER NOT NULL, session_id TEXT NOT NULL,
          closed INTEGER NOT NULL DEFAULT 0, access INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE hw_pages (
          scope TEXT NOT NULL, page_key TEXT NOT NULL, newer_key TEXT, older_key TEXT,
          request_cursor TEXT, next_cursor TEXT, snapshot INTEGER, checksum TEXT,
          is_root INTEGER NOT NULL, payload TEXT NOT NULL, row_count INTEGER NOT NULL,
          byte_count INTEGER NOT NULL, access INTEGER NOT NULL,
          PRIMARY KEY(scope, page_key))''');
        await db.execute('CREATE INDEX hw_pages_lru ON hw_pages(access)');
        await db.execute('''CREATE TABLE hw_page_ids (
          scope TEXT NOT NULL, page_key TEXT NOT NULL, msg_id TEXT NOT NULL,
          ordinal INTEGER NOT NULL, PRIMARY KEY(scope,page_key,ordinal))''');
        await db.execute(
            'CREATE INDEX hw_page_lookup ON hw_page_ids(scope,msg_id)');
        await db.execute('''CREATE TABLE hw_clear_epochs (
          owner TEXT NOT NULL, conversation TEXT NOT NULL, epoch INTEGER NOT NULL,
          PRIMARY KEY(owner,conversation))''');
        await db.execute('''CREATE TABLE hw_mutations (
          revision INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL,
          conversation TEXT NOT NULL, clear_epoch INTEGER NOT NULL,
          event_id TEXT NOT NULL, msg_id TEXT NOT NULL, kind TEXT NOT NULL,
          authority_revision INTEGER NOT NULL, restore_token TEXT, payload TEXT,
          active INTEGER NOT NULL DEFAULT 1, previous_fact TEXT,
          UNIQUE(owner,conversation,msg_id,kind))''');
        await db.execute('''CREATE TABLE hw_mutation_versions (
          owner TEXT NOT NULL, conversation TEXT NOT NULL, msg_id TEXT NOT NULL, kind TEXT NOT NULL,
          source TEXT NOT NULL, revision INTEGER NOT NULL, access INTEGER NOT NULL DEFAULT 0,
          clear_epoch INTEGER NOT NULL DEFAULT 0, is_command INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(owner,conversation,msg_id,kind,source))''');
        await db.execute(
            'CREATE TABLE hw_mutation_order (singleton INTEGER PRIMARY KEY, revision INTEGER NOT NULL)');
        await db.execute("INSERT INTO hw_mutation_order VALUES (1,0)");
        await db.execute(
            "CREATE TABLE hw_mutation_pending (revision INTEGER PRIMARY KEY, owner TEXT NOT NULL, conversation TEXT NOT NULL, clear_epoch INTEGER NOT NULL,event_id TEXT NOT NULL,msg_id TEXT NOT NULL,kind TEXT NOT NULL,payload TEXT,process_id TEXT NOT NULL, UNIQUE(owner,conversation,msg_id,kind,event_id))");
        await db.execute(
            'CREATE INDEX hw_pending_lookup ON hw_mutation_pending(owner,conversation,msg_id,kind)');
        await db.execute(
            'CREATE INDEX hw_pending_process ON hw_mutation_pending(process_id)');
        await db.execute(
            "CREATE TABLE hw_mutation_terminal (owner TEXT NOT NULL,conversation TEXT NOT NULL,msg_id TEXT NOT NULL,kind TEXT NOT NULL,event_id TEXT NOT NULL,outcome TEXT NOT NULL,completion_order INTEGER NOT NULL,clear_epoch INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(owner,conversation,msg_id,kind,event_id))");
        await db.execute(
            'CREATE INDEX hw_mutation_lookup ON hw_mutations(owner,conversation,msg_id,revision)');
        await db.execute('''CREATE TABLE hw_deferred (
          bucket TEXT NOT NULL, event_id TEXT NOT NULL, ingress_sequence INTEGER NOT NULL,
          source_sequence INTEGER, account_generation INTEGER NOT NULL, domain_generation INTEGER NOT NULL,
          msg_id TEXT NOT NULL, unread INTEGER NOT NULL, payload TEXT,
          PRIMARY KEY(bucket,event_id),
          UNIQUE(bucket,account_generation,domain_generation,ingress_sequence))''');
        await db.execute(
            'CREATE UNIQUE INDEX hw_deferred_source ON hw_deferred(bucket,source_sequence) WHERE source_sequence>=0');
        await db.execute(
            'CREATE INDEX hw_deferred_legacy_source ON hw_deferred(bucket) WHERE source_sequence IS NULL');
        await db.execute(
            'CREATE INDEX hw_deferred_tail ON hw_deferred(bucket,ingress_sequence)');
        await db.execute(
            'CREATE INDEX hw_deferred_body_tail ON hw_deferred(bucket,ingress_sequence DESC) WHERE payload IS NOT NULL');
        await db.execute('''CREATE TABLE hw_deferred_state (
          bucket TEXT PRIMARY KEY, received INTEGER NOT NULL, unread INTEGER NOT NULL,
          first_seq INTEGER, last_seq INTEGER, first_id TEXT, last_id TEXT,
          acknowledged_sequence INTEGER NOT NULL DEFAULT -1,
          acknowledged_source_sequence INTEGER NOT NULL DEFAULT -1,
          body_active INTEGER NOT NULL DEFAULT 0, body_access INTEGER NOT NULL DEFAULT 0)''');
        await db.execute(
            'CREATE INDEX hw_deferred_active_buckets ON hw_deferred_state(body_access DESC) WHERE body_active=1');
      },
    );
    try {
      if (!SqfliteLifecycleGuard.instance.canOpenDatabase ||
          !SqfliteLifecycleGuard.instance.writesAllowed) {
        throw const SqfliteClosedForBackground();
      }
      // Optimistic commands are only meaningful in their issuing process.
      // A new process must rely on fresh SDK facts, not infer command success.
      // Discard the corresponding old session pages too: they may contain a
      // serialized optimistic revoked copy even after the pending row is gone.
      await db.transaction((tx) async {
        // Additive extension keeps the existing user_version readable by an
        // older binary; no authority records or pending deliveries are reset.
        await _upgradeDeferredOrdering(tx);
        await tx.delete('hw_mutation_pending',
            where: 'process_id<>?', whereArgs: [_processID]);
        final previousSessions = await tx.query('hw_sessions',
            columns: ['scope'],
            where: 'process_id<>?',
            whereArgs: [_processID]);
        for (final row in previousSessions) {
          await _deleteSessionPages(tx, row['scope'] as String);
        }
        await tx.delete('hw_sessions',
            where: 'process_id<>?', whereArgs: [_processID]);
      });
      // Cleanup contains awaits; a pause during it must not publish a handle
      // after the lifecycle host has already started closing database stores.
      if (!SqfliteLifecycleGuard.instance.canOpenDatabase ||
          !SqfliteLifecycleGuard.instance.writesAllowed) {
        throw const SqfliteClosedForBackground();
      }
      return _db = db;
    } catch (_) {
      // _db does not own this handle until all open-time work succeeds.
      await SqfliteLifecycleGuard.closeDatabase(db);
      rethrow;
    }
  }

  /// v3 used one number for arrival order and formal ingress replay protection.
  /// Keep its existing snapshot ordinals, but separate the formal source fence.
  /// Legacy ACK rows no longer contain source identity, so their old fence must
  /// remain conservative; already rejected legacy events cannot be recovered.
  Future<void> _upgradeDeferredOrdering(DatabaseExecutor db) async {
    final deliveryColumns = await db.rawQuery('PRAGMA table_info(hw_deferred)');
    if (!deliveryColumns.any((row) => row['name'] == 'source_sequence')) {
      await db.execute(
          'ALTER TABLE hw_deferred ADD COLUMN source_sequence INTEGER');
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS hw_deferred_legacy_source ON hw_deferred(bucket) WHERE source_sequence IS NULL');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS hw_deferred_source ON hw_deferred(bucket,source_sequence) WHERE source_sequence>=0');
    // Null identifies legacy writes, including writes from a temporary rollback.
    // Both old formal and fallback adapters used received: event IDs. There is
    // no reliable prefix discriminator: retain the old source fence rather
    // than let ordinary formal replays resurrect already counted messages.
    // New fallback writes explicitly use -1.
    // A legacy writer can reuse a formal source at a different ordinal. Keep
    // that row as unknown (-2) rather than fail opening or erase pending data.
    await db.execute('''UPDATE hw_deferred SET source_sequence=CASE
      WHEN EXISTS (SELECT 1 FROM hw_deferred identified
        WHERE identified.bucket=hw_deferred.bucket
        AND identified.source_sequence=hw_deferred.ingress_sequence
        AND identified.source_sequence>=0) THEN -2
      ELSE ingress_sequence END WHERE source_sequence IS NULL''');
    final stateColumns =
        await db.rawQuery('PRAGMA table_info(hw_deferred_state)');
    if (!stateColumns
        .any((row) => row['name'] == 'acknowledged_source_sequence')) {
      await db.execute(
          'ALTER TABLE hw_deferred_state ADD COLUMN acknowledged_source_sequence INTEGER NOT NULL DEFAULT -1');
      await db.execute(
          'UPDATE hw_deferred_state SET acknowledged_source_sequence=acknowledged_sequence');
    }
    for (final column in ['last_message_timestamp', 'last_group_message_seq']) {
      if (!stateColumns.any((row) => row['name'] == column)) {
        await db.execute(
            'ALTER TABLE hw_deferred_state ADD COLUMN $column INTEGER NOT NULL DEFAULT 0');
      }
    }
    final migratingBodies =
        !deliveryColumns.any((row) => row['name'] == 'message_timestamp');
    for (final column in [
      'acknowledged',
      'message_timestamp',
      'group_message_seq'
    ]) {
      if (!deliveryColumns.any((row) => row['name'] == column)) {
        await db.execute(
            'ALTER TABLE hw_deferred ADD COLUMN $column INTEGER NOT NULL DEFAULT 0');
      }
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS hw_deferred_pending ON hw_deferred(bucket,ingress_sequence) WHERE acknowledged=0');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS hw_deferred_message ON hw_deferred(bucket,msg_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS hw_deferred_content ON hw_deferred(bucket,group_message_seq DESC,message_timestamp DESC,ingress_sequence DESC) WHERE acknowledged=0');
    if (migratingBodies) {
      // Only the old bounded body tail is decoded once. SDK history owns the
      // bodies thereafter; the existing delivery rows keep identity and edges.
      final bodies = await db.query('hw_deferred',
          columns: ['bucket', 'event_id', 'payload'],
          where: 'payload IS NOT NULL');
      for (final row in bodies) {
        final message = _decodeMessage(row['payload'] as String);
        await db.update(
            'hw_deferred',
            {
              'message_timestamp': message.timestamp ?? 0,
              'group_message_seq': message.groupID?.isNotEmpty == true
                  ? int.tryParse(message.seq ?? '') ?? 0
                  : 0,
            },
            where: 'bucket=? AND event_id=?',
            whereArgs: [row['bucket'], row['event_id']]);
      }
      final states = await db.query('hw_deferred_state');
      for (final state in states) {
        await db.update(
            'hw_deferred',
            {
              'message_timestamp': _int(state['last_message_timestamp']),
              'group_message_seq': _int(state['last_group_message_seq']),
            },
            where:
                'bucket=? AND msg_id=? AND message_timestamp=0 AND group_message_seq=0',
            whereArgs: [state['bucket'], state['last_id']]);
        final newest =
            await _newestDeferredBoundary(db, state['bucket'] as String);
        if (newest != null) {
          await db.update(
              'hw_deferred_state',
              {
                'last_id': newest['msg_id'],
                'last_message_timestamp': newest['message_timestamp'],
                'last_group_message_seq': newest['group_message_seq'],
              },
              where: 'bucket=?',
              whereArgs: [state['bucket']]);
        }
      }
    }
    await db.update('hw_deferred', {'payload': null},
        where: 'payload IS NOT NULL');
  }

  Future<Map<String, Object?>?> _newestDeferredBoundary(
      DatabaseExecutor db, String bucket) async {
    final scope = jsonDecode(bucket) as List;
    final rows = await db.rawQuery(
        '''SELECT d.msg_id,d.message_timestamp,d.group_message_seq
      FROM hw_deferred d WHERE d.bucket=? AND d.acknowledged=0 AND NOT EXISTS (
        SELECT 1 FROM hw_mutations m WHERE m.owner=?
        AND (m.conversation=? OR m.conversation='*') AND m.msg_id=d.msg_id
        AND m.kind='delete' AND m.active=1)
      ORDER BY d.group_message_seq DESC,d.message_timestamp DESC,d.ingress_sequence DESC LIMIT 1''',
        [bucket, scope[0], scope[1]]);
    return rows.firstOrNull;
  }

  Future<void> _checkScope(DatabaseExecutor db, HistoryWindowScope s) async {
    _checkLease(s);
    if (s.ownerUserID.isEmpty ||
        s.conversationID.isEmpty ||
        s.sessionID.isEmpty) {
      throw ArgumentError(
          'History window scope must have owner, conversation and session');
    }
    final epochs = await db.query('hw_clear_epochs',
        columns: ['epoch'],
        where: 'owner=? AND conversation=?',
        whereArgs: [s.ownerUserID, s.conversationID]);
    if (epochs.isNotEmpty && _int(epochs.first['epoch']) > s.clearEpoch) {
      throw const HistoryWindowStaleScope();
    }
    final rows = await db
        .query('hw_sessions', where: 'scope=?', whereArgs: [_scopeKey(s)]);
    if (rows.isNotEmpty && _int(rows.first['closed']) != 0) {
      throw const HistoryWindowStaleScope();
    }
    final newer = await db.rawQuery(
        '''SELECT 1 FROM hw_sessions WHERE owner=? AND process_id=?
      AND (account_generation>? OR (account_generation=? AND domain_generation>?)) LIMIT 1''',
        [
          s.ownerUserID,
          _processID,
          s.accountGeneration,
          s.accountGeneration,
          s.domainGeneration
        ]);
    if (newer.isNotEmpty) throw const HistoryWindowStaleScope();
  }

  void _checkLease(HistoryWindowScope scope) {
    if (scope.isCurrent?.call() == false) throw const HistoryWindowStaleScope();
  }

  Future<bool> _touchSession(DatabaseExecutor db, HistoryWindowScope s) async {
    await _checkScope(db, s);
    final existed = await db.query('hw_sessions',
        columns: ['scope'],
        where: 'scope=?',
        whereArgs: [_scopeKey(s)],
        limit: 1);
    await db.insert(
        'hw_sessions',
        {
          'scope': _scopeKey(s),
          'process_id': _processID,
          'owner': s.ownerUserID,
          'conversation': s.conversationID,
          'account_generation': s.accountGeneration,
          'domain_generation': s.domainGeneration,
          'clear_epoch': s.clearEpoch,
          'session_id': s.sessionID,
          'closed': 0,
          'access': _tick,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return existed.isEmpty;
  }

  @override
  Future<void> savePage(HistoryWindowPage page) => savePages([page]);

  @override
  Future<void> savePages(List<HistoryWindowPage> pages) async {
    for (final page in pages) {
      await MessagePersistCoordinator.instance.enqueue<void>(
        priority: MessagePersistPriority.userHistory,
        source: MessagePersistSource.userHistory,
        conversationId: page.scope.conversationID,
        accountGeneration: page.scope.accountGeneration,
        itemCount: page.messages.isEmpty ? 1 : page.messages.length,
        run: () => _persistOnePage(page),
      );
    }
  }

  Future<void> _persistOnePage(HistoryWindowPage page) => _runSerial(
      (db) => db.transaction((tx) async {
            final touched = <String>{};
            for (final current in [page]) {
              if (current.pageKey.isEmpty) throw ArgumentError('Empty page key');
              final scope = _scopeKey(current.scope);
              if (touched.add(scope)) {
                await _touchSession(tx, current.scope);
              }
              final existing = await tx.query('hw_pages',
                  columns: [
                    'payload',
                    'snapshot',
                    'newer_key',
                    'older_key',
                    'is_root',
                    'request_cursor',
                    'next_cursor'
                  ],
                  where: 'scope=? AND page_key=?',
                  whereArgs: [scope, page.pageKey],
                  limit: 1);
              final previous = existing.isEmpty ? null : existing.first;
              final sameSnapshot = previous != null &&
                  previous['snapshot'] == page.snapshotMaxSeq;
              // A live-window edge is not evidence that cached history ends.
              // Keep proven external links when a subsequent trim saves only
              // a subset of the same snapshot under the same stable page key.
              final newerKey = page.newerPageKey ??
                  (sameSnapshot ? previous['newer_key'] as String? : null);
              final olderKey = page.olderPageKey ??
                  (sameSnapshot ? previous['older_key'] as String? : null);
              final isRoot = page.isReplayRoot ||
                  (sameSnapshot && _int(previous['is_root']) == 1);
              final requestCursor = page.requestCursor ??
                  (sameSnapshot ? previous['request_cursor'] as String? : null);
              final nextCursor = page.nextOlderCursor ??
                  (sameSnapshot ? previous['next_cursor'] as String? : null);
              final mergedMessages = await _retainAuthoritativeHistory(
                tx, current.scope,
                current.messages,
              );
              final encoded = await compute(_encodeHistoryPage, mergedMessages,
                  debugLabel: 'history-page-encode');
              final payload = encoded.$1;
              final bytes = encoded.$2 +
                  utf8
                      .encode(jsonEncode([
                        page.pageKey,
                        newerKey,
                        olderKey,
                        requestCursor,
                        nextCursor,
                        page.pageChecksum,
                        _scopeKey(page.scope),
                      ]))
                      .length +
                  128 +
                      encoded.$3.fold<int>(
                      0,
                      (n, id) =>
                          n +
                          utf8.encode(id).length +
                          utf8.encode(_scopeKey(page.scope)).length +
                          utf8.encode(page.pageKey).length +
                          96);
              if (mergedMessages.length > math.min(maxRows, maxPageRows) ||
                  bytes > maxBytes) {
                throw StateError(
                    'History page exceeds cache budget; retain the live window');
              }
              // A new replay root replaces the previous marker, but is still budgeted.
              if (page.isReplayRoot) {
                await tx.update('hw_pages', {'is_root': 0},
                    where: 'scope=?', whereArgs: [scope]);
              }
              final sameBody =
                  existing.isNotEmpty && existing.first['payload'] == payload;
              if (sameBody) {
                await tx.update(
                    'hw_pages',
                    {
                      'newer_key': newerKey,
                      'older_key': olderKey,
                      'request_cursor': requestCursor,
                      'next_cursor': nextCursor,
                      'snapshot': page.snapshotMaxSeq,
                      'checksum': page.pageChecksum,
                      'is_root': isRoot ? 1 : 0,
                      'byte_count': bytes,
                      'access': _tick,
                    },
                    where: 'scope=? AND page_key=?',
                    whereArgs: [scope, page.pageKey]);
              } else {
                await tx.insert(
                    'hw_pages',
                    {
                      'scope': scope,
                      'page_key': page.pageKey,
                      'newer_key': newerKey,
                      'older_key': olderKey,
                      'request_cursor': requestCursor,
                      'next_cursor': nextCursor,
                      'snapshot': page.snapshotMaxSeq,
                      'checksum': page.pageChecksum,
                      'is_root': isRoot ? 1 : 0,
                      'payload': payload,
                      'row_count': mergedMessages.length,
                      'byte_count': bytes,
                      'access': _tick,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
                await tx.delete('hw_page_ids',
                    where: 'scope=? AND page_key=?',
                    whereArgs: [scope, page.pageKey]);
                final batch = tx.batch();
                for (var i = 0; i < mergedMessages.length; i++) {
                  final id = encoded.$3[i];
                  if (id.isNotEmpty) {
                    batch.insert('hw_page_ids', {
                      'scope': scope,
                      'page_key': page.pageKey,
                      'msg_id': id,
                      'ordinal': i,
                    });
                  }
                }
                await batch.commit(noResult: true);
              }
              // Only explicit transport links establish adjacency. Same-snapshot pages
              // receive reciprocal links; a cache hole is never silently bridged.
              final snapshotPredicate = page.snapshotMaxSeq == null
                  ? 'snapshot IS NULL'
                  : 'snapshot=?';
              for (final link in [
                (newerKey, 'older_key'),
                (olderKey, 'newer_key')
              ]) {
                if (link.$1 == null) continue;
                await tx.rawUpdate(
                    'UPDATE hw_pages SET ${link.$2}=? WHERE scope=? AND page_key=? AND $snapshotPredicate',
                    [
                      page.pageKey,
                      scope,
                      link.$1,
                      if (page.snapshotMaxSeq != null) page.snapshotMaxSeq
                    ]);
              }
            }
            await _evict(tx);
            final retained = await tx.query('hw_pages',
                columns: ['page_key'],
                where: 'scope=? AND page_key=?',
                whereArgs: [_scopeKey(page.scope), page.pageKey]);
            if (retained.isEmpty) {
              throw StateError('Saved page could not be retained');
            }
            _checkLease(page.scope);
          }),
      write: true);

  Future<void> _deletePage(
      DatabaseExecutor tx, String scope, String key) async {
    await tx.delete('hw_page_ids',
        where: 'scope=? AND page_key=?', whereArgs: [scope, key]);
    await tx.delete('hw_pages',
        where: 'scope=? AND page_key=?', whereArgs: [scope, key]);
    // Keep neighbors' absent-target links: they are explicit evidence of a hole,
    // useful to resume from the replay root, never proof of exhaustion.
  }

  Future<void> _deleteSessionPages(DatabaseExecutor tx, String scope) async {
    await tx.delete('hw_page_ids', where: 'scope=?', whereArgs: [scope]);
    await tx.delete('hw_pages', where: 'scope=?', whereArgs: [scope]);
  }

  Future<void> _evict(DatabaseExecutor tx) async {
    final sessions = await tx.query('hw_sessions', orderBy: 'access DESC');
    for (final row in sessions.skip(maxSessions)) {
      final scope = row['scope'] as String;
      await _deleteSessionPages(tx, scope);
      await tx.delete('hw_sessions', where: 'scope=?', whereArgs: [scope]);
    }
    final rows = await tx.query('hw_pages',
        columns: ['scope', 'page_key', 'row_count', 'byte_count', 'is_root'],
        orderBy: 'access ASC');
    var pages = rows.length;
    var count = rows.fold<int>(0, (v, r) => v + _int(r['row_count']));
    var bytes = rows.fold<int>(0, (v, r) => v + _int(r['byte_count']));
    final removed = <String>{};
    for (final row in rows.where((r) => _int(r['is_root']) == 0)) {
      if (pages <= maxPages && count <= maxRows && bytes <= maxBytes) break;
      await _deletePage(tx, row['scope'] as String, row['page_key'] as String);
      removed.add(jsonEncode([row['scope'], row['page_key']]));
      pages--;
      count -= _int(row['row_count']);
      bytes -= _int(row['byte_count']);
    }
    if (pages > maxPages || count > maxRows || bytes > maxBytes) {
      final oldest = await tx.query('hw_sessions',
          columns: ['scope'], orderBy: 'access ASC');
      for (final session in oldest) {
        if (pages <= maxPages && count <= maxRows && bytes <= maxBytes) break;
        final sessionKey = session['scope'] as String;
        for (final row in rows.where((r) =>
            r['scope'] == sessionKey &&
            !removed.contains(jsonEncode([r['scope'], r['page_key']])))) {
          pages--;
          count -= _int(row['row_count']);
          bytes -= _int(row['byte_count']);
        }
        await _deleteSessionPages(tx, sessionKey);
        await tx
            .delete('hw_sessions', where: 'scope=?', whereArgs: [sessionKey]);
      }
    }
  }

  Future<HistoryWindowPage> _page(HistoryWindowScope scope, Map<String, Object?> row) async {
    final payload = row['payload'] as String;
    final useIsolate = payload.length >= 32768 || _int(row['row_count']) >= 20;
    List<V2TimMessage> messages;
    if (useIsolate) {
      try {
        messages = await compute(
          _decodeHistoryPage,
          (payload: payload, seed: CommonUtils.exportIsolateSeed()),
          debugLabel: 'history-page-decode',
        );
      } catch (e, st) {
        debugPrint(
          'HistoryWindowStore: isolate page decode failed, fallback sync: $e\n$st',
        );
        messages = _decodeHistoryPage((payload: payload, seed: null));
      }
    } else {
      messages = _decodeHistoryPage((payload: payload, seed: null));
    }
    return HistoryWindowPage(
        scope: scope,
        pageKey: row['page_key'] as String,
        messages: messages,
        newerPageKey: row['newer_key'] as String?,
        olderPageKey: row['older_key'] as String?,
        requestCursor: row['request_cursor'] as String?,
        nextOlderCursor: row['next_cursor'] as String?,
        snapshotMaxSeq: row['snapshot'] as int?,
        pageChecksum: row['checksum'] as String?,
        isReplayRoot: _int(row['is_root']) != 0,
      );
  }

  Future<HistoryWindowPage?> _loadPage(
      DatabaseExecutor db, HistoryWindowScope scope, String key) async {
    final rows = await db.query('hw_pages',
        where: 'scope=? AND page_key=? AND row_count<=?',
        whereArgs: [_scopeKey(scope), key, maxPageRows],
        limit: 1);
    if (rows.isEmpty || _int(rows.first['row_count']) > maxPageRows) {
      return null;
    }
    if (SqfliteLifecycleGuard.instance.writesAllowed) {
      await db.update('hw_pages', {'access': _tick},
          where: 'scope=? AND page_key=?', whereArgs: [_scopeKey(scope), key]);
      await db.update('hw_sessions', {'access': _tick},
          where: 'scope=?', whereArgs: [_scopeKey(scope)]);
    }
    return _page(scope, rows.first);
  }

  Future<HistoryWindowReadResult> _result(
      DatabaseExecutor db,
      HistoryWindowScope scope,
      List<HistoryWindowPage> pages,
      List<V2TimMessage> messages,
      {HistoryWindowDirection? missing,
      HistoryWindowBoundary? boundary,
      bool alreadyApplied = false}) async {
    final projected =
        alreadyApplied ? messages : await _apply(db, scope, messages);
    if (scope.isCurrent?.call() == false) {
      return HistoryWindowReadResult(
          status: HistoryWindowReadStatus.stale, boundary: boundary);
    }
    return HistoryWindowReadResult(
        status: pages.isEmpty || (boundary != null && messages.isEmpty)
            ? HistoryWindowReadStatus.miss
            : HistoryWindowReadStatus.hit,
        messages: projected,
        pageKeys: pages.map((p) => p.pageKey).toList(),
        pages: pages,
        snapshotMaxSeq: pages.isEmpty ? null : pages.first.snapshotMaxSeq,
        boundary: boundary,
        missingDirection: missing);
  }

  @override
  Future<HistoryWindowReadResult> readPage(
          {required HistoryWindowScope scope, required String pageKey}) =>
      _run((db) async {
        try {
          await _checkScope(db, scope);
        } on HistoryWindowStaleScope {
          return const HistoryWindowReadResult(
              status: HistoryWindowReadStatus.stale);
        }
        final page = await _loadPage(db, scope, pageKey);
        return _result(
            db, scope, page == null ? [] : [page], page?.messages ?? []);
      });

  @override
  Future<HistoryWindowReadResult> readReplayRoot(HistoryWindowScope scope) =>
      _run((db) async {
        try {
          await _checkScope(db, scope);
        } on HistoryWindowStaleScope {
          return const HistoryWindowReadResult(
              status: HistoryWindowReadStatus.stale);
        }
        final roots = await db.query('hw_pages',
            columns: ['page_key'],
            where: 'scope=? AND is_root=1',
            whereArgs: [_scopeKey(scope)],
            limit: 1);
        final page = roots.isEmpty
            ? null
            : await _loadPage(db, scope, roots.first['page_key'] as String);
        return _result(
            db, scope, page == null ? [] : [page], page?.messages ?? []);
      });

  @override
  Future<HistoryWindowReadResult> readAdjacent(
          {required HistoryWindowScope scope,
          required HistoryWindowBoundary boundary,
          required HistoryWindowDirection direction,
          int limit = 50}) =>
      _run((db) async {
        try {
          await _checkScope(db, scope);
        } on HistoryWindowStaleScope {
          return HistoryWindowReadResult(
              status: HistoryWindowReadStatus.stale, boundary: boundary);
        }
        final cap = limit.clamp(1, 200);
        String? pageKey = boundary.pageKey;
        int? ordinal = boundary.ordinal;
        if (pageKey == null || ordinal == null) {
          final locations = await db.rawQuery(
              'SELECT i.page_key,i.ordinal FROM hw_page_ids i JOIN hw_pages p ON p.scope=i.scope AND p.page_key=i.page_key WHERE i.scope=? AND i.msg_id=? ORDER BY p.access DESC LIMIT 1',
              [_scopeKey(scope), boundary.msgID]);
          if (locations.isNotEmpty) {
            pageKey = locations.first['page_key'] as String;
            ordinal = _int(locations.first['ordinal']);
          }
        }
        var current =
            pageKey == null ? null : await _loadPage(db, scope, pageKey);
        if (current == null ||
            ordinal == null ||
            ordinal < 0 ||
            ordinal >= current.messages.length) {
          return HistoryWindowReadResult(
              status: HistoryWindowReadStatus.miss,
              boundary: boundary,
              missingDirection: direction);
        }
        final snapshot = current.snapshotMaxSeq;
        final snapshotPredicate =
            snapshot == null ? 'snapshot IS NULL' : 'snapshot=?';
        final pages = <HistoryWindowPage>[];
        final visited = <String>{};
        final selected = <V2TimMessage>[];
        final seen = <String>{boundary.msgID};
        HistoryWindowDirection? missing;
        HistoryWindowBoundary? continuation;
        var scannedRows = 0;
        var scanLimitReached = false;
        var cursor = ordinal;
        var frontier = boundary;
        while (current != null && visited.add(current.pageKey)) {
          scannedRows += current.messages.length;
          // Retain metadata only. Across four pages at most 200 source messages
          // are decoded; deleted pages cannot accumulate as a hidden output list.
          pages.add(HistoryWindowPage(
              scope: scope,
              pageKey: current.pageKey,
              messages: const [],
              newerPageKey: current.newerPageKey,
              olderPageKey: current.olderPageKey,
              requestCursor: current.requestCursor,
              nextOlderCursor: current.nextOlderCursor,
              snapshotMaxSeq: current.snapshotMaxSeq,
              pageChecksum: current.pageChecksum,
              isReplayRoot: current.isReplayRoot));
          final positions = direction == HistoryWindowDirection.older
              ? [for (var i = cursor + 1; i < current.messages.length; i++) i]
              : [for (var i = cursor - 1; i >= 0; i--) i];
          final raw = [for (final i in positions) current.messages[i]];
          final corrected = await _apply(db, scope, raw);
          final byID = {
            for (final message in corrected)
              if (_identity(message).isNotEmpty) _identity(message): message
          };
          final anonymous = Set<V2TimMessage>.identity()
            ..addAll(corrected.where((m) => _identity(m).isEmpty));
          for (var i = 0; i < raw.length; i++) {
            final original = raw[i];
            final id = _identity(original);
            frontier = HistoryWindowBoundary(
                msgID: id,
                seq: original.seq,
                pageKey: current.pageKey,
                ordinal: positions[i]);
            continuation = frontier;
            final message = id.isEmpty
                ? (anonymous.contains(original) ? original : null)
                : byID[id];
            if (message != null && (id.isEmpty || seen.add(id))) {
              selected.add(message);
            }
            if (selected.length >= cap) break;
          }
          if (selected.length >= cap) break;
          final nextKey = direction == HistoryWindowDirection.older
              ? current.olderPageKey
              : current.newerPageKey;
          String? candidateKey;
          int? candidateOrdinal;
          // Validate links from metadata before decoding any candidate payload.
          // A rejected link must not consume an unreported fifth page decode.
          if (nextKey != null && !visited.contains(nextKey)) {
            final reciprocalColumn = direction == HistoryWindowDirection.older
                ? 'newer_key'
                : 'older_key';
            final linked = await db.query('hw_pages',
                columns: ['page_key'],
                where:
                    'scope=? AND page_key=? AND $snapshotPredicate AND $reciprocalColumn=? AND row_count<=?',
                whereArgs: [
                  _scopeKey(scope),
                  nextKey,
                  if (snapshot != null) snapshot,
                  current.pageKey,
                  maxPageRows
                ],
                limit: 1);
            if (linked.isNotEmpty) candidateKey = nextKey;
          }
          if (candidateKey == null && frontier.msgID.isNotEmpty) {
            final space = direction == HistoryWindowDirection.older
                ? 'p.row_count-i.ordinal-1'
                : 'i.ordinal';
            final exclusions = List.filled(visited.length, '?').join(',');
            // The shared message proves an overlap, including when that
            // message is deleted by authority facts. Require actual rows in
            // the requested direction so overlap-only cycles cannot stall.
            final overlapping = await db.rawQuery(
                'SELECT i.page_key,i.ordinal FROM hw_page_ids i '
                'JOIN hw_pages p ON p.scope=i.scope AND p.page_key=i.page_key '
                'WHERE i.scope=? AND i.msg_id=? AND p.$snapshotPredicate '
                'AND p.row_count<=? AND $space>0 '
                'AND i.page_key NOT IN ($exclusions) '
                'ORDER BY $space DESC,p.access DESC LIMIT 1',
                [
                  _scopeKey(scope),
                  frontier.msgID,
                  if (snapshot != null) snapshot,
                  maxPageRows,
                  ...visited
                ]);
            if (overlapping.isNotEmpty) {
              candidateKey = overlapping.first['page_key'] as String;
              candidateOrdinal = _int(overlapping.first['ordinal']);
            }
          }
          if (candidateKey == null) {
            missing = direction;
            break;
          }
          if (pages.length >= 4 || scannedRows >= 200) {
            scanLimitReached = true;
            continuation ??= frontier;
            break;
          }
          final next = await _loadPage(db, scope, candidateKey);
          if (next == null) {
            missing = direction;
            break;
          }
          current = next;
          cursor = candidateOrdinal ??
              (direction == HistoryWindowDirection.older
                  ? -1
                  : next.messages.length);
        }
        if (scope.isCurrent?.call() == false) {
          return HistoryWindowReadResult(
              status: HistoryWindowReadStatus.stale, boundary: boundary);
        }
        final newer = direction == HistoryWindowDirection.newer;
        return HistoryWindowReadResult(
            status: selected.isNotEmpty || scanLimitReached
                ? HistoryWindowReadStatus.hit
                : HistoryWindowReadStatus.miss,
            messages: newer ? selected.reversed.toList() : selected,
            pageKeys: pages.map((p) => p.pageKey).toList(),
            pages: newer ? pages.reversed.toList() : pages,
            snapshotMaxSeq: snapshot,
            boundary: boundary,
            missingDirection: missing,
            continuationBoundary: continuation,
            scanLimitReached: scanLimitReached,
            scannedRows: scannedRows);
      });

  @override
  Future<void> recordMutation(HistoryWindowMutation mutation) async {
    await _run(
      (db) => db.transaction((tx) async {
            if (mutation.ownerUserID.isEmpty ||
                mutation.msgID.isEmpty ||
                mutation.eventID.isEmpty) {
              throw ArgumentError(
                  'Mutation requires owner, message and event ID');
            }
            if (mutation.isCurrent?.call() == false) {
              throw const HistoryWindowStaleScope();
            }
            final authorization = mutation.authorizationScope;
            if (authorization != null) {
              if (authorization.ownerUserID != mutation.ownerUserID ||
                  (mutation.conversationID != null &&
                      authorization.conversationID !=
                          mutation.conversationID)) {
                throw const HistoryWindowStaleScope();
              }
              await _checkScope(tx, authorization);
            }
            final conversation = mutation.conversationID ?? '*';
            if (conversation != '*') {
              final epochs = await tx.query('hw_clear_epochs',
                  columns: ['epoch'],
                  where: 'owner=? AND conversation=?',
                  whereArgs: [mutation.ownerUserID, conversation]);
              if (epochs.isNotEmpty &&
                  _int(epochs.first['epoch']) > mutation.clearEpoch) {
                throw const HistoryWindowStaleScope();
              }
            }
            final key = [
              mutation.ownerUserID,
              conversation,
              mutation.msgID,
              mutation.kind.name
            ];
            final terminal =
                mutation.kind == HistoryWindowMutationKind.restore ||
                    mutation.kind == HistoryWindowMutationKind.settle;
            if (terminal) {
              final token = mutation.restoreMutationToken;
              if (token == null || token.isEmpty) {
                throw ArgumentError('Terminal command requires original token');
              }
              final pending = await tx.rawQuery(
                  "SELECT * FROM hw_mutation_pending WHERE owner=? AND msg_id=? AND event_id=? AND (conversation=? OR conversation='*')",
                  [mutation.ownerUserID, mutation.msgID, token, conversation]);
              for (final command in pending) {
                final commandKey = [
                  command['owner'],
                  command['conversation'],
                  command['msg_id'],
                  command['kind']
                ];
                if (mutation.kind == HistoryWindowMutationKind.settle) {
                  final current = await tx.query('hw_mutations',
                      columns: ['revision'],
                      where:
                          'owner=? AND conversation=? AND msg_id=? AND kind=?',
                      whereArgs: commandKey);
                  if (current.isEmpty ||
                      _int(current.first['revision']) <
                          _int(command['revision'])) {
                    await tx.insert(
                        'hw_mutations',
                        {
                          'revision': command['revision'],
                          'owner': command['owner'],
                          'conversation': command['conversation'],
                          'clear_epoch': command['clear_epoch'],
                          'event_id': command['event_id'],
                          'msg_id': command['msg_id'],
                          'kind': command['kind'],
                          'payload': command['payload'],
                          'authority_revision': 0,
                          'active': 1,
                        },
                        conflictAlgorithm: ConflictAlgorithm.replace);
                  }
                }
                await tx.delete('hw_mutation_pending',
                    where: 'revision=?', whereArgs: [command['revision']]);
                await tx.insert(
                    'hw_mutation_terminal',
                    {
                      'owner': command['owner'],
                      'conversation': command['conversation'],
                      'msg_id': command['msg_id'],
                      'kind': command['kind'],
                      'event_id': command['event_id'],
                      'outcome': mutation.kind.name,
                      'clear_epoch': command['clear_epoch'],
                      'completion_order': await _nextAuthorityRevision(tx),
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
                await tx.rawDelete(
                    'DELETE FROM hw_mutation_terminal WHERE rowid IN (SELECT rowid FROM hw_mutation_terminal WHERE owner=? AND conversation=? AND msg_id=? AND kind=? ORDER BY completion_order DESC LIMIT -1 OFFSET 16)',
                    commandKey);
              }
            } else {
              final source = mutation.sourceKey;
              if (source != null &&
                  source.isNotEmpty &&
                  mutation.revision > 0) {
                final previous = await tx.query('hw_mutation_versions',
                    columns: ['revision'],
                    where:
                        'owner=? AND conversation=? AND msg_id=? AND kind=? AND source=?',
                    whereArgs: [...key, source]);
                if (previous.isNotEmpty &&
                    _int(previous.first['revision']) >= mutation.revision) {
                  return;
                }
              }
              if (mutation.kind == HistoryWindowMutationKind.edit &&
                  mutation.message == null) {
                throw ArgumentError('Edit requires a complete message');
              }
              final table =
                  mutation.pending ? 'hw_mutation_pending' : 'hw_mutations';
              final duplicate = await tx.query(table,
                  columns: ['event_id'],
                  where:
                      'owner=? AND conversation=? AND msg_id=? AND kind=? AND event_id=?',
                  whereArgs: [...key, mutation.eventID],
                  limit: 1);
              final ended = await tx.query('hw_mutation_terminal',
                  columns: ['event_id'],
                  where:
                      'owner=? AND conversation=? AND msg_id=? AND kind=? AND event_id=?',
                  whereArgs: [...key, mutation.eventID],
                  limit: 1);
              if (duplicate.isNotEmpty || ended.isNotEmpty) return;
              if (mutation.pending) {
                final count = _int((await tx.rawQuery(
                        'SELECT COUNT(*) FROM hw_mutation_pending WHERE owner=? AND conversation=? AND msg_id=? AND kind=?',
                        key))
                    .first
                    .values
                    .first);
                if (count >= maxPendingMutations) {
                  throw const HistoryWindowPendingLimit();
                }
              }
              await tx.insert(
                  table,
                  {
                    'revision': await _nextAuthorityRevision(tx),
                    'owner': mutation.ownerUserID,
                    'conversation': conversation,
                    'clear_epoch': mutation.clearEpoch,
                    'event_id': mutation.eventID,
                    'msg_id': mutation.msgID,
                    'kind': mutation.kind.name,
                    'payload': mutation.message == null
                        ? null
                        : jsonEncode(_messageJson(mutation.message!)),
                    if (!mutation.pending)
                      'authority_revision': mutation.revision,
                    if (!mutation.pending) 'active': 1,
                    if (mutation.pending) 'process_id': _processID,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace);
              if (source != null &&
                  source.isNotEmpty &&
                  mutation.revision > 0) {
                await tx.insert(
                    'hw_mutation_versions',
                    {
                      'owner': mutation.ownerUserID,
                      'conversation': conversation,
                      'msg_id': mutation.msgID,
                      'kind': mutation.kind.name,
                      'source': source,
                      'revision': mutation.revision,
                      'access': _tick,
                      'clear_epoch': mutation.clearEpoch,
                      'is_command': mutation.pending ? 1 : 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
                await tx.rawDelete(
                    'DELETE FROM hw_mutation_versions WHERE rowid IN (SELECT rowid FROM hw_mutation_versions WHERE owner=? AND conversation=? AND msg_id=? AND kind=? ORDER BY access DESC LIMIT -1 OFFSET 4)',
                    key);
              }
            }
            // A caller's account/domain fence can invalidate while SQLite yields.
            if (mutation.isCurrent?.call() == false) {
              throw const HistoryWindowStaleScope();
            }
          }),
      write: true);
    _rememberMutationAuthority(mutation);
  }

  void _rememberMutationAuthority(HistoryWindowMutation mutation) {
    if (mutation.pending) return;
    final conversationId = mutation.conversationID?.trim() ?? '';
    if (conversationId.isEmpty || mutation.msgID.trim().isEmpty) return;
    final kind = switch (mutation.kind) {
      HistoryWindowMutationKind.revoke => MessagePersistAuthorityKind.revoke,
      HistoryWindowMutationKind.delete => MessagePersistAuthorityKind.delete,
      HistoryWindowMutationKind.edit => MessagePersistAuthorityKind.edit,
      HistoryWindowMutationKind.settle ||
      HistoryWindowMutationKind.restore =>
        MessagePersistAuthorityKind.sendState,
    };
    MessagePersistCoordinator.instance.rememberAuthority(
      conversationId: conversationId,
      messageId: mutation.msgID,
      kind: kind,
    );
  }

  Future<List<V2TimMessage>> _retainAuthoritativeHistory(
    DatabaseExecutor db, HistoryWindowScope scope,
    List<V2TimMessage> messages,
  ) async {
    final conversationId = scope.conversationID;
    final coordinator = MessagePersistCoordinator.instance;
    final kinds = <String, MessagePersistAuthorityKind>{};
    final missing = <String>{};
    for (final message in messages) {
      final id = _identity(message);
      final cached = coordinator.authorityFor(conversationId: conversationId, messageId: id);
      if (cached != null) { kinds[id] = cached; }
      else if (id.isNotEmpty) { missing.add(id); }
    }
    // UI authority is only a bounded hot cache. Old durable facts must survive
    // its eviction, including completed optimistic commands.
    final ids = missing.toList();
    for (var offset = 0; offset < ids.length; offset += 400) {
      final batch = ids.sublist(offset, math.min(offset + 400, ids.length));
      final placeholders = List.filled(batch.length, '?').join(',');
      final args = [scope.ownerUserID, conversationId, ...batch];
      final facts = await db.rawQuery(
          "SELECT msg_id,kind FROM hw_mutations WHERE owner=? AND (conversation=? OR conversation='*') AND active=1 AND kind='revoke' AND msg_id IN ($placeholders) UNION ALL SELECT msg_id,'sendState' AS kind FROM hw_mutation_terminal WHERE owner=? AND (conversation=? OR conversation='*') AND msg_id IN ($placeholders)",
          [...args, ...args]);
      for (final fact in facts) {
        final id = fact['msg_id'] as String;
        if (fact['kind'] == 'revoke') { kinds[id] = MessagePersistAuthorityKind.revoke; }
        else { kinds.putIfAbsent(id, () => MessagePersistAuthorityKind.sendState); }
      }
    }
    final out = <V2TimMessage>[];
    for (final message in messages) {
      final id = _identity(message);
      final kind = kinds[id];
      if (kind == MessagePersistAuthorityKind.revoke) {
        message.status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
      }
      out.add(message);
    }
    return out;
  }

  Future<int> _nextAuthorityRevision(DatabaseExecutor tx) async {
    await tx.rawUpdate(
        'UPDATE hw_mutation_order SET revision=revision+1 WHERE singleton=1');
    return _int((await tx.query('hw_mutation_order',
            columns: ['revision'], where: 'singleton=1'))
        .single['revision']);
  }

  @override
  Future<List<V2TimMessage>> applyMutations(
          {required HistoryWindowScope scope,
          required List<V2TimMessage> messages}) =>
      _run((db) async {
        await _checkScope(db, scope);
        final result = await _apply(db, scope, messages);
        _checkLease(scope);
        return result;
      });

  Future<List<V2TimMessage>> _apply(DatabaseExecutor db,
      HistoryWindowScope scope, List<V2TimMessage> messages) async {
    if (messages.isEmpty) return [];
    final ids =
        messages.map(_identity).where((id) => id.isNotEmpty).toSet().toList();
    final grouped = <String, List<Map<String, Object?>>>{};
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, math.min(i + 400, ids.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      final args = [scope.ownerUserID, scope.conversationID, ...chunk];
      final rows = await db.rawQuery(
          "SELECT msg_id,kind,payload,revision FROM hw_mutations WHERE owner=? AND (conversation=? OR conversation='*') AND active=1 AND msg_id IN ($placeholders) UNION ALL SELECT msg_id,kind,payload,revision FROM hw_mutation_pending WHERE owner=? AND (conversation=? OR conversation='*') AND msg_id IN ($placeholders) ORDER BY revision",
          [...args, ...args]);
      for (final row in rows) {
        (grouped[row['msg_id'] as String] ??= []).add(row);
      }
    }
    final result = <V2TimMessage>[];
    for (final original in messages) {
      final rows = grouped[_identity(original)];
      if (rows == null) {
        result.add(original);
        continue;
      }
      var message = original;
      String? latestEdit;
      var deleted = false;
      var revoked = false;
      for (final row in rows) {
        if (row['kind'] == 'edit' && row['payload'] != null) {
          latestEdit = row['payload'] as String;
        } else if (row['kind'] == 'delete') {
          deleted = true;
        } else if (row['kind'] == 'revoke') {
          revoked = true;
        }
      }
      if (deleted) continue;
      if (latestEdit != null) message = _decodeMessage(latestEdit);
      if (revoked) {
        message = _messageFromJson(_messageJson(message));
        message.status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
      }
      result.add(message);
    }
    return result;
  }

  @override
  Future<HistoryWindowDeferredReceipt> appendDeferred(
          {required HistoryWindowScope scope,
          required String eventID,
          required int ingressSequence,
          bool hasStableIngressSequence = true,
          required V2TimMessage message}) {
    return _run(
          (db) => db.transaction((tx) async {
                if (await _touchSession(tx, scope)) await _evict(tx);
                if (eventID.isEmpty || ingressSequence < 0) {
                  throw ArgumentError(
                      'Deferred append requires ingress identity');
                }
                final bucket = _deferredKey(scope);
                final old = await tx.query('hw_deferred_state',
                    where: 'bucket=?', whereArgs: [bucket]);
                final previous = old.firstOrNull;
                // The coalescer and direct SDK adapter can name the same
                // callback differently. Message identity is shared by both,
                // including metadata rows retained after a SDK-only ACK.
                final messageID = _identity(message);
                if (messageID.isNotEmpty) {
                  final existing = await tx.query('hw_deferred',
                      columns: ['event_id'],
                      where: 'bucket=? AND msg_id=?',
                      whereArgs: [bucket, messageID],
                      limit: 1);
                  if (existing.isNotEmpty) {
                    return HistoryWindowDeferredReceipt(
                        inserted: false,
                        state: previous == null
                            ? const HistoryWindowDeferredState()
                            : _state(previous));
                  }
                }
                // A local fallback counter must never advance the formal
                // ingress replay fence. Conversely, a newly arriving formal
                // event must be ordered after an already captured UI snapshot.
                if (hasStableIngressSequence &&
                    previous != null &&
                    ingressSequence <=
                        _int(previous['acknowledged_source_sequence'])) {
                  return HistoryWindowDeferredReceipt(
                      inserted: false, state: _state(previous));
                }
                final retainedOrdinal = (await tx.rawQuery(
                        'SELECT MAX(ingress_sequence) AS ordinal FROM hw_deferred WHERE bucket=?',
                        [bucket]))
                    .first['ordinal'] as int?;
                final previousPendingOrdinal = previous == null
                    ? -1
                    : math.max(previous['last_seq'] as int? ?? -1,
                        _int(previous['acknowledged_sequence']));
                // Individually read rows retain identity for replay protection.
                // Their ordinal still owns its position even after the pending
                // tail moves backwards or becomes empty.
                final previousOrdinal =
                    math.max(previousPendingOrdinal, retainedOrdinal ?? -1);
                final ordinal = math.max(previousOrdinal + 1,
                    hasStableIngressSequence ? ingressSequence : 1);
                final unread =
                    message.isSelf != true && message.isRead != true ? 1 : 0;
                await tx.insert(
                    'hw_deferred',
                    {
                      'bucket': bucket,
                      'event_id': eventID,
                      'ingress_sequence': ordinal,
                      'source_sequence':
                          hasStableIngressSequence ? ingressSequence : -1,
                      'account_generation': scope.accountGeneration,
                      'domain_generation': scope.domainGeneration,
                      'msg_id': _identity(message),
                      'unread': unread,
                      'message_timestamp': message.timestamp ?? 0,
                      'group_message_seq': message.groupID?.isNotEmpty == true
                          ? int.tryParse(message.seq ?? '') ?? 0
                          : 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore);
                final inserted = _int((await tx.rawQuery('SELECT changes()'))
                        .first
                        .values
                        .first) ==
                    1;
                if (inserted) {
                  final timestamp = message.timestamp ?? 0;
                  final groupSeq = message.groupID?.isNotEmpty == true
                      ? int.tryParse(message.seq ?? '') ?? 0
                      : 0;
                  final previousSeq = _int(previous?['last_group_message_seq']);
                  final previousTime =
                      _int(previous?['last_message_timestamp']);
                  final isNewest = previous == null ||
                      _int(previous['received']) == 0 ||
                      groupSeq > previousSeq ||
                      (groupSeq == previousSeq && timestamp >= previousTime);
                  final identity = _identity(message);
                  // Android 9 ships SQLite 3.22, which does not parse UPSERT.
                  if (previous == null) {
                    await tx.insert('hw_deferred_state', {
                      'bucket': bucket,
                      'received': 1,
                      'unread': unread,
                      'first_seq': ordinal,
                      'last_seq': ordinal,
                      'first_id': identity,
                      'last_id': identity,
                      'body_active': 1,
                      'body_access': _tick,
                      'last_message_timestamp': timestamp,
                      'last_group_message_seq': groupSeq,
                    });
                  } else {
                    final firstSeq = previous['first_seq'] as int?;
                    final lastSeq = previous['last_seq'] as int?;
                    await tx.update(
                        'hw_deferred_state',
                        {
                          'received': _int(previous['received']) + 1,
                          'unread': _int(previous['unread']) + unread,
                          'first_id': firstSeq == null || ordinal < firstSeq
                              ? identity
                              : previous['first_id'],
                          'last_id':
                              isNewest ? identity : previous['last_id'],
                          'first_seq': firstSeq == null
                              ? ordinal
                              : math.min(firstSeq, ordinal),
                          'last_seq': lastSeq == null
                              ? ordinal
                              : math.max(lastSeq, ordinal),
                          'body_active': 1,
                          'body_access': _tick,
                          'last_message_timestamp':
                              isNewest ? timestamp : previousTime,
                          'last_group_message_seq':
                              isNewest ? groupSeq : previousSeq,
                        },
                        where: 'bucket=?',
                        whereArgs: [bucket]);
                  }
                }
                final state = await _loadState(tx, bucket);
                _checkLease(scope);
                return HistoryWindowDeferredReceipt(
                    inserted: inserted, state: state);
              }),
          write: true);
  }

  Future<HistoryWindowDeferredState> _loadState(
      DatabaseExecutor db, String bucket) async {
    final rows = await db
        .query('hw_deferred_state', where: 'bucket=?', whereArgs: [bucket]);
    return rows.isEmpty
        ? const HistoryWindowDeferredState()
        : _state(rows.first);
  }

  HistoryWindowDeferredState _state(Map<String, Object?> row) =>
      HistoryWindowDeferredState(
        acknowledgedThroughSequence: _int(row['acknowledged_sequence']),
        receivedCount: _int(row['received']),
        unreadCount: _int(row['unread']),
        firstIngressSequence: row['first_seq'] as int?,
        lastIngressSequence: row['last_seq'] as int?,
        firstMessageID: row['first_id'] as String?,
        lastMessageID: row['last_id'] as String?,
        lastMessageTimestamp: _int(row['last_message_timestamp']),
        lastGroupMessageSeq: _int(row['last_group_message_seq']),
      );

  @override
  Future<bool> areDeferredMessagesAuthoritativelyDeleted({
    required HistoryWindowScope scope,
    required int throughIngressSequence,
  }) =>
      _run((db) async {
        await _checkScope(db, scope);
        // Only the exceptional missing-boundary return path runs this indexed
        // existence query. It does not materialize old messages or scan per frame.
        final surviving = await db.rawQuery("""SELECT 1 FROM hw_deferred d
      WHERE d.bucket=? AND d.acknowledged=0 AND d.ingress_sequence<=? AND NOT EXISTS (
        SELECT 1 FROM hw_mutations m WHERE m.owner=?
        AND (m.conversation=? OR m.conversation='*')
        AND m.msg_id=d.msg_id AND m.kind='delete' AND m.active=1) LIMIT 1""", [
          _deferredKey(scope),
          throughIngressSequence,
          scope.ownerUserID,
          scope.conversationID
        ]);
        _checkLease(scope);
        return surviving.isEmpty;
      });

  @override
  Future<HistoryWindowDeferredState> deferredState(HistoryWindowScope scope) =>
      _run((db) async {
        await _checkScope(db, scope);
        final bucket = _deferredKey(scope);
        final rows = await db
            .query('hw_deferred_state', where: 'bucket=?', whereArgs: [bucket]);
        final newest =
            rows.isEmpty ? null : await _newestDeferredBoundary(db, bucket);
        // Deletion may have retired the newest message since the last arrival.
        // Recompute only this small content boundary for a latest-window read;
        // pending optimistic deletes do not qualify as confirmed authority.
        final state = rows.isEmpty
            ? const HistoryWindowDeferredState()
            : _state({
                ...rows.first,
                'last_id': newest?['msg_id'],
                'last_message_timestamp': newest?['message_timestamp'] ?? 0,
                'last_group_message_seq': newest?['group_message_seq'] ?? 0,
              });
        _checkLease(scope);
        return state;
      });

  @override
  Future<Set<String>> readDeferredMessageIDs(
          {required HistoryWindowScope scope, int limit = 120}) =>
      _run((db) async {
        await _checkScope(db, scope);
        final rows = await db.query('hw_deferred',
            columns: ['msg_id'],
            where: 'bucket=? AND acknowledged=0',
            whereArgs: [_deferredKey(scope)],
            orderBy: 'ingress_sequence DESC',
            limit: limit.clamp(1, maxDeferredTail));
        _checkLease(scope);
        return rows.map((row) => row['msg_id'] as String).toSet();
      });

  @override
  Future<List<V2TimMessage>> readDeferredTail(
          {required HistoryWindowScope scope, int limit = 120}) =>
      _run((db) async {
        await _checkScope(db, scope);
        final rows = await db.query('hw_deferred',
            columns: ['payload'],
            where: 'bucket=? AND payload IS NOT NULL',
            whereArgs: [_deferredKey(scope)],
            orderBy: 'ingress_sequence DESC',
            limit: limit.clamp(1, maxDeferredTail));
        final result = await _apply(db, scope,
            rows.map((r) => _decodeMessage(r['payload'] as String)).toList());
        _checkLease(scope);
        return result;
      });

  @override
  Future<void> acknowledgeDeferred(
          {required HistoryWindowScope scope,
          required int throughIngressSequence}) =>
      _run(
          (db) => db.transaction((tx) async {
                await _checkScope(tx, scope);
                final bucket = _deferredKey(scope);
                final acknowledgedSource = (await tx.rawQuery(
                        'SELECT MAX(source_sequence) AS source_sequence FROM hw_deferred WHERE bucket=? AND ingress_sequence<=?',
                        [bucket, throughIngressSequence]))
                    .first['source_sequence'] as int?;
                // Formal ingress has its durable source watermark. SDK-only
                // deliveries retain the existing identity row after ACK so a
                // callback replay cannot increment the unread scalar again.
                // These metadata facts leave only on clear/explicit owner purge.
                await tx.update(
                    'hw_deferred', {'acknowledged': 1, 'payload': null},
                    where:
                        'bucket=? AND acknowledged=0 AND source_sequence<0 AND ingress_sequence<=?',
                    whereArgs: [bucket, throughIngressSequence]);
                await tx.delete('hw_deferred',
                    where:
                        'bucket=? AND source_sequence>=0 AND ingress_sequence<=?',
                    whereArgs: [bucket, throughIngressSequence]);
                final aggregate = (await tx.rawQuery(
                        'SELECT COUNT(*) AS received, COALESCE(SUM(unread),0) AS unread FROM hw_deferred WHERE bucket=? AND acknowledged=0',
                        [bucket]))
                    .first;
                final first = await tx.query('hw_deferred',
                    columns: ['msg_id', 'ingress_sequence'],
                    where: 'bucket=? AND acknowledged=0',
                    whereArgs: [bucket],
                    orderBy: 'ingress_sequence ASC',
                    limit: 1);
                final last = await tx.query('hw_deferred',
                    columns: ['msg_id', 'ingress_sequence'],
                    where: 'bucket=? AND acknowledged=0',
                    whereArgs: [bucket],
                    orderBy: 'ingress_sequence DESC',
                    limit: 1);
                final newest = await _newestDeferredBoundary(tx, bucket);
                final existingState = await tx.query('hw_deferred_state',
                    where: 'bucket=?', whereArgs: [bucket]);
                final acknowledgedSeq = throughIngressSequence;
                final acknowledgedSourceSeq = acknowledgedSource ?? -1;
                final stateValues = <String, Object?>{
                  'received': aggregate['received'],
                  'unread': aggregate['unread'],
                  'first_seq': first.firstOrNull?['ingress_sequence'],
                  'last_seq': last.firstOrNull?['ingress_sequence'],
                  'first_id': first.firstOrNull?['msg_id'],
                  'last_id': newest?['msg_id'],
                  'last_message_timestamp':
                      newest?['message_timestamp'] ?? 0,
                  'last_group_message_seq':
                      newest?['group_message_seq'] ?? 0,
                  'acknowledged_sequence': existingState.isEmpty
                      ? acknowledgedSeq
                      : math.max(
                          _int(existingState.first['acknowledged_sequence']),
                          acknowledgedSeq),
                  'acknowledged_source_sequence': existingState.isEmpty
                      ? acknowledgedSourceSeq
                      : math.max(
                          _int(existingState
                              .first['acknowledged_source_sequence']),
                          acknowledgedSourceSeq),
                };
                if (existingState.isEmpty) {
                  await tx.insert('hw_deferred_state', {
                    'bucket': bucket,
                    ...stateValues,
                  });
                } else {
                  await tx.update('hw_deferred_state', stateValues,
                      where: 'bucket=?', whereArgs: [bucket]);
                }
                _checkLease(scope);
              }),
          write: true);

  @override
  Future<HistoryWindowVisibleReceipt> acknowledgeVisibleDeferred({
    required HistoryWindowScope scope,
    required List<String> messageIDs,
    required int afterIngressSequence,
    bool Function()? isCurrent,
  }) =>
      _run(
          (db) => db.transaction((tx) async {
                await _checkScope(tx, scope);
                void checkCurrent() {
                  _checkLease(scope);
                  if (isCurrent?.call() == false) {
                    throw const HistoryWindowStaleScope();
                  }
                }

                checkCurrent();
                final bucket = _deferredKey(scope);
                final ids = messageIDs
                    .map((id) => id.trim())
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .toList(growable: false);
                final before = await _loadState(tx, bucket);
                if (ids.isEmpty) {
                  return HistoryWindowVisibleReceipt(
                      acknowledgedMessageIDs: const {}, state: before);
                }
                final matched = <Map<String, Object?>>[];
                for (var offset = 0; offset < ids.length; offset += maxDeferredTail) {
                  final batch = ids.sublist(
                      offset, math.min(ids.length, offset + maxDeferredTail));
                  final where = 'bucket=? AND acknowledged=0 AND '
                      'ingress_sequence>? AND msg_id IN '
                      '(${List.filled(batch.length, '?').join(',')})';
                  final args = <Object?>[bucket, afterIngressSequence, ...batch];
                  matched.addAll(await tx.query('hw_deferred',
                      columns: ['msg_id', 'unread'],
                      where: where,
                      whereArgs: args));
                  // Keep identities even for formal arrivals: an individually
                  // read row cannot advance the source fence past unseen rows.
                  await tx.update(
                      'hw_deferred', {'acknowledged': 1, 'payload': null},
                      where: where, whereArgs: args);
                }
                if (matched.isEmpty) {
                  checkCurrent();
                  return HistoryWindowVisibleReceipt(
                      acknowledgedMessageIDs: const {}, state: before);
                }
                final first = await tx.query('hw_deferred',
                    columns: ['msg_id', 'ingress_sequence'],
                    where: 'bucket=? AND acknowledged=0',
                    whereArgs: [bucket],
                    orderBy: 'ingress_sequence ASC',
                    limit: 1);
                final last = await tx.query('hw_deferred',
                    columns: ['ingress_sequence'],
                    where: 'bucket=? AND acknowledged=0',
                    whereArgs: [bucket],
                    orderBy: 'ingress_sequence DESC',
                    limit: 1);
                final newest = await _newestDeferredBoundary(tx, bucket);
                await tx.update(
                    'hw_deferred_state',
                    {
                      'received': math.max(0, before.receivedCount - matched.length),
                      'unread': math.max(
                          0,
                          before.unreadCount -
                              matched.fold<int>(
                                  0, (sum, row) => sum + _int(row['unread']))),
                      'first_seq': first.firstOrNull?['ingress_sequence'],
                      'last_seq': last.firstOrNull?['ingress_sequence'],
                      'first_id': first.firstOrNull?['msg_id'],
                      'last_id': newest?['msg_id'],
                      'last_message_timestamp': newest?['message_timestamp'] ?? 0,
                      'last_group_message_seq': newest?['group_message_seq'] ?? 0,
                    },
                    where: 'bucket=?',
                    whereArgs: [bucket]);
                final state = await _loadState(tx, bucket);
                checkCurrent();
                return HistoryWindowVisibleReceipt(
                    acknowledgedMessageIDs: matched
                        .map((row) => row['msg_id'] as String)
                        .toSet(),
                    state: state);
              }),
          write: true);

  @override
  Future<int> persistedClearEpoch(
          {required String ownerUserID, required String conversationID}) =>
      _run((db) async {
        final rows = await db.query('hw_clear_epochs',
            columns: ['epoch'],
            where: 'owner=? AND conversation=?',
            whereArgs: [ownerUserID, conversationID],
            limit: 1);
        return rows.isEmpty ? 0 : _int(rows.first['epoch']);
      });

  @override
  Future<void> clearConversation(
          {required String ownerUserID,
          required String conversationID,
          required int clearEpoch}) =>
      _run(
          (db) => db.transaction((tx) async {
                final existingEpoch = await tx.query('hw_clear_epochs',
                    columns: ['epoch'],
                    where: 'owner=? AND conversation=?',
                    whereArgs: [ownerUserID, conversationID],
                    limit: 1);
                if (existingEpoch.isEmpty) {
                  await tx.insert('hw_clear_epochs', {
                    'owner': ownerUserID,
                    'conversation': conversationID,
                    'epoch': clearEpoch,
                  });
                } else {
                  await tx.update(
                      'hw_clear_epochs',
                      {
                        'epoch': math.max(
                            _int(existingEpoch.first['epoch']), clearEpoch),
                      },
                      where: 'owner=? AND conversation=?',
                      whereArgs: [ownerUserID, conversationID]);
                }
                final cleared = [ownerUserID, conversationID, clearEpoch];
                await tx.delete('hw_mutation_pending',
                    where: 'owner=? AND conversation=? AND clear_epoch<?',
                    whereArgs: cleared);
                await tx.delete('hw_mutation_terminal',
                    where: 'owner=? AND conversation=? AND clear_epoch<?',
                    whereArgs: cleared);
                await tx.delete('hw_mutation_versions',
                    where:
                        'owner=? AND conversation=? AND clear_epoch<? AND is_command=1',
                    whereArgs: cleared);
                final sessions = await tx.query('hw_sessions',
                    columns: ['scope'],
                    where: 'owner=? AND conversation=? AND clear_epoch<?',
                    whereArgs: [ownerUserID, conversationID, clearEpoch]);
                for (final row in sessions) {
                  await _deleteSessionPages(tx, row['scope'] as String);
                  await tx.delete('hw_sessions',
                      where: 'scope=?', whereArgs: [row['scope']]);
                }
                final buckets =
                    await tx.query('hw_deferred_state', columns: ['bucket']);
                for (final row in buckets) {
                  final key = jsonDecode(row['bucket'] as String) as List;
                  if (key[0] == ownerUserID &&
                      key[1] == conversationID &&
                      (key[2] as int) < clearEpoch) {
                    await tx.delete('hw_deferred',
                        where: 'bucket=?', whereArgs: [row['bucket']]);
                    await tx.delete('hw_deferred_state',
                        where: 'bucket=?', whereArgs: [row['bucket']]);
                  }
                }
                // Confirmed authority survives clear: fetched remote history must not
                // resurrect a confirmed revoke/delete. Unfinished command tokens
                // were atomically retired above with the old clear epoch.
              }),
          write: true);

  /// Explicit account-data purge only. Ordinary route/account switching keeps
  /// authority facts; JSON bucket keys are decoded and compared exactly.
  Future<void> clearForOwner(String ownerUserID) => _run(
      (db) => db.transaction((tx) async {
            if (ownerUserID.isEmpty) return;
            final sessions = await tx.query('hw_sessions',
                columns: ['scope'], where: 'owner=?', whereArgs: [ownerUserID]);
            for (final row in sessions) {
              await _deleteSessionPages(tx, row['scope'] as String);
            }
            await tx.delete('hw_sessions',
                where: 'owner=?', whereArgs: [ownerUserID]);
            await tx.delete('hw_mutations',
                where: 'owner=?', whereArgs: [ownerUserID]);
            await tx.delete('hw_mutation_versions',
                where: 'owner=?', whereArgs: [ownerUserID]);
            await tx.delete('hw_mutation_pending',
                where: 'owner=?', whereArgs: [ownerUserID]);
            await tx.delete('hw_mutation_terminal',
                where: 'owner=?', whereArgs: [ownerUserID]);
            await tx.delete('hw_clear_epochs',
                where: 'owner=?', whereArgs: [ownerUserID]);
            final buckets =
                await tx.query('hw_deferred_state', columns: ['bucket']);
            for (final row in buckets) {
              final key = jsonDecode(row['bucket'] as String) as List;
              if (key.first == ownerUserID) {
                await tx.delete('hw_deferred',
                    where: 'bucket=?', whereArgs: [row['bucket']]);
                await tx.delete('hw_deferred_state',
                    where: 'bucket=?', whereArgs: [row['bucket']]);
              }
            }
          }),
      write: true);

  @override
  Future<void> closeSession(HistoryWindowScope scope) => _run(
      (db) => db.transaction((tx) async {
            await _deleteSessionPages(tx, _scopeKey(scope));
            final existing = await tx.query('hw_sessions',
                columns: ['scope'],
                where: 'scope=?',
                whereArgs: [_scopeKey(scope)]);
            if (existing.isEmpty) {
              if (scope.isCurrent?.call() == false) return;
              try {
                await _touchSession(tx, scope);
              } on HistoryWindowStaleScope {
                return;
              }
            }
            await tx.update('hw_sessions', {'closed': 1},
                where: 'scope=?', whereArgs: [_scopeKey(scope)]);
            await _evict(tx);
          }),
      write: true);

  /// Account logout/background close invalidates queued work and waits for the
  /// currently executing transaction before closing the native connection.
  Future<void> closeIfOpen() async {
    _lifecycle++;
    await _serial;
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
  }

  Future<void> clearSession() => closeIfOpen();

  @visibleForTesting
  Future<Map<String, int>> debugStatistics() => _run((db) async {
        final page = (await db.rawQuery(
                'SELECT COUNT(*) AS pages,COALESCE(SUM(row_count),0) AS rows,COALESCE(SUM(byte_count),0) AS bytes FROM hw_pages'))
            .first;
        final result = <String, int>{
          for (final key in ['pages', 'rows', 'bytes']) key: _int(page[key])
        };
        for (final table in [
          'sessions',
          'page_ids',
          'mutations',
          'mutation_pending',
          'mutation_terminal',
          'mutation_versions',
          'deferred'
        ]) {
          result[table] = _int(
              (await db.rawQuery('SELECT COUNT(*) FROM hw_$table'))
                  .first
                  .values
                  .first);
        }
        result['deferred_bodies'] = _int((await db.rawQuery(
                'SELECT COUNT(*) FROM hw_deferred WHERE payload IS NOT NULL'))
            .first
            .values
            .first);
        return result;
      });
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _identity(V2TimMessage message) =>
    (message.msgID?.trim().isNotEmpty ?? false)
        ? message.msgID!.trim()
        : message.id?.trim() ?? '';
// Native toJson omits public-only archive fields (timestamp, groupID, userID)
// and serializes elemList rather than a replaced primary element. Persist those
// public values explicitly so opaque Community pages round-trip without loss.
Map<String, dynamic> _messageJson(V2TimMessage message) {
  final wire = Map<String, dynamic>.from(message.toJson());
  if (!kIsWeb) {
    final primary = switch (message.elemType) {
      1 => message.textElem?.toJson(),
      2 => message.customElem?.toJson(),
      3 => message.imageElem?.toJson(),
      4 => message.soundElem?.toJson(),
      5 => message.videoElem?.toJson(),
      6 => message.fileElem?.toJson(),
      7 => message.locationElem?.toJson(),
      8 => message.faceElem?.toJson(),
      9 => message.groupTipsElem?.toJson(),
      10 => message.mergerElem?.toJson(),
      _ => null,
    };
    if (primary != null) {
      final elements =
          List<Object?>.from(wire['message_elem_array'] as List? ?? []);
      if (elements.isEmpty) {
        elements.add(primary);
      } else {
        elements[0] = primary;
      }
      wire['message_elem_array'] = elements;
    }
  }
  wire['_history_ui'] = {
    'msgID': message.msgID,
    'id': message.id,
    'timestamp': message.timestamp,
    'groupID': message.groupID,
    'userID': message.userID,
    'seq': message.seq,
    'nickName': message.nickName,
    'friendRemark': message.friendRemark,
    'faceUrl': message.faceUrl,
    'nameCard': message.nameCard,
    'progress': message.progress,
    'elemType': message.elemType,
  };
  return wire;
}

V2TimMessage _messageFromJson(Map<String, dynamic> wire) {
  final message = V2TimMessage.fromJson(wire);
  final ui = wire['_history_ui'] as Map?;
  if (ui != null) {
    message.msgID = ui['msgID'] as String?;
    message.id = ui['id'] as String?;
    message.timestamp = ui['timestamp'] as int?;
    message.groupID = ui['groupID'] as String?;
    message.userID = ui['userID'] as String?;
    message.seq = ui['seq'] as String?;
    message.nickName = ui['nickName'] as String?;
    message.friendRemark = ui['friendRemark'] as String?;
    message.faceUrl = ui['faceUrl'] as String?;
    message.nameCard = ui['nameCard'] as String?;
    message.progress = ui['progress'] as int?;
    message.elemType = (ui['elemType'] as int?) ?? message.elemType;
  }
  return message;
}

V2TimMessage _decodeMessage(String raw) =>
    _messageFromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));

// Top-level compute entry points: no store, database, or route closure crosses
// the isolate boundary. Payload and its index IDs come from the same snapshot.
(String, int, List<String>) _encodeHistoryPage(List<V2TimMessage> messages) {
  final payload = jsonEncode(messages.map(_messageJson).toList());
  return (payload, utf8.encode(payload).length,
      messages.map(_identity).toList(growable: false));
}

// Element fromJson (image/sound/video/file) resolves local paths through
// CommonUtils statics, which are empty in a fresh compute isolate. Seed them
// from the main-isolate snapshot before decoding; the sync path passes null.
List<V2TimMessage> _decodeHistoryPage(
    ({String payload, CommonUtilsIsolateSeed? seed}) job) {
  final seed = job.seed;
  if (seed != null) {
    CommonUtils.applyIsolateSeed(seed);
  }
  return (jsonDecode(job.payload) as List)
      .map((wire) => _messageFromJson(Map<String, dynamic>.from(wire as Map)))
      .toList(growable: false);
}
