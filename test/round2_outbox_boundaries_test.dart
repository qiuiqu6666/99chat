import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outbox_retry_identity.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every committed canonical send state has a newer version', () async {
    final f = await _Fixture.create();
    final prepared = await f.read();
    final intent = await f.intent();
    final dispatch = await f.read();
    await f.persistence.transitionOutbox(
        next: intent.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 12);
    final sending = await f.read();
    expect(dispatch.stateVersion, greaterThan(prepared.stateVersion));
    expect(sending.stateVersion, greaterThan(dispatch.stateVersion));
  });

  test('terminal truth survives recovery payload garbage collection', () async {
    final f = await _Fixture.create();
    await f.send();
    final success = await f.result(true);
    await f.persistence.completeOutboxProjection(
        ownerUserId: 'alice',
        operationId: 'op',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 22);
    final version = (await f.read()).stateVersion;
    (f.store as InMemoryImIngressStore).outboxRecoveryCopies.clear();
    final restored = await f.read();
    expect(restored.deliveryConfirmed, isTrue);
    expect(restored.canRetry, isFalse);
    expect(restored.stateVersion, greaterThanOrEqualTo(version));
    expect(restored.stateVersion, greaterThan(success.stateVersion));
  });

  test('committed success actively notifies an already displayed failure',
      () async {
    final f = await _Fixture.create();
    await f.send();
    final view = f.persistence.watchOutboxResult('alice', 'op');
    await f.result(false);
    var notifications = 0;
    final dynamic observable = view;
    expect(view, isA<Listenable>());
    void onChange() => notifications++;
    observable.addListener(onChange);
    await f.persistence.adoptOutboxProviderSucceeded(
        ownerUserId: 'alice',
        operationId: 'op',
        clientCorrelationId: 'corr',
        conversationId: 'alice|c2c_bob',
        payloadHash: 'hash',
        leaseOwnerId: 'writer',
        fencingToken: f.lease.fencingToken,
        nowMs: 24,
        serverMsgId: 'server');
    expect(notifications, greaterThan(0));
    expect(view.current!.deliveryConfirmed, isTrue);
    observable.removeListener(onChange);
  });

  test('a caller timeout cannot release the SDK draft write queue', () async {
    final first = Completer<int>();
    var calls = 0;
    String? sdk;
    final service = ConversationDraftService.forTesting(
        ownerForTest: () => 'alice',
        writeForTest: (_, value) async {
          calls++;
          if (calls == 1) await first.future;
          sdk = value;
          return 0;
        },
        readForTest: (_) async => sdk,
        commitForTest: (_, __) async {});
    var edit = service.beginEditing('c2c_bob');
    edit = service.recordEdit(edit, 'A')!;
    final a = service.persistDraft(
        conversationID: 'c2c_bob', rawInputText: 'A', expectedEdit: edit);
    await expectLater(
        a.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    edit = service.recordEdit(edit, 'B')!;
    final b = service.persistDraft(
        conversationID: 'c2c_bob', rawInputText: 'B', expectedEdit: edit);
    await Future<void>.value();
    expect(calls, 1);
    first.complete(0);
    await Future.wait([a, b]);
    expect(calls, 2);
    expect(
        await service.loadDraftText(
            conversationID: 'c2c_bob', expectedEdit: edit),
        'B');
  });

  test('storage error is unavailable, never legacy missing or retry permission',
      () async {
    final result = await Im05Persistence(store: _UnavailableStore())
        .readOutboxResult(ownerUserId: 'alice', operationId: 'op');
    expect(result.decision, ImOutboxResultDecision.unavailable);
    expect(result.canRetry, isFalse);
    expect(result.reason, contains('storage_unavailable'));
  });

  test(
      'SQLite commit failure emits nothing; two adapters share committed truth and GC version',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final directory = await Directory.systemTemp.createTemp('round2-commit-');
    final core = MessageCoreStore.instance;
    await core.closeIfOpen();
    await databaseFactory.setDatabasesPath(directory.path);
    try {
      final firstStore = ConversationLocalImIngressStore(core: core);
      final f = await _Fixture.create(store: firstStore);
      await f.send();
      final second =
          Im05Persistence(store: ConversationLocalImIngressStore(core: core));
      final view = second.watchOutboxResult('alice', 'op');
      final before = await second.readOutboxResult(
          ownerUserId: 'alice', operationId: 'op');
      var changes = 0;
      view.addListener(() => changes++);
      // Same SQLite handle; enable FK enforcement outside a transaction.
      var db =
          await openDatabase('${directory.path}/${MessageCoreStore.dbName}');
      print('commit_probe: handle');
      await db.execute('PRAGMA foreign_keys=ON');
      await db.execute('CREATE TABLE commit_parent(id INTEGER PRIMARY KEY)');
      await db.execute(
          'CREATE TABLE commit_child(id INTEGER REFERENCES commit_parent(id) DEFERRABLE INITIALLY DEFERRED)');
      await db.execute(
          "CREATE TRIGGER fail_at_commit AFTER UPDATE ON message_outbox WHEN NEW.state='acknowledged' BEGIN INSERT INTO commit_child VALUES(999); END");
      print('commit_probe: armed');
      await expectLater(f.result(true), throwsA(anything));
      print('commit_probe: rejected');
      expect(changes, 0);
      final after = await f.read();
      print('commit_probe: readable');
      db = await openDatabase('${directory.path}/${MessageCoreStore.dbName}');
      expect(after.stateVersion, before.stateVersion);
      expect(after.currentState, ImOutboxState.sending);
      expect((await db.rawQuery('SELECT * FROM commit_child')), isEmpty);
      await db.execute('DROP TRIGGER fail_at_commit');
      await f.result(true);
      expect(view.current!.deliveryConfirmed, isTrue);
      expect(changes, 1);
      final confirmedVersion = view.current!.stateVersion;
      await db.delete('message_outbox_recovery_copy');
      final withoutPayload = await second.readOutboxResult(
          ownerUserId: 'alice', operationId: 'op');
      expect(withoutPayload.deliveryConfirmed, isTrue);
      expect(withoutPayload.stateVersion, greaterThan(confirmedVersion));
      await core.closeIfOpen();
      final reopened = await Im05Persistence(
              store: ConversationLocalImIngressStore(core: core))
          .readOutboxResult(ownerUserId: 'alice', operationId: 'op');
      expect(reopened.deliveryConfirmed, isTrue);
      expect(reopened.stateVersion, withoutPayload.stateVersion);
    } finally {
      await core.closeIfOpen();
      await databaseFactory
          .deleteDatabase('${directory.path}/${MessageCoreStore.dbName}');
      await databaseFactory.setDatabasesPath(original);
      await directory.delete();
    }
  });

  test('concurrent same-operation attempts get exactly one SDK dispatch permit',
      () async {
    final f = await _Fixture.create();
    final other = Im05Persistence(store: f.store);
    var sdkCalls = 0;
    Future<void> attempt(Im05Persistence persistence, String attempt) async {
      final permit = await persistence.recordDispatchIntent(
          ownerUserId: 'alice',
          operationId: 'op',
          dispatchAttemptId: attempt,
          leaseOwnerId: 'writer',
          fencingToken: f.lease.fencingToken,
          nowMs: 11);
      if (permit.canDispatch) sdkCalls++;
    }

    await Future.wait([attempt(f.persistence, 'one'), attempt(other, 'two')]);
    expect(sdkCalls, 1);
    expect((await f.read()).canRetry, isFalse);
  });

  test('two SQLite adapters admit only one retry child across key formats',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final directory =
        await Directory.systemTemp.createTemp('round3-retry-race-');
    final core = MessageCoreStore.instance;
    await core.closeIfOpen();
    await databaseFactory.setDatabasesPath(directory.path);
    try {
      final firstStore = ConversationLocalImIngressStore(core: core);
      final secondStore = ConversationLocalImIngressStore(core: core);
      final f = await _Fixture.create(store: firstStore);
      await f.send();
      await f.result(false);
      final parent = (await f.read()).main!;
      final stable = outboxRetryOperationId(parent)!;
      final legacy = legacyOutboxRetryOperationId(
          'alice', parent.operationId, parent.stateVersion);
      Future<ImOutboxDispatchAssessment> prepare(
              Im05Persistence persistence, String operation) =>
          persistence.prepareOutbox(
              main: ImOutboxRecord(
                  operationId: operation,
                  ownerUserId: 'alice',
                  conversationId: 'alice|c2c_bob',
                  clientCorrelationId: 'corr-$operation',
                  messageType: 1,
                  payloadReference: 'encrypted',
                  payloadHash: 'hash',
                  state: ImOutboxState.prepared,
                  createdAtMs: 21,
                  updatedAtMs: 21,
                  retryOfOperationId: 'op',
                  retryOfStateVersion: parent.stateVersion),
              recoveryCopy: ImOutboxRecoveryRecord(
                  ownerUserId: 'alice',
                  operationId: operation,
                  clientCorrelationId: 'corr-$operation',
                  conversationId: 'alice|c2c_bob',
                  messageType: 1,
                  recoveryRevision: 1,
                  state: ImOutboxCopyState.copyPrepared,
                  payloadReferenceOrCiphertext: 'encrypted',
                  payloadHash: 'hash',
                  checksum: 'hash',
                  updatedAtMs: 21),
              leaseOwnerId: 'writer',
              fencingToken: f.lease.fencingToken,
              nowMs: 21);
      final results = await Future.wait([
        prepare(f.persistence, stable),
        prepare(Im05Persistence(store: secondStore), legacy)
      ]);
      expect(results.where((result) => result.canDispatch), hasLength(1));
      expect(
          results.where((result) =>
              result.decision == ImOutboxDispatchDecision.recoveryConflict),
          hasLength(1));
    } finally {
      await core.closeIfOpen();
      await databaseFactory
          .deleteDatabase('${directory.path}/${MessageCoreStore.dbName}');
      await databaseFactory.setDatabasesPath(original);
      await directory.delete();
    }
  });

  test('a zero-row recovery update rolls back the main outcome transition',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final original = await getDatabasesPath();
    final directory = await Directory.systemTemp.createTemp('round2-cas-');
    final core = MessageCoreStore.instance;
    await core.closeIfOpen();
    await databaseFactory.setDatabasesPath(directory.path);
    try {
      final f = await _Fixture.create(
          store: ConversationLocalImIngressStore(core: core));
      await f.send();
      final before = await f.read();
      final db =
          await openDatabase('${directory.path}/${MessageCoreStore.dbName}');
      await db.execute(
          "CREATE TRIGGER ignore_copy BEFORE UPDATE ON message_outbox_recovery_copy BEGIN SELECT RAISE(IGNORE); END");
      await expectLater(
          f.persistence.recordOutcomeUnknown(
              ownerUserId: 'alice',
              operationId: 'op',
              leaseOwnerId: 'writer',
              fencingToken: f.lease.fencingToken,
              nowMs: 30),
          throwsStateError);
      final after = await f.read();
      expect(after.currentState, before.currentState);
      expect(after.stateVersion, before.stateVersion);
    } finally {
      await core.closeIfOpen();
      await databaseFactory
          .deleteDatabase('${directory.path}/${MessageCoreStore.dbName}');
      await databaseFactory.setDatabasesPath(original);
      await directory.delete();
    }
  });
}

