import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
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

typedef _Request = ({
  HistoryMsgGetTypeEnum type,
  String? messageID,
  int seq,
  int count,
});

class _CommunitySdk extends MessageService {
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

      if (boundary <= 0) {
        rows = [for (var seq = 100; seq >= 61; seq--) _row(groupID!, seq)];
      } else if (recovered) {
        rows = [
          for (var index = 1; index <= count; index++)
            _row(groupID!, boundary - index),
        ];
      } else {
        rows = [];
      }
      return MessageHistorySdkResult(
          code: 0,
          desc: 'controlled Community older page',
          data: V2TimMessageListResult(messageList: rows, isFinished: false));
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
  Completer<bool>? heldUiLoad;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  setUp(() async {
    physics = null;
    uiOlderLoads = 0;
    heldUiLoad = null;
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
                  if (direction == LoadDirection.previous) {
                    uiOlderLoads++;
                    if (heldUiLoad != null) return heldUiLoad!.future;
                  }
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

  Future<void> mountFailedShortFill(WidgetTester tester) async {
    global.setMessageList(
      model.conversationID,
      [_row(model.conversationID, 100), _row(model.conversationID, 99)],
      replace: true,
      applyMemoryWindow: false,
    );
    sdk.firstOlderGate.complete();
    final handler = FlutterError.onError;
    await tester.pumpWidget(build());
    FlutterError.onError = handler;
    await waitUntil(
      tester,
      () =>
          uiOlderLoads > 0 &&
          !model.isLoadingChatHistory &&
          sdk.activeCalls == 0,
      'the short viewport must attempt its first automatic fill',
    );
    await idleBeyondProtection(tester);
    expect(uiOlderLoads, 1,
        reason: 'a zero-growth automatic fill must stop after one UI request');
    expect(scroll.position.maxScrollExtent, lessThanOrEqualTo(1));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform silent fill stays silent during programmatic motion',
        (tester) async {
      final oldPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      final request = Completer<bool>();
      try {
        heldUiLoad = request;
        final conv = model.conversationID;
        global.setMessageList(conv, [_row(conv, 100), _row(conv, 99)],
            replace: true, applyMemoryWindow: false);
        final handler = FlutterError.onError;
        await tester.pumpWidget(build());
        FlutterError.onError = handler;
        await waitUntil(tester, () => uiOlderLoads == 1,
            'automatic fill must start without a user gesture');
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // New rows/layout make the viewport barely scrollable. The latest
        // edge is now also inside the 160px "near oldest" band.
        global.setMessageList(
            conv, [for (var seq = 100; seq >= 91; seq--) _row(conv, seq)],
            replace: true, applyMemoryWindow: false);
        await frames(tester, 6);
        expect(scroll.position.maxScrollExtent, inExclusiveRange(1, 160));
        scroll.jumpTo(scroll.position.minScrollExtent + 1);
        await frames(tester, 2);
        scroll.jumpTo(scroll.position.minScrollExtent);
        await frames(tester, 2);
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'layout/automatic pinning is not user pagination intent');
        expect(uiOlderLoads, 1);
        // A real older-directed drag may promote that same in-flight fill.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 90),
            touchSlopY: 0);
        await frames(tester, 3);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(uiOlderLoads, 1);
      } finally {
        if (!request.isCompleted) request.complete(false);
        heldUiLoad = null;
        await close(tester);
        debugDefaultTargetPlatformOverride = oldPlatform;
      }
    });

