import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lock_profile_log.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_group_member_full_info.dart';

enum GroupMemberStoreMutationKind { upsert, delete, snapshot, reset }

@immutable
class GroupMemberStoreCommit {
  const GroupMemberStoreCommit({
    required this.version,
    required this.ownerUserId,
    required this.groupId,
    required this.kind,
    this.upserted = const <GroupMemberRecord>[],
    this.deletedUserIds = const <String>{},
    this.snapshotComplete = false,
    this.snapshotCount = 0,
  });

  final int version;
  final String ownerUserId;
  final String groupId;
  final GroupMemberStoreMutationKind kind;
  final List<GroupMemberRecord> upserted;
  final Set<String> deletedUserIds;
  final bool snapshotComplete;
  final int snapshotCount;
}

/// 群成员分页缓存（按 owner + groupId 隔离）。
class GroupMemberLocalStore {
  GroupMemberLocalStore._();

  static final GroupMemberLocalStore instance = GroupMemberLocalStore._();

  static const _dbName = 'group_member_local_v1.db';
  static const _table = 'group_members';
  static const _cursorTable = 'group_member_incremental_cursor';
  static const _readByIdsChunkSize = 200;

  Database? _db;
  final Map<String, Map<String, List<GroupMemberRecord>>> _memoryByOwner = {};
  final Set<String> _completeSnapshots = <String>{};
  int _commitVersion = 0;
  final ValueNotifier<GroupMemberStoreCommit> commitListenable =
      ValueNotifier<GroupMemberStoreCommit>(
    const GroupMemberStoreCommit(
      version: 0,
      ownerUserId: '',
      groupId: '',
      kind: GroupMemberStoreMutationKind.reset,
    ),
  );
  bool _factoryReady = false;

  bool get _useMemoryOnly => kIsWeb;

  void _emitCommit({
    required String owner,
    required String groupId,
    required GroupMemberStoreMutationKind kind,
    List<GroupMemberRecord> upserted = const <GroupMemberRecord>[],
    Set<String> deletedUserIds = const <String>{},
    bool snapshotComplete = false,
    int snapshotCount = 0,
  }) {
    commitListenable.value = GroupMemberStoreCommit(
      version: ++_commitVersion,
      ownerUserId: owner,
      groupId: groupId,
      kind: kind,
      upserted: List<GroupMemberRecord>.unmodifiable(upserted),
      deletedUserIds: Set<String>.unmodifiable(deletedUserIds),
      snapshotComplete: snapshotComplete,
      snapshotCount: snapshotCount,
    );
  }

  static List<GroupMemberRecord> dedupeGroupMemberRecords(
    List<GroupMemberRecord> records,
  ) {
    final byUserId = <String, GroupMemberRecord>{};
    for (final record in records) {
      final userId = ChatIdFormat.rawUserUid(record.userId);
      if (userId.isEmpty) {
        continue;
      }
      byUserId[userId] =
          record.userId == userId ? record : record.copyWith(userId: userId);
    }
    return byUserId.values.toList(growable: false);
  }

  @visibleForTesting
  static bool samePersistedGroupMemberRecord(
    GroupMemberRecord existing,
    GroupMemberRecord incoming,
  ) {
    return existing.userId == incoming.userId &&
        existing.nickname == incoming.nickname &&
        existing.avatarUrl == incoming.avatarUrl &&
        existing.friendRemark == incoming.friendRemark &&
        existing.nameCard == incoming.nameCard &&
        existing.role == incoming.role &&
        existing.joinedAt == incoming.joinedAt &&
        existing.isSelf == incoming.isSelf &&
        existing.muteUntil == incoming.muteUntil &&
        existing.invitedByUserId == incoming.invitedByUserId &&
        existing.invitedByNickname == incoming.invitedByNickname &&
        existing.joinChannel == incoming.joinChannel;
  }

  @visibleForTesting
  static List<GroupMemberRecord> mergeIncomingPreservingJoinMeta({
    required List<GroupMemberRecord> existing,
    required List<GroupMemberRecord> incoming,
  }) {
    final existingByUserId = <String, GroupMemberRecord>{
      for (final record in existing) record.userId: record,
    };
    return incoming
        .map((record) {
          final old = existingByUserId[record.userId];
          return old == null ? record : record.mergingJoinMetaFrom(old);
        })
        .toList(growable: false);
  }

  @visibleForTesting
  static List<GroupMemberRecord> groupMemberRecordsToUpsert({
    required List<GroupMemberRecord> existing,
    required List<GroupMemberRecord> normalized,
  }) {
    final existingByUserId = <String, GroupMemberRecord>{
      for (final record in existing) record.userId: record,
    };
    return normalized.where((record) {
      final old = existingByUserId[record.userId];
      return old == null || !samePersistedGroupMemberRecord(old, record);
    }).toList(growable: false);
  }

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

