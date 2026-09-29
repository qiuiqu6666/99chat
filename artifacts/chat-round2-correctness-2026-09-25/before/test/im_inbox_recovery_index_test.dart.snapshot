import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_inbox_recovery_query.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'recovery uses pending-only ordered index and repairs existing databases',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final dir =
        await Directory.systemTemp.createTemp('message-recovery-index-');
    await databaseFactory.setDatabasesPath(dir.path);
    final core = MessageCoreStore.instance;
    final store = ConversationLocalImIngressStore(core: core);
    final gateway = DurableIngressGateway(store: store);
    try {
      for (var i = 0; i < 10; i++) {
        await gateway.append(ImIngressDraft<String>(
            eventId: 'e$i',
            eventNamespace: 'chat',
            kind: ImEventKind.notification,
            ownerUserId: 'owner',
            accountGeneration: 2,
            domainGeneration: i == 8 ? 4 : 3,
            clearEpoch: 0,
            source: ImEventSource.sdkListener,
            authority: ImEventAuthority.provider,
            observedAtMs: 1,
            payloadHash: '$i',
            recoveryMode: ImRecoveryMode.commandArguments,
            recoveryRef: 'test',
            payload: 'test'));
      }
      await core.runTransaction((db) async {
        for (final entry in <int, String>{
          0: 'completed',
          1: 'prepared',
          2: 'metadataCommitted',
          3: 'projectionPublished',
          4: 'processing',
          5: 'processing',
          6: 'processing',
          7: 'completed',
          8: 'prepared',
          9: 'prepared'
        }.entries) {
          await db.update(
              'message_event_inbox',
              {
                'status': entry.value,
                'processing_started_at':
                    entry.key == 4 ? null : (entry.key == 5 ? 600 : 900)
              },
              where: 'event_id = ?',
              whereArgs: ['e${entry.key}']);
        }
        // A large completed tail must neither appear nor inflate recovery scans.
        await db.execute(
            '''WITH RECURSIVE seq(x) AS (SELECT 11 UNION ALL SELECT x+1 FROM seq WHERE x<10010)
          INSERT INTO message_event_inbox (owner_user_id,event_id,event_namespace,event_kind,
            account_generation,domain_generation,source,authority,clear_epoch,account_ingress_sequence,
            scope_ingress_sequence,payload_hash,recovery_mode,status,observed_at)
          SELECT 'owner','done'||x,'chat','notification',2,3,'sdkListener','provider',0,x,0,'h','ephemeralUi','completed',1 FROM seq''');
      });
      Future<List<ImInboxRecord>> recover({int? domain = 3, int limit = 100}) =>
          store.transaction((tx) => tx.listInboxForRecovery(
              ownerUserId: 'owner',
              accountGeneration: 2,
              domainGeneration: domain,
              nowMs: 1000,
              processingTimeoutMs: 300,
              limit: limit));
      expect((await recover()).map((r) => r.event.eventId),
          ['e1', 'e2', 'e3', 'e4', 'e5', 'e9']);
      await core.runTransaction((db) async {
        await db.update(
          'message_event_inbox',
          {'next_retry_at': 5000000},
          where: "event_id IN ('e2','e3','e9')",
        );
      });
      expect((await recover()).map((r) => r.event.eventId),
          ['e1', 'e4', 'e5']);
      await core.runTransaction((db) async {
        await db.update(
          'message_event_inbox',
          {'next_retry_at': 0},
          where: "event_id IN ('e2','e3','e9')",
        );
      });
      expect(
          (await recover(limit: 2)).map((r) => r.event.eventId), ['e1', 'e2']);
      expect((await recover(domain: null)).map((r) => r.event.eventId),
          ['e1', 'e2', 'e3', 'e4', 'e5', 'e8', 'e9']);
      for (final domain in <int?>[3, null]) {
        final plan = await core.runTransaction((db) => db.rawQuery(
            'EXPLAIN QUERY PLAN SELECT * FROM message_event_inbox WHERE '
            '${ImInboxRecoveryQuery.where(hasDomainGeneration: domain != null)} '
            'ORDER BY ${ImInboxRecoveryQuery.orderBy} LIMIT 100',
            ImInboxRecoveryQuery.arguments(
                ownerUserId: 'owner',
                accountGeneration: 2,
                domainGeneration: domain,
                nowMs: 1000,
                staleBeforeMs: 700)));
        final details = plan.map((r) => r['detail']).join('\n');
        expect(details, contains(ImInboxRecoveryQuery.indexName));
        expect(details, isNot(contains('TEMP B-TREE')));
      }
      await core.runTransaction(
          (db) => db.execute('DROP INDEX ${ImInboxRecoveryQuery.indexName}'));
      await core.closeIfOpen();
      expect(
          await core.runTransaction((db) => db.rawQuery(
              "SELECT name FROM sqlite_master WHERE name = ?",
              [ImInboxRecoveryQuery.indexName])),
          hasLength(1));
      expect((await recover()).length, 6);
    } finally {
      await core.closeIfOpen();
      await databaseFactory
          .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
      await databaseFactory.setDatabasesPath(original);
      await dir.delete();
    }
  });
}
