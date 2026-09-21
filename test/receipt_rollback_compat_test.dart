import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/receipt_recovery_compat.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class _Service implements MessageService {
  late V2TimAdvancedMsgListener listener;
  @override
  Future<void> addAdvancedMsgListener(
      {required V2TimAdvancedMsgListener listener}) async {
    this.listener = listener;
  }

  @override
  Future<void> removeAdvancedMsgListener(
      {V2TimAdvancedMsgListener? listener}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ImIngressDraft<void> _draft(
  String id,
  String recovery, {
  String? operation,
  ImRecoveryMode mode = ImRecoveryMode.commandArguments,
  List<ImIngressDraft<dynamic>> copies = const [],
}) =>
    ImIngressDraft<void>(
        eventId: id,
        eventNamespace: 'chat',
        kind: ImEventKind.readReceipt,
        scope: AccountScopedConversationKey(
            ownerUserId: 'owner',
            conversationType: ImConversationType.c2c,
            conversationId: 'peer'),
        ownerUserId: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        clearEpoch: 0,
        operationId: operation,
        source: ImEventSource.sdkListener,
        authority: ImEventAuthority.provider,
        observedAtMs: 1,
        payloadHash: recovery,
        recoveryMode: mode,
        recoveryRef: recovery,
        recoveryCopies: copies);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String originalPath;
  final core = MessageCoreStore.instance;
  late ConversationLocalImIngressStore store;
  late DurableIngressGateway gateway;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalPath = await getDatabasesPath();
    dir = await Directory.systemTemp.createTemp('receipt-rollback-');
    await databaseFactory.setDatabasesPath(dir.path);
    store = ConversationLocalImIngressStore(core: core);
    gateway = DurableIngressGateway(store: store);
  });
  tearDown(() async {
    await core.closeIfOpen();
    await databaseFactory
        .deleteDatabase(p.join(dir.path, MessageCoreStore.dbName));
    await databaseFactory.setDatabasesPath(originalPath);
    await dir.delete(recursive: true);
  });
  Future<List<ImInboxRecord>> records() =>
      core.runTransaction((db) async => (await db.query('message_event_inbox',
              orderBy: 'account_ingress_sequence'))
          .map(imInboxRecordFromStorageMap)
          .toList());

  test('unscoped SDK receipts remain recoverable notification batches',
      () async {
    final service = _Service();
    final delivered = Completer<EventEnvelope<dynamic>>();
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: gateway,
        ownerUserId: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: delivered.complete);
    await adapter.register();
    service.listener.onRecvMessageReadReceipts([
      V2TimMessageReceipt(userID: '', msgID: 'unscoped', timestamp: 20),
    ]);
    final live = await delivered.future.timeout(const Duration(seconds: 10));
    await adapter.unregister();
    expect(live.kind, ImEventKind.notification);
    expect(live.scope, isNull);
    expect(live.payload, isA<ImReadReceiptBatch>());
    final persisted = await records();
    expect(persisted, hasLength(2));
    final recovery = persisted
        .singleWhere((r) => r.recoveryMode == ImRecoveryMode.commandArguments);
    expect(recovery.event.kind, ImEventKind.notification);
    expect(recovery.recoveryRef, startsWith('receipt-json:'));
    expect(
        V2TimMessageReceipt.fromJson(
                jsonDecode(recovery.recoveryRef.substring(13)) as Map)
            .msgID,
        'unscoped');
  });

  test('live batch has one callback; the old loader can recover every semantic',
      () async {
    final service = _Service();
    final delivered = Completer<EventEnvelope<dynamic>>();
    var calls = 0;
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: gateway,
        ownerUserId: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: (event) {
          calls++;
          delivered.complete(event);
        });
    await adapter.register();
    final receipts = [
      V2TimMessageReceipt(userID: 'peer', timestamp: 0, msgID: 'wild'),
      V2TimMessageReceipt(userID: 'peer', timestamp: 60, msgID: 'positive'),
    ];
    service.listener.onRecvC2CReadReceipt(receipts);
    service.listener.onRecvMessageReadReceipts(receipts);
    final live = await delivered.future.timeout(const Duration(seconds: 10));
    await adapter.unregister();
    expect(calls, 1);
    expect(live.payload, isA<ImReadReceiptBatch>());
    final persisted = await records();
    expect(persisted, hasLength(5));
    final watermarks = <int>[];
    final messages = <String?>[];
    // Deliberately use ONLY the pre-batching binary's branches and codec.
    for (final row in persisted) {
      if (row.recoveryMode == ImRecoveryMode.ephemeralUi) continue;
      expect(row.recoveryRef, startsWith('receipt-json:'));
      final receipt = V2TimMessageReceipt.fromJson(
          jsonDecode(row.recoveryRef.substring('receipt-json:'.length)) as Map);
      if (row.event.eventId.startsWith('c2c-read:')) {
        watermarks.add(receipt.timestamp);
      } else {
        messages.add(receipt.msgID);
      }
    }
    expect(watermarks, unorderedEquals([0, 60]));
    expect(messages, unorderedEquals(['wild', 'positive']));

    final lease = (await ImWriterLeaseService(store: store)
        .acquire(ownerUserId: 'owner', leaseOwnerId: 'writer', nowMs: 2))!;
    await gateway.claimForWriter(event: live, lease: lease, nowMs: 3);
    for (final pair in [
      [ImInboxStatus.processing, ImInboxStatus.metadataCommitted],
      [ImInboxStatus.metadataCommitted, ImInboxStatus.projectionPublished],
      [ImInboxStatus.projectionPublished, ImInboxStatus.completed],
    ]) {
      expect(
          await gateway.advanceForWriter(
              event: live,
              expectedStatus: pair[0],
              nextStatus: pair[1],
              lease: lease,
              nowMs: 4,
              completeRecoveryCopies: pair[1] == ImInboxStatus.completed),
          isTrue);
    }
    expect(
        (await records()).every((row) => row.status == ImInboxStatus.completed),
        isTrue);
  });

  test(
      'discarding aggregate during recovery does not acknowledge unapplied copies',
      () async {
    const operation = '${receiptRecoveryOperationPrefix}crash';
    final parent = await gateway.append(_draft(operation, 'ephemeral:aggregate',
        operation: operation,
        mode: ImRecoveryMode.ephemeralUi,
        copies: [
          _draft('message-read:copy', 'receipt-json:{}', operation: operation)
        ]));
    final lease = (await ImWriterLeaseService(store: store)
        .acquire(ownerUserId: 'owner', leaseOwnerId: 'writer', nowMs: 2))!;
    await gateway.claimForWriter(event: parent.event, lease: lease, nowMs: 3);
    for (final pair in [
      [ImInboxStatus.processing, ImInboxStatus.metadataCommitted],
      [ImInboxStatus.metadataCommitted, ImInboxStatus.projectionPublished],
      [ImInboxStatus.projectionPublished, ImInboxStatus.completed],
    ]) {
      await gateway.advanceForWriter(
          event: parent.event,
          expectedStatus: pair[0],
          nextStatus: pair[1],
          lease: lease,
          nowMs: 4);
    }
    final rows = await records();
    expect(rows.first.status, ImInboxStatus.completed);
    expect(rows.last.status, ImInboxStatus.prepared);
  });

  test('a failed copy insert rolls back parent and allocated sequences',
      () async {
    await core.runTransaction((db) => db.execute('''CREATE TRIGGER fail_copy
      BEFORE INSERT ON message_event_inbox WHEN NEW.event_id = 'message-read:copy'
      BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END'''));
    const operation = '${receiptRecoveryOperationPrefix}atomic';
    final draft = _draft(operation, 'ephemeral:aggregate',
        operation: operation,
        mode: ImRecoveryMode.ephemeralUi,
        copies: [
          _draft('message-read:copy', 'receipt-json:{}', operation: operation)
        ]);
    await expectLater(gateway.append(draft), throwsA(isA<DatabaseException>()));
    expect(await records(), isEmpty);
    expect(
        await core.runTransaction((db) => db.query('message_ingress_counter')),
        isEmpty);
    await core.runTransaction((db) => db.execute('DROP TRIGGER fail_copy'));
    await gateway.append(draft);
    expect((await records()).map((row) => row.event.accountIngressSequence),
        [1, 2]);
  });

  test(
      'opening an existing database converts pending batches atomically and once',
      () async {
    final payload = jsonEncode({
      'watermark': true,
      'receipts': [
        V2TimMessageReceipt(userID: 'peer', timestamp: 10, msgID: 'm').toJson(),
      ]
    });
    await gateway.append(
        _draft('read-receipt-batch:old', 'receipt-batch-json:$payload'));
    await gateway.append(
        _draft('read-receipt-batch:completed', 'receipt-batch-json:$payload'));
    await core.runTransaction((db) => db.update(
        'message_event_inbox', {'status': 'completed'},
        where: 'event_id = ?', whereArgs: ['read-receipt-batch:completed']));
    await core.closeIfOpen();
    var rows = await records();
    expect(rows, hasLength(4));
    expect(rows.first.recoveryMode, ImRecoveryMode.ephemeralUi);
    expect(rows[1].recoveryMode, ImRecoveryMode.commandArguments);
    expect(
        rows
            .skip(2)
            .every((row) => row.recoveryRef.startsWith('receipt-json:')),
        isTrue);
    await core.closeIfOpen();
    rows = await records();
    expect(rows, hasLength(4));
    final appended = await gateway.append(_draft('after-migration', 'test'));
    expect(appended.event.accountIngressSequence, 5);
  });
}
