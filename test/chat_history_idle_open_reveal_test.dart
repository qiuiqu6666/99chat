import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_visibility.dart';

class _IdleOpenModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TUIChatGlobalModel global;
  late _IdleOpenModel model;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  late V2TimConversation conversation;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    final conv = '@TGS#idle_open_${++generation}';
    model = _IdleOpenModel()
      ..conversationID = conv
      ..conversationType = ConvType.group
      ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Public')
      ..chatConfig = const TIMUIKitChatConfig(
        isAutoReportRead: false,
        isShowReadingStatus: false,
        isUseDraft: false,
      )
      ..suppressReadReporting = true;
    global.configureMessageWriterScope(
      ownerUserID: 'idle-open-test',
      accountGeneration: generation,
      domainGeneration: 1,
    );
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    final messages = List.generate(10, (index) {
      final seq = 100 - index;
      return V2TimMessage.fromJson({
        'message_msg_id': '$conv-$seq',
        'message_conv_id': conv,
        'message_conv_type': 2,
        'message_server_time': seq,
        'message_risk_type_identified': 0,
      })
        ..groupID = conv
        ..seq = '$seq'
        ..timestamp = seq
        ..isSelf = false
        ..status = 2
        ..elemType = 1
        ..textElem = V2TimTextElem(text: 'message $seq');
    });
    global.setMessageList(conv, messages,
        replace: true, applyMemoryWindow: false);
    // A partial cached window must go through layout readiness, even though
    // the tall message rows already fill the viewport.
    global.markInitialHistoryLoaded(conv);
    global.markInitialHistoryMayHaveOlder(conv, mayHaveOlder: true);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    conversation = V2TimConversation(
      conversationID: 'group_$conv',
      groupID: conv,
      type: 2,
      unreadCount: 0,
      lastMessage: messages.first,
    );
  });

  tearDown(() {
    model.dispose();
    global.clearData();
    controller.dispose();
    scroll.dispose();
  });

  Widget build(TargetPlatform platform) => MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: TIMUIKitHistoryMessageListSelector(
              conversationID: model.conversationID,
              builder: (_, messages, __) => TIMUIKitHistoryMessageList(
                model: model,
                conversation: conversation,
                controller: controller,
                messageList: messages,
                onLoadMore: (id, direction, [count, seq, message]) async =>
                    true,
                itemBuilder: (_, message) => SizedBox(
                  height: message?.elemType == 11 ? 24 : 200,
                  child: Text('seq:${message?.seq}'),
                ),
              ),
            ),
          ),
        ),
      );

  bool visible(WidgetTester tester) => tester
      .widget<ChatHistoryVisibility>(find.byType(ChatHistoryVisibility))
      .visible;

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform partial cached history reveals without user input',
        (tester) async {
      final handler = FlutterError.onError;
      await tester.pumpWidget(build(platform));
      FlutterError.onError = handler;
      // Only deliver requested frames; manually pumping many frames masks
      // a missing frame request in the layout readiness loop.
      await tester.pumpAndSettle();
      FlutterError.onError = handler;
      final didReveal = visible(tester);
      final messageCount = global.rawMessageCount(model.conversationID);
      final atBottom =
          scroll.position.pixels == scroll.position.minScrollExtent;
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = handler;
      expect(tester.takeException(), isNull);
      expect(messageCount, 10);
      expect(didReveal, isTrue);
      expect(atBottom, isTrue);
    });
  }

  testWidgets('watchdog repaints cached history after frames stop',
      (tester) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(build(TargetPlatform.iOS));
    FlutterError.onError = handler;
    // Finish initial dirty layout, but stop before the geometry sampling loop
    // reaches its stable-frame count. Do not supply more frames until timeout.
    await tester.pump();
    FlutterError.onError = handler;
    expect(visible(tester), isFalse);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump(const Duration(milliseconds: 1700));
    FlutterError.onError = handler;
    final didReveal = visible(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    FlutterError.onError = handler;
    expect(tester.takeException(), isNull);
    expect(didReveal, isTrue);
  });

  testWidgets('leaving during reveal cancels the pending watchdog',
      (tester) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(build(TargetPlatform.iOS));
    FlutterError.onError = handler;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
