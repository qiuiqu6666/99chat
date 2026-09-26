import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_demo/src/navigation/app_chat_route.dart';
import 'package:tencent_cloud_chat_demo/src/platform/route_handler.dart';
import 'package:tencent_cloud_chat_demo/src/services/active_chat_registry.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_open_perf_log.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/message_notification_banner.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controller/tim_uikit_chat_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage _row(String group, int seq) => V2TimMessage.fromJson({
      'message_risk_type_identified': 0,
    })
      ..msgID = '$group-row-$seq'
      ..seq = '$seq'
      ..groupID = group
      ..sender = 'sender'
      ..elemType = 1
      ..timestamp = 1700000000 + seq
      ..status = 2
      ..textElem = V2TimTextElem(text: '$group message $seq');

V2TimConversation _conversation(String group) => V2TimConversation(
    conversationID: 'group_$group',
    groupID: group,
    type: 2,
    showName: group,
    lastMessage: _row(group, 200));

class _History extends MessageService {
  Completer<void>? gate;
  final requestedGroups = <String>[];
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
    requestedGroups.add(groupID!);
    if (groupID == '@TGS#banner-second') await gate?.future;
    return MessageHistorySdkResult(
        code: 0,
        desc: 'fixture',
        data: V2TimMessageListResult(
            isFinished: true,
            messageList: List.generate(count, (i) => _row(groupID, 200 - i))));
  }

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

