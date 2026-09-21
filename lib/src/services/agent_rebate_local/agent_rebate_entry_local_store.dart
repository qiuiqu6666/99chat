import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_demo/src/services/agent_rebate_local/agent_rebate_entry_record.dart';

/// 「某账号 × 某群」反水入口判定的本地持久化。
///
/// - 主键 `(owner_user_id, group_id)`；
/// - `group_id` 用 [ChatIdFormat.normalizeGroupId] 归一；
/// - 对外暴露 **同步** [readCachedSync]（仅内存命中）以供进群首屏零延迟渲染；
/// - 异步 [read] 兜底读 sqflite（仅冷启动第一次进群走一次）；
/// - [upsert] / [markNotAgent] 同时更新内存映射与 sqflite（web 跳过 sqflite）；
/// - [clearSession] 只清内存映射；[clearForOwner] 清磁盘对应 owner 行。
class AgentRebateEntryLocalStore {
  AgentRebateEntryLocalStore._();

  static final AgentRebateEntryLocalStore instance =
      AgentRebateEntryLocalStore._();

  static const String _dbName = 'agent_rebate_entry_v1.db';
  static const String _table = 'agent_rebate_entries';
  static const String _metaTable = 'agent_rebate_entry_meta';

  Database? _db;
  bool _factoryReady = false;

  final Map<String, AgentRebateEntryRecord> _byOwnerGroup = <String, AgentRebateEntryRecord>{};

