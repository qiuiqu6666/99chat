import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';

EventEnvelope<String> ingress(
  String id, {
  String namespace = 'chat',
  String conversation = 'c2c_bob',
}) =>
    EventEnvelope<String>(
      eventId: id,
      eventNamespace: namespace,
      kind: ImEventKind.realtimeMessage,
      ownerUserId: 'alice',
      accountGeneration: 1,
      domainGeneration: 1,
      clearEpoch: 0,
      accountIngressSequence: 1,
      scopeIngressSequence: 1,
      source: ImEventSource.sdkListener,
      authority: ImEventAuthority.provider,
      observedAtMs: 1,
      payload: id,
      scope: AccountScopedConversationKey(
          ownerUserId: 'alice',
          conversationType: ImConversationType.c2c,
          conversationId: conversation),
    );

void main() {
  test('SDK and recovery namespaces cannot concurrently write one conversation',
      () async {
    final gate = Completer<void>();
    final order = <String>[];
    final router = ImMailboxRouter(handler: (e) async {
      order.add(e.eventId);
      if (e.eventId == 'sdk') await gate.future;
    });
    final first = router.dispatch(ingress('sdk', namespace: 'sdk.realtime'));
    final recovery =
        router.dispatch(ingress('recovery', namespace: 'durable.inbox'));
    await Future<void>.delayed(Duration.zero);
    final beforeRelease = List<String>.of(order);
    gate.complete();
    await Future.wait([first, recovery]);
    await router.drain();
    expect(beforeRelease, ['sdk']);
    expect(order, ['sdk', 'recovery']);
  });

  test(
      'history admission and urgent receipt preserve conversation causal order',
      () async {
    final gate = Completer<void>();
    final order = <String>[];
    final router = ImMailboxRouter(handler: (e) async {
      order.add(e.eventId);
      if (e.eventId == 'first') await gate.future;
    });
    final first = router.dispatch(ingress('first'));
    final history =
        router.dispatch(ingress('history'), lane: ImIngressLane.history);
    final background =
        router.dispatch(ingress('background'), lane: ImIngressLane.background);
    final urgent =
        router.dispatch(ingress('urgent'), lane: ImIngressLane.urgent);
    gate.complete();
    await Future.wait([first, history, background, urgent]);
    await router.drain();
    expect(order, ['first', 'history', 'background', 'urgent']);
  });

  test(
      'timed-out handler holds conversation and worker until actual completion',
      () async {
    final gate = Completer<void>();
    final order = <String>[];
    final router = ImMailboxRouter(
        maxConcurrentWorkers: 2,
        handlerTimeout: const Duration(milliseconds: 15),
        handler: (e) async {
          order.add(e.eventId);
          if (e.eventId == 'slow') await gate.future;
        });
    final timedOut = expectLater(
        router.dispatch(ingress('slow')), throwsA(isA<TimeoutException>()));
    final next = router.dispatch(ingress('next'));
    await timedOut;
    await router.dispatch(ingress('other', conversation: 'c2c_carol'));
    final beforeRelease = List<String>.of(order);
    final inflight = router.activeWorkerCount;
    var drained = false;
    final drain = router.drain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    final prematurelyDrained = drained;
    gate.complete();
    await next;
    await drain;
    expect(beforeRelease, ['slow', 'other']);
    expect(inflight, 1);
    expect(prematurelyDrained, isFalse);
    expect(order, ['slow', 'other', 'next']);
  });

  test('late handler error is observed and does not run the next turn early',
      () async {
    final gate = Completer<void>();
    var nextRan = false;
    final router = ImMailboxRouter(
        handlerTimeout: const Duration(milliseconds: 15),
        handler: (e) async {
          if (e.eventId == 'slow') {
            await gate.future;
            throw StateError('late');
          }
          nextRan = true;
        });
    final timedOut = expectLater(
        router.dispatch(ingress('slow')), throwsA(isA<TimeoutException>()));
    final next = router.dispatch(ingress('next'));
    await timedOut;
    final early = nextRan;
    gate.complete();
    await next;
    await router.drain();
    expect(early, isFalse);
    expect(nextRan, isTrue);
    expect(router.activeMailboxCount, 0);
  });

  test('busy conversation yields workers to another ready conversation',
      () async {
    final gate = Completer<void>();
    final order = <String>[];
    final router = ImMailboxRouter(
        maxConcurrentWorkers: 1,
        handler: (e) async {
          order.add(e.eventId);
          if (e.eventId == 'first') await gate.future;
        });
    final first = router.dispatch(ingress('first'));
    final same = router.dispatch(ingress('same'));
    final other = router.dispatch(ingress('other', conversation: 'c2c_carol'));
    gate.complete();
    await Future.wait([first, same, other]);
    await router.drain();
    expect(order, ['first', 'other', 'same']);
  });
  test('capacity pressure waits without losing or reordering admitted facts',
      () async {
    final gate = Completer<void>();
    final seen = <String>[];
    final router = ImMailboxRouter(
        maxConcurrentWorkers: 1,
        maxQueuedEvents: 1,
        handler: (event) async {
          seen.add(event.eventId);
          if (event.eventId == '0') await gate.future;
        });
    final jobs = [
      for (var i = 0; i < 1000; i++) router.dispatch(ingress('$i'))
    ];
    final all = Future.wait(jobs);
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['0']);
    expect(router.activeWorkerCount, 1);
    expect(router.pendingEventCount, 999);
    final drain = router.drain();
    gate.complete();
    await all;
    await drain;
    expect(seen, [for (var i = 0; i < 1000; i++) '$i']);
    expect(router.pendingEventCount, 0);
    expect(router.activeMailboxCount, 0);
    expect(router.limitHitCount, greaterThan(0));
  });
}
