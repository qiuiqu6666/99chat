import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:extended_text_field/extended_text_field.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
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
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitTextField/tim_uikit_text_field.dart';

class _HistorySdk extends MessageService {
  int calls = 0;
  int code = 0;
  List<V2TimMessage> newest = [];
  Future<void> Function()? duringRead;
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
    calls++;
    final response = newest;
    final responseCode = code;
    await duringRead?.call();
    return MessageHistorySdkResult(
        code: responseCode,
        desc: 'controlled SDK response',
        data: responseCode == 0
            ? V2TimMessageListResult(isFinished: true, messageList: response)
            : null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _ChatModel extends TUIChatSeparateViewModel {
  int readReports = 0;
  int newestReloadsInFlight = 0;

  @override
  Future<bool> reloadNewestMessageWindow({
    int? count,
    bool allowWhileReadingHistory = false,
    Future<void>? cancelWhen,
  }) async {
    newestReloadsInFlight++;
    try {
      return await super.reloadNewestMessageWindow(
          count: count,
          allowWhileReadingHistory: allowWhileReadingHistory,
          cancelWhen: cancelWhen);
    } finally {
      newestReloadsInFlight--;
    }
  }
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {
    readReports++;
  }
}

class _AckStore extends HistoryWindowStore {
  _AckStore({required super.debugDatabasePath});
  Future<void> Function()? beforeDeferredState;
  @override
  Future<HistoryWindowDeferredState> deferredState(HistoryWindowScope scope) async {
    await beforeDeferredState?.call();
    return super.deferredState(scope);
  }
  Future<void> Function()? afterAcknowledge;
  Future<void> Function()? afterVisibleAcknowledge;
  @override
  Future<HistoryWindowVisibleReceipt> acknowledgeVisibleDeferred({
    required HistoryWindowScope scope,
    required List<String> messageIDs,
    required int afterIngressSequence,
    bool Function()? isCurrent,
  }) async {
    final receipt = await super.acknowledgeVisibleDeferred(
      scope: scope,
      messageIDs: messageIDs,
      afterIngressSequence: afterIngressSequence,
      isCurrent: isCurrent,
    );
    final callback = afterVisibleAcknowledge;
    afterVisibleAcknowledge = null;
    await callback?.call();
    return receipt;
  }
  @override
  Future<void> acknowledgeDeferred(
      {required HistoryWindowScope scope,
      required int throughIngressSequence}) async {
    await super.acknowledgeDeferred(
        scope: scope, throughIngressSequence: throughIngressSequence);
    final callback = afterAcknowledge;
    afterAcknowledge = null;
    await callback?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _AckStore store;
  late _HistorySdk sdk;
  late TUIChatGlobalModel global;
  late _ChatModel model;
  late AutoScrollController scroll;
  var sequence = 0;
  String getConv() => model.conversationID;
  V2TimMessage row(int id, {String? conversation}) {
    final conv = conversation ?? getConv();
    return V2TimMessage.fromJson({
      'message_msg_id': '$conv-$id',
      'message_conv_id': conv,
      'message_conv_type': 2,
      'message_server_time': id,
      'message_risk_type_identified': 0
    })
      ..groupID = conv
      ..seq = '$id'
      ..isSelf = false
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $id');
  }

  _ChatModel makeModel(String conv) => _ChatModel()
    ..conversationID = conv
    ..conversationType = ConvType.group
    ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Public')
    ..chatConfig = const TIMUIKitChatConfig(
        isAutoReportRead: false,
        isShowReadingStatus: false,
        inboundChunkRevealEnabled: true,
        isUseDraft: false)
    ..suppressReadReporting = true;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('durable-tongue-');
    store = _AckStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _HistorySdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'tongue-owner',
        accountGeneration: ++sequence,
        domainGeneration: 1);
    model = makeModel('@TGS#tongue_$sequence');
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(
        CurrentConversation(getConv(), ConvType.group),
        notify: false);
    scroll = AutoScrollController();
    global.bindActiveChatScrollController(
        conversationID: getConv(), scrollController: scroll);
    global.bindHistoryLiveWindowFreeze(
      conversationID: getConv(),
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    global.setMessageList(getConv(), List.generate(100, (i) => row(100 - i)),
        replace: true, applyMemoryWindow: false);
  });
  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final errorHandler = FlutterError.onError;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = errorHandler;
  }

