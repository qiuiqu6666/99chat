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

const _targetSeq = 1676691;
const _oldNewestSeq = 1676981;
const _entryCount = 287;

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
        ? [_message(groupID!, _targetSeq)]
        : List.generate(20,
            (i) => _message(groupID!, newer ? _targetSeq + i : _targetSeq - i));
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
    directory = await Directory.systemTemp.createTemp('real-unread-jump-');
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
    global.lockEntryUnreadForTongue(
        conversationID: conversationID,
        unreadCount: _entryCount,
        firstUnreadSeq: _targetSeq);
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

  Future<void> mount(WidgetTester tester, {int oldCount = 84}) async {
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
    for (var i = 0; i < 25; i++) {
      await frame(tester);
    }
    expect(
        find.text('showPrevious:$_entryCount').hitTestable(), findsNothing);
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

  for (final oldCount in [84, 39]) {
    regression('entry unread is absent with $oldCount loaded messages', (tester) async {
      await mount(tester, oldCount: oldCount);
      expect(find.text('showPrevious:$_entryCount'), findsNothing);
      expect(spinner(), findsNothing);
      expect(sdk.pinStarted, isFalse);
      expect(sdk.requests.where((r) => r.pins != null), isEmpty);
      expect(global.receivedNewMessageCountFor(model.conversationID), 0);
      expect(model.initialUnreadCount, _entryCount);
    });
  }
}
