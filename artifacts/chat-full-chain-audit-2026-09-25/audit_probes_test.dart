import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/chat_page/chat_draft_controller.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class LocalMetadataOnlyService implements MessageService {
  @override
  Future<V2TimCallback> setLocalCustomData({required String msgID,
    required String localCustomData}) async => V2TimCallback(code: 0, desc: '');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK operation: ${invocation.memberName}');
}

class PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AUDIT concurrent first opens create only one route', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final observer = PushCounter();
    late BuildContext origin;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Builder(builder: (context) {
        origin = context;
        return const SizedBox.shrink();
      }),
    ));
    final before = observer.pushes;
    final conversation = V2TimConversation(
      conversationID: 'c2c_audit', userID: 'audit', type: 1);
    // No locator is registered: exercise the supported warm-up failure path.
    // Observe Navigator.push before mounting either Chat subtree.
    await tester.runAsync(() async {
      unawaited(openOrReuseAppChat<void>(origin, conversation));
      unawaited(openOrReuseAppChat<void>(origin, conversation));
      await Future<void>.delayed(Duration.zero);
    });
    final pushed = observer.pushes - before;
    await tester.pumpWidget(const SizedBox.shrink());
    AppChatRouteRegistry.instance.reset();
    expect(pushed, 1);
  });

  test('AUDIT provider-confirmed success survives a late explicit failure', () async {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(LocalMetadataOnlyService());
    final global = serviceLocator<TUIChatGlobalModel>();
    final delivered = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'audit-local'
      ..msgID = 'audit-server'
      ..isSelf = true
      ..elemType = 1
      ..timestamp = 1700000000
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    global.setMessageList('audit-peer', [delivered], replace: true);
    global.applyOutgoingSendResult(
      V2TimValueCallback<V2TimMessage>(
        code: 6012, desc: 'late SDK failure', data: delivered),
      'audit-peer', 'audit-local', ConvType.c2c, null, null);
    final status = global.rawMessageList('audit-peer')!.single.status;
    global.removeMessageList('audit-peer');
    expect(status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
  });

  test('AUDIT conversation read retry remains scheduled after 20 failures', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const owner = 'audit-read-retry-owner';
    ConversationLocalStore.instance.debugOwnerUserId = owner;
    final store = ConversationReadOutboxStore.instance;
    try {
      await store.clearOwner(owner);
      await store.enqueue(ownerUserId: owner, conversationId: 'c2c_audit',
        lastReadMessageId: 'audit-message', cleanTimestamp: 1700000000);
      for (var i = 0; i < 20; i++) {
        final row = (await store.find(ownerUserId: owner,
          conversationId: 'c2c_audit'))!;
        await store.markRetry(row);
      }
      final row = (await store.find(ownerUserId: owner,
        conversationId: 'c2c_audit'))!;
      expect(row.attemptCount, 20);
      expect(row.nextRetryAtMs - DateTime.now().millisecondsSinceEpoch,
        inInclusiveRange(0, 64000));
    } finally {
      await store.clearOwner(owner);
      ConversationLocalStore.instance.debugOwnerUserId = null;
    }
  });

  test('AUDIT late send completion preserves text entered after submission', () {
    final draft = ChatDraftController();
    // The input layer emits an empty value immediately after submit.
    draft.onChanged('', persist: (_, __) {});
    // The user starts a different, unsent draft while the SDK request is pending.
    draft.onChanged('next unsent draft', persist: (_, __) {});
    // Chat.messageDidSend invokes this unconditionally on the late success.
    draft.markSendCompleted();
    final retainedText = draft.text;
    final suppressesLeaveSave = draft.shouldSuppressLifecyclePersist;
    draft.dispose();
    expect(retainedText, 'next unsent draft');
    expect(suppressesLeaveSave, isFalse);
  });
}
