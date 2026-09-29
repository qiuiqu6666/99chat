import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    setupServiceLocator();
  });

  late HistoryWindowRepository? previousRepository;
  late TUIChatGlobalModel global;

  setUp(() {
    previousRepository = HistoryWindowRepositoryProvider.repository;
    HistoryWindowRepositoryProvider.repository = null;
    global = TUIChatGlobalModel();
    global.configureMessageWriterScope(
      ownerUserID: 'ack-key-reader',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    global.chatConfig = const TIMUIKitChatConfig(
      isAutoReportRead: false,
      inboundChunkRevealEnabled: true,
    );
  });

  tearDown(() {
    global.dispose();
    HistoryWindowRepositoryProvider.repository = previousRepository;
  });

  V2TimMessage seedMessage() => V2TimMessage.fromJson(<String, dynamic>{
        'message_msg_id': 'seed',
        'message_server_time': 1,
        'message_risk_type_identified': 0,
      })
        ..userID = 'rqwm8onw3j'
        ..isSelf = true
        ..elemType = 1;

  V2TimMessage inboundMessage(String msgId) =>
      V2TimMessage.fromJson(<String, dynamic>{
        'message_msg_id': msgId,
        'message_server_time': 10,
        'message_risk_type_identified': 0,
      })
        ..userID = 'rqwm8onw3j'
        ..isSelf = false
        ..elemType = 1;

  Future<void> pumpQuiet(WidgetTester tester, [Duration? duration]) async {
    final handler = FlutterError.onError;
    await tester.pump(duration);
    FlutterError.onError = handler;
  }

  Future<void> openC2cAndWaitForReveal(
    WidgetTester tester,
    V2TimMessage incoming,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const storageKey = 'c2c_rqwm8onw3j';
    global.setCurrentConversation(
      CurrentConversation(storageKey, ConvType.c2c),
      notify: false,
    );
    global.setMessageList(storageKey, <V2TimMessage>[seedMessage()],
        replace: true, applyMemoryWindow: false);
    global.markInitialHistoryLoaded(storageKey);
    global.setFollowingLatest(storageKey, true, notify: false);
    global.setMessageListPosition(
      storageKey,
      HistoryMessagePosition.bottom,
      notify: false,
    );
    await global.applyAppRealtimeMessage(incoming);
    await pumpQuiet(tester, const Duration(milliseconds: 80));
    await pumpQuiet(tester);
  }

  testWidgets(
      'bare-id completeInboundProjectionReveal releases c2c_* waiting',
      (tester) async {
    const storageKey = 'c2c_rqwm8onw3j';
    const bareId = 'rqwm8onw3j';
    await openC2cAndWaitForReveal(tester, inboundMessage('in-1'));

    expect(global.isInboundProjectionRevealWaiting(storageKey), isTrue,
        reason: 'enqueue must wait on the storage key before ACK');

    global.completeInboundProjectionReveal(bareId);

    expect(global.isInboundProjectionRevealWaiting(storageKey), isFalse,
        reason: 'wrapper must resolve bare id onto c2c_* waiting');

    await global.applyAppRealtimeMessage(inboundMessage('in-2'));
    await pumpQuiet(tester, const Duration(milliseconds: 80));
    await pumpQuiet(tester);

    expect(global.isInboundProjectionRevealWaiting(storageKey), isTrue,
        reason: 'next realtime message must start a new transaction');
    global.completeInboundProjectionReveal(storageKey);
    expect(global.isInboundProjectionRevealWaiting(storageKey), isFalse);
  });
}
