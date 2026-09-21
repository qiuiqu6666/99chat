import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
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

V2TimMessage _row(int seq, String conversationID) => V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
      'message_seq': '$seq',
      'message_conv_id': conversationID,
      'message_conv_type': 2,
      'message_server_time': seq,
      'message_risk_type_identified': 0,
    })
      ..groupID = conversationID
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'text$seq');

class _Sdk extends MessageService {
  final cursors = <int>[];
  final getTypes = <HistoryMsgGetTypeEnum>[];
  late Future<V2TimMessageListResult> Function(int cursor) history;
  Future<V2TimMessageListResult> Function(
      int cursor, HistoryMsgGetTypeEnum getType)? historyByType;

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
    final cursor = lastMsgSeq > 0
        ? lastMsgSeq
        : int.tryParse(
                (lastMsgID ?? lastMsg?.msgID ?? '').replaceFirst('m', '')) ??
            -1;
    cursors.add(cursor);
    getTypes.add(getType);
    return MessageHistorySdkResult(
        code: 0,
        desc: 'controlled SDK page',
        data: await (historyByType?.call(cursor, getType) ?? history(cursor)));
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
  String getConv() => model.conversationID;
  List<String?> currentIDs() => global
      .canonicalMessageWindow(getConv())
      .map((message) => message.msgID)
      .toList();
  V2TimMessageListResult page(Iterable<int> seqs) => V2TimMessageListResult(
      messageList: seqs.map((seq) => _row(seq, getConv())).toList(),
      isFinished: false);
  Future<bool> load() => model.loadChatRecord(
      count: 10,
      lastMsgID: 'm99',
      lastMsgSeq: 99,
      lastMsg: _row(99, getConv()));
  Future<void> deleteRows(Iterable<int> seqs) async {
    for (final seq in seqs) {
      await global.recordHistoryWindowMutation(
          conversationID: getConv(),
          msgID: 'm$seq',
          kind: HistoryWindowMutationKind.delete);
    }
  }

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory = await Directory.systemTemp.createTemp('filtered-sdk-page-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _Sdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(TUIChatGlobalModel());
    model = TUIChatSeparateViewModel()
      ..conversationID = '@TGS#${820000 + ++sequence}'
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.public
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    model.groupInfo = V2TimGroupInfo(groupID: getConv(), groupType: 'Public');
    global = model.globalModel;
    global.configureMessageWriterScope(
        ownerUserID: 'filtered-page-owner',
        accountGeneration: 100 + sequence,
        domainGeneration: 1);
    global.setMessageList(
        getConv(), [_row(100, getConv()), _row(99, getConv())],
        applyMemoryWindow: false);
  });

  tearDown(() async {
    // Let best-effort page persistence finish before deleting its database.
    for (var n = 0; n < 15; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    model.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  for (final community in [false, true]) {
    for (final filteredCount in [3, 8]) {
      test(
          'deleted $filteredCount-row ${community ? "Community" : "Public"} '
          'page advances once without a network loop', () async {
        if (community) model.groupType = GroupReceiptAllowType.community;
        final deleted = [
          for (var seq = 98; seq >= 99 - filteredCount; seq--) seq
        ];
        final next = deleted.last - 1;
        sdk.history = (cursor) async => page(cursor == 99
            ? deleted
            : cursor == deleted.last
                ? [next]
                : []);
        await deleteRows(deleted);

        expect(await load(), isFalse);
        expect(currentIDs(), ['m100', 'm99']);
        expect(sdk.cursors, [99], reason: 'Do not auto-scan filtered pages.');
        expect(await load(), isTrue);
        expect(sdk.cursors, [99, deleted.last]);
        expect(currentIDs(), ['m100', 'm99', 'm$next']);
      });
    }
  }

  test('lifecycle-filtered rows retain their SDK continuation boundary',
      () async {
    sdk.history = (cursor) async =>
        page(cursor == 99 ? [for (var seq = 98; seq >= 91; seq--) seq] : [90]);
    model.lifeCycle = ChatLifeCycle(
        didGetHistoricalMessageList: (messages) async => messages
            .where((message) => int.parse(message.seq!) >= 99)
            .toList());
    expect(await load(), isFalse);
    expect(currentIDs(), ['m100', 'm99']);
    expect(sdk.cursors, [99]);
    model.lifeCycle = null;
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 91]);
    expect(currentIDs(), ['m100', 'm99', 'm90']);
  });

  test('a repeated filtered page does not rewind or advance its cursor',
      () async {
    sdk.history = (_) async => page([98, 97, 96]);
    await deleteRows([98, 97, 96]);
    expect(await load(), isFalse);
    expect(await load(), isFalse);
    expect(await load(), isFalse);
    expect(sdk.cursors, [99, 96, 96]);
    expect(currentIDs(), ['m100', 'm99']);
  });

  test('C2C same-second filtered pages advance without trusting sender seq',
      () async {
    model.conversationType = ConvType.c2c;
    model.conversationID = 'filtered-c2c-$sequence';
    V2TimMessage c2cRow(int id) => _row(id, getConv())
      ..groupID = null
      ..userID = getConv()
      ..timestamp = 1000
      // A C2C sender's seq need not increase across the conversation.
      ..seq = '${1000 - id}';
    global.setMessageList(getConv(), [c2cRow(100), c2cRow(99)],
        replace: true, applyMemoryWindow: false);
    sdk.history = (cursor) async => V2TimMessageListResult(messageList: [
          for (final id in cursor == 99 ? [98, 97, 96] : [95]) c2cRow(id)
        ], isFinished: false);
    await deleteRows([98, 97, 96]);
    Future<bool> c2cLoad() =>
        model.loadChatRecord(count: 3, lastMsgID: 'm99', lastMsg: c2cRow(99));
    expect(await c2cLoad(), isFalse);
    expect(sdk.cursors, [99]);
    expect(await c2cLoad(), isTrue);
    expect(sdk.cursors, [99, 96]);
    expect(currentIDs().toSet(), {'m100', 'm99', 'm95'});
  });

  test('same-second C2C repeated filtered subsets cannot rewind the cursor',
      () async {
    model.conversationType = ConvType.c2c;
    model.conversationID = 'filtered-c2c-$sequence';
    V2TimMessage c2cRow(int id) => _row(id, getConv())
      ..groupID = null
      ..userID = getConv()
      ..timestamp = 1000
      ..seq = '${1000 - id}';
    global.setMessageList(getConv(), [c2cRow(100), c2cRow(99)],
        replace: true, applyMemoryWindow: false);
    sdk.history = (cursor) async => V2TimMessageListResult(messageList: [
          for (final id in cursor == 99 ? [98, 97, 96] : [98, 97]) c2cRow(id)
        ], isFinished: false);
    await deleteRows([98, 97, 96]);
    Future<bool> c2cLoad() =>
        model.loadChatRecord(count: 3, lastMsgID: 'm99', lastMsg: c2cRow(99));
    expect(await c2cLoad(), isFalse);
    expect(await c2cLoad(), isFalse);
    expect(await c2cLoad(), isFalse);
    expect(sdk.cursors, [99, 96, 96]);
    expect(currentIDs().toSet(), {'m100', 'm99'});
  });

  test('a partially deleted long page retains its visible older tail',
      () async {
    sdk.history = (_) async => page([for (var seq = 98; seq >= 91; seq--) seq]);
    await deleteRows([for (var seq = 98; seq >= 92; seq--) seq]);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99]);
    expect(currentIDs(), ['m100', 'm99', 'm91']);
  });

  test('a disconnected raw page cannot advance even when every row is deleted',
      () async {
    sdk.history = (_) async => page([70, 69]);
    await deleteRows([70, 69]);
    expect(await load(), isFalse);
    expect(await load(), isFalse);
    expect(sdk.cursors, [99, 99]);
    expect(currentIDs(), ['m100', 'm99']);
  });

  test('SDK local fallback retains the accepted filtered boundary', () async {
    final deleted = [for (var seq = 98; seq >= 91; seq--) seq];
    sdk.historyByType = (cursor, getType) async {
      if (cursor == 99) return page(deleted);
      return page(getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
          ? [90]
          : []);
    };
    await deleteRows(deleted);
    expect(await load(), isFalse);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 91, 91]);
    expect(sdk.getTypes, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    ]);
    expect(currentIDs(), ['m100', 'm99', 'm90']);
  });

  test('a visible group tail does not retry the same cloud cursor', () async {
    sdk.historyByType = (cursor, getType) async {
      if (cursor == 99) return page([98]);
      return page(getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG
          ? [97]
          : []);
    };
    expect(await load(), isTrue);
    // The model keeps seq + full anchor for the accepted group SDK tail.
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 98, 98]);
    expect(sdk.getTypes, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    ]);
    expect(currentIDs(), ['m100', 'm99', 'm98', 'm97']);
  });

  test('a genuinely different stale cursor still gets one recovery read',
      () async {
    sdk.history = (cursor) async => page(cursor == 101 ? [] : [98]);
    expect(
        await model.loadChatRecord(
            count: 10,
            lastMsgID: 'm101',
            lastMsgSeq: 101,
            lastMsg: _row(101, getConv())),
        isTrue);
    expect(sdk.cursors, [101, 99]);
    expect(sdk.getTypes,
        everyElement(HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG));
    expect(currentIDs(), ['m100', 'm99', 'm98']);
  });

  test('online local fallback records local provenance without cloud proof',
      () async {
    await global.ensureMessageHistoryCoverageLoaded(getConv());
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
    sdk.historyByType = (_, getType) async => page(
        getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG ? [98] : []);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 99]);
    expect(sdk.getTypes, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
    ]);
    final coverage = global.messageHistoryCoverageFor(getConv())!;
    expect(coverage.lastRequestedSource, 'cloud');
    expect(coverage.lastActualSource, 'local');
    expect(coverage.lastProofKind, MessageHistoryProofKind.none);
  });

  test('a failed local fallback remains retryable after a finished cloud page',
      () async {
    sdk.historyByType = (_, getType) async {
      if (getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG) {
        throw StateError('controlled local SDK failure');
      }
      return V2TimMessageListResult(messageList: [], isFinished: true);
    };
    expect(await load(), isFalse);
    expect(sdk.cursors, [99, 99]);
    expect(model.haveMoreData, isTrue);
    expect(currentIDs(), ['m100', 'm99']);
    sdk.historyByType = (_, __) async => page([98]);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 99, 99]);
    expect(currentIDs(), ['m100', 'm99', 'm98']);
  });

  test('a failed cloud read does not masquerade as an empty fallback',
      () async {
    sdk.history = (_) async => throw StateError('controlled cloud SDK failure');
    expect(await load(), isFalse);
    expect(sdk.getTypes, [HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG]);
    expect(model.haveMoreData, isTrue);
    expect(currentIDs(), ['m100', 'm99']);
  });

  test('empty fallback cooldown cannot turn a retry into end proof', () async {
    var finished = false;
    sdk.history = (_) async =>
        V2TimMessageListResult(messageList: [], isFinished: finished);
    expect(await load(), isFalse);
    expect(model.haveMoreData, isTrue);
    finished = true;
    expect(await load(), isFalse);
    expect(model.haveMoreData, isTrue);
    expect(sdk.getTypes, [
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
    ]);
  });

  test('a local fallback completing in an expired scope cannot commit',
      () async {
    final localStarted = Completer<void>();
    final localResponse = Completer<V2TimMessageListResult>();
    sdk.historyByType = (_, getType) async {
      if (getType == HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG) {
        localStarted.complete();
        return localResponse.future;
      }
      return page([]);
    };
    final pending = load();
    await localStarted.future;
    global.configureMessageWriterScope(
        ownerUserID: 'replacement-owner',
        accountGeneration: 9000 + sequence,
        domainGeneration: 1);
    localResponse.complete(page([98]));
    expect(await pending, isFalse);
    expect(currentIDs(), ['m100', 'm99']);
    sdk.historyByType = (_, __) async => page([98]);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 99, 99]);
    expect(currentIDs(), ['m100', 'm99', 'm98']);
  });

  test('duplicate-only pages retain the requested cursor', () async {
    sdk.history = (_) async => page([100, 99]);
    expect(await load(), isFalse);
    expect(await load(), isFalse);
    expect(sdk.cursors, [99, 99]);
    expect(currentIDs(), ['m100', 'm99']);
  });

  test('filtered wrong-direction rows cannot advance the cursor', () async {
    sdk.history = (_) async => page([101, 98, 97]);
    await deleteRows([101, 98, 97]);
    expect(await load(), isFalse);
    expect(await load(), isFalse);
    expect(sdk.cursors, [99, 99]);
    expect(currentIDs(), ['m100', 'm99']);
  });

  test('a scope invalidated during lifecycle cannot accept filtered progress',
      () async {
    sdk.history = (_) async => page([98, 97, 96]);
    model.lifeCycle =
        ChatLifeCycle(didGetHistoricalMessageList: (messages) async {
      global.configureMessageWriterScope(
          ownerUserID: 'replacement-owner',
          accountGeneration: 9000 + sequence,
          domainGeneration: 1);
      return messages
          .where((message) => int.parse(message.seq!) >= 99)
          .toList();
    });
    expect(await load(), isFalse);
    model.lifeCycle = null;
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 99]);
    expect(currentIDs(), ['m100', 'm99', 'm98', 'm97', 'm96']);
  });

  test('an SDK response from an expired window cannot advance its cursor',
      () async {
    final started = Completer<void>();
    final response = Completer<V2TimMessageListResult>();
    sdk.history = (_) {
      started.complete();
      return response.future;
    };
    final pending = load();
    await started.future;
    global.configureMessageWriterScope(
        ownerUserID: 'replacement-owner',
        accountGeneration: 9000 + sequence,
        domainGeneration: 1);
    response.complete(page([98, 97, 96]));
    expect(await pending, isFalse);
    sdk.history = (_) async => page([98, 97, 96]);
    expect(await load(), isTrue);
    expect(sdk.cursors, [99, 99]);
    expect(currentIDs(), ['m100', 'm99', 'm98', 'm97', 'm96']);
  });
}
