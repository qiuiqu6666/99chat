import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/runtime_ingress_processor.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final core = MessageCoreStore.instance;
  late Directory dir;
  late String oldPath;
  late DurableIngressGateway gateway;
  late ImWriterLease lease;
  late EventEnvelope<void> event;
  final calls = <String>[];
  String? failAt;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    oldPath = await getDatabasesPath();
    dir = await Directory.systemTemp.createTemp('runtime-ingress-');
    await databaseFactory.setDatabasesPath(dir.path);
    final store = ConversationLocalImIngressStore(core: core);
    gateway = DurableIngressGateway(store: store);
    lease = (await ImWriterLeaseService(store: store).acquire(
        ownerUserId: 'owner', leaseOwnerId: 'test-writer', nowMs: 1000))!;
    event = (await gateway.append(ImIngressDraft<void>(
      eventId: 'event',
      eventNamespace: 'chat',
      kind: ImEventKind.notification,
      scope: AccountScopedConversationKey(
          ownerUserId: 'owner',
          conversationType: ImConversationType.c2c,
          conversationId: 'c2c_peer'),
      ownerUserId: 'owner',
      accountGeneration: 1,
      domainGeneration: 1,
      clearEpoch: 0,
      source: ImEventSource.sdkListener,
      authority: ImEventAuthority.provider,
      observedAtMs: 1000,
      payloadHash: 'metadata',
      recoveryMode: ImRecoveryMode.commandArguments,
      recoveryRef: 'metadata',
    )))
        .event;
    await gateway.claimForWriter(event: event, lease: lease, nowMs: 1001);
    await core.runTransaction((db) => db.execute(
        'CREATE TABLE runtime_test_metadata (event_id TEXT PRIMARY KEY)'));
    calls.clear();
    failAt = null;
  });
  tearDown(() async {
    await core.closeIfOpen();
    await databaseFactory
        .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
    await databaseFactory.setDatabasesPath(oldPath);
    if (!p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path)) {
      throw StateError('test cleanup escaped temporary directory');
    }
    await dir.delete(recursive: true);
  });

  Future<ImInboxStatus> checkpoint() => core.runTransaction((db) async {
        final rows = await db.query('message_event_inbox');
        return imInboxRecordFromStorageMap(rows.single).status;
      });
  Future<void> step(String name) async {
    calls.add(name);
    if (failAt == name) throw StateError(name);
  }

  Future<bool> run() async => const RuntimeIngressProcessor().run(
        status: await checkpoint(),
        isCurrent: () => true,
        applyMetadata: () async {
          await step('metadata');
          await core.runTransaction((db) => db.insert(
              'runtime_test_metadata', {'event_id': event.eventId},
              conflictAlgorithm: ConflictAlgorithm.ignore));
        },
        flushMetadata: () => step('flush'),
        advance: (from, to) => gateway.advanceForWriter(
            event: event,
            expectedStatus: from,
            nextStatus: to,
            lease: lease,
            nowMs: 1002),
        adoptOutgoing: () async {
          await step('adopt');
          return true;
        },
        publish: () => step('publish'),
        completeOutgoing: () => step('outbox'),
      );

  test('SQLite reopen resumes committed metadata without applying it twice',
      () async {
    failAt = 'adopt';
    await expectLater(run(), throwsStateError);
    expect(await checkpoint(), ImInboxStatus.metadataCommitted);
    expect(calls, isNot(contains('publish')));
    await core.closeIfOpen();
    calls.clear();
    failAt = null;
    expect(await run(), isTrue);
    expect(calls, ['adopt', 'publish', 'outbox']);
    expect(await checkpoint(), ImInboxStatus.completed);
    final count =
        await core.runTransaction((db) => db.query('runtime_test_metadata'));
    expect(count, hasLength(1));
  });
  test('SQLite reopen after projection does not publish the same event again',
      () async {
    failAt = 'outbox';
    await expectLater(run(), throwsStateError);
    expect(await checkpoint(), ImInboxStatus.projectionPublished);
    await core.closeIfOpen();
    calls.clear();
    failAt = null;
    expect(await run(), isTrue);
    expect(calls, ['adopt', 'outbox']);
    expect(await checkpoint(), ImInboxStatus.completed);
  });
  test('metadata failure leaves Inbox processing and never publishes',
      () async {
    failAt = 'metadata';
    await expectLater(run(), throwsStateError);
    await core.closeIfOpen();
    expect(await checkpoint(), ImInboxStatus.processing);
    final rows =
        await core.runTransaction((db) => db.query('runtime_test_metadata'));
    expect(rows, isEmpty);
    expect(calls, ['metadata']);
  });
}
