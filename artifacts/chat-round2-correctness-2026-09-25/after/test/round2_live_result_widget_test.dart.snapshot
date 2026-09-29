import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_contracts.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im05_persistence.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/outgoing_send_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/account_scoped_conversation_key.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/contracts/outgoing_identity_contract.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_friendship_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'already rendered failed UIKit row removes its real retry icon after committed success',
      (tester) async {
    final frameworkErrorHandler = FlutterError.onError;
    addTearDown(() => FlutterError.onError = frameworkErrorHandler);
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(_MetadataOnlyService());
    final global = serviceLocator<TUIChatGlobalModel>();
    global.clearData();
    final separate = TUIChatSeparateViewModel()
      ..conversationID = 'bob'
      ..conversationType = ConvType.c2c;
    final store = InMemoryImIngressStore();
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
            updatedAtMs: 10),
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
            updatedAtMs: 10),
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 10);
    final intent = await persistence.recordDispatchIntent(
        ownerUserId: 'alice',
        operationId: 'op',
        dispatchAttemptId: 'attempt',
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 11);
    await persistence.transitionOutbox(
        next: intent.main!.copyWith(state: ImOutboxState.sending),
        expectedState: ImOutboxState.dispatchIntent,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 12);
    final view = persistence.watchOutboxResult('alice', 'op');
    final failed = await persistence.adjudicateOutboxSdkResult(
        ownerUserId: 'alice',
        operationId: 'op',
        expectedAttemptId: 'attempt',
        succeeded: false,
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 15,
        resultCode: '6012',
        sdkLocalId: 'local');
    final message = V2TimMessage.fromJson({'message_risk_type_identified': 0})
      ..id = 'local'
      ..msgID = 'server'
      ..sender = 'alice'
      ..userID = 'bob'
      ..isSelf = true
      ..elemType = 1
      ..timestamp = 1700000000
      ..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    global.setMessageList('bob', [message], replace: true);
    final result = ImCoordinatedSendResult(
        sdkResult: V2TimValueCallback<V2TimMessage>(
            code: 6012, desc: 'failed', data: message),
        usedOutbox: true,
        identity: OutgoingIdentityContract(
            scope: AccountScopedConversationKey(
                ownerUserId: 'alice',
                conversationType: ImConversationType.c2c,
                conversationId: 'c2c_bob'),
            operationId: 'op',
            clientCorrelationId: 'corr',
            messageKind: OutgoingMessageKind.text,
            payloadFingerprint: 'hash',
            createdAtMs: 10),
        outboxResult: failed,
        resultView: view);
    global.applyOutgoingSendResult(
        result.sdkResult, 'bob', 'local', ConvType.c2c, null, null,
        coordinatedResult: result);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
              value: separate),
          ChangeNotifierProvider<TUIFriendShipViewModel>.value(
              value: serviceLocator<TUIFriendShipViewModel>()),
          ChangeNotifierProvider<ChatUiStateStore>.value(
              value: serviceLocator<ChatUiStateStore>()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ListView(children: [
          TIMUIKitHistoryMessageListItem(
              message: message,
              showAvatar: false,
              showMessageReadReceipt: false,
              messageItemBuilder: MessageItemBuilder(
                  textMessageItemBuilder: (_, __, ___) => const Text('A'))),
        ])))));
    await tester.pump(const Duration(milliseconds: 50));
    FlutterError.onError = frameworkErrorHandler;
    expect(find.byIcon(Icons.error), findsOneWidget);
    await persistence.adoptOutboxProviderSucceeded(
        ownerUserId: 'alice',
        operationId: 'op',
        clientCorrelationId: 'corr',
        conversationId: 'alice|c2c_bob',
        payloadHash: 'hash',
        leaseOwnerId: 'writer',
        fencingToken: lease.fencingToken,
        nowMs: 20,
        serverMsgId: 'server');
    await tester.pump(const Duration(milliseconds: 50));
    FlutterError.onError = frameworkErrorHandler;
    print(
        'live-probe: stored=${view.current?.currentState} row=${global.rawMessageList('bob')?.first.status} effective=${result.sdkResult.code}');
    expect(find.byIcon(Icons.error), findsNothing);
    expect(global.rawMessageList('bob')!.single.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(global.getConversationPreviewMessage('bob')!.status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(result.currentOutboxResult!.canRetry, isFalse);
    await tester.pumpWidget(const SizedBox());
    global.clearData();
    separate.dispose();
    await tester.pump(const Duration(seconds: 3));
  });
}

class _MetadataOnlyService implements MessageService {
  @override
  Future<V2TimCallback> setLocalCustomData(
          {required String msgID, required String localCustomData}) async =>
      V2TimCallback(code: 0, desc: '');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected SDK ${invocation.memberName}');
}
