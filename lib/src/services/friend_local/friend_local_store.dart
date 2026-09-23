import 'package:tencent_cloud_chat_demo/src/services/sqlite_query_diagnostics.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_friend_api.dart';
import 'package:tencent_cloud_chat_demo/src/api/sync_protocol_api.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/search_local/pinyin_index.dart';
import 'package:tencent_cloud_chat_demo/src/services/search_local/search_id_page.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lock_profile_log.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_friend_info.dart';

/// 自托管好友通讯录本地库（按登录账号隔离）。在线状态不由本库提供。
class FriendLocalStore {
  FriendLocalStore._() : _memoryOnly = false;

  @visibleForTesting
  FriendLocalStore.memoryForTest() : _memoryOnly = true;

  final bool _memoryOnly;

  static final FriendLocalStore instance = FriendLocalStore._();

  static const _dbName = 'contacts.db';
  static const _legacyDbName = 'friend_local_v1.db';
  static const _metaTable = 'contacts_store_meta';
  static const _syncJobTable = 'contact_sync_job';
  static const _table = 'friends';
  static const _searchTable = 'friend_search_index';
  static const _ftsTable = 'contact_fts';
  static const int _dbVersion = 7;
  static const int defaultSearchPageSize = 80;

  Database? _db;
  final Map<String, List<MeFriendRecord>> _memoryByOwner = {};
  final Map<String, Set<String>> _memoryProtocolEvents = {};
  final Map<String, Map<String, int>> _memoryTombstoneVersions = {};
  final Map<String, Map<String, Object?>> _memorySyncJobs = {};
  final Map<String, Map<String, Map<String, SyncProtocolItem>>> _memoryStaging =
      {};
  bool _factoryReady = false;
  bool? _ftsAvailable;

  Future<void> _ensureDatabaseFactory() async {
    if (_factoryReady) {
      return;
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryReady = true;
  }

  Future<void> _createFriendsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_table (
        owner_user_id TEXT NOT NULL,
        friend_user_id TEXT NOT NULL,
        friend_nickname TEXT NOT NULL DEFAULT '',
        friend_avatar_url TEXT NOT NULL DEFAULT '',
        friend_avatar_version INTEGER,
        remark TEXT NOT NULL DEFAULT '',
        remark_known INTEGER NOT NULL DEFAULT 1,
        added_at INTEGER NOT NULL DEFAULT 0,
        peer_deleted_me INTEGER NOT NULL DEFAULT 0,
        can_message INTEGER NOT NULL DEFAULT 1,
        in_my_friend_list INTEGER NOT NULL DEFAULT 1,
         is_friend INTEGER NOT NULL DEFAULT 1,
         item_version INTEGER NOT NULL DEFAULT 0,
         updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_user_id, friend_user_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_friends_owner ON $_table(owner_user_id)',
    );
  }

  Future<void> _createSearchIndexTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_searchTable (
        owner_user_id TEXT NOT NULL,
        friend_user_id TEXT NOT NULL,
        haystack TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (owner_user_id, friend_user_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_friend_search_owner_id '
      'ON $_searchTable(owner_user_id, friend_user_id)',
    );
  }

