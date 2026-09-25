import 'ledger_page_progress.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/record/wallet_record_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/contact_social_cache_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/utils/chat_id_format.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';

/// Persistent cache for wallet ledger pages, isolated by account and query.
class WalletLedgerLocalStore {
  WalletLedgerLocalStore._();

  static final instance = WalletLedgerLocalStore._();

  static const _dbName = 'wallet_ledger_local_v1.db';
  static const _recordsTable = 'wallet_ledger_records';
  static const _metaTable = 'wallet_ledger_sync_meta';

  Database? _db;
  bool _factoryReady = false;

  final Map<String, Map<String, Map<String, WalletRecordDto>>> _memory = {};
  final Map<String, Set<String>> _complete = {};

  bool get _useMemoryOnly => kIsWeb;

  Future<void> _ensureDatabaseFactory() async {
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
    await _ensureDatabaseFactory();
    final basePath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(basePath, _dbName),
      version: 1,
      onOpen: (db) async {
        // FFB-2 扩散：iOS sqflite_darwin 启动期 PRAGMA 救火。失败不阻断 DB open。
        await SqfliteBootstrapHelper.withTag('wallet').runOnOpenPragmas(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_recordsTable (
            owner_user_id TEXT NOT NULL,
            scope_key TEXT NOT NULL,
            record_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner_user_id, scope_key, record_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_wallet_ledger_records_scope '
          'ON $_recordsTable(owner_user_id, scope_key)',
        );
        await db.execute('''
          CREATE TABLE $_metaTable (
            owner_user_id TEXT NOT NULL,
            scope_key TEXT NOT NULL,
            complete INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner_user_id, scope_key)
          )
        ''');
      },
    );
    return _db!;
  }

  String currentOwnerUserId() {
    final fromContact =
        ChatIdFormat.rawUserUid(ContactSocialCacheStore.safeLoginUserId());
    if (fromContact.isNotEmpty) return fromContact;
    try {
      return ChatIdFormat.rawUserUid(
        TIMUIKitCore.getInstance().loginInfo.userID,
      );
    } catch (_) {
      return '';
    }
  }

  String _owner(String? ownerUserId) {
    final explicit = ChatIdFormat.rawUserUid(ownerUserId);
    return explicit.isNotEmpty ? explicit : currentOwnerUserId();
  }

  Map<String, WalletRecordDto> _memoryScope(String owner, String scopeKey) {
    return _memory.putIfAbsent(owner, () => {}).putIfAbsent(scopeKey, () => {});
  }

  Set<String> _memoryComplete(String owner) {
    return _complete.putIfAbsent(owner, () => <String>{});
  }

  Future<List<WalletRecordDto>> read({
    required String scopeKey,
    String? ownerUserId,
  }) async {
    final owner = _owner(ownerUserId);
    if (owner.isEmpty) return const [];

    final memory = _memoryScope(owner, scopeKey);
    if (memory.isNotEmpty || _useMemoryOnly) {
      return memory.values.toList(growable: false);
    }

    final db = await _openDb();
    final rows = await db.query(
      _recordsTable,
      columns: const ['record_id', 'payload'],
      where: 'owner_user_id = ? AND scope_key = ?',
      whereArgs: [owner, scopeKey],
    );
    for (final row in rows) {
      final id = row['record_id']?.toString() ?? '';
      final payload = row['payload']?.toString() ?? '';
      final record = _decodeRecord(payload);
      if (id.isNotEmpty && record != null) memory[id] = record;
    }
    return memory.values.toList(growable: false);
  }

  Future<bool> isComplete({
    required String scopeKey,
    String? ownerUserId,
  }) async {
    final owner = _owner(ownerUserId);
    if (owner.isEmpty) return false;
    if (_memoryComplete(owner).contains(scopeKey)) return true;
    if (_useMemoryOnly) return false;

    final db = await _openDb();
    final rows = await db.query(
      _metaTable,
      columns: const ['complete'],
      where: 'owner_user_id = ? AND scope_key = ?',
      whereArgs: [owner, scopeKey],
      limit: 1,
    );
    final complete = rows.isNotEmpty && rows.first['complete'] == 1;
    if (complete) _memoryComplete(owner).add(scopeKey);
    return complete;
  }

