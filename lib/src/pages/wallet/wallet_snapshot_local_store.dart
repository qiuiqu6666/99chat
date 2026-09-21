import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/sqflite_bootstrap_helper.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';

import 'wallet_repository.dart';

/// Display snapshots only; spending still uses the server's validation.
class WalletSnapshotLocalStore {
  WalletSnapshotLocalStore({this.databasePath});
  static final instance = WalletSnapshotLocalStore();
  final String? databasePath;
  Database? _db;
  Future<Database>? _opening;

  Future<Database> _database() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) return existing;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = databasePath ??
        p.join(await getDatabasesPath(), 'wallet_snapshot_v1.db');
    return _db = await openDatabase(path, version: 1, onOpen: (db) async {
      await SqfliteBootstrapHelper.withTag('wallet_snapshot')
          .runOnOpenPragmas(db);
    }, onCreate: (db, _) async {
      await db.execute('CREATE TABLE wallet_snapshot ('
          'owner TEXT PRIMARY KEY, payload TEXT NOT NULL)');
    });
  }

  Future<WalletDto?> read(String owner) async {
    if (kIsWeb || owner.isEmpty) return null;
    try {
      final rows = await (await _database()).query('wallet_snapshot',
          where: 'owner = ?', whereArgs: [owner], limit: 1);
      if (rows.isEmpty) return null;
      final data = jsonDecode(rows.single['payload'] as String) as Map;
      return WalletDto(
        totalBal: data['totalBal'] as String,
        totalBalUsd: data['totalBalUsd'] as String,
        trxAddr: data['trxAddr'] as String,
        coins: (data['coins'] as List).map((raw) {
          final c = raw as Map;
          return CoinDto(
            name: c['name'] as String,
            sub: c['sub'] as String,
            bal: c['bal'] as String,
            fiat: c['fiat'] as String,
            type: CoinType.values.byName(c['type'] as String),
            code: c['code'] as String,
            logoUrl: c['logoUrl'] as String?,
            platformCoin: c['platformCoin'] as bool,
            depositEnabled: c['depositEnabled'] as bool,
            withdrawEnabled: c['withdrawEnabled'] as bool,
            balMinor: c['balMinor'] as int,
            scale: c['scale'] as int,
            priceChangePercent: (c['priceChangePercent'] as num?)?.toDouble(),
          );
        }).toList(growable: false),
      );
    } catch (_) {
      // A missing or damaged cache must never block the network refresh.
      return null;
    }
  }

  Future<void> write(String owner, WalletDto wallet) async {
    if (kIsWeb || owner.isEmpty) return;
    final payload = jsonEncode({
      'totalBal': wallet.totalBal,
      'totalBalUsd': wallet.totalBalUsd,
      'trxAddr': wallet.trxAddr,
      'coins': wallet.coins
          .map((c) => {
                'name': c.name,
                'sub': c.sub,
                'bal': c.bal,
                'fiat': c.fiat,
                'type': c.type.name,
                'code': c.code,
                'logoUrl': c.logoUrl,
                'platformCoin': c.platformCoin,
                'depositEnabled': c.depositEnabled,
                'withdrawEnabled': c.withdrawEnabled,
                'balMinor': c.balMinor,
                'scale': c.scale,
                'priceChangePercent': c.priceChangePercent,
              })
          .toList(),
    });
    await (await _database()).insert(
        'wallet_snapshot', {'owner': owner, 'payload': payload},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) await opening;
    await _db?.close();
    _db = null;
  }
}
