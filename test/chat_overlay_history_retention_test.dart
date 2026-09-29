import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/api/lottery_live_api.dart';
import 'package:tencent_cloud_chat_demo/src/pages/settings/lottery_drawer.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_history_warm_scheduler.dart';
import 'package:tencent_cloud_chat_demo/src/services/external_chat_entry_service.dart';
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

import 'lottery_live_fixture.dart';

class _OverlayHistoryModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = ConversationHistoryWarmScheduler.instance;
  final registry = ActiveChatRegistry.instance;
  late TUIChatGlobalModel global;
  late _OverlayHistoryModel model;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  late String groupID;
  var generation = 0;

  void seed(String id, {int count = 10}) {
    global.setMessageList(
      id,
      List.generate(count, (index) {
        final seq = count - index;
        return V2TimMessage.fromJson({
          'message_msg_id': '$id-$seq',
          'message_conv_id': id,
          'message_conv_type': 2,
          'message_server_time': seq,
          'message_risk_type_identified': 0,
        })
          ..groupID = id
          ..seq = '$seq'
          ..timestamp = seq
          ..isSelf = false
          ..status = 2
          ..elemType = 1
          ..textElem = V2TimTextElem(text: 'message $seq');
      }),
      replace: true,
      applyMemoryWindow: false,
    );
    global.markInitialHistoryLoaded(id);
    global.markInitialHistoryMayHaveOlder(id, mayHaveOlder: true);
  }

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    scheduler.resetForTest();
    registry.reset();
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    groupID = '@TGS#overlay_history_${++generation}';
    global.configureMessageWriterScope(
      ownerUserID: 'overlay-history-test',
      accountGeneration: generation,
      domainGeneration: 1,
    );
    model = _OverlayHistoryModel()
      ..conversationID = groupID
      ..conversationType = ConvType.group
      ..groupInfo = V2TimGroupInfo(groupID: groupID, groupType: 'Public')
      ..chatConfig = const TIMUIKitChatConfig(
        isAutoReportRead: false,
        isShowReadingStatus: false,
        isUseDraft: false,
      )
      ..suppressReadReporting = true;
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(CurrentConversation(groupID, ConvType.group),
        notify: false);
    seed(groupID);
    registry.enter('group_$groupID', conversationType: ConvType.group);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    lotteryLiveApi = FakeLotteryApi();
    lotteryLiveApi.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(
          Response(requestOptions: options, data: liveFixture(options.path)));
    }));
  });

  tearDown(() {
    scheduler.resetForTest();
    registry.reset();
    lotteryLiveApi.dio.interceptors.clear();
    model.dispose();
    global.clearData();
    controller.dispose();
    scroll.dispose();
  });

  testWidgets('covered group survives orphan cleanup, including SDK ID aliases',
      (tester) async {
    registry.updateRouteVisible(false);
    seed('closed-group');
    scheduler.reconcileStaleMessageMemory(global);
    expect(global.rawMessageCount(groupID), 10);
    expect(global.hasInitialHistoryLoaded(groupID), isTrue);
    expect(global.rawMessageCount('closed-group'), 0);
    expect(registry.isActiveChat(groupID), isFalse,
        reason: 'Keeping history must not mark covered messages as read.');
  });

  testWidgets(
      'covered group survives cache pressure while closed windows evict',
      (tester) async {
    registry.updateRouteVisible(false);
    scheduler.touchMemoryWarm(groupID);
    final cap = ConversationHistoryWarmScheduler.memoryWarmCap;
    for (var i = 0; i < cap + 2; i++) {
      seed('closed-$i', count: 1);
      scheduler.touchMemoryWarm('closed-$i');
    }
    scheduler.evictMemoryWarmForTest(global);
    expect(global.rawMessageCount(groupID), 10);
    expect(global.rawMessageCount('closed-0'), 0);
    expect(global.messageListMap.length, lessThanOrEqualTo(cap));
  });

  testWidgets('covered open group cannot be trimmed as a departed chat',
      (tester) async {
    seed(groupID, count: 30);
    registry.updateRouteVisible(false);
    scheduler.scheduleReleaseAfterChatLeave(groupID);
    expect(global.rawMessageCount(groupID), 30);
    await tester.pump(const Duration(seconds: 16));
    expect(global.rawMessageCount(groupID), 30);
  });

  testWidgets('another chat release does not erase a covered group',
      (tester) async {
    seed('previous-group');
    scheduler.scheduleReleaseAfterChatLeave('previous-group');
    registry.updateRouteVisible(false);
    await tester.pump(const Duration(seconds: 16));
    expect(global.rawMessageCount('previous-group'), 0);
    expect(global.rawMessageCount(groupID), 10);
  });

  testWidgets('reopened covered group survives old timer and releases on exit',
      (tester) async {
    registry.leave(groupID);
    scheduler.scheduleReleaseAfterChatLeave(groupID);
    await tester.pump(const Duration(seconds: 5));
    registry.enter('group_$groupID', routeVisible: false);
    await tester.pump(const Duration(seconds: 16));
    expect(global.rawMessageCount(groupID), 10);
    registry.leave(groupID);
    scheduler.scheduleReleaseAfterChatLeave(groupID);
    await tester.pump(const Duration(seconds: 16));
    expect(global.rawMessageCount(groupID), 0);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform lottery popup retains painted history past cleanup',
        (tester) async {
      // A previous visit left a delayed release queued before this visit.
      registry.leave(groupID);
      scheduler.scheduleReleaseAfterChatLeave(groupID);
      registry.enter('group_$groupID');
      final handler = FlutterError.onError;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(builder: (context) {
            // Use the same route visibility publication as the chat page.
            ExternalChatEntryService.instance.updateActiveChatState(
              conversationID: 'group_$groupID',
              isRouteVisible: ModalRoute.of(context)?.isCurrent != false,
              hasVisibleMessages: global.rawMessageCount(groupID) > 0,
            );
            return Scaffold(
              appBar: AppBar(actions: [
                TextButton(
                  onPressed: () => showLotteryDrawer(context,
                      groupUid: groupID, gameId: 'game1'),
                  child: const Text('open lottery'),
                ),
              ]),
              body: TIMUIKitHistoryMessageListSelector(
                conversationID: groupID,
                builder: (_, messages, __) => TIMUIKitHistoryMessageList(
                  model: model,
                  conversation: V2TimConversation(
                    conversationID: 'group_$groupID',
                    groupID: groupID,
                    type: 2,
                    unreadCount: 0,
                  ),
                  controller: controller,
                  messageList: messages,
                  onLoadMore: (id, direction, [count, seq, message]) async =>
                      true,
                  itemBuilder: (_, message) => SizedBox(
                    height: 100,
                    child: Text('row:${message?.seq}'),
                  ),
                ),
              ),
            );
          }),
        ),
      ));
      FlutterError.onError = handler;
      await tester.pumpAndSettle();
      FlutterError.onError = handler;
      expect(find.text('row:10'), findsOneWidget);
      await tester.tap(find.text('open lottery'));
      await tester.pumpAndSettle();
      FlutterError.onError = handler;
      expect(registry.isActiveChat(groupID), isFalse);
      expect(registry.matchesOpenConversation(groupID), isTrue);
      final beforeOffset = scroll.offset;
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 4));
      final remaining = global.rawMessageCount(groupID);
      final painted = tester
          .widget<ChatHistoryVisibility>(find.byType(ChatHistoryVisibility))
          .visible;
      final loading = find.text('正在加载消息…').evaluate().length;
      final afterOffset = scroll.offset;
      // Dismiss the real popup and verify the same rows remain on return.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      final rowStillPresent = find.text('row:10').evaluate().isNotEmpty;
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = handler;
      expect(tester.takeException(), isNull);
      expect(remaining, 10);
      expect(painted, isTrue);
      expect(loading, 0);
      expect(afterOffset, beforeOffset);
      expect(rowStillPresent, isTrue);
    });
  }
}
