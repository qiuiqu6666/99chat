import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_mailbox.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_recovery_worker.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

import 'chat_runtime_ingress_order_test.dart' as fixture;

class _Sdk implements MessageService {
  V2TimAdvancedMsgListener? listener;
  @override
  Future<void> addAdvancedMsgListener({required V2TimAdvancedMsgListener listener}) async {
    this.listener = listener;
  }
  @override
  Future<void> removeAdvancedMsgListener({V2TimAdvancedMsgListener? listener}) async {
    if (identical(this.listener, listener)) this.listener = null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nonwaiting admission retains at most queue plus worker capacity', () async {
    final gate = Completer<void>();
    final seen = <String>[];
    final router = ImMailboxRouter(maxConcurrentWorkers: 2, maxQueuedEvents: 8,
        handler: (event) async {
          seen.add(event.eventId);
          if (event.eventId == '0') await gate.future;
        });
    var accepted = 0;
    var rejected = 0;
    final jobs = [
      for (var i = 0; i < 10000; i++)
        router.dispatch(fixture.ingress('$i'), waitForCapacity: false).then<void>(
            (_) { accepted++; }, onError: (Object error) {
          expect(error, isA<ImMailboxCapacityExceeded>());
          rejected++;
        })
    ];
    final retainedBeforeDrain = router.retainedEventCount;
    await Future<void>.delayed(Duration.zero);
    expect(retainedBeforeDrain, lessThanOrEqualTo(10));
    expect(router.retainedEventCount, lessThanOrEqualTo(10));
    gate.complete();
    await Future.wait(jobs);
    await router.drain();
    expect(accepted, 10);
    expect(rejected, 9990);
    expect(seen, [for (var i = 0; i < 10; i++) '$i']);
    expect(router.retainedEventCount, 0);
  });

  test('real adapter durable control rows survive reopen and capacity deferral', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('im-admission-');
    await databaseFactory.setDatabasesPath(directory.path);
    final local = ConversationLocalStore.instance;
    final ingressStore = ConversationLocalImIngressStore(owner: local);
    final gateway = DurableIngressGateway(store: ingressStore);
    final sdk = _Sdk();
    final persisted = Completer<void>();
    var persistedCount = 0;
    const owner = 'bounded-recovery-owner';
    final adapter = TencentAdvancedMessageAdapter(messageService: sdk,
        ingress: gateway, ownerUserId: owner, accountGeneration: 1,
        domainGeneration: 1, onEvent: (_) {
      // Crash boundary: persistence finished; no business handler ran.
      if (++persistedCount == 3) persisted.complete();
    });
    final gate = Completer<void>();
    final recovered = <String>[];
    final router = ImMailboxRouter(maxConcurrentWorkers: 1, maxQueuedEvents: 1,
        handler: (event) async {
      if (event.eventId == 'hold') await gate.future;
      if (event.payload is ImMessageRevokedEvent) {
        recovered.add((event.payload as ImMessageRevokedEvent).msgID);
      }
    });
    Future<void>? held;
    Future<void>? queued;
    try {
      await adapter.register();
      for (var i = 0; i < 3; i++) sdk.listener!.onRecvMessageRevoked('m$i');
      await persisted.future.timeout(const Duration(seconds: 5));
      await adapter.unregister();
      await local.closeDatabaseForTest();
      final now = DateTime.now().millisecondsSinceEpoch;
      final lease = await ImWriterLeaseService(store: ingressStore).acquire(
          ownerUserId: owner, leaseOwnerId: 'reopened-core', nowMs: now, ttlMs: 60000);
      held = router.dispatch(fixture.ingress('hold'));
      queued = router.dispatch(fixture.ingress('queued'));
      await Future<void>.delayed(Duration.zero);
      var payloadReads = 0;
      final worker = ImRecoveryWorker(gateway: gateway, router: router,
          lease: lease!, ownerUserId: owner, accountGeneration: 1,
          domainGeneration: 1, loadPayload: (record) async {
        payloadReads++;
        // Explicit test loader boundary: no SDK replay guarantee is assumed.
        // The real adapter's complete revoke ID is in the persisted reference.
        expect(record.recoveryRef, startsWith('revoke:'));
        return ImRecoveryPayload.recovered(
            ImMessageRevokedEvent(msgID: record.recoveryRef.substring(7)));
      });
      final blocked = await worker.run(nowMs: now, limit: 3);
      expect(blocked.dispatched, 0);
      expect(blocked.scanned, 0, reason: 'a full scan triggers immediate coordinator reruns');
      expect(blocked.moreDue, isFalse);
      expect(blocked.nextRetryAtMs, now + 500);
      expect(payloadReads, 0);
      final rows = await gateway.listForRecovery(ownerUserId: owner,
          accountGeneration: 1, domainGeneration: 1, nowMs: now,
          processingTimeoutMs: 30000, limit: 3);
      expect(rows, hasLength(3));
      expect(rows.every((row) => row.retryCount == 0), isTrue);
      expect(rows.every((row) => !imInboxRecordToStorageMap(row).containsKey('payload')), isTrue);
      gate.complete();
      await Future.wait([held, queued]);
      final replay = await worker.run(nowMs: now + 500, limit: 3);
      expect(replay.dispatched, 3);
      expect(recovered.toSet(), {'m0', 'm1', 'm2'});
      expect(payloadReads, 3);
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (held != null) await held;
      if (queued != null) await queued;
      await router.drain();
      await adapter.unregister();
      await local.closeDatabaseForTest();
      await directory.delete(recursive: true);
    }
  });
}
