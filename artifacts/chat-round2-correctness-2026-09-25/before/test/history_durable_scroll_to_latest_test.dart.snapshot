import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_tongue_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_history_window_transition.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';

V2TimMessage _message(String conversationID, int seq) => V2TimMessage.fromJson({
      'message_msg_id': '$conversationID-$seq',
      'message_conv_id': conversationID,
      'message_conv_type': 2,
      'message_server_time': seq,
      'message_risk_type_identified': 0,
    })
      ..groupID = conversationID
      ..seq = '$seq'
      ..isSelf = false
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'message $seq');

class _ObservedTrimStore extends HistoryWindowStore {
  _ObservedTrimStore({required super.debugDatabasePath});

  int trimPageWrites = 0;
  int pendingPageSaves = 0;

  @override
  Future<void> savePages(List<HistoryWindowPage> pages) async {
    pendingPageSaves++;
    try {
      await super.savePages(pages);
      if (pages.any((page) => page.pageKey.startsWith('window:'))) {
        trimPageWrites++;
      }
    } finally {
      pendingPageSaves--;
    }
  }
}

class _PagingSdk extends MessageService {
  int newest = 100;
  bool failHistory = false;
  int failedHistoryCalls = 0;
  Completer<void>? newerPageGate;
  Completer<void>? latestPageGate;
  int gatedNewerCalls = 0;
  final requests = <({HistoryMsgGetTypeEnum type, int seq, String? id})>[];

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
    requests.add((type: getType, seq: boundary, id: lastMsgID));
    final newer = getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    final gate = newerPageGate;
    if (!newer && boundary <= 0 && latestPageGate != null) {
      await latestPageGate!.future;
    }
    if (newer && gate != null && !gate.isCompleted) {
      gatedNewerCalls++;
      await gate.future;
    }
    if (failHistory) {
      failedHistoryCalls++;
      return const MessageHistorySdkResult(
          code: 10002,
          desc: 'controlled newer history unavailable',
          data: null);
    }
    final all = [
      for (var seq = newest; seq > 0; seq--) _message(groupID!, seq)
    ];
    final candidates = all.where((row) {
      final seq = int.parse(row.seq!);
      return boundary <= 0 || (newer ? seq > boundary : seq < boundary);
    }).toList();
    // NEWER must return the nearest adjacent page, even when 95 rows arrived.
    final rows = newer
        ? candidates.reversed.take(count).toList().reversed.toList()
        : candidates.take(count).toList();
    return MessageHistorySdkResult(
        code: 0,
        desc: 'controlled SDK page',
        data: V2TimMessageListResult(
            isFinished: candidates.length <= count, messageList: rows));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

// Only the external read-report side effect is suppressed. Loading, cursor
// updates, durable admission, publication and visible-latest proof are real.
class _ReadingModel extends TUIChatSeparateViewModel {
  Completer<bool>? pendingLatestPage;
  int pendingLatestCalls = 0;

