import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

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
  Future<void> Function()? afterVisibleAcknowledge;
  String? acknowledgeTriggerID;
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
        isCurrent: isCurrent);
    if (receipt.acknowledgedMessageIDs.contains(acknowledgeTriggerID)) {
      final callback = afterVisibleAcknowledge;
      afterVisibleAcknowledge = null;
      await callback?.call();
    }
    return receipt;
  }

  @override
  Future<void> savePages(List<HistoryWindowPage> pages) async {
    await super.savePages(pages);
    if (pages.any((page) => page.pageKey.startsWith('window:'))) {
      trimPageWrites++;
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
  Future<void> Function()? duringLatestRead;
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
    if (!newer && boundary <= 0) await duringLatestRead?.call();
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
  late ValueNotifier<double> lateRowHeight;
  Future<void>? pendingAdmissions;
  var admissionsIdle = true;
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
    global.bindHistoryLiveWindowFreeze(
      conversationID: conv,
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    pendingAdmissions = null;
    admissionsIdle = true;
    afterFrame = null;
    lateRowHeight = ValueNotifier<double>(64);
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
      WidgetTester tester, bool Function() ready, String reason) async {
    // SQLite runs in real time; a frame count only budgets FakeAsync time and
    // expires too early when other Flutter test isolates compete for the DB.
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
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
              itemBuilder: (_, message) => ValueListenableBuilder<double>(
                valueListenable: lateRowHeight,
                builder: (_, height, __) => SizedBox(
                  key: ValueKey('row-${message?.msgID}'),
                  height: message?.seq == '103'
                      ? height
                      : rowHeight?.call(message) ??
                          (message?.elemType == 11 ? 24 : 64),
                  child: Text('seq:${message?.seq}'),
                ),
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
    lateRowHeight.dispose();
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

  testWidgets('connected reading budget reserves one page before idle trim',
      (tester) async {
    try {
      final conv = model.conversationID;
      global.bindHistoryLiveWindowFreeze(
        conversationID: conv,
        freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
        canAppendIncoming: model.canAppendIncomingToReadingWindow,
        didAppendIncoming: model.didAppendIncomingToReadingWindow,
      );
      global.setFollowingLatest(conv, false);
      global.setMessageListPosition(
          conv, HistoryMessagePosition.awayTwoScreen, notify: false);
      expect(model.canAppendIncomingToReadingWindow(), isTrue);

      final rows = List.generate(2959, (index) => _message(conv, 2959 - index));
      global.setMessageList(conv, rows,
          replace: true, applyMemoryWindow: false);
      expect(global.historyWindowNeedsTrim(conv), isFalse);
      expect(global.historyWindowPaginationBlocked(conv), isFalse);

      global.setMessageList(conv, <V2TimMessage>[_message(conv, 2960)],
          needResetNewMessageCount: false);
      expect(global.rawMessageCount(conv), 2960);
      expect(global.historyWindowNeedsTrim(conv), isTrue);
      expect(global.historyWindowPaginationBlocked(conv), isTrue);
    } finally {
      await close(tester);
    }
  });


  for (final dragging in [false, true]) {
    testWidgets('connected live append preserves painted reading row (drag=$dragging)',
        (tester) async {
      try {
        await mount(tester, rowHeight: (row) =>
            row?.elemType == 11 ? 24 : 48.0 + (int.tryParse(row?.seq ?? '') ?? 0) % 4 * 12);
        final conv = model.conversationID;
        scroll.jumpTo(1200);
        global.setFollowingLatest(conv, false);
        await frames(tester, 5);
        final target = find.text('seq:80');
        expect(target, findsOneWidget);
        final gesture = dragging
            ? await tester.startGesture(tester.getCenter(target)) : null;
        if (gesture != null) {
          await gesture.moveBy(const Offset(0, -20));
          await frame(tester);
        }
        final top = tester.getTopLeft(target).dy;
        final pin = global.pinToBottomRequestSeq;
        afterFrame = () => expect(tester.getTopLeft(target).dy, closeTo(top, 1),
            reason: 'every painted frame must preserve the reading row');
        for (var seq = 101; seq <= 112; seq++) {
          await global.applyAppRealtimeMessage(_message(conv, seq));
        }
        await frames(tester, 12);
        expect(global.rawMessageCount(conv), 112);
        expect(global.deferredIncomingBufferedCount(conv), 0);
        expect(global.receivedNewMessageCountFor(conv), 12);
        expect(global.remainingLiveIncomingCountFor(conv), 12);
        expect(model.historyNewerPageCursor?.seq, '112');
        expect(model.isVisibleOnReadingTimeline(_message(conv, 112)), isTrue);
        expect(global.isFollowingLatest(conv), isFalse);
        expect(global.pinToBottomRequestSeq, pin);
        await global.applyAppRealtimeMessage(_message(conv, 112));
        await frames(tester, 5);
        expect(global.receivedNewMessageCountFor(conv), 12);
        afterFrame = null;
        await gesture?.cancel();
        await frames(tester, 3);
        for (var step = 0; step < 10 && !global.isFollowingLatest(conv); step++) {
          scroll.jumpTo(scroll.position.minScrollExtent);
          await frames(tester, 5);
        }
        await frames(tester, 15);
        expect(global.remainingLiveIncomingCountFor(conv), 0);
        expect(global.receivedNewMessageCountFor(conv), 0);
        expect(global.isFollowingLatest(conv), isTrue);
        await global.applyAppRealtimeMessage(_message(conv, 113));
        await frames(tester, 8);
        expect(find.byKey(ValueKey('row-$conv-113')).hitTestable(),
            findsOneWidget,
            reason: 'a new arrival after manual restoration stays at the live edge');
        expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
      } finally {
        afterFrame = null;
        await close(tester);
      }
    });
  }


  testWidgets('300 live arrivals remain connected without moving the reading row',
      (tester) async {
    try {
      await mount(tester);
      final conv = model.conversationID;
      scroll.jumpTo(1200);
      global.setFollowingLatest(conv, false);
      await frames(tester, 5);
      final target = find.text('seq:80');
      final top = tester.getTopLeft(target).dy;
      final pin = global.pinToBottomRequestSeq;
      sdk.newest = 400;
      var admitted = false;
      admissionsIdle = false;
      final admissions = (() async {
        for (var seq = 101; seq <= 400; seq++) {
          await global.applyAppRealtimeMessage(_message(conv, seq));
        }
      })().whenComplete(() {
        admitted = true;
        admissionsIdle = true;
      });
      pendingAdmissions = admissions;
      await waitForRealIO(tester, () => admitted, 'bounded burst admission');
      await admissions;
      await frames(tester, 15);
      expect(tester.getTopLeft(target).dy, closeTo(top, 1));
      expect(global.rawMessageCount(conv), 400);
      expect(global.isFollowingLatest(conv), isFalse);
      expect(global.pinToBottomRequestSeq, pin);
      expect(global.remainingLiveIncomingCountFor(conv), 300);
      expect(global.memoryWindowMissingNewer(conv), isFalse);
    } finally {
      afterFrame = null;
      await close(tester);
    }
  });

  testWidgets('disconnected history keeps arrivals outside the loaded window',
      (tester) async {
    try {
      await mount(tester);
      final conv = model.conversationID;
      scroll.jumpTo(1200);
      global.setFollowingLatest(conv, false);
      model.haveMoreLatestData = true;
      sdk.newest = 1000;
      await frames(tester, 3);
      final pin = global.pinToBottomRequestSeq;
      var admitted = false;
      final admission = global.applyAppRealtimeMessage(_message(conv, 1000))
          .whenComplete(() => admitted = true);
      await waitForRealIO(tester, () => admitted, 'durable gap admission');
      await admission;
      await frames(tester, 5);
      expect(global.rawMessageList(conv)!.any((m) => m.seq == '1000'), isFalse);
      expect(global.receivedNewMessageCountFor(conv), 1);
      expect(global.memoryWindowMissingNewer(conv), isTrue);
      expect(global.pinToBottomRequestSeq, pin);
    } finally {
      await close(tester);
    }
  });

  testWidgets('latest edge follows appended messages without an unread capsule',
      (tester) async {
    try {
      await mount(tester);
      final conv = model.conversationID;
      for (var seq = 101; seq <= 104; seq++) {
        await global.applyAppRealtimeMessage(_message(conv, seq));
      }
      await frames(tester, 40);
      expect(global.rawMessageList(conv)!.first.seq, '104');
      expect(global.isFollowingLatest(conv), isTrue);
      expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
      expect(global.remainingLiveIncomingCountFor(conv), 0);
    } finally {
      await close(tester);
    }
  });
}
