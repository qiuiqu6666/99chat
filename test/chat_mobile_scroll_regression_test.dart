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

  Future<void> receive(WidgetTester tester, int first, int last) async {
    sdk.newest = last;
    admissionFinished = false;
    pendingAdmission = (() async {
      for (var seq = first; seq <= last; seq++) {
        await global
            .applyAppRealtimeMessage(_message(model.conversationID, seq));
      }
    })()
        .whenComplete(() => admissionFinished = true);
    await waitFor(
        tester, () => admissionFinished, 'durable admission completes');
    await pendingAdmission;
    await frames(tester, 12);
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
    for (final arrivals in [0, 40, 120]) {
      testWidgets(
          '${platform.name}: one bottom tap reaches newest after $arrivals live arrivals',
          (tester) async {
        try {
          await mount(tester, platform);
          final conv = model.conversationID;
          for (var i = 0; i < 4; i++) {
            await tester.drag(
                find.byType(CustomScrollView).first, const Offset(0, 1100));
            await frames(tester, 8);
          }
          expect(global.isFollowingLatest(conv), isFalse);
          if (arrivals > 0) {
            await receive(tester, 101, 100 + arrivals);
            expect(scroll.position.minScrollExtent, lessThan(0),
                reason: 'live arrivals exercise the negative latest extent');
          }
          final newest = find.byKey(ValueKey('row-$conv-${100 + arrivals}'));
          expect(newest.hitTestable(), findsNothing);
          final capsule = find
              .textContaining(arrivals == 0 ? 'toLatest:' : 'showUnread:')
              .hitTestable();
          expect(capsule, findsOneWidget);
          var firstBottomPainted = false;
          var largestRebound = 0.0;
          var missingLatestFrames = 0;
          final returnFrames = <String>[];
          // Check the transition itself, not only the final settled position.
          // Releasing a negative-extent center used to expose the old origin
          // for a frame after the newest row had already reached the bottom.
          afterFrame = () {
            final position = scroll.position;
            final distance = position.pixels - position.minScrollExtent;
            final visible = newest.hitTestable().evaluate().isNotEmpty;
            returnFrames.add('pixels=${position.pixels.toStringAsFixed(1)} '
                'min=${position.minScrollExtent.toStringAsFixed(1)} '
                'latestVisible=$visible');
            if (distance.abs() <= 4 && visible) firstBottomPainted = true;
            if (firstBottomPainted) {
              if (distance > largestRebound) largestRebound = distance;
              if (!visible) missingLatestFrames++;
            }
          };
          await tester.tap(capsule);
          await waitFor(
              tester,
              () =>
                  global.isFollowingLatest(conv) &&
                  !global.isUserScrollToBottomInProgress(conv) &&
                  newest.hitTestable().evaluate().length == 1 &&
                  (scroll.offset - scroll.position.minScrollExtent).abs() < 1,
              'one tap reaches and commits the actual newest message');
          // Completion can run in post-frame callbacks. Give the next layout
          // and the platform's ballistic activity time to settle before using
          // hit testing as a visibility proof.
          await frames(tester, 40);
          expect(firstBottomPainted, isTrue);
          expect(largestRebound, lessThanOrEqualTo(4),
              reason: returnFrames.join('\n'));
          expect(missingLatestFrames, 0, reason: returnFrames.join('\n'));
          final top = tester.getTopLeft(newest).dy;
          afterFrame = () {
            expect(newest.hitTestable(), findsOneWidget);
            expect(tester.getTopLeft(newest).dy, closeTo(top, 1));
            expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 4));
          };
          await frames(tester, 10);
          expect(newest.hitTestable(), findsOneWidget,
              reason: 'the final settled viewport must retain the newest row');
          expect(global.receivedNewMessageCountFor(conv), 0);
          expect(global.remainingLiveIncomingCountFor(conv), 0);
        } finally {
          await close(tester);
        }
      });
    }

    for (final continuous in [true, false]) {
      testWidgets(
          '${platform.name}: one return completes with ${continuous ? 'continuous arrivals and delayed latest height' : '300 highly variable live rows'}',
          (tester) async {
        Future<bool>? returning;
        var returned = false;
        try {
          await mount(tester, platform,
              heightForSequence: continuous
                  ? null
                  : (seq) =>
                      const <double>[28, 720, 36, 1050, 52, 96][seq % 6]);
          final conv = model.conversationID;
          for (var i = 0; i < 4; i++) {
            await tester.drag(
                find.byType(CustomScrollView).first, const Offset(0, 1100));
            await frames(tester, 8);
          }
          expect(global.isFollowingLatest(conv), isFalse);
          final prefixEnd = continuous ? 220 : 400;
          await receive(tester, 101, prefixEnd);
          expect(scroll.position.minScrollExtent, lessThan(0));
          // This is the public user-return API bound to the mounted capsule's
          // production transaction. Its future, rather than a transient bottom
          // flag, identifies when the one return request has completed.
          returning = model
              .requestLatestViewportReturn()
              .whenComplete(() => returned = true);
          if (continuous) {
            Future<void> chain = Future<void>.value();
            for (var tick = 0; tick < 80; tick++) {
              if (tick.isEven) {
                final seq = prefixEnd + tick ~/ 2 + 1;
                admissionFinished = false;
                chain = chain.then((_) async {
                  sdk.newest = seq;
                  await global.applyAppRealtimeMessage(_message(conv, seq));
                });
                pendingAdmission = chain;
              }
              await frame(tester);
            }
            pendingAdmission =
                chain.whenComplete(() => admissionFinished = true);
            await waitFor(tester, () => admissionFinished,
                '40ms incoming stream must complete');
            await pendingAdmission;
          }
          await waitFor(tester, () => returned,
              'the single production return future must finish');
          expect(await returning, isTrue);
          final latestSeq = continuous ? 260 : 400;
          if (continuous) {
            // Simulate the latest attachment resolving its actual height after
            // return completion. This change uses only the public row builder.
            rowHeights.value = {latestSeq: 420};
          }
          await frames(tester, 75);
          final newest = find.byKey(ValueKey('row-$conv-$latestSeq'));
          final viewport = tester.getRect(find.byType(CustomScrollView).first);
          expect(global.rawMessageList(conv)!.first.seq, '$latestSeq');
          expect(newest.hitTestable(), findsOneWidget,
              reason: 'one request must expose the final live message');
          expect(tester.getBottomLeft(newest).dy, closeTo(viewport.bottom, 4),
              reason:
                  'latest message bottom must align after geometry settles');
          expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 4));
          expect(global.isFollowingLatest(conv), isTrue);
          expect(global.isUserScrollToBottomInProgress(conv), isFalse);
          expect(global.remainingLiveIncomingCountFor(conv), 0);
        } finally {
          if (returning != null && !returned) {
            await waitFor(tester, () => returned,
                'return transaction must finish before disposal');
          }
          await close(tester);
        }
      });
    }
  }
}
