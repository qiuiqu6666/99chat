import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'sqflite_lifecycle_guard.dart';

/// Capability only. Enable after W7 lifecycle and W8 explicit-consent migration.
/// W8 is excluded from the current release, so production uses the legacy path.
class PhotoBackupProgressStore {
  PhotoBackupProgressStore({this.databasePath});
  static final instance = PhotoBackupProgressStore();
  static const bool enabled = false;
  static const int policyVersion = 1;
  final String? databasePath;
  Database? _db;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Database> _database() async {
    final existing = SqfliteLifecycleGuard.beforeOpen(_db);
    if (existing != null) return existing;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = databasePath ??
        p.join(await getDatabasesPath(), 'photo_backup_progress_v1.db');
    SqfliteLifecycleGuard.beforeOpen(null);
    final opened =
        await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE progress (owner TEXT NOT NULL, asset TEXT NOT NULL, '
          'version TEXT NOT NULL, status TEXT NOT NULL, policy INTEGER NOT NULL, PRIMARY KEY(owner, asset))');
      await db.execute('CREATE TABLE migration (owner TEXT PRIMARY KEY)');
    });
    // Retain the handle for a serialized close even if the background gate
    // changed while native open was in progress.
    _db = opened;
    SqfliteLifecycleGuard.beforeOpen(opened);
    return opened;
  }

  void _requireWrite(bool Function()? isCurrent) {
    if (!SqfliteLifecycleGuard.instance.writesAllowed ||
        (isCurrent != null && !isCurrent()))
      throw const SqfliteClosedForBackground();
  }

  Future<Map<String, String>> readOwner(String owner) => _serial(() async {
        final db = await _database();
        final rows = await db.query('progress',
            where: 'owner = ? AND policy = ?',
            whereArgs: [owner, policyVersion]);
        return {
          for (final row in rows)
            row['asset'] as String: row['version'] as String
        };
      });

  Future<void> record(
    String owner,
    String asset,
    String version, {
    required String status,
    bool Function()? isCurrent,
  }) =>
      _serial(() async {
        _requireWrite(isCurrent);
        final db = await _database();
        _requireWrite(isCurrent);
        await db.insert(
            'progress',
            {
              'owner': owner,
              'asset': asset,
              'version': version,
              'status': status,
              'policy': policyVersion
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<void> migrateLegacy(
    String owner,
    Map<String, String> snapshot, {
    bool Function()? isCurrent,
  }) =>
      _serial(() async {
        _requireWrite(isCurrent);
        final db = await _database();
        _requireWrite(isCurrent);
        await db.transaction((txn) async {
          if ((await txn
                  .query('migration', where: 'owner = ?', whereArgs: [owner]))
              .isNotEmpty) return;
          final entries = snapshot.entries.toList();
          for (var start = 0; start < entries.length; start += 250) {
            _requireWrite(isCurrent);
            final batch = txn.batch();
            for (final row in entries.skip(start).take(250)) {
              batch.insert(
                  'progress',
                  {
                    'owner': owner,
                    'asset': row.key,
                    'version': row.value,
                    'status': 'legacy_complete',
                    'policy': policyVersion
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            await batch.commit(noResult: true);
          }
          _requireWrite(isCurrent);
          await txn.insert('migration', {'owner': owner});
        });
      });

  Future<void> clearForOwner(String owner) => _serial(() async {
        if (!enabled && _db == null) return;
        _requireWrite(null);
        final db = await _database();
        _requireWrite(null);
        await db.transaction((txn) async {
          await txn.delete('progress', where: 'owner = ?', whereArgs: [owner]);
          await txn.delete('migration', where: 'owner = ?', whereArgs: [owner]);
        });
      });

  Future<void> closeIfOpen() => _serial(() async {
        final db = _db;
        await SqfliteLifecycleGuard.closeDatabase(db);
        if (identical(_db, db)) _db = null;
      });
}
