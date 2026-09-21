import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

const _scope = HistoryWindowScope(
  ownerUserID: 'owner',
  accountGeneration: 1,
  domainGeneration: 1,
  conversationID: 'c2c_peer',
  clearEpoch: 0,
  sessionID: 'session',
);

V2TimMessage _message(String id) => V2TimMessage.fromJson({
      'message_msg_id': id,
      'message_seq': 1,
      'message_server_time': 1,
      'message_risk_type_identified': 0,
    })
      ..isSelf = false
      ..isRead = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  late String path;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('deferred-source-order-');
    path = p.join(directory.path, 'history.db');
    store = HistoryWindowStore(debugDatabasePath: path);
  });

  tearDown(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    await store.closeIfOpen();
    await directory.delete(recursive: true);
  });

  Future<HistoryWindowDeferredReceipt> append(String event, int sequence,
          {bool formal = true}) =>
      store.appendDeferred(
        scope: _scope,
        eventID: event,
        ingressSequence: sequence,
        hasStableIngressSequence: formal,
        message: _message(event),
      );

  Future<void> ack(int ordinal) =>
      store.acknowledgeDeferred(scope: _scope, throughIngressSequence: ordinal);

  Future<Database> downgradeExtension() async {
    await store.closeIfOpen();
    final db = await openDatabase(path, version: 3);
    await db.execute('DROP INDEX hw_deferred_source');
    await db.execute('DROP INDEX hw_deferred_legacy_source');
    await db.execute('ALTER TABLE hw_deferred DROP COLUMN source_sequence');
    await db.execute(
        'ALTER TABLE hw_deferred_state DROP COLUMN acknowledged_source_sequence');
    await db.execute(
        'ALTER TABLE hw_deferred_state DROP COLUMN last_message_timestamp');
    await db.execute(
        'ALTER TABLE hw_deferred_state DROP COLUMN last_group_message_seq');
    return db;
  }

  test('fallback ACK does not consume the next independent formal sequence',
      () async {
    await append('formal100', 100);
    final fallback = await append('fallback', 101, formal: false);
    expect(fallback.state.lastIngressSequence, 101);
    await ack(101);
    final next = await append('formal101', 101);
    expect(next.inserted, isTrue);
    expect(next.state.receivedCount, 1);
    expect(next.state.unreadCount, 1);
    expect(next.state.lastIngressSequence, 102);
    expect((await append('formal100', 100)).inserted, isFalse);
    expect((await append('other-event-same-source', 101)).inserted, isFalse);
    await ack(102);
    await store.closeIfOpen();
    expect((await append('formal101', 101)).inserted, isFalse);
    expect((await store.deferredState(_scope)).receivedCount, 0);
  });

  test('captured newest snapshot leaves later formal and fallback arrivals',
      () async {
    await append('formal100', 100);
    final snapshot = (await append('fallback1', 0, formal: false))
        .state
        .lastIngressSequence!;
    await append('formal101', 101);
    await append('fallback2', 0, formal: false);
    await ack(snapshot);
    final state = await store.deferredState(_scope);
    expect(state.receivedCount, 2);
    expect(state.firstIngressSequence, 102);
    expect(state.lastIngressSequence, 103);
    expect((await store.readDeferredTail(scope: _scope)).map((m) => m.msgID),
        ['fallback2', 'formal101']);
  });

  test('fallback ignores synthetic sequence and survives reopen after full ACK',
      () async {
    final first = await append('fallback1', 1000000, formal: false);
    expect(first.state.lastIngressSequence, 1);
    await ack(1);
    await store.closeIfOpen();
    final second = await append('fallback2', 0, formal: false);
    expect(second.inserted, isTrue);
    expect(second.state.lastIngressSequence, 2);
    final firstFormal = await append('formal1', 1);
    expect(firstFormal.inserted, isTrue);
    expect(firstFormal.state.lastIngressSequence, 3);
    expect(firstFormal.state.receivedCount, 2);
  });

  test('pending event and formal sequence dedup do not advance snapshot order',
      () async {
    await append('formal10', 10);
    expect((await append('formal10', 100)).inserted, isFalse);
    expect((await append('duplicate-source', 10)).inserted, isFalse);
    final fallback = await append('fallback', 0, formal: false);
    expect(fallback.state.lastIngressSequence, 11);
    expect((await append('fallback', 900, formal: false)).inserted, isFalse);
    expect((await store.deferredState(_scope)).receivedCount, 2);
    await ack(11);
    expect((await append('formal11', 11)).inserted, isTrue);
  });

  test(
      'real v3 additive migration keeps pending bodies and conservatively retains unknown old source fences',
      () async {
    await append('formal99', 99);
    await ack(99);
    await append('received:formal100', 100);
    await append('received:legacy-fallback', 0, formal: false);
    final legacy = await downgradeExtension();
    expect(await legacy.getVersion(), 3);
    await legacy.close();

    final state = await store.deferredState(_scope);
    expect(state.receivedCount, 2);
    expect(state.lastIngressSequence, 101);
    expect((await store.readDeferredTail(scope: _scope)).map((m) => m.msgID),
        ['received:legacy-fallback', 'received:formal100']);
    expect((await append('received:formal100-replay', 100)).inserted, isFalse);
    await ack(101);
    // Legacy fallback source identity was never recorded, so its old fence
    // cannot be safely lowered. Fresh explicit-source databases avoid this.
    expect((await append('formal101', 101)).inserted, isFalse);
    final next = await append('formal102', 102);
    expect(next.inserted, isTrue);
    expect(next.state.lastIngressSequence, 102);
    expect((await append('formal99', 99)).inserted, isFalse);
    await store.closeIfOpen();
    final inspect = await openDatabase(path, version: 3);
    expect(await inspect.getVersion(), 3);
    expect((await inspect.query('hw_deferred')).length, 1);
    await inspect.close();
  });

  test(
      'actual received-prefixed formal IDs retain replay protection after migration',
      () async {
    await append('received:server-message-100', 100);
    final legacy = await downgradeExtension();
    await legacy.close();
    expect((await append('received:replay-100', 100)).inserted, isFalse);
    await ack(100);
    expect((await append('received:replay-100', 100)).inserted, isFalse);
    expect((await append('received:new-message-101', 101)).inserted, isTrue);
  });

  test(
      'legacy fully ACKed fence remains conservative when source was discarded',
      () async {
    await append('formal100', 100);
    await append('received:legacy-fallback', 0, formal: false);
    await ack(101);
    final legacy = await downgradeExtension();
    await legacy.close();
    // v3 already discarded the source identity of this ACK. Do not resurrect
    // earlier formal deliveries by guessing which part came from a fallback.
    expect((await append('formal100-replay', 100)).inserted, isFalse);
    expect((await append('formal102', 102)).inserted, isTrue);
  });

  test(
      'legacy inserts after extension are classified on reopen without version bump',
      () async {
    await append('formal100', 100);
    await store.closeIfOpen();
    final legacy = await openDatabase(path, version: 3);
    final previous = (await legacy.query('hw_deferred')).single;
    await legacy.insert('hw_deferred', {
      'bucket': previous['bucket'],
      'event_id': 'formal101-from-old-binary',
      'ingress_sequence': 101,
      'account_generation': 1,
      'domain_generation': 1,
      'msg_id': 'legacy101',
      'unread': 1,
      'payload': previous['payload'],
    });
    await legacy.rawUpdate(
        'UPDATE hw_deferred_state SET received=2,unread=2,last_seq=101,last_id=?',
        ['legacy101']);
    await legacy.close();
    expect((await append('formal101-replay', 101)).inserted, isFalse);
    expect((await store.deferredState(_scope)).receivedCount, 2);
    await ack(101);
    expect((await append('formal101-replay', 101)).inserted, isFalse);
    expect((await append('formal102', 102)).inserted, isTrue);
  });

  test(
      'legacy duplicate formal source cannot prevent reopening additive schema',
      () async {
    await append('formal100', 100);
    await append('fallback', 0, formal: false);
    await append('formal101', 101);
    await ack(101);
    await store.closeIfOpen();
    final legacy = await openDatabase(path, version: 3);
    final previous = (await legacy.query('hw_deferred')).single;
    await legacy.insert('hw_deferred', {
      'bucket': previous['bucket'],
      'event_id': 'legacy-replay101',
      'ingress_sequence': 101,
      'account_generation': 1,
      'domain_generation': 1,
      'msg_id': 'legacy101',
      'unread': 1,
      'payload': previous['payload'],
    });
    await legacy.rawUpdate(
        'UPDATE hw_deferred_state SET received=2,unread=2,first_seq=101,first_id=?',
        ['legacy101']);
    await legacy.close();
    // The old writer did not preserve source/ordinal semantics. Keep every
    // pending body and open normally instead of letting backfill hit UNIQUE.
    expect((await store.deferredState(_scope)).receivedCount, 2);
    expect(await store.readDeferredTail(scope: _scope), hasLength(2));
    expect((await append('formal101-replay', 101)).inserted, isFalse);
    await ack(102);
    expect((await append('formal101-replay', 101)).inserted, isFalse);
    expect((await append('formal102', 102)).inserted, isTrue);
  });
}
