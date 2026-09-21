import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _row(String conv, int seq) => V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
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

class _LatestRecoverySdk extends MessageService {
  final olderGate = Completer<void>();
  int olderCalls = 0;
  int newerCalls = 0;
  int activeCalls = 0;

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
    final boundary = int.tryParse(lastMsg?.seq ?? '') ?? lastMsgSeq;
    final newer = getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    activeCalls++;
    try {
      if (newer) {
        newerCalls++;
      } else {
        olderCalls++;
        await olderGate.future;
      }
      return MessageHistorySdkResult(
        code: 0,
        desc: 'controlled history page',
        data: V2TimMessageListResult(
          messageList: [
            for (var index = 1; index <= count; index++)
              _row(groupID!, boundary + (newer ? index : -index)),
          ],
          isFinished: false,
        ),
      );
    } finally {
      activeCalls--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _LatestRecoverySdk sdk;
  late _ReadingModel model;
  late TUIChatGlobalModel global;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  late V2TimConversation conversation;
  var generation = 0;
  var platform = TargetPlatform.android;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    platform = TargetPlatform.android;
    HistoryWindowRepositoryProvider.repository = null;
    await serviceLocator.unregister<MessageService>();
    sdk = _LatestRecoverySdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    final conv = '@TGS#community_gesture_recovery_${++generation}';
    model = _ReadingModel()
      ..conversationID = conv
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Community')
      ..chatConfig = const TIMUIKitChatConfig(
          isAutoReportRead: false,
          isShowReadingStatus: false,
          inboundChunkRevealEnabled: true,
          isUseDraft: false)
      ..suppressReadReporting = true
      ..haveMoreData = true
      ..haveMoreLatestData = true;
    global.configureMessageWriterScope(
        ownerUserID: 'community-gesture-recovery-owner',
        accountGeneration: generation,
        domainGeneration: 1);
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    global.setMessageList(
        conv, [for (var seq = 100; seq >= 61; seq--) _row(conv, seq)],
        replace: true, applyMemoryWindow: false);
    global.markInitialHistoryLoaded(conv);
    global.markMemoryWindowMissingNewer(conv);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    conversation = V2TimConversation(
        conversationID: 'group_$conv',
        groupID: conv,
        type: 2,
        unreadCount: 0,
        lastMessage: _row(conv, 100));
  });

  Widget build() => MultiProvider(
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
                key: const Key('community-history-list'),
                model: model,
                conversation: conversation,
                controller: controller,
                mainHistoryListConfig: TIMUIKitHistoryMessageListConfig(
                  physics: platform == TargetPlatform.iOS
                      ? const BouncingScrollPhysics()
                      : const ClampingScrollPhysics(),
                ),
                messageList: messages,
                onLoadMore: (id, direction, [count, seq, message]) =>
                    model.loadChatRecord(
                        count: count ?? 20,
                        direction: direction,
                        lastMsgID: id,
                        lastMsgSeq: seq ?? -1,
                        lastMsg: message),
                itemBuilder: (_, message) => SizedBox(
                  key: ValueKey('row-${message?.msgID}'),
                  height: message?.elemType == 11 ? 24 : 64,
                  child: Text('seq:${message?.seq}'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final handler = FlutterError.onError;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = handler;
  }

  Future<void> frames(WidgetTester tester, [int count = 25]) async {
    for (var index = 0; index < count; index++) {
      await frame(tester);
    }
  }

  Future<void> waitUntil(
      WidgetTester tester, bool Function() ready, String reason) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
      await frame(tester);
    }
    expect(ready(), isTrue, reason: reason);
  }

  List<int> currentSeqs() => global
      .rawMessageList(model.conversationID)!
      .map((message) => int.parse(message.seq!))
      .toList();

  Future<void> holdOlderAndReachLatest(WidgetTester tester,
      {bool wheel = false}) async {
    final targetPlatform = platform;
    platform = TargetPlatform.android;
    final handler = FlutterError.onError;
    await tester.pumpWidget(build());
    FlutterError.onError = handler;
    await frames(tester);
    final list = find.byType(CustomScrollView);
    final reachingOlder = Stopwatch()..start();
    while (sdk.olderCalls == 0 &&
        reachingOlder.elapsed < const Duration(seconds: 10)) {
      await tester.drag(list, const Offset(0, 600), touchSlopY: 0);
      await frames(tester, 8);
    }
    expect(sdk.olderCalls, greaterThan(0));
    expect(sdk.activeCalls, greaterThan(0));
    if (targetPlatform != platform) {
      platform = targetPlatform;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await frames(tester, 2);
    }
    // Reverse direction while the old page is still waiting on transport.
    // The final edge gesture is released before that page is allowed to finish.
    var minimumOffset = scroll.offset;
    void trackOffset() {
      if (scroll.offset < minimumOffset) minimumOffset = scroll.offset;
    }

    scroll.addListener(trackOffset);
    if (wheel) {
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: Offset(0, scroll.position.maxScrollExtent + 600),
      ));
    } else {
      await tester.drag(list, Offset(0, -scroll.position.maxScrollExtent - 600),
          touchSlopY: 0);
    }
    await frames(tester, 50);
    scroll.removeListener(trackOffset);
    if (platform == TargetPlatform.iOS) {
      expect(minimumOffset, lessThan(scroll.position.minScrollExtent - 10),
          reason: 'this fixture must exercise a real iOS edge rebound');
    }
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
    expect(sdk.newerCalls, 0);
  }

  Future<void> releaseOlder(WidgetTester tester) async {
    sdk.olderGate.complete();
    await waitUntil(
        tester,
        () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
        'the older request must finish');
  }

  Future<void> close(WidgetTester tester) async {
    if (!sdk.olderGate.isCompleted) sdk.olderGate.complete();
    await waitUntil(
        tester,
        () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
        'history transport must settle before disposing the fixture');
    await tester.pumpWidget(const SizedBox.shrink());
    global.dismissAllContextMenuOverlays();
    global.clearActiveChatScrollController(
        conversationID: model.conversationID);
    model.dispose();
    global.clearData();
    controller.dispose();
    scroll.dispose();
    await frame(tester, 2000);
  }

  testWidgets('released latest gesture resumes exactly once after older load',
      (tester) async {
    try {
      await holdOlderAndReachLatest(tester);
      await releaseOlder(tester);
      await waitUntil(tester, () => sdk.newerCalls == 1,
          'the released edge gesture must resume without another drag');
      await frames(tester, 100);
      expect(sdk.newerCalls, 1,
          reason: 'one deferred gesture must not automatically chain pages');
      expect(currentSeqs(), contains(120));
    } finally {
      await close(tester);
    }
  });

  testWidgets('iOS rebound preserves the released latest gesture',
      (tester) async {
    platform = TargetPlatform.iOS;
    try {
      await holdOlderAndReachLatest(tester);
      await releaseOlder(tester);
      await waitUntil(tester, () => sdk.newerCalls == 1,
          'spring rebound is not a reverse user gesture');
      await frames(tester, 100);
      expect(sdk.newerCalls, 1);
    } finally {
      await close(tester);
    }
  });
  testWidgets('mouse wheel at latest retains a request through an older load',
      (tester) async {
    try {
      await holdOlderAndReachLatest(tester, wheel: true);
      await releaseOlder(tester);
      await waitUntil(tester, () => sdk.newerCalls == 1,
          'pointer scrolling must retain the same latest-load intent');
      await frames(tester, 100);
      expect(sdk.newerCalls, 1);
    } finally {
      await close(tester);
    }
  });

  testWidgets('context menu holds the pending latest request until closing',
      (tester) async {
    try {
      await holdOlderAndReachLatest(tester);
      global.beginMessageContextMenuOverlay(
          conversationID: model.conversationID);
      await frames(tester, 5);
      await releaseOlder(tester);
      await frames(tester, 100);
      expect(sdk.newerCalls, 0,
          reason: 'the active menu owns its underlying message viewport');
      global.endMessageContextMenuOverlay(conversationID: model.conversationID);
      await waitUntil(tester, () => sdk.newerCalls == 1,
          'closing the menu resumes a still-valid latest edge request');
      await frames(tester, 100);
      expect(sdk.newerCalls, 1);
    } finally {
      await close(tester);
    }
  });
  testWidgets('reversing away from latest cancels the held gesture',
      (tester) async {
    try {
      await holdOlderAndReachLatest(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400),
          touchSlopY: 0);
      await frames(tester, 20);
      expect(scroll.offset - scroll.position.minScrollExtent, greaterThan(96));
      await releaseOlder(tester);
      await frames(tester, 100);
      expect(sdk.newerCalls, 0,
          reason: 'history movement must discard the old latest intent');
    } finally {
      await close(tester);
    }
  });
}