  Future<Database> _openDb() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) {
      return existing;
    }
    await _ensureDatabaseFactory();
    final basePath = await getDatabasesPath();
    final path = p.join(basePath, _dbName);
    _db = await openDatabase(
      path,
      version: 7,
      onOpen: (db) async {
        // FFB-2 扩散：iOS sqflite_darwin 启动期 PRAGMA 救火。失败不阻断 DB open。
        await SqfliteBootstrapHelper.withTag('group_member')
            .runOnOpenPragmas(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            owner_user_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            nickname TEXT NOT NULL DEFAULT '',
            avatar_url TEXT NOT NULL DEFAULT '',
            friend_remark TEXT NOT NULL DEFAULT '',
            name_card TEXT NOT NULL DEFAULT '',
            role INTEGER NOT NULL DEFAULT 200,
            joined_at INTEGER NOT NULL DEFAULT 0,
            is_self INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            mute_until INTEGER NOT NULL DEFAULT 0,
            invited_by_user_id TEXT NOT NULL DEFAULT '',
            invited_by_nickname TEXT NOT NULL DEFAULT '',
            join_channel TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (owner_user_id, group_id, user_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_group_members_owner_group ON $_table(owner_user_id, group_id)',
        );
        await db.execute('CREATE INDEX idx_group_members_window '
            'ON $_table(owner_user_id, group_id, role DESC, joined_at, user_id)');
        await db.execute('''
          CREATE TABLE $_cursorTable (
            owner_user_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            member_seq INTEGER NOT NULL DEFAULT 0,
            snapshot_complete INTEGER NOT NULL DEFAULT 0,
            snapshot_count INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            needs_member_sync INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner_user_id, group_id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_group_members_window '
              'ON $_table(owner_user_id, group_id, role DESC, joined_at, user_id)');
        }
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN mute_until INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN invited_by_user_id TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN invited_by_nickname TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN join_channel TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE $_cursorTable (
              owner_user_id TEXT NOT NULL,
              group_id TEXT NOT NULL,
              member_seq INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (owner_user_id, group_id)
            )
          ''');
        }
        if (oldVersion < 5) {
          await _safeAddColumn(
            db,
            table: _cursorTable,
            column: 'snapshot_complete',
            ddl:
                'ALTER TABLE $_cursorTable ADD COLUMN snapshot_complete INTEGER NOT NULL DEFAULT 0',
          );
          await _safeAddColumn(
            db,
            table: _cursorTable,
            column: 'snapshot_count',
            ddl:
                'ALTER TABLE $_cursorTable ADD COLUMN snapshot_count INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await _safeAddColumn(
            db,
            table: _cursorTable,
            column: 'needs_member_sync',
            ddl:
                'ALTER TABLE $_cursorTable ADD COLUMN needs_member_sync INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    await _healCursorTableIfMissingColumns(_db!);
    return _db!;
  }

  /// Idempotent ADD COLUMN：先 PRAGMA table_info 检查列是否已存在。
  /// 避免 db schema 与 user_version 不一致时（例如中途被外部脚本/测试
  /// 工具改过表结构，或 _healCursorTableIfMissingColumns 重建表后
  /// user_version 仍 < N 但表里已有新列）重复加列抛 "duplicate column"。
  static Future<void> _safeAddColumn(
    Database db, {
    required String table,
    required String column,
    required String ddl,
  }) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final hasColumn = info.any(
        (row) => (row['name'] as String?) == column,
      );
      if (hasColumn) {
        return;
      }
      await db.execute(ddl);
    } catch (_) {
      // 静默失败：宁可缺列也不能阻断 openDatabase。
      // 上层 hasCompleteSnapshot 等方法在缺列时会走 fallback path。
    }
  }

  /// Idempotent schema heal: 旧部署 v5 db 缺 snapshot_complete 列时
  /// （onUpgrade v4→v5 早期版本没补列，导致已升 v5 设备永久残留），
  /// DROP 整个 cursor 表，重建为空。成员流游标随 TCP seq 再写入。
  ///
  /// 业务数据安全：cursor 表只存增量游标与 snapshot 标记，群成员真实数据
  /// 在 $_table（group_members），不会被破坏。
  Future<void> _healCursorTableIfMissingColumns(Database db) async {
    const requiredColumns = <String>{
      'snapshot_complete',
      'snapshot_count',
      'needs_member_sync',
    };
    try {
      final info = await db.rawQuery('PRAGMA table_info($_cursorTable)');
      final existing = info
          .map((row) => row['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();
      final missing = requiredColumns.difference(existing);
      if (missing.isEmpty) {
        return;
      }
      // 缺列：drop + 重建。cursor 行不丢业务（成员表 group_members 完整
      // 保留；只是增量游标清零，下次 sync 从 seq=0 开始）。
      await db.execute('DROP TABLE IF EXISTS $_cursorTable');
      await db.execute('''
        CREATE TABLE $_cursorTable (
          owner_user_id TEXT NOT NULL,
          group_id TEXT NOT NULL,
          member_seq INTEGER NOT NULL DEFAULT 0,
          snapshot_complete INTEGER NOT NULL DEFAULT 0,
          snapshot_count INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0,
          needs_member_sync INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (owner_user_id, group_id)
        )
      ''');
      if (kDebugMode) {
        debugPrint(
          '[GroupMemberLocalStore] healed cursor table, missing=$missing',
        );
      }
    } catch (e) {
      // Heal 失败不能阻断 openDatabase；让上层 try/catch 处理。
      if (kDebugMode) {
        debugPrint(
          '[GroupMemberLocalStore] cursor heal skipped error=$e',
        );
      }
    }
  }

  Future<void> closeIfOpen() async {
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
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

  String _resolveGroupId(String groupId) {
    final canonical = ChatIdFormat.canonicalGroupStorageId(groupId);
    return canonical.isNotEmpty ? canonical : groupId.trim();
  }

  Future<List<GroupMemberRecord>> readAll({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final rawGid = groupId.trim();
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return const <GroupMemberRecord>[];
    }
    if (_useMemoryOnly) {
      final cached = _memoryByOwner[owner]?[gid] ??
          (rawGid == gid
              ? const <GroupMemberRecord>[]
              : _memoryByOwner[owner]?[rawGid] ?? const <GroupMemberRecord>[]);
      return List<GroupMemberRecord>.from(cached);
    }
    final db = await _openDb();
    var rows = await db.query(
      _table,
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
      orderBy: 'role DESC, joined_at ASC, user_id ASC',
    );
    // Read legacy pre-canonical rows once so coverage installs do not hide an
    // existing member snapshot after the storage key normalization change.
    if (rows.isEmpty && rawGid != gid) {
      rows = await db.query(
        _table,
        where: 'owner_user_id = ? AND group_id = ?',
        whereArgs: [owner, rawGid],
        orderBy: 'role DESC, joined_at ASC, user_id ASC',
      );
    }
    return rows.map(_recordFromRow).toList(growable: false);
  }

  /// Count a complete cached collection without decoding member objects.
  Future<int> countMembers(
      {required String groupId, String? ownerUserId}) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return 0;
    if (_useMemoryOnly) return _memoryByOwner[owner]?[gid]?.length ?? 0;
    final db = await _openDb();
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $_table '
        'WHERE owner_user_id = ? AND group_id = ?',
        [owner, gid]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// A bounded local window; never materialize the full group to show a preview.
  /// Null means incomplete/unknown; zero is an authoritative empty snapshot.
  /// Read coverage and count in one SQL statement so a reset cannot race a
  /// separate hasCompleteSnapshot()/countMembers() pair.
  Future<int?> readCompleteSnapshotCount({
    required String groupId,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return null;
    if (_useMemoryOnly) {
      return _completeSnapshots.contains('$owner|$gid')
          ? (_memoryByOwner[owner]?[gid]?.length ?? 0)
          : null;
    }
    final db = await _openDb();
    final rows = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM $_table m '
      'WHERE m.owner_user_id = c.owner_user_id AND m.group_id = c.group_id) AS n '
      'FROM $_cursorTable c WHERE c.owner_user_id = ? AND c.group_id = ? '
      'AND c.snapshot_complete = 1 LIMIT 1',
      [owner, gid],
    );
    return rows.isEmpty ? null : (rows.single['n'] as num).toInt();
  }

  /// A bounded local window; never materialize the full group to show a preview.
  Future<List<GroupMemberRecord>> readWindow({
    required String groupId,
    String? ownerUserId,
    int limit = 50,
    int offset = 0,
    String keyword = '',
    int? role,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || limit <= 0) return [];
    final start = offset < 0 ? 0 : offset;
    final needle = keyword.trim().toLowerCase();
    if (_useMemoryOnly) {
      final rows = (_memoryByOwner[owner]?[gid] ?? const <GroupMemberRecord>[])
          .where((r) =>
              (role == null || r.role == role) &&
              (needle.isEmpty ||
                  [r.userId, r.nickname, r.nameCard, r.friendRemark]
                      .any((s) => s.toLowerCase().contains(needle))))
          .toList();
      rows.sort((a, b) {
        final role = b.role.compareTo(a.role);
        if (role != 0) return role;
        final joined = a.joinedAt.compareTo(b.joinedAt);
        return joined != 0 ? joined : a.userId.compareTo(b.userId);
      });
      return rows.skip(start).take(limit).toList(growable: false);
    }
    final db = await _openDb();
    Future<List<Map<String, Object?>>> query(String key) => db.query(
          _table,
          where: 'owner_user_id = ? AND group_id = ?' +
              (role == null ? '' : ' AND role = ?') +
              (needle.isEmpty
                  ? ''
                  : ' AND (instr(lower(user_id), ?) > 0 OR instr(lower(nickname), ?) > 0'
                      ' OR instr(lower(name_card), ?) > 0 OR instr(lower(friend_remark), ?) > 0)'),
          whereArgs: [
            owner,
            key,
            if (role != null) role,
            if (needle.isNotEmpty) ...[needle, needle, needle, needle]
          ],
          orderBy: 'role DESC, joined_at ASC, user_id ASC',
          limit: limit,
          offset: start,
        );
    var rows = await query(gid);
    if (rows.isEmpty && groupId.trim() != gid) {
      // Only use legacy rows if the canonical collection is absent, not when
      // a canonical page/search legitimately has no matches.
      final exists = await db.query(_table,
          columns: ['user_id'],
          where: 'owner_user_id = ? AND group_id = ?',
          whereArgs: [owner, gid],
          limit: 1);
      if (exists.isEmpty) rows = await query(groupId.trim());
    }
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<List<V2TimGroupMemberFullInfo>> loadAsV2TimMembers({
    required String groupId,
    String? ownerUserId,
    int? limit,
    int offset = 0,
    String keyword = '',
  }) async {
    final records = limit == null
        ? await readAll(groupId: groupId, ownerUserId: ownerUserId)
        : await readWindow(
            groupId: groupId,
            ownerUserId: ownerUserId,
            limit: limit,
            offset: offset,
            keyword: keyword);
    return records.map(_toV2TimMember).toList(growable: false);
  }

  Future<List<V2TimGroupMemberFullInfo>> readByUserIds({
    required String groupId,
    required List<String> userIds,
    String? ownerUserId,
  }) async {
    final records = await readRecordsByUserIds(
      groupId: groupId,
      userIds: userIds,
      ownerUserId: ownerUserId,
    );
    return records.map(_toV2TimMember).toList(growable: false);
  }

  Future<GroupMemberRecord?> readRecord({
    required String groupId,
    required String userId,
    String? ownerUserId,
  }) async {
    final uid = ChatIdFormat.rawUserUid(userId);
    if (uid.isEmpty) {
      return null;
    }
    final list = await readRecordsByUserIds(
      groupId: groupId,
      userIds: <String>[uid],
      ownerUserId: ownerUserId,
    );
    for (final record in list) {
      if (record.userId == uid) {
        return record;
      }
    }
    return null;
  }

  Future<List<GroupMemberRecord>> readRecordsByUserIds({
    required String groupId,
    required List<String> userIds,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final wanted =
        userIds.map(ChatIdFormat.rawUserUid).where((e) => e.isNotEmpty).toSet();
    if (owner.isEmpty || gid.isEmpty || wanted.isEmpty) {
      return const <GroupMemberRecord>[];
    }
    if (_useMemoryOnly) {
      final all = await readAll(groupId: gid, ownerUserId: owner);
      return all
          .where((record) => wanted.contains(record.userId))
          .toList(growable: false);
    }
    final db = await _openDb();
    final records = await _readRecordsByUserIds(
      db,
      owner: owner,
      groupId: gid,
      userIds: wanted.toList(growable: false),
    );
    records.sort((a, b) {
      final roleCmp = b.role.compareTo(a.role);
      if (roleCmp != 0) return roleCmp;
      final joinedCmp = a.joinedAt.compareTo(b.joinedAt);
      if (joinedCmp != 0) return joinedCmp;
      return a.userId.compareTo(b.userId);
    });
    return records;
  }

  Future<void> replacePage({
    required String ownerUserId,
    required String groupId,
    required int offset,
    required List<GroupMemberRecord> records,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return;
    }
    if (offset <= 0) {
      await clearGroup(ownerUserId: owner, groupId: gid);
    }
    await upsertMany(ownerUserId: owner, groupId: gid, records: records);
  }

  /// Reconciles an authoritative complete member snapshot in one transaction.
  /// Unchanged rows are retained, missing rows are removed, and only changed or
  /// new rows are written.
  Future<void> replaceSnapshot({
    required String ownerUserId,
    required String groupId,
    required List<GroupMemberRecord> records,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final normalized = dedupeGroupMemberRecords(records);
    if (owner.isEmpty || gid.isEmpty) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final byGroup = _memoryByOwner.putIfAbsent(owner, () => {});
      byGroup[gid] = List<GroupMemberRecord>.from(normalized)
        ..sort((a, b) {
          final roleCmp = b.role.compareTo(a.role);
          if (roleCmp != 0) return roleCmp;
          final joinedCmp = a.joinedAt.compareTo(b.joinedAt);
          if (joinedCmp != 0) return joinedCmp;
          return a.userId.compareTo(b.userId);
        });
      _completeSnapshots.add('$owner|$gid');
      _emitCommit(
        owner: owner,
        groupId: gid,
        kind: GroupMemberStoreMutationKind.snapshot,
        upserted: normalized,
        snapshotComplete: true,
        snapshotCount: normalized.length,
      );
      return;
    }

    final db = await _openDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await profiledTransaction<void>(
      db,
      dbTag: _dbName,
      op: 'replaceSnapshot',
      extras: <String, Object?>{'count': normalized.length},
      action: (txn) async {
        final rows = await txn.query(
          _table,
          where: 'owner_user_id = ? AND group_id = ?',
          whereArgs: [owner, gid],
        );
        final existing = rows.map(_recordFromRow).toList(growable: false);
        final incomingIds = normalized.map((item) => item.userId).toSet();
        final toDelete = existing
            .where((item) => !incomingIds.contains(item.userId))
            .map((item) => item.userId)
            .toList(growable: false);
        final toUpsert = groupMemberRecordsToUpsert(
          existing: existing,
          normalized: normalized,
        );
        await txn.insert(
          _cursorTable,
          <String, Object?>{
            'owner_user_id': owner,
            'group_id': gid,
            'member_seq': 0,
            'snapshot_complete': 1,
            'snapshot_count': normalized.length,
            'updated_at': now,
            'needs_member_sync': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.update(
          _cursorTable,
          <String, Object?>{
            'snapshot_complete': 1,
            'snapshot_count': normalized.length,
            'updated_at': now,
            'needs_member_sync': 0,
          },
          where: 'owner_user_id = ? AND group_id = ?',
          whereArgs: <Object?>[owner, gid],
        );
        if (toDelete.isEmpty && toUpsert.isEmpty) {
          SqfliteLockProfileLog.event(
            'replaceSnapshot_skip',
            extras: <String, Object?>{
              'db': _dbName,
              'count': normalized.length,
            },
          );
          return;
        }
        final batch = txn.batch();
        for (final userId in toDelete) {
          batch.delete(
            _table,
            where: 'owner_user_id = ? AND group_id = ? AND user_id = ?',
            whereArgs: [owner, gid, userId],
          );
        }
        for (final item in toUpsert) {
          batch.insert(
            _table,
            _rowFromRecord(owner, gid, item, now),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      },
    );
    _emitCommit(
      owner: owner,
      groupId: gid,
      kind: GroupMemberStoreMutationKind.snapshot,
      upserted: normalized,
      snapshotComplete: true,
      snapshotCount: normalized.length,
    );
  }

  Future<void> upsertMany({
    required String ownerUserId,
    required String groupId,
    required List<GroupMemberRecord> records,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final normalized = dedupeGroupMemberRecords(records);
    if (owner.isEmpty || gid.isEmpty || normalized.isEmpty) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final byGroup = _memoryByOwner.putIfAbsent(owner, () => {});
      final list = offsetList(byGroup, gid);
      final toUpsert = groupMemberRecordsToUpsert(
        existing: list,
        normalized: mergeIncomingPreservingJoinMeta(
          existing: list,
          incoming: normalized,
        ),
      );
      for (final item in toUpsert) {
        list.removeWhere((e) => e.userId == item.userId);
        list.add(item);
      }
      list.sort((a, b) {
        final roleCmp = b.role.compareTo(a.role);
        if (roleCmp != 0) return roleCmp;
        final joinedCmp = a.joinedAt.compareTo(b.joinedAt);
        if (joinedCmp != 0) return joinedCmp;
        return a.userId.compareTo(b.userId);
      });
      byGroup[gid] = list;
      if (toUpsert.isNotEmpty) {
        _emitCommit(
          owner: owner,
          groupId: gid,
          kind: GroupMemberStoreMutationKind.upsert,
          upserted: toUpsert,
        );
      }
      return;
    }
    final db = await _openDb();
    final existing = await _readRecordsByUserIds(
      db,
      owner: owner,
      groupId: gid,
      userIds:
          normalized.map((record) => record.userId).toList(growable: false),
    );
    final toUpsert = groupMemberRecordsToUpsert(
      existing: existing,
      normalized: mergeIncomingPreservingJoinMeta(
        existing: existing,
        incoming: normalized,
      ),
    );
    if (toUpsert.isEmpty) {
      SqfliteLockProfileLog.event(
        'upsertMany_skip',
        extras: <String, Object?>{
          'db': _dbName,
          'count': normalized.length,
          'unchanged': normalized.length,
        },
      );
      return;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await profiledTransaction<void>(
      db,
      dbTag: _dbName,
      op: 'upsertMany',
      extras: <String, Object?>{
        'count': toUpsert.length,
        'unchanged': normalized.length - toUpsert.length,
      },
      action: (txn) async {
        for (final item in toUpsert) {
          await txn.insert(
            _table,
            _rowFromRecord(owner, gid, item, now),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      },
    );
    _emitCommit(
      owner: owner,
      groupId: gid,
      kind: GroupMemberStoreMutationKind.upsert,
      upserted: toUpsert,
    );
  }

  Future<List<GroupMemberRecord>> _readRecordsByUserIds(
    Database db, {
    required String owner,
    required String groupId,
    required List<String> userIds,
  }) async {
    final records = <GroupMemberRecord>[];
    for (var offset = 0;
        offset < userIds.length;
        offset += _readByIdsChunkSize) {
      final end = offset + _readByIdsChunkSize > userIds.length
          ? userIds.length
          : offset + _readByIdsChunkSize;
      final chunk = userIds.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        _table,
        where:
            'owner_user_id = ? AND group_id = ? AND user_id IN ($placeholders)',
        whereArgs: <Object?>[owner, groupId, ...chunk],
      );
      records.addAll(rows.map(_recordFromRow));
    }
    return records;
  }

  List<GroupMemberRecord> offsetList(
      Map<String, List<GroupMemberRecord>> byGroup, String gid) {
    return List<GroupMemberRecord>.from(byGroup[gid] ?? const []);
  }

  Future<void> deleteUsers({
    required String ownerUserId,
    required String groupId,
    required List<String> userIds,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final ids = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((e) => e.isNotEmpty)
        .toList();
    if (owner.isEmpty || gid.isEmpty || ids.isEmpty) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final byGroup = _memoryByOwner[owner];
      final list = byGroup?[gid];
      if (list == null) {
        return;
      }
      list.removeWhere((e) => ids.contains(e.userId));
      _emitCommit(
        owner: owner,
        groupId: gid,
        kind: GroupMemberStoreMutationKind.delete,
        deletedUserIds: ids.toSet(),
      );
      return;
    }
    final db = await _openDb();
    for (final userId in ids) {
      await db.delete(
        _table,
        where: 'owner_user_id = ? AND group_id = ? AND user_id = ?',
        whereArgs: [owner, gid, userId],
      );
    }
    _emitCommit(
      owner: owner,
      groupId: gid,
      kind: GroupMemberStoreMutationKind.delete,
      deletedUserIds: ids.toSet(),
    );
  }

  /// Applies one member-stream event and advances its cursor atomically.
  ///
  /// The cursor must never move ahead of the corresponding member mutation:
  /// after a process kill it is safe to replay an already committed event, but
  /// it is not safe to skip an event whose row was never written.
  Future<void> applyIncrementalEvent({
    required String ownerUserId,
    required String groupId,
    required int memberSeq,
    GroupMemberRecord? upsert,
    String? removeUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final removeId = ChatIdFormat.rawUserUid(removeUserId);
    final record = upsert == null
        ? null
        : (ChatIdFormat.rawUserUid(upsert.userId).isEmpty
            ? null
            : (upsert.userId == ChatIdFormat.rawUserUid(upsert.userId)
                ? upsert
                : upsert.copyWith(
                    userId: ChatIdFormat.rawUserUid(upsert.userId))));
    if (owner.isEmpty ||
        gid.isEmpty ||
        memberSeq < 0 ||
        (record == null && removeId.isEmpty)) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      if (record != null) {
        await upsertMany(ownerUserId: owner, groupId: gid, records: [record]);
      } else {
        await deleteUsers(
            ownerUserId: owner, groupId: gid, userIds: [removeId]);
      }
      return;
    }
    final db = await _openDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await profiledTransaction<void>(
      db,
      dbTag: _dbName,
      op: 'applyIncrementalEvent',
      extras: <String, Object?>{'seq': memberSeq, 'upsert': record != null},
      action: (txn) async {
        if (record != null) {
          await txn.insert(
            _table,
            _rowFromRecord(owner, gid, record, now),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.delete(
            _table,
            where: 'owner_user_id = ? AND group_id = ? AND user_id = ?',
            whereArgs: [owner, gid, removeId],
          );
        }
        await txn.insert(
          _cursorTable,
          <String, Object?>{
            'owner_user_id': owner,
            'group_id': gid,
            'member_seq': memberSeq,
            'updated_at': now,
            'needs_member_sync': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.rawUpdate('''
          UPDATE $_cursorTable
          SET member_seq = CASE WHEN member_seq < ? THEN ? ELSE member_seq END,
              updated_at = ?, needs_member_sync = 0
          WHERE owner_user_id = ? AND group_id = ?
        ''', <Object?>[memberSeq, memberSeq, now, owner, gid]);
      },
    );
    _emitCommit(
      owner: owner,
      groupId: gid,
      kind: record != null
          ? GroupMemberStoreMutationKind.upsert
          : GroupMemberStoreMutationKind.delete,
      upserted: record == null
          ? const <GroupMemberRecord>[]
          : <GroupMemberRecord>[record],
      deletedUserIds: record == null ? <String>{removeId} : const <String>{},
    );
  }

  Future<int> readIncrementalCursor({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || _useMemoryOnly) return 0;
    final db = await _openDb();
    final rows = await db.query(
      _cursorTable,
      columns: const ['member_seq'],
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
      limit: 1,
    );
    return (rows.isEmpty
        ? 0
        : (rows.first['member_seq'] as num?)?.toInt() ?? 0);
  }

  /// 返回 cursor 表中该群的 member_seq + updated_at。
  /// 缺失任何字段返回 (0, 0)。
  Future<({int seq, int updatedAtMs})> readIncrementalCursorWithTimestamp({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || _useMemoryOnly) {
      return (seq: 0, updatedAtMs: 0);
    }
    final db = await _openDb();
    final rows = await db.query(
      _cursorTable,
      columns: const ['member_seq', 'updated_at'],
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
      limit: 1,
    );
    if (rows.isEmpty) return (seq: 0, updatedAtMs: 0);
    return (
      seq: (rows.first['member_seq'] as num?)?.toInt() ?? 0,
      updatedAtMs: (rows.first['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否存在该群的 cursor 行（用于决定是否需要 refresh=true）。
  Future<bool> hasCursorRow({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || _useMemoryOnly) return false;
    final db = await _openDb();
    final rows = await db.query(
      _cursorTable,
      columns: const ['member_seq'],
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasCompleteSnapshot({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return false;
    if (_useMemoryOnly) return _completeSnapshots.contains('$owner|$gid');
    final db = await _openDb();
    final rows = await db.query(
      _cursorTable,
      columns: const ['snapshot_complete'],
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
      limit: 1,
    );
    return rows.isNotEmpty &&
        ((rows.first['snapshot_complete'] as num?)?.toInt() ?? 0) == 1;
  }

  Future<void> advanceIncrementalCursor({
    required String ownerUserId,
    required String groupId,
    required int memberSeq,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || memberSeq < 0 || _useMemoryOnly) return;
    final db = await _openDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(
      _cursorTable,
      <String, Object?>{
        'owner_user_id': owner,
        'group_id': gid,
        'member_seq': memberSeq,
        'updated_at': now,
        'needs_member_sync': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.rawUpdate('''
      UPDATE $_cursorTable
      SET member_seq = CASE WHEN member_seq < ? THEN ? ELSE member_seq END,
          updated_at = ?, needs_member_sync = 0
      WHERE owner_user_id = ? AND group_id = ?
    ''', <Object?>[memberSeq, memberSeq, now, owner, gid]);
  }

  Future<void> clearIncrementalCursor({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty || _useMemoryOnly) return;
    final db = await _openDb();
    await db.update(
      _cursorTable,
      <String, Object?>{
        'member_seq': 0,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
    );
  }

  Future<void> clearGroup({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) {
      return;
    }
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      _memoryByOwner[owner]?.remove(gid);
      _completeSnapshots.remove('$owner|$gid');
      _emitCommit(
        owner: owner,
        groupId: gid,
        kind: GroupMemberStoreMutationKind.reset,
      );
      return;
    }
    final db = await _openDb();
    await db.delete(
      _table,
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
    );
    await db.delete(
      _cursorTable,
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
    );
    _emitCommit(
      owner: owner,
      groupId: gid,
      kind: GroupMemberStoreMutationKind.reset,
    );
  }

  /// 列出该 owner 下 needs_member_sync=1 的所有群 ID（已 normalize）。
  Future<List<String>> readPendingMemberSyncGroupIds({
    required String ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty || _useMemoryOnly) return const <String>[];
    final db = await _openDb();
    final rows = await db.query(
      _cursorTable,
      columns: const ['group_id'],
      where: 'owner_user_id = ? AND needs_member_sync = 1',
      whereArgs: [owner],
    );
    return rows
        .map((row) => ChatIdFormat.normalizeGroupId(
              (row['group_id'] as String?) ?? '',
            ))
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// 把群标记为待成员同步（needs_member_sync=1）。
  /// 使用 UPSERT：如果 row 不存在则插入空 cursor 行；如果存在则更新。
  Future<void> markMemberSyncPending({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return;
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) return;
    final db = await _openDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(
      _cursorTable,
      <String, Object?>{
        'owner_user_id': owner,
        'group_id': gid,
        'member_seq': 0,
        'snapshot_complete': 0,
        'snapshot_count': 0,
        'updated_at': now,
        'needs_member_sync': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      _cursorTable,
      <String, Object?>{'needs_member_sync': 1, 'updated_at': now},
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: <Object?>[owner, gid],
    );
  }

  /// 清除单个群的待同步标记，避免 owner 级批量清除误伤其它群。
  Future<void> clearMemberSyncPending({
    required String ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    if (owner.isEmpty || gid.isEmpty) return;
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) return;
    final db = await _openDb();
    await db.update(
      _cursorTable,
      const <String, Object?>{'needs_member_sync': 0},
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, gid],
    );
  }

  /// 清空某 owner 下所有群的 needs_member_sync 标记（登出/换账号时调用）。
  Future<void> clearPendingMemberSyncForOwner({
    required String ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) return;
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) return;
    final db = await _openDb();
    await db.update(
      _cursorTable,
      <String, Object?>{'needs_member_sync': 0},
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
  }

  Future<void> patchUser({
    required String ownerUserId,
    required String groupId,
    required String userId,
    required GroupMemberRecord Function(GroupMemberRecord current) transform,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final gid = _resolveGroupId(groupId);
    final uid = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty || gid.isEmpty || uid.isEmpty) {
      return;
    }
    final current = await readRecord(
      groupId: gid, ownerUserId: owner, userId: uid,
    );
    if (current == null) {
      return;
    }
    await upsertMany(
      ownerUserId: owner,
      groupId: gid,
      records: [transform(current)],
    );
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    _memoryByOwner.remove(owner);
    _completeSnapshots.removeWhere((key) => key.startsWith('$owner|'));
    if (_useMemoryOnly) {
      _emitCommit(
        owner: owner,
        groupId: '',
        kind: GroupMemberStoreMutationKind.reset,
      );
      return;
    }
    final db = await _openDb();
    await db.delete(_table, where: 'owner_user_id = ?', whereArgs: [owner]);
    await db.delete(
      _cursorTable,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    _emitCommit(
      owner: owner,
      groupId: '',
      kind: GroupMemberStoreMutationKind.reset,
    );
  }

  Future<void> clearSession() async {
    // 登出只卸内存；磁盘多账号共存，注销走 clearForOwner。
    _memoryByOwner.clear();
    _completeSnapshots.clear();
    _emitCommit(
      owner: '',
      groupId: '',
      kind: GroupMemberStoreMutationKind.reset,
    );
  }

  /// 测试专用：整表清空（生产登出禁止调用）。
  @visibleForTesting
  Future<void> wipeAllDiskForTest() async {
    _memoryByOwner.clear();
    _completeSnapshots.clear();
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.delete(_table);
  }

  V2TimGroupMemberFullInfo _toV2TimMember(GroupMemberRecord record) {
    return V2TimGroupMemberFullInfo(
      userID: record.userId,
      role: record.role,
      joinTime: record.joinedAt > 0 ? record.joinedAt ~/ 1000 : null,
      nickName: record.nickname,
      nameCard: record.nameCard,
      friendRemark: record.friendRemark,
      faceUrl: record.avatarUrl,
      muteUntil: record.muteUntil > 0 ? record.muteUntil : null,
    );
  }

  GroupMemberRecord _recordFromRow(Map<String, Object?> row) {
    return GroupMemberRecord(
      userId: row['user_id']?.toString() ?? '',
      nickname: row['nickname']?.toString() ?? '',
      avatarUrl: row['avatar_url']?.toString() ?? '',
      friendRemark: row['friend_remark']?.toString() ?? '',
      nameCard: row['name_card']?.toString() ?? '',
      role: (row['role'] as int?) ?? 200,
      joinedAt: (row['joined_at'] as int?) ?? 0,
      isSelf: (row['is_self'] as int? ?? 0) != 0,
      muteUntil: (row['mute_until'] as int?) ?? 0,
      invitedByUserId: row['invited_by_user_id']?.toString() ?? '',
      invitedByNickname: row['invited_by_nickname']?.toString() ?? '',
      joinChannel: row['join_channel']?.toString() ?? '',
    );
  }

  Map<String, Object?> _rowFromRecord(
    String owner,
    String groupId,
    GroupMemberRecord record,
    int updatedAt,
  ) {
    return <String, Object?>{
      'owner_user_id': owner,
      'group_id': groupId,
      'user_id': record.userId,
      'nickname': record.nickname,
      'avatar_url': record.avatarUrl,
      'friend_remark': record.friendRemark,
      'name_card': record.nameCard,
      'role': record.role,
      'joined_at': record.joinedAt,
      'is_self': record.isSelf ? 1 : 0,
      'updated_at': updatedAt,
      'mute_until': record.muteUntil,
      'invited_by_user_id': record.invitedByUserId,
      'invited_by_nickname': record.invitedByNickname,
      'join_channel': record.joinChannel,
    };
  }
}
