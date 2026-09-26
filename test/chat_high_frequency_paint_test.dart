import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

// Count actual painted pixels: a mounted row with a valid global rect can
// still be clipped to zero height or hidden by an ancestor's opacity.
Future<double> _paintedFraction(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = boundary.toImageSync(pixelRatio: .1);
  try {
    final bytes = await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
    var colored = 0;
    for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) < 30 &&
          bytes.getUint8(i + 2) > 220 &&
          bytes.getUint8(i + 3) > 220) {
        colored++;
      }
    }
    return colored / (image.width * image.height);
  } finally {
    image.dispose();
  }
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  var generation = 0;
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final initialCount in [2, 30]) {
      for (final batchSize in [1, 6, 24]) {
        for (final scenario in [
          'live',
          if (initialCount == 2 && batchSize == 6) 'hydrate',
          if (initialCount == 2 && batchSize == 24) 'no-animation',
        ]) {
          testWidgets(
              '$platform $scenario paint survives $batchSize arrivals per frame from $initialCount rows',
              (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            tester.view.physicalSize = const Size(400, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final handler = FlutterError.onError;
            Future<void> frame([int ms = 16]) async {
              await tester.pump(Duration(milliseconds: ms));
              FlutterError.onError = handler;
            }

            await serviceLocator.unregister<TUIChatGlobalModel>();
            final global = TUIChatGlobalModel();
            serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
            final conv = '@paint-${++generation}';
            V2TimMessage message(int seq) => V2TimMessage.fromJson({
                  'message_msg_id': '$conv-$seq',
                  'message_risk_type_identified': 0,
                })
                  ..groupID = conv
                  ..seq = '$seq'
                  ..timestamp = seq
                  ..isSelf = false
                  ..status = 2
                  ..elemType = 1
                  ..textElem = V2TimTextElem(text: '$seq');
            final model = _ReadingModel()
              ..conversationID = conv
              ..conversationType = ConvType.group
              ..chatConfig = TIMUIKitChatConfig(
                  isAutoReportRead: false,
                  isShowReadingStatus: false,
                  isUseDraft: false,
                  messageEnterAnimationListPushEnabled:
                      scenario != 'no-animation',
                  messageEnterAnimationStyle: MessageEnterAnimationStyle.wechat)
              ..suppressReadReporting = true
              ..haveMoreData = false
              ..haveMoreLatestData = false;
            global.configureMessageWriterScope(
                ownerUserID: 'paint-owner',
                accountGeneration: generation,
                domainGeneration: 1);
            global.chatConfig = model.chatConfig;
            global.setCurrentConversation(
                CurrentConversation(conv, ConvType.group),
                notify: false);
            var rows = [
              for (var seq = initialCount; seq > 0; seq--) message(10000 + seq)
            ];
            global.setMessageList(conv, rows,
                replace: true, applyMemoryWindow: false);
            global.markInitialHistoryLoaded(conv);
            final scroll = AutoScrollController();
            final controller =
                TIMUIKitHistoryMessageListController(scrollController: scroll);
            final boundary = GlobalKey();
            late StateSetter update;
            try {
              await tester.pumpWidget(MultiProvider(
                  providers: [
                    ChangeNotifierProvider<TUIChatGlobalModel>.value(
                        value: global),
                    ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                        value: model),
                  ],
                  child: MaterialApp(
                      home: Scaffold(
                          body: RepaintBoundary(
                    key: boundary,
                    child: StatefulBuilder(builder: (_, setState) {
                      update = setState;
                      return TIMUIKitHistoryMessageList(
                        model: model,
                        conversation: V2TimConversation(
                            conversationID: 'group_$conv',
                            groupID: conv,
                            type: 2,
                            unreadCount: 0,
                            lastMessage: rows.first),
                        controller: controller,
                        messageList: rows,
                        onLoadMore: (_, __, [count, seq, message]) async =>
                            false,
                        itemBuilder: (_, row) => SizedBox(
                          key: ValueKey('row-${row?.msgID}'),
                          height: const [
                            44.0,
                            64.0,
                            120.0,
                            480.0,
                            1000.0
                          ][int.parse(row!.seq!) % 5],
                          child: const ColoredBox(color: Color(0xff0066ff)),
                        ),
                      );
                    }),
                  )))));
              FlutterError.onError = handler;
              for (var i = 0; i < 30; i++) {
                await frame(20);
              }
              final baseline = await _paintedFraction(tester, boundary);
              expect(baseline, greaterThan(.15));
              if (scenario == 'hydrate') {
                update(() => rows = [
                      ...rows,
                      for (var seq = 10000; seq > 9950; seq--) message(seq),
                    ]);
                await frame();
                final projectedCount = tester
                    .widgetList<SliverList>(find.byType(SliverList))
                    .fold<int>(
                        0,
                        (count, list) =>
                            count + (list.delegate.estimatedChildCount ?? 0));
                expect(projectedCount, greaterThanOrEqualTo(initialCount));
                expect(projectedCount, lessThan(rows.length),
                    reason:
                        'older history must still mount in bounded frame batches');
                expect(await _paintedFraction(tester, boundary),
                    greaterThanOrEqualTo(baseline * .9));
              }
              var seq = 10000 + initialCount;
              for (var tick = 0; tick < 80; tick++) {
                if (tick < 50) {
                  final incoming = [
                    for (var i = 0; i < batchSize; i++) message(++seq)
                  ].reversed;
                  update(
                      () => rows = [...incoming, ...rows].take(100).toList());
                }
                await frame();
                final painted = await _paintedFraction(tester, boundary);
                expect(painted, greaterThanOrEqualTo(baseline * .9),
                    reason:
                        'frame=$tick rows=${rows.length} pixels=${scroll.offset} range=${scroll.position.minScrollExtent}..${scroll.position.maxScrollExtent}');
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await frame(2000);
              model.dispose();
              global.dispose();
              controller.dispose();
              scroll.dispose();
              FlutterError.onError = handler;
              debugDefaultTargetPlatformOverride = null;
            }
          });
        }
      }
    }
    for (final initialCount in [2, 100]) {
      for (final reading in [false, if (initialCount == 100) true]) {
        testWidgets(
            '$platform durable ingress keeps painting from $initialCount rows (reading=$reading)',
            (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SqfliteLifecycleGuard.instance.debugReset();
          final directory = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('chat-paint-'),
          ))!;
          final store = HistoryWindowStore(
              debugDatabasePath: '${directory.path}/history.db');
          HistoryWindowRepositoryProvider.repository = store;
          await serviceLocator.unregister<TUIChatGlobalModel>();
          final global = TUIChatGlobalModel();
          serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
          final conv = '@durable-paint-${++generation}';
          V2TimMessage message(int seq) => V2TimMessage.fromJson({
                'message_msg_id': '$conv-$seq',
                'message_conv_id': conv,
                'message_conv_type': 2,
                'message_server_time': seq,
                'message_risk_type_identified': 0,
              })
                ..groupID = conv
                ..seq = '$seq'
                ..isSelf = false
                ..status = 2
                ..elemType = 1
                ..textElem = V2TimTextElem(text: '$seq');
          final model = _ReadingModel()
            ..conversationID = conv
            ..conversationType = ConvType.group
            ..groupType = GroupReceiptAllowType.public
            ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Public')
            ..chatConfig = const TIMUIKitChatConfig(
                isAutoReportRead: false,
                isShowReadingStatus: false,
                isUseDraft: false,
                inboundChunkRevealEnabled: true,
                messageEnterAnimationListPushEnabled: true,
                messageEnterAnimationStyle: MessageEnterAnimationStyle.wechat)
            ..suppressReadReporting = true
            ..haveMoreData = false
            ..haveMoreLatestData = false;
          global.configureMessageWriterScope(
              ownerUserID: 'paint-owner',
              accountGeneration: generation,
              domainGeneration: 1);
          global.chatConfig = model.chatConfig;
          global.setCurrentConversation(
              CurrentConversation(conv, ConvType.group),
              notify: false);
          global.setMessageList(
              conv, [for (var seq = initialCount; seq > 0; seq--) message(seq)],
              replace: true, applyMemoryWindow: false);
          global.markInitialHistoryLoaded(conv);
          global.bindHistoryLiveWindowFreeze(
              conversationID: conv,
              freezeIfNeeded: model.freezeVisibleHistoryWindowIfNeeded,
              canAppendIncoming: model.canAppendIncomingToReadingWindow,
              didAppendIncoming: model.didAppendIncomingToReadingWindow);
          final scroll = AutoScrollController();
          final controller =
              TIMUIKitHistoryMessageListController(scrollController: scroll);
          final boundary = GlobalKey();
          final handler = FlutterError.onError;
          Future<void> frame([int ms = 16]) async {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 2)));
            await tester.pump(Duration(milliseconds: ms));
            FlutterError.onError = handler;
          }

          Future<void> waitFor(bool Function() ready) async {
            final elapsed = Stopwatch()..start();
            while (!ready() && elapsed.elapsed < const Duration(seconds: 15)) {
              await frame();
            }
            expect(ready(), isTrue);
          }

          Future<void>? admissions;
          var admitted = true;
          try {
            await tester.pumpWidget(MultiProvider(
                providers: [
                  ChangeNotifierProvider<TUIChatGlobalModel>.value(
                      value: global),
                  ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                      value: model),
                ],
                child: MaterialApp(
                    home: Scaffold(
                        body: RepaintBoundary(
                  key: boundary,
                  child: TIMUIKitHistoryMessageListSelector(
                      conversationID: conv,
                      builder: (_, rows, __) => TIMUIKitHistoryMessageList(
                            model: model,
                            conversation: V2TimConversation(
                                conversationID: 'group_$conv',
                                groupID: conv,
                                type: 2,
                                unreadCount: 0,
                                lastMessage: message(initialCount)),
                            controller: controller,
                            messageList: rows,
                            onLoadMore: (_, __, [count, seq, message]) async =>
                                false,
                            itemBuilder: (_, row) => SizedBox(
                              key: ValueKey('row-${row?.msgID}'),
                              height: row?.elemType == 11
                                  ? 24
                                  : const [
                                      44.0,
                                      64.0,
                                      120.0,
                                      480.0,
                                      1000.0
                                    ][int.parse(row!.seq!) % 5],
                              child: const ColoredBox(color: Color(0xff0066ff)),
                            ),
                          )),
                )))));
            FlutterError.onError = handler;
            for (var i = 0; i < 30; i++) {
              await frame();
            }
            if (reading) {
              scroll.jumpTo(1200);
              global.setFollowingLatest(conv, false);
              for (var i = 0; i < 5; i++) {
                await frame();
              }
            }
            final baseline = await _paintedFraction(tester, boundary);
            expect(baseline, greaterThan(.15));
            final pin = global.pinToBottomRequestSeq;
            final target =
                reading ? find.byKey(ValueKey('row-$conv-96')) : null;
            final top = target == null ? null : tester.getTopLeft(target).dy;
            admitted = false;
            admissions = (() async {
              for (var seq = initialCount + 1;
                  seq <= initialCount + 180;
                  seq++) {
                await global.applyAppRealtimeMessage(message(seq));
              }
            })()
                .whenComplete(() => admitted = true);
            final deadline = Stopwatch()..start();
            var settledFrames = 0;
            var observedFrames = 0;
            while ((!admitted || settledFrames < 120) &&
                deadline.elapsed < const Duration(seconds: 20)) {
              await frame();
              observedFrames++;
              if (admitted) settledFrames++;
              expect(await _paintedFraction(tester, boundary),
                  greaterThanOrEqualTo(baseline * .9),
                  reason:
                      'ingress frame=$observedFrames raw=${global.rawMessageCount(conv)} pixels=${scroll.offset}');
              if (target != null) {
                expect(tester.getTopLeft(target).dy, closeTo(top!, 1));
              }
            }
            expect(admitted, isTrue);
            await admissions;
            expect(settledFrames, 120);
            expect(global.rawMessageList(conv)!.first.seq,
                '${initialCount + 180}');
            expect(global.isFollowingLatest(conv), !reading);
            if (reading) {
              expect(global.pinToBottomRequestSeq, pin);
            } else {
              expect(
                  scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
            }
          } finally {
            await waitFor(() => admitted);
            await admissions;
            await tester.pumpWidget(const SizedBox.shrink());
            global.dismissAllContextMenuOverlays();
            global.clearActiveChatScrollController(conversationID: conv);
            global.clearData();
            model.dispose();
            controller.dispose();
            scroll.dispose();
            HistoryWindowRepositoryProvider.repository = null;
            var closed = false;
            final closing =
                store.closeIfOpen().whenComplete(() => closed = true);
            await waitFor(() => closed);
            await closing;
            await frame(2000);
            global.dispose();
            await tester.runAsync(() => directory.delete(recursive: true));
            SqfliteLifecycleGuard.instance.debugReset();
            FlutterError.onError = handler;
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  }
}
