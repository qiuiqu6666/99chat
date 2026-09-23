import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/account_runtime_supervisor.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_effect_scheduler.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/runtime/runtime_protocol.dart';

void main() {
  final scope = RuntimeAccountScope(
      ownerUserID: 'owner', accountEpoch: 3, sdkDomainEpoch: 7);
  RuntimeEnvelope event(String id,
          {String conversation = 'group_room',
          RuntimeAccountScope? account,
          int epoch = 0,
          int? visit,
          int? operation,
          int? revision,
          String kind = 'append',
          Map<String, Object?>? payload}) =>
      RuntimeEnvelope(
          scope: account ?? scope,
          conversationKey: conversation,
          eventID: id,
          operationID: 'operation-$id',
          correlationID: 'trace-$id',
          source: 'test',
          kind: kind,
          clearEpoch: epoch,
          visitID: visit,
          viewOperation: operation,
          expectedRevision: revision,
          payload: RuntimeDocument(payload ?? {'value': id}));
  RuntimeTransition append(RuntimeSnapshot before, RuntimeEnvelope event) =>
      RuntimeTransition(
          document: RuntimeDocument({
            'events': [
              ...before.document['events'] as List,
              event.payload['value']
            ]
          }),
          effects: [
            RuntimeEffectIntent(
                operationID: event.operationID,
                kind: 'send',
                payload: event.payload)
          ]);
  AccountRuntimeSupervisor runtime({RuntimeReducer? reducer, int batch = 32}) =>
      AccountRuntimeSupervisor.shadow(
          scope: scope,
          reducer: reducer ?? append,
          eventsPerTurn: batch,
          initialState: (_) => RuntimeDocument({'events': <Object?>[]}));

  test('ingress deeply freezes SDK-shaped input and rejects live objects', () {
    final nested = <String, Object?>{
      'rows': [
        <String, Object?>{'id': 'original'}
      ]
    };
    final document = RuntimeDocument(nested);
    ((nested['rows'] as List).single as Map)['id'] = 'changed';
    expect(((document['rows'] as List).single as Map)['id'], 'original');
    expect(
        () => (document['rows'] as List).add('escape'), throwsUnsupportedError);
    expect(() => ((document['rows'] as List).single as Map)['id'] = 'escape',
        throwsUnsupportedError);
    expect(() => RuntimeDocument({'sdk': Object()}), throwsArgumentError);
    expect(() => RuntimeDocument({'callback': () {}}), throwsArgumentError);
    expect(() => RuntimeDocument({'nan': double.nan}), throwsArgumentError);
  });

  test(
      'one conversation preserves FIFO and duplicate events produce no effects',
      () async {
    final r = runtime();
    addTearDown(r.close);
    final receipts = await Future.wait([
      r.dispatch(event('1')),
      r.dispatch(event('2')),
      r.dispatch(event('1'))
    ]);
    expect(receipts.map((r) => r.disposition), [
      RuntimeDisposition.committed,
      RuntimeDisposition.committed,
      RuntimeDisposition.duplicate
    ]);
    expect(receipts.map((r) => r.ingressSequence), [1, 2, 3]);
    expect(receipts.last.effects, isEmpty);
    expect(r.snapshotFor('group_room').document['events'], ['1', '2']);
    expect(r.snapshotFor('group_room').revision, 2);
  });

  test('large mailbox yields to a different conversation', () async {
    final order = <String>[];
    final r = runtime(
        batch: 1,
        reducer: (state, input) {
          order.add(input.eventID);
          return append(state, input);
        });
    addTearDown(r.close);
    final pending = [
      r.dispatch(event('a1')),
      r.dispatch(event('a2')),
      r.dispatch(event('b1', conversation: 'group_other'))
    ];
    await Future.wait(pending);
    expect(order, ['a1', 'b1', 'a2']);
  });

  test('clear invalidates queued old facts before a new epoch can publish',
      () async {
    final r = runtime();
    addTearDown(r.close);
    await r.dispatch(event('before-clear'));
    final oldHistory = r.dispatch(event('late-history'));
    final clear = r.clearConversation(
        conversationKey: 'group_room', eventID: 'clear-1', nextEpoch: 1);
    final newMessage = r.dispatch(event('after-clear', epoch: 1));
    expect((await oldHistory).disposition, RuntimeDisposition.staleClear);
    expect((await clear).snapshot.document['events'], isEmpty);
    expect((await newMessage).disposition, RuntimeDisposition.committed);
    expect(r.snapshotFor('group_room').document['events'], ['after-clear']);
    expect((await r.dispatch(event('old-result', epoch: 0))).disposition,
        RuntimeDisposition.staleClear);
  });

  test(
      'account closure invalidates pending events and never creates stale actors',
      () async {
    final r = runtime();
    final pending = r.dispatch(event('pending'));
    await r.close();
    expect((await pending).disposition, RuntimeDisposition.staleAccount);
    final next = runtime();
    addTearDown(next.close);
    final old = RuntimeAccountScope(
        ownerUserID: 'owner', accountEpoch: 2, sdkDomainEpoch: 7);
    expect((await next.dispatch(event('old', account: old))).disposition,
        RuntimeDisposition.staleAccount);
    expect(next.actorCount, 0);
    expect((await r.dispatch(event('closed'))).disposition,
        RuntimeDisposition.staleAccount);
  });

  test(
      'reopened pages and superseded searches cannot publish into the current visit',
      () async {
    final r = runtime();
    addTearDown(r.close);
    final visit = r.openView('group_room');
    final search = r.beginViewOperation(visit);
    final pending =
        r.dispatch(event('old-search', visit: visit, operation: search));
    r.beginViewOperation(visit);
    expect((await pending).disposition, RuntimeDisposition.staleView);
    r.closeView(visit);
    final next = r.openView('group_room');
    expect(next, isNot(visit));
    expect(
        (await r.dispatch(
                event('closed-page', visit: visit, operation: search)))
            .disposition,
        RuntimeDisposition.staleView);
    expect((await r.dispatch(event('realtime'))).disposition,
        RuntimeDisposition.committed);
  });

  test(
      'explicit revision dependencies reject stale results without rejecting unrelated facts',
      () async {
    final r = runtime();
    addTearDown(r.close);
    await r.dispatch(event('first'));
    expect((await r.dispatch(event('dependent', revision: 0))).disposition,
        RuntimeDisposition.staleRevision);
    expect((await r.dispatch(event('independent'))).disposition,
        RuntimeDisposition.committed);
  });

  test(
      'a throwing reducer neither commits nor poisons retries or the next event',
      () async {
    var fail = true;
    final r = runtime(reducer: (state, input) {
      if (fail) throw StateError('injected');
      return append(state, input);
    });
    addTearDown(r.close);
    expect((await r.dispatch(event('retry'))).disposition,
        RuntimeDisposition.rejected);
    expect(r.snapshotFor('group_room').revision, 0);
    fail = false;
    expect((await r.dispatch(event('retry'))).disposition,
        RuntimeDisposition.committed);
    expect((await r.dispatch(event('next'))).snapshot.document['events'],
        ['retry', 'next']);
  });

  test(
      'effect lanes are FIFO and a slow SDK lane does not block another conversation',
      () async {
    final scheduler = RuntimeEffectScheduler(maxConcurrent: 2);
    addTearDown(scheduler.close);
    final gate = Completer<RuntimeDocument>();
    final started = <String>[];
    final a1 = scheduler.schedule(
        lane: 'a',
        isCurrent: () => true,
        execute: () {
          started.add('a1');
          return gate.future;
        });
    final a2 = scheduler.schedule(
        lane: 'a',
        isCurrent: () => true,
        execute: () async {
          started.add('a2');
          return RuntimeDocument({});
        });
    final b1 = scheduler.schedule(
        lane: 'b',
        isCurrent: () => true,
        execute: () async {
          started.add('b1');
          return RuntimeDocument({});
        });
    await b1;
    expect(started, ['a1', 'b1']);
    gate.complete(RuntimeDocument({}));
    await Future.wait([a1, a2]);
    expect(started, ['a1', 'b1', 'a2']);
    expect(scheduler.runningCount, 0);
  });

  test('equivalent effects coalesce without merging distinct cursor identities',
      () async {
    final scheduler = RuntimeEffectScheduler(maxConcurrent: 1);
    addTearDown(scheduler.close);
    final gate = Completer<RuntimeDocument>();
    var calls = 0;
    Future<RuntimeDocument> execute() {
      calls++;
      return gate.future;
    }

    final first = scheduler.schedule(
        lane: 'history',
        coalescingIdentity: (scope, 'cloud', 10),
        isCurrent: () => true,
        execute: execute);
    final same = scheduler.schedule(
        lane: 'history',
        coalescingIdentity: (scope, 'cloud', 10),
        isCurrent: () => true,
        execute: execute);
    final other = scheduler.schedule(
        lane: 'history',
        coalescingIdentity: (scope, 'cloud', 20),
        isCurrent: () => true,
        execute: execute);
    expect(identical(first, same), isTrue);
    expect(identical(first, other), isFalse);
    gate.complete(RuntimeDocument({'ok': true}));
    await Future.wait([first, same, other]);
    expect(calls, 2);
  });

  test('obsolete dispatched writes keep their response and are never retried',
      () async {
    final scheduler = RuntimeEffectScheduler(maxConcurrent: 1);
    final gate = Completer<RuntimeDocument>();
    var calls = 0;
    final running = scheduler.schedule(
        lane: 'send',
        isCurrent: () => true,
        execute: () {
          calls++;
          return gate.future;
        });
    final queued = scheduler.schedule(
        lane: 'send',
        isCurrent: () => true,
        execute: () async {
          calls++;
          return RuntimeDocument({});
        });
    scheduler.close();
    expect((await queued).dispatched, isFalse);
    expect(scheduler.runningCount, 1);
    gate.complete(RuntimeDocument({'serverID': 'confirmed'}));
    final result = await running;
    expect(result.status, RuntimeEffectStatus.obsolete);
    expect(result.dispatched, isTrue);
    expect(result.value!['serverID'], 'confirmed');
    expect(calls, 1);
  });

  test('effect failures release slots and queue overload is an explicit result',
      () async {
    final scheduler = RuntimeEffectScheduler(maxConcurrent: 1, maxQueued: 1);
    addTearDown(scheduler.close);
    final gate = Completer<RuntimeDocument>();
    final running = scheduler.schedule(
        lane: 'a', isCurrent: () => true, execute: () => gate.future);
    final queued = scheduler.schedule(
        lane: 'b',
        isCurrent: () => true,
        execute: () async => RuntimeDocument({'ok': true}));
    final overloaded = await scheduler.schedule(
        lane: 'c',
        isCurrent: () => true,
        execute: () async => throw StateError('must not execute'));
    expect(overloaded.status, RuntimeEffectStatus.overloaded);
    expect(overloaded.dispatched, isFalse);
    gate.completeError(StateError('SDK failed'));
    expect((await running).status, RuntimeEffectStatus.failed);
    expect((await queued).status, RuntimeEffectStatus.completed);
  });
  test(
      'duplicate clears share a result and conflicting epochs cannot move the fence',
      () async {
    final r = runtime();
    addTearDown(r.close);
    final first = r.clearConversation(
        conversationKey: 'group_room', eventID: 'clear', nextEpoch: 1);
    final duplicate = r.clearConversation(
        conversationKey: 'group_room', eventID: 'clear', nextEpoch: 1);
    expect(identical(first, duplicate), isTrue);
    await first;
    expect(
        () => r.clearConversation(
            conversationKey: 'group_room', eventID: 'clear', nextEpoch: 2),
        throwsArgumentError);
    expect((await r.dispatch(event('valid', epoch: 1))).disposition,
        RuntimeDisposition.committed);
    expect(r.snapshotFor('group_room').document['events'], ['valid']);
  });

  test('failed clear preparation leaves the original epoch usable', () async {
    var failClear = false;
    final r = AccountRuntimeSupervisor.shadow(
        scope: scope,
        reducer: append,
        initialState: (_) {
          if (failClear) throw StateError('reset preparation failed');
          return RuntimeDocument({'events': <Object?>[]});
        });
    addTearDown(r.close);
    await r.dispatch(event('before'));
    failClear = true;
    expect(
        () => r.clearConversation(
            conversationKey: 'group_room', eventID: 'clear', nextEpoch: 1),
        throwsStateError);
    expect((await r.dispatch(event('after'))).snapshot.document['events'],
        ['before', 'after']);
    expect(r.snapshotFor('group_room').clearEpoch, 0);
  });

  test('closed runtime cannot allocate a new actor through a snapshot read',
      () async {
    final r = runtime();
    await r.close();
    expect(() => r.snapshotFor('new-conversation'), throwsStateError);
    expect(r.actorCount, 0);
  });

  test('a lifecycle barrier during reduction prevents publication', () async {
    late final AccountRuntimeSupervisor r;
    r = runtime(reducer: (state, input) {
      unawaited(r.close());
      return append(state, input);
    });
    final result = await r.dispatch(event('interrupted'));
    expect(result.disposition, RuntimeDisposition.staleAccount);
    expect(result.snapshot.revision, 0);
    expect(result.effects, isEmpty);
  });
}