class _UnavailableStore implements ImIngressStore {
  @override
  Future<T> transaction<T>(Future<T> Function(ImIngressTransaction) action,
          {MessagePersistPriority persistPriority =
              MessagePersistPriority.realtime}) =>
      Future.error(StateError('injected read fault'));
}

class _Fixture {
  _Fixture(this.store, this.persistence, this.lease);
  final ImIngressStore store;
  final Im05Persistence persistence;
  final ImWriterLease lease;
  static Future<_Fixture> create({ImIngressStore? store}) async {
    store ??= InMemoryImIngressStore();
    final persistence = Im05Persistence(store: store);
    final lease = (await ImWriterLeaseService(store: store).acquire(
        ownerUserId: 'alice',
        leaseOwnerId: 'writer',
        nowMs: 10,
        ttlMs: 100000))!;
    await persistence.prepareOutbox(
        main: const ImOutboxRecord(
            operationId: 'op',
            ownerUserId: 'alice',
            conversationId: 'alice|c2c_bob',
            clientCorrelationId: 'corr',
            messageType: 1,
            payloadReference: 'encrypted',
            payloadHash: 'hash',
            state: ImOutboxState.prepared,
            createdAtMs: 10,
            updatedAtMs: 10,
            sdkMessageId: 'local'),
        recoveryCopy: const ImOutboxRecoveryRecord(
            ownerUserId: 'alice',
            operationId: 'op',
            clientCorrelationId: 'corr',
            conversationId: 'alice|c2c_bob',
            messageType: 1,
            recoveryRevision: 1,
            state: ImOutboxCopyState.copyPrepared,
            payloadReferenceOrCiphertext: 'encrypted',
            payloadHash: 'hash',
            checksum: 'hash',
            updatedAtMs: 10,
            sdkLocalId: 'local'),
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 10);
    return _Fixture(store, persistence, lease);
  }

  Future<ImOutboxResultVerdict> read() =>
      persistence.readOutboxResult(ownerUserId: 'alice', operationId: 'op');
  Future<ImOutboxDispatchAssessment> intent() =>
      persistence.recordDispatchIntent(
          ownerUserId: 'alice',
          operationId: 'op',
          dispatchAttemptId: 'attempt',
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: 11);
  Future<void> send() async {
    final result = await intent();
    await persistence.transitionOutbox(
        next: result.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 12);
  }

  Future<ImOutboxResultVerdict> result(bool success) =>
      persistence.adjudicateOutboxSdkResult(
          ownerUserId: 'alice',
          operationId: 'op',
          expectedAttemptId: 'attempt',
          succeeded: success,
          leaseOwnerId: 'writer',
          fencingToken: lease.fencingToken,
          nowMs: 20,
          sdkLocalId: 'local',
          serverMsgId: 'server',
          resultCode: success ? '0' : '6012');
}
