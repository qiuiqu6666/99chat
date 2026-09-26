import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/message_anchor.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

const _group = '@TGS#search-return';
V2TimMessage _row(int seq) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
    })
      ..msgID = 'row-$seq'
      ..seq = '$seq'
      ..groupID = _group
      ..sender = 'sender'
      ..elemType = 1
      ..timestamp = 1700000000 + seq
      ..status = 2
      ..textElem = V2TimTextElem(text: 'History row $seq');

final _conversation = V2TimConversation(
  conversationID: 'group_$_group',
  groupID: _group,
  type: 2,
  showName: 'Search return',
  lastMessage: _row(200),
);
MessageAnchor _anchor(int seq) =>
    MessageAnchor.fromConversationMessage(_conversation, _row(seq));

class _History extends MessageService {
  final requestedSeqs = <int>[];

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
    requestedSeqs.add(lastMsgSeq);
    final target = lastMsgSeq > 0 ? lastMsgSeq : 200;
    final newer = getType == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG ||
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG;
    return MessageHistorySdkResult(
      code: 0,
      desc: 'fixture',
      data: V2TimMessageListResult(
        isFinished: true,
        messageList:
            List.generate(count, (i) => _row(newer ? target + i : target - i)),
      ),
    );
  }

  @override
  Future<List<V2TimMessage>?> findMessages(
          {required List<String> messageIDList}) async =>
      messageIDList.map((id) => _row(int.parse(id.split('-').last))).toList();

  @override
  Future<V2TimCallback> markGroupMessageAsRead(
          {required String groupID}) async =>
      V2TimCallback(code: 0, desc: 'fixture');

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) async =>
      V2TimCallback(code: 0, desc: 'fixture');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Unexpected MessageService call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform search result reuses the live UIKit model and window',
        (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      final frameworkError = FlutterError.onError;
      final registry = AppChatRouteRegistry.instance;
      final history = _History();
      await serviceLocator.unregister<MessageService>();
      serviceLocator.registerSingleton<MessageService>(history);
      await serviceLocator.unregister<TUIChatGlobalModel>();
      final global = TUIChatGlobalModel();
      serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
      global.configureMessageWriterScope(
          ownerUserID: 'search-return',
          accountGeneration: 1,
          domainGeneration: 1);
      final controller = TIMUIKitChatController();
      registry.prepareForTest = () async {};
      registry.chatBuilderForTest = (anchor, message) => TIMUIKitChat(
            key: const ValueKey('retained-uikit'),
            controller: controller,
            conversation: _conversation,
            conversationID: _group,
            initFindingMsg: message,
            searchJumpAnchor: anchor,
            localOnlyInitialOpen: true,
            config: const TIMUIKitChatConfig(
                isAutoReportRead: false, isShowReadingStatus: false),
          );
      Future<void> pump(
          [Duration duration = const Duration(milliseconds: 50)]) async {
        FlutterError.onError = frameworkError;
        await tester.pump(duration);
        FlutterError.onError = frameworkError;
        expect(tester.takeException(), isNull);
      }

      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await pump();
        }
      }

      try {
        final navKey = GlobalKey<NavigatorState>();
        late BuildContext home;
        await tester.pumpWidget(MaterialApp(
          navigatorKey: navKey,
          home: Builder(builder: (context) {
            home = context;
            return const Scaffold(body: Text('Conversations'));
          }),
        ));
        FlutterError.onError = frameworkError;
        var chatClosed = false;
        final opened = openOrReuseAppChat(home, _conversation)
            .whenComplete(() => chatClosed = true);
        await settle();
        final state = tester.state(find.byType(TIMUIKitChat));
        final model = controller.model!;
        final route = registry.activeRoute(
            navKey.currentState!, appChatSessionKey(_conversation))!;
        expect(global.rawMessageCount(_group), greaterThan(1));

        for (final seq in [50, 80, 80]) {
          // Match the real route depth: chat -> profile/settings -> search.
          navKey.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Profile'))));
          await settle();
          late BuildContext search;
          navKey.currentState!.push(MaterialPageRoute<void>(builder: (context) {
            search = context;
            return const Scaffold(body: Text('Search results'));
          }));
          await settle();
          final callsBefore = history.requestedSeqs.length;
          var searchChatClosed = false;
          final result = openOrReuseAppChat(search, _conversation,
                  initFindingMsg: _row(seq), searchJumpAnchor: _anchor(seq))
              .whenComplete(() => searchChatClosed = true);
          await settle();
          expect(route.isCurrent, isTrue);
          expect(tester.state(find.byType(TIMUIKitChat)), same(state));
          expect(controller.model, same(model));
          expect(chatClosed, isFalse);
          expect(searchChatClosed, isFalse);
          expect(history.requestedSeqs.skip(callsBefore), contains(seq));
          expect(global.rawMessageList(_group)!.map((m) => m.msgID),
              contains('row-$seq'));
          expect(global.getSearchJumpStatus(_group), SearchJumpStatus.success);
          expect(model.jumpMsgID, 'row-$seq');
          final position = controller.scrollController!.position.pixels;
          final revision = global.messageListRevisionFor(_group);
          navKey.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Ordinary detail'))));
          await settle();
          navKey.currentState!.pop();
          await settle();
          expect(controller.scrollController!.position.pixels,
              closeTo(position, 0.5));
          expect(global.messageListRevisionFor(_group), revision);
          // The old path released this conversation after a 15-second grace.
          await pump(const Duration(seconds: 16));
          expect(global.rawMessageCount(_group), greaterThan(1));
          // Keep the actual pop completion contract; collect without awaiting.
          unawaited(result);
        }
        navKey.currentState!.pop();
        await settle();
        await opened;
        expect(chatClosed, isTrue);
        expect(registry.hasAnyActiveChatRoute(), isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        FlutterError.onError = frameworkError;
        await tester.pump(const Duration(seconds: 2));
        FlutterError.onError = frameworkError;
        registry.reset();
        ChatOpenPerfLog.resetForTest();
        global.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });
  }

  for (final beforeFirstFrame in [false, true]) {
    testWidgets(
        'last target wins ${beforeFirstFrame ? 'after push before first frame' : 'during preparation'}',
        (tester) async {
      final registry = AppChatRouteRegistry.instance;
      final prepare = Completer<void>();
      registry.prepareForTest = () => prepare.future;
      final targets = <MessageAnchor?>[];
      registry.chatBuilderForTest = (anchor, _) {
        targets.add(anchor);
        return Scaffold(body: Text(anchor?.msgID ?? 'Latest'));
      };
      final navKey = GlobalKey<NavigatorState>();
      late BuildContext home;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(builder: (context) {
          home = context;
          return const SizedBox.shrink();
        }),
      ));
      final first = openOrReuseAppChat(home, _conversation,
          searchJumpAnchor: _anchor(50));
      if (beforeFirstFrame) {
        prepare.complete();
        await tester.idle();
        expect(navKey.currentState!.canPop(), isTrue);
        expect(
            registry.activeRoute(
                navKey.currentState!, appChatSessionKey(_conversation)),
            isNull);
      }
      final second = openOrReuseAppChat(home, _conversation,
          searchJumpAnchor: _anchor(80));
      if (!beforeFirstFrame) prepare.complete();
      await tester.pumpAndSettle();
      expect(targets.last?.msgID, 'row-80');
      final route = registry.activeRoute(
          navKey.currentState!, appChatSessionKey(_conversation));
      expect(route?.isCurrent, isTrue);
      final plain = openOrReuseAppChat(home, _conversation);
      await tester.pumpAndSettle();
      expect(
          registry.activeRoute(
              navKey.currentState!, appChatSessionKey(_conversation)),
          same(route));
      expect(targets.last?.msgID, 'row-80');
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      await Future.wait([first, second, plain]);
      expect(navKey.currentState!.canPop(), isFalse);
      registry.reset();
      ChatOpenPerfLog.resetForTest();
    });
  }

  testWidgets('account change cancels search preparation before push',
      (tester) async {
    final registry = AppChatRouteRegistry.instance;
    final prepare = Completer<void>();
    registry.prepareForTest = () => prepare.future;
    registry.chatBuilderForTest = (_, __) => const Text('Unexpected chat');
    final navKey = GlobalKey<NavigatorState>();
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(builder: (context) {
          home = context;
          return const SizedBox.shrink();
        })));
    final opened =
        openOrReuseAppChat(home, _conversation, searchJumpAnchor: _anchor(50));
    SessionIdentityService.instance.invalidate(reason: 'search_test');
    prepare.complete();
    await tester.pumpAndSettle();
    await opened;
    expect(navKey.currentState!.canPop(), isFalse);
    expect(find.text('Unexpected chat'), findsNothing);
    registry.reset();
    ChatOpenPerfLog.resetForTest();
  });
}
