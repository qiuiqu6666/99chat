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

  // Temporary audit: real SQLite durable admission + production tongue selector.
  // No unread counter or remaining-ID fixture injection.
  Future<void> beginVisit(WidgetTester tester) async {
    var done = false;
    Object? error;
    final pending = global.beginHistoryUnreadVisit(getConv()).then<void>(
      (_) => done = true,
      onError: (Object failure, StackTrace _) { error = failure; done = true; },
    );
    for (var attempt = 0; attempt < 1500 && !done; attempt++) {
      await frame(tester);
    }
    expect(done, isTrue, reason: 'visit baseline must finish under frame pumping');
    await pending;
    expect(error, isNull);
  }

  Future<void> assertArrivalReminder(WidgetTester tester) async {
    print('AUDIT receive completed: received=${global.receivedNewMessageCountFor(getConv())}, remaining=${global.remainingLiveIncomingCountFor(getConv())}');
    print('AUDIT SQL read starting');
    HistoryWindowDeferredState? sql;
    Object? error;
    var done = false;
    final pending = store.deferredState(global.historyWindowScopeFor(getConv())!)
        .then<void>((value) { sql = value; done = true; },
            onError: (Object failure, StackTrace _) { error = failure; done = true; });
    for (var attempt = 0; attempt < 1500 && !done; attempt++) {
      await frame(tester);
    }
    expect(done, isTrue, reason: 'SQL read must complete under frame pumping');
    await pending;
    expect(error, isNull);
    print('AUDIT SQL read completed: received=${sql!.receivedCount}');
    expect(sql!.receivedCount, 1, reason: 'real durable producer persisted arrival');
    expect(global.receivedNewMessageCountFor(getConv()), 1,
        reason: 'legacy/scalar count confirms arrival in this initialized visit');
    expect(global.deferredIncomingBufferedCount(getConv()), 1);
    expect(global.remainingLiveIncomingCountFor(getConv()), 1,
        reason: 'production capsule now uses the identity ledger, which must agree');
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
  }

  uiTest('AUDIT durable newer-gap arrival must enter capsule identity ledger',
      (tester) async {
    await mount(tester);
    await beginVisit(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    await assertArrivalReminder(tester);
  });

  uiTest('AUDIT background arrival while reading must enter capsule identity ledger',
      (tester) async {
    await mount(tester);
    await beginVisit(tester);
    await away(tester);
    global.setChatAppLifecycleState(AppLifecycleState.paused);
    await receive(tester, 101, 1);
    global.setChatAppLifecycleState(AppLifecycleState.resumed);
    await frame(tester, 300);
    await assertArrivalReminder(tester);
  });

  uiTest('AUDIT foreground in-memory arrival control updates capsule ledger',
      (tester) async {
    await mount(tester);
    await beginVisit(tester);
    await away(tester);
    await receive(tester, 101, 1);
    expect(global.remainingLiveIncomingCountFor(getConv()), 1);
    expect(find.text('showUnread:1').hitTestable(), findsOneWidget);
  });
}