  Future<bool> _tryCreateFts(DatabaseExecutor db) async {
    try {
      await db.execute('DROP TABLE IF EXISTS $_ftsTable');
      await db.execute('''
        CREATE VIRTUAL TABLE $_ftsTable USING fts5(
          owner_user_id UNINDEXED,
          user_id UNINDEXED,
          body,
          tokenize='unicode61'
        )
      ''');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureFtsFlag(Database db) async {
    if (_ftsAvailable != null) {
      return;
    }
    try {
      final rows = await db.diagnosedRawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [_ftsTable],
      );
      if (rows.isEmpty) {
        _ftsAvailable = false;
        return;
      }
      // sqlite_master can retain an FTS table created by another driver while
      // the current Android build has no FTS5 module. Probe MATCH once so all
      // later searches use the LIKE index without emitting noisy exceptions.
      await db.diagnosedRawQuery(
        'SELECT user_id FROM $_ftsTable WHERE $_ftsTable MATCH ? LIMIT 1',
        const ['__fts_probe__'],
      );
      _ftsAvailable = true;
    } catch (_) {
      _ftsAvailable = false;
    }
  }

  Future<Database> _openDb() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) {
      await _ensureFtsFlag(existing);
      return existing;
    }
    await _ensureDatabaseFactory();
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onOpen: (db) async {
        // FFB-2 扩散：iOS sqflite_darwin 启动期 PRAGMA 救火。失败不阻断 DB open。
        await SqfliteBootstrapHelper.withTag('friend').runOnOpenPragmas(db);
        await _createSearchIndexTable(db);
        await _createMetaTable(db);
        await _createProtocolTables(db);
        await _ensureFtsFlag(db);
      },
      onCreate: (db, version) async {
        await _createFriendsTable(db);
        await _createSearchIndexTable(db);
        await _createMetaTable(db);
        await _createProtocolTables(db);
        _ftsAvailable = await _tryCreateFts(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Install before any upgrade that rebuilds rows using the new columns.
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN remark_known INTEGER NOT NULL DEFAULT 1',
          );
          // Old relation-only shells did not record remark provenance.
          await db.execute("UPDATE $_table SET remark_known = 0 "
              "WHERE remark = '' AND friend_nickname = '' "
              "AND friend_avatar_url = ''");
        }
        if (oldVersion < 2) {
          await _createSearchIndexTable(db);
          _ftsAvailable = await _tryCreateFts(db);
          await _rebuildSearchIndexForAllOwners(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN friend_avatar_version INTEGER',
          );
        }
        if (oldVersion < 4) {
          await _createMetaTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN item_version INTEGER NOT NULL DEFAULT 0',
          );
          await _createProtocolTables(db);
        }
        if (oldVersion < 7) {
          // Legacy optimistic/SDK writers could corrupt membership after the
          // saved watermark. Keep the visible cache, but require one full sync.
          await db.delete(_syncJobTable);
          await db.delete('contact_sync_staging');
          await db.delete('contact_sync_event');
        }
      },
    );
    try {
      await _migrateLegacyDbIfNeeded(_db!, basePath);
    } catch (_) {
      // Keep the new contacts database usable; retry on a later open.
    }
    return _db!;
  }

  Future<void> _createMetaTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_metaTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_syncJobTable (
        owner_user_id TEXT NOT NULL,
        domain TEXT NOT NULL,
        scope_id TEXT NOT NULL DEFAULT '',
        account_generation INTEGER NOT NULL DEFAULT 0,
        snapshot_revision TEXT NOT NULL DEFAULT '',
        next_cursor TEXT NOT NULL DEFAULT '',
        has_more INTEGER NOT NULL DEFAULT 1,
        persisted_count INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'idle',
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(owner_user_id, domain, scope_id)
      )
    ''');
  }

  Future<void> _createProtocolTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contact_sync_staging (
        owner_user_id TEXT NOT NULL,
        snapshot_revision TEXT NOT NULL,
        item_id TEXT NOT NULL,
        item_version INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        data_json TEXT NOT NULL DEFAULT '{}',
        PRIMARY KEY(owner_user_id, snapshot_revision, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contact_tombstone (
        owner_user_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        item_version INTEGER NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contact_sync_event (
        owner_user_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        item_version INTEGER NOT NULL,
        applied_at INTEGER NOT NULL,
        PRIMARY KEY(owner_user_id, event_id)
      )
    ''');
  }

  Future<void> _migrateLegacyDbIfNeeded(
    Database target,
    String basePath,
  ) async {
    final marker = await target.diagnosedQuery(
      _metaTable,
      where: 'key = ?',
      whereArgs: const <Object?>['legacy_migration_v1'],
      limit: 1,
    );
    if (marker.isNotEmpty) return;
    final legacyPath = p.join(basePath, _legacyDbName);
    if (!await databaseFactory.databaseExists(legacyPath)) return;
    final legacy = await openDatabase(
      legacyPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final tables = await legacy.diagnosedRawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final available =
          tables.map((row) => row['name']?.toString() ?? '').toSet();
      for (final table in <String>[_table, _searchTable]) {
        if (!available.contains(table)) continue;
        await _copyLegacyTable(legacy, target, table);
      }
      await target.insert(
        _metaTable,
        const <String, Object?>{
          'key': 'legacy_migration_v1',
          'value': 'complete',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } finally {
      await SqfliteLifecycleGuard.closeDatabase(legacy);
    }
  }

  Future<void> _copyLegacyTable(
    Database source,
    Database target,
    String table,
  ) async {
    final sourceInfo =
        await source.diagnosedRawQuery('PRAGMA table_info($table)');
    final targetInfo =
        await target.diagnosedRawQuery('PRAGMA table_info($table)');
    final targetColumns = targetInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final columns = sourceInfo
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty && targetColumns.contains(name))
        .toList(growable: false);
    if (columns.isEmpty) return;
    final inferRemarkKnown =
        table == _table && !columns.contains('remark_known');
    final insertColumns = [...columns, if (inferRemarkKnown) 'remark_known'];
    final names = insertColumns.map(_quoteIdentifier).join(', ');
    final placeholders =
        List<String>.filled(insertColumns.length, '?').join(', ');
    var offset = 0;
    while (true) {
      final rows = await source.diagnosedQuery(
        table,
        columns: columns,
        limit: 500,
        offset: offset,
      );
      if (rows.isEmpty) break;
      await target.transaction<void>((txn) async {
        for (final row in rows) {
          await txn.rawInsert(
            'INSERT OR IGNORE INTO ${_quoteIdentifier(table)} ($names) '
            'VALUES ($placeholders)',
            <Object?>[
              ...columns.map((column) => row[column]),
              if (inferRemarkKnown) _recordFromRow(row).remarkKnown ? 1 : 0,
            ],
          );
        }
      });
      offset += rows.length;
      if (rows.length < 500) break;
    }
  }

  static String _quoteIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  Future<void> closeIfOpen() async {
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
  }

  Future<void> _rebuildSearchIndexForAllOwners(DatabaseExecutor db) async {
    final owners = await db.diagnosedRawQuery(
      'SELECT DISTINCT owner_user_id FROM $_table',
    );
    for (final row in owners) {
      final owner = row['owner_user_id']?.toString() ?? '';
      if (owner.isEmpty) {
        continue;
      }
      await _rebuildSearchIndexForOwner(db, owner);
    }
  }

  Future<void> _rebuildSearchIndexForOwner(
    DatabaseExecutor db,
    String owner,
  ) async {
    await db.delete(
      _searchTable,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    if (_ftsAvailable == true) {
      try {
        await db.delete(
          _ftsTable,
          where: 'owner_user_id = ?',
          whereArgs: [owner],
        );
      } catch (_) {}
    }
    final rows = await db.diagnosedQuery(
      _table,
      columns: const [
        'owner_user_id',
        'friend_user_id',
        'friend_nickname',
        'friend_avatar_url',
        'friend_avatar_version',
        'remark',
        'remark_known',
        'added_at',
        'peer_deleted_me',
        'can_message',
        'in_my_friend_list',
        'is_friend',
        'item_version',
        'updated_at',
      ],
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    final batch = db.batch();
    for (final row in rows) {
      final record = _recordFromRow(row);
      _enqueueSearchUpsert(batch, owner, record);
    }
    await batch.commit(noResult: true);
  }

  void _enqueueSearchUpsert(
    Batch batch,
    String owner,
    MeFriendRecord record,
  ) {
    final id = record.friendUserId.trim();
    if (id.isEmpty) {
      return;
    }
    final haystack = PinyinIndex.friendHaystack(
      userId: id,
      nickname: record.friendNickname,
      remark: record.remark,
    );
    batch.insert(
      _searchTable,
      <String, Object?>{
        'owner_user_id': owner,
        'friend_user_id': id,
        'haystack': haystack,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (_ftsAvailable == true) {
      batch.insert(_ftsTable, <String, Object?>{
        'owner_user_id': owner,
        'user_id': id,
        'body': haystack,
      });
    }
  }

  Future<void> _upsertSearchRow(
    DatabaseExecutor db,
    String owner,
    MeFriendRecord record,
  ) async {
    final id = record.friendUserId.trim();
    if (id.isEmpty) {
      return;
    }
    final haystack = PinyinIndex.friendHaystack(
      userId: id,
      nickname: record.friendNickname,
      remark: record.remark,
    );
    await db.insert(
      _searchTable,
      <String, Object?>{
        'owner_user_id': owner,
        'friend_user_id': id,
        'haystack': haystack,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (_ftsAvailable == true) {
      try {
        await db.delete(
          _ftsTable,
          where: 'owner_user_id = ? AND user_id = ?',
          whereArgs: [owner, id],
        );
        await db.insert(_ftsTable, <String, Object?>{
          'owner_user_id': owner,
          'user_id': id,
          'body': haystack,
        });
      } catch (_) {
        _ftsAvailable = false;
      }
    }
  }

  Future<void> _deleteSearchRow(
    DatabaseExecutor db,
    String owner,
    String friendUserId,
  ) async {
    await db.delete(
      _searchTable,
      where: 'owner_user_id = ? AND friend_user_id = ?',
      whereArgs: [owner, friendUserId],
    );
    if (_ftsAvailable == true) {
      try {
        await db.delete(
          _ftsTable,
          where: 'owner_user_id = ? AND user_id = ?',
          whereArgs: [owner, friendUserId],
        );
      } catch (_) {}
    }
  }

  String currentOwnerUserId() {
    return ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
  }

  String _resolveOwner(String? ownerUserId) {
    final explicit = ChatIdFormat.rawUserUid(ownerUserId);
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return currentOwnerUserId();
  }

  bool get _useMemoryOnly => kIsWeb || _memoryOnly;

  /// 测试可见：当前进程是否启用了 FTS5。
  @visibleForTesting
  bool? get debugFtsAvailable => _ftsAvailable;

  Future<List<MeFriendRecord>> readAll({String? ownerUserId}) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return const [];
    }
    if (_useMemoryOnly) {
      return List.unmodifiable(_memoryByOwner[owner] ?? const []);
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _table,
      columns: const [
        'owner_user_id',
        'friend_user_id',
        'friend_nickname',
        'friend_avatar_url',
        'friend_avatar_version',
        'remark',
        'remark_known',
        'added_at',
        'peer_deleted_me',
        'can_message',
        'in_my_friend_list',
        'is_friend',
        'item_version',
        'updated_at',
      ],
      where: 'owner_user_id = ?',
      whereArgs: [owner],
      orderBy: 'friend_user_id ASC',
    );
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<List<MeFriendRecord>> readByIds({
    required List<String> friendUserIds,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final ids = friendUserIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (owner.isEmpty || ids.isEmpty) {
      return const [];
    }
    if (_useMemoryOnly) {
      final map = <String, MeFriendRecord>{
        for (final item in _memoryByOwner[owner] ?? const <MeFriendRecord>[])
          item.friendUserId: item,
      };
      return [
        for (final id in ids)
          if (map[id] != null) map[id]!,
      ];
    }
    final db = await _openDb();
    final out = <MeFriendRecord>[];
    const chunk = 200;
    for (var i = 0; i < ids.length; i += chunk) {
      final slice =
          ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
      final placeholders = List.filled(slice.length, '?').join(',');
      final rows = await db.diagnosedRawQuery(
        'SELECT owner_user_id, friend_user_id, friend_nickname, '
        'friend_avatar_url, friend_avatar_version, remark, remark_known, added_at, '
        'peer_deleted_me, can_message, in_my_friend_list, is_friend, '
        'item_version, updated_at FROM $_table WHERE owner_user_id = ? '
        'AND friend_user_id COLLATE NOCASE IN ($placeholders)',
        <Object?>[owner, ...slice],
      );
      final byId = <String, MeFriendRecord>{};
      for (final row in rows) {
        final record = _recordFromRow(row);
        byId[record.friendUserId.toLowerCase()] = record;
      }
      for (final id in slice) {
        final hit = byId[id.toLowerCase()];
        if (hit != null) {
          out.add(hit);
        }
      }
    }
    return out;
  }

  Future<List<V2TimFriendInfo>> loadAsV2TimFriends({
    String? ownerUserId,
  }) async {
    final records = await readAll(ownerUserId: ownerUserId);
    return records.map((e) => e.toV2TimFriendInfo()).toList(growable: false);
  }

  Future<List<V2TimFriendInfo>> loadAsV2TimFriendsByIds({
    required List<String> friendUserIds,
    String? ownerUserId,
  }) async {
    final records = await readByIds(
      friendUserIds: friendUserIds,
      ownerUserId: ownerUserId,
    );
    return records.map((e) => e.toV2TimFriendInfo()).toList(growable: false);
  }

  /// 本地好友关键字搜索：返回 ID 页（cursor = 上一页最后 friend_user_id）。
  Future<SearchIdPage> searchFriendIds({
    required String keyword,
    String? ownerUserId,
    int limit = defaultSearchPageSize,
    String? cursor,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final needles = ChatIdFormat.searchKeywordNeedles(keyword);
    final pageSize = limit <= 0 ? defaultSearchPageSize : limit;
    if (owner.isEmpty || needles.isEmpty) {
      return SearchIdPage.empty;
    }

    if (_useMemoryOnly) {
      return _searchFriendIdsInMemory(
        owner: owner,
        needles: needles,
        pageSize: pageSize,
        cursor: cursor,
      );
    }

    final db = await _openDb();
    await _ensureFtsFlag(db);

    List<Map<String, Object?>> rows;
    if (_ftsAvailable == true && needles.every(_isAsciiKeyword)) {
      rows = await _searchFriendIdsViaFts(
        db: db,
        owner: owner,
        needles: needles,
        pageSize: pageSize + 1,
        cursor: cursor,
      );
    } else {
      rows = await _searchFriendIdsViaLike(
        db: db,
        owner: owner,
        needles: needles,
        pageSize: pageSize + 1,
        cursor: cursor,
      );
    }

    final ids = <String>[];
    for (final row in rows) {
      final id =
          row['friend_user_id']?.toString() ?? row['user_id']?.toString() ?? '';
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    final hasMore = ids.length > pageSize;
    final pageIds = hasMore ? ids.sublist(0, pageSize) : List<String>.from(ids);
    return SearchIdPage(
      ids: pageIds,
      nextCursor: pageIds.isEmpty ? null : pageIds.last,
      hasMore: hasMore,
    );
  }

  bool _isAsciiKeyword(String needle) {
    return RegExp(r'^[a-z0-9_@.\-]+$').hasMatch(needle);
  }

  String _ftsMatchQuery(String needle) {
    final escaped = needle.replaceAll('"', '""');
    return '"$escaped"*';
  }

  Future<List<Map<String, Object?>>> _searchFriendIdsViaLike({
    required Database db,
    required String owner,
    required List<String> needles,
    required int pageSize,
    String? cursor,
  }) async {
    final likeClauses = <String>[];
    final args = <Object?>[owner];
    for (final needle in needles) {
      likeClauses.add('haystack LIKE ?');
      args.add('%$needle%');
    }
    final cursorClause = (cursor != null && cursor.trim().isNotEmpty)
        ? ' AND friend_user_id > ?'
        : '';
    if (cursorClause.isNotEmpty) {
      args.add(cursor!.trim());
    }
    args.add(pageSize);
    return db.diagnosedRawQuery(
      'SELECT friend_user_id FROM $_searchTable '
      'WHERE owner_user_id = ? AND (${likeClauses.join(' OR ')})$cursorClause '
      'ORDER BY friend_user_id ASC LIMIT ?',
      args,
    );
  }

  Future<List<Map<String, Object?>>> _searchFriendIdsViaFts({
    required Database db,
    required String owner,
    required List<String> needles,
    required int pageSize,
    String? cursor,
  }) async {
    try {
      if (needles.isEmpty) {
        return const [];
      }
      final unions = <String>[];
      final args = <Object?>[];
      for (final needle in needles) {
        unions.add(
          'SELECT user_id FROM $_ftsTable '
          'WHERE owner_user_id = ? AND $_ftsTable MATCH ?',
        );
        args.add(owner);
        args.add(_ftsMatchQuery(needle));
      }
      final cursorClause = (cursor != null && cursor.trim().isNotEmpty)
          ? ' WHERE user_id > ?'
          : '';
      if (cursorClause.isNotEmpty) {
        args.add(cursor!.trim());
      }
      args.add(pageSize);
      return await db.diagnosedRawQuery(
        'SELECT user_id FROM (${unions.join(' UNION ')}) AS hits'
        '$cursorClause ORDER BY user_id ASC LIMIT ?',
        args,
      );
    } catch (_) {
      _ftsAvailable = false;
      return _searchFriendIdsViaLike(
        db: db,
        owner: owner,
        needles: needles,
        pageSize: pageSize,
        cursor: cursor,
      );
    }
  }

  SearchIdPage _searchFriendIdsInMemory({
    required String owner,
    required List<String> needles,
    required int pageSize,
    String? cursor,
  }) {
    final all = _memoryByOwner[owner] ?? const <MeFriendRecord>[];
    final matched = <String>[];
    for (final item in all) {
      final id = item.friendUserId.trim();
      if (id.isEmpty) {
        continue;
      }
      if (cursor != null &&
          cursor.trim().isNotEmpty &&
          id.compareTo(cursor.trim()) <= 0) {
        continue;
      }
      final haystack = PinyinIndex.friendHaystack(
        userId: id,
        nickname: item.friendNickname,
        remark: item.remark,
      );
      if (!needles.any(haystack.contains)) {
        continue;
      }
      matched.add(id);
    }
    matched.sort();
    final hasMore = matched.length > pageSize;
    final pageIds =
        hasMore ? matched.sublist(0, pageSize) : List<String>.from(matched);
    return SearchIdPage(
      ids: pageIds,
      nextCursor: pageIds.isEmpty ? null : pageIds.last,
      hasMore: hasMore,
    );
  }

  Future<void> replaceAll({
    required String ownerUserId,
    required List<MeFriendRecord> records,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final normalized = records
        .where((e) => e.friendUserId.isNotEmpty)
        .map((e) => e.copyWith())
        .toList(growable: false);
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final current = _memoryByOwner[owner] ?? const <MeFriendRecord>[];
      final byId = <String, MeFriendRecord>{
        for (final item in current) item.friendUserId: item
      };
      for (final item in normalized) {
        final tombstoneVersion =
            _memoryTombstoneVersions[owner]?[item.friendUserId] ?? 0;
        if (tombstoneVersion > 0 && item.itemVersion <= tombstoneVersion) {
          byId.remove(item.friendUserId);
          continue;
        }
        final old = byId[item.friendUserId];
        if (old == null ||
            (item.itemVersion > 0 && old.itemVersion == 0) ||
            item.itemVersion > old.itemVersion) {
          byId[item.friendUserId] = item;
        }
      }
      byId.removeWhere((id, item) {
        final tombstoneVersion = _memoryTombstoneVersions[owner]?[id] ?? 0;
        return tombstoneVersion > 0 && item.itemVersion <= tombstoneVersion;
      });
      _memoryByOwner[owner] = byId.values.toList(growable: false);
      return;
    }
    final db = await _openDb();
    // A snapshot may have been captured before a newer realtime/change event
    // was applied. Preserve those higher-version rows instead of allowing the
    // snapshot replace to roll them back.
    final currentRows = await db.diagnosedQuery(
      _table,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    final tombstoneRows = await db.diagnosedQuery(
      'contact_tombstone',
      columns: const ['item_id', 'item_version'],
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    final tombstoneVersionById = <String, int>{
      for (final row in tombstoneRows)
        row['item_id']?.toString() ?? '':
            (row['item_version'] as num?)?.toInt() ?? 0,
    };
    final currentById = <String, MeFriendRecord>{
      for (final row in currentRows)
        if ((row['friend_user_id']?.toString() ?? '').isNotEmpty)
          row['friend_user_id']!.toString(): _recordFromRow(row),
    };
    final versioned = <MeFriendRecord>[];
    final seen = <String>{};
    for (final item in normalized) {
      final id = item.friendUserId.trim();
      final tombstoneVersion = tombstoneVersionById[id] ?? 0;
      if (tombstoneVersion > 0 && item.itemVersion <= tombstoneVersion) {
        continue;
      }
      final current = currentById[id];
      final winner = current != null && current.itemVersion > item.itemVersion
          ? current
          : item;
      versioned.add(winner);
      seen.add(id);
    }
    for (final current in currentById.values) {
      final tombstoneVersion = tombstoneVersionById[current.friendUserId] ?? 0;
      if (!seen.contains(current.friendUserId) &&
          current.itemVersion > 0 &&
          current.itemVersion > tombstoneVersion) {
        versioned.add(current);
      }
    }
    versioned.sort((a, b) => a.friendUserId.compareTo(b.friendUserId));
    final effective = versioned;
    await profiledTransaction<void>(
      db,
      dbTag: _dbName,
      op: 'replaceAll',
      extras: <String, Object?>{'count': effective.length},
      action: (txn) async {
        final batch = txn.batch();
        batch.delete(_table, where: 'owner_user_id = ?', whereArgs: [owner]);
        batch.delete(
          _searchTable,
          where: 'owner_user_id = ?',
          whereArgs: [owner],
        );
        for (final item in effective) {
          batch.insert(_table, _rowFromRecord(owner, item, now));
          _enqueueSearchUpsert(batch, owner, item);
        }
        await batch.commit(noResult: true);
        if (_ftsAvailable == true) {
          try {
            await txn.delete(
              _ftsTable,
              where: 'owner_user_id = ?',
              whereArgs: [owner],
            );
            for (final item in effective) {
              final id = item.friendUserId.trim();
              if (id.isEmpty) {
                continue;
              }
              await txn.insert(_ftsTable, <String, Object?>{
                'owner_user_id': owner,
                'user_id': id,
                'body': PinyinIndex.friendHaystack(
                  userId: id,
                  nickname: item.friendNickname,
                  remark: item.remark,
                ),
              });
            }
          } catch (_) {
            _ftsAvailable = false;
          }
        }
      },
    );
  }

  Future<void> clearProtocolStaging({
    required String ownerUserId,
    String? snapshotRevision,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (_useMemoryOnly) {
      if (snapshotRevision == null) {
        _memoryStaging.remove(owner);
      } else {
        _memoryStaging[owner]?.remove(snapshotRevision);
      }
      return;
    }
    if (owner.isEmpty || _useMemoryOnly) return;
    final db = await _openDb();
    await db.delete(
      'contact_sync_staging',
      where: snapshotRevision == null
          ? 'owner_user_id = ?'
          : 'owner_user_id = ? AND snapshot_revision = ?',
      whereArgs: snapshotRevision == null
          ? <Object?>[owner]
          : <Object?>[owner, snapshotRevision],
    );
  }

  Future<void> clearSyncJob({required String ownerUserId}) async {
    final owner = _resolveOwner(ownerUserId);
    _memorySyncJobs.remove(owner);
    if (owner.isEmpty || _useMemoryOnly) return;
    final db = await _openDb();
    await db.delete(_syncJobTable,
        where: 'owner_user_id = ? AND domain = ? AND scope_id = ?',
        whereArgs: [owner, 'contacts', '']);
  }

  Future<Map<String, Object?>?> readSyncJob({
    required String ownerUserId,
    String domain = 'contacts',
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (_useMemoryOnly) return _memorySyncJobs[owner];
    if (owner.isEmpty || _useMemoryOnly) return null;
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _syncJobTable,
      where: 'owner_user_id = ? AND domain = ? AND scope_id = ?',
      whereArgs: <Object?>[owner, domain, ''],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> saveSyncJob({
    required String ownerUserId,
    required String snapshotRevision,
    required String nextCursor,
    required bool hasMore,
    required int persistedCount,
    required String state,
    int accountGeneration = 0,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (_useMemoryOnly && owner.isNotEmpty) {
      _memorySyncJobs[owner] = {
        'snapshot_revision': snapshotRevision,
        'next_cursor': nextCursor,
        'has_more': hasMore ? 1 : 0,
        'persisted_count': persistedCount,
        'state': state,
      };
      return;
    }
    if (owner.isEmpty || _useMemoryOnly) return;
    final db = await _openDb();
    await db.insert(
      _syncJobTable,
      <String, Object?>{
        'owner_user_id': owner,
        'domain': 'contacts',
        'scope_id': '',
        'account_generation': accountGeneration,
        'snapshot_revision': snapshotRevision,
        'next_cursor': nextCursor,
        'has_more': hasMore ? 1 : 0,
        'persisted_count': persistedCount,
        'state': state,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearProtocolEvents({required String ownerUserId}) async {
    final owner = _resolveOwner(ownerUserId);
    _memoryProtocolEvents.remove(owner);
    if (owner.isEmpty || _useMemoryOnly) return;
    final db = await _openDb();
    await db.delete(
      'contact_sync_event',
      where: 'owner_user_id = ?',
      whereArgs: <Object?>[owner],
    );
  }

  Future<List<String>> readProtocolDeletedIds({
    required String ownerUserId,
    required String snapshotRevision,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty || snapshotRevision.trim().isEmpty || _useMemoryOnly) {
      return const [];
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      'contact_sync_staging',
      columns: const ['item_id', 'item_version', 'updated_at'],
      where: 'owner_user_id = ? AND snapshot_revision = ? AND deleted = 1',
      whereArgs: <Object?>[owner, snapshotRevision.trim()],
    );
    for (final row in rows) {
      await recordProtocolTombstone(
        ownerUserId: owner,
        itemId: row['item_id']?.toString() ?? '',
        itemVersion: (row['item_version'] as num?)?.toInt() ?? 0,
        deletedAt: (row['updated_at'] as num?)?.toInt(),
      );
    }
    return rows
        .map((row) => row['item_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<void> publishProtocolSnapshot({
    required String ownerUserId,
    required String snapshotRevision,
    required List<MeFriendRecord> records,
    int accountGeneration = 0,
    bool replaceAbsent = false,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final revision = snapshotRevision.trim();
    if (owner.isEmpty || revision.isEmpty || _useMemoryOnly) {
      if (_useMemoryOnly &&
          replaceAbsent &&
          owner.isNotEmpty &&
          revision.isNotEmpty) {
        _memoryByOwner[owner] = List<MeFriendRecord>.of(records);
        final tombstones =
            _memoryTombstoneVersions.putIfAbsent(owner, () => {});
        for (final item in _memoryStaging[owner]?[revision]?.values ??
            <SyncProtocolItem>[]) {
          if (item.deleted && item.itemVersion > (tombstones[item.id] ?? -1)) {
            tombstones[item.id] = item.itemVersion;
          }
        }
        for (final record in records) {
          if (record.itemVersion > (tombstones[record.friendUserId] ?? -1)) {
            tombstones.remove(record.friendUserId);
          }
        }
        _memoryStaging[owner]?.remove(revision);
        return;
      }
      await replaceAll(ownerUserId: owner, records: records);
      return;
    }
    final db = await _openDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction<void>((txn) async {
      final deleted = await txn.diagnosedQuery(
        'contact_sync_staging',
        where: 'owner_user_id = ? AND snapshot_revision = ? AND deleted = 1',
        whereArgs: <Object?>[owner, revision],
      );
      final currentRows = await txn.diagnosedQuery(
        _table,
        where: 'owner_user_id = ?',
        whereArgs: [owner],
      );
      final tombstoneRows = await txn.diagnosedQuery(
        'contact_tombstone',
        columns: const ['item_id', 'item_version'],
        where: 'owner_user_id = ?',
        whereArgs: [owner],
      );
      final existingJob = await txn.diagnosedQuery(
        _syncJobTable,
        columns: const ['next_cursor'],
        where: 'owner_user_id = ? AND domain = ? AND scope_id = ?',
        whereArgs: <Object?>[owner, 'contacts', ''],
        limit: 1,
      );
      final snapshotCursor = existingJob.isEmpty
          ? ''
          : existingJob.first['next_cursor']?.toString() ?? '';
      final currentById = <String, MeFriendRecord>{
        for (final row in currentRows)
          if ((row['friend_user_id']?.toString() ?? '').isNotEmpty)
            row['friend_user_id']!.toString(): _recordFromRow(row),
      };
      final tombstoneVersionById = <String, int>{
        for (final row in tombstoneRows)
          row['item_id']?.toString() ?? '':
              (row['item_version'] as num?)?.toInt() ?? 0,
      };
      final effectiveById = <String, MeFriendRecord>{};
      for (final record in records) {
        final id = record.friendUserId.trim();
        if (id.isEmpty) continue;
        final incomingVersion = record.itemVersion;
        final tombstoneVersion = tombstoneVersionById[id] ?? 0;
        if (tombstoneVersion > 0 && incomingVersion <= tombstoneVersion) {
          continue;
        }
        final current = currentById[id];
        effectiveById[id] =
            current != null && current.itemVersion > incomingVersion
                ? current
                : record;
      }
      // Realtime/change writes that won the race before this transaction began
      // must not be rolled back by an older snapshot row.
      for (final current
          in replaceAbsent ? const <MeFriendRecord>[] : currentById.values) {
        final tombstoneVersion =
            tombstoneVersionById[current.friendUserId] ?? 0;
        if (!effectiveById.containsKey(current.friendUserId) &&
            current.itemVersion > 0 &&
            current.itemVersion > tombstoneVersion) {
          effectiveById[current.friendUserId] = current;
        }
      }
      for (final row in deleted) {
        final id = row['item_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final deletedVersion = (row['item_version'] as num?)?.toInt() ?? 0;
        final current = currentById[id];
        if (current != null && current.itemVersion > deletedVersion) {
          effectiveById[id] = current;
        } else {
          effectiveById.remove(id);
        }
      }
      final effective = effectiveById.values.toList(growable: false);
      if (kDebugMode) {
        debugPrint(
          'FriendLocalStore: publish contacts '
          'incoming=${records.length} deleted=${deleted.length} '
          'effective=${effective.length}',
        );
      }
      await txn.delete(_table, where: 'owner_user_id = ?', whereArgs: [owner]);
      await txn
          .delete(_searchTable, where: 'owner_user_id = ?', whereArgs: [owner]);
      if (_ftsAvailable == true) {
        await txn
            .delete(_ftsTable, where: 'owner_user_id = ?', whereArgs: [owner]);
      }
      for (final record in effective) {
        await txn.insert(_table, _rowFromRecord(owner, record, now));
        await _upsertSearchRow(txn, owner, record);
      }
      for (final row in deleted) {
        final id = row['item_id']?.toString() ?? '';
        if (id.isEmpty || effectiveById.containsKey(id)) continue;
        final deletedVersion = (row['item_version'] as num?)?.toInt() ?? 0;
        final existingVersion = tombstoneVersionById[id] ?? 0;
        if (existingVersion > deletedVersion) continue;
        await txn.insert(
          'contact_tombstone',
          <String, Object?>{
            'owner_user_id': owner,
            'item_id': row['item_id'],
            'item_version': row['item_version'],
            'deleted_at': row['updated_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final record in effective) {
        final id = record.friendUserId.trim();
        final tombstoneVersion = tombstoneVersionById[id] ?? 0;
        if (record.itemVersion > tombstoneVersion) {
          await txn.delete(
            'contact_tombstone',
            where: 'owner_user_id = ? AND item_id = ?',
            whereArgs: <Object?>[owner, id],
          );
        }
      }
      await txn.insert(
        _syncJobTable,
        <String, Object?>{
          'owner_user_id': owner,
          'domain': 'contacts',
          'scope_id': '',
          'account_generation': accountGeneration,
          'snapshot_revision': revision,
          'next_cursor': snapshotCursor,
          'has_more': 0,
          'persisted_count': effective.length,
          'state': 'completed',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'contact_sync_staging',
        where: 'owner_user_id = ? AND snapshot_revision = ?',
        whereArgs: <Object?>[owner, revision],
      );
    });
  }

  Future<bool> applyProtocolChange({
    required String ownerUserId,
    required SyncChangeEvent event,
    MeFriendRecord? record,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = event.id.trim();
    if (owner.isEmpty || id.isEmpty) return false;
    if (_useMemoryOnly) {
      final eventId = event.eventId.trim();
      final seen = _memoryProtocolEvents.putIfAbsent(owner, () => <String>{});
      if (eventId.isNotEmpty && !seen.add(eventId)) return false;
      final current = (_memoryByOwner[owner] ?? const <MeFriendRecord>[])
          .where((item) => item.friendUserId == id)
          .cast<MeFriendRecord?>()
          .firstWhere((item) => item != null, orElse: () => null);
      final tombstoneVersion = _memoryTombstoneVersions[owner]?[id] ?? 0;
      final currentVersion = current?.itemVersion ?? 0;
      if (event.itemVersion <= currentVersion ||
          (tombstoneVersion > 0 && event.itemVersion <= tombstoneVersion)) {
        return false;
      }
      if (event.isDelete) {
        final list = List<MeFriendRecord>.from(
          _memoryByOwner[owner] ?? const <MeFriendRecord>[],
        )..removeWhere((item) => item.friendUserId == id);
        _memoryByOwner[owner] = list;
        _memoryTombstoneVersions.putIfAbsent(owner, () => <String, int>{})[id] =
            event.itemVersion;
      } else if (record != null) {
        final overlaid = _overlayProtocolFriendRecord(
          incoming: record.copyWith(itemVersion: event.itemVersion),
          current: current,
          data: event.data,
        );
        await upsert(
          ownerUserId: owner,
          record: overlaid,
          itemVersion: event.itemVersion,
        );
      }
      return true;
    }
    final db = await _openDb();
    return db.transaction<bool>((txn) async {
      final seen = await txn.diagnosedQuery(
        'contact_sync_event',
        columns: const ['event_id'],
        where: 'owner_user_id = ? AND event_id = ?',
        whereArgs: <Object?>[owner, event.eventId],
        limit: 1,
      );
      if (seen.isNotEmpty) return false;
      final tombstone = await txn.diagnosedQuery(
        'contact_tombstone',
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND item_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final current = await txn.diagnosedQuery(
        _table,
        where: 'owner_user_id = ? AND friend_user_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final currentRecord =
          current.isEmpty ? null : _recordFromRow(current.first);
      final currentVersion = <int>[
        if (tombstone.isNotEmpty)
          (tombstone.first['item_version'] as num?)?.toInt() ?? 0,
        currentRecord?.itemVersion ?? 0,
      ].fold<int>(0, (max, value) => value > max ? value : max);
      if (event.itemVersion > currentVersion) {
        if (event.isDelete) {
          await txn.delete(
            _table,
            where: 'owner_user_id = ? AND friend_user_id = ?',
            whereArgs: <Object?>[owner, id],
          );
          await _deleteSearchRow(txn, owner, id);
          await txn.insert(
            'contact_tombstone',
            <String, Object?>{
              'owner_user_id': owner,
              'item_id': id,
              'item_version': event.itemVersion,
              'deleted_at': event.occurredAt,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else if (record != null) {
          final overlaid = _overlayProtocolFriendRecord(
            incoming: record.copyWith(itemVersion: event.itemVersion),
            current: currentRecord,
            data: event.data,
          );
          await txn.insert(
            _table,
            _rowFromRecord(
              owner,
              overlaid,
              event.occurredAt,
              itemVersion: event.itemVersion,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _upsertSearchRow(txn, owner, overlaid);
          await txn.delete(
            'contact_tombstone',
            where: 'owner_user_id = ? AND item_id = ?',
            whereArgs: <Object?>[owner, id],
          );
        }
      }
      await txn.insert(
        'contact_sync_event',
        <String, Object?>{
          'owner_user_id': owner,
          'event_id': event.eventId,
          'item_id': id,
          'item_version': event.itemVersion,
          'applied_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return event.itemVersion > currentVersion;
    });
  }

  Future<void> stageProtocolItems({
    required String ownerUserId,
    required String snapshotRevision,
    required List<SyncProtocolItem> items,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final revision = snapshotRevision.trim();
    if (owner.isEmpty || revision.isEmpty || items.isEmpty || _useMemoryOnly) {
      if (_useMemoryOnly && owner.isNotEmpty && revision.isNotEmpty) {
        final staged = _memoryStaging
            .putIfAbsent(owner, () => {})
            .putIfAbsent(revision, () => {});
        for (final item in items) {
          if (item.id.isNotEmpty &&
              item.itemVersion >= (staged[item.id]?.itemVersion ?? -1)) {
            staged[item.id] = item;
          }
        }
      }
      return;
    }
    final db = await _openDb();
    await db.transaction<void>((txn) async {
      final batch = txn.batch();
      final stagedVersions = <String, int>{};
      for (final item in items) {
        final id = item.id.trim();
        if (id.isEmpty) continue;
        final previous = await txn.diagnosedQuery(
          'contact_sync_staging',
          columns: const ['item_version'],
          where: 'owner_user_id = ? AND snapshot_revision = ? AND item_id = ?',
          whereArgs: <Object?>[owner, revision, id],
          limit: 1,
        );
        final previousVersion = stagedVersions[id] ??
            (previous.isEmpty
                ? -1
                : (previous.first['item_version'] as num?)?.toInt() ?? 0);
        if (previousVersion > item.itemVersion) continue;
        stagedVersions[id] = item.itemVersion;
        batch.insert(
          'contact_sync_staging',
          <String, Object?>{
            'owner_user_id': owner,
            'snapshot_revision': revision,
            'item_id': id,
            'item_version': item.itemVersion,
            'updated_at': item.updatedAt,
            'deleted': item.deleted ? 1 : 0,
            'data_json': jsonEncode(item.data),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<MeFriendRecord>> readProtocolStaging({
    required String ownerUserId,
    required String snapshotRevision,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final revision = snapshotRevision.trim();
    if (owner.isEmpty || revision.isEmpty) return const [];
    if (_useMemoryOnly) {
      return [
        for (final item
            in _memoryStaging[owner]?[revision]?.values ?? <SyncProtocolItem>[])
          if (!item.deleted)
            MeFriendRecord.fromJson({
              ...item.data,
              'friendUserId': item.id,
              'itemVersion': item.itemVersion,
              'updatedAt': item.updatedAt,
            }),
      ];
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      'contact_sync_staging',
      where: 'owner_user_id = ? AND snapshot_revision = ? AND deleted = 0',
      whereArgs: <Object?>[owner, revision],
      orderBy: 'item_id ASC',
    );
    if (kDebugMode) {
      debugPrint(
        'FriendLocalStore: read contact staging rows=${rows.length} '
        'revision=$revision',
      );
    }
    final out = <MeFriendRecord>[];
    for (final row in rows) {
      try {
        final raw = jsonDecode(row['data_json']?.toString() ?? '{}');
        final data =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        // The envelope id is the protocol authority. A flattened payload can
        // contain a null/empty legacy friendUserId; never let it erase the row.
        data['friendUserId'] = row['item_id']?.toString() ?? '';
        data['itemVersion'] = row['item_version'];
        data.putIfAbsent('updatedAt', () => row['updated_at']);
        final record = MeFriendRecord.fromJson(data);
        if (record.friendUserId.isNotEmpty) out.add(record);
      } catch (error) {
        debugPrint(
          'FriendLocalStore: contact staging parse failed '
          'id=${row['item_id']} error=$error',
        );
      }
    }
    return out;
  }

  Future<bool> claimProtocolEvent({
    required String ownerUserId,
    required String eventId,
    required String itemId,
    required int itemVersion,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final event = eventId.trim();
    final id = itemId.trim();
    if (owner.isEmpty || event.isEmpty || id.isEmpty || _useMemoryOnly) {
      return true;
    }
    final db = await _openDb();
    return db.transaction<bool>((txn) async {
      final seen = await txn.diagnosedQuery(
        'contact_sync_event',
        columns: const ['event_id'],
        where: 'owner_user_id = ? AND event_id = ?',
        whereArgs: <Object?>[owner, event],
        limit: 1,
      );
      if (seen.isNotEmpty) return false;
      final tombstone = await txn.diagnosedQuery(
        'contact_tombstone',
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND item_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      if (tombstone.isNotEmpty &&
          ((tombstone.first['item_version'] as num?)?.toInt() ?? 0) >=
              itemVersion) {
        await txn.insert(
            'contact_sync_event',
            <String, Object?>{
              'owner_user_id': owner,
              'event_id': event,
              'item_id': id,
              'item_version': itemVersion,
              'applied_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        return false;
      }
      final current = await txn.diagnosedQuery(
        _table,
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND friend_user_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      if (current.isNotEmpty &&
          ((current.first['item_version'] as num?)?.toInt() ?? 0) >=
              itemVersion) {
        return false;
      }
      await txn.insert(
          'contact_sync_event',
          <String, Object?>{
            'owner_user_id': owner,
            'event_id': event,
            'item_id': id,
            'item_version': itemVersion,
            'applied_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    });
  }

  Future<void> recordProtocolTombstone({
    required String ownerUserId,
    required String itemId,
    required int itemVersion,
    int? deletedAt,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = itemId.trim();
    if (owner.isEmpty || id.isEmpty) return;
    if (_useMemoryOnly) {
      final tombstones =
          _memoryTombstoneVersions.putIfAbsent(owner, () => <String, int>{});
      if (itemVersion >= (tombstones[id] ?? 0)) {
        tombstones[id] = itemVersion;
        final list = List<MeFriendRecord>.from(
          _memoryByOwner[owner] ?? const <MeFriendRecord>[],
        )..removeWhere((item) => item.friendUserId == id);
        _memoryByOwner[owner] = list;
      }
      return;
    }
    final db = await _openDb();
    await db.transaction<void>((txn) async {
      final current = await txn.diagnosedQuery(
        'contact_tombstone',
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND item_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final currentVersion = current.isEmpty
          ? 0
          : (current.first['item_version'] as num?)?.toInt() ?? 0;
      if (itemVersion < currentVersion) return;
      await txn.insert(
        'contact_tombstone',
        <String, Object?>{
          'owner_user_id': owner,
          'item_id': id,
          'item_version': itemVersion,
          'deleted_at': deletedAt ?? DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> upsert({
    required String ownerUserId,
    required MeFriendRecord record,
    int? itemVersion,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = record.friendUserId.trim();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final incomingVersion = itemVersion ?? record.itemVersion;
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final list = List<MeFriendRecord>.from(_memoryByOwner[owner] ?? const []);
      final currentIndex = list.indexWhere((e) => e.friendUserId == id);
      if (currentIndex >= 0) {
        final currentVersion = list[currentIndex].itemVersion;
        if ((incomingVersion == 0 && currentVersion > 0) ||
            (incomingVersion > 0 && currentVersion >= incomingVersion)) {
          return;
        }
      }
      final tombstoneVersion = _memoryTombstoneVersions[owner]?[id] ?? 0;
      if (tombstoneVersion > 0 && incomingVersion <= tombstoneVersion) {
        return;
      }
      list.removeWhere((e) => e.friendUserId == id);
      list.add(record.copyWith(itemVersion: incomingVersion));
      if (incomingVersion > tombstoneVersion) {
        _memoryTombstoneVersions[owner]?.remove(id);
      }
      list.sort((a, b) => a.friendUserId.compareTo(b.friendUserId));
      _memoryByOwner[owner] = list;
      return;
    }
    final db = await _openDb();
    await db.transaction<void>((txn) async {
      final current = await txn.diagnosedQuery(
        _table,
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND friend_user_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final currentVersion = current.isEmpty
          ? 0
          : (current.first['item_version'] as num?)?.toInt() ?? 0;
      final tombstone = await txn.diagnosedQuery(
        'contact_tombstone',
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND item_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final tombstoneVersion = tombstone.isEmpty
          ? 0
          : (tombstone.first['item_version'] as num?)?.toInt() ?? 0;
      if ((incomingVersion == 0 && currentVersion > 0) ||
          (incomingVersion > 0 && currentVersion >= incomingVersion) ||
          (tombstoneVersion > 0 && incomingVersion <= tombstoneVersion)) {
        return;
      }
      if (incomingVersion > tombstoneVersion) {
        await txn.delete(
          'contact_tombstone',
          where: 'owner_user_id = ? AND item_id = ?',
          whereArgs: <Object?>[owner, id],
        );
      }
      await txn.insert(
        _table,
        _rowFromRecord(owner, record, now, itemVersion: incomingVersion),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _upsertSearchRow(txn, owner, record);
    });
  }

  Future<void> delete({
    required String ownerUserId,
    required String friendUserId,
    bool force = false,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = friendUserId.trim();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final list = List<MeFriendRecord>.from(_memoryByOwner[owner] ?? const []);
      if (!force &&
          list.any((item) => item.friendUserId == id && item.itemVersion > 0)) {
        return;
      }
      list.removeWhere((e) => e.friendUserId == id);
      _memoryByOwner[owner] = list;
      return;
    }
    final db = await _openDb();
    if (!force) {
      final current = await db.diagnosedQuery(
        _table,
        columns: const ['item_version'],
        where: 'owner_user_id = ? AND friend_user_id = ?',
        whereArgs: <Object?>[owner, id],
        limit: 1,
      );
      final version = current.isEmpty
          ? 0
          : (current.first['item_version'] as num?)?.toInt() ?? 0;
      if (version > 0) return;
    }
    await db.delete(
      _table,
      where: 'owner_user_id = ? AND friend_user_id = ?',
      whereArgs: [owner, id],
    );
    await _deleteSearchRow(db, owner, id);
  }

  Future<void> patch({
    required String ownerUserId,
    required String friendUserId,
    required MeFriendRecord Function(MeFriendRecord current) transform,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = friendUserId.trim();
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final all = await readAll(ownerUserId: owner);
    final index = all.indexWhere((e) => e.friendUserId == id);
    if (index < 0) {
      return;
    }
    await upsert(ownerUserId: owner, record: transform(all[index]));
  }

  /// Updates the user-owned remark without applying contact sync version
  /// ordering. A local edit is newer user intent and must survive a stale SDK
  /// snapshot that arrives after the edit.
  Future<bool> updateRemark({
    required String ownerUserId,
    required String friendUserId,
    required String remark,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = friendUserId.trim();
    if (owner.isEmpty || id.isEmpty) return false;
    final current = await readByIds(
      friendUserIds: <String>[id],
      ownerUserId: owner,
    );
    if (current.isEmpty) return false;
    final next = current.first.copyWith(remark: remark.trim());
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final list = List<MeFriendRecord>.from(_memoryByOwner[owner] ?? const []);
      final index = list.indexWhere((item) => item.friendUserId == id);
      if (index < 0) return false;
      list[index] = next;
      _memoryByOwner[owner] = list;
      return true;
    }
    final db = await _openDb();
    await db.transaction<void>((txn) async {
      await txn.update(
        _table,
        <String, Object?>{'remark': next.remark, 'remark_known': 1},
        where: 'owner_user_id = ? AND friend_user_id = ?',
        whereArgs: <Object?>[owner, id],
      );
      await _upsertSearchRow(txn, owner, next);
    });
    return true;
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    _memoryByOwner.remove(owner);
    _memorySyncJobs.remove(owner);
    _memoryStaging.remove(owner);
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.delete(_table, where: 'owner_user_id = ?', whereArgs: [owner]);
    await db.delete(
      _searchTable,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    if (_ftsAvailable == true) {
      try {
        await db.delete(
          _ftsTable,
          where: 'owner_user_id = ?',
          whereArgs: [owner],
        );
      } catch (_) {}
    }
  }

  Future<void> clearSession() async {
    // 登出只卸内存；磁盘多账号共存，注销走 clearForOwner。
    _memoryByOwner.clear();
    _memoryProtocolEvents.clear();
    _memoryTombstoneVersions.clear();
    _memorySyncJobs.clear();
    _memoryStaging.clear();
  }

  /// 测试专用：整表清空（生产登出禁止调用）。
  @visibleForTesting
  Future<void> wipeAllDiskForTest() async {
    _memoryByOwner.clear();
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.delete(_table);
    try {
      await db.delete(_searchTable);
    } catch (_) {}
    if (_ftsAvailable == true) {
      try {
        await db.delete(_ftsTable);
      } catch (_) {}
    }
  }

  MeFriendRecord _recordFromRow(Map<String, Object?> row) {
    return MeFriendRecord(
      friendUserId: row['friend_user_id']?.toString() ?? '',
      remark: row['remark']?.toString() ?? '',
      remarkKnown: row['remark_known'] == null
          ? (row['remark']?.toString().trim().isNotEmpty == true ||
              row['friend_nickname']?.toString().trim().isNotEmpty == true ||
              row['friend_avatar_url']?.toString().trim().isNotEmpty == true)
          : row['remark_known'] == 1,
      friendNickname: row['friend_nickname']?.toString() ?? '',
      friendAvatarUrl: row['friend_avatar_url']?.toString() ?? '',
      friendAvatarVersion: row['friend_avatar_version'] as int?,
      itemVersion: (row['item_version'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
      addedAt: (row['added_at'] as int?) ?? 0,
      peerDeletedMe: (row['peer_deleted_me'] as int? ?? 0) != 0,
      canMessage: (row['can_message'] as int? ?? 1) != 0,
      inMyFriendList: (row['in_my_friend_list'] as int? ?? 1) != 0,
      isFriend: (row['is_friend'] as int? ?? 1) != 0,
    );
  }

  Map<String, Object?> _rowFromRecord(
      String owner, MeFriendRecord record, int updatedAt,
      {int? itemVersion}) {
    return <String, Object?>{
      'owner_user_id': owner,
      'friend_user_id': record.friendUserId,
      'friend_nickname': record.friendNickname,
      'friend_avatar_url': record.friendAvatarUrl,
      'friend_avatar_version': record.friendAvatarVersion,
      'remark': record.remark,
      'remark_known': record.remarkKnown ? 1 : 0,
      'added_at': record.addedAt,
      'peer_deleted_me': record.peerDeletedMe ? 1 : 0,
      'can_message': record.canMessage ? 1 : 0,
      'in_my_friend_list': record.inMyFriendList ? 1 : 0,
      'is_friend': record.isFriend ? 1 : 0,
      'item_version': itemVersion ?? record.itemVersion,
      'updated_at': record.updatedAt > 0 ? record.updatedAt : updatedAt,
    };
  }
}

MeFriendRecord _overlayProtocolFriendRecord({
  required MeFriendRecord incoming,
  required MeFriendRecord? current,
  required Map<String, dynamic> data,
}) {
  if (current == null) {
    return incoming;
  }
  final nickname = incoming.friendNickname.trim();
  final avatar = incoming.friendAvatarUrl.trim();
  return current.copyWith(
    friendUserId: incoming.friendUserId,
    remark: incoming.remarkKnown ? incoming.remark : current.remark,
    remarkKnown: incoming.remarkKnown ? true : current.remarkKnown,
    friendNickname:
        nickname.isNotEmpty ? incoming.friendNickname : current.friendNickname,
    friendAvatarUrl:
        avatar.isNotEmpty ? incoming.friendAvatarUrl : current.friendAvatarUrl,
    friendAvatarVersion:
        incoming.friendAvatarVersion ?? current.friendAvatarVersion,
    itemVersion: incoming.itemVersion,
    updatedAt: incoming.updatedAt > 0 ? incoming.updatedAt : current.updatedAt,
    addedAt: _protocolDataHasKey(data, const ['addedAt', 'added_at'])
        ? incoming.addedAt
        : current.addedAt,
    peerDeletedMe:
        _protocolDataHasKey(data, const ['peerDeletedMe', 'peer_deleted_me'])
            ? incoming.peerDeletedMe
            : current.peerDeletedMe,
    canMessage: _protocolDataHasKey(data, const ['canMessage', 'can_message'])
        ? incoming.canMessage
        : current.canMessage,
    inMyFriendList:
        _protocolDataHasKey(data, const ['inMyFriendList', 'in_my_friend_list'])
            ? incoming.inMyFriendList
            : current.inMyFriendList,
    isFriend: _protocolDataHasKey(data, const ['isFriend', 'is_friend'])
        ? incoming.isFriend
        : current.isFriend,
  );
}

bool _protocolDataHasKey(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) {
      return true;
    }
  }
  return false;
}
