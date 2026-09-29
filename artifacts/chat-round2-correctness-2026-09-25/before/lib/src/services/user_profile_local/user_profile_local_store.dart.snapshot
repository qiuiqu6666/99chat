import 'package:tencent_cloud_chat_demo/src/services/sqlite_query_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/models/user_profile_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';

/// 用户个人资料本地库（按登录账号隔离）。
class UserProfileLocalStore {
  UserProfileLocalStore._();

  static final UserProfileLocalStore instance = UserProfileLocalStore._();

  static const _dbName = 'user_profile_local_v1.db';
  static const _table = 'user_profiles';

  Database? _db;
  final Map<String, Map<String, UserProfileRecord>> _memoryByOwner = {};
  bool _factoryReady = false;

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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            owner_user_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            nickname TEXT NOT NULL DEFAULT '',
            avatar_url TEXT NOT NULL DEFAULT '',
            avatar_version INTEGER NOT NULL DEFAULT 0,
            self_signature TEXT NOT NULL DEFAULT '',
            friend_remark TEXT NOT NULL DEFAULT '',
            friend_remark_confirmed INTEGER NOT NULL DEFAULT 0,
            gender INTEGER,
            birthday INTEGER,
            updated_at INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner_user_id, user_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_user_profiles_owner ON $_table(owner_user_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN friend_remark_confirmed INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN avatar_version INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
    return _db!;
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

  bool get _useMemoryOnly => kIsWeb;

  Future<UserProfileRecord?> read({
    required String userId,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = ChatIdFormat.rawUserUid(userId);
    if (owner.isEmpty || id.isEmpty) {
      return null;
    }
    if (_useMemoryOnly) {
      return _memoryByOwner[owner]?[id];
    }
    final db = await _openDb();
    final rows = await db.diagnosedQuery(
      _table,
      columns: const [
        'owner_user_id', 'user_id', 'nickname', 'avatar_url',
        'avatar_version', 'self_signature', 'friend_remark',
        'friend_remark_confirmed', 'gender',
        'birthday', 'updated_at',
      ],
      where: 'owner_user_id = ? AND user_id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return UserProfileRecord.fromRow(rows.first);
  }

  Future<List<UserProfileRecord>> readByIds({
    required List<String> userIds,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final ids = userIds
        .map(ChatIdFormat.rawUserUid)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (owner.isEmpty || ids.isEmpty) {
      return const [];
    }
    if (_useMemoryOnly) {
      final bucket =
          _memoryByOwner[owner] ?? const <String, UserProfileRecord>{};
      return [
        for (final id in ids)
          if (bucket[id] != null) bucket[id]!,
      ];
    }
    final db = await _openDb();
    final out = <UserProfileRecord>[];
    // Keep the SQLite variable count bounded on every supported platform.
    const chunkSize = 200;
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final end =
          offset + chunkSize > ids.length ? ids.length : offset + chunkSize;
      final slice = ids.sublist(offset, end);
      final placeholders = List.filled(slice.length, '?').join(',');
      final rows = await db.diagnosedRawQuery(
        'SELECT owner_user_id, user_id, nickname, avatar_url, avatar_version, '
        'self_signature, friend_remark, friend_remark_confirmed, gender, birthday, updated_at '
        'FROM $_table WHERE owner_user_id = ? '
        'AND user_id IN ($placeholders)',
        <Object?>[owner, ...slice],
      );
      final byId = <String, UserProfileRecord>{
        for (final row in rows)
          UserProfileRecord.fromRow(row).userId: UserProfileRecord.fromRow(row),
      };
      for (final id in slice) {
        final record = byId[id];
        if (record != null) {
          out.add(record);
        }
      }
    }
    return out;
  }

  Future<void> upsert({
    required UserProfileRecord record,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    final id = ChatIdFormat.rawUserUid(record.userId);
    if (owner.isEmpty || id.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final normalized = record.copyWith(
      userId: id,
      updatedAt: record.updatedAt > 0 ? record.updatedAt : now,
    );
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final bucket = _memoryByOwner.putIfAbsent(owner, () => {});
      bucket[id] = normalized;
      return;
    }
    final db = await _openDb();
    await db.insert(
      _table,
      _rowFromRecord(owner, normalized),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Writes a bounded batch in one SQLite transaction.
  Future<void> upsertBatch({
    required List<UserProfileRecord> records,
    String? ownerUserId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty || records.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final byId = <String, UserProfileRecord>{};
    for (final record in records) {
      final id = ChatIdFormat.rawUserUid(record.userId);
      if (id.isEmpty) {
        continue;
      }
      byId[id] = record.copyWith(
        userId: id,
        updatedAt: record.updatedAt > 0 ? record.updatedAt : now,
      );
    }
    if (byId.isEmpty) {
      return;
    }
    final normalized = byId.values.toList(growable: false);
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) {
      final bucket = _memoryByOwner.putIfAbsent(owner, () => {});
      for (final record in normalized) {
        bucket[record.userId] = record;
      }
      return;
    }
    final db = await _openDb();
    await db.transaction<void>((txn) async {
      final batch = txn.batch();
      for (final record in normalized) {
        batch.insert(
          _table,
          _rowFromRecord(owner, record),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    _memoryByOwner.remove(owner);
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.delete(_table, where: 'owner_user_id = ?', whereArgs: [owner]);
  }

  Future<void> clearSession() async {
    // 登出只卸内存；磁盘多账号共存，注销走 clearForOwner。
    _memoryByOwner.clear();
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
  }

  Map<String, Object?> _rowFromRecord(String owner, UserProfileRecord record) {
    return <String, Object?>{
      'owner_user_id': owner,
      'user_id': record.userId,
      'nickname': record.nickname,
      'avatar_url': record.avatarUrl,
      'avatar_version': record.avatarVersion,
      'self_signature': record.selfSignature,
      'friend_remark': record.friendRemark,
      'friend_remark_confirmed': record.friendRemarkConfirmed ? 1 : 0,
      'gender': record.gender,
      'birthday': record.birthday,
      'updated_at': record.updatedAt,
    };
  }
}