  bool get _useMemoryOnly => kIsWeb;

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
      version: 1,
      onOpen: (db) async {
        await SqfliteBootstrapHelper.withTag('agent_rebate').runOnOpenPragmas(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            owner_user_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            bound INTEGER NOT NULL DEFAULT 0,
            enabled INTEGER NOT NULL DEFAULT 0,
            is_agent INTEGER NOT NULL DEFAULT 0,
            robot_id TEXT NOT NULL DEFAULT '',
            machine_code_masked TEXT,
            rebate_rate REAL NOT NULL DEFAULT 0,
            level_no INTEGER NOT NULL DEFAULT 0,
            player_type TEXT NOT NULL DEFAULT '',
            player_no TEXT NOT NULL DEFAULT '',
            display_name TEXT NOT NULL DEFAULT '',
            data_version INTEGER NOT NULL DEFAULT 1,
            fetched_at_ms INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner_user_id, group_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_agent_rebate_owner_group '
          'ON $_table(owner_user_id, group_id)',
        );
        await db.execute('''
          CREATE TABLE $_metaTable (
            owner_user_id TEXT PRIMARY KEY,
            full_fetched_at_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> closeIfOpen() async {
    final db = _db;
    _db = null;
    await SqfliteLifecycleGuard.closeDatabase(db);
  }

  /// 当前登录用户 ID（同步读取；用于 main.dart 启动预热）。
  String currentOwnerUserId() {
    return _resolveOwner(null);
  }

  /// 把指定 owner 的所有 entry 一次性灌进 [_byOwnerGroup] 内存映射。
  ///
  /// 仅在冷启动早期由 main.dart fire-and-forget 触发；失败不抛。
  /// web 平台无磁盘可读，直接返回 0。
  /// 返回已加载条数（用于日志埋点）。
  Future<int> preloadForOwner(String? ownerUserId) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty || _useMemoryOnly) {
      return 0;
    }
    try {
      final db = await _openDb();
      final rows = await db.query(
        _table,
        where: 'owner_user_id = ?',
        whereArgs: [owner],
      );
      var loaded = 0;
      for (final row in rows) {
        final rawGroupId = (row['group_id'] as String?) ?? '';
        if (rawGroupId.isEmpty) {
          continue;
        }
        final record = _fromRow(row);
        _byOwnerGroup[_compositeKey(owner, rawGroupId)] = record;
        loaded++;
      }
      return loaded;
    } catch (e) {
      debugPrint('[AgentRebateEntry] preload failed (ignored): $e');
      return 0;
    }
  }

  String _compositeKey(String ownerUserId, String groupId) {
    final owner = ownerUserId.trim();
    final group = ChatIdFormat.normalizeGroupId(groupId.trim());
    return '$owner|$group';
  }

  String _resolveOwner(String? ownerUserId) {
    final explicit = ownerUserId?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return ContactSocialCacheStore.safeLoginUserId().trim();
  }

  /// 同步只查内存映射。命中即返回；未命中返回 null（**不读 sqflite**）。
  ///
  /// 供 `chat.dart` 在 `didUpdateWidget` 同步调用：进群首屏立即拿到上次缓存。
  AgentRebateEntryRecord? readCachedSync({
    String? ownerUserId,
    required String groupId,
  }) {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return null;
    }
    return _byOwnerGroup[_compositeKey(owner, groupId)];
  }

  /// 异步：先内存，未命中再走 sqflite。
  ///
  /// 仅在 `readCachedSync` 返回 null 时由 [AgentIdentityService.refreshForGroup]
  /// 内部调用一次（典型场景：冷启动第一次进群）。
  Future<AgentRebateEntryRecord?> read({
    String? ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return null;
    }
    final key = _compositeKey(owner, groupId);
    final cached = _byOwnerGroup[key];
    if (cached != null) {
      return cached;
    }
    if (_useMemoryOnly) {
      return null;
    }
    final db = await _openDb();
    final rows = await db.query(
      _table,
      where: 'owner_user_id = ? AND group_id = ?',
      whereArgs: [owner, ChatIdFormat.normalizeGroupId(groupId.trim())],
    );
    if (rows.isEmpty) {
      return null;
    }
    final record = _fromRow(rows.first);
    _byOwnerGroup[key] = record;
    return record;
  }

  /// 异步写：先更新内存映射，再写 sqflite。
  Future<void> upsert({
    String? ownerUserId,
    required String groupId,
    required AgentRebateEntryRecord record,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    final normalized = ChatIdFormat.normalizeGroupId(groupId.trim());
    _byOwnerGroup[_compositeKey(owner, groupId)] = record;
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.insert(
      _table,
      _toRow(owner, normalized, record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 把指定群的 `isAgent` 置为 false 并写回。
  ///
  /// - 内存有记录：仅翻 `isAgent`，其余字段保留；
  /// - 内存无记录：插入一条全 0 记录（保证下次进群首屏不会"误显"）。
  Future<void> markNotAgent({
    String? ownerUserId,
    required String groupId,
  }) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    final key = _compositeKey(owner, groupId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _byOwnerGroup[key];
    final next = existing == null
        ? AgentRebateEntryRecord(
            fetchedAtMs: now,
          ).copyWith(isAgent: false, fetchedAtMs: now)
        : existing.copyWith(isAgent: false, fetchedAtMs: now);
    await upsert(
      ownerUserId: owner,
      groupId: groupId,
      record: next,
    );
  }

  /// 登出时调用：仅清内存映射，保留磁盘数据（与 `GroupLocalStore.clearSession` 一致）。
  Future<void> clearSession() async {
    _byOwnerGroup.clear();
  }

  /// 注销账号 / 切换账号时调用：清磁盘对应 owner 的全部行。
  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = _resolveOwner(ownerUserId);
    if (owner.isEmpty) {
      return;
    }
    final keysToRemove = _byOwnerGroup.keys
        .where((key) => key.startsWith('$owner|'))
        .toList(growable: false);
    for (final key in keysToRemove) {
      _byOwnerGroup.remove(key);
    }
    if (_useMemoryOnly) {
      return;
    }
    final db = await _openDb();
    await db.delete(
      _table,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
    await db.delete(
      _metaTable,
      where: 'owner_user_id = ?',
      whereArgs: [owner],
    );
  }

  Map<String, Object?> _toRow(
    String ownerUserId,
    String normalizedGroupId,
    AgentRebateEntryRecord record,
  ) {
    return <String, Object?>{
      'owner_user_id': ownerUserId,
      'group_id': normalizedGroupId,
      'bound': record.bound ? 1 : 0,
      'enabled': record.enabled ? 1 : 0,
      'is_agent': record.isAgent ? 1 : 0,
      'robot_id': record.robotId,
      'machine_code_masked': record.machineCodeMasked,
      'rebate_rate': record.rebateRate,
      'level_no': record.levelNo,
      'player_type': record.playerType,
      'player_no': record.playerNo,
      'display_name': record.displayName,
      'data_version': record.dataVersion,
      'fetched_at_ms': record.fetchedAtMs,
    };
  }

  AgentRebateEntryRecord _fromRow(Map<String, Object?> row) {
    return AgentRebateEntryRecord(
      bound: (row['bound'] as int? ?? 0) != 0,
      enabled: (row['enabled'] as int? ?? 0) != 0,
      isAgent: (row['is_agent'] as int? ?? 0) != 0,
      robotId: (row['robot_id'] as String?) ?? '',
      machineCodeMasked: row['machine_code_masked'] as String?,
      rebateRate: (row['rebate_rate'] as num?)?.toDouble() ?? 0,
      levelNo: (row['level_no'] as int?) ?? 0,
      playerType: (row['player_type'] as String?) ?? '',
      playerNo: (row['player_no'] as String?) ?? '',
      displayName: (row['display_name'] as String?) ?? '',
      dataVersion: (row['data_version'] as int?) ?? 1,
      fetchedAtMs: (row['fetched_at_ms'] as int?) ?? 0,
    );
  }
}
