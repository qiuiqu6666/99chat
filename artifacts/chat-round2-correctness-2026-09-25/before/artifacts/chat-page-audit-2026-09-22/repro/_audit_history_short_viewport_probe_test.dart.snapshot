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
import 'package:tencent_cloud_chat_uikit/business_logic/controllers/history_pagination_controller.dart'
    show HistoryAvailability;
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/chat_list_pagination_ui_gate.dart';
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

enum _PageMode {
  short,
  duplicate,
  wrongDirection,
  unfinishedEmpty,
  finishedEmpty
}

typedef _Request = ({
  HistoryMsgGetTypeEnum type,
  String? messageID,
  int seq,
  int count,
});

class _CommunitySdk extends MessageService {
  _PageMode mode = _PageMode.short;
  bool recovered = false;
  final firstOlderGate = Completer<void>();
  int gatedCalls = 0;
  int activeCalls = 0;
  final requests = <_Request>[];

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
    requests.add((
      type: getType,
      messageID: lastMsgID ?? lastMsg?.msgID,
      seq: boundary,
      count: count,
    ));
    activeCalls++;
    try {
      if (boundary > 0 && !firstOlderGate.isCompleted) {
        gatedCalls++;
        await firstOlderGate.future;
      }
      late List<V2TimMessage> rows;
      var finished = false;
      if (boundary <= 0) {
        rows = [for (var seq = 100; seq >= 61; seq--) _row(groupID!, seq)];
      } else if (recovered) {
        rows = [
          for (var index = 1; index <= count; index++)
            _row(groupID!, boundary - index),
        ];
      } else {
        switch (mode) {
          case _PageMode.short:
            final length = boundary == 61 ? 5 : count;
            rows = [
              for (var index = 1; index <= length; index++)
                _row(groupID!, boundary - index),
            ];
            finished = length < count;
          case _PageMode.duplicate:
            rows = [for (var seq = 100; seq >= 61; seq--) _row(groupID!, seq)];
            finished = true;
          case _PageMode.wrongDirection:
            rows = [_row(groupID!, 100), _row(groupID, 99)];
            finished = true;
          case _PageMode.unfinishedEmpty:
            rows = [];
          case _PageMode.finishedEmpty:
            rows = [];
            finished = true;
        }
      }
      return MessageHistorySdkResult(
          code: 0,
          desc: 'controlled Community older page',
          data:
              V2TimMessageListResult(messageList: rows, isFinished: finished));
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
  late _CommunitySdk sdk;
  late _ReadingModel model;
  late TUIChatGlobalModel global;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  late V2TimConversation conversation;
  var generation = 0;
  ScrollPhysics? physics;
  var uiOlderLoads = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    physics = null;
    uiOlderLoads = 0;
    HistoryWindowRepositoryProvider.repository = null;
    await serviceLocator.unregister<MessageService>();
    sdk = _CommunitySdk();
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
      ..haveMoreLatestData = false;
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
          home: Scaffold(
            body: TIMUIKitHistoryMessageListSelector(
              conversationID: model.conversationID,
              builder: (_, messages, __) => TIMUIKitHistoryMessageList(
                key: const Key('community-history-list'),
                model: model,
                conversation: conversation,
                controller: controller,
                mainHistoryListConfig:
                    TIMUIKitHistoryMessageListConfig(physics: physics),
                messageList: messages,
                onLoadMore: (id, direction, [count, seq, message]) {
                  if (direction == LoadDirection.previous) uiOlderLoads++;
                  return model.loadChatRecord(
                      count: count ?? 20,
                      direction: direction,
                      lastMsgID: id,
                      lastMsgSeq: seq ?? -1,
                      lastMsg: message);
                },
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

  Future<void> mountAndReachOlder(WidgetTester tester,
      {bool reachExactEdge = false, bool releaseFirst = true}) async {
    final handler = FlutterError.onError;
    await tester.pumpWidget(build());
    FlutterError.onError = handler;
    await frames(tester);
    expect(scroll.hasClients, isTrue);
    expect(sdk.requests, isEmpty,
        reason: 'mounting at newest must not request an older page');
    final reachingOlder = Stopwatch()..start();
    while (sdk.gatedCalls == 0 &&
        reachingOlder.elapsed < const Duration(seconds: 15)) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600),
          touchSlopY: 0);
      await frames(tester, 8);
    }
    expect(sdk.gatedCalls, greaterThan(0));
    expect(sdk.requests.first.seq, 61);
    if (reachExactEdge) {
      // Keep the rejected request in flight while positioning at the real
      // boundary, so setup does not itself consume the later retry gesture.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600),
          touchSlopY: 0);
      await frames(tester);
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    }
    if (!releaseFirst) return;
    sdk.firstOlderGate.complete();
    await waitUntil(
        tester,
        () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
        'the first gesture request must finish before testing retry eligibility');
    await frames(tester);
  }

  Future<void> pumpAndRebuildWithoutGesture(WidgetTester tester) async {
    await frames(tester, 60);
    final handler = FlutterError.onError;
    await tester.pumpWidget(build());
    FlutterError.onError = handler;
    await frames(tester, 60);
  }

  Future<void> waitPreviousCooldown(WidgetTester tester) async {
    // This throttle uses real DateTime, so FakeAsync frames alone do not
    // represent the user's pause between two pagination attempts.
    await tester.runAsync(() => Future<void>.delayed(Duration(
        milliseconds: ChatListPaginationUiGate.loadPreviousCooldownMs + 20)));
    await frames(tester, 2);
  }

  Future<void> idleBeyondProtection(WidgetTester tester) async {
    // Production protection uses DateTime, so advance real time as well as
    // Flutter timers before asserting that an idle retry cannot start later.
    final handler = FlutterError.onError;
    try {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)));
      await frames(tester, 100);
    } finally {
      FlutterError.onError = handler;
    }
  }

  Future<void> close(WidgetTester tester) async {
    if (!sdk.firstOlderGate.isCompleted) sdk.firstOlderGate.complete();
    await waitUntil(
        tester,
        () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
        'SDK work must settle before disposing the Community fixture');
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
  testWidgets('AUDIT touch drag retries a failed automatic short viewport fill', (tester) async {
    try {
      global.setMessageList(model.conversationID,
        [_row(model.conversationID, 100), _row(model.conversationID, 99)],
        replace: true, applyMemoryWindow: false);
      sdk.mode = _PageMode.unfinishedEmpty;
      sdk.firstOlderGate.complete();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await waitUntil(tester, () => uiOlderLoads > 0 && !model.isLoadingChatHistory && sdk.activeCalls == 0,
        'the short viewport must attempt its first automatic fill');
      await idleBeyondProtection(tester);
      final before = uiOlderLoads;
      expect(scroll.position.maxScrollExtent, lessThanOrEqualTo(1));
      sdk.recovered = true;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 180), touchSlopY: 0);
      await idleBeyondProtection(tester);
      print('AUDIT short viewport before=$before after=$uiOlderLoads count=${currentSeqs().length} max=${scroll.position.maxScrollExtent}');
      expect(uiOlderLoads, greaterThan(before),
        reason: 'Once network recovers, a deliberate touch drag must retry short history even when maxScrollExtent is zero.');
      expect(currentSeqs(), contains(98));
    } finally {
      await close(tester);
    }
  });
}
