import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/runtime_commit_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/runtime_commit_schema.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.open();
  });
  tearDown(() => f.close());

  test('snapshot, dedup and effect survive closing and reopening SQLite',
      () async {
    final committed = await f.commit('one', effects: [f.effect('send-1')]);
    expect(committed.snapshot.revision, 1);
    await f.core.closeIfOpen();
    final restored = await f.load();
    expect(restored!.document['event'], 'one');
    final duplicate = await f.commit('one', effects: [f.effect('send-1')]);
    expect(duplicate.duplicate, isTrue);
    expect(duplicate.snapshot.revision, 1);
    expect(await f.effects(RuntimeDurableEffectState.pending), hasLength(1));
  });

  test('effect insertion failure rolls back snapshot and event identity',
      () async {
    await f.core.runTransaction((db) => db.execute('''
      CREATE TEMP TRIGGER runtime_fail_effect BEFORE INSERT ON chat_runtime_effect
      BEGIN SELECT RAISE(ABORT, 'injected_effect_failure'); END
    '''));
    await expectLater(
        f.commit('one', effects: [f.effect('send-1')]), throwsA(anything));
    expect(await f.load(), isNull);
    final events =
        await f.core.runTransaction((db) => db.query('chat_runtime_event'));
    expect(events, isEmpty);
    expect(await f.effects(RuntimeDurableEffectState.pending), isEmpty);
    await f.core
        .runTransaction((db) => db.execute('DROP TRIGGER runtime_fail_effect'));
    expect((await f.commit('one', effects: [f.effect('send-1')])).duplicate,
        isFalse);
  });

  test('duplicate uses current snapshot and rejects reused event payload',
      () async {
    final first = await f.commit('one', payload: {'a': 1, 'b': 2});
    await f.commit('two', before: first.snapshot);
    final repeated = await f.commit('one', payload: {'b': 2, 'a': 1});
    expect(repeated.duplicate, isTrue);
    expect(repeated.snapshot.revision, 2);
    await expectLater(f.commit('one', payload: {'a': 9, 'b': 2}),
        _rejected(RuntimeCommitFailure.identityConflict));
    expect((await f.load())!.revision, 2);
  });

  test('revision CAS rejects competing proposals without partial effects',
      () async {
    final outcomes = await Future.wait<Object>([
      f.commit('one', effects: [f.effect('a')]).then<Object>((v) => v,
          onError: (Object e) => e),
      f.commit('two', effects: [f.effect('b')]).then<Object>((v) => v,
          onError: (Object e) => e),
    ]);
    expect(outcomes.whereType<RuntimeDurableCommit>(), hasLength(1));
    expect(outcomes.whereType<RuntimeCommitRejected>().single.reason,
        RuntimeCommitFailure.staleRevision);
    expect((await f.load())!.revision, 1);
    expect(await f.effects(RuntimeDurableEffectState.pending), hasLength(1));
  });

  test('new event cannot steal an existing effect operation', () async {
    final first = await f.commit('one', effects: [f.effect('same')]);
    await expectLater(
        f.commit('two', before: first.snapshot, effects: [f.effect('same')]),
        _rejected(RuntimeCommitFailure.identityConflict));
    expect((await f.load())!.revision, 1);
    expect(await f.core.runTransaction((db) => db.query('chat_runtime_event')),
        hasLength(1));
  });

  test('current persisted lease rejects old owner and expiry inside commit',
      () async {
    var reads = 0;
    final expiring = RuntimeCommitCoordinator(
        core: f.core, nowMs: () => ++reads == 1 ? f.now : f.lease.expiresAtMs);
    await expectLater(
        expiring.commit(
            event: f.event('expiry'),
            before: f.initial,
            transition: RuntimeTransition(document: RuntimeDocument({'x': 1})),
            lease: f.lease),
        _rejected(RuntimeCommitFailure.staleLease));
    expect(await f.load(), isNull);
    final old = f.lease;
    await f.replaceLease();
    await expectLater(
        f.coordinator
            .load(scope: f.scope, conversationKey: 'c2c_peer', lease: old),
        _rejected(RuntimeCommitFailure.staleLease));
  });

  test('account and SDK generations fence old work without erasing state',
      () async {
    await f.commit('one');
    final oldScope = f.scope;
    f.scope = RuntimeAccountScope(
        ownerUserID: 'owner', accountEpoch: 1, sdkDomainEpoch: 2);
    await f.coordinator.activateAccount(scope: f.scope, lease: f.lease);
    expect((await f.load())!.scope, f.scope);
    expect((await f.load())!.revision, 1);
    await expectLater(
        f.coordinator.activateAccount(scope: oldScope, lease: f.lease),
        _rejected(RuntimeCommitFailure.staleAccount));
    await expectLater(
        f.coordinator
            .load(scope: oldScope, conversationKey: 'c2c_peer', lease: f.lease),
        _rejected(RuntimeCommitFailure.staleAccount));
    final other = RuntimeAccountScope(
        ownerUserID: 'other', accountEpoch: 1, sdkDomainEpoch: 2);
    await expectLater(
        f.coordinator.activateAccount(scope: other, lease: f.lease),
        _rejected(RuntimeCommitFailure.staleLease));
  });

  test(
      'clear cancels pending work but preserves dispatched identity and result',
      () async {
    final first = await f
        .commit('one', effects: [f.effect('pending'), f.effect('dispatched')]);
    final dispatched = await f.claim('dispatched', 'attempt-1');
    expect(dispatched!.state, RuntimeDurableEffectState.dispatching);
    final cleared = await f.commit('clear',
        before: first.snapshot, clearEpoch: 1, clearing: true);
    expect(cleared.snapshot.clearEpoch, 1);
    expect(await f.claim('pending', 'attempt-2'), isNull);
    expect(await f.effects(RuntimeDurableEffectState.cancelled), hasLength(1));
    expect(
        await f.effects(RuntimeDurableEffectState.dispatching), hasLength(1));
    expect(
        await f.result(
            'dispatched', 'attempt-1', RuntimeDurableEffectState.succeeded),
        isTrue);
    expect((await f.load())!.document['event'], 'clear');
    expect(
        (await f.effects(RuntimeDurableEffectState.succeeded))
            .single
            .result!['ok'],
        isTrue);
    await expectLater(f.commit('late', before: cleared.snapshot, clearEpoch: 0),
        _rejected(RuntimeCommitFailure.staleClear));
  });

  test('lost clear receipt can replay against a restored current snapshot',
      () async {
    final first = await f.commit('one');
    final cleared = await f.commit('clear',
        before: first.snapshot, clearEpoch: 1, clearing: true);
    await f.core.closeIfOpen();
    final restored = (await f.load())!;
    final replay = await f.commit('clear',
        before: restored, clearEpoch: 1, clearing: true);
    expect(replay.duplicate, isTrue);
    expect(replay.snapshot.revision, cleared.snapshot.revision);
    await expectLater(
        f.commit('different-clear',
            before: restored, clearEpoch: 1, clearing: true),
        _rejected(RuntimeCommitFailure.staleClear));
  });

  test('clear rollback preserves both prior state and pending effect',
      () async {
    final first = await f.commit('one', effects: [f.effect('pending')]);
    await f.core.runTransaction((db) => db.execute('''
      CREATE TEMP TRIGGER runtime_fail_clear BEFORE UPDATE ON chat_runtime_effect
      WHEN NEW.state = 'cancelled'
      BEGIN SELECT RAISE(ABORT, 'injected_clear_failure'); END
    '''));
    await expectLater(
        f.commit('clear',
            before: first.snapshot, clearEpoch: 1, clearing: true),
        throwsA(anything));
    expect((await f.load())!.clearEpoch, 0);
    expect((await f.load())!.revision, 1);
    expect(await f.effects(RuntimeDurableEffectState.pending), hasLength(1));
  });

  test('dispatch claim is exclusive and a wrong attempt cannot settle it',
      () async {
    await f.commit('one', effects: [f.effect('send')]);
    final claims =
        await Future.wait([f.claim('send', 'a'), f.claim('send', 'b')]);
    expect(claims.whereType<RuntimeDurableEffect>(), hasLength(1));
    final actual = claims.whereType<RuntimeDurableEffect>().single.attemptID!;
    expect(await f.result('send', 'wrong', RuntimeDurableEffectState.succeeded),
        isFalse);
    expect(await f.result('send', actual, RuntimeDurableEffectState.unknown),
        isTrue);
    expect(await f.claim('send', 'c'), isNull);
    expect(await f.result('send', actual, RuntimeDurableEffectState.succeeded),
        isTrue);
    expect(await f.result('send', actual, RuntimeDurableEffectState.failed),
        isFalse);
  });

  test('fenced restart preserves unknown attempts and revalidates pending work',
      () async {
    await f.commit('one', effects: [f.effect('sent'), f.effect('pending')]);
    await f.claim('sent', 'original-attempt');
    await f.core.closeIfOpen();
    await f.replaceLease();
    expect(await f.effects(RuntimeDurableEffectState.unknown), hasLength(1));
    expect(await f.claim('sent', 'retry'), isNull);
    expect(await f.claim('pending', 'new-attempt'), isNull);
    expect(
        await f.coordinator.revalidatePendingEffect(
            scope: f.scope,
            conversationKey: 'c2c_peer',
            operationID: 'pending',
            kind: 'test.effect',
            expectedClearEpoch: 0,
            lease: f.lease),
        isTrue);
    expect(await f.claim('pending', 'new-attempt'), isNotNull);
    expect(
        await f.coordinator.revalidatePendingEffect(
            scope: f.scope,
            conversationKey: 'c2c_peer',
            operationID: 'sent',
            kind: 'test.effect',
            expectedClearEpoch: 0,
            lease: f.lease),
        isFalse);
    expect(
        await f.result(
            'sent', 'original-attempt', RuntimeDurableEffectState.succeeded),
        isTrue);
  });

  test('attempt identity cannot be reused for another operation', () async {
    await f.commit('one', effects: [f.effect('a'), f.effect('b')]);
    await f.claim('a', 'attempt');
    await expectLater(f.claim('b', 'attempt'), throwsA(anything));
    expect(
        (await f.effects(RuntimeDurableEffectState.pending)).single.operationID,
        'b');
  });

  test('bounded keyset recovery includes every effect sharing a revision',
      () async {
    await f
        .commit('one', effects: [f.effect('c'), f.effect('a'), f.effect('b')]);
    final first = await f.coordinator.listEffects(
        scope: f.scope,
        conversationKey: 'c2c_peer',
        lease: f.lease,
        state: RuntimeDurableEffectState.pending,
        limit: 2);
    expect(first.map((e) => e.operationID), ['a', 'b']);
    final cursor = first.last;
    final second = await f.coordinator.listEffects(
        scope: f.scope,
        conversationKey: 'c2c_peer',
        lease: f.lease,
        state: RuntimeDurableEffectState.pending,
        limit: 2,
        afterRevision: cursor.revision,
        afterOperationID: cursor.operationID,
        afterKind: cursor.kind);
    expect(second.map((e) => e.operationID), ['c']);
  });

  test('same event and operation identities remain isolated by conversation',
      () async {
    await f.commit('one', effects: [f.effect('send')]);
    await f.coordinator.commit(
        event: f.event('one', conversationKey: 'group_peer'),
        before: f.empty('group_peer'),
        transition: RuntimeTransition(
            document: RuntimeDocument({'group': true}),
            effects: [f.effect('send')]),
        lease: f.lease);
    final rows = await f.coordinator.listEffects(
        scope: f.scope,
        conversationKey: 'group_peer',
        lease: f.lease,
        state: RuntimeDurableEffectState.pending);
    expect(rows, hasLength(1));
    expect(await f.effects(RuntimeDurableEffectState.pending), hasLength(1));
  });

  test('existing v1 database gains runtime tables without losing legacy data',
      () async {
    await f.core.runTransaction((db) async {
      await db
          .insert('message_core_meta', {'key': 'legacy-test', 'value': 'keep'});
      for (final table
          in RuntimeCommitSchema.objects.where((s) => !s.startsWith('idx_'))) {
        await db.execute('DROP TABLE $table');
      }
    });
    await f.core.closeIfOpen();
    final objects = await f.core.runTransaction((db) => db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('table','index')"));
    expect(objects.map((row) => row['name']).toSet(),
        containsAll(RuntimeCommitSchema.objects));
    final kept = await f.core.runTransaction((db) => db.query(
        'message_core_meta',
        where: 'key = ?',
        whereArgs: ['legacy-test']));
    expect(kept.single['value'], 'keep');
    await f.coordinator.activateAccount(scope: f.scope, lease: f.lease);
    expect((await f.commit('after-upgrade')).snapshot.revision, 1);
  });
}

