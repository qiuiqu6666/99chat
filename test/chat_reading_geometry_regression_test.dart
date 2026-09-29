import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// Match the controller type exposed by the production history list.
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
    final newer = getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    final candidates = [
      for (var seq = newest; seq > 0; seq--)
        if (boundary <= 0 || (newer ? seq > boundary : seq < boundary))
          _message(groupID!, seq),
    ];
    final rows = newer
        ? candidates.reversed.take(count).toList().reversed.toList()
        : candidates.take(count).toList();
    return MessageHistorySdkResult(
      code: 0,
      desc: 'controlled SDK page',
      data: V2TimMessageListResult(
          isFinished: candidates.length <= count, messageList: rows),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

// Keep loading, durable admission and visible-message acknowledgement real.
class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
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
  late ValueNotifier<Map<int, double>> rowHeights;
  Future<void>? pendingAdmission;
  var admissionFinished = true;
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
    directory = await Directory.systemTemp.createTemp('mobile-chat-scroll-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _PagingSdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'mobile-scroll-reader',
        accountGeneration: ++generation,
        domainGeneration: 1);
    final conv = '@TGS#mobile_scroll_$generation';
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
    global.bindHistoryLiveWindowFreeze(
        conversationID: conv,
        freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded);
    scroll = AutoScrollController();
    controller = TIMUIKitHistoryMessageListController(scrollController: scroll);
    rowHeights = ValueNotifier<Map<int, double>>({});
    pendingAdmission = null;
    admissionFinished = true;
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

  Future<void> waitFor(
      WidgetTester tester, bool Function() ready, String reason) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
      await frame(tester);
    }
    expect(ready(), isTrue, reason: reason);
  }

  Future<void> mount(WidgetTester tester, TargetPlatform platform,
      {double Function(int)? heightForSequence}) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
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
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: TIMUIKitHistoryMessageListSelector(
            conversationID: conv,
            builder: (_, messages, __) => TIMUIKitHistoryMessageList(
              model: model,
              conversation: conversation,
              controller: controller,
              messageList: messages,
              onLoadMore: (id, direction, [count, seq, message]) =>
                  model.loadChatRecord(
                      count: count ?? 40,
                      direction: direction,
                      lastMsgID: id,
                      lastMsgSeq: seq ?? -1,
                      lastMsg: message),
              itemBuilder: (_, message) {
                final seq = int.tryParse(message?.seq ?? '') ?? 0;
                return ValueListenableBuilder<Map<int, double>>(
                  valueListenable: rowHeights,
                  builder: (_, heights, __) => SizedBox(
                    key: ValueKey('row-${message?.msgID}'),
                    height: message?.elemType == 11
                        ? 24
                        : heights[seq] ??
                            heightForSequence?.call(seq) ??
                            (seq % 11 == 0 ? 180 : 48.0 + seq % 4 * 20),
                    child: Text('seq:${message?.seq}'),
                  ),
                );
              },
              tongueItemBuilder: (tap, type, count) => TextButton(
                  onPressed: tap, child: Text('${type.name}:$count')),
            ),
          ),
        ),
      ),
    ));
    FlutterError.onError = handler;
    await frames(tester);
    expect(scroll.hasClients, isTrue);
  }

  Future<void> close(WidgetTester tester) async {
    afterFrame = null;
    await waitFor(tester, () => admissionFinished,
        'finish SQLite work before disposing its scope');
    await pendingAdmission;
    await tester.pumpWidget(const SizedBox.shrink());
    global.dismissAllContextMenuOverlays();
    global.clearActiveChatScrollController(
        conversationID: model.conversationID);
    global.clearData();
    model.dispose();
    controller.dispose();
    scroll.dispose();
    rowHeights.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    var closed = false;
    final closing = store.closeIfOpen().whenComplete(() => closed = true);
    await waitFor(tester, () => closed, 'history database closes');
    await closing;
    await frame(tester, 2000);
    await tester.runAsync(() => directory.delete(recursive: true));
    SqfliteLifecycleGuard.instance.debugReset();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = null;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name}: viewport resize releases its geometry latch',
        (tester) async {
      try {
        await mount(tester, platform);
        final conv = model.conversationID;
        expect(global.isGeometryViewportTransitionActive(conv), isFalse);
        tester.view.physicalSize = const Size(390, 620);
        await frames(tester, 8);
        expect(global.isGeometryViewportTransitionActive(conv), isFalse,
            reason:
                'settled frames must release the latch without a user gesture or incoming rows');
        tester.view.physicalSize = const Size(390, 844);
        await frames(tester, 8);
        expect(global.isGeometryViewportTransitionActive(conv), isFalse);
      } finally {
        await close(tester);
      }
    });

    testWidgets(
        '${platform.name}: late row growth and shrink preserve historical reading',
        (tester) async {
      try {
        await mount(tester, platform);
        final conv = model.conversationID;
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, 650));
        await frames(tester, 60);
        expect(global.isFollowingLatest(conv), isFalse);
        final candidates = <MapEntry<int, double>>[];
        for (var seq = 1; seq <= 100; seq++) {
          final row = find.byKey(ValueKey('row-$conv-$seq'));
          if (row.evaluate().isNotEmpty) {
            final rect = tester.getRect(row);
            if (rect.top >= 0 && rect.bottom <= 844) {
              candidates.add(MapEntry(seq, rect.top));
            }
          }
        }
        candidates.sort((a, b) => a.value.compareTo(b.value));
        expect(candidates.length, greaterThan(2));
        final anchor = candidates[candidates.length ~/ 2].key;
        final delayed = candidates.last.key;
        final anchorFinder = find.byKey(ValueKey('row-$conv-$anchor'));
        final delayedFinder = find.byKey(ValueKey('row-$conv-$delayed'));
        final before = tester.getTopLeft(anchorFinder).dy;
        final initialHeight = tester.getSize(delayedFinder).height;
        rowHeights.value = {delayed: initialHeight + 120};
        await tester.pump();
        expect(tester.getTopLeft(anchorFinder).dy, closeTo(before, 1),
            reason: 'the first painted frame must preserve the reading row');
        await frames(tester, 30);
        rowHeights.value = {delayed: initialHeight};
        await tester.pump();
        expect(tester.getTopLeft(anchorFinder).dy, closeTo(before, 1),
            reason: 'late shrink must not ratchet the reading position');
        await frames(tester, 3);
        final pixels = scroll.position.pixels;
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, 150));
        await frames(tester, 8);
        expect(scroll.position.pixels, greaterThan(pixels + 100),
            reason: 'the reading anchor must yield to a fresh user drag');
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets('geometry settling releases only the list-owned transition',
      (tester) async {
    try {
      await mount(tester, TargetPlatform.android);
      final conv = model.conversationID;
      global.beginGeometryViewportTransition(conv);
      tester.view.physicalSize = const Size(390, 620);
      await frames(tester, 8);
      expect(global.isGeometryViewportTransitionActive(conv), isTrue,
          reason:
              'an independent keyboard transition still owns its protection');
      global.endGeometryViewportTransition(conv);
      expect(global.isGeometryViewportTransitionActive(conv), isFalse,
          reason: 'the list must not leave another unmatched transition depth');
    } finally {
      await close(tester);
    }
  });

  testWidgets('disposing during resize releases the pending list transition',
      (tester) async {
    try {
      await mount(tester, TargetPlatform.android);
      final conv = model.conversationID;
      tester.view.physicalSize = const Size(390, 620);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(global.isGeometryViewportTransitionActive(conv), isFalse);
      await frames(tester, 5);
      expect(global.isGeometryViewportTransitionActive(conv), isFalse,
          reason:
              'stale frame callbacks must not reacquire protection after disposal');
    } finally {
      await close(tester);
    }
  });
}