  Future<void> upsert({
    required String scopeKey,
    required Iterable<WalletRecordDto> records,
    String? ownerUserId,
  }) async {
    final owner = _owner(ownerUserId);
    if (owner.isEmpty) return;
    final batchRecords = records
        .where((record) => record.id.trim().isNotEmpty)
        .toList(growable: false);
    final memory = _memoryScope(owner, scopeKey);
    for (final record in batchRecords) {
      memory[record.id] = record;
    }

    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) return;

    final db = await _openDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final record in batchRecords) {
      batch.insert(
        _recordsTable,
        {
          'owner_user_id': owner,
          'scope_key': scopeKey,
          'record_id': record.id,
          'payload': jsonEncode(_encodeRecord(record)),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markComplete({
    required String scopeKey,
    String? ownerUserId,
  }) async {
    final owner = _owner(ownerUserId);
    if (owner.isEmpty) return;
    _memoryComplete(owner).add(scopeKey);
    if (_useMemoryOnly || !SqfliteLifecycleGuard.instance.writesAllowed) return;

    final db = await _openDb();
    await db.insert(
      _metaTable,
      {
        'owner_user_id': owner,
        'scope_key': scopeKey,
        'complete': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearForOwner(String? ownerUserId) async {
    final owner = _owner(ownerUserId);
    if (owner.isEmpty) return;
    _memory.remove(owner);
    _complete.remove(owner);
    await LedgerPageProgress.clear(owner);
    if (_useMemoryOnly) return;
    final db = await _openDb();
    await db
        .delete(_recordsTable, where: 'owner_user_id = ?', whereArgs: [owner]);
    await db.delete(_metaTable, where: 'owner_user_id = ?', whereArgs: [owner]);
  }

  Map<String, dynamic> _encodeRecord(WalletRecordDto record) => {
        'id': record.id,
        'type': record.type.name,
        'status': record.status.name,
        'title': record.title,
        'subTitle': record.subTitle,
        'amount': record.amount,
        'coin': record.coin,
        'income': record.income,
        'network': record.network,
        'fee': record.fee,
        'payer': record.payer,
        'payee': record.payee,
        'addr': record.addr,
        'hash': record.hash,
        'block': record.block,
        'time': record.time,
        'orderNo': record.orderNo,
        'serverOrderId': record.serverOrderId,
        'clientOrderId': record.clientOrderId,
        'memo': record.memo,
        'rpType': record.rpType,
        'rpCnt': record.rpCnt,
        'rpTotal': record.rpTotal,
        'rpClaim': record.rpClaim,
        'rpMsg': record.rpMsg,
        'rpStatus': record.rpStatus,
        'createdAt': record.createdAt,
        'expiredAt': record.expiredAt,
      };

  WalletRecordDto? _decodeRecord(String payload) {
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map) return null;
      final json = Map<String, dynamic>.from(raw);
      final id = json['id']?.toString() ?? '';
      if (id.isEmpty) return null;
      return WalletRecordDto(
        id: id,
        type: _enumValue(
            WalletRecordType.values, json['type'], WalletRecordType.all),
        status: _enumValue(
          WalletRecordStatus.values,
          json['status'],
          WalletRecordStatus.pending,
        ),
        title: json['title']?.toString() ?? '',
        subTitle: json['subTitle']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '',
        coin: json['coin']?.toString() ?? '',
        income: json['income'] == true,
        network: json['network']?.toString() ?? '',
        fee: json['fee']?.toString() ?? '',
        payer: json['payer']?.toString() ?? '',
        payee: json['payee']?.toString() ?? '',
        addr: json['addr']?.toString() ?? '',
        hash: json['hash']?.toString() ?? '',
        block: json['block']?.toString() ?? '',
        time: json['time']?.toString() ?? '',
        orderNo: json['orderNo']?.toString() ?? '',
        serverOrderId: json['serverOrderId']?.toString() ?? '',
        clientOrderId: json['clientOrderId']?.toString() ?? '',
        memo: json['memo']?.toString() ?? '',
        rpType: json['rpType']?.toString() ?? '',
        rpCnt: json['rpCnt']?.toString() ?? '',
        rpTotal: json['rpTotal']?.toString() ?? '',
        rpClaim: json['rpClaim']?.toString() ?? '',
        rpMsg: json['rpMsg']?.toString() ?? '',
        rpStatus: json['rpStatus']?.toString() ?? '',
        createdAt: json['createdAt']?.toString() ?? '',
        expiredAt: json['expiredAt']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
    final name = raw?.toString();
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
