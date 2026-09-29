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
        .runAsync(() => Future<void>.delayed(Duration(milliseconds: milliseconds)));
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

  for(final durable in [false,true]) {
    testWidgets('audit arrivals during held toward-latest drag durable=$durable',(tester) async {
      TestGesture? gesture;
      var pendingCount=0;
      try {
        if(!durable) HistoryWindowRepositoryProvider.repository=null;
        final conv=model.conversationID;
        global.bindHistoryLiveWindowFreeze(conversationID:conv,freezeIfNeeded:model.freezeVisibleHistoryWindowIfNeeded);
        await mount(tester,realTongue:true,rowHeight:(message) {
          final seq=int.tryParse(message?.seq??'')??0;
          return seq>100 && seq%3==0?180:64;
        });
        final list=find.byType(CustomScrollView);
        await tester.drag(list,const Offset(0,512),touchSlopY:0);
        await frames(tester,8);
        expect(global.isFollowingLatest(conv),isFalse);
        var seq=100;
        gesture=await tester.startGesture(const Offset(400,550));
        await gesture.moveBy(const Offset(0,-20));
        await frame(tester,16);
        var stalled=0;
        var followedAtEnd=false;
        var largestRetreat=0.0;
        var tailNeverReached=true;
        for(var step=0;step<60;step++) {
          if(step%4==0 && step<48) {
            sdk.newest=++seq;
            final incoming=seq;
            pendingCount++;
            admissionsIdle=false;
            pendingAdmissions=(pendingAdmissions??Future<void>.value()).then((_)async {
              try {
                await global.applyAppRealtimeMessage(_message(conv,incoming),ingressEventID:'during-$incoming',ingressSequence:incoming);
              } catch(e) {admissionError=e;} finally {pendingCount--;admissionsIdle=pendingCount==0;}
            });
          }
          final before=scroll.offset;
          await gesture.moveBy(const Offset(0,-48));
          await frame(tester,16);
          final distance=scroll.offset-scroll.position.minScrollExtent;
          if(global.isFollowingLatest(conv) && distance<=4) followedAtEnd=true;
          if(followedAtEnd && distance>largestRetreat) largestRetreat=distance;
          if(step>1 && distance>48 && (scroll.offset-before).abs()<1) stalled++;
          if(distance<=4 && step>=48) tailNeverReached=false;
          print('DURING durable=$durable step=$step distance=${distance.toStringAsFixed(1)} delta=${(scroll.offset-before).toStringAsFixed(1)} min=${scroll.position.minScrollExtent.toStringAsFixed(1)} new=$seq raw=${global.rawMessageCount(conv)} received=${global.receivedNewMessageCountFor(conv)} deferred=${global.deferredIncomingBufferedCount(conv)} durablePending=${global.hasDurableHistoryDeferred(conv)} recent=${model.didAttachBufferedTowardLatestRecently} holding=${global.isChatListUserScrolling} following=${global.isFollowingLatest(conv)}');
        }
        await gesture.cancel();
        gesture=null;
        await waitForRealIO(tester,()=>admissionsIdle,'continuous admission completes');
        await pendingAdmissions;
        await frames(tester,50);
        print('DURING_FINAL durable=$durable neverReached=$tailNeverReached stalled=$stalled count=${global.receivedNewMessageCountFor(conv)} live=${global.remainingLiveIncomingCountFor(conv)} distance=${scroll.offset-scroll.position.minScrollExtent} following=${global.isFollowingLatest(conv)} latest=${find.text("seq:$seq").hitTestable().evaluate().length}');
        expect(admissionError,isNull);
        expect(largestRetreat,lessThanOrEqualTo(4),reason:"once truly following at the edge, continued toward-latest drag must follow newly arriving rows before paint");
        expect(tailNeverReached,isFalse,reason:'finger faster than arrival growth must reach current latest edge');
        expect(global.receivedNewMessageCountFor(conv),0,reason:'no additional swipe after the final incoming row');
        expect(global.isFollowingLatest(conv),isTrue);
      } finally {await gesture?.cancel();await close(tester);}
    });
  }
}