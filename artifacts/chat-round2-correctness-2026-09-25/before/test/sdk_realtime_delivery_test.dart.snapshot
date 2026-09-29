import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
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

V2TimMessage _message(String id, {int type = 1}) => V2TimMessage.fromJson({
      'message_msg_id': id,
      'message_sender': 'bob',
      'message_conv_type': 1,
      'message_conv_id': 'bob',
      'message_risk_type_identified': 0,
      'message_elem_array': <Object?>[],
    })
      ..elemType = type
      ..isSelf = false;

void main() {
  test(
      'SDK ordinary delivery bypasses Inbox and deduplicates pending callbacks',
      () async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final release = Completer<void>();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
      messageService: service,
      ingress: DurableIngressGateway(store: store),
      ownerUserId: 'alice',
      accountGeneration: 2,
      domainGeneration: 3,
      onEvent: (_) => fail('ordinary message entered durable path'),
      sdkRealtimeClearEpoch: (_) => 7,
      onSdkRealtimeEvent: (event) async {
        events.add(event);
        await release.future;
      },
    );
    await adapter.register();
    final message = _message('ordinary');
    service.listener!.onRecvNewMessage(message);
    service.listener!.onRecvNewMessage(message);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.clearEpoch, 7);
    expect(events.single.accountGeneration, 2);
    expect(events.single.domainGeneration, 3);
    expect(events.single.eventNamespace,
        TencentAdvancedMessageAdapter.sdkRealtimeNamespace);
    expect(store.inbox, isEmpty);
    release.complete();
    await Future<void>.delayed(Duration.zero);
    service.listener!.onRecvNewMessage(message);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    await adapter.unregister();
  });

  test('custom, membership and outgoing confirmation retain durable recovery',
      () async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final events = <EventEnvelope<dynamic>>[];
    final adapter = TencentAdvancedMessageAdapter(
      messageService: service,
      ingress: DurableIngressGateway(store: store),
      ownerUserId: 'alice',
      accountGeneration: 2,
      domainGeneration: 3,
      onEvent: events.add,
      onSdkRealtimeEvent: (_) => fail('business event lost durable recovery'),
    );
    await adapter.register();
    service.listener!.onRecvNewMessage(_message('business', type: 2));
    service.listener!.onRecvNewMessage(_message('membership', type: 9));
    final scope = AccountScopedConversationKey(
        ownerUserId: 'alice',
        conversationType: ImConversationType.c2c,
        conversationId: 'bob');
    final outgoing = _message('sent')
      ..isSelf = true
      ..cloudCustomData = jsonEncode(OutgoingIdentityContract(
              scope: scope,
              operationId: 'send_1',
              clientCorrelationId: 'client_1',
              messageKind: OutgoingMessageKind.text,
              payloadFingerprint: 'fingerprint',
              createdAtMs: 10)
          .toCloudCustomData());
    service.listener!.onRecvNewMessage(outgoing);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(3));
    expect(store.inbox, hasLength(3));
    expect(events.every((event) => event.eventNamespace == 'chat'), isTrue);
    await adapter.unregister();
  });

  test('SDK projection failure retries without creating Inbox records',
      () async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    final delivered = Completer<void>();
    var attempts = 0;
    var failures = 0;
    final adapter = TencentAdvancedMessageAdapter(
      messageService: service,
      ingress: DurableIngressGateway(store: store),
      ownerUserId: 'alice',
      accountGeneration: 2,
      domainGeneration: 3,
      onEvent: (_) => fail('retry used durable path'),
      onSdkRealtimeEvent: (_) {
        if (++attempts == 1) throw StateError('temporarily unavailable');
        delivered.complete();
      },
      onIngestFailure: (_, error, stack, {required attempt, required dropped}) {
        failures++;
        expect(dropped, isFalse);
      },
    );
    await adapter.register();
    service.listener!.onRecvNewMessage(_message('retry'));
    await delivered.future.timeout(const Duration(seconds: 3));
    expect(attempts, 2);
    expect(failures, 1);
    expect(store.inbox, isEmpty);
    await adapter.unregister();
  });

  test('stale SDK adapter and detached callback cannot publish live content',
      () async {
    final service = _Service();
    final store = InMemoryImIngressStore();
    var current = true;
    var calls = 0;
    final adapter = TencentAdvancedMessageAdapter(
      messageService: service,
      ingress: DurableIngressGateway(store: store),
      ownerUserId: 'alice',
      accountGeneration: 2,
      domainGeneration: 3,
      onEvent: (_) => fail('stale callback entered durable path'),
      onSdkRealtimeEvent: (_) {
        calls++;
      },
      isUiProgressLifecycleCurrent: () => current,
    );
    await adapter.register();
    final listener = service.listener!;
    current = false;
    listener.onRecvNewMessage(_message('stale'));
    await Future<void>.delayed(Duration.zero);
    await adapter.unregister();
    current = true;
    listener.onRecvNewMessage(_message('detached'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    expect(store.inbox, isEmpty);
  });
}
