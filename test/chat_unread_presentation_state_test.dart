import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// Match the controller exposed by the vendored chat widget.
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  var sequence = 0;
  late TUIChatGlobalModel global;
  late TUIChatSeparateViewModel model;
  late AutoScrollController scroll;
  late String conv;

  V2TimMessage row(int id) => V2TimMessage.fromJson({
        'message_msg_id': '$conv-$id',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..groupID = conv
        ..seq = '$id'
        ..status = 2
        ..isSelf = false
        ..elemType = 1;

  Future<void> frame(WidgetTester tester, [int milliseconds = 16]) async {
    final handler = FlutterError.onError;
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = handler;
  }

  Future<void> away(WidgetTester tester) async {
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    global.setFollowingLatest(conv, false, notify: false);
    await frame(tester);
    global.setChatListUserScrolling(false);
    await frame(tester, 250);
  }

  Future<void> receive(WidgetTester tester, int id) async {
    await global.applyAppRealtimeMessage(row(id));
    await frame(tester, 60);
    await frame(tester, 60);
  }

  void uiTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      conv = '@TGS#unread_presentation_${++sequence}';
      global = serviceLocator<TUIChatGlobalModel>();
      global.configureMessageWriterScope(
        ownerUserID: 'presentation-reader',
        accountGeneration: sequence,
        domainGeneration: 1,
      );
      global.chatConfig = const TIMUIKitChatConfig(
        isAutoReportRead: false,
        inboundChunkRevealEnabled: true,
      );
      global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
          notify: false);
      final rows = List.generate(100, (index) => row(100 - index));
      global.setMessageList(conv, rows,
          replace: true, applyMemoryWindow: false);
      model = TUIChatSeparateViewModel()
        ..conversationID = conv
        ..suppressReadReporting = true;
      scroll = AutoScrollController();
      global.bindActiveChatScrollController(
          conversationID: conv, scrollController: scroll);
      global.bindHistoryLiveWindowFreeze(
          conversationID: conv,
          freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded);
      final handler = FlutterError.onError;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: global,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: [
              ListView.builder(
                controller: scroll,
                reverse: true,
                itemExtent: 60,
                itemCount: rows.length,
                itemBuilder: (_, index) => Text('row $index'),
              ),
              TIMUIKitHistoryMessageListTongueContainer(
                messageList: rows,
                conversation: V2TimConversation(
                    conversationID: 'group_$conv', groupID: conv, type: 2),
                scrollToIndexBySeq: (_) async => false,
                scrollToFirstUnread: (_) async => false,
                scrollController: scroll,
                model: model,
                tongueItemBuilder: (tap, type, count) => TextButton(
                    onPressed: tap, child: Text('${type.name}:$count')),
              ),
            ]),
          ),
        ),
      ));
      FlutterError.onError = handler;
      await frame(tester);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        global.clearActiveChatScrollController(conversationID: conv);
        global.clearData();
        model.dispose();
        scroll.dispose();
        await frame(tester, 1000);
      }
    });
  }

  uiTest('legacy pending count cannot turn an empty live ledger into unread',
      (tester) async {
    await away(tester);
    global.receivedNewMessageCount = 9;
    global.notifyListeners();
    await frame(tester, 250);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
    expect(find.text('showUnread:9'), findsNothing);
  });

  uiTest('live ledger determines the capsule when legacy count is zero',
      (tester) async {
    await away(tester);
    await receive(tester, 101);
    await receive(tester, 102);
    global.receivedNewMessageCount = 0;
    global.notifyListeners();
    await frame(tester, 250);
    expect(global.remainingLiveIncomingCountFor(conv), 2);
    expect(find.text('showUnread:2').hitTestable(), findsOneWidget);
  });

  uiTest('visible identities retire the reminder despite legacy count residue',
      (tester) async {
    await away(tester);
    await receive(tester, 101);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
    global.markLiveIncomingSeen(conversationID: conv, ids: ['$conv-101']);
    await frame(tester, 250);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
  });

  uiTest('legacy residue at latest does not reschedule follow commits',
      (tester) async {
    expect(global.isFollowingLatest(conv), isTrue);
    expect(global.remainingLiveIncomingCountFor(conv), 0);
    var modelNotifies = 0;
    model.addListener(() => modelNotifies++);
    global.receivedNewMessageCount = 7;
    global.notifyListeners();
    for (var i = 0; i < 8; i++) {
      await frame(tester);
    }
    expect(modelNotifies, 0,
        reason: 'a compatibility scalar is not pending live presentation');
  });
}
