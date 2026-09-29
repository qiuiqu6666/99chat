import 'package:tencent_cloud_chat_demo/utils/group_tips_message_helper.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_tips_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_tips_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_info.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
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
      ..elemType = seq == 101 || seq == 104 ? 9 : 1
      ..groupTipsElem = seq == 101 || seq == 104
          ? V2TimGroupTipsElem(
              groupID: conversationID,
              type: GroupTipsElemType.V2TIM_GROUP_TIPS_TYPE_SET_ADMIN,
              opMember: V2TimGroupMemberInfo(userID: 'operator'),
              memberList: [V2TimGroupMemberInfo(userID: 'member')])
          : null
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
  bool onlyHidden = false;
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
      for (var seq = newest; seq > 0; seq--)
        if (!onlyHidden || seq == 101) _message(groupID!, seq)
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
    // SQL runs outside FakeAsync. Keep real and virtual frame time aligned so
    // parallel test isolates cannot burn the production ACK deadline while a
    // real SQLite transaction is still waiting for CPU time.
    await tester.runAsync(() =>
        Future<void>.delayed(Duration(milliseconds: milliseconds.clamp(1, 20))));
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
      int expectedRawCount = 100,
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
    expect(global.rawMessageCount(conv), expectedRawCount);
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

  void installHiddenPolicy({bool permanent = true}) {
    global.lifeCycle = ChatLifeCycle(
      messageShouldMount: (message) =>
          !GroupTipsMessageHelper.isImNativeAdminRoleTip(message),
      messagePermanentlyHidden:
          permanent ? GroupTipsMessageHelper.isImNativeAdminRoleTip : null,
    );
  }

  Future<void> receive(WidgetTester tester, int sequence) async {
    final conv = model.conversationID;
    sdk.newest = sequence;
    admissionsIdle = false;
    pendingAdmissions = global
        .applyAppRealtimeMessage(_message(conv, sequence),
            ingressEventID: 'arrival-$sequence', ingressSequence: sequence)
        .then<void>((_) {})
        .whenComplete(() => admissionsIdle = true);
    await waitForRealIO(tester, () => admissionsIdle, 'arrival persists');
    await pendingAdmissions;
    await frames(tester);
  }

  Future<void> readHistory(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
    await frames(tester);
    global.markMemoryWindowMissingNewer(model.conversationID);
  }

  Future<void> returnToLatest(WidgetTester tester) async {
    var done = false;
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    final returning = state
        .scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => done = true);
    await waitForRealIO(tester, () => done, 'return completes');
    await returning;
    await frames(tester);
  }

  testWidgets(
      'hidden administrator signal retains raw history but no unread reminder',
      (tester) async {
    try {
      installHiddenPolicy();
      await mount(tester);
      final conv = model.conversationID;
      await readHistory(tester);
      await receive(tester, 101);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(find.text('showUnread:1'), findsNothing);
      await returnToLatest(tester);
      expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
      expect(global.rawMessageList(conv)!.first.seq, '101');
      expect(global.newestDisplayableConfirmedMessage(conv)!.seq, '100');
      expect(
          find.byKey(ValueKey('row-$conv-100')).hitTestable(), findsOneWidget);
      expect(find.byKey(ValueKey('row-$conv-101')), findsNothing);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
      await returnToLatest(tester);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
    } finally {
      await close(tester);
    }
  });

  testWidgets('mixed visible and hidden arrivals count only visible messages',
      (tester) async {
    try {
      installHiddenPolicy();
      await mount(tester);
      final conv = model.conversationID;
      await readHistory(tester);
      await receive(tester, 101);
      await receive(tester, 102);
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
      await tester.tap(find.text('showUnread:1'));
      await waitForRealIO(tester,
          () => !global.isUserScrollToBottomInProgress(conv), 'return ends');
      await frames(tester);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
      expect(
          global.rawMessageList(conv)!.any((row) => row.seq == '101'), isTrue);
      expect(
          find.byKey(ValueKey('row-$conv-102')).hitTestable(), findsOneWidget);
      // Later ordinary messages still create their own reminder.
      await readHistory(tester);
      await receive(tester, 103);
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      await returnToLatest(tester);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
    } finally {
      await close(tester);
    }
  });

  testWidgets('installing permanent policy repairs an existing hidden identity',
      (tester) async {
    try {
      installHiddenPolicy(permanent: false);
      await mount(tester);
      final conv = model.conversationID;
      await readHistory(tester);
      await receive(tester, 101);
      await receive(tester, 102);
      expect(global.remainingLiveIncomingCountFor(conv), 2);
      installHiddenPolicy();
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      await returnToLatest(tester);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(
          global.rawMessageList(conv)!.any((row) => row.seq == '101'), isTrue);
    } finally {
      await close(tester);
    }
  });

  testWidgets('temporarily unmounted row still requires its own visible proof',
      (tester) async {
    try {
      installHiddenPolicy(permanent: false);
      await mount(tester);
      final conv = model.conversationID;
      await readHistory(tester);
      await receive(tester, 101);
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      await returnToLatest(tester);
      expect(global.remainingLiveIncomingCountFor(conv), 1);
      expect(global.hasDurableHistoryDeferred(conv), isTrue);
      expect(global.isFollowingLatest(conv), isFalse);
    } finally {
      await close(tester);
    }
  });

  testWidgets('latest hidden boundary settles mixed visible arrivals',
      (tester) async {
    try {
      installHiddenPolicy();
      await mount(tester);
      final conv = model.conversationID;
      await readHistory(tester);
      await receive(tester, 102);
      await receive(tester, 103);
      await receive(tester, 104);
      expect(global.remainingLiveIncomingCountFor(conv), 2);
      await returnToLatest(tester);
      expect(global.rawMessageList(conv)!.first.seq, '104');
      expect(global.newestDisplayableConfirmedMessage(conv)!.seq, '103');
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
      'all-hidden loaded history settles without a fabricated visible row',
      (tester) async {
    try {
      installHiddenPolicy();
      final conv = model.conversationID;
      global.setMessageList(conv, [], replace: true, applyMemoryWindow: false);
      sdk.onlyHidden = true;
      await mount(tester, expectedRawCount: 0);
      global.markMemoryWindowMissingNewer(conv);
      await receive(tester, 101);
      await returnToLatest(tester);
      expect(global.rawMessageList(conv)!.single.seq, '101');
      expect(global.newestDisplayableConfirmedMessage(conv), isNull);
      expect(global.hasOnlyPermanentlyHiddenConfirmedMessages(conv), isTrue);
      expect(global.getMessageList(conv), isEmpty);
      expect(global.remainingLiveIncomingCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
    } finally {
      await close(tester);
    }
  });
}
