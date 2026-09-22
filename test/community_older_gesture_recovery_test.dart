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

  testWidgets('a Community short page continues with the next older gesture',
      (tester) async {
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester);
      expect(currentSeqs(), [for (var seq = 100; seq >= 56; seq--) seq]);
      expect(model.historyAvailability, isNot(HistoryAvailability.exhausted));
      expect(global.messageHistoryCoverageFor(model.conversationID), isNotNull);
      expect(
          global
              .messageHistoryCoverageFor(model.conversationID)!
              .olderExhausted,
          isFalse);
      await waitPreviousCooldown(tester);
      final callsBeforeNextGesture = sdk.requests.length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400),
          touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().last < 56,
          'the next older gesture must continue beyond a five-row short page');
      expect(sdk.requests[callsBeforeNextGesture].seq, 56);
      expect(currentSeqs(), [for (var seq = 100; seq >= 36; seq--) seq]);
    } finally {
      await close(tester);
    }
  });

  for (final mode in [
    _PageMode.duplicate,
    _PageMode.wrongDirection,
    _PageMode.unfinishedEmpty,
  ]) {
    testWidgets('Community ${mode.name} retries only on a new older gesture',
        (tester) async {
      try {
        sdk.mode = mode;
        await mountAndReachOlder(tester);
        expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
        expect(model.historyAvailability, isNot(HistoryAvailability.exhausted));
        final callsAfterRejectedPage = sdk.requests.length;
        sdk.recovered = true;
        await pumpAndRebuildWithoutGesture(tester);
        expect(sdk.requests.length, callsAfterRejectedPage,
            reason: 'idle frames and rebuilds must not retry ${mode.name}');
        expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
            touchSlopY: 0);
        await waitUntil(tester, () => currentSeqs().last < 61,
            'a fresh user gesture must retry the original older cursor');
        expect(sdk.requests[callsAfterRejectedPage].seq, 61);
        expect(sdk.requests[callsAfterRejectedPage].type,
            HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG);
        expect(currentSeqs(), [for (var seq = 100; seq >= 41; seq--) seq]);
        // The recovery request completed after its initiating gesture. Read
        // the newly loaded row with another small, genuine scrolling gesture.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 64),
            touchSlopY: 0);
        await frames(tester);
        expect(find.text('seq:60').hitTestable(), findsOneWidget);
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets('an older mouse wheel at the Community boundary retries once',
      (tester) async {
    try {
      sdk.mode = _PageMode.duplicate;
      await mountAndReachOlder(tester, reachExactEdge: true);
      expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
      expect(model.historyAvailability, isNot(HistoryAvailability.exhausted));
      final callsAfterRejectedPage = sdk.requests.length;
      sdk.recovered = true;
      await pumpAndRebuildWithoutGesture(tester);
      await waitPreviousCooldown(tester);
      expect(sdk.requests.length, callsAfterRejectedPage,
          reason: 'rebuilds and elapsed cooldown do not replace user intent');
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));

      // reverse:true means a negative wheel delta asks for older history.
      // Already being at max extent leaves no scroll displacement and emits
      // no dragDetails; the real pointer signal still has to release retry.
      await tester.sendEventToBinding(PointerScrollEvent(
          position: tester.getCenter(find.byType(CustomScrollView)),
          scrollDelta: const Offset(0, -96)));
      await waitUntil(tester, () => currentSeqs().last < 61,
          'an older wheel signal at the boundary must retry without dragging');
      expect(sdk.requests[callsAfterRejectedPage].seq, 61);
      expect(sdk.requests[callsAfterRejectedPage].type,
          HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG);
      expect(currentSeqs(), [for (var seq = 100; seq >= 41; seq--) seq]);
    } finally {
      await close(tester);
    }
  });

  testWidgets('older loading starts while the finger holds the top overscroll',
      (tester) async {
    TestGesture? gesture;
    try {
      physics = const BouncingScrollPhysics();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await frames(tester);
      // Materialize the older rows before choosing a distance from the edge;
      // the initial lazy-sliver extent is only an estimate.
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester, 2);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester, 2);
      scroll.jumpTo(scroll.position.maxScrollExtent - 80);
      await frames(tester, 2);
      gesture = await tester.startGesture(const Offset(400, 250));
      await gesture.moveBy(const Offset(0, 240));
      await frames(tester, 2);
      expect(scroll.position.outOfRange, isTrue);
      await frames(tester, 20);
      expect(uiOlderLoads, 1,
          reason: 'reaching the top must load without releasing for a rebound');
      expect(sdk.gatedCalls, 1);
    } finally {
      await gesture?.cancel();
      await close(tester);
    }
  });

  testWidgets('one fast older fling loads without a second gesture',
      (tester) async {
    try {
      physics = const BouncingScrollPhysics();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await frames(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester, 2);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester, 2);
      scroll.jumpTo(scroll.position.maxScrollExtent - 700);
      await frames(tester, 2);
      await tester.fling(find.byType(CustomScrollView),
          const Offset(0, 300), 4000);
      await frames(tester, 100);
      expect(uiOlderLoads, 1);
      expect(sdk.gatedCalls, 1);
    } finally {
      await close(tester);
    }
  });

  testWidgets('an initially exhausted edge admits one reading-window probe',
      (tester) async {
    try {
      model.haveMoreData = false;
      sdk.mode = _PageMode.finishedEmpty;
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await frames(tester, 60);
      expect(model.historyAvailability, HistoryAvailability.exhausted);
      expect(uiOlderLoads, 0,
          reason: 'idle layout must not probe an exhausted older boundary');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200),
          touchSlopY: 0);
      await waitUntil(tester, () => uiOlderLoads == 1,
          'the first explicit edge gesture must preserve the end probe');
      sdk.firstOlderGate.complete();
      await waitUntil(tester,
          () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
          'the single end probe must finish');
      await idleBeyondProtection(tester);
      expect(global.isMemoryWindowSuppressed(model.conversationID), isTrue,
          reason: 'the probe must establish the same reading-window ownership');
      final callsAtEnd = sdk.requests.length;
      await pumpAndRebuildWithoutGesture(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
          touchSlopY: 0);
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 1);
      expect(sdk.requests.length, callsAtEnd,
          reason: 'neither rebuild nor another drag may repeat a terminal probe');
      expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
    } finally {
      await close(tester);
    }
  });

  testWidgets('a confirmed empty Community end does not create an SDK loop',
      (tester) async {
    try {
      sdk.mode = _PageMode.finishedEmpty;
      await mountAndReachOlder(tester);
      expect(model.historyAvailability, HistoryAvailability.exhausted);
      expect(model.haveMoreData, isFalse);
      final callsAtEnd = sdk.requests.length;
      await pumpAndRebuildWithoutGesture(tester);
      expect(sdk.requests.length, callsAtEnd);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
          touchSlopY: 0);
      await frames(tester, 60);
      expect(sdk.requests.length, callsAtEnd);
      expect(currentSeqs(), [for (var seq = 100; seq >= 61; seq--) seq]);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'direction changes during a short older page preserve the next gesture',
      (tester) async {
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester,
          reachExactEdge: true, releaseFirst: false);
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, -600), touchSlopY: 0);
      await frames(tester, 3);
      await tester.drag(list, const Offset(0, 600), touchSlopY: 0);
      await frames(tester, 3);
      sdk.firstOlderGate.complete();
      await waitUntil(
          tester,
          () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
          'the short page must finish after direction changes');
      await frames(tester, 3);
      expect(currentSeqs().last, 56);
      final callsAfterShort = sdk.requests.length;
      await tester.drag(list, const Offset(0, 400), touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().last == 36,
          'the next edge gesture must survive the remaining protection window');
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, callsAfterShort + 1,
          reason: 'one fresh gesture must not chain additional pages');
    } finally {
      await close(tester);
    }
  });

  testWidgets('reversing after a protected older gesture discards its retry',
      (tester) async {
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester);
      final calls = sdk.requests.length;
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 400), touchSlopY: 0);
      await frames(tester, 2);
      await tester.drag(list, const Offset(0, -600), touchSlopY: 0);
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, calls);
      expect(currentSeqs().last, 56);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'an in-flight duplicate page cannot consume queued gestures as retries',
      (tester) async {
    try {
      sdk.mode = _PageMode.duplicate;
      await mountAndReachOlder(tester,
          reachExactEdge: true, releaseFirst: false);
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, -400), touchSlopY: 0);
      await frames(tester, 3);
      await tester.drag(list, const Offset(0, 400), touchSlopY: 0);
      await frames(tester, 3);
      sdk.firstOlderGate.complete();
      await waitUntil(
          tester,
          () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
          'the duplicate response must finish');
      final calls = sdk.requests.length;
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, calls,
          reason: 'gestures before a rejected response do not authorize loops');
      sdk.recovered = true;
      await tester.drag(list, const Offset(0, 96), touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().last == 41,
          'a new gesture after the response must retry the same cursor');
      expect(sdk.requests.length, calls + 1);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'iOS older edge rebound retains a gesture blocked by a context menu',
      (tester) async {
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester);
      physics = const BouncingScrollPhysics();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await frames(tester, 2);
      var maxOverscroll = 0.0;
      void sample() {
        final overscroll = scroll.offset - scroll.position.maxScrollExtent;
        if (overscroll > maxOverscroll) maxOverscroll = overscroll;
      }

      scroll.addListener(sample);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600),
          touchSlopY: 0);
      scroll.removeListener(sample);
      expect(maxOverscroll, greaterThan(10),
          reason: 'this test must exercise a real older-edge overscroll');
      global.beginMessageContextMenuOverlay(
          conversationID: model.conversationID);
      final calls = sdk.requests.length;
      await frames(tester, 50);
      // Overlay/viewport restoration can temporarily expose a different scroll
      // coordinate. Automatic geometry is not a reversal of the user's intent.
      scroll.jumpTo(scroll.position.minScrollExtent);
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, calls,
          reason: 'an open menu must retain its message viewport');
      scroll.jumpTo(scroll.position.maxScrollExtent);
      global.endMessageContextMenuOverlay(conversationID: model.conversationID);
      await waitUntil(tester, () => currentSeqs().last == 36,
          'closing the menu must resume the still-valid older edge gesture');
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, calls + 1);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'replacing the page model retires an old in-flight pagination owner',
      (tester) async {
    _ReadingModel? retired;
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester,
          reachExactEdge: true, releaseFirst: false);
      retired = model;
      final conv = model.conversationID;
      model = _ReadingModel()
        ..conversationID = conv
        ..conversationType = ConvType.group
        ..groupType = GroupReceiptAllowType.community
        ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Community')
        ..chatConfig = retired.chatConfig
        ..suppressReadReporting = true
        ..haveMoreData = true
        ..haveMoreLatestData = false;
      retired.dispose();
      final handler = FlutterError.onError;
      try {
        await tester.pumpWidget(build());
      } finally {
        FlutterError.onError = handler;
      }
      await frames(tester, 2);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
          touchSlopY: 0);
      await waitUntil(tester, () => model.isLoadingChatHistory,
          'the new page owner must paginate while the retired SDK future waits');
      sdk.firstOlderGate.complete();
      await waitUntil(
          tester,
          () => !model.isLoadingChatHistory && sdk.activeCalls == 0,
          'both transport futures must finish before checking the new window');
      await idleBeyondProtection(tester);
      // The shared SDK request belongs to the retired writer generation and
      // may be rejected by both consumers. A fresh gesture must still work.
      if (currentSeqs().last == 61) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
            touchSlopY: 0);
        await waitUntil(tester, () => currentSeqs().last == 56,
            'a stale shared response must leave the replacement retryable');
      }
      expect(currentSeqs(), [for (var seq = 100; seq >= 56; seq--) seq]);
      final calls = sdk.requests.length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400),
          touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().last == 36,
          'late old cleanup must not poison the replacement page retry latch');
      expect(sdk.requests.length, calls + 1);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'latest window replacement releases old pagination before its SDK reply',
      (tester) async {
    try {
      sdk.mode = _PageMode.short;
      await mountAndReachOlder(tester,
          reachExactEdge: true, releaseFirst: false);
      final oldLoads = uiOlderLoads;
      final oldWindowIsCurrent = model.captureHistoryWindowPublicationFence();
      var newestReloadFinished = false;
      var newestReloaded = false;
      final newestReload = model
          .reloadNewestMessageWindow(allowWhileReadingHistory: true)
          .then((loaded) {
        newestReloaded = loaded;
        newestReloadFinished = true;
      });
      await frames(tester, 3);
      expect(oldWindowIsCurrent(), isFalse,
          reason: 'starting replacement revokes the old publication owner');
      expect(sdk.firstOlderGate.isCompleted, isFalse);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 96),
          touchSlopY: 0);
      await frames(tester, 30);
      expect(uiOlderLoads, oldLoads + 1,
          reason:
              'the replaced window must own a new older request immediately');
      sdk.firstOlderGate.complete();
      await waitUntil(
          tester,
          () =>
              newestReloadFinished &&
              !model.isLoadingChatHistory &&
              sdk.activeCalls == 0,
          'all old/new transport work must settle');
      await newestReload;
      expect(newestReloaded, isTrue);
      await idleBeyondProtection(tester);
      expect(currentSeqs().last, anyOf(61, 56));
    } finally {
      await close(tester);
    }
  });

  testWidgets('a real reversal cancels a queued older debounce before dispatch',
      (tester) async {
    try {
      sdk.mode = _PageMode.duplicate;
      await mountAndReachOlder(tester, reachExactEdge: true);
      await idleBeyondProtection(tester);
      sdk.recovered = true;
      final calls = sdk.requests.length;
      final list = find.byType(CustomScrollView);
      // Both gestures complete before the 120 ms pagination debounce fires.
      await tester.drag(list, const Offset(0, 96), touchSlopY: 0);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      await idleBeyondProtection(tester);
      expect(sdk.requests.length, calls,
          reason: 'latest-directed movement must not start an older request');
      expect(currentSeqs().last, 61);
      await tester.drag(list, const Offset(0, 96), touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().last == 41,
          'a later real older gesture remains eligible after cancellation');
      expect(sdk.requests.length, calls + 1);
    } finally {
      await close(tester);
    }
  });
}
