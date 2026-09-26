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
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_at_info.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_mention_read_store.dart';
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

var _targetSeq = 1676691;
const _oldNewestSeq = 1676981;
const _entryCount = 0;

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

/// Stub only the SDK boundary. Around-window merge, publication, real SQLite
/// admission, list projection, Tongue callback and scrolling remain production.
class _AroundWindowSdk extends MessageService {
  final pinGate = Completer<void>();
  bool pinStarted = false;
  bool fail = false;
  final requests = <({HistoryMsgGetTypeEnum type, int seq, List<int>? pins})>[];

  void release() {
    if (!pinGate.isCompleted) pinGate.complete();
  }

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
    requests.add((type: getType, seq: lastMsgSeq, pins: messageSeqList));
    final requestedSeq = messageSeqList?.first ?? lastMsgSeq;
    if (messageSeqList?.contains(_targetSeq) == true) {
      pinStarted = true;
      await pinGate.future;
    }
    if (fail) {
      return const MessageHistorySdkResult(
          code: -1, desc: 'controlled history failure', data: null);
    }
    final isPin = messageSeqList?.isNotEmpty == true;
    final newer = getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    final rows = isPin
        ? [_message(groupID!, requestedSeq)]
        : List.generate(
            20,
            (i) => _message(
                groupID!, newer ? requestedSeq + i : requestedSeq - i));
    return MessageHistorySdkResult(
        code: 0,
        desc: 'controlled around window',
        data: V2TimMessageListResult(isFinished: true, messageList: rows));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _RealJumpModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  late _AroundWindowSdk sdk;
  late TUIChatGlobalModel global;
  late _RealJumpModel model;
  late AutoScrollController scroll;
  late TIMUIKitHistoryMessageListController controller;
  late Widget Function() buildHistory;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('real-mention-jump-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _AroundWindowSdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'unread-jump-test-owner',
        accountGeneration: ++generation,
        domainGeneration: 1);
    final conversationID = '@TGS#real_unread_$generation';
    model = _RealJumpModel()
      ..conversationID = conversationID
      ..conversationType = ConvType.group
      ..groupInfo = V2TimGroupInfo(groupID: conversationID, groupType: 'Public')
      ..chatConfig = const TIMUIKitChatConfig(
          isAutoReportRead: false,
          isShowReadingStatus: false,
          inboundChunkRevealEnabled: true,
          isUseDraft: false)
      ..suppressReadReporting = true
      ..initialUnreadCount = _entryCount
      ..entryUnreadLastMessage = _message(conversationID, _oldNewestSeq);
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(
        CurrentConversation(conversationID, ConvType.group),
        notify: false);
    global.setMessageList(conversationID,
        List.generate(84, (i) => _message(conversationID, _oldNewestSeq - i)),
        replace: true, applyMemoryWindow: false);
    global.markInitialHistoryLoaded(conversationID);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
  });

  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final handler = FlutterError.onError;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(Duration(milliseconds: milliseconds));
    FlutterError.onError = handler;
  }

  Future<void> waitUntil(
      WidgetTester tester, bool Function() predicate, String reason,
      {int frames = 300}) async {
    for (var attempt = 0; attempt < frames && !predicate(); attempt++) {
      await frame(tester);
    }
    expect(predicate(), isTrue, reason: reason);
  }

  Finder spinner() => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '正在定位消息');

  Future<void> mount(WidgetTester tester,
      {int oldCount = 84, List<int>? mentions, int warmFrames = 25}) async {
    if (oldCount != 84) {
      global.setMessageList(
          model.conversationID,
          List.generate(oldCount,
              (i) => _message(model.conversationID, _oldNewestSeq - i)),
          replace: true,
          applyMemoryWindow: false);
    }
    final conversation = V2TimConversation(
        conversationID: 'group_${model.conversationID}',
        groupID: model.conversationID,
        type: 2,
        unreadCount: _entryCount,
        groupReadSequence: _targetSeq - 1,
        lastMessage: model.entryUnreadLastMessage);
    buildHistory = () => MultiProvider(
            providers: [
              ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
              ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                  value: model),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: TIMUIKitHistoryMessageListSelector(
              conversationID: model.conversationID,
              builder: (context, messages, _) => TIMUIKitHistoryMessageList(
                key: const Key('actual-history-list'),
                model: model,
                conversation: conversation,
                groupAtInfoList: [
                  for (final seq in mentions ?? [_targetSeq])
                    V2TimGroupAtInfo(seq: '$seq', atType: 2)
                ],
                controller: controller,
                messageList: messages,
                onLoadMore: (_, __, [___, ____, _____]) async => false,
                itemBuilder: (_, message) => SizedBox(
                  key: ValueKey('row-${message?.msgID}'),
                  height: message?.elemType == 11 ? 24 : 64,
                  child: Text('seq:${message?.seq}'),
                ),
                tongueItemBuilder: (tap, type, count) => TextButton(
                    onPressed: tap, child: Text('${type.name}:$count')),
              ),
            ))));
    final handler = FlutterError.onError;
    await tester.pumpWidget(buildHistory());
    FlutterError.onError = handler;
    for (var i = 0; i < warmFrames; i++) {
      await frame(tester);
    }
    expect(find.text('showPrevious:$_entryCount').hitTestable(), findsNothing);
    expect(global.rawMessageCount(model.conversationID), oldCount);
    expect(
        tester
            .widget<TIMUIKitHistoryMessageList>(
                find.byType(TIMUIKitHistoryMessageList))
            .messageList
            .length,
        oldCount + 1);
  }

  void regression(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        sdk.release();
        await tester.pumpWidget(const SizedBox.shrink());
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
        await waitUntil(tester, () => closed, 'history store closes',
            frames: 300);
        await closing;
        await frame(tester, 2000);
        await tester.runAsync(() => directory.delete(recursive: true));
        SqfliteLifecycleGuard.instance.debugReset();
      }
    });
  }

  Finder mention() => find.text('atAll:0');

  for (final (target, count) in [
    (_oldNewestSeq, 84),
    (_oldNewestSeq - 4, 84),
    (_oldNewestSeq - 60, 84),
    (_oldNewestSeq - 83, 84),
    (_oldNewestSeq - 4, 6),
    (1676691, 84),
  ]) {
    regression('at-all tap positions actual row $target in $count rows',
        (tester) async {
      _targetSeq = target;
      sdk.release();
      await mount(tester, oldCount: count);
      expect(mention().hitTestable(), findsOneWidget);
      await tester.tap(mention());
      await waitUntil(
          tester,
          () => model.jumpMsgID == '${model.conversationID}-$target',
          'mention target must be positioned');
      await waitUntil(tester, () => mention().evaluate().isEmpty,
          'only a completed jump consumes the mention');
      final row = find.byKey(ValueKey('row-${model.conversationID}-$target'));
      expect(row, findsOneWidget);
      final list = find.byType(TIMUIKitHistoryMessageList);
      final delta =
          (tester.getCenter(row).dy - tester.getCenter(list).dy).abs();
      expect(delta, lessThanOrEqualTo(3), reason: 'target is centered');
      expect(
          GroupMentionReadStore.instance
              .cached('unread-jump-test-owner', model.conversationID),
          contains('$target'));
      if (target > _oldNewestSeq - 84) expect(sdk.requests, isEmpty);
    });
  }

  regression('double tap loads one window and exposes loading feedback',
      (tester) async {
    _targetSeq = 1676691;
    await mount(tester);
    await tester.tap(mention());
    await tester.tap(mention(), warnIfMissed: false);
    await waitUntil(
        tester,
        () => sdk.pinStarted && spinner().evaluate().isNotEmpty,
        'SDK target read begins with visible loading feedback');
    expect(spinner(), findsOneWidget);
    expect(sdk.requests.where((r) => r.pins != null), hasLength(1));
    sdk.release();
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'successful jump consumes the mention');
    expect(model.jumpMsgID, '${model.conversationID}-$_targetSeq');
    expect(spinner(), findsNothing);
  });

  regression('early tap uses loaded rows before first-screen batching finishes',
      (tester) async {
    _targetSeq = _oldNewestSeq - 60;
    sdk.release();
    await mount(tester, warmFrames: 1);
    await waitUntil(tester, () => mention().hitTestable().evaluate().isNotEmpty,
        'mention button is interactive');
    await tester.tap(mention());
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'loaded target is positioned');
    expect(model.jumpMsgID, '${model.conversationID}-$_targetSeq');
    expect(sdk.requests, isEmpty,
        reason:
            'already loaded history must not depend on network availability');
  });

  regression('successive at-all reminders each position their own message',
      (tester) async {
    final older = _oldNewestSeq - 60;
    final newer = _oldNewestSeq - 4;
    await mount(tester, mentions: [newer, older]);
    await tester.tap(mention());
    await waitUntil(
        tester,
        () =>
            GroupMentionReadStore.instance
                .cached('unread-jump-test-owner', model.conversationID)
                ?.contains('$older') ==
            true,
        'first target is acknowledged');
    expect(model.jumpMsgID, '${model.conversationID}-$older');
    await frame(tester);
    expect(mention().hitTestable(), findsOneWidget);
    await tester.tap(mention());
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'the next reminder can be clicked in the same page');
    expect(model.jumpMsgID, '${model.conversationID}-$newer');
    final row = find.byKey(ValueKey('row-${model.conversationID}-$newer'));
    expect(
        (tester.getCenter(row).dy -
                tester.getCenter(find.byType(TIMUIKitHistoryMessageList)).dy)
            .abs(),
        lessThanOrEqualTo(3));
    expect(sdk.requests, isEmpty);
  });

  regression('failed history load preserves reminder and permits retry',
      (tester) async {
    _targetSeq = 1676691;
    sdk.fail = true;
    sdk.release();
    await mount(tester);
    await tester.tap(mention());
    await waitUntil(
        tester,
        () =>
            global.getSearchJumpStatus(model.conversationID) ==
                SearchJumpStatus.failed &&
            spinner().evaluate().isEmpty,
        'failed load releases the UI');
    expect(mention().hitTestable(), findsOneWidget);
    expect(global.rawMessageCount(model.conversationID), 84);
    expect(
        GroupMentionReadStore.instance
            .cached('unread-jump-test-owner', model.conversationID),
        isNot(contains('$_targetSeq')));
    sdk.fail = false;
    await tester.tap(mention());
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'retry succeeds without leaving the conversation');
    expect(model.jumpMsgID, '${model.conversationID}-$_targetSeq');
  });

  regression('new arrivals do not pull a positioned mention back to latest',
      (tester) async {
    _targetSeq = _oldNewestSeq - 4;
    await mount(tester);
    await tester.tap(mention());
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'mention is positioned before new messages arrive');
    final target =
        find.byKey(ValueKey('row-${model.conversationID}-$_targetSeq'));
    final before = tester.getCenter(target).dy;
    var done = false;
    Object? failure;
    final receiving = () async {
      for (var i = 1; i <= 6; i++) {
        final seq = _oldNewestSeq + i;
        await global.applyAppRealtimeMessage(
            _message(model.conversationID, seq),
            ingressEventID: '${model.conversationID}-event-$seq',
            ingressSequence: seq);
      }
    }()
        .catchError((Object error) {
      failure = error;
    }).whenComplete(() => done = true);
    await waitUntil(tester, () => done, 'incoming messages are admitted',
        frames: 1500);
    await receiving;
    expect(failure, isNull);
    for (var i = 0; i < 30; i++) {
      await frame(tester);
    }
    expect(target, findsOneWidget);
    expect((tester.getCenter(target).dy - before).abs(), lessThanOrEqualTo(3));
    expect(model.jumpMsgID, '${model.conversationID}-$_targetSeq');
  });

  regression('timed-out load cannot overwrite a later mention jump',
      (tester) async {
    _targetSeq = 1676691;
    await mount(tester);
    await tester.tap(mention());
    await waitUntil(tester, () => sdk.pinStarted, 'SDK read is pending');
    await frame(tester, 13000);
    await waitUntil(tester, () => spinner().evaluate().isEmpty,
        'timeout releases the retained viewport');
    expect(global.getSearchJumpStatus(model.conversationID),
        SearchJumpStatus.failed);
    expect(mention().hitTestable(), findsOneWidget);
    expect(
        GroupMentionReadStore.instance
            .cached('unread-jump-test-owner', model.conversationID),
        isNot(contains('1676691')));

    _targetSeq = _oldNewestSeq - 4;
    await tester.pumpWidget(buildHistory());
    await frame(tester);
    await tester.tap(mention());
    await waitUntil(tester, () => mention().evaluate().isEmpty,
        'new memory target succeeds while old SDK call is still pending');
    sdk.release();
    for (var i = 0; i < 20; i++) {
      await frame(tester);
    }
    expect(global.rawMessageCount(model.conversationID), 84);
    expect(model.jumpMsgID, '${model.conversationID}-$_targetSeq');
    expect(global.getSearchJumpStatus(model.conversationID),
        SearchJumpStatus.success);
  });
}