class _SilentReadModel extends TUIChatSeparateViewModel {
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final scenario in [(true, false), (false, false), (false, true)]) {
      final (reuse, cold) = scenario;
      testWidgets(
          '$platform notification ${reuse ? 'reuses covered chat' : 'switches chat during old pop'} (cold=$cold)',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        final handler = FlutterError.onError;
        final registry = AppChatRouteRegistry.instance;
        await serviceLocator.unregister<MessageService>();
        final history = _History()..gate = cold ? Completer<void>() : null;
        serviceLocator.registerSingleton<MessageService>(history);
        await serviceLocator.unregister<TUIChatGlobalModel>();
        final global = TUIChatGlobalModel();
        serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
        global.configureMessageWriterScope(
            ownerUserID: 'banner-test',
            accountGeneration: 1,
            domainGeneration: 1);
        const first = '@TGS#banner-first';
        const second = '@TGS#banner-second';
        for (final id in [first, if (!cold) second]) {
          global.setMessageList(id, List.generate(30, (i) => _row(id, 200 - i)),
              replace: true, applyMemoryWindow: false);
          global.markInitialHistoryLoaded(id);
        }
        var buildingGroup = first;
        final controllers = <String, TIMUIKitChatController>{};
        final routeGroups = <Route<dynamic>, String>{};
        registry.prepareForTest = () async {};
        registry.chatBuilderForTest = (_, __) => Builder(builder: (context) {
          // Match appChatRoute's captured conversation even when the old
          // route rebuilds underneath a different route during a transition.
          final group = routeGroups.putIfAbsent(
              ModalRoute.of(context)!, () => buildingGroup);
          return TIMUIKitChat(
              key: ValueKey(group),
              controller: controllers.putIfAbsent(
                  group, () => TIMUIKitChatController()),
              conversation: _conversation(group),
              conversationID: group,
              localOnlyInitialOpen: true,
              config: const TIMUIKitChatConfig(
                  isAutoReportRead: false, isShowReadingStatus: false));
        });
        Future<void> frame([int ms = 16]) async {
          FlutterError.onError = handler;
          await tester.pump(Duration(milliseconds: ms));
          FlutterError.onError = handler;
          expect(tester.takeException(), isNull);
        }

        Future<void> settle() async {
          for (var i = 0; i < 40; i++) {
            await frame();
          }
        }

        try {
          ActiveChatRegistry.instance.reset();
          await tester.pumpWidget(MaterialApp(
              navigatorKey: AppNavigator.key,
              home: const Scaffold(body: Text('Conversations'))));
          FlutterError.onError = handler;
          final navigator = AppNavigator.key.currentState!;
          unawaited(
              openOrReuseAppChat(AppNavigator.context!, _conversation(first)));
          await settle();
          final initialState = tester.state(find.byKey(const ValueKey(first)));
          final initialModel = controllers[first]!.model;
          final initialRoute = registry.activeRoute(
              navigator, appChatSessionKey(_conversation(first)))!;
          expect(global.currentSelectedConv, first);
          if (reuse) {
            for (final name in ['Profile', 'Search']) {
              navigator.push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: Text(name))));
              await settle();
            }
          }
          final target = reuse ? first : second;
          buildingGroup = target;
          final result = RouteHandler.openChat(
              conversationID: 'group_$target',
              conversation: _conversation(target),
              source: 'notification_test');
          await settle();
          expect(await result, isTrue);
          expect(global.currentSelectedConv, target,
              reason: 'old route disposal must not remove the new active chat');
          if (cold) {
            expect(history.requestedGroups, contains(second));
            history.gate!.complete();
            await settle();
          }
          if (reuse) {
            expect(initialRoute.isCurrent, isTrue);
            expect(tester.state(find.byKey(const ValueKey(first))),
                same(initialState));
            expect(controllers[first]!.model, same(initialModel));
          }
          expect(global.rawMessageCount(target), greaterThan(1));
          expect(
              find.text('$target message 200').hitTestable(), findsOneWidget);
          await frame(16000);
          expect(global.rawMessageCount(target), greaterThan(1));
        } finally {
          if (history.gate != null && !history.gate!.isCompleted) {
            history.gate!.complete();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          FlutterError.onError = handler;
          await tester.pump(const Duration(seconds: 2));
          FlutterError.onError = handler;
          registry.reset();
          ActiveChatRegistry.instance.reset();
          ChatOpenPerfLog.resetForTest();
          global.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  for (final sameConversation in [false, true]) {
    for (final closeOldFirst in [false, true]) {
      testWidgets(
          'model disposal leaves ${sameConversation ? 'replacement' : 'different'} chat active (oldFirst=$closeOldFirst)',
          (tester) async {
        await serviceLocator.unregister<TUIChatGlobalModel>();
        final global = TUIChatGlobalModel();
        serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
        global.configureMessageWriterScope(
            ownerUserID: 'owner-test',
            accountGeneration: 1,
            domainGeneration: 1);
        final old = _SilentReadModel()..suppressReadReporting = true;
        final active = _SilentReadModel()..suppressReadReporting = true;
        const first = '@TGS#owner-first';
        final second = sameConversation ? first : '@TGS#owner-second';
        old.initForEachConversation(ConvType.group, first, null);
        active.initForEachConversation(ConvType.group, second, null);
        await tester.pump();
        final leaving = closeOldFirst ? old : active;
        final survivor = closeOldFirst ? active : old;
        final survivorID = survivor.conversationID;
        global.setFollowingLatest(survivorID, false);
        global.beginHistoryReconciliation(
            conversationID: survivorID,
            requestedSource: MessageReconciliationSource.cloud,
            networkState: MessageReconciliationNetworkState.online);
        expect(global.hasActiveHistoryReconciliation(survivorID), isTrue);
        leaving.dispose();
        leaving.releaseCurrentConversation();
        expect(global.currentSelectedConv, survivorID);
        expect(global.isFollowingLatest(survivorID), isFalse,
            reason: 'late disposal cannot reset the surviving viewport');
        expect(global.hasActiveHistoryReconciliation(survivorID), isTrue,
            reason:
                'the surviving page must be allowed to publish its history');
        survivor.dispose();
        expect(global.currentSelectedConv, isEmpty);
        expect(global.hasActiveHistoryReconciliation(survivorID), isFalse);
        await tester.pump(const Duration(seconds: 2));
        global.dispose();
      });
    }
  }

  testWidgets(
      'disposing an unregistered preview model cannot release active chat',
      (tester) async {
    await serviceLocator.unregister<TUIChatGlobalModel>();
    final global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    final active = _SilentReadModel()..suppressReadReporting = true;
    active.initForEachConversation(ConvType.group, '@TGS#preview-owner', null);
    await tester.pump();
    final preview = _SilentReadModel()
      ..conversationID = '@TGS#preview-owner'
      ..conversationType = ConvType.group
      ..suppressReadReporting = true;
    preview.dispose();
    expect(global.currentSelectedConv, '@TGS#preview-owner');
    active.dispose();
    expect(global.currentSelectedConv, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    global.dispose();
  });
}
