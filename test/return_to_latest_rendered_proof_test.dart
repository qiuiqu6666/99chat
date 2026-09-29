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
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/TIMUIKitTongue/tim_uikit_chat_history_message_list_tongue_container.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';

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
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {
    readReports++;
  }
}

class _VisibilityProofStore extends HistoryWindowStore {
  _VisibilityProofStore({required super.debugDatabasePath});
  Future<void> Function()? beforeVisibleAcknowledgement;
  Future<void> Function()? beforeDeferredRead;

  @override
  Future<HistoryWindowDeferredState> deferredState(HistoryWindowScope scope) async {
    final before = beforeDeferredRead;
    beforeDeferredRead = null;
    await before?.call();
    return super.deferredState(scope);
  }

  @override
  Future<HistoryWindowVisibleReceipt> acknowledgeVisibleDeferred({
    required HistoryWindowScope scope,
    required List<String> messageIDs,
    required int afterIngressSequence,
    bool Function()? isCurrent,
  }) async {
    final before = beforeVisibleAcknowledgement;
    beforeVisibleAcknowledgement = null;
    await before?.call();
    return super.acknowledgeVisibleDeferred(
      scope: scope,
      messageIDs: messageIDs,
      afterIngressSequence: afterIngressSequence,
      isCurrent: isCurrent,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _VisibilityProofStore store;
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
    directory = await Directory.systemTemp.createTemp('rendered-tongue-');
    store = _VisibilityProofStore(
        debugDatabasePath: '${directory.path}/history.db');
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

  late ValueNotifier<int?> projectionLimit;
  late ValueNotifier<double> newestTranslation;
  late ValueNotifier<bool> visible;
  final viewportKey = GlobalKey();
  final rowKeys = <String, GlobalKey>{};
  List<V2TimMessage> displayed = [];
  var holdVisibilityNotification = false;

  bool verifyLatestVisible() {
    if (displayed.isEmpty) return false;
    final viewport = viewportKey.currentContext?.findRenderObject();
    final row =
        rowKeys[displayed.first.msgID]?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        row is! RenderBox ||
        !viewport.attached ||
        !row.attached ||
        !viewport.hasSize ||
        !row.hasSize) {
      return false;
    }
    final edge =
        row.localToGlobal(Offset(0, row.size.height), ancestor: viewport).dy;
    return edge >= -4 && edge <= viewport.size.height + 4;
  }

  Future<void> mount(WidgetTester tester) async {
    projectionLimit = ValueNotifier<int?>(null);
    newestTranslation = ValueNotifier(0.0);
    visible = ValueNotifier(false);
    holdVisibilityNotification = false;
    final handler = FlutterError.onError;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
        ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: AnimatedBuilder(
        animation:
            Listenable.merge([global, projectionLimit, newestTranslation]),
        builder: (_, __) {
          final limit = projectionLimit.value;
          displayed = (global.rawMessageList(getConv()) ?? <V2TimMessage>[])
              .where((row) => limit == null || int.parse(row.seq!) <= limit)
              .toList();
          for (final row in displayed) {
            rowKeys.putIfAbsent(row.msgID!, GlobalKey.new);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final next = verifyLatestVisible();
            if (!holdVisibilityNotification && visible.value != next) {
              visible.value = next;
            }
          });
          return Stack(key: viewportKey, children: [
            ListView.builder(
              key: const Key('history'),
              controller: scroll,
              reverse: true,
              itemExtent: 60,
              itemCount: displayed.length,
              itemBuilder: (_, index) {
                final row = displayed[index];
                return Transform.translate(
                  offset: Offset(0, index == 0 ? newestTranslation.value : 0),
                  child: SizedBox(
                      key: rowKeys[row.msgID],
                      height: 60,
                      child: Text('row:${row.seq}')),
                );
              },
            ),
            TIMUIKitHistoryMessageListTongueContainer(
              messageList: displayed,
              conversation: V2TimConversation(
                  conversationID: 'group_${getConv()}',
                  groupID: getConv(),
                  type: 2,
                  unreadCount: 0),
              scrollToIndexBySeq: (_) async => false,
              scrollToFirstUnread: (_) async => true,
              scrollController: scroll,
              model: model,
              latestMessageVisible: visible,
              verifyLatestMessageVisible: verifyLatestVisible,
              tongueItemBuilder: (tap, type, count) => TextButton(
                  onPressed: tap, child: Text('${type.name}:$count')),
            ),
            if (global.isMessageContextMenuOverlayOpen)
              const Positioned.fill(
                child: ColoredBox(
                    color: Colors.black54, child: Text('message menu overlay')),
              ),
          ]);
        },
      ))),
    ));
    FlutterError.onError = handler;
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
      if (n >= 119 && !global.isUserScrollToBottomInProgress(getConv())) break;
    }
    expect(global.isUserScrollToBottomInProgress(getConv()), isFalse,
        reason: 'latest-window return and durable ACK must finish');
    await frame(tester);
    await frame(tester, 200);
  }

  void uiTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        global.dismissAllContextMenuOverlays();
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

  uiTest('ordinary return waits for an existing older-page request to finish',
      (tester) async {
    await mount(tester);
    await away(tester);
    model.haveMoreData = true;
    sdk.code = 500;
    final release = Completer<void>();
    sdk.duringRead = () => release.future;
    final history = model.loadChatRecord(
        count: 20, lastMsg: row(1), lastMsgID: row(1).msgID, lastMsgSeq: 1);
    try {
      for (var n = 0; n < 500 && sdk.calls == 0; n++) {
        await frame(tester, 1);
      }
      expect(sdk.calls, 1);
      expect(model.isLoadingChatHistory, isTrue);
      final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      var done = false;
      final returning = state.scrollToLatestAndDismissUnreadCapsule()
          .whenComplete(() => done = true);
      for (var n = 0; n < 100; n++) {
        await frame(tester, 16);
      }
      expect(done, isFalse,
          reason: 'an already running page request is still pending, not failed');
      expect(find.byKey(const ValueKey('return-latest-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
      release.complete();
      await settleReturn(tester);
      await history;
      await returning;
      expect(global.isFollowingLatest(getConv()), isTrue);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
    } finally {
      if (!release.isCompleted) release.complete();
      await settleReturn(tester);
      await history;
    }
  });

  uiTest('ordinary return waits for the newest row to join the painted list',
      (tester) async {
    await mount(tester);
    await away(tester);
    projectionLimit.value = 99;
    await frame(tester);
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var done = false;
    final returning = state.scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => done = true);
    for (var n = 0; n < 60 && scroll.offset > 1; n++) {
      await frame(tester, 16);
    }
    for (var n = 0; n < 20; n++) {
      await frame(tester, 16);
    }
    expect(scroll.offset, closeTo(0, 1));
    expect(done, isFalse,
        reason: 'a temporary old projection must not end the return as failed');
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
    projectionLimit.value = null;
    await settleReturn(tester);
    await returning;
    expect(find.text('row:100'), findsOneWidget);
    expect(global.isFollowingLatest(getConv()), isTrue);
    expect(model.readReports, greaterThan(0));
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
    expect(sdk.calls, 0, reason: 'a connected loaded window needs no SDK reload');
  });

  uiTest('one tap retries visible proof after unrelated history revision changes',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 7);
    sdk.newest = List.generate(50, (i) => row(107 - i));
    var changed = false;
    store.beforeVisibleAcknowledgement = () async {
      changed = true;
      final current = global.rawMessageList(getConv())!;
      global.setMessageList(getConv(), current.take(current.length - 1).toList(),
          replace: true, applyMemoryWindow: false);
    };
    await tester.tap(find.text('showUnread:7'));
    await settleReturn(tester);
    expect(changed, isTrue);
    expect(verifyLatestVisible(), isTrue);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.remainingLiveIncomingCountFor(getConv()), 0,
        reason: 'an unrelated old-row change must not require another user tap');
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
  });

  uiTest('stale newest page exposes retry and preserves unread until successful',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(100 - i));
    final before = scroll.offset;
    await tester.tap(find.text('showUnread:1'));
    await frame(tester);
    expect(find.byKey(const ValueKey('return-latest-loading')), findsOneWidget);
    await settleReturn(tester, frameMs: 1);
    expect(scroll.offset, before);
    expect(global.remainingLiveIncomingCountFor(getConv()), 1);
    expect(model.readReports, 0);
    expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
    expect(find.byKey(const ValueKey('return-latest-retry')), findsOneWidget);
    expect(find.text('showUnread:1'), findsOneWidget);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    await tester.tap(find.byKey(const ValueKey('return-latest-retry')));
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.remainingLiveIncomingCountFor(getConv()), 0);
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
    expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
  });

  uiTest('return loading remains visible and duplicate actions share one request',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    final release = Completer<void>();
    sdk.duringRead = () => release.future;
    try {
      await tester.tap(find.text('showUnread:1'));
      for (var n = 0; n < 500 && sdk.calls == 0; n++) await frame(tester);
      expect(sdk.calls, 1);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsOneWidget);
      final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      await state.scrollToLatestAndDismissUnreadCapsule();
      await frame(tester, 200);
      expect(sdk.calls, 1);
      expect(global.remainingLiveIncomingCountFor(getConv()), 1);
      release.complete();
      await settleReturn(tester);
      expect(global.remainingLiveIncomingCountFor(getConv()), 0);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });

  uiTest('drag takes over pending return without failure or late snap to bottom',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    final release = Completer<void>();
    sdk.duringRead = () => release.future;
    try {
      await tester.tap(find.text('showUnread:1'));
      for (var n = 0; n < 500 && sdk.calls == 0; n++) await frame(tester);
      expect(sdk.calls, 1);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('history'))));
      await gesture.moveBy(const Offset(0, 180));
      await frame(tester);
      await gesture.cancel();
      await frame(tester, 200);
      final afterDrag = scroll.offset;
      expect(afterDrag, greaterThan(1200));
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
      release.complete();
      await settleReturn(tester);
      expect(scroll.offset, closeTo(afterDrag, 1));
      expect(global.remainingLiveIncomingCountFor(getConv()), 1);
      expect(model.readReports, 0);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });

  uiTest('replacing controller cancels return before a late page can move either list',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    final release = Completer<void>();
    sdk.duringRead = () => release.future;
    final oldScroll = scroll;
    var replaced = false;
    try {
      await tester.tap(find.text('showUnread:1'));
      for (var n = 0; n < 500 && sdk.calls == 0; n++) await frame(tester);
      expect(sdk.calls, 1);
      scroll = AutoScrollController(initialScrollOffset: 1200);
      replaced = true;
      global.bindActiveChatScrollController(
          conversationID: getConv(), scrollController: scroll);
      await mount(tester);
      await frame(tester, 200);
      expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
      final offset = scroll.offset;
      release.complete();
      await settleReturn(tester);
      expect(scroll.offset, closeTo(offset, 1));
      expect(global.rawMessageList(getConv())!.first.seq, '100');
      expect(global.remainingLiveIncomingCountFor(getConv()), 1);
      expect(model.readReports, 0);
    } finally {
      if (!release.isCompleted) release.complete();
      if (replaced) oldScroll.dispose();
    }
  });

  uiTest(
      'hung visible proof releases UI while durable writer stays ordered and retries',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    final release = Completer<void>();
    var entered = false;
    store.beforeVisibleAcknowledgement = () {
      entered = true;
      return release.future;
    };
    try {
      await tester.tap(find.text('showUnread:1'));
      for (var n = 0; n < 500 && !entered; n++) await frame(tester);
      expect(entered, isTrue);
      await frame(tester, 13000);
      await settleReturn(tester);
      expect(global.receivedNewMessageCountFor(getConv()), 1);
      expect(ChatRecoveryTrace.recentEvents.any((e) => e.contains('latest_proof_timeout')), isTrue);
      final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      unawaited(state.scrollToLatestAndDismissUnreadCapsule());
      await settleReturn(tester);
      expect(global.receivedNewMessageCountFor(getConv()), 1,
          reason: 'a pending durable writer cannot be bypassed on timeout');
      release.complete();
      for (var n = 0; n < 40; n++) await frame(tester);
      expect(global.receivedNewMessageCountFor(getConv()), 1,
          reason: 'late expired proof cannot consume the reminder');
      unawaited(state.scrollToLatestAndDismissUnreadCapsule());
      await settleReturn(tester);
      expect(global.receivedNewMessageCountFor(getConv()), 0);
    } finally {
      if (!release.isCompleted) release.complete();
      await frame(tester, 200);
    }
  });

  uiTest('hung latest snapshot expires without publishing an obsolete window',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    final release = Completer<void>();
    var entered = false;
    store.beforeDeferredRead = () {
      entered = true;
      return release.future;
    };
    bool? result;
    final calls = sdk.calls;
    try {
      unawaited(model.reloadNewestMessageWindow(allowWhileReadingHistory: true)
          .then((value) => result = value));
      for (var n = 0; n < 500 && !entered; n++) await frame(tester);
      expect(entered, isTrue);
      await frame(tester, 21000);
      expect(result, isFalse);
      expect(global.receivedNewMessageCountFor(getConv()), 1);
      release.complete();
      for (var n = 0; n < 40; n++) await frame(tester);
      expect(sdk.calls, calls, reason: 'expired preflight cannot invoke SDK');
      sdk.newest = List.generate(50, (i) => row(101 - i));
      final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      unawaited(state.scrollToLatestAndDismissUnreadCapsule());
      await settleReturn(tester);
      expect(global.receivedNewMessageCountFor(getConv()), 0);
    } finally {
      if (!release.isCompleted) release.complete();
      await frame(tester, 200);
    }
  });

  uiTest(
      'return does not acknowledge deferred rows outside the rendered projection',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    projectionLimit.value = 101;
    sdk.newest = List.generate(50, (i) => row(101 - i));
    sdk.duringRead = () async {
      await global.applyAppRealtimeMessage(row(102),
          ingressEventID: '${getConv()}-event-102', ingressSequence: 102);
    };
    await tester.tap(find.text('showUnread:1'));
    await settleReturn(tester);
    expect(global.rawMessageList(getConv())!.first.seq, '102');
    expect(find.text('row:101'), findsOneWidget);
    expect(find.text('row:102'), findsNothing);
    expect(verifyLatestVisible(), isTrue);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.receivedNewMessageCountFor(getConv()), 2,
        reason: 'a database/body snapshot is not the rendered viewport');
    expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
    expect(model.readReports, 0);
    expect(find.text('showUnread:2'), findsOneWidget);

    projectionLimit.value = null;
    sdk.duringRead = null;
    sdk.newest = List.generate(50, (i) => row(102 - i));
    await frame(tester);
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(find.text('row:102'), findsOneWidget);
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(global.hasDurableHistoryDeferred(getConv()), isFalse);
    expect(model.readReports, greaterThanOrEqualTo(1));
  });

  uiTest(
      'physical extent alone cannot complete return while latest row is displaced',
      (tester) async {
    await mount(tester);
    await awayInHistoryGap(tester);
    await receive(tester, 101, 1);
    sdk.newest = List.generate(50, (i) => row(101 - i));
    sdk.duringRead = () async {
      await global.applyAppRealtimeMessage(row(102),
          ingressEventID: '${getConv()}-event-102', ingressSequence: 102);
    };
    // A notifier can lag an insertion/keyboard frame. The synchronous row
    // measurement, rather than that old true value, must gate completion.
    holdVisibilityNotification = true;
    visible.value = true;
    newestTranslation.value = 120;
    await tester.tap(find.text('showUnread:1'));
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.rawMessageList(getConv())!.first.seq, '102');
    expect(verifyLatestVisible(), isFalse);
    expect(visible.value, isTrue, reason: 'the older-frame notifier is stale');
    expect(global.receivedNewMessageCountFor(getConv()), 2,
        reason: 'a stale visible flag cannot acknowledge an unpainted latest row');
    expect(model.readReports, 0);

    holdVisibilityNotification = false;
    newestTranslation.value = 0;
    sdk.duringRead = null;
    sdk.newest = List.generate(50, (i) => row(102 - i));
    await frame(tester);
    await tester.tap(find.text('showUnread:2'));
    await settleReturn(tester);
    expect(verifyLatestVisible(), isTrue);
    expect(global.receivedNewMessageCountFor(getConv()), 0);
    expect(model.readReports, greaterThanOrEqualTo(1));
  });

  uiTest('a real drag cancels ordinary return during visible proof retries',
      (tester) async {
    await mount(tester);
    await away(tester);
    projectionLimit.value = 99;
    await frame(tester);
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
        find.byType(TIMUIKitHistoryMessageListTongueContainer));
    var done = false;
    final returning = state.scrollToLatestAndDismissUnreadCapsule()
        .whenComplete(() => done = true);
    for (var n = 0; n < 60 && scroll.offset > 1; n++) {
      await frame(tester, 16);
    }
    for (var n = 0; n < 8; n++) {
      await frame(tester, 16);
    }
    expect(scroll.offset, closeTo(0, 1));
    expect(done, isFalse,
        reason: 'the ordinary return must still be resampling its old projection');
    expect(sdk.calls, 0);
    expect(find.byKey(const ValueKey('return-latest-loading')), findsOneWidget);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('history'))));
    await gesture.moveBy(const Offset(0, 180));
    await frame(tester, 16);
    await gesture.cancel();
    await frame(tester, 240);
    final afterDrag = scroll.offset;
    expect(afterDrag, greaterThan(100));
    expect(done, isTrue);
    expect(global.isUserScrollToBottomInProgress(getConv()), isFalse);
    expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);

    // The missing row becomes paintable after the user has taken over. The
    // old retry continuation must neither move the list nor report it read.
    projectionLimit.value = null;
    for (var n = 0; n < 30; n++) {
      await frame(tester, 40);
    }
    await returning;
    expect(scroll.offset, closeTo(afterDrag, 1));
    expect(global.isFollowingLatest(getConv()), isFalse);
    expect(model.readReports, 0);
    expect(sdk.calls, 0);
    expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);
  });

  uiTest('late retried visible ACK cannot unlock a new A return after A to B to A',
      (tester) async {
    final conversationA = getConv();
    final oldModelA = model;
    final oldProofRelease = Completer<void>();
    final newSdkRelease = Completer<void>();
    _ChatModel? middleModel;
    var proofs = 0;
    var oldDone = false;
    try {
      await mount(tester);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 1);
      sdk.newest = List.generate(50, (i) => row(101 - i));
      store.beforeVisibleAcknowledgement = () async {
        proofs++;
        final current = global.rawMessageList(getConv())!;
        global.setMessageList(getConv(), current.take(current.length - 1).toList(),
            replace: true, applyMemoryWindow: false);
        store.beforeVisibleAcknowledgement = () {
          proofs++;
          return oldProofRelease.future;
        };
      };
      final oldState = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      final oldReturning = oldState.scrollToLatestAndDismissUnreadCapsule()
          .whenComplete(() => oldDone = true);
      for (var n = 0; n < 1200 && proofs < 2; n++) {
        await frame(tester, 1);
      }
      expect(proofs, 2,
          reason: 'hold the second visible ACK, after a rejected first proof');
      expect(oldDone, isFalse);
      expect(sdk.calls, 1);

      middleModel = makeModel('@TGS#proof_middle_$sequence');
      model = middleModel;
      global.setCurrentConversation(
          CurrentConversation(getConv(), ConvType.group), notify: false);
      global.setMessageList(getConv(), List.generate(100, (i) => row(100 - i)),
          replace: true, applyMemoryWindow: false);
      await mount(tester);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
      model = makeModel(conversationA);
      global.setCurrentConversation(
          CurrentConversation(getConv(), ConvType.group), notify: false);
      global.bindActiveChatScrollController(
          conversationID: getConv(), scrollController: scroll);
      global.bindHistoryLiveWindowFreeze(
          conversationID: getConv(),
          freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded);
      await mount(tester);
      await awayInHistoryGap(tester);
      final remaining = global.receivedNewMessageCountFor(conversationA);
      expect(remaining, greaterThan(0));
      final newReadReports = model.readReports;
      final newOffset = scroll.offset;
      sdk.duringRead = () => newSdkRelease.future;
      final newState = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
          find.byType(TIMUIKitHistoryMessageListTongueContainer));
      final newReturning = newState.scrollToLatestAndDismissUnreadCapsule();
      await frame(tester, 40);
      expect(global.isUserScrollToBottomInProgress(conversationA), isTrue);

      oldProofRelease.complete();
      for (var n = 0; n < 1200 && sdk.calls < 2; n++) {
        await frame(tester, 1);
      }
      await oldReturning;
      expect(sdk.calls, 2);
      expect(oldDone, isTrue);
      expect(global.receivedNewMessageCountFor(conversationA), remaining,
          reason: 'the old visit proof must not acknowledge the new visit');
      expect(model.readReports, newReadReports);
      expect(scroll.offset, closeTo(newOffset, 1));
      expect(global.isUserScrollToBottomInProgress(conversationA), isTrue,
          reason: 'the old proof cannot release the new return transaction');
      expect(find.byKey(const ValueKey('return-latest-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('return-latest-retry')), findsNothing);

      newSdkRelease.complete();
      await settleReturn(tester);
      await newReturning;
      expect(global.receivedNewMessageCountFor(conversationA), 0);
      expect(global.isUserScrollToBottomInProgress(conversationA), isFalse);
      expect(find.byKey(const ValueKey('return-latest-loading')), findsNothing);
    } finally {
      if (!oldProofRelease.isCompleted) oldProofRelease.complete();
      if (!newSdkRelease.isCompleted) newSdkRelease.complete();
      await settleReturn(tester, frameMs: 1);
      if (!identical(oldModelA, model)) oldModelA.dispose();
      if (!identical(middleModel, model)) middleModel?.dispose();
    }
  });

  for (final restoring in [false, true]) {
    uiTest('latest ACK rechecks context-menu protection (restoring=$restoring)',
        (tester) async {
      await mount(tester);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 1);
      sdk.newest = List.generate(50, (i) => row(101 - i));
      sdk.duringRead = () async {
        await global.applyAppRealtimeMessage(row(102),
            ingressEventID: '${getConv()}-event-102', ingressSequence: 102);
      };
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeVisibleAcknowledgement = () async {
        entered.complete();
        await release.future;
      };
      try {
        await tester.tap(find.text('showUnread:1'));
        final pendingTime = Stopwatch()..start();
        while (!entered.isCompleted &&
            pendingTime.elapsed < const Duration(seconds: 15)) {
          await frame(tester, 1);
        }
        expect(entered.isCompleted, isTrue);
        expect(verifyLatestVisible(), isTrue);
        expect(global.receivedNewMessageCountFor(getConv()), greaterThan(0));
        global.beginMessageContextMenuOverlay(conversationID: getConv());
        await frame(tester);
        expect(find.text('message menu overlay'), findsOneWidget);
        if (restoring) {
          global.endMessageContextMenuOverlay(conversationID: getConv());
          await frame(tester);
          expect(global.isContextMenuViewportRestoreActive(getConv()), isTrue);
        }
        release.complete();
        await settleReturn(tester, frameMs: 1);
        expect(
            restoring
                ? global.isContextMenuViewportRestoreActive(getConv())
                : global.isMessageContextMenuOverlayOpen,
            isTrue,
            reason: 'the protection must remain active through acknowledgement');
        expect(verifyLatestVisible(), isTrue,
            reason: 'geometry remains valid behind the overlay transaction');
        expect(global.receivedNewMessageCountFor(getConv()), greaterThan(0),
            reason:
                'a protection change invalidates the pending reading proof');
        expect(global.hasDurableHistoryDeferred(getConv()), isTrue);
        expect(model.readReports, 0);
        if (!restoring) {
          global.endMessageContextMenuOverlay(conversationID: getConv());
        }
        global.completeContextMenuViewportRestore(getConv());
        sdk.duringRead = null;
        sdk.newest = List.generate(50, (i) => row(102 - i));
        await frame(tester, 200);
        final state =
            tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
                find.byType(TIMUIKitHistoryMessageListTongueContainer));
        unawaited(state.scrollToLatestAndDismissUnreadCapsule());
        await settleReturn(tester);
        expect(global.receivedNewMessageCountFor(getConv()), 0);
        expect(model.readReports, greaterThanOrEqualTo(1));
      } finally {
        if (!release.isCompleted) release.complete();
      }
    });
  }
}
