import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat.dart';

class _CountingHistoryService extends MessageService {
  int localCalls = 0;
  int cloudCalls = 0;

  @override
  Future<MessageHistorySdkResult> getHistoryMessageListWithStatus({
    HistoryMsgGetTypeEnum getType =
        HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    final isCloud =
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG ||
            getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG;
    if (isCloud) {
      cloudCalls++;
    } else {
      localCalls++;
    }
    final conversationID = groupID ?? userID ?? 'local_only_unread';
    return MessageHistorySdkResult(
      code: 0,
      desc: 'counted',
      data: V2TimMessageListResult(
        isFinished: true,
        messageList: [
          V2TimMessage.fromJson({
            'message_msg_id': '$conversationID-local-1',
            'message_conv_id': conversationID,
            'message_conv_type': 2,
            'message_server_time': 1,
            'message_status': 2,
            'message_risk_type_identified': 0,
          }),
        ],
      ),
    );
  }

  @override
  Future<V2TimCallback> markGroupMessageAsRead({
    required String groupID,
  }) async {
    return V2TimCallback(code: 0, desc: 'counted');
  }

  @override
  Future<V2TimCallback> markC2CMessageAsRead({
    required String userID,
  }) async {
    return V2TimCallback(code: 0, desc: 'counted');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected MessageService call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  testWidgets(
      'local-only unread chat initialization uses SDK local history and no cloud request',
      (tester) async {
    final service = _CountingHistoryService();
    await serviceLocator.unregister<MessageService>();
    serviceLocator.registerSingleton<MessageService>(service);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    final global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
      ownerUserID: 'local-only-unread-test-owner',
      accountGeneration: 1,
      domainGeneration: 1,
    );
    final frameworkErrorHandler = FlutterError.onError;
    void restoreFrameworkErrorHandler() {
      FlutterError.onError = frameworkErrorHandler;
    }

    var cleanedUp = false;
    Future<void> cleanup() async {
      if (cleanedUp) {
        return;
      }
      cleanedUp = true;
      restoreFrameworkErrorHandler();
      await tester.pumpWidget(const SizedBox.shrink());
      restoreFrameworkErrorHandler();
      // TIMUIKitChat schedules keyboard/draft/call probes at 350/500/800ms
      // during initState.  They are intentionally uncancellable in the
      // widget, so advance fake time after unmount to let mounted guards drain
      // them before the test binding checks for pending timers.
      await tester.pump(const Duration(seconds: 1));
      restoreFrameworkErrorHandler();
      global.dispose();
      await serviceLocator.unregister<TUIChatGlobalModel>();
      await serviceLocator.unregister<MessageService>();
      restoreFrameworkErrorHandler();
    }

    // Keep this as a fallback, but the test body also awaits cleanup before
    // returning so TestWidgetsFlutterBinding sees no pending timers.
    addTearDown(cleanup);
    const groupID = '@TGS#local_only_unread';
    final conversation = V2TimConversation(
      conversationID: 'group_$groupID',
      groupID: groupID,
      type: 2,
      unreadCount: 12,
      lastMessage: V2TimMessage.fromJson({
        'message_msg_id': 'entry-tip',
        'message_seq': '12',
        'message_conv_id': groupID,
        'message_conv_type': 2,
        'message_server_time': 12,
        'message_status': 2,
        'message_risk_type_identified': 0,
      }),
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: TIMUIKitChat(
            conversation: conversation,
            localOnlyInitialOpen: true,
            entryUnreadCount: 12,
          ),
        ),
      );
      restoreFrameworkErrorHandler();
      await tester.pump(const Duration(milliseconds: 50));
      restoreFrameworkErrorHandler();

      restoreFrameworkErrorHandler();
      expect(tester.takeException(), isNull);
      restoreFrameworkErrorHandler();
      expect(service.localCalls, greaterThan(0));
      restoreFrameworkErrorHandler();
      expect(service.cloudCalls, 0);
    } finally {
      await cleanup();
    }
  });
}
