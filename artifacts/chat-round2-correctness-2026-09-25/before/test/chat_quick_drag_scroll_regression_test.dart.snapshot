import 'package:flutter/foundation.dart';
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
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scenario in [
      (insertionFrames: 1, sustained: false),
      (insertionFrames: 6, sustained: false),
      (insertionFrames: 6, sustained: true),
    ]) {
      final insertionFrames = scenario.insertionFrames;
      testWidgets(
          '${platform.name}: ${scenario.sustained ? 'sustained drag' : 'same-frame drag cancellation'} after $insertionFrames insertion frames stops live motion',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        Future<void> frame([int milliseconds = 16]) async {
          final handler = FlutterError.onError;
          await tester.pump(Duration(milliseconds: milliseconds));
          FlutterError.onError = handler;
        }

        final conv = '@TGS#quick_drag_${++generation}';
        V2TimMessage message(int seq) => V2TimMessage.fromJson({
              'message_msg_id': '$conv-$seq',
              'message_conv_id': conv,
              'message_conv_type': 2,
              'message_server_time': seq,
              'message_risk_type_identified': 0,
            })
              ..groupID = conv
              ..seq = '$seq'
              ..timestamp = seq
              ..isSelf = false
              ..status = 2
              ..elemType = 1
              ..textElem = V2TimTextElem(text: 'message $seq');
        await serviceLocator.unregister<TUIChatGlobalModel>();
        final global = TUIChatGlobalModel();
        serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
        global.configureMessageWriterScope(
            ownerUserID: 'quick-drag-test',
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
        global.setCurrentConversation(CurrentConversation(conv, ConvType.group),
            notify: false);
        var rows = [for (var seq = 30; seq > 0; seq--) message(seq)];
        global.setMessageList(conv, rows,
            replace: true, applyMemoryWindow: false);
        global.markInitialHistoryLoaded(conv);
        final scroll = AutoScrollController();
        final controller =
            TIMUIKitHistoryMessageListController(scrollController: scroll);
        try {
          late StateSetter update;
          final conversation = V2TimConversation(
              conversationID: 'group_$conv',
              groupID: conv,
              type: 2,
              unreadCount: 0,
              lastMessage: rows.first);
          final handler = FlutterError.onError;
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<TUIChatGlobalModel>.value(value: global),
              ChangeNotifierProvider<TUIChatSeparateViewModel>.value(
                  value: model),
            ],
            child: MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
                update = setState;
                return TIMUIKitHistoryMessageList(
                  model: model,
                  conversation: conversation,
                  controller: controller,
                  messageList: rows,
                  onLoadMore: (id, direction, [count, seq, message]) async =>
                      true,
                  itemBuilder: (_, row) => SizedBox(
                    key: ValueKey('row-${row?.msgID}'),
                    height: 64,
                    child: Text('seq:${row?.seq}'),
                  ),
                );
              })),
            ),
          ));
          FlutterError.onError = handler;
          for (var i = 0; i < 30; i++) {
            await frame(20);
          }
          update(() => rows = [message(31), ...rows]);
          for (var i = 0; i < insertionFrames; i++) {
            await frame();
          }
          expect(global.isInboundViewportPushActive(conv), isTrue,
              reason: 'the drag interrupts an in-flight production insertion');
          final readingRow = find.byKey(ValueKey('row-$conv-28'));
          expect(readingRow.hitTestable(), findsOneWidget);
          final beforeTop = tester.getTopLeft(readingRow).dy;
          final beforePixels = scroll.offset;
          final gesture =
              await tester.startGesture(tester.getCenter(readingRow));
          if (scenario.sustained) {
            await gesture.moveBy(const Offset(0, 700));
            expect(global.isChatListUserScrolling, isTrue);
            await frame();
            expect(global.isChatListUserScrolling, isTrue,
                reason: 'stopping insertion must not cancel the held gesture');
            final nextRow = find.byKey(ValueKey('row-$conv-18'));
            expect(nextRow, findsOneWidget);
            expect(
                tester
                    .getRect(find.byType(CustomScrollView).first)
                    .contains(tester.getCenter(nextRow)),
                isTrue,
                reason:
                    'the replacement reading row must be inside the viewport');
            final heldTop = tester.getTopLeft(nextRow).dy;
            final heldPixels = scroll.offset;
            await gesture.moveBy(const Offset(0, 20));
            expect(global.isChatListUserScrolling, isTrue);
            final userDelta = scroll.offset - heldPixels;
            expect(userDelta, closeTo(20, .5),
                reason: 'the same pointer must still control the viewport');
            await frame();
            expect(global.isChatListUserScrolling, isTrue);
            expect(tester.getTopLeft(nextRow).dy,
                closeTo(heldTop + userDelta, .5));
            await gesture.cancel();
            final top = tester.getTopLeft(nextRow).dy;
            for (var i = 0; i < 20; i++) {
              await frame();
              expect(tester.getTopLeft(nextRow).dy, closeTo(top, .5));
            }
            return;
          }
          await gesture.moveBy(const Offset(0, 150));
          expect(global.isChatListUserScrolling, isTrue);
          // Both pointer events occur before the ticker receives another frame.
          // Cancel removes gesture momentum from this viewport ownership test.
          await gesture.cancel();
          expect(global.isChatListUserScrolling, isFalse);
          final expectedTop = beforeTop + scroll.offset - beforePixels;
          await frame();
          expect(global.isFollowingLatest(conv), isFalse);
          final top = tester.getTopLeft(readingRow).dy;
          expect(top, closeTo(expectedTop, .5),
              reason: 'the first painted frame must contain only user motion');
          for (var i = 0; i < 20; i++) {
            await frame();
            expect(tester.getTopLeft(readingRow).dy, closeTo(top, .5),
                reason:
                    'frame $i: an ended user drag must cancel the old push');
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await frame(2000);
          model.dispose();
          global.dispose();
          scroll.dispose();
          controller.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
