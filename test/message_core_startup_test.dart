import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy rows migrate in batches and migration is not replayed',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final dir =
        await Directory.systemTemp.createTemp('message-core-migration-');
    await databaseFactory.setDatabasesPath(dir.path);
    final store = MessageCoreStore.instance;
    final legacyPath = p.join(dir.path, 'conversation_local_v1.db');
    final legacy = await openDatabase(legacyPath);
    try {
      await legacy.execute('CREATE TABLE message_writer_lease ('
          'owner_user_id TEXT PRIMARY KEY, lease_owner_id TEXT NOT NULL, '
          'fencing_token INTEGER NOT NULL, acquired_at INTEGER NOT NULL, '
          'expires_at INTEGER NOT NULL, heartbeat_at INTEGER NOT NULL)');
      final batch = legacy.batch();
      for (var i = 0; i < 505; i++) {
        batch.insert('message_writer_lease', {
          'owner_user_id': 'owner_$i',
          'lease_owner_id': 'legacy',
          'fencing_token': 7,
          'acquired_at': 1,
          'expires_at': 2,
          'heartbeat_at': 1,
        });
      }
      await batch.commit(noResult: true);
      final rows =
          await store.runTransaction((db) => db.query('message_writer_lease'));
      expect(rows, hasLength(505));
      expect(rows.every((r) => r['fencing_token'] == 7), isTrue);
      await store.runTransaction((db) => db.delete('message_writer_lease'));
      await store.closeIfOpen();
      expect(
          await store.runTransaction((db) => db.query('message_writer_lease')),
          isEmpty);
    } finally {
      await store.closeIfOpen();
      await legacy.close();
      await databaseFactory.deleteDatabase(legacyPath);
      await databaseFactory
          .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
      await databaseFactory.setDatabasesPath(original);
      await dir.delete();
    }
  });

  test('core open is shared, migrations settle and missing indexes recover',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final dir = await Directory.systemTemp.createTemp('message-core-startup-');
    await databaseFactory.setDatabasesPath(dir.path);
    final store = MessageCoreStore.instance;
    try {
      final counts = await Future.wait(List.generate(
          4,
          (_) => store.runTransaction((db) => db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type IN ('table','index')"))));
      expect(
          counts.every(
              (rows) => rows.any((r) => r['name'] == 'message_writer_lease')),
          isTrue);
      final marker =
          await store.runTransaction((db) => db.query('message_core_meta'));
      expect(marker.single['value'], 'complete');
      await store.runTransaction((db) async {
        await db.execute('DROP INDEX idx_message_outbox_ready');
        await db
            .insert('message_core_meta', {'key': 'test_data', 'value': 'keep'});
      });
      await store.closeIfOpen();
      final repaired = await store.runTransaction((db) => db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name='idx_message_outbox_ready'"));
      expect(repaired, hasLength(1));
      await store.closeIfOpen();
      final preserved = await store.runTransaction((db) => db.query(
          'message_core_meta',
          where: 'key = ?',
          whereArgs: ['test_data']));
      expect(preserved.single['value'], 'keep');
    } finally {
      await store.closeIfOpen();
      await databaseFactory
          .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
      await databaseFactory.setDatabasesPath(original);
      await dir.delete();
    }
  });
}
