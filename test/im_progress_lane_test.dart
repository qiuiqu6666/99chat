import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/coalesced_ui_progress.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_download_progress.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class _Service implements MessageService {
  V2TimAdvancedMsgListener? listener;
  @override
  Future<void> addAdvancedMsgListener(
      {required V2TimAdvancedMsgListener listener}) async {
    this.listener = listener;
  }

  @override
  Future<void> removeAdvancedMsgListener(
      {V2TimAdvancedMsgListener? listener}) async {
    this.listener = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimMessage _message() => V2TimMessage.fromJson({
      'message_msg_id': 'upload',
      'message_risk_type_identified': 0,
      'message_sender': 'alice',
      'message_conv_type': 1,
      'message_conv_id': 'bob',
      'message_status': 1,
      'message_elem_array': <Object?>[],
    });
V2TimMessageDownloadProgress _download(int size,
        {bool finished = false, int error = 0}) =>
    V2TimMessageDownloadProgress(
      isFinish: finished,
      isError: error != 0,
      msgID: 'download',
      totalSize: 1000,
      currentSize: size,
      type: 0,
      isSnapshot: false,
      path: '/download',
      errorCode: error,
      errorDesc: '',
    );

void main() {
  testWidgets('slow consumer has one real call and bounded latest values',
      (tester) async {
    final first = Completer<void>();
    final values = <int>[];
    var active = 0;
    var peak = 0;
    final lane = CoalescedUiProgress<int>(
        capacity: 3,
        onError: (e, s) => fail('$e'),
        onProgress: (value) async {
          active++;
          if (active > peak) peak = active;
          values.add(value);
          if (value == 1) await first.future;
          active--;
        });
    lane.add('same', 1);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 2; i < 1000; i++) {
      lane.add('same', i);
    }
    lane.add('b', 2);
    lane.add('c', 3);
    lane.add('d', 4);
    expect(lane.pendingCount, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(values, [1]);
    first.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(values, [1, 2, 3, 4]);
    expect(peak, 1);
    lane.dispose();
  });

  testWidgets('cancel waits for actual consumer and dispose is terminal',
      (tester) async {
    final release = Completer<void>();
    final values = <int>[];
    final lane = CoalescedUiProgress<int>(
        onError: (e, s) => fail('$e'),
        onProgress: (value) async {
          values.add(value);
          await release.future;
        });
    lane.add('a', 1);
    await tester.pump(const Duration(milliseconds: 50));
    lane.add('a', 2);
    var cancelled = false;
    final cancel = lane.cancel('a').then((_) {
      cancelled = true;
    });
    await tester.pump();
    expect(cancelled, isFalse);
    release.complete();
    await cancel;
    lane.dispose();
    lane.dispose();
    lane.add('a', 3);
    await tester.pump(const Duration(seconds: 1));
    expect(values, [1]);
    expect(lane.pendingCount, 0);
  });

  testWidgets('upload/download bursts bypass Inbox but final states persist',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final progress = <Object>[];
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add,
        onUiProgress: progress.add);
    await adapter.register();
    final message = _message();
    for (var i = 1; i <= 99; i++) {
      service.listener!.onSendMessageProgress(message, i);
      service.listener!.onMessageDownloadProgressCallback(_download(i));
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.inbox, isEmpty);
    expect(progress, hasLength(2));
    expect((progress[0] as ImMessageProgressEvent).progress, 99);
    expect((progress[1] as ImMessageDownloadProgressEvent).progress.currentSize,
        99);
    service.listener!.onSendMessageProgress(message, 100);
    service.listener!
        .onSendMessageProgress(message, 30); // late obsolete sample
    service.listener!
        .onMessageDownloadProgressCallback(_download(1000, finished: true));
    await tester.pump();
    expect(events, hasLength(2));
    expect(store.inbox, hasLength(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress, hasLength(2));
    service.listener!
        .onMessageDownloadProgressCallback(_download(0)); // new attempt
    service.listener!.onMessageDownloadProgressCallback(_download(1, error: 5));
    await tester.pump();
    expect(events, hasLength(3));
    await adapter.unregister();
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress, hasLength(2));
  });

  testWidgets(
      'both receipt callbacks share identity and read-state changes survive',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add);
    await adapter.register();
    final receipt = V2TimMessageReceipt(
        userID: 'bob', timestamp: 100, msgID: 'm', isPeerRead: true);
    service.listener!.onRecvC2CReadReceipt([receipt]);
    service.listener!.onRecvMessageReadReceipts([receipt]);
    await tester.pump();
    expect(store.inbox, hasLength(3));
    expect(events, hasLength(1));
    service.listener!.onRecvC2CReadReceipt([receipt]);
    await tester.pump();
    expect(events, hasLength(1));
    final recovery = store.inbox.values
        .firstWhere((row) => row.event.eventId.startsWith('message-read:'))
        .recoveryRef;
    final restored = V2TimMessageReceipt.fromJson(
        jsonDecode(recovery.substring('receipt-json:'.length)) as Map);
    expect(restored.toJson(), receipt.toJson());
    service.listener!.onRecvMessageReadReceipts([
      V2TimMessageReceipt(
          userID: '',
          groupID: 'g',
          msgID: 'gm',
          timestamp: 0,
          readCount: 1,
          unreadCount: 2)
    ]);
    service.listener!.onRecvMessageReadReceipts([
      V2TimMessageReceipt(
          userID: '',
          groupID: 'g',
          msgID: 'gm',
          timestamp: 0,
          readCount: 2,
          unreadCount: 1)
    ]);
    await tester.pump();
    expect(events, hasLength(3));
    expect(store.inbox, hasLength(7));
    await adapter.unregister();
  });

  testWidgets(
      'completed duplicate skips dispatch; pending duplicate can recover',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add);
    await adapter.register();
    service.listener!.onRecvNewMessage(_message());
    await tester.pump();
    service.listener!.onRecvNewMessage(_message());
    await tester.pump();
    expect(events, hasLength(2));
    final key = store.inbox.keys.single;
    store.inbox[key] =
        store.inbox[key]!.copyWith(status: ImInboxStatus.completed);
    service.listener!.onRecvNewMessage(_message());
    await tester.pump();
    expect(events, hasLength(2));
    expect(store.inbox, hasLength(1));
    await adapter.unregister();
  });
  testWidgets(
      'identical terminal is delivered again for a new transfer attempt',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add);
    await adapter.register();
    service.listener!.onMessageDownloadProgressCallback(_download(3, error: 5));
    await tester.pump();
    expect(events, hasLength(1));
    final first = events.single;
    final rowKey = store.inbox.keys.single;
    store.inbox[rowKey] =
        store.inbox[rowKey]!.copyWith(status: ImInboxStatus.completed);
    service.listener!.onMessageDownloadProgressCallback(_download(0));
    expect(adapter.isCurrentUiProgress(first.payload as Object), isFalse);
    service.listener!.onMessageDownloadProgressCallback(_download(2));
    service.listener!.onMessageDownloadProgressCallback(_download(3, error: 5));
    await tester.pump();
    expect(events, hasLength(2));
    expect(events.last.eventId, isNot(first.eventId));
    expect(adapter.isCurrentUiProgress(events.last.payload as Object), isTrue);
    await adapter.unregister();
  });

  testWidgets(
      'restart fences terminal waiting behind a slow old progress callback',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final release = Completer<void>();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add,
        onUiProgress: (_) => release.future);
    await adapter.register();
    service.listener!.onMessageDownloadProgressCallback(_download(2));
    await tester.pump(const Duration(milliseconds: 50));
    service.listener!.onMessageDownloadProgressCallback(_download(3, error: 5));
    service.listener!.onMessageDownloadProgressCallback(_download(0));
    release.complete();
    await tester.pump();
    expect(events, isEmpty);
    service.listener!
        .onMessageDownloadProgressCallback(_download(1000, finished: true));
    await tester.pump();
    expect(events, hasLength(1));
    await adapter.unregister();
  });

  testWidgets(
      'same-account domain invalidation stops queued progress and terminals',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    var currentDomain = 1;
    final values = <Object>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: (_) {},
        onUiProgress: values.add,
        isUiProgressLifecycleCurrent: () => currentDomain == 1);
    await adapter.register();
    service.listener!.onMessageDownloadProgressCallback(_download(2));
    currentDomain = 2;
    await tester.pump(const Duration(milliseconds: 50));
    service.listener!
        .onMessageDownloadProgressCallback(_download(1000, finished: true));
    await tester.pump();
    expect(values, isEmpty);
    expect(store.inbox, isEmpty);
    await adapter.unregister();
  });

  testWidgets(
      'reversed receipt replay is durable-idempotent after adapter recreation',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    TencentAdvancedMessageAdapter create() => TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add);
    var adapter = create();
    await adapter.register();
    final receipts = [
      V2TimMessageReceipt(
          userID: '', groupID: 'g', msgID: 'a', timestamp: 0, readCount: 1),
      V2TimMessageReceipt(
          userID: '', groupID: 'g', msgID: 'b', timestamp: 0, readCount: 2)
    ];
    service.listener!.onRecvMessageReadReceipts(receipts);
    await tester.pump();
    expect(events, hasLength(1));
    final rowKey = store.inbox.entries
        .firstWhere((entry) =>
            entry.value.event.eventId.startsWith('receipt-compat-batch:'))
        .key;
    store.inbox[rowKey] =
        store.inbox[rowKey]!.copyWith(status: ImInboxStatus.completed);
    await adapter.unregister();
    adapter = create();
    await adapter.register();
    service.listener!.onRecvMessageReadReceipts(receipts.reversed.toList());
    await tester.pump();
    expect(store.inbox, hasLength(3));
    expect(events, hasLength(1));
    expect(adapter.ingestFailureCount, 0);
    await adapter.unregister();
  });

  testWidgets(
      'batch preserves latest group counters and generic C2C receipt semantics',
      (tester) async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: store),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add);
    await adapter.register();
    service.listener!.onRecvMessageReadReceipts([
      V2TimMessageReceipt(
          userID: '',
          groupID: 'g',
          msgID: 'a',
          timestamp: 0,
          readCount: 1,
          unreadCount: 2),
      V2TimMessageReceipt(
          userID: '',
          groupID: 'g',
          msgID: 'a',
          timestamp: 0,
          readCount: 2,
          unreadCount: 1),
      V2TimMessageReceipt(
          userID: 'bob', msgID: 'm1', timestamp: 0, isPeerRead: true),
    ]);
    await tester.pump();
    expect(events, hasLength(2));
    final batches = events.map((e) => e.payload as ImReadReceiptBatch).toList();
    expect(batches.every((b) => !b.applyC2CWatermark), isTrue);
    expect(batches.first.receipts.single.readCount, 2);
    // A later watermark still has work to do even if generic state arrived first.
    service.listener!.onRecvC2CReadReceipt([
      V2TimMessageReceipt(
          userID: 'bob', msgID: 'm1', timestamp: 0, isPeerRead: true)
    ]);
    await tester.pump();
    expect(events, hasLength(3));
    expect(
        (events.last.payload as ImReadReceiptBatch).applyC2CWatermark, isTrue);
    await adapter.unregister();
  });
  for (final completedOthers in [129, 260]) {
    testWidgets(
        'old transfer retry stays distinct after $completedOthers terminals',
        (tester) async {
      final service = _Service();
      final store = InMemoryImIngressStore();
      final events = <EventEnvelope<dynamic>>[];
      final adapter = TencentAdvancedMessageAdapter(
          messageService: service,
          ingress: DurableIngressGateway(store: store),
          ownerUserId: 'alice',
          accountGeneration: 1,
          domainGeneration: 1,
          onEvent: events.add);
      await adapter.register();
      service.listener!
          .onMessageDownloadProgressCallback(_download(3, error: 5));
      await tester.pump();
      final first = events.single;
      final rowKey = store.inbox.keys.single;
      store.inbox[rowKey] =
          store.inbox[rowKey]!.copyWith(status: ImInboxStatus.completed);
      for (var i = 0; i < completedOthers; i++) {
        service.listener!.onMessageDownloadProgressCallback(
            _download(3, error: 5)..msgID = 'other$i');
      }
      await tester.pump();
      service.listener!.onMessageDownloadProgressCallback(_download(0));
      service.listener!
          .onMessageDownloadProgressCallback(_download(3, error: 5));
      await tester.pump();
      expect(events, hasLength(completedOthers + 2));
      expect(events.last.eventId, isNot(first.eventId));
      expect(adapter.ingestFailureCount, 0);
      await adapter.unregister();
    });
  }
}
