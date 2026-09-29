import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/durable_ingress_gateway.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/tencent_advanced_message_adapter.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';

class _Service implements MessageService {
  final added = <V2TimAdvancedMsgListener>[];
  final removed = <V2TimAdvancedMsgListener>[];
  final firstRegistration = Completer<void>();
  Completer<void>? removal;
  @override
  Future<void> addAdvancedMsgListener(
      {required V2TimAdvancedMsgListener listener}) {
    added.add(listener);
    return added.length == 1 ? firstRegistration.future : Future.value();
  }

  @override
  Future<void> removeAdvancedMsgListener(
      {V2TimAdvancedMsgListener? listener}) async {
    if (listener != null) removed.add(listener);
    await removal?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'listener timeout allows retry and late registration cannot steal ownership',
      (tester) async {
    final service = _Service();
    final ingress = InMemoryImIngressStore();
    final events = <Object>[];
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: ingress),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: events.add,
        onSdkRealtimeEvent: events.add);
    Object? failure;
    unawaited(adapter.register().catchError((Object e) {
      failure = e;
    }));
    await tester.pump(const Duration(seconds: 11));
    expect(failure, isA<TimeoutException>());
    expect(adapter.isRegistered, isFalse);
    await adapter.register();
    expect(adapter.isRegistered, isTrue);
    final old = service.added.first;
    final current = service.added.last;
    final message = V2TimMessage.fromJson({
      'message_msg_id': 'm1',
      'message_risk_type_identified': 0,
      'message_sender': 'bob',
      'message_conv_type': 1,
      'message_conv_id': 'bob',
      'message_status': 2,
      'message_elem_array': <Object?>[],
    })
      ..userID = 'bob';
    old.onRecvNewMessage(message);
    await tester.pump();
    expect(events, isEmpty);
    current.onRecvNewMessage(message);
    await tester.pump();
    expect(events, hasLength(1));
    service.firstRegistration.complete();
    await tester.pump();
    expect(service.removed, [old]);
    expect(adapter.isRegistered, isTrue);
    await adapter.unregister();
    expect(service.removed, [old, current]);
  });

  testWidgets(
      'unregister fences callbacks before pending SDK registration completes',
      (tester) async {
    final service = _Service();
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: InMemoryImIngressStore()),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: (_) {});
    final oldRegistration = adapter.register();
    await adapter.unregister();
    expect(adapter.isRegistered, isFalse);
    await adapter.register();
    expect(adapter.isRegistered, isTrue);
    service.firstRegistration.complete();
    await oldRegistration;
    expect(adapter.isRegistered, isTrue);
    expect(
        service.removed
            .every((listener) => identical(listener, service.added.first)),
        isTrue);
    await adapter.unregister();
  });

  testWidgets(
      'hung listener removal has a deadline and does not block next registration',
      (tester) async {
    final service = _Service()..firstRegistration.complete();
    final adapter = TencentAdvancedMessageAdapter(
        messageService: service,
        ingress: DurableIngressGateway(store: InMemoryImIngressStore()),
        ownerUserId: 'alice',
        accountGeneration: 1,
        domainGeneration: 1,
        onEvent: (_) {});
    await adapter.register();
    service.removal = Completer<void>();
    Object? error;
    unawaited(adapter.unregister().catchError((Object e) {
      error = e;
    }));
    expect(adapter.isRegistered, isFalse);
    await tester.pump(const Duration(seconds: 11));
    expect(error, isA<TimeoutException>());
    await adapter.register();
    expect(adapter.isRegistered, isTrue);
    service.removal!.complete();
    service.removal = null;
    await adapter.unregister();
  });
}
