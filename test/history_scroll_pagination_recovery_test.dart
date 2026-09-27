import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_history_coverage.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _Sdk extends MessageService {
  late Future<V2TimMessageListResult> Function(HistoryMsgGetTypeEnum, int) read;
  final requests = <({HistoryMsgGetTypeEnum type, int seq})>[];

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
    requests.add((type: getType, seq: lastMsgSeq));
    return MessageHistorySdkResult(
        code: 0, desc: 'test page', data: await read(getType, lastMsgSeq));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var sequence = 0;
  late Directory directory;
  late HistoryWindowStore store;
  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late _Sdk sdk;
  String conv() => model.conversationID;
  List<String?> ids() =>
      global.messageListMap[conv()]!.map((message) => message.msgID).toList();
  V2TimMessage row(int seq) => V2TimMessage.fromJson({
        'message_msg_id': 'm$seq',
        'message_seq': '$seq',
        'message_conv_id': conv(),
        'message_conv_type': 2,
        'message_server_time': seq,
        'message_risk_type_identified': 0,
      })
        ..groupID = conv()
        ..status = 2
        ..elemType = 1
        ..textElem = V2TimTextElem(text: 'text$seq');
  V2TimMessage invite(int seq) => row(seq)
    ..elemType = 2
    ..textElem = null
    ..customElem = V2TimCustomElem(
        data: jsonEncode({
      'businessID': 'lk_call',
      'action': 'invite',
      'callId': 'invite-$seq',
      'callerId': 'self_a',
      'calleeId': 'peer_a',
      'mediaType': 'video',
    }));
  Future<bool> load(
          {int anchor = 99,
          LoadDirection direction = LoadDirection.previous,
          HistoryMsgGetTypeEnum? getType}) =>
      model.loadChatRecord(
          count: 20,
          lastMsgID: 'm$anchor',
          lastMsgSeq: anchor,
          lastMsg: row(anchor),
          direction: direction,
          getType: getType);
  void filterCalls() {
    model.lifeCycle = ChatLifeCycle(
        didGetHistoricalMessageList: (messages) async =>
            TUIChatGlobalModel.dedupeMessages(
                CallBubbleDedupe.normalizeCallHistoryMessages(messages,
                    preserveTipIdentity: true)));
  }

  Future<void> cacheHiddenPage({bool withNext = true}) async {
    final scope = global.historyWindowScopeFor(conv())!;
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'root',
        messages: [row(100), row(99)],
        olderPageKey: 'hidden'));
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'hidden',
        newerPageKey: 'root',
        olderPageKey: withNext ? 'next' : null,
        messages: [for (var seq = 98; seq >= 79; seq--) invite(seq)]));
    if (withNext) {
      await store.savePage(HistoryWindowPage(
          scope: scope,
          pageKey: 'next',
          newerPageKey: 'hidden',
          messages: [row(78)]));
    }
    filterCalls();
  }

  void prepareLatest() {
    HistoryWindowRepositoryProvider.repository = null;
    model.haveMoreLatestData = true;
    global.markMemoryWindowMissingNewer(conv());
    model.freezeVisibleHistoryWindowIfNeeded();
  }

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory = await Directory.systemTemp.createTemp('scroll-recovery-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _Sdk();
    sdk.read = (_, __) async => throw StateError('Unexpected history request');
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(TUIChatGlobalModel());
    model = TUIChatSeparateViewModel()
      ..conversationID = '@TGS#${810000 + ++sequence}'
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    model.groupInfo = V2TimGroupInfo(groupID: conv(), groupType: 'Community');
    global = model.globalModel;
    global.configureMessageWriterScope(
        ownerUserID: 'scroll-owner',
        accountGeneration: 100 + sequence,
        domainGeneration: 1);
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
    global.setMessageList(conv(), [row(100), row(99)],
        applyMemoryWindow: false);
    await global.ensureMessageHistoryCoverageLoaded(conv());
  });
  tearDown(() async {
    for (var n = 0; n < 15; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    model.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  for (final cloudFails in [true, false]) {
    test(
        'short local newer page stays retryable after cloud '
        '${cloudFails ? 'failure' : 'empty page'}', () async {
      prepareLatest();
      sdk.read = (type, _) async {
        if (type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG) {
          if (cloudFails) throw StateError('cloud unavailable');
          return V2TimMessageListResult(isFinished: true, messageList: []);
        }
        return V2TimMessageListResult(
            isFinished: true,
            messageList: [for (var seq = 101; seq <= 105; seq++) row(seq)]);
      };
      await load(anchor: 100, direction: LoadDirection.latest);
      expect(ids(), contains('m105'));
      expect(model.haveMoreLatestData, isTrue);
      expect(global.memoryWindowMissingNewer(conv()), isTrue);
      final coverage = global.messageHistoryCoverageFor(conv())!;
      expect(coverage.lastRequestedSource, 'cloud');
      expect(coverage.lastActualSource, 'local');
      expect(coverage.lastProofKind, MessageHistoryProofKind.none);

      sdk.read = (type, anchor) async {
        expect(type, HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG);
        expect(anchor, 105);
        return V2TimMessageListResult(
            isFinished: true, messageList: [row(106)]);
      };
      await load(anchor: 105, direction: LoadDirection.latest);
      expect(ids(), contains('m106'));
      expect(model.haveMoreLatestData, isFalse);
      expect(
          global.messageHistoryCoverageFor(conv())!.lastActualSource, 'cloud');
    });
  }

  test('empty local fallback after cloud failure is not remote exhaustion',
      () async {
    prepareLatest();
    sdk.read = (type, _) async {
      if (type == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG) {
        throw StateError('cloud unavailable');
      }
      return V2TimMessageListResult(isFinished: true, messageList: []);
    };
    await load(anchor: 100, direction: LoadDirection.latest);
    expect(model.haveMoreLatestData, isTrue);
    expect(global.memoryWindowMissingNewer(conv()), isTrue);
    expect(global.messageHistoryCoverageFor(conv())!.lastActualSource, 'local');
    expect(ids(), ['m100', 'm99']);
  });

  test('confirmed cloud empty end still finishes catch-up', () async {
    prepareLatest();
    sdk.read = (_, __) async =>
        V2TimMessageListResult(isFinished: true, messageList: []);
    await load(anchor: 100, direction: LoadDirection.latest);
    expect(model.haveMoreLatestData, isFalse);
    expect(global.messageHistoryCoverageFor(conv())!.lastActualSource, 'cloud');
  });

  test('explicit local newer end also preserves cloud continuation', () async {
    prepareLatest();
    sdk.read = (_, __) async =>
        V2TimMessageListResult(isFinished: true, messageList: [row(101)]);
    await load(
        anchor: 100,
        direction: LoadDirection.latest,
        getType: HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_NEWER_MSG);
    expect(model.haveMoreLatestData, isTrue);
    expect(global.memoryWindowMissingNewer(conv()), isTrue);
  });

  test('hidden cached page advances without phantom scroll growth', () async {
    await cacheHiddenPage();
    expect(await load(), isFalse);
    expect(ids(), ['m100', 'm99']);
    expect(await load(), isTrue);
    expect(ids(), ['m100', 'm99', 'm78']);
    expect(sdk.requests, isEmpty);
    expect(model.haveMoreData, isTrue);
  });

  test('cache miss after hidden page permits repeated SDK recovery', () async {
    await cacheHiddenPage(withNext: false);
    expect(await load(), isFalse);
    // First network attempt fails. Its retry must not rewind the cache scan.
    expect(await load(), isFalse);
    expect(sdk.requests, isNotEmpty);
    final failedRequests = sdk.requests.length;
    sdk.read = (_, __) async =>
        V2TimMessageListResult(isFinished: false, messageList: [row(98)]);
    expect(await load(), isTrue);
    expect(sdk.requests.length, greaterThan(failedRequests));
    expect(ids(), contains('m98'));
  });

  test('hidden cached newer page preserves the cursor for visible newer rows',
      () async {
    final scope = global.historyWindowScopeFor(conv())!;
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'root',
        messages: [row(100), row(99)],
        newerPageKey: 'hidden'));
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'hidden',
        olderPageKey: 'root',
        newerPageKey: 'next',
        messages: [for (var seq = 120; seq >= 101; seq--) invite(seq)]));
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'next',
        olderPageKey: 'hidden',
        messages: [row(121)]));
    filterCalls();
    model.haveMoreLatestData = true;
    model.freezeVisibleHistoryWindowIfNeeded();
    expect(await load(anchor: 100, direction: LoadDirection.latest), isFalse);
    expect(ids(), ['m100', 'm99']);
    expect(await load(anchor: 100, direction: LoadDirection.latest), isTrue);
    expect(ids(), ['m121', 'm100', 'm99']);
    expect(sdk.requests, isEmpty);
    expect(model.haveMoreLatestData, isTrue);
  });

  test('rejected lifecycle page is retried before advancing cache cursor',
      () async {
    await cacheHiddenPage();
    var lifecycleCalls = 0;
    model.lifeCycle =
        ChatLifeCycle(didGetHistoricalMessageList: (messages) async {
      lifecycleCalls++;
      if (lifecycleCalls == 1) throw StateError('temporary lifecycle failure');
      return messages;
    });
    expect(await load(), isFalse);
    expect(ids(), ['m100', 'm99']);
    expect(await load(), isTrue);
    expect(ids(), containsAll(['m98', 'm79']));
    expect(ids(), isNot(contains('m78')));
    expect(sdk.requests, isEmpty);
  });
}