Matcher _rejected(RuntimeCommitFailure reason) =>
    throwsA(isA<RuntimeCommitRejected>()
        .having((error) => error.reason, 'reason', reason));

class _Fixture {
  final core = MessageCoreStore.instance;
  late RuntimeCommitCoordinator coordinator;
  late ImWriterLeaseService leases;
  late ImWriterLease lease;
  late String originalPath;
  late Directory directory;
  int now = 1000;
  RuntimeAccountScope scope = RuntimeAccountScope(
      ownerUserID: 'owner', accountEpoch: 1, sdkDomainEpoch: 1);

  Future<void> open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalPath = await getDatabasesPath();
    directory = await Directory.systemTemp.createTemp('runtime-commit-');
    await databaseFactory.setDatabasesPath(directory.path);
    coordinator = RuntimeCommitCoordinator(core: core, nowMs: () => now);
    leases = ImWriterLeaseService(
        store: ConversationLocalImIngressStore(core: core));
    lease = (await leases.acquire(
        ownerUserId: 'owner', leaseOwnerId: 'runtime-test-1', nowMs: now))!;
    await coordinator.activateAccount(scope: scope, lease: lease);
  }

  Future<void> close() async {
    await core.closeIfOpen();
    await databaseFactory
        .deleteDatabase(p.join(directory.path, MessageCoreStore.dbName));
    await databaseFactory.setDatabasesPath(originalPath);
    await directory.delete(recursive: true);
  }

  Future<void> replaceLease() async {
    now = lease.expiresAtMs + 1;
    lease = (await leases.acquire(
        ownerUserId: 'owner', leaseOwnerId: 'runtime-test-2', nowMs: now))!;
    await coordinator.activateAccount(scope: scope, lease: lease);
  }

  RuntimeSnapshot empty(String key) => RuntimeSnapshot(
      scope: scope,
      conversationKey: key,
      clearEpoch: 0,
      revision: 0,
      document: RuntimeDocument({}));
  RuntimeSnapshot get initial => empty('c2c_peer');
  RuntimeEnvelope event(String id,
          {int clearEpoch = 0,
          Map<String, Object?> payload = const {},
          String conversationKey = 'c2c_peer'}) =>
      RuntimeEnvelope(
          scope: scope,
          conversationKey: conversationKey,
          eventID: id,
          operationID: id,
          correlationID: id,
          source: 'test',
          kind: 'test.fact',
          clearEpoch: clearEpoch,
          payload: RuntimeDocument(payload));
  RuntimeEffectIntent effect(String id) => RuntimeEffectIntent(
      operationID: id,
      kind: 'test.effect',
      payload: RuntimeDocument({'value': id}));

  Future<RuntimeDurableCommit> commit(String id,
          {RuntimeSnapshot? before,
          List<RuntimeEffectIntent> effects = const [],
          int clearEpoch = 0,
          bool clearing = false,
          Map<String, Object?> payload = const {}}) async =>
      coordinator.commit(
          event: event(id, clearEpoch: clearEpoch, payload: payload),
          before: before ?? initial,
          transition: RuntimeTransition(
              document: RuntimeDocument({'event': id}), effects: effects),
          lease: lease,
          clearing: clearing);

  Future<RuntimeSnapshot?> load() =>
      coordinator.load(scope: scope, conversationKey: 'c2c_peer', lease: lease);
  Future<List<RuntimeDurableEffect>> effects(RuntimeDurableEffectState state) =>
      coordinator.listEffects(
          scope: scope,
          conversationKey: 'c2c_peer',
          lease: lease,
          state: state);
  Future<RuntimeDurableEffect?> claim(String op, String attempt) =>
      coordinator.claimEffect(
          scope: scope,
          conversationKey: 'c2c_peer',
          operationID: op,
          kind: 'test.effect',
          attemptID: attempt,
          lease: lease);
  Future<bool> result(
          String op, String attempt, RuntimeDurableEffectState state) =>
      coordinator.recordEffectResult(
          scope: scope,
          conversationKey: 'c2c_peer',
          operationID: op,
          kind: 'test.effect',
          attemptID: attempt,
          state: state,
          result: RuntimeDocument({'ok': true}),
          lease: lease);
}
