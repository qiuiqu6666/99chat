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
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _ChatModel extends TUIChatSeparateViewModel {
  int readReports = 0;
  @override
  Future<void> markMessageAsRead({
    bool notify = true,
    bool force = false,
  }) async {
    readReports++;
  }
}

class _VisibilityProofStore extends HistoryWindowStore {
  _VisibilityProofStore({required super.debugDatabasePath});
  Future<void> Function()? beforeVisibleAcknowledgement;

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
        'message_risk_type_identified': 0,
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
      isUseDraft: false,
    )
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
      debugDatabasePath: '${directory.path}/history.db',
    );
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
      domainGeneration: 1,
    );
    model = makeModel('@TGS#tongue_$sequence');
    global.chatConfig = model.chatConfig;
    global.setCurrentConversation(
      CurrentConversation(getConv(), ConvType.group),
      notify: false,
    );
    scroll = AutoScrollController();
    global.bindActiveChatScrollController(
      conversationID: getConv(),
      scrollController: scroll,
    );
    global.bindHistoryLiveWindowFreeze(
      conversationID: getConv(),
      freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
    );
    global.setMessageList(
      getConv(),
      List.generate(100, (i) => row(100 - i)),
      replace: true,
      applyMemoryWindow: false,
    );
  });
  Future<void> frame(WidgetTester tester, [int milliseconds = 20]) async {
    final errorHandler = FlutterError.onError;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
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
    final row = rowKeys[displayed.first.msgID]?.currentContext
        ?.findRenderObject();
    if (viewport is! RenderBox ||
        row is! RenderBox ||
        !viewport.attached ||
        !row.attached ||
        !viewport.hasSize ||
        !row.hasSize) {
      return false;
    }
    final edge = row
        .localToGlobal(Offset(0, row.size.height), ancestor: viewport)
        .dy;
    return edge >= -4 && edge <= viewport.size.height + 4;
  }

  Future<void> mount(WidgetTester tester) async {
    projectionLimit = ValueNotifier<int?>(null);
    newestTranslation = ValueNotifier(0.0);
    visible = ValueNotifier(false);
    holdVisibilityNotification = false;
    final handler = FlutterError.onError;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
          ChangeNotifierProvider<TUIChatSeparateViewModel>.value(value: model),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: Listenable.merge([
                global,
                projectionLimit,
                newestTranslation,
              ]),
              builder: (_, __) {
                final limit = projectionLimit.value;
                displayed =
                    (global.rawMessageList(getConv()) ?? <V2TimMessage>[])
                        .where(
                          (row) =>
                              limit == null || int.parse(row.seq!) <= limit,
                        )
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
                return Stack(
                  key: viewportKey,
                  children: [
                    ListView.builder(
                      key: const Key('history'),
                      controller: scroll,
                      reverse: true,
                      itemExtent: 60,
                      itemCount: displayed.length,
                      itemBuilder: (_, index) {
                        final row = displayed[index];
                        return Transform.translate(
                          offset: Offset(
                            0,
                            index == 0 ? newestTranslation.value : 0,
                          ),
                          child: SizedBox(
                            key: rowKeys[row.msgID],
                            height: 60,
                            child: Text('row:${row.seq}'),
                          ),
                        );
                      },
                    ),
                    TIMUIKitHistoryMessageListTongueContainer(
                      messageList: displayed,
                      conversation: V2TimConversation(
                        conversationID: 'group_${getConv()}',
                        groupID: getConv(),
                        type: 2,
                        unreadCount: 0,
                      ),
                      scrollToIndexBySeq: (_) async => false,
                      scrollToFirstUnread: (_) async => true,
                      scrollController: scroll,
                      model: model,
                      latestMessageVisible: visible,
                      verifyLatestMessageVisible: verifyLatestVisible,
                      tongueItemBuilder: (tap, type, count) => TextButton(
                        onPressed: tap,
                        child: Text('${type.name}:$count'),
                      ),
                    ),
                    if (global.isMessageContextMenuOverlayOpen)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Text('message menu overlay'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
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
          await global.applyAppRealtimeMessage(
            row(id),
            ingressEventID: '${getConv()}-event-$id',
            ingressSequence: id,
          );
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
    expect(
      failure,
      isNull,
      reason: 'durable admission must preserve the message',
    );
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
    expect(
      global.isUserScrollToBottomInProgress(getConv()),
      isFalse,
      reason: 'latest-window return and durable ACK must finish',
    );
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

  uiTest(
    'return waits for the newest projected identity before read reporting',
    (tester) async {
      await mount(tester);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 1);
      projectionLimit.value = 101;
      sdk.newest = List.generate(50, (i) => row(101 - i));
      sdk.duringRead = () async {
        await global.applyAppRealtimeMessage(
          row(102),
          ingressEventID: '${getConv()}-event-102',
          ingressSequence: 102,
        );
      };
      await tester.tap(find.text('showUnread:1'));
      await settleReturn(tester);
      expect(global.rawMessageList(getConv())!.first.seq, '102');
      expect(find.text('row:101'), findsOneWidget);
      expect(find.text('row:102'), findsNothing);
      expect(scroll.offset, closeTo(0, 1));
      expect(model.readReports, 0);

      projectionLimit.value = null;
      sdk.duringRead = null;
      sdk.newest = List.generate(50, (i) => row(102 - i));
      await frame(tester);
      final state = tester
          .state<TIMUIKitHistoryMessageListTongueContainerState>(
            find.byType(TIMUIKitHistoryMessageListTongueContainer),
          );
      unawaited(state.scrollToLatestAndDismissUnreadCapsule());
      await settleReturn(tester);
      expect(find.text('row:102'), findsOneWidget);
      expect(model.readReports, 1);
    },
  );

  uiTest('ordinary return still reports read after successful follow commit', (
    tester,
  ) async {
    await mount(tester);
    await away(tester);
    final state = tester.state<TIMUIKitHistoryMessageListTongueContainerState>(
      find.byType(TIMUIKitHistoryMessageListTongueContainer),
    );
    unawaited(state.scrollToLatestAndDismissUnreadCapsule());
    await settleReturn(tester);
    expect(scroll.offset, closeTo(0, 1));
    expect(global.isFollowingLatest(getConv()), isTrue);
    expect(model.readReports, 1);
  });

  uiTest(
    'menu opened during latest reload prevents read reporting until uncovered',
    (tester) async {
      await mount(tester);
      await awayInHistoryGap(tester);
      await receive(tester, 101, 1);
      sdk.newest = List.generate(50, (i) => row(101 - i));
      sdk.duringRead = () async {
        global.beginMessageContextMenuOverlay(conversationID: getConv());
      };
      await tester.tap(find.text('showUnread:1'));
      await settleReturn(tester);
      expect(global.isMessageContextMenuOverlayOpen, isTrue);
      expect(model.readReports, 0);
      global.dismissAllContextMenuOverlays();
      sdk.duringRead = null;
      await frame(tester);
      final state = tester
          .state<TIMUIKitHistoryMessageListTongueContainerState>(
            find.byType(TIMUIKitHistoryMessageListTongueContainer),
          );
      unawaited(state.scrollToLatestAndDismissUnreadCapsule());
      await settleReturn(tester);
      expect(model.readReports, 1);
    },
  );
}