  @override
  Future<bool> loadChatRecord({
    HistoryMsgGetTypeEnum? getType,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    V2TimMessage? lastMsg,
    LoadDirection direction = LoadDirection.previous,
    bool forceReloadNewest = false,
  }) {
    if (direction == LoadDirection.latest && pendingLatestPage != null) {
      pendingLatestCalls++;
      return pendingLatestPage!.future;
    }
    return super.loadChatRecord(
        getType: getType,
        lastMsgSeq: lastMsgSeq,
        count: count,
        lastMsgID: lastMsgID,
        lastMsg: lastMsg,
        direction: direction,
        forceReloadNewest: forceReloadNewest);
  }

  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _ObservedTrimStore store;
  late _PagingSdk sdk;
  late TUIChatGlobalModel global;
  late _ReadingModel model;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  Future<void>? pendingAdmissions;
  var admissionsIdle = true;
  var stopAdmissions = false;
  Object? admissionError;
  void Function()? afterFrame;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('durable-user-scroll-');
    store =
        _ObservedTrimStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _PagingSdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'durable-scroll-reader',
        accountGeneration: ++generation,
        domainGeneration: 1);
    final conv = '@TGS#durable_scroll_$generation';
    model = _ReadingModel()
      ..conversationID = conv
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.public
      ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Public')
      ..chatConfig = const TIMUIKitChatConfig(
          isAutoReportRead: false,
          isShowReadingStatus: false,
          inboundChunkRevealEnabled: true,
          isUseDraft: false)
      ..suppressReadReporting = true
      ..haveMoreData = false
      ..haveMoreLatestData = false;
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
        notify: false);
    global.setMessageList(
        conv, List.generate(100, (index) => _message(conv, 100 - index)),
        replace: true, applyMemoryWindow: false);
    global.markInitialHistoryLoaded(conv);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    pendingAdmissions = null;
    admissionsIdle = true;
    stopAdmissions = false;
    admissionError = null;
    afterFrame = null;
  });

  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final handler = FlutterError.onError;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = handler;
    afterFrame?.call();
  }

  Future<void> frames(WidgetTester tester, [int count = 25]) async {
    for (var i = 0; i < count; i++) {
      await frame(tester);
    }
  }

  Future<void> waitForRealIO(
      WidgetTester tester, bool Function() ready, String reason,
      {Duration timeout = const Duration(seconds: 15)}) async {
    // SQLite runs in real time; a frame count only budgets FakeAsync time and
    // expires too early when other Flutter test isolates compete for the DB.
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < timeout) {
      await frame(tester);
    }
    expect(ready(), isTrue, reason: reason);
  }

  Future<void> mount(WidgetTester tester,
      {bool realTongue = false,
      double Function(V2TimMessage? message)? rowHeight}) async {
    final conv = model.conversationID;
    final conversation = V2TimConversation(
        conversationID: 'group_$conv',
        groupID: conv,
        type: 2,
        unreadCount: 0,
        lastMessage: _message(conv, 100));
    final handler = FlutterError.onError;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
        ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TIMUIKitHistoryMessageListSelector(
            conversationID: conv,
            builder: (_, messages, __) => TIMUIKitHistoryMessageList(
              key: const Key('production-history-list'),
              model: model,
              conversation: conversation,
              controller: controller,
              messageList: messages,
              onLoadMore: (id, direction, [count, seq, message]) {
                return model.loadChatRecord(
                    count: count ?? 40,
                    direction: direction,
                    lastMsgID: id,
                    lastMsgSeq: seq ?? -1,
                    lastMsg: message);
              },
              itemBuilder: (_, message) => SizedBox(
                key: ValueKey('row-${message?.msgID}'),
                height: rowHeight?.call(message) ??
                    (message?.elemType == 11 ? 24 : 64),
                child: Text('seq:${message?.seq}'),
              ),
              tongueItemBuilder: realTongue
                  ? null
                  : (tap, type, count) => TextButton(
                      onPressed: tap, child: Text('${type.name}:$count')),
            ),
          ),
        ),
      ),
    ));
    FlutterError.onError = handler;
    await frames(tester);
    expect(scroll.hasClients, isTrue);
    expect(global.rawMessageCount(conv), 100);
  }

  Future<void> close(WidgetTester tester) async {
    if (sdk.latestPageGate != null && !sdk.latestPageGate!.isCompleted) {
      sdk.latestPageGate!.complete();
    }
    if (model.pendingLatestPage != null &&
        !model.pendingLatestPage!.isCompleted) {
      model.pendingLatestPage!.complete(false);
    }
    // If an assertion failed during admission, stop starting further appends
    // and finish the active one before invalidating its owner/session scope.
    stopAdmissions = true;
    await waitForRealIO(tester, () => admissionsIdle,
        'pending durable admission must finish before fixture disposal');
    await pendingAdmissions;
    final gate = sdk.newerPageGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
      await waitForRealIO(tester, () => !model.isLoadingChatHistory,
          'gated SDK history must settle before fixture disposal');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    // savePages queues each trim chunk separately through the persistence
    // coordinator. Closing the current DB transaction before that outer
    // Future finishes lets a later chunk reopen the Windows database handle.
    await waitForRealIO(tester, () => store.pendingPageSaves == 0,
        'all started page-save futures must finish before closing the database');
    global.dismissAllContextMenuOverlays();
    global.clearActiveChatScrollController(
        conversationID: model.conversationID);
    global.clearData();
    model.dispose();
    controller.dispose();
    scroll.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    var closed = false;
    final closing = store.closeIfOpen().whenComplete(() => closed = true);
    await waitForRealIO(tester, () => closed, 'history store must close');
    await closing;
    await frame(tester, 2000);
    await tester.runAsync(() => directory.delete(recursive: true));
    SqfliteLifecycleGuard.instance.debugReset();
  }

  for (final scenario in [
    (durable: false, count: 1, oldEdge: false),
    (durable: false, count: 71, oldEdge: false),
    (durable: true, count: 1, oldEdge: false),
    (durable: true, count: 71, oldEdge: false),
    (durable: true, count: 1, oldEdge: true),
  ]) {
    final durable = scenario.durable;
    final count = scenario.count;
    testWidgets(
        'return after $count arrivals reaches the rendered newest row '
        '(durable=$durable, oldEdge=${scenario.oldEdge})', (tester) async {
      try {
        if (!durable) HistoryWindowRepositoryProvider.repository = null;
        await mount(tester, realTongue: true);
        final conv = model.conversationID;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 1600));
        await frames(tester);
        expect(global.isFollowingLatest(conv), isFalse);
        sdk.newest = 100 + count;
        admissionsIdle = false;
        pendingAdmissions = (() async {
          try {
            for (var seq = 101; seq <= sdk.newest && !stopAdmissions; seq++) {
              await global.applyAppRealtimeMessage(_message(conv, seq),
                  ingressEventID: 'return-$seq', ingressSequence: seq);
            }
          } finally {
            admissionsIdle = true;
          }
        })();
        await waitForRealIO(
            tester, () => admissionsIdle, 'arrivals must commit');
        await pendingAdmissions;
        await frames(tester);
        if (scenario.oldEdge) {
          // Reaching the old physical edge must not take the early success
          // path while the newest message is still only in the repository.
          scroll.jumpTo(scroll.position.minScrollExtent);
        }
        final state =
            tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
                find.byType(TIMUIKitHistoryMessageListTongueContainer));
        var returned = false;
        final pending = state
            .scrollToLatestAndDismissUnreadCapsule()
            .whenComplete(() => returned = true);
        await waitForRealIO(tester, () => returned, 'one return must finish');
        await pending;
        await frames(tester);
        final newest = find.byKey(ValueKey('row-$conv-${sdk.newest}'));
        expect(newest.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(newest).dy,
            closeTo(tester.getBottomRight(find.byType(CustomScrollView)).dy, 4),
            reason:
                'the actual newest row must occupy the bottom of the viewport');
        expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
        expect(global.isFollowingLatest(conv), isTrue);
        if (!durable && count == 1) {
          // The first arrival after restoration must extend the real live
          // edge and stay in the viewport without another manual swipe.
          sdk.newest++;
          await global.applyAppRealtimeMessage(_message(conv, sdk.newest),
              ingressEventID: 'after-return-${sdk.newest}',
              ingressSequence: sdk.newest);
          await frames(tester);
          final followingRow =
              find.byKey(ValueKey('row-$conv-${sdk.newest}'));
          expect(followingRow.hitTestable(), findsOneWidget);
          expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
        }
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets(
      'production return keeps drag interactive and cancels late publication',
      (tester) async {
    try {
      await mount(tester);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      global.markMemoryWindowMissingNewer(conv);
      sdk.newest = 150;
      sdk.latestPageGate = Completer<void>();
      final state =
          tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
              find.byType(TIMUIKitHistoryMessageListTongueContainer));
      var returned = false;
      final pending = state
          .scrollToLatestAndDismissUnreadCapsule()
          .whenComplete(() => returned = true);
      await waitForRealIO(tester, () => sdk.requests.any((r) => r.seq <= 0),
          'latest SDK request must start');
      expect(find.byType(RawImage), findsNothing,
          reason: 'network waits must not retain a pointer-absorbing snapshot');
      expect(find.text('取消'), findsNothing);
      final before = scroll.offset;
      await tester.drag(list, const Offset(0, 120));
      await frames(tester);
      expect(scroll.offset, greaterThan(before));
      expect(returned, isTrue,
          reason: 'a deliberate drag cancels explicit return');
      expect(global.isUserScrollToBottomInProgress(conv), isFalse);
      final afterDrag = scroll.offset;
      sdk.latestPageGate!.complete();
      await waitForRealIO(tester, () => !model.isLoadingChatHistory,
          'late request must finish without publishing');
      await frames(tester);
      expect(global.rawMessageList(conv)!.first.seq, '100');
      expect(scroll.offset, closeTo(afterDrag, 1));
      await pending;
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'old newer-page cleanup cannot restore suppression after window replacement',
      (tester) async {
    try {
      await mount(tester);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      model.haveMoreLatestData = true;
      global.markMemoryWindowMissingNewer(conv);
      global.setMemoryWindowSuppressed(conv, true);
      model.pendingLatestPage = Completer<bool>();
      admissionsIdle = false;
      pendingAdmissions = global
          .applyAppRealtimeMessage(_message(conv, 101),
              ingressEventID: 'stale-page-101', ingressSequence: 101)
          .then<void>((_) {})
          .whenComplete(() => admissionsIdle = true);
      await waitForRealIO(
          tester, () => admissionsIdle, 'durable arrival must persist');
      final reachingEdge = Stopwatch()..start();
      while (model.pendingLatestCalls == 0 &&
          reachingEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -1500));
        await frames(tester);
      }
      expect(model.pendingLatestCalls, greaterThan(0),
          reason: 'manual scrolling must start a newer-page request');
      sdk.newest = 150;
      var reloaded = false;
      final reload = model
          .reloadNewestMessageWindow(allowWhileReadingHistory: true)
          .then((result) => reloaded = result);
      await waitForRealIO(tester, () => reloaded, 'replacement must finish');
      await reload;
      // The new window now owns this setting; the old pagination must not
      // restore the value it captured before that replacement.
      global.setMemoryWindowSuppressed(conv, false);
      model.pendingLatestPage!.complete(false);
      await frames(tester);
      expect(global.isMemoryWindowSuppressed(conv), isFalse);
      expect(global.rawMessageList(conv)!.first.seq, '150');
    } finally {
      await close(tester);
    }
  });

  for (final scenario in [
    (step: 48.0, height: 64.0),
    (step: 96.0, height: 64.0),
    (step: 48.0, height: 32.0),
  ]) {
    testWidgets(
        'continuous hot drag follows every frame '
        '(step=${scenario.step}, row=${scenario.height})', (tester) async {
      TestGesture? gesture;
      try {
        HistoryWindowRepositoryProvider.repository = null;
        await mount(tester,
            realTongue: true,
            rowHeight: (message) =>
                message?.elemType == 11 ? 24 : scenario.height);
        final conv = model.conversationID;
        final list = find.byType(CustomScrollView);
        await tester.drag(list, const Offset(0, 512), touchSlopY: 0);
        await frames(tester);
        sdk.newest = 171;
        for (var seq = 101; seq <= sdk.newest; seq++) {
          await global.applyAppRealtimeMessage(_message(conv, seq),
              ingressEventID: 'continuous-hot-$seq', ingressSequence: seq);
        }
        await frames(tester);
        expect(global.deferredIncomingBufferedCount(conv), 0);
        expect(global.rawMessageCount(conv), 171);
        expect(global.receivedNewMessageCountFor(conv), 71);
        gesture = await tester.startGesture(const Offset(400, 550));
        await gesture.moveBy(const Offset(0, -20));
        await frame(tester, 16);
        for (var step = 0; step < 30; step++) {
          final before = scroll.offset;
          await gesture.moveBy(Offset(0, -scenario.step));
          await frame(tester, 16);
          expect(scroll.offset - before, closeTo(-scenario.step, 1),
              reason: 'frame $step must follow the finger across the appended '
                  'rows; buffered=${global.deferredIncomingBufferedCount(conv)}');
        }
        // Appended rows ahead of the finger must not consume their unread IDs.
        final unread = global.receivedNewMessageCountFor(conv);
        expect(unread, inExclusiveRange(0, 71));
        expect(global.rawMessageCount(conv), 171);
      } finally {
        await gesture?.cancel();
        await close(tester);
      }
    });
  }

  testWidgets(
      'row-by-row downward scroll preserves anchors and consumes only seen arrivals',
      (tester) async {
    const arrivalsCount = 71;
    try {
      await mount(tester, realTongue: true);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      final viewport = tester.getRect(list);

      Finder row(int seq) => find.byKey(ValueKey('row-$conv-$seq'));
      bool fullyVisible(int seq) {
        final finder = row(seq);
        if (finder.evaluate().isEmpty) return false;
        final rect = tester.getRect(finder);
        return rect.top >= viewport.top - 1 &&
            rect.bottom <= viewport.bottom + 1;
      }

      void expectCounter(int expected) {
        expect(global.receivedNewMessageCountFor(conv), expected);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        if (expected == 0) {
          expect(capsule.hitTestable(), findsNothing);
        } else {
          if (capsule.hitTestable().evaluate().isEmpty) {
            expect(scroll.offset - scroll.position.minScrollExtent,
                lessThan(scroll.position.viewportDimension * 0.5),
                reason:
                    'a hidden capsule must be within its distance threshold');
          } else {
            expect(capsule.hitTestable(), findsOneWidget);
            expect(tester.widget<TIMUIKitTongueItem>(capsule).unreadCount,
                expected);
            final label =
                find.descendant(of: capsule, matching: find.byType(Text));
            expect(tester.widget<Text>(label).data, contains('$expected'));
          }
        }
      }

      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      sdk.newest = 100 + arrivalsCount;
      sdk.newerPageGate = Completer<void>();
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= sdk.newest && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'seen-arrival-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          '71 real durable admissions must finish');
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expectCounter(arrivalsCount);

      // Reach the old loaded edge with real gestures while the first network
      // page is held. Opening a newer page must keep message 100 at that edge.
      final reachingOldEdge = Stopwatch()..start();
      while ((!fullyVisible(100) || sdk.gatedNewerCalls == 0) &&
          reachingOldEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester, 5);
      }
      expect(fullyVisible(100), isTrue);
      expect(sdk.gatedNewerCalls, greaterThan(0));
      final oldAnchorTop = tester.getTopLeft(row(100)).dy;
      expectCounter(arrivalsCount);
      sdk.newerPageGate!.complete();
      await waitForRealIO(
          tester,
          () => global.rawMessageList(conv)!.any((m) => m.seq == '120'),
          'the first newer page must load');
      await frames(tester);
      expect(fullyVisible(100), isTrue,
          reason:
              'loading 20 unseen messages must not jump past the old anchor');
      expect(tester.getTopLeft(row(100)).dy, closeTo(oldAnchorTop, 1));
      expect(fullyVisible(101), isFalse);
      expectCounter(arrivalsCount);

      for (var seq = 101; seq <= 100 + arrivalsCount; seq++) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester, 25);
        expect(fullyVisible(seq), isTrue,
            reason: 'one 64px gesture must reveal adjacent message $seq');
        await waitForRealIO(
            tester,
            () =>
                global.receivedNewMessageCountFor(conv) <=
                100 + arrivalsCount - seq,
            'the visible receipt for message $seq must commit');
        // Receipt publication can occur after this frame's widget build.
        await frames(tester, 2);
        expect(fullyVisible(seq), isTrue);
        expectCounter(100 + arrivalsCount - seq);
        if (seq == 102) {
          // Revisiting an already seen row must not resurrect its reminder.
          await tester.drag(list, const Offset(0, 64), touchSlopY: 0);
          await frames(tester, 25);
          expect(fullyVisible(101), isTrue);
          expectCounter(arrivalsCount - 2);
          await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
          await frames(tester, 25);
          expect(fullyVisible(102), isTrue);
          expectCounter(arrivalsCount - 2);
        }
      }
      await waitForRealIO(tester, () => !global.hasDurableHistoryDeferred(conv),
          'viewing the final arrival must finish durable acknowledgement');
      expectCounter(0);
      await waitForRealIO(
          tester,
          () => global.isFollowingLatest(conv) && model.hasCaughtUpToLiveLatest,
          'reading the last arrival must resume following live messages');
      await frames(tester);
      final beforeLiveTop = tester.getTopLeft(row(171)).dy;
      var previousTop = beforeLiveTop;
      void observeLiveGeometry() {
        expect(row(171), findsOneWidget);
        final nextTop = tester.getTopLeft(row(171)).dy;
        expect(nextTop, lessThanOrEqualTo(previousTop + 1),
            reason: 'returning to live must not push message 171 backwards');
        previousTop = nextTop;
      }

      sdk.newest = 172;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          await global.applyAppRealtimeMessage(_message(conv, 172),
              ingressEventID: 'live-after-reading-172', ingressSequence: 172);
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      final liveWait = Stopwatch()..start();
      while (
          !admissionsIdle && liveWait.elapsed < const Duration(seconds: 15)) {
        await frame(tester);
        observeLiveGeometry();
      }
      expect(admissionsIdle, isTrue);
      await pendingAdmissions;
      expect(admissionError, isNull);
      for (var frameIndex = 0; frameIndex < 40; frameIndex++) {
        await frame(tester);
        observeLiveGeometry();
      }
      expect(fullyVisible(171), isTrue);
      expect(fullyVisible(172), isTrue);
      expect(tester.getTopLeft(row(172)).dy, closeTo(beforeLiveTop, 1));
      expect(tester.getTopLeft(row(171)).dy, closeTo(beforeLiveTop - 64, 1));
      expect(scroll.offset - scroll.position.minScrollExtent, closeTo(0, 1));
      expect(global.isFollowingLatest(conv), isTrue);
      expect(model.hasCaughtUpToLiveLatest, isTrue);
      expectCounter(0);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'pure hot arrivals keep their anchors and count until each row is visible',
      (tester) async {
    const newest = 171;
    try {
      // Exercise the connected in-memory append path independently of storage.
      HistoryWindowRepositoryProvider.repository = null;
      await mount(tester, realTongue: true);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      final viewport = tester.getRect(list);
      Finder row(int seq) => find.byKey(ValueKey('row-$conv-$seq'));
      bool fullyVisible(int seq) {
        if (row(seq).evaluate().isEmpty) return false;
        final rect = tester.getRect(row(seq));
        return rect.top >= viewport.top - 1 &&
            rect.bottom <= viewport.bottom + 1;
      }

      void expectCounter(int expected) {
        expect(global.receivedNewMessageCountFor(conv), expected);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        if (expected == 0) {
          expect(capsule.hitTestable(), findsNothing);
        } else {
          if (capsule.hitTestable().evaluate().isEmpty) {
            expect(scroll.offset - scroll.position.minScrollExtent,
                lessThan(scroll.position.viewportDimension * 0.5));
          } else {
            expect(capsule.hitTestable(), findsOneWidget);
            expect(tester.widget<TIMUIKitTongueItem>(capsule).unreadCount,
                expected);
          }
        }
      }

      await tester.drag(list, const Offset(0, 512), touchSlopY: 0);
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      final beforeArrivalOffset = scroll.offset;
      final beforeArrivalIDs =
          global.rawMessageList(conv)!.map((message) => message.msgID).toList();
      sdk.newest = newest;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= newest && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'hot-reading-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(
          tester, () => admissionsIdle, '71 pure hot admissions must finish');
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect(global.rawMessageCount(conv), newest);
      expect(
          global
              .rawMessageList(conv)!
              .skip(newest - beforeArrivalIDs.length)
              .map((message) => message.msgID),
          orderedEquals(beforeArrivalIDs));
      expect(scroll.offset, closeTo(beforeArrivalOffset, 1));
      expectCounter(71);

      final reachingOldEdge = Stopwatch()..start();
      while (!fullyVisible(100) &&
          reachingOldEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expectCounter(71);
      }
      expect(fullyVisible(100), isTrue);
      final readingEdgeTop = tester.getTopLeft(row(100)).dy;
      expectCounter(71);

      for (var seq = 101; seq <= newest; seq++) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expect(fullyVisible(seq), isTrue,
            reason: 'one gesture must reveal adjacent hot message $seq; '
                'rect=${row(seq).evaluate().isEmpty ? 'unmounted' : tester.getRect(row(seq))}, '
                'viewport=$viewport, raw=${global.rawMessageCount(conv)}, '
                'hot=${global.deferredIncomingBufferedCount(conv)}, '
                'received=${global.receivedNewMessageCountFor(conv)}, '
                'offset=${scroll.offset}, '
                'minimum=${scroll.position.minScrollExtent}');
        expect(tester.getTopLeft(row(seq)).dy, closeTo(readingEdgeTop, 1));
        expectCounter(newest - seq);
        expect(global.hasDurableHistoryDeferred(conv), isFalse);
        if (seq == 102) {
          await tester.drag(list, const Offset(0, 64), touchSlopY: 0);
          await frames(tester);
          expect(fullyVisible(101), isTrue);
          expectCounter(69);
          await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
          await frames(tester);
          expect(fullyVisible(102), isTrue);
          expectCounter(69);
        }
      }
      await waitForRealIO(
          tester,
          () => global.isFollowingLatest(conv) && model.hasCaughtUpToLiveLatest,
          'reading every hot arrival must return to following latest');
      expectCounter(0);
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect(fullyVisible(newest), isTrue);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'idle connected append keeps the reading position and unread count',
      (tester) async {
    try {
      HistoryWindowRepositoryProvider.repository = null;
      await mount(tester, realTongue: true);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      Future<int> pumpOnlyScheduledFrames() async {
        var pumped = 0;
        // Do not introduce a gesture while verifying idle append behavior.
        while (tester.binding.hasScheduledFrame && pumped < 60) {
          final handler = FlutterError.onError;
          await tester.pump(const Duration(milliseconds: 16));
          FlutterError.onError = handler;
          pumped++;
        }
        expect(tester.binding.hasScheduledFrame, isFalse,
            reason: 'idle append must finish within a bounded number '
                'of production-scheduled frames');
        return pumped;
      }

      void expectCounter(int expected) {
        expect(global.hasDurableHistoryDeferred(conv), isFalse);
        expect(global.receivedNewMessageCountFor(conv), expected);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        if (capsule.hitTestable().evaluate().isEmpty) {
          expect(scroll.offset - scroll.position.minScrollExtent,
              lessThan(scroll.position.viewportDimension * 0.5));
        } else {
          expect(capsule.hitTestable(), findsOneWidget);
          expect(
              tester.widget<TIMUIKitTongueItem>(capsule).unreadCount, expected);
        }
      }

      await tester.drag(list, const Offset(0, 512), touchSlopY: 0);
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      final readingOffset = scroll.offset;
      sdk.newest = 171;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= 171 && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'idle-hot-reading-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          'pure hot admissions must finish before testing idle frame supply');
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expect(global.rawMessageCount(conv), 171);
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect(scroll.offset, closeTo(readingOffset, 1));
      expectCounter(71);

      await pumpOnlyScheduledFrames();
      expect(global.rawMessageCount(conv), 171);
      expect(scroll.offset, closeTo(readingOffset, 1));
      expectCounter(71);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'an 1800px pure hot row is counted only at its bottom before the next row',
      (tester) async {
    try {
      HistoryWindowRepositoryProvider.repository = null;
      await mount(tester,
          realTongue: true,
          rowHeight: (message) => message?.seq == '101'
              ? 1800
              : message?.elemType == 11
                  ? 24
                  : 64);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      final viewport = tester.getRect(list);
      Finder row(int seq) => find.byKey(ValueKey('row-$conv-$seq'));
      bool fullyVisible(int seq) {
        if (row(seq).evaluate().isEmpty) return false;
        final rect = tester.getRect(row(seq));
        return rect.top >= viewport.top - 1 &&
            rect.bottom <= viewport.bottom + 1;
      }

      void expectCounter(int expected) {
        expect(global.hasDurableHistoryDeferred(conv), isFalse);
        expect(global.receivedNewMessageCountFor(conv), expected);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        if (capsule.hitTestable().evaluate().isEmpty) {
          expect(scroll.offset - scroll.position.minScrollExtent,
              lessThan(scroll.position.viewportDimension * 0.5));
        } else {
          expect(capsule.hitTestable(), findsOneWidget);
          expect(
              tester.widget<TIMUIKitTongueItem>(capsule).unreadCount, expected);
        }
      }

      await tester.drag(list, const Offset(0, 512), touchSlopY: 0);
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      final beforeArrivalOffset = scroll.offset;
      final beforeArrivalIDs =
          global.rawMessageList(conv)!.map((message) => message.msgID).toList();
      sdk.newest = 171;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= 171 && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'hot-tall-reading-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          '71 pure hot admissions including a tall row must finish');
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect(global.rawMessageCount(conv), 171);
      expect(
          global
              .rawMessageList(conv)!
              .skip(171 - beforeArrivalIDs.length)
              .map((message) => message.msgID),
          orderedEquals(beforeArrivalIDs));
      expect(scroll.offset, closeTo(beforeArrivalOffset, 1));
      expectCounter(71);

      final reachingOldEdge = Stopwatch()..start();
      while (!fullyVisible(100) &&
          reachingOldEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expectCounter(71);
      }
      expect(fullyVisible(100), isTrue);
      final oldAnchorTop = tester.getTopLeft(row(100)).dy;
      await waitForRealIO(
          tester,
          () => global
              .rawMessageList(conv)!
              .any((message) => message.seq == '101'),
          'the tall hot row must be staged before reading beyond the old edge');
      await frames(tester);
      expect(fullyVisible(100), isTrue);
      expect(tester.getTopLeft(row(100)).dy, closeTo(oldAnchorTop, 1));
      expectCounter(71);

      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      await frames(tester);
      expect(row(101), findsOneWidget);
      var tallRect = tester.getRect(row(101));
      expect(tallRect.height, 1800);
      expect(tallRect.top, lessThan(viewport.bottom));
      expect(tallRect.bottom, greaterThan(viewport.bottom));
      expectCounter(71);

      var observedMiddle = false;
      final readingTallRow = Stopwatch()..start();
      while (tallRect.bottom > viewport.bottom + 64 &&
          readingTallRow.elapsed < const Duration(seconds: 15)) {
        final previousTop = tallRect.top;
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expect(row(101), findsOneWidget);
        tallRect = tester.getRect(row(101));
        expect(tallRect.top, closeTo(previousTop - 64, 1),
            reason: 'preparing adjacent hot rows must not jump within media');
        if (tallRect.top < viewport.top && tallRect.bottom > viewport.bottom) {
          observedMiddle = true;
        }
        expectCounter(71);
      }
      expect(observedMiddle, isTrue,
          reason: 'the test must scroll through the middle of the tall row');
      final remaining = tallRect.bottom - viewport.bottom;
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(64));
      await tester.drag(list, Offset(0, -remaining), touchSlopY: 0);
      await frames(tester);
      expect(tester.getRect(row(101)).bottom, closeTo(viewport.bottom, 1));
      expectCounter(70);

      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      await frames(tester);
      expect(fullyVisible(102), isTrue,
          reason: 'one further gesture must reveal the row after tall media');
      expect(tester.getRect(row(102)).bottom, closeTo(viewport.bottom, 1));
      expectCounter(69);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'one latest edge gesture survives temporary media restoration geometry',
      (tester) async {
    try {
      await mount(tester, realTongue: true);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 1200), touchSlopY: 0);
      await frames(tester);
      sdk.newest = 101;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          await global.applyAppRealtimeMessage(_message(conv, 101),
              ingressEventID: 'media-geometry-101', ingressSequence: 101);
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(
          tester, () => admissionsIdle, 'the pending arrival must be durable');
      expect(admissionError, isNull);
      await frames(tester);
      expect(global.receivedNewMessageCountFor(conv), 1);
      expect(global.hasDurableHistoryDeferred(conv), isTrue);

      // Place the user within the edge band without arming a user gesture.
      scroll.jumpTo(scroll.position.minScrollExtent + 64);
      await frames(tester);
      final requestsBefore = sdk.requests.length;
      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      final edgePixels = scroll.offset;
      global.saveScrollBeforeMediaPreview(conv);
      // Reparenting/restoration may temporarily change scroll coordinates.
      // This is a programmatic update, not a second or reversed user gesture.
      scroll.jumpTo(edgePixels + 512);
      await frames(tester);
      expect(
          sdk.requests.skip(requestsBefore).where(
              (r) => r.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG),
          isEmpty);
      global.restoreScrollAfterMediaPreview(conv);
      await frames(tester);
      global.finishScrollAfterMediaPreview(conv);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 450)));
      await waitForRealIO(
          tester,
          () =>
              !global.shouldLockChatScrollForMediaPreview &&
              !global.isRestoringScrollAfterMediaPreview,
          'media restoration must release');
      await waitForRealIO(
          tester,
          () => global.rawMessageList(conv)!.any((m) => m.seq == '101'),
          'the original edge gesture must resume without a second drag');
      expect(
          sdk.requests
              .skip(requestsBefore)
              .where((r) =>
                  r.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG)
              .length,
          1);
      expect(scroll.offset, closeTo(edgePixels, 1));
      expect(global.receivedNewMessageCountFor(conv), 1,
          reason: 'loading an unseen row must not acknowledge it');
      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      await frames(tester);
      final latest = find.byKey(ValueKey('row-$conv-101'));
      expect(latest.hitTestable(), findsOneWidget);
      expect(tester.getRect(latest).bottom,
          lessThanOrEqualTo(tester.getRect(list).bottom + 1));
      await waitForRealIO(
          tester,
          () => global.receivedNewMessageCountFor(conv) == 0,
          'the visibly consumed row must acknowledge normally');
    } finally {
      global.endMediaPreviewOverlay();
      await close(tester);
    }
  });

  testWidgets(
      '300 arrivals cross real window trims without skipping rows or unread progress',
      (tester) async {
    const newest = 400;
    try {
      await mount(tester, realTongue: true);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      final viewport = tester.getRect(list);
      Finder row(int seq) => find.byKey(ValueKey('row-$conv-$seq'));
      bool fullyVisible(int seq) {
        if (row(seq).evaluate().isEmpty) return false;
        final rect = tester.getRect(row(seq));
        return rect.top >= viewport.top - 1 &&
            rect.bottom <= viewport.bottom + 1;
      }

      void expectCounter(int expected) {
        expect(global.receivedNewMessageCountFor(conv), expected);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        if (expected == 0) {
          expect(capsule.hitTestable(), findsNothing);
        } else {
          if (capsule.hitTestable().evaluate().isEmpty) {
            expect(scroll.offset - scroll.position.minScrollExtent,
                lessThan(scroll.position.viewportDimension * 0.5));
          } else {
            expect(capsule.hitTestable(), findsOneWidget);
            expect(tester.widget<TIMUIKitTongueItem>(capsule).unreadCount,
                expected);
          }
        }
      }

      var previousWindowCount = global.rawMessageCount(conv);
      var peakWindowCount = previousWindowCount;
      final committedTrimSizes = <({int before, int after})>[];
      afterFrame = () {
        final count = global.rawMessageCount(conv);
        if (count > peakWindowCount) peakWindowCount = count;
        if (count < previousWindowCount) {
          committedTrimSizes.add((before: previousWindowCount, after: count));
          expect(count, ChatMessageWindowPolicy.targetSize,
              reason: 'an idle trim must retain its full target window');
        }
        previousWindowCount = count;
        expect(count, lessThanOrEqualTo(ChatMessageWindowPolicy.softMax),
            reason: 'each published window must remain bounded');
      };

      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      sdk.newest = newest;
      sdk.newerPageGate = Completer<void>();
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= newest && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'trim-reading-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          '300 real durable admissions must finish before scrolling',
          timeout: const Duration(seconds: 60));
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expectCounter(300);

      final reachingOldEdge = Stopwatch()..start();
      while ((!fullyVisible(100) || sdk.gatedNewerCalls == 0) &&
          reachingOldEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester, 5);
      }
      expect(fullyVisible(100), isTrue);
      expect(sdk.gatedNewerCalls, greaterThan(0));
      final readingEdgeTop = tester.getTopLeft(row(100)).dy;
      sdk.newerPageGate!.complete();
      await waitForRealIO(
          tester,
          () => global
              .rawMessageList(conv)!
              .any((message) => message.seq == '120'),
          'the first adjacent page must load');
      await frames(tester);
      expect(fullyVisible(100), isTrue);
      expect(tester.getTopLeft(row(100)).dy, closeTo(readingEdgeTop, 1));
      expectCounter(300);

      for (var seq = 101; seq <= newest; seq++) {
        // FakeAsync advances 500 ms between gestures while SQLite receives
        // only a few real milliseconds. Let the already-armed edge request
        // finish its page/trim before dragging across an unloaded boundary.
        // Waiting neither sends another gesture nor waits for the next row
        // to become visible: that still requires exactly one 64 px drag.
        if (!global.rawMessageList(conv)!.any((m) => m.seq == '$seq')) {
          await waitForRealIO(
              tester,
              () =>
                  global.rawMessageList(conv)!.any((m) => m.seq == '$seq') &&
                  !model.isLoadingChatHistory &&
                  !tester
                      .state<ChatHistoryWindowTransitionState>(
                          find.byType(ChatHistoryWindowTransition))
                      .isRetainingViewport,
              'the existing edge request must load message $seq without another gesture');
          expect(fullyVisible(seq - 1), isTrue);
          expect(
              tester.getTopLeft(row(seq - 1)).dy, closeTo(readingEdgeTop, 1));
          expectCounter(newest - seq + 1);
        }
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        await waitForRealIO(
            tester,
            () => !tester
                .state<ChatHistoryWindowTransitionState>(
                    find.byType(ChatHistoryWindowTransition))
                .isRetainingViewport,
            'message $seq must finish the real trim snapshot transition');
        final adjacentAfterGesture = fullyVisible(seq);
        if (!adjacentAfterGesture) {
          final nearby = <String>[];
          for (var candidate = seq - 3; candidate <= seq + 3; candidate++) {
            nearby.add(
                '$candidate:${row(candidate).evaluate().isEmpty ? 'unmounted' : tester.getRect(row(candidate))}');
          }
          debugPrint('CHAT_OVERLAP_ADJACENCY_FAILURE '
              '${{
            'expected': seq,
            'sdkNewest': sdk.newest,
            'sdkRequests': sdk.requests,
            'rawNewest': global.rawMessageList(conv)?.first.seq,
            'rawOldest': global.rawMessageList(conv)?.last.seq,
            'cursor': model.historyNewerPageCursor?.seq,
            'modelLoading': model.isLoadingChatHistory,
            'modelMoreLatest': model.haveMoreLatestData,
            'rawCount': global.rawMessageCount(conv),
            'offset': scroll.offset,
            'minExtent': scroll.position.minScrollExtent,
            'maxExtent': scroll.position.maxScrollExtent,
            'unread': global.receivedNewMessageCountFor(conv),
            'following': global.isFollowingLatest(conv),
            'newerMissing': global.memoryWindowMissingNewer(conv),
            'historyActive': model.hasHistoryReadingWindow,
            'rowRects': nearby,
            'trimCount': committedTrimSizes.length,
          }}');
          await frames(tester, 200);
          debugPrint('CHAT_OVERLAP_AFTER_NO_FURTHER_GESTURE '
              'expected=$seq sdkRequests=${sdk.requests.length} '
              'rawNewest=${global.rawMessageList(conv)?.first.seq} '
              'cursor=${model.historyNewerPageCursor?.seq} '
              'rawCount=${global.rawMessageCount(conv)} '
              'offset=${scroll.offset} min=${scroll.position.minScrollExtent} '
              'rect=${row(seq).evaluate().isEmpty ? 'unmounted' : tester.getRect(row(seq))}');
        }
        expect(adjacentAfterGesture, isTrue,
            reason: 'message $seq must remain adjacent after '
                '${committedTrimSizes.length} committed trims; '
                'window=${global.rawMessageCount(conv)}, '
                'offset=${scroll.offset}, '
                'cursor=${model.historyNewerPageCursor?.seq}');
        expect(tester.getTopLeft(row(seq)).dy, closeTo(readingEdgeTop, 1),
            reason: 'trim or page publication must not move the reading edge');
        final visibleReceiptWait = Stopwatch()..start();
        while (global.receivedNewMessageCountFor(conv) > newest - seq &&
            visibleReceiptWait.elapsed < const Duration(seconds: 15)) {
          await frame(tester);
        }
        expect(global.receivedNewMessageCountFor(conv), newest - seq,
            reason: 'visible receipt for $seq must commit; '
                'rect=${row(seq).evaluate().isEmpty ? 'unmounted' : tester.getRect(row(seq))}, '
                'viewport=$viewport, '
                'trims=$committedTrimSizes, '
                'savedTrimPages=${store.trimPageWrites}, '
                'raw=${global.rawMessageCount(conv)}, '
                'cursor=${model.historyNewerPageCursor?.seq}, '
                'offset=${scroll.offset}, '
                'minimum=${scroll.position.minScrollExtent}');
        await waitForRealIO(tester, () {
          final capsule = find.byWidgetPredicate((widget) =>
              widget is TIMUIKitTongueItem &&
              widget.valueType == MessageListTongueType.showUnread);
          final visible = capsule.hitTestable().evaluate();
          if (newest == seq) return visible.isEmpty;
          if (visible.length == 1) {
            return tester.widget<TIMUIKitTongueItem>(capsule).unreadCount ==
                newest - seq;
          }
          return visible.isEmpty &&
              scroll.offset - scroll.position.minScrollExtent <
                  scroll.position.viewportDimension * 0.5 &&
              !global.memoryWindowMissingNewer(conv);
        }, 'the reading UI must finish its trim transition for message $seq');
        expect(fullyVisible(seq), isTrue);
        expect(tester.getTopLeft(row(seq)).dy, closeTo(readingEdgeTop, 1));
        expectCounter(newest - seq);
      }
      await waitForRealIO(
          tester,
          () =>
              !global.hasDurableHistoryDeferred(conv) &&
              global.isFollowingLatest(conv) &&
              model.hasCaughtUpToLiveLatest,
          'reading all 300 arrivals must resume following latest');
      expectCounter(0);
      expect(fullyVisible(newest), isTrue);
      expect(committedTrimSizes, isNotEmpty,
          reason: 'this scenario must commit a real bounded-window trim');
      expect(
          store.trimPageWrites, greaterThanOrEqualTo(committedTrimSizes.length),
          reason: 'each committed trim must persist its displaced pages');
      expect(peakWindowCount, greaterThan(ChatMessageWindowPolicy.targetSize));
      expect(
          peakWindowCount, lessThanOrEqualTo(ChatMessageWindowPolicy.softMax));
      expect(
          sdk.requests
              .where((request) =>
                  request.type ==
                      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG &&
                  request.seq < newest)
              .map((request) => request.seq)
              .toSet()
              .toList(),
          [for (var seq = 100; seq < newest; seq += 20) seq],
          reason: 'trimming must preserve every adjacent NEWER page cursor');

      // Continue in the same real, already-trimmed list: media restoration,
      // keyboard geometry and another inbound burst must not strand the tail.
      afterFrame = null;
      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      final returningToOldHistory = Stopwatch()..start();
      while (!global.memoryWindowMissingNewer(conv) &&
          returningToOldHistory.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, 1400));
        await frames(tester, 40);
      }
      expect(global.memoryWindowMissingNewer(conv), isTrue,
          reason: 'real older pagination and trim must evict the newer side');
      global.saveScrollBeforeMediaPreview(conv);
      sdk.newest = 405;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 401; seq <= 405 && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'overlap-preview-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          'preview arrivals must persist without moving the history reader');
      expect(admissionError, isNull);
      await waitForRealIO(
          tester,
          () => global.receivedNewMessageCountFor(conv) == 5,
          'the inbound coalescer must publish the five preview arrivals');
      expect(global.receivedNewMessageCountFor(conv), 5);
      global.restoreScrollAfterMediaPreview(conv);
      await waitForRealIO(
          tester,
          () =>
              !global.shouldLockChatScrollForMediaPreview &&
              !global.isRestoringScrollAfterMediaPreview,
          'the actual media viewport restoration must release');
      global.beginKeyboardViewportTransition(conv);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await frames(tester);
      final capsule = find.byWidgetPredicate((widget) =>
          widget is TIMUIKitTongueItem &&
          widget.valueType == MessageListTongueType.showUnread);
      expect(capsule.hitTestable(), findsOneWidget);
      final requestsBeforeReturn = sdk.requests.length;
      sdk.latestPageGate = Completer<void>();
      await tester.tap(capsule.hitTestable());
      await waitForRealIO(
          tester,
          () => sdk.requests.skip(requestsBeforeReturn).any((r) => r.seq <= 0),
          'the visible unread button must start a latest-window read');
      sdk.newest = 410;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 406; seq <= 410 && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'overlap-return-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          'arrivals during the pending button action must persist');
      expect(admissionError, isNull);
      sdk.latestPageGate!.complete();
      await waitForRealIO(
          tester,
          () =>
              !global.isUserScrollToBottomInProgress(conv) &&
              global.rawMessageList(conv)?.first.seq == '410' &&
              (scroll.offset - scroll.position.minScrollExtent).abs() <= 1,
          'trim + media restore + keyboard + arrivals must complete return');
      await frames(tester);
      final latestRow = find.byKey(ValueKey('row-$conv-410'));
      expect(latestRow.hitTestable(), findsOneWidget,
          reason:
              'SDK/model completion alone does not prove the newest row painted');
      final currentViewport = tester.getRect(list);
      final latestRect = tester.getRect(latestRow);
      expect(latestRect.top, greaterThanOrEqualTo(currentViewport.top - 1));
      expect(latestRect.bottom, lessThanOrEqualTo(currentViewport.bottom + 1));
      expect(global.receivedNewMessageCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
      expect(capsule.hitTestable(), findsNothing);
      expect(find.text('取消'), findsNothing);
      debugPrint('CHAT_OVERLAP_LATEST_VISIBLE sdk=${sdk.newest} '
          'raw=${global.rawMessageList(conv)?.first.seq} '
          'rect=$latestRect viewport=$currentViewport '
          'offset=${scroll.offset} min=${scroll.position.minScrollExtent} '
          'trims=${committedTrimSizes.length} unread=0');
    } finally {
      afterFrame = null;
      tester.view.resetViewInsets();
      global.endKeyboardViewportTransition(model.conversationID);
      global.endMediaPreviewOverlay();
      await close(tester);
    }
  });

  testWidgets(
      'a 1200px arrival is counted only after its bottom and preserves page continuity',
      (tester) async {
    try {
      await mount(tester,
          realTongue: true,
          rowHeight: (message) => message?.seq == '101'
              ? 1200
              : message?.elemType == 11
                  ? 24
                  : 64);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      final viewport = tester.getRect(list);
      Finder row(int seq) => find.byKey(ValueKey('row-$conv-$seq'));
      bool fullyVisible(int seq) {
        if (row(seq).evaluate().isEmpty) return false;
        final rect = tester.getRect(row(seq));
        return rect.top >= viewport.top - 1 &&
            rect.bottom <= viewport.bottom + 1;
      }

      void expectCounter(int count) {
        expect(global.receivedNewMessageCountFor(conv), count);
        final capsule = find.byWidgetPredicate((widget) =>
            widget is TIMUIKitTongueItem &&
            widget.valueType == MessageListTongueType.showUnread);
        expect(capsule.hitTestable(), findsOneWidget);
        expect(tester.widget<TIMUIKitTongueItem>(capsule).unreadCount, count);
      }

      Future<void> waitForVisibleReceipt(int seq) async {
        final expected = 171 - seq;
        // A Flutter frame does not complete SQLite's real-thread transaction.
        // Wait without another gesture; keep exact geometry/count assertions.
        await waitForRealIO(tester, () {
          final capsule = find.byWidgetPredicate((widget) =>
              widget is TIMUIKitTongueItem &&
              widget.valueType == MessageListTongueType.showUnread);
          return global.receivedNewMessageCountFor(conv) == expected &&
              capsule.hitTestable().evaluate().length == 1 &&
              tester.widget<TIMUIKitTongueItem>(capsule).unreadCount ==
                  expected;
        }, 'the already-visible tall-row receipt for $seq must commit');
      }

      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      expect(global.isFollowingLatest(conv), isFalse);
      sdk.newest = 171;
      sdk.newerPageGate = Completer<void>();
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= 171 && !stopAdmissions; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'tall-arrival-$seq', ingressSequence: seq);
          }
        } catch (error) {
          admissionError = error;
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle,
          '71 durable admissions including the tall row must finish');
      await pendingAdmissions;
      expect(admissionError, isNull);
      await frames(tester);
      expectCounter(71);

      final reachingOldEdge = Stopwatch()..start();
      while ((!fullyVisible(100) || sdk.gatedNewerCalls == 0) &&
          reachingOldEdge.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester, 5);
      }
      expect(fullyVisible(100), isTrue);
      expect(sdk.gatedNewerCalls, greaterThan(0));
      final anchorTop = tester.getTopLeft(row(100)).dy;
      sdk.newerPageGate!.complete();
      await waitForRealIO(
          tester,
          () => global.rawMessageList(conv)!.any((m) => m.seq == '120'),
          'the page containing the tall row must load');
      await frames(tester);
      expect(fullyVisible(100), isTrue);
      expect(tester.getTopLeft(row(100)).dy, closeTo(anchorTop, 1));
      expectCounter(71);

      await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
      await frames(tester);
      expect(tester.getRect(row(101)).height, 1200);
      expect(tester.getRect(row(101)).top, lessThan(viewport.bottom));
      expect(tester.getRect(row(101)).bottom, greaterThan(viewport.bottom));
      expectCounter(71);

      final readingTallRow = Stopwatch()..start();
      while (tester.getRect(row(101)).bottom > viewport.bottom + 64 &&
          readingTallRow.elapsed < const Duration(seconds: 15)) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expectCounter(71);
      }
      final remaining = tester.getRect(row(101)).bottom - viewport.bottom;
      expect(remaining, inExclusiveRange(0, 65));
      await tester.drag(list, Offset(0, -remaining), touchSlopY: 0);
      await frames(tester);
      expect(tester.getRect(row(101)).bottom, closeTo(viewport.bottom, 1));
      await waitForVisibleReceipt(101);
      expect(tester.getRect(row(101)).bottom, closeTo(viewport.bottom, 1));
      expectCounter(70);

      // Continue into the second SDK page with ordinary one-row gestures.
      for (var seq = 102; seq <= 122; seq++) {
        await tester.drag(list, const Offset(0, -64), touchSlopY: 0);
        await frames(tester);
        expect(fullyVisible(seq), isTrue,
            reason: 'tall-row recovery must still reach adjacent message $seq');
        await waitForVisibleReceipt(seq);
        expect(fullyVisible(seq), isTrue);
        expectCounter(171 - seq);
      }
      expect(
          sdk.requests.any((request) =>
              request.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG &&
              request.seq == 120),
          isTrue);
    } finally {
      await close(tester);
    }
  });

  testWidgets('arrivals during an iOS bottom bounce remain reachable',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await mount(tester);
      final conv = model.conversationID;
      final list = find.byType(CustomScrollView);
      await tester.drag(list, const Offset(0, 1200));
      await frames(tester);
      scroll.jumpTo(scroll.position.minScrollExtent + 50);
      await frames(tester);
      final gesture = await tester.startGesture(tester.getCenter(list));
      await gesture.moveBy(const Offset(0, -160));
      await frame(tester);
      expect(scroll.position.pixels, lessThan(scroll.position.minScrollExtent));
      await gesture.up();
      sdk.newest = 103;
      admissionsIdle = false;
      pendingAdmissions = (() async {
        try {
          for (var seq = 101; seq <= 103; seq++) {
            await global.applyAppRealtimeMessage(_message(conv, seq),
                ingressEventID: 'bounce-$seq', ingressSequence: seq);
          }
        } finally {
          admissionsIdle = true;
        }
      })();
      await waitForRealIO(tester, () => admissionsIdle, 'bounce arrivals');
      await pendingAdmissions;
      await frames(tester, 80);
      final newestVisible = find.text('seq:103').hitTestable().evaluate().isNotEmpty;
      final reminderVisible =
          find.textContaining('showUnread:').hitTestable().evaluate().isNotEmpty;
      expect(newestVisible || reminderVisible, isTrue,
          reason: 'a rebound must either follow the new tip or retain its reminder');
      if (!newestVisible) {
        expect(global.remainingLiveIncomingCountFor(conv), greaterThan(0));
      }
    } finally {
      await close(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final durable in [false, true]) {
    testWidgets('near-bottom rebound keeps new arrivals discoverable '
        '(durable=$durable)', (tester) async {
      try {
        if (!durable) HistoryWindowRepositoryProvider.repository = null;
        await mount(tester);
        final conv = model.conversationID;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
        await frames(tester);
        expect(global.isFollowingLatest(conv), isFalse);
        // Exercise the settled near-edge part of a rebound without pressing
        // the capsule. A geometric near-bottom is not yet a latest-row proof.
        scroll.jumpTo(scroll.position.minScrollExtent + 30);
        await frames(tester);
        expect(global.isFollowingLatest(conv), isFalse);
        sdk.newest = 103;
        admissionsIdle = false;
        pendingAdmissions = (() async {
          try {
            for (var seq = 101; seq <= 103; seq++) {
              await global.applyAppRealtimeMessage(_message(conv, seq),
                  ingressEventID: 'rebound-$seq', ingressSequence: seq);
            }
          } finally {
            admissionsIdle = true;
          }
        })();
        await waitForRealIO(tester, () => admissionsIdle, 'rebound arrivals');
        await pendingAdmissions;
        await frames(tester, 50);
        expect(global.remainingLiveIncomingCountFor(conv), greaterThan(0));
        expect(find.textContaining('showUnread:').hitTestable(), findsOneWidget,
            reason: 'unseen arrivals must remain reachable even near the edge');
        expect(find.text('seq:103').hitTestable(), findsNothing);
      } finally {
        await close(tester);
      }
    });
  }

  for (final scenario in [
    (deep: false, failFirst: false),
    (deep: true, failFirst: false),
    (deep: true, failFirst: true),
  ]) {
    final deepHistory = scenario.deep;
    testWidgets(
        'manual downward scroll loads 95 durable arrivals and confirms latest '
        '(deep=$deepHistory, retry=${scenario.failFirst})', (tester) async {
      try {
        await mount(tester);
        final conv = model.conversationID;
        final list = find.byType(CustomScrollView);
        // In the production reverse list, dragging down reveals older messages.
        await tester.drag(list, const Offset(0, 1200));
        await frames(tester);
        if (deepHistory) {
          await tester.drag(list, const Offset(0, 1800));
          await frames(tester, 60);
          expect(scroll.offset - scroll.position.minScrollExtent,
              greaterThan(scroll.position.viewportDimension * 2));
        }
        expect(
            scroll.offset - scroll.position.minScrollExtent, greaterThan(600));
        expect(global.isFollowingLatest(conv), isFalse);
        final offsetBeforeArrival = scroll.offset;
        final originalIDs =
            global.rawMessageList(conv)!.map((m) => m.msgID).toList();
        final firstVisible = find
            .byWidgetPredicate((widget) =>
                widget is Text && widget.data?.startsWith('seq:') == true)
            .hitTestable();
        expect(firstVisible, findsWidgets);
        final visibleText = tester.widget<Text>(firstVisible.first).data!;
        final visibleTop = tester.getTopLeft(find.text(visibleText)).dy;

        sdk.newest = 195;
        admissionsIdle = false;
        pendingAdmissions = (() async {
          try {
            for (var seq = 101; seq <= 195 && !stopAdmissions; seq++) {
              await global.applyAppRealtimeMessage(_message(conv, seq),
                  ingressEventID: 'arrival-$seq', ingressSequence: seq);
            }
          } catch (error) {
            admissionError = error;
          } finally {
            admissionsIdle = true;
          }
        })();
        await waitForRealIO(tester, () => admissionsIdle,
            '95 durable admissions must settle within 15 real seconds');
        await pendingAdmissions;
        expect(admissionError, isNull);
        await frames(tester);
        expect(global.rawMessageList(conv)!.map((m) => m.msgID), originalIDs);
        expect(scroll.offset, closeTo(offsetBeforeArrival, 1));
        expect(tester.getTopLeft(find.text(visibleText)).dy,
            closeTo(visibleTop, 1));
        expect(global.receivedNewMessageCountFor(conv), 95);
        expect(global.hasDurableHistoryDeferred(conv), isTrue);
        if (deepHistory) {
          // The standalone list still reports notShowLatest at this measured
          // deep offset. Model the legal settled-position transition after
          // admission so the same durable pending state enters awayTwoScreen.
          global.setMessageListPosition(
              conv, HistoryMessagePosition.awayTwoScreen,
              notify: false);
          expect(global.getMessageListPosition(conv),
              HistoryMessagePosition.awayTwoScreen);
        }

        if (scenario.failFirst) {
          sdk.failHistory = true;
          final failureWait = Stopwatch()..start();
          while (sdk.failedHistoryCalls == 0 &&
              failureWait.elapsed < const Duration(seconds: 15)) {
            await tester.drag(list, const Offset(0, -1400));
            await frames(tester, 40);
          }
          expect(sdk.failedHistoryCalls, greaterThan(0));
          await frames(tester, 40);
          expect(global.rawMessageList(conv)!.map((m) => m.msgID), originalIDs);
          expect(model.historyNewerPageCursor?.seq, '100');
          expect(global.receivedNewMessageCountFor(conv), 95);
          expect(global.hasDurableHistoryDeferred(conv), isTrue);
          sdk.failHistory = false;
        }

        // Repeated real drag/overscroll/end notifications must recover the live
        // edge without pressing the unread capsule or calling model restore APIs.
        final returnWait = Stopwatch()..start();
        while (global.hasDurableHistoryDeferred(conv) &&
            returnWait.elapsed < const Duration(seconds: 20)) {
          await tester.drag(list, const Offset(0, -1400));
          await frames(tester, 30);
        }
        final newerRequests = sdk.requests.where((request) =>
            request.type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG);
        expect(newerRequests, isNotEmpty,
            reason:
                'the production scroll handler must enter SDK newer pagination');
        expect(newerRequests.first.seq, 100,
            reason: 'replay starts at the connected history edge');
        expect(
            newerRequests
                .map((request) => request.seq)
                .where((seq) => seq < 195)
                .toSet()
                .toList(),
            [100, 120, 140, 160, 180],
            reason: 'each nearest newer page advances without skipping a gap');
        expect(global.rawMessageList(conv)!.map((m) => m.seq),
            [for (var seq = 195; seq > 0; seq--) '$seq'],
            reason: '95 arrivals must be reached by manual downward scrolling; '
                'SDK=${sdk.requests}; '
                'cursor=${model.historyNewerPageCursor?.seq}; '
                'more=${model.haveMoreLatestData}; '
                'raw=${global.rawMessageCount(conv)}; '
                'offset=${scroll.offset}; '
                'hot=${global.deferredIncomingBufferedCount(conv)}');
        expect(find.text('seq:195').hitTestable(), findsOneWidget);
        expect(global.hasDurableHistoryDeferred(conv), isFalse);
        expect(global.receivedNewMessageCountFor(conv), 0);
        expect(model.hasCaughtUpToLiveLatest, isTrue);
        await frames(tester);
        expect(global.isFollowingLatest(conv), isTrue);
        expect(global.remainingLiveIncomingCountFor(conv), 0);
        expect(find.textContaining('showUnread:').hitTestable(), findsNothing);
        expect(find.textContaining('toLatest:').hitTestable(), findsNothing);
      } finally {
        await close(tester);
      }
    });
  }
}