  Future<void> mount(WidgetTester tester,
      {int entry = 0,
      bool input = false,
      bool Function()? beginTransition,
      Future<void> Function()? finishTransition,
      Future<bool> Function(int)? onFirstUnread}) async {
    model.initialUnreadCount = entry;
    final errorHandler = FlutterError.onError;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Consumer<TUIChatGlobalModel>(
                  builder: (_, current, __) => Stack(children: [
          ListView.builder(
              key: const Key('history'),
              controller: scroll,
              reverse: true,
              itemExtent: 60,
              itemCount: current.rawMessageCount(getConv()),
              itemBuilder: (_, i) => Text(
                  'history ${current.rawMessageList(getConv())![i].msgID}')),
          TIMUIKitHistoryMessageListTongueContainer(
            messageList: global.rawMessageList(getConv())!,
            conversation: V2TimConversation(
                conversationID: 'group_${getConv()}',
                groupID: getConv(),
                type: 2,
                unreadCount: entry),
            scrollToIndexBySeq: (_) async => false,
            scrollToFirstUnread: onFirstUnread ?? (_) async => true,
            beginWindowTransition: beginTransition,
            finishWindowTransition: finishTransition,
            scrollController: scroll,
            model: model,
            tongueItemBuilder: (tap, type, count) =>
                TextButton(onPressed: tap, child: Text('${type.name}:$count')),
          ),
          if (input)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: TIMUIKitInputTextField(
                conversationID: getConv(),
                conversationType: ConvType.group,
                scrollController: scroll,
                model: model,
                currentConversation: V2TimConversation(
                    conversationID: 'group_${getConv()}',
                    groupID: getConv(),
                    type: 2,
                    unreadCount: entry),
                showSendAudio: false,
                showSendEmoji: false,
                showMorePanel: false,
              ),
            ),
        ]))))));
    FlutterError.onError = errorHandler;
    await frame(tester);
  }

  Future<void> away(WidgetTester tester) async {
    global.setChatListUserScrolling(true);
    scroll.jumpTo(1200);
    await frame(tester);
    global.setFollowingLatest(getConv(), false, notify: false);
    global.setChatListUserScrolling(false);
    await frame(tester, 250);
  }

  Future<void> awayInHistoryGap(WidgetTester tester) async {
    await away(tester);
    global.markMemoryWindowMissingNewer(getConv());
  }

  Future<void> receive(WidgetTester tester, int from, int count) async {
    var done = false;
    Object? failure;
    final pending = () async {
      try {
        for (var id = from; id < from + count; id++) {
          await global.applyAppRealtimeMessage(row(id),
              ingressEventID: '${getConv()}-event-$id', ingressSequence: id);
        }
      } catch (error) {
        failure = error;
      } finally {
        done = true;
      }
    }();
    for (var attempt = 0; attempt < 1500 && !done; attempt++) {
      await frame(tester);
    }
    expect(done, isTrue, reason: 'durable admission must complete');
    await pending;
    expect(failure, isNull,
        reason: 'durable admission must preserve the message');
    await frame(tester, 80);
  }

  Future<void> settleReturn(WidgetTester tester, {int frameMs = 30}) async {
    // SQLite runs in real time while widget timers use FakeAsync. A fixed
    // frame count can reach the assertion after the SDK page commit but before
    // its durable ACK has completed on a busy integration-test worker.
    // Observe the actual UI transaction, never the expected unread count.
    for (var n = 0; n < (frameMs == 1 ? 6000 : 1500); n++) {
      await frame(tester, frameMs);
      if (n >= 119 && model.newestReloadsInFlight == 0 &&
          !global.isUserScrollToBottomInProgress(getConv())) {
        break;
      }
    }
    expect(global.isUserScrollToBottomInProgress(getConv()), isFalse,
        reason: 'latest-window return and durable ACK must finish');
    expect(model.newestReloadsInFlight, 0,
        reason: 'input-triggered reload must finish its durable ACK too');
    await frame(tester);
    await frame(tester, 200);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await frame(tester, 1000);
  }

  void uiTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        global.clearActiveChatScrollController(conversationID: getConv());
        global.clearData();
        model.dispose();
        scroll.dispose();
        HistoryWindowRepositoryProvider.repository = null;
        var closed = false;
        final closing = store.closeIfOpen().whenComplete(() => closed = true);
        // Widget-admitted callbacks run in FakeAsync. Drain them while real
        // SQLite IO completes, before leaving this widget test's active zone.
        final closingTime = Stopwatch()..start();
        while (!closed && closingTime.elapsed < const Duration(seconds: 15)) {
          await frame(tester);
        }
        expect(closed, isTrue, reason: 'history database close must drain');
        await closing;
        await frame(tester, 2000);
        await tester.runAsync(() => directory.delete(recursive: true));
        SqfliteLifecycleGuard.instance.debugReset();
      }
    });
  }

  uiTest('continuous durable arrivals reveal incrementally without starving return',
      (tester) async {
    await mount(tester, beginTransition: () => true, finishTransition: () async {
      await global.applyAppRealtimeMessage(row(104),
          ingressEventID: '${getConv()}-event-104', ingressSequence: 104);
    });
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    var nextID = 103;
    sdk.duringRead = () async {
      final id = nextID++;
      await global.applyAppRealtimeMessage(row(id),
          ingressEventID: '${getConv()}-event-$id', ingressSequence: id);
      sdk.newest = List.generate(50, (i) => row(id - i));
    };
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, 1, reason: 'success must finish its captured target');
    expect(scroll.offset, closeTo(0, 1));
    expect(global.rawMessageList(getConv())!.first.seq, '104');
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(model.readReports, 1);
    expect(find.text('取消'), findsNothing);
  });

  uiTest('delivery after visible snapshot stays unread and is projected at latest',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    Future<void>? lateArrival;
    var lateArrivalFinished = false;
    sdk.duringRead = () => global.applyAppRealtimeMessage(row(103),
        ingressEventID: '${getConv()}-event-103', ingressSequence: 103);
    store.afterVisibleAcknowledge = () async {
      lateArrival = global.applyAppRealtimeMessage(row(104),
          ingressEventID: '${getConv()}-late-visible-104', ingressSequence: 104)
          .whenComplete(() => lateArrivalFinished = true);
    };
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    final lateArrivalTime = Stopwatch()..start();
    while (!lateArrivalFinished &&
        lateArrivalTime.elapsed < const Duration(seconds: 15)) {
      await frame(tester);
    }
    expect(lateArrivalFinished, isTrue,
        reason: 'fake-zone admission needs frames while real SQLite completes');
    await lateArrival;
    await frame(tester);
    expect(sdk.calls, 1);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.rawMessageList(getConv())!.first.seq, '104');
    expect(global.receivedNewMessageCountFor(getConv()), 1,
        reason: 'the older visible snapshot must not consume a later identity');
    expect(model.readReports, 0);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
  });

  uiTest('post-target backlog beyond the hot cap stays unread and retryable',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    sdk.duringRead = () async {
      for (var id = 103; id <= 223; id++) {
        await global.applyAppRealtimeMessage(row(id),
            ingressEventID: '${getConv()}-event-$id', ingressSequence: id);
      }
    };
    await tester.tap(find.text('showUnread:2'));
    // Real SQLite IO must not consume 30 fake-clock milliseconds for every
    // two real milliseconds while the controlled SDK awaits this burst.
    await settleReturn(tester, frameMs: 1);
    expect(sdk.calls, 1);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.rawMessageList(getConv())!.first.seq, '102');
    expect(global.receivedNewMessageCountFor(getConv()), 121);
    expect(model.readReports, 0);
    expect(global.remainingLiveIncomingIdsFor(getConv()),
        {for (var seq = 103; seq <= 223; seq++) '${getConv()}-$seq'},
        reason: 'the bounded SQL tail must not retain captured IDs 101/102');
    expect(find.text('showUnread:121').hitTestable(), findsOneWidget);
    sdk.duringRead = null;
    sdk.newest = List.generate(50, (i) => row(223 - i));
    await tester.tap(find.text('showUnread:121'));
    await settleReturn(tester);
    expect(global.rawMessageList(getConv())!.first.seq, '223');
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(model.readReports, 1);
  });

  uiTest('old ballistic motion cannot cancel a newer bottom tap', (tester) async {
    await mount(tester);
    await away(tester);
    await tester.fling(find.byType(ListView), const Offset(0, 180), 1500);
    await tester.pump(const Duration(milliseconds: 16));
    expect(scroll.position.activity, isA<BallisticScrollActivity>());
    await tester.tap(find.text('toLatest:0'));
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 1));
    expect(model.readReports, 1);
    expect(find.text('取消'), findsNothing);
  });

  uiTest('late burst revokes live reveal before exceeding its bounded window',
      (tester) async {
    await mount(tester, beginTransition: () => true, finishTransition: () async {
      for (var id = 104; id <= 224; id++) {
        await global.applyAppRealtimeMessage(row(id),
            ingressEventID: '${getConv()}-event-$id', ingressSequence: id);
      }
    });
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    sdk.duringRead = () => global.applyAppRealtimeMessage(row(103),
        ingressEventID: '${getConv()}-event-103', ingressSequence: 103);
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester, frameMs: 1);
    expect(sdk.calls, 1);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.rawMessageList(getConv())!.length, lessThanOrEqualTo(222));
    expect(global.rawMessageList(getConv())!.first.seq, '222');
    expect(global.receivedNewMessageCountFor(getConv()), 122);
    expect(global.canRevealDurableIncomingAfterLatestReturn(getConv()), isFalse);
    expect(global.isFollowingLatest(getConv()), isFalse);
    expect(model.readReports, 0);
    expect(find.text('showUnread:122').hitTestable(), findsOneWidget);
  });

  uiTest('storage-only delivery revokes reveal instead of allowing a later gap',
      (tester) async {
    await mount(tester, beginTransition: () => true, finishTransition: () async {
      await global.applyAppRealtimeMessage(row(104),
          ingressEventID: '${getConv()}-held-104', ingressSequence: 104,
          projectMessageList: false);
      await global.applyAppRealtimeMessage(row(105),
          ingressEventID: '${getConv()}-event-105', ingressSequence: 105);
    });
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    sdk.duringRead = () => global.applyAppRealtimeMessage(row(103),
        ingressEventID: '${getConv()}-event-103', ingressSequence: 103);
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(global.rawMessageList(getConv())!.first.seq, '103');
    expect(global.canRevealDurableIncomingAfterLatestReturn(getConv()), isFalse);
    expect(global.receivedNewMessageCountFor(getConv()), 3);
    expect(model.readReports, 0);
    expect(find.text('showUnread:3').hitTestable(), findsOneWidget);
  });

  uiTest('stalled return times out and ignores late SDK publication', (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    final originalIDs = global.rawMessageList(getConv())!.map((m) => m.msgID).toList();
    final gate = Completer<void>();
    sdk.newest = List.generate(50, (i) => row(150 - i));
    sdk.duringRead = () => gate.future;
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var done = false;
    final pending = state.scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => done = true);
    try {
      final started = Stopwatch()..start();
      while (sdk.calls == 0 && started.elapsed < const Duration(seconds: 15)) {
        await frame(tester, 1);
      }
      expect(sdk.calls, 1);
      await frame(tester, 30000);
      for (var n = 0; n < 10; n++) { await frame(tester); }
      expect(done, isTrue, reason: 'the whole return must have a deadline');
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
      expect(model.readReports, 0);
      gate.complete();
      sdk.duringRead = null;
      for (var n = 0; n < 200 && model.isLoadingChatHistory; n++) { await frame(tester); }
      expect(global.rawMessageList(getConv())!.map((m) => m.msgID), originalIDs,
          reason: 'timeout must invalidate the late publication, not just unlock UI');
      await pending;
      await tester.tap(find.text('toLatest:0'));
      await settleReturn(tester);
      expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-150');
      expect(model.readReports, 1);
    } finally {
      if (!gate.isCompleted) gate.complete();
      for (var n = 0; n < 300 && !done; n++) { await frame(tester); }
      await pending;
    }
  });

  uiTest('drag interrupts durable return without a cancel button', (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    final entered = Completer<void>();
    final gate = Completer<void>();
    store.beforeDeferredState = () async {
      if (!entered.isCompleted) entered.complete();
      await gate.future;
    };
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var done = false;
    final pending = state.scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => done = true);
    try {
      for (var n = 0; n < 200 && !entered.isCompleted; n++) { await frame(tester); }
      expect(entered.isCompleted, isTrue);
      expect(find.text('取消'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 120));
      for (var n = 0; n < 10; n++) { await frame(tester); }
      expect(done, isTrue);
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      expect(scroll.offset, greaterThan(1200));
      expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
      gate.complete();
      store.beforeDeferredState = null;
      for (var n = 0; n < 60; n++) { await frame(tester); }
      expect(sdk.calls, 0, reason: 'cancelled preparation must not start a reload');
      expect(model.readReports, 0);
      await pending;
    } finally {
      if (!gate.isCompleted) gate.complete();
      store.beforeDeferredState = null;
      for (var n = 0; n < 300 && !done; n++) { await frame(tester); }
      await pending;
    }
  });

  uiTest('drag interrupts return animation without a cancel button and permits retry', (tester) async {
    await mount(tester);
    await away(tester);
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    final pending = state.scrollToLatestAndDismissUnreadCapsule();
    for (var n = 0; n < 5; n++) { await frame(tester, 16); }
    expect(find.text('取消'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    for (var n = 0; n < 5; n++) { await frame(tester, 16); }
    await pending;
    final stopped = scroll.offset;
    expect(stopped, greaterThan(24));
    expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
    await frame(tester, 1000);
    expect(scroll.offset, closeTo(stopped, 1));
    expect(model.readReports, 0);
    expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
    await tester.tap(find.text('toLatest:0'));
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 1));
    expect(model.readReports, 1);
  });

  uiTest('a pending entry baseline does not create a bottom reminder',
      (tester) async {
    await mount(tester);
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeDeferredState = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    var baselineFinished = false;
    final baseline = global.beginHistoryUnreadVisit(getConv())
        .whenComplete(() => baselineFinished = true);
    try {
      for (var n = 0; n < 50 && !entered.isCompleted; n++) {
        await frame(tester);
      }
      expect(entered.isCompleted, isTrue);
      expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
      global.notifyListeners();
      await frame(tester, 250);
      expect(find.text('toLatest:0').hitTestable(), findsNothing);
      expect(find.text('showUnread:0').hitTestable(), findsNothing);
    } finally {
      store.beforeDeferredState = null;
      release.complete();
      final baselineTime = Stopwatch()..start();
      while (!baselineFinished &&
          baselineTime.elapsed < const Duration(seconds: 15)) {
        await frame(tester);
      }
      expect(baselineFinished, isTrue,
          reason: 'released baseline must finish while frames keep running');
      await baseline;
    }
    await unmount(tester);
  });

  uiTest('arrival during entry baseline stays live when the reader is at bottom',
      (tester) async {
    await mount(tester);
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeDeferredState = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    var baselineFinished = false;
    final baseline = global.beginHistoryUnreadVisit(getConv())
        .whenComplete(() => baselineFinished = true);
    for (var n = 0; n < 50 && !entered.isCompleted; n++) {
      await frame(tester);
    }
    var finished = false;
    final incoming = global.applyAppRealtimeMessage(row(101),
        ingressEventID: '${getConv()}-during-entry', ingressSequence: 101)
        .whenComplete(() => finished = true);
    await frame(tester);
    store.beforeDeferredState = null;
    release.complete();
    for (var n = 0; n < 100 && (!finished || !baselineFinished); n++) {
      await frame(tester);
    }
    expect(finished && baselineFinished, isTrue);
    await baseline;
    await incoming;
    await frame(tester, 1000);
    expect(global.deferredIncomingBufferedCount(getConv()), 0);
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(global.rawMessageList(getConv())!.any((m) => m.msgID == '${getConv()}-101'), isTrue);
    expect(find.text('showUnread:1').hitTestable(), findsNothing);
    await unmount(tester);
  });

  uiTest('quiet return completes using only frames requested by production',
      (tester) async {
    await mount(tester);
    await away(tester);
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var completed = false;
    unawaited(state.scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => completed = true));
    await tester.pumpAndSettle();
    expect(completed, isTrue,
        reason: 'A quiet conversation must not need another user gesture/frame');
    expect(scroll.position.pixels, closeTo(scroll.position.minScrollExtent, 1));
    expect(model.readReports, 1);
  });

  for (final failsAtBegin in [true, false]) {
    uiTest(
        '${failsAtBegin ? 'begin' : 'finish'} transition error preserves unread and permits a real retry',
        (tester) async {
      var failTransition = true;
      var begins = 0;
      var finishes = 0;
      final failure = StateError('controlled transition failure');
      global.lockEntryUnreadForTongue(
          conversationID: getConv(), unreadCount: 100);
      await mount(tester, entry: 100, beginTransition: () {
        begins++;
        if (failsAtBegin && failTransition) throw failure;
        return true;
      }, finishTransition: () async {
        finishes++;
        if (!failsAtBegin && failTransition) throw failure;
      });
      await awayInHistoryGap(tester);
      await receive(tester, 101, 2);
      sdk.newest = List.generate(50, (i) => row(102 - i));
      expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
      final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));

      // Attach the error observer immediately: SQLite completion and widget
      // animation advance on different clocks in this fixture.
      var failed = false;
      final observedFailure = expectLater(
              state.scrollToLatestAndDismissUnreadCapsule(),
              throwsA(same(failure)))
          .whenComplete(() => failed = true);
      for (var attempt = 0; attempt < 1500 && !failed; attempt++) {
        await frame(tester);
      }
      expect(failed, isTrue, reason: 'the failing transaction must settle');
      await observedFailure;
      await frame(tester, 250);
      expect(begins, 1);
      expect(finishes, greaterThan(0));
      expect(sdk.calls, failsAtBegin ? 0 : greaterThan(0));
      expect(model.readReports, 0);
      expect(scroll.offset, 1200);
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      if (failsAtBegin) {
        expect(global.receivedNewMessageCountFor(getConv()), 2);
        expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
        expect(find.text('showUnread:2').hitTestable(), findsOneWidget);
      } else {
        // The successful SDK page has acknowledged its covered arrivals, but
        // failing to reveal/scroll must not dismiss the unread entry or mark
        // that history as read. The return button remains actionable.
        expect(global.receivedNewMessageCountFor(getConv()), 0);
        expect(global.getUnreadTongueRemaining(getConv()), 100);
        expect(find.text('toLatest:0').hitTestable(), findsOneWidget);
      }

      failTransition = false;
      var retried = false;
      final retry = state.scrollToLatestAndDismissUnreadCapsule()
          .whenComplete(() => retried = true);
      for (var attempt = 0; attempt < 1500 && !retried; attempt++) {
        await frame(tester);
      }
      expect(retried, isTrue, reason: 'retry must finish without a stale lock');
      await retry;
      // Completion alone is insufficient: a stale local flag returns early.
      expect(model.readReports, 1);
      expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
      expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-102');
      expect(global.receivedNewMessageCountFor(getConv()), 0);
      expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      if (failsAtBegin) expect(begins, 2);
      await unmount(tester);
    });
  }

  for (final historyGap in [false, true]) {
    for (final keyboardAlreadyOpen in [false, true]) {
      uiTest(
        'tapping input returns history to bottom (gap=$historyGap, keyboardOpen=$keyboardAlreadyOpen)',
        (tester) async {
          final previousDeviceType = TUIKitScreenUtils.deviceType;
          TUIKitScreenUtils.deviceType = DeviceType.Mobile;
          addTearDown(() => TUIKitScreenUtils.deviceType = previousDeviceType);
          await mount(tester, input: true);
          if (historyGap) {
            await awayInHistoryGap(tester);
            await receive(tester, 101, 2);
            sdk.newest = List.generate(50, (i) => row(102 - i));
          } else {
            await away(tester);
          }
          final coordinator = KeyboardViewportTransitionCoordinator(
            pauseMedia: () {},
            resumeMedia: () {},
          );
          KeyboardViewportTransitionCoordinator.active = coordinator;
          try {
            // Keep the IME occupied while an asynchronous newest-page read finishes.
            if (keyboardAlreadyOpen) {
              coordinator.applyLogicalInset(
                280,
                viewHeight: 600,
                displayHeight: 600,
              );
            }
            await tester.tap(find.byType(ExtendedTextField));
            coordinator.applyLogicalInset(
              280,
              viewHeight: 600,
              displayHeight: 600,
            );
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            addTearDown(tester.view.resetViewInsets);
            await settleReturn(tester);
            expect(coordinator.isOccupied, isTrue);
            expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
            expect(global.receivedNewMessageCountFor(getConv()), 0);
            expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
            if (historyGap) {
              expect(sdk.calls, greaterThan(0));
              expect(
                global.rawMessageList(getConv())!.first.msgID,
                '${getConv()}-102',
              );
            }
          } finally {
            coordinator.dispose();
          }
          await unmount(tester);
        },
      );
    }
  }

  for (final succeeds in [false, true]) {
    uiTest(
        'input return ${succeeds ? 'loads newest before clearing' : 'preserves reminders on failure'}',
        (tester) async {
      global.lockEntryUnreadForTongue(
          conversationID: getConv(), unreadCount: 100);
      await mount(tester, entry: 100, input: true);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 2);
      sdk.code = succeeds ? 0 : -1;
      sdk.newest = List.generate(50, (i) => row(102 - i));
      // Exercise the actual input State's public return method. Keyboard
      // platform events are outside this widget-level regression's scope.
      final dynamic inputState =
          tester.state(find.byType(TIMUIKitInputTextField));
      inputState.goDownBottom(fromOutgoingSend: true);
      await settleReturn(tester);
      expect(sdk.calls, greaterThan(0));
      expect(global.rawMessageList(getConv())!.first.msgID,
          '${getConv()}-${succeeds ? 102 : 100}');
      expect(global.receivedNewMessageCountFor(getConv()), succeeds ? 0 : 2);
      expect(global.hasDurableHistoryDeferred(getConv()), !succeeds);
      expect(find.text('showPrevious:100'), findsNothing);
      if (succeeds) {
        expect(scroll.offset, closeTo(0, 1));
        expect(model.readReports, greaterThan(0));
      } else {
        expect(model.readReports, 0);
      }
      await unmount(tester);
    });
  }

  uiTest('a live arrival remains actionable after only a short upward scroll',
      (tester) async {
    await mount(tester);
    global.setChatListUserScrolling(true);
    scroll.jumpTo(100);
    await frame(tester);
    global.setFollowingLatest(getConv(), false, notify: false);
    global.setChatListUserScrolling(false);
    await frame(tester, 250);
    expect(find.text('toLatest:0').hitTestable(), findsNothing);
    await receive(tester, 101, 1);
    expect(scroll.offset, 100);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(global.deferredIncomingBufferedCount(getConv()), 1);
    expect(global.rawMessageList(getConv())!.any((m) => m.msgID == '${getConv()}-101'),
        isFalse);
    expect(global.receivedNewMessageCountFor(getConv()), 1);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
    await unmount(tester);
  });

  uiTest('removed entry unread does not hide two live messages',
      (tester) async {
    global.lockEntryUnreadForTongue(
        conversationID: getConv(), unreadCount: 100);
    await mount(tester, entry: 100);
    await away(tester);
    await receive(tester, 101, 2);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(find.text('showUnread:2'), findsOneWidget);
    expect(global.receivedNewMessageCountFor(getConv()), 2);
    await frame(tester);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(find.text('showUnread:2'), findsOneWidget);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(global.deferredIncomingBufferedCount(getConv()), 2);
    expect(
        global.rawMessageList(getConv())!.map((m) => m.msgID),
        isNot(containsAll(['${getConv()}-102', '${getConv()}-101'])));
    expect(
        await tester.runAsync(() =>
            store.deferredState(global.historyWindowScopeFor(getConv())!)),
        isA<HistoryWindowDeferredState>()
            .having((v) => v.receivedCount, 'received', 0));
    await unmount(tester);
  });

  for (final manual in [false, true]) {
    uiTest(
        '121 durable arrivals require an explicit return (${manual ? 'manual drag' : 'button'})',
        (tester) async {
      global.lockEntryUnreadForTongue(
          conversationID: getConv(), unreadCount: 1000);
      await mount(tester, entry: 1000);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 121);
      expect(global.deferredIncomingBufferedCount(getConv()), 120);
      expect(global.receivedNewMessageCountFor(getConv()), 121);
      expect(global.memoryWindowMissingNewer(getConv()), isTrue);
      sdk.newest = List.generate(50, (i) => row(221 - i));
      if (manual) {
        global.setChatListUserScrolling(true);
        await tester.drag(
            find.byKey(const Key('history')), const Offset(0, -1500));
        await frame(tester);
        global.setChatListUserScrolling(false);
        await frame(tester, 500);
        expect(global.isUserScrollToBottomInProgress(getConv()), isFalse,
            reason: 'A manual scroll must not start the button transaction');
        expect(sdk.calls, 0, reason: 'A manual scroll must not reload the live tip');
        expect(global.receivedNewMessageCountFor(getConv()), 121);
        expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
        expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-100');
        expect(model.readReports, 0);
        await tester.tap(find.text('showUnread:121'));
      } else {
        await tester.tap(find.text('showUnread:121'));
      }
      await settleReturn(tester);
      expect(sdk.calls, greaterThan(0));
      expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-221');
      expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
      expect(global.receivedNewMessageCountFor(getConv()), 0);
      expect(global.getMessageListPosition(getConv()),
          HistoryMessagePosition.bottom);
      expect(find.text('showPrevious:1000'), findsNothing);
      expect(model.readReports, greaterThan(0));
      await unmount(tester);
    });
  }

  uiTest(
      'failed latest fetch at the loaded edge preserves retry, entry and durable count',
      (tester) async {
    await mount(tester, entry: 100);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    // A manual return requests the real newest window. A failed request must
    // leave this old physical edge retryable rather than acknowledge it.
    sdk.code = -1;
    global.setChatListUserScrolling(true);
    scroll.jumpTo(0);
    await frame(tester);
    global.setChatListUserScrolling(false);
    await frame(tester, 250);
    expect(find.text('showUnread:2').hitTestable(), findsOneWidget);
    final callsBeforeRetry = sdk.calls;
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(callsBeforeRetry));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-100');
    expect(global.receivedNewMessageCountFor(getConv()), 2);
    expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(find.text('showUnread:2').hitTestable(), findsOneWidget);
    expect(model.readReports, 0);
    final callsBeforeSuccess = sdk.calls;
    sdk.code = 0;
    sdk.newest = List.generate(50, (i) => row(102 - i));
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(callsBeforeSuccess));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-102');
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(find.text('showPrevious:100'), findsNothing);
    await unmount(tester);
  });

  uiTest(
      'a successful but old SDK page cannot acknowledge newer durable arrivals',
      (tester) async {
    global.lockEntryUnreadForTongue(
        conversationID: getConv(), unreadCount: 100);
    await mount(tester, entry: 100);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.code = 0;
    sdk.newest = List.generate(50, (i) => row(100 - i));
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(0));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-100');
    expect(global.receivedNewMessageCountFor(getConv()), 2);
    expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(find.text('showUnread:2').hitTestable(), findsOneWidget);
    expect(model.readReports, 0);
    final callsBeforeRetry = sdk.calls;
    sdk.newest = List.generate(50, (i) => row(102 - i));
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(callsBeforeRetry));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-102');
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(model.readReports, greaterThan(0));
    await unmount(tester);
  });

  uiTest(
      'confirmed deletion of all pending messages allows the actual older latest page',
      (tester) async {
    await mount(tester, entry: 100);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    final scope = global.historyWindowScopeFor(getConv())!;
    var done = false;
    Object? failure;
    final deletes = (() async {
      for (final id in [101, 102]) {
        await store.recordMutation(HistoryWindowMutation(
            ownerUserID: scope.ownerUserID,
            conversationID: scope.conversationID,
            clearEpoch: scope.clearEpoch,
            msgID: '${getConv()}-$id',
            eventID: 'server-delete-$id',
            kind: HistoryWindowMutationKind.delete));
      }
    })()
        .catchError((Object error) {
      failure = error;
    }).whenComplete(() {
      done = true;
    });
    for (var n = 0; n < 1500 && !done; n++) {
      await frame(tester);
    }
    expect(done, isTrue);
    await deletes;
    expect(failure, isNull);
    sdk.newest = List.generate(50, (i) => row(100 - i));
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(0));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-100');
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(model.readReports, greaterThan(0));
    await unmount(tester);
  });

  uiTest('arrival after the reload ACK is revealed and read only after reaching bottom',
      (tester) async {
    await mount(tester, entry: 100);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    sdk.newest = List.generate(50, (i) => row(102 - i));
    Future<void>? lateArrival;
    Object? lateFailure;
    var lateArrivalFinished = false;
    store.afterAcknowledge = () async {
      // The transaction has acknowledged only 101/102. An inbound durable
      // append at its old-history edge must survive the remaining UI frames.
      global.setMessageListPosition(
          getConv(), HistoryMessagePosition.awayTwoScreen,
          notify: false);
      lateArrival = global
          .applyAppRealtimeMessage(row(103),
              ingressEventID: '${getConv()}-event-103', ingressSequence: 103)
          .catchError((Object error) {
        lateFailure = error;
      }).whenComplete(() => lateArrivalFinished = true);
      // Admission is queued behind the ACK transaction. Do not await that
      // queue from inside the transaction itself.
    };
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    final lateArrivalTime = Stopwatch()..start();
    while (!lateArrivalFinished &&
        lateArrivalTime.elapsed < const Duration(seconds: 15)) {
      await frame(tester);
    }
    expect(lateArrivalFinished, isTrue,
        reason: 'post-reload admission must finish while frames keep running');
    await lateArrival;
    expect(lateFailure, isNull,
        reason: 'post-ACK admission must survive session reset');
    await frame(tester);
    expect(global.rawMessageList(getConv())!.first.seq, '103');
    expect(scroll.offset, closeTo(0, 1));
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(find.text('showUnread:1').hitTestable(), findsNothing);
    expect(find.text('showPrevious:100'), findsNothing);
    expect(model.readReports, 1);
    await unmount(tester);
  });

  uiTest('entry unread remains absent before and after a manual return',
      (tester) async {
    global.lockEntryUnreadForTongue(
        conversationID: getConv(), unreadCount: 100);
    await mount(tester, entry: 100);
    await away(tester);
    expect(find.text('showPrevious:100'), findsNothing);
    global.setChatListUserScrolling(true);
    await tester.drag(find.byKey(const Key('history')), const Offset(0, -1500));
    await frame(tester);
    global.setChatListUserScrolling(false);
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 24));
    expect(find.text('showPrevious:100'), findsNothing);
    expect(global.hasLockedEntryUnreadFor(getConv()), isFalse);
    expect(model.readReports, greaterThan(0));
    await unmount(tester);
  });

  uiTest('late return from A cannot strand the reused tongue or clear B unread',
      (tester) async {
    await mount(tester, entry: 100);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 2);
    final release = Completer<void>();
    final oldModel = model;
    final oldRows = List.generate(50, (i) => row(102 - i));
    sdk.newest = oldRows;
    sdk.duringRead = () => release.future;
    await tester.tap(find.text('showUnread:2'));
    for (var n = 0; n < 50 && sdk.calls == 0; n++) {
      await frame(tester);
    }
    expect(sdk.calls, greaterThan(0));
    model = makeModel('@TGS#next_$sequence');
    global.setCurrentConversation(
        CurrentConversation(getConv(), ConvType.group),
        notify: false);
    global.bindActiveChatScrollController(
        conversationID: getConv(), scrollController: scroll);
    global.bindHistoryLiveWindowFreeze(
      conversationID: getConv(),
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    global.setMessageList(getConv(), List.generate(100, (i) => row(100 - i)),
        replace: true);
    await mount(tester, entry: 200);
    scroll.jumpTo(0);
    await frame(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 201, 1);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
    final calls = sdk.calls;
    sdk.duringRead = null;
    sdk.newest = List.generate(50, (i) => row(201 - i));
    await tester.tap(find.text('showUnread:1'));
    await settleReturn(tester);
    expect(sdk.calls, greaterThan(calls));
    expect(global.rawMessageList(getConv())!.first.msgID, '${getConv()}-201');
    await awayInHistoryGap(tester);
    await receive(tester, 202, 1);
    expect(global.receivedNewMessageCountFor(getConv()), 1);
    release.complete();
    await settleReturn(tester);
    expect(global.rawMessageList(getConv())!.first.groupID, getConv());
    expect(global.receivedNewMessageCountFor(getConv()), 1);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
    oldModel.dispose();
    await unmount(tester);
  });
  uiTest('an old A return cannot unlock a newer A return after A to B to A',
      (tester) async {
    final conversationA = getConv();
    final oldModelA = model;
    final oldRelease = Completer<void>();
    final newRelease = Completer<void>();
    var oldFinished = false;
    var newFinishing = false;
    _ChatModel? middleModel;
    try {
      await mount(tester, entry: 100, finishTransition: () async {
        oldFinished = true;
      });
      await awayInHistoryGap(tester);
      await receive(tester, 101, 2);
      sdk.newest = List.generate(50, (i) => row(102 - i));
      sdk.duringRead = () => oldRelease.future;
      await tester.tap(find.text('showUnread:2'));
      for (var n = 0; n < 80 && sdk.calls == 0; n++) {
        await frame(tester);
      }
      expect(sdk.calls, 1);
      final modelB = makeModel('@TGS#middle_$sequence');
      middleModel = modelB;
      model = modelB;
      global.setCurrentConversation(
          CurrentConversation(getConv(), ConvType.group),
          notify: false);
      global.setMessageList(getConv(), List.generate(100, (i) => row(100 - i)),
          replace: true);
      await mount(tester, entry: 200);
      model = makeModel(conversationA);
      global.setCurrentConversation(
          CurrentConversation(getConv(), ConvType.group),
          notify: false);
      global.bindActiveChatScrollController(
          conversationID: getConv(), scrollController: scroll);
      global.bindHistoryLiveWindowFreeze(
        conversationID: getConv(),
        freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
      );
      await mount(tester, entry: 300, finishTransition: () async {
        newFinishing = true;
        await newRelease.future;
      });
      scroll.jumpTo(0);
      await frame(tester);
      await awayInHistoryGap(tester);
      await tester.tap(find.text('showUnread:2'));
      for (var n = 0; n < 30; n++) {
        await frame(tester);
      }
      expect(global.isUserScrollToBottomInProgress(conversationA), isTrue);
      // The same SDK request is correctly shared by both models. Keep the new
      // UI's final transition pending after that shared response is delivered.
      expect(sdk.calls, 1);
      oldRelease.complete();
      final handoffWait = Stopwatch()..start();
      while (!(oldFinished && newFinishing) &&
          handoffWait.elapsed < const Duration(seconds: 15)) {
        // Wait for the actual ACK/reveal and transition callback. Real SQLite
        // completion can exceed a fixed 120-frame / 240 ms wall-clock budget.
        // Advance fake time gently so IO does not consume the UI deadline.
        await frame(tester, 1);
      }
      expect(oldFinished, isTrue);
      expect(newFinishing, isTrue);
      await frame(tester);
      expect(global.isUserScrollToBottomInProgress(conversationA), isTrue,
          reason: 'the old UI finally must not unlock the new UI transaction');
      newRelease.complete();
      await settleReturn(tester);
      expect(global.isUserScrollToBottomInProgress(conversationA), isFalse);
      expect(global.rawMessageList(conversationA)!.first.msgID,
          '$conversationA-102');
      await unmount(tester);
    } finally {
      // Failed assertions must release both controlled continuations before
      // uiTest closes SQLite, otherwise a late reload can reopen its database.
      if (!oldRelease.isCompleted) oldRelease.complete();
      if (!newRelease.isCompleted) newRelease.complete();
      final drainWait = Stopwatch()..start();
      while ((oldModelA.isLoadingChatHistory || model.isLoadingChatHistory ||
              global.isUserScrollToBottomInProgress(conversationA)) &&
          drainWait.elapsed < const Duration(seconds: 15)) {
        await frame(tester, 1);
      }
      oldModelA.dispose();
      middleModel?.dispose();
    }
  });
}
