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

V2TimMessage _message(String conversationID, int seq) =>
    V2TimMessage.fromJson({
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

class _PagingSdk extends MessageService {
  int newest = 100;

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
    final newer =
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    final all = [
      for (var seq = newest; seq > 0; seq--) _message(groupID!, seq),
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
        isFinished: candidates.length <= count,
        messageList: rows,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

// Only the external read-report side effect is suppressed. Loading, cursor
// updates, durable admission, publication and visible-latest proof are real.
class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead({
    bool notify = true,
    bool force = false,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  late _PagingSdk sdk;
  late TUIChatGlobalModel global;
  late _ReadingModel model;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('chat-visible-incoming-');
    store = HistoryWindowStore(
      debugDatabasePath: '${directory.path}/history.db',
    );
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
      domainGeneration: 1,
    );
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
        isUseDraft: false,
      )
      ..suppressReadReporting = true
      ..haveMoreData = false
      ..haveMoreLatestData = false;
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(
      CurrentConversation(conv, ConvType.group),
      notify: false,
    );
    global.setMessageList(
      conv,
      List.generate(100, (index) => _message(conv, 100 - index)),
      replace: true,
      applyMemoryWindow: false,
    );
    global.markInitialHistoryLoaded(conv);
    scroll = AutoScrollController();
    global.bindHistoryLiveWindowFreeze(
      conversationID: conv,
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
  });

  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final handler = FlutterError.onError;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = handler;
  }

  Future<void> frames(WidgetTester tester, [int count = 25]) async {
    for (var i = 0; i < count; i++) {
      await frame(tester);
    }
  }

  Future<void> waitForRealIO(
    WidgetTester tester,
    bool Function() ready,
    String reason,
  ) async {
    // SQLite runs in real time; a frame count only budgets FakeAsync time and
    // expires too early when other Flutter test isolates compete for the DB.
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
      await frame(tester);
    }
    expect(ready(), isTrue, reason: reason);
  }

  Future<void> mount(WidgetTester tester, {double probeInset = 0}) async {
    final conv = model.conversationID;
    final conversation = V2TimConversation(
      conversationID: 'group_$conv',
      groupID: conv,
      type: 2,
      unreadCount: 0,
      lastMessage: _message(conv, 100),
    );
    final handler = FlutterError.onError;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: EdgeInsets.only(bottom: probeInset)),
            child: child!,
          ),
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Padding(
              padding: EdgeInsets.only(bottom: probeInset),
              child: TIMUIKitHistoryMessageListSelector(
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
                      lastMsg: message,
                    );
                  },
                  itemBuilder: (_, message) => SizedBox(
                    key: ValueKey('row-${message?.msgID}'),
                    height: message?.elemType == 11 ? 24 : 64,
                    child: Text('seq:${message?.seq}'),
                  ),
                  tongueItemBuilder: (tap, type, count) => TextButton(
                    onPressed: tap,
                    child: Text('${type.name}:$count'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    FlutterError.onError = handler;
    await frames(tester);
    expect(scroll.hasClients, isTrue);
    expect(global.rawMessageCount(conv), 100);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    global.dismissAllContextMenuOverlays();
    global.clearActiveChatScrollController(
      conversationID: model.conversationID,
    );
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

  Future<void> stageIncoming(WidgetTester tester) async {
    final conv = model.conversationID;
    global.setFollowingLatest(conv, false, notify: false);
    scroll.jumpTo(1000);
    await frames(tester);
    await tester.runAsync(() async {
      await global.applyAppRealtimeMessage(_message(conv, 101));
      await global.applyAppRealtimeMessage(_message(conv, 102));
    });
    await frames(tester);
    expect(global.remainingLiveIncomingCountFor(conv), 2);
    final connectedRows = global.rawMessageList(conv)!
        .where((message) =>
            message.msgID == '$conv-101' || message.msgID == '$conv-102')
        .length;
    if (connectedRows < 2) {
      expect(
        model.revealBufferedIncomingTowardLatest(limit: 8, skipCooldown: true),
        isTrue,
      );
    } else {
      expect(connectedRows, 2,
          reason: 'a connected live tail appends without a reveal step');
    }
    await frames(tester);
    expect(
      global.remainingLiveIncomingCountFor(conv),
      2,
      reason: 'prefetched rows below the viewport stay unseen',
    );
  }

  void expectIncomingRowVisible(WidgetTester tester) {
    final row = find.byKey(ValueKey('row-${model.conversationID}-101'));
    expect(row, findsOneWidget);
    final rect = tester.getRect(row);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(scroll.position.viewportDimension));
  }

  for (final inset in [0.0, 200.0, 320.0]) {
    testWidgets(
      'visible incoming identities use the laid-out viewport, inset=$inset',
      (tester) async {
        try {
          await mount(tester, probeInset: inset);
          await stageIncoming(tester);
          scroll.jumpTo(scroll.position.minScrollExtent + 20);
          await frames(tester, 4);
          expectIncomingRowVisible(tester);
          expect(
            global
                .remainingLiveIncomingIdsFor(model.conversationID)
                .contains('${model.conversationID}-101'),
            isFalse,
          );
          expect(
            global.isFollowingLatest(model.conversationID),
            isFalse,
            reason: 'this verifies visible rows, not whole-ledger bottom settlement',
          );
        } finally {
          await close(tester);
        }
      },
    );
  }

  testWidgets('dialog-covered rows stay unseen and resume sampling after pop', (
    tester,
  ) async {
    try {
      await mount(tester);
      await stageIncoming(tester);
      final context = tester.element(find.byType(CustomScrollView));
      final navigator = Navigator.of(context);
      unawaited(
        showGeneralDialog<void>(
          context: context,
          transitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) =>
              const SizedBox.expand(child: ColoredBox(color: Colors.white)),
        ),
      );
      await frames(tester, 3);
      expect(ModalRoute.of(context)?.isCurrent, isFalse);
      scroll.jumpTo(scroll.position.minScrollExtent + 20);
      await frames(tester, 4);
      expectIncomingRowVisible(tester);
      expect(global.remainingLiveIncomingCountFor(model.conversationID), 2);
      final offset = scroll.offset;
      navigator.pop();
      await frames(tester, 8);
      expect(scroll.offset, closeTo(offset, .01));
      expect(
        global.remainingLiveIncomingCountFor(model.conversationID),
        1,
        reason: 'uncovering must sample without an extra user drag',
      );
      scroll.jumpTo(scroll.position.minScrollExtent);
      await frames(tester, 8);
      expect(global.remainingLiveIncomingCountFor(model.conversationID), 0);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'context menu protects incoming identities during underlying movement',
    (tester) async {
      try {
        await mount(tester);
        await stageIncoming(tester);
        final conv = model.conversationID;
        global.beginMessageContextMenuOverlay(conversationID: conv);
        await frames(tester, 3);
        scroll.jumpTo(scroll.position.minScrollExtent + 20);
        await frames(tester, 4);
        expectIncomingRowVisible(tester);
        expect(global.remainingLiveIncomingCountFor(conv), 2);
        global.dismissAllContextMenuOverlays();
        await frames(tester, 10);
        expect(global.remainingLiveIncomingCountFor(conv), 1);
        scroll.jumpTo(scroll.position.minScrollExtent);
        await frames(tester, 8);
        expect(global.remainingLiveIncomingCountFor(conv), 0);
      } finally {
        await close(tester);
      }
    },
  );
}
