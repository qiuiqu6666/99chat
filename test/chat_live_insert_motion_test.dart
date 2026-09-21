import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKItMessageList/tim_uikit_chat_history_message_list.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _ReadingModel extends TUIChatSeparateViewModel {
  @override
  Future<void> markMessageAsRead(
      {bool notify = true, bool force = false}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  var generation = 0;
  for (final short in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final scenario in [
        'single',
        'burst',
        'reduced motion',
        'drag',
        'dispose',
        if (!short) 'window rotation',
        if (!short) 'window shrink',
        if (short) 'fills viewport',
      ]) {
        testWidgets(
            'live ${outgoing ? 'send' : 'receive'} $scenario keeps geometry with short=$short',
            (tester) async {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          Future<void> frame([int milliseconds = 16]) async {
            final handler = FlutterError.onError;
            await tester.pump(Duration(milliseconds: milliseconds));
            FlutterError.onError = handler;
          }

          final count = short
              ? (scenario == 'drag'
                  ? 9
                  : (scenario == 'fills viewport' ? 8 : 2))
              : 30;
          final conv = '@TGS#motion_${++generation}';
          V2TimMessage message(int seq, {bool self = false}) =>
              V2TimMessage.fromJson({
                'message_msg_id': '$conv-$seq',
                'message_conv_id': conv,
                'message_conv_type': 2,
                'message_server_time': seq,
                'message_risk_type_identified': 0,
              })
                ..groupID = conv
                ..seq = '$seq'
                ..timestamp = seq
                ..isSelf = self
                ..status = self ? 1 : 2
                ..elemType = 1
                ..textElem = V2TimTextElem(text: 'message $seq');
          await serviceLocator.unregister<TUIChatGlobalModel>();
          final global = TUIChatGlobalModel();
          serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
          global.configureMessageWriterScope(
              ownerUserID: 'motion-test',
              accountGeneration: generation,
              domainGeneration: 1);
          final model = _ReadingModel()
            ..conversationID = conv
            ..conversationType = ConvType.group
            ..groupType = GroupReceiptAllowType.public
            ..groupInfo = V2TimGroupInfo(groupID: conv, groupType: 'Public')
            ..chatConfig = const TIMUIKitChatConfig(
              isAutoReportRead: false,
              isShowReadingStatus: false,
              isUseDraft: false,
              messageEnterAnimationListPushEnabled: true,
              messageEnterAnimationStyle: MessageEnterAnimationStyle.wechat,
            )
            ..suppressReadReporting = true
            ..haveMoreData = false
            ..haveMoreLatestData = false;
          global.chatConfig = model.chatConfig;
          global.setCurrentConversation(
              CurrentConversation(conv, ConvType.group),
              notify: false);
          var rows = [for (var seq = count; seq > 0; seq--) message(seq)];
          global.setMessageList(conv, rows,
              replace: true, applyMemoryWindow: false);
          global.markInitialHistoryLoaded(conv);
          final scroll = AutoScrollController();
          final controller =
              TIMUIKitHistoryMessageListController(scrollController: scroll);
          Future<void> close() async {
            await tester.pumpWidget(const SizedBox());
            if (short && scenario == 'dispose') {
              expect(global.isInboundViewportPushActive(conv), isFalse);
            }
            await frame(2000);
            expect(tester.takeException(), isNull);
            model.dispose();
            global.dispose();
            scroll.dispose();
            controller.dispose();
          }

          late StateSetter update;
          final conversation = V2TimConversation(
              conversationID: 'group_$conv',
              groupID: conv,
              type: 2,
              unreadCount: 0,
              lastMessage: rows.first);
          final originalErrorHandler = FlutterError.onError;
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
              ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                  value: model),
            ],
            child: MaterialApp(
                home: MediaQuery(
                    data: MediaQueryData(
                        disableAnimations: scenario == 'reduced motion'),
                    child: Scaffold(body: StatefulBuilder(
                      builder: (_, setState) {
                        update = setState;
                        return TIMUIKitHistoryMessageList(
                          model: model,
                          conversation: conversation,
                          controller: controller,
                          messageList: rows,
                          onLoadMore: (id, direction,
                                  [count, seq, message]) async =>
                              true,
                          itemBuilder: (_, row) => SizedBox(
                            key: ValueKey('row-${row?.msgID}'),
                            height: 64,
                            child: Text('seq:${row?.seq}'),
                          ),
                        );
                      },
                    )))),
          ));
          FlutterError.onError = originalErrorHandler;
          for (var i = 0; i < 30; i++) {
            await frame(20);
          }
          final oldRow = find.byKey(ValueKey('row-$conv-$count'));
          expect(oldRow, findsOneWidget);
          final before = tester.getTopLeft(oldRow).dy;
          update(() => rows = [
                message(count + 1, self: outgoing),
                ...rows.take(scenario == 'window rotation'
                    ? rows.length - 1
                    : scenario == 'window shrink'
                        ? rows.length - 5
                        : rows.length),
              ]);
          if (scenario == 'dispose' || scenario == 'drag') {
            // A bottom-aligned short list cannot accept a drag until the new
            // row grows past the viewport, so exercise that crossing here.
            for (var i = 0; i < (short && scenario == 'drag' ? 10 : 6); i++) {
              await frame();
            }
            if (scenario == 'drag') {
              final gesture =
                  await tester.startGesture(tester.getCenter(oldRow));
              await gesture.moveBy(const Offset(0, 32));
              await frame(48);
              expect(global.isChatListUserScrolling, isTrue);
              final heldPosition = tester.getTopLeft(oldRow).dy;
              for (var i = 0; i < 20; i++) {
                await frame();
                expect(tester.getTopLeft(oldRow).dy, closeTo(heldPosition, .5),
                    reason:
                        'insertion must stop moving rows while a drag owns the viewport');
              }
              await gesture.up();
            }
            await close();
            return;
          }
          final positions = <double>[before];
          final offsets = <double>[];
          var inserted = 1;
          for (var frame = 0; frame < 52; frame++) {
            if ((scenario == 'burst' || scenario == 'fills viewport') &&
                [6, 13, 20].contains(frame)) {
              inserted++;
              update(() =>
                  rows = [message(count + inserted, self: outgoing), ...rows]);
            }
            final handler = FlutterError.onError;
            await tester.pump(const Duration(milliseconds: 16));
            FlutterError.onError = handler;
            positions.add(tester.getTopLeft(oldRow).dy);
            offsets.add(scroll.position.pixels);
          }
          expect(tester.takeException(), isNull);
          expect(
              find.byKey(ValueKey('row-$conv-${count + 1}')), findsOneWidget);
          // Both production modes are bottom aligned. A short list grows its row
          // without scroll extent; a long list compensates its scroll position.
          expect(before - positions.last, closeTo(64 * inserted, 1));
          if (scenario != 'reduced motion') {
            expect(positions.toSet().length, greaterThan(5));
          }
          if (!short && scenario != 'reduced motion') {
            expect(offsets.any((value) => value > 1), isTrue,
                reason:
                    'must exercise real viewport motion, not instant insertion');
          }
          for (var i = 1; i < positions.length; i++) {
            final step = positions[i - 1] - positions[i];
            expect(step,
                inInclusiveRange(-.5, scenario == 'reduced motion' ? 64.5 : 20),
                reason: 'frame $i must not jump or reverse direction');
          }
          expect(scroll.position.pixels,
              closeTo(scroll.position.minScrollExtent, .5));
          await close();
        });
      }
    }
  }
}