    testWidgets('$platform older-page spinner hides on return to latest',
        (tester) async {
      final oldPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      final request = Completer<bool>();
      try {
        heldUiLoad = request;
        final handler = FlutterError.onError;
        await tester.pumpWidget(build());
        FlutterError.onError = handler;
        await idleBeyondProtection(tester);
        expect(uiOlderLoads, 0);
        // Materialize lazy older rows before measuring the older edge.
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await frames(tester, 2);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await frames(tester, 2);
        scroll.jumpTo(scroll.position.maxScrollExtent - 40);
        await frames(tester, 3);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 120),
            touchSlopY: 0);
        await waitUntil(tester, () => uiOlderLoads == 1,
            'older-directed user gesture must start pagination');
        await frames(tester, 2);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        scroll.jumpTo(scroll.position.minScrollExtent);
        await frames(tester, 2);
        expect(request.isCompleted, isFalse);
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'an in-flight older request must not spin at latest');
        expect(uiOlderLoads, 1);
      } finally {
        if (!request.isCompleted) request.complete(false);
        heldUiLoad = null;
        await close(tester);
        debugDefaultTargetPlatformOverride = oldPlatform;
      }
    });
  }

  for (final alwaysScrollable in [false, true]) {
    testWidgets(
        'a deliberate short-window touch retries once '
        '(alwaysScrollable=$alwaysScrollable)', (tester) async {
      try {
        if (alwaysScrollable) {
          physics = const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics());
        }
        await mountFailedShortFill(tester);
        sdk.recovered = true;
        final requests = sdk.requests.length;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 180),
            touchSlopY: 0);
        await waitUntil(tester, () => currentSeqs().contains(98),
            'a fresh older touch must retry even with zero scroll range');
        await idleBeyondProtection(tester);
        expect(uiOlderLoads, 2);
        expect(sdk.requests[requests].seq, 99);
        expect(currentSeqs(), [for (var seq = 100; seq >= 79; seq--) seq]);
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets('idle, tap, small and latest-directed drags do not retry',
      (tester) async {
    try {
      physics =
          const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      await mountFailedShortFill(tester);
      sdk.recovered = true;
      final list = find.byType(CustomScrollView);
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await tester.tap(list);
      await tester.drag(list, const Offset(0, kTouchSlop / 2), touchSlopY: 0);
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 1);
      await tester.drag(list, const Offset(0, -180), touchSlopY: 0);
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 1,
          reason: 'a latest-directed touch must retain the failed-page latch');
      expect(currentSeqs(), [100, 99]);
    } finally {
      await close(tester);
    }
  });

  testWidgets('a failed touch retry needs a new gesture before another request',
      (tester) async {
    try {
      await mountFailedShortFill(tester);
      final list = find.byType(CustomScrollView);
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, 64));
      await waitUntil(
        tester,
        () =>
            uiOlderLoads == 2 &&
            !model.isLoadingChatHistory &&
            sdk.activeCalls == 0,
        'one older gesture must issue one retry',
      );
      await gesture.moveBy(const Offset(0, 64));
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 2,
          reason: 'continued movement of one gesture cannot retry its failure');
      await gesture.up();
      sdk.recovered = true;
      await tester.drag(list, const Offset(0, 180), touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().contains(98),
          'a later gesture remains eligible after another failed request');
      expect(uiOlderLoads, 3);
    } finally {
      await close(tester);
    }
  });

  testWidgets('a touch moving during another request cannot retry its failure',
      (tester) async {
    final request = Completer<bool>();
    try {
      await mountFailedShortFill(tester);
      final list = find.byType(CustomScrollView);
      final center = tester.getCenter(list);
      // Pointer down belongs to the previous failed short page. A temporary
      // viewport resize lets a wheel start another request before it moves.
      final gesture = await tester.startGesture(center);
      await tester.binding.setSurfaceSize(const Size(800, 120));
      await frames(tester, 3);
      expect(scroll.position.maxScrollExtent, greaterThan(1));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester, 3);
      heldUiLoad = request;
      await tester.sendEventToBinding(PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -80),
      ));
      await waitUntil(tester, () => uiOlderLoads == 2,
          'the wheel retry must be in flight before the touch moves');
      await tester.binding.setSurfaceSize(null);
      await frames(tester, 3);
      expect(scroll.position.maxScrollExtent, lessThanOrEqualTo(1));
      await gesture.moveBy(const Offset(0, 64));
      await frames(tester, 10);
      request.complete(false);
      heldUiLoad = null;
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 2,
          reason: 'a gesture formed during a request cannot retry its failure');
      await gesture.up();
      sdk.recovered = true;
      await tester.drag(list, const Offset(0, 180), touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().contains(98),
          'a fresh post-result touch can still retry');
      expect(uiOlderLoads, 3);
    } finally {
      if (!request.isCompleted) request.complete(false);
      heldUiLoad = null;
      await tester.binding.setSurfaceSize(null);
      await close(tester);
    }
  });

  testWidgets('reversing a queued short-window touch cancels its retry',
      (tester) async {
    try {
      await mountFailedShortFill(tester);
      sdk.recovered = true;
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(CustomScrollView)));
      await gesture.moveBy(const Offset(0, 64));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(0, -64));
      await gesture.up();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 1);
      expect(currentSeqs(), [100, 99]);
    } finally {
      await close(tester);
    }
  });

  for (final menuLock in [false, true]) {
    testWidgets(
        'a touch claimed by a later lock cannot queue a retry '
        '(menuLock=$menuLock)', (tester) async {
      try {
        await mountFailedShortFill(tester);
        sdk.recovered = true;
        final gesture = await tester
            .startGesture(tester.getCenter(find.byType(CustomScrollView)));
        if (menuLock) {
          global.beginMessageContextMenuOverlay(
              conversationID: model.conversationID);
        } else {
          physics = const NeverScrollableScrollPhysics();
          final handler = FlutterError.onError;
          await tester.pumpWidget(build());
          FlutterError.onError = handler;
        }
        await gesture.moveBy(const Offset(0, 64));
        await gesture.up();
        await frames(tester);
        expect(uiOlderLoads, 1,
            reason:
                'movement after input is locked must not become history intent');
        if (menuLock) {
          global.endMessageContextMenuOverlay(
              conversationID: model.conversationID);
        } else {
          physics = null;
        }
        final handler = FlutterError.onError;
        await tester.pumpWidget(build());
        FlutterError.onError = handler;
        await idleBeyondProtection(tester);
        expect(uiOlderLoads, 1,
            reason:
                'unlocking cannot replay movement owned by another surface');
        expect(currentSeqs(), [100, 99]);
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets('a retired conversation pointer cannot retry its replacement',
      (tester) async {
    _ReadingModel? retired;
    try {
      await mountFailedShortFill(tester);
      final previousListState =
          tester.state(find.byType(TIMUIKitHistoryMessageList));
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(CustomScrollView)));
      retired = model;
      final conv = '${model.conversationID}_replacement';
      model = _ReadingModel()
        ..conversationID = conv
        ..conversationType = ConvType.group
        ..groupType = GroupReceiptAllowType.community
        ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Community')
        ..chatConfig = retired.chatConfig
        ..suppressReadReporting = true
        ..haveMoreData = true
        ..haveMoreLatestData = false;
      global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
          notify: false);
      global.setMessageList(conv, [_row(conv, 100), _row(conv, 99)],
          replace: true, applyMemoryWindow: false);
      global.markInitialHistoryLoaded(conv);
      conversation = V2TimConversation(
          conversationID: 'group_$conv',
          groupID: conv,
          type: 2,
          unreadCount: 0,
          lastMessage: _row(conv, 100));
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      expect(tester.state(find.byType(TIMUIKitHistoryMessageList)),
          same(previousListState));
      await idleBeyondProtection(tester);
      final calls = uiOlderLoads;
      sdk.recovered = true;
      await gesture.moveBy(const Offset(0, 64));
      await gesture.up();
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, calls,
          reason:
              'a pointer begun in the retired window cannot own the new one');
      expect(currentSeqs(), [100, 99]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 180),
          touchSlopY: 0);
      await waitUntil(tester, () => currentSeqs().contains(98),
          'a fresh touch belongs to the replacement window and can retry it');
      expect(uiOlderLoads, calls + 1);
    } finally {
      retired?.dispose();
      await close(tester);
    }
  });

  testWidgets('disabling scrolling before dispatch drops a queued touch retry',
      (tester) async {
    try {
      await mountFailedShortFill(tester);
      sdk.recovered = true;
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(CustomScrollView)));
      await gesture.moveBy(const Offset(0, 64));
      physics = const NeverScrollableScrollPhysics();
      final handler = FlutterError.onError;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await gesture.up();
      await frames(tester);
      expect(uiOlderLoads, 1);
      physics = null;
      await tester.pumpWidget(build());
      FlutterError.onError = handler;
      await idleBeyondProtection(tester);
      expect(uiOlderLoads, 1);
    } finally {
      await close(tester);
    }
  });

  for (final disposeList in [false, true]) {
    testWidgets(
        'cancel or dispose drops a queued short-window retry '
        '(disposeList=$disposeList)', (tester) async {
      try {
        await mountFailedShortFill(tester);
        sdk.recovered = true;
        final gesture = await tester
            .startGesture(tester.getCenter(find.byType(CustomScrollView)));
        await gesture.moveBy(const Offset(0, 64));
        if (disposeList) {
          await tester.pumpWidget(const SizedBox.shrink());
          await gesture.up();
        } else {
          await gesture.cancel();
          final handler = FlutterError.onError;
          await tester.pumpWidget(build());
          FlutterError.onError = handler;
        }
        await idleBeyondProtection(tester);
        expect(uiOlderLoads, 1);
        expect(currentSeqs(), [100, 99]);
      } finally {
        await close(tester);
      }
    });
  }
}
