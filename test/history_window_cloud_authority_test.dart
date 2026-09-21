import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _HistorySdk extends MessageService {
  List<V2TimMessage> rows = [];
  int calls = 0;
  int exactSeqFailuresRemaining = 0;
  final List<
      ({
        HistoryMsgGetTypeEnum getType,
        int lastMsgSeq,
        List<int>? messageSeqList,
      })> requests = [];
  Completer<void>? release;
  final entered = Completer<void>();
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
    requests.add((
      getType: getType,
      lastMsgSeq: lastMsgSeq,
      messageSeqList: messageSeqList == null
          ? null
          : List<int>.unmodifiable(messageSeqList),
    ));
    if (!entered.isCompleted) entered.complete();
    await release?.future;
    if (messageSeqList?.isNotEmpty == true && exactSeqFailuresRemaining > 0) {
      exactSeqFailuresRemaining--;
      return const MessageHistorySdkResult(
        code: 10004,
        desc: 'MsgSeqList is empty',
      );
    }
    return MessageHistorySdkResult(
        code: 0,
        desc: 'test',
        data: V2TimMessageListResult(isFinished: true, messageList: rows));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK ${invocation.memberName}');
}

V2TimMessage row(int id, {String? text}) => V2TimMessage.fromJson({
      'message_msg_id': 'm$id',
      'message_server_time': id,
      'message_risk_type_identified': 0,
    })
      ..userID = 'peer'
      ..seq = '$id'
      ..isSelf = false
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: text ?? 'original$id');

V2TimMessage groupRow(int id, {String? text}) => row(id, text: text)
  ..userID = null
  ..groupID = '@TGS#_gap-group';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  late TUIChatGlobalModel global;
  late _HistorySdk sdk;
  const conv = 'c2c_peer';
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory =
        await Directory.systemTemp.createTemp('history-cloud-authority-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _HistorySdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    global = TUIChatGlobalModel();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    global.configureMessageWriterScope(
        ownerUserID: 'owner', accountGeneration: 1, domainGeneration: 1);
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
  });
  tearDown(() async {
    global.invalidateBoundedHistorySessions();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  test(
      'real reconnect catch-up applies durable edit/delete after more than 512 facts and Writer reset',
      () async {
    global.setMessageList(conv, [row(100)], replace: true);
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm103',
        kind: HistoryWindowMutationKind.edit,
        message: row(103, text: 'authoritative edit'));
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm102',
        kind: HistoryWindowMutationKind.delete);
    for (var id = 200; id < 800; id++) {
      await global.recordHistoryWindowMutation(
          conversationID: conv,
          msgID: 'm$id',
          kind: HistoryWindowMutationKind.edit,
          message: row(id, text: 'fact$id'));
    }
    global.cancelHistoryReconciliation(conv);
    sdk.rows = [row(103), row(102), row(101)];
    await global.reconcileConversationCloud(conv, reason: 'reconnect');
    expect(sdk.calls, 1);
    final rows = global.rawMessageList(conv)!;
    expect(rows.map((m) => m.msgID), ['m103', 'm101', 'm100']);
    expect(rows.first.textElem!.text, 'authoritative edit');
    expect(global.messageWriterRetainedCountForTesting(conv), rows.length);
  });

  test(
      'inactive SDK warm preload applies durable facts before seeding raw and Writer',
      () async {
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm2',
        kind: HistoryWindowMutationKind.delete);
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm3',
        kind: HistoryWindowMutationKind.edit,
        message: row(3, text: 'fresh warm row'));
    sdk.rows = [row(3), row(2), row(1)];
    await global.preloadMessageForConversation(
        conversationType: ConvType.c2c, conversationID: 'peer');
    expect(sdk.calls, 1);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID), ['m3', 'm1']);
    expect(global.rawMessageList(conv)!.first.textElem!.text, 'fresh warm row');
  });

  test('late warm preload cannot cross account scope', () async {
    sdk.rows = [row(3)];
    sdk.release = Completer<void>();
    final load = global.preloadMessageForConversation(
        conversationType: ConvType.c2c, conversationID: 'peer');
    await sdk.entered.future;
    global.configureMessageWriterScope(
        ownerUserID: 'new-owner', accountGeneration: 2, domainGeneration: 1);
    sdk.release!.complete();
    await load;
    expect(sdk.calls, 1);
    expect(global.rawMessageCount(conv), 0);
    expect(global.messageWriterRetainedCountForTesting(conv), 0);
  });

  test('group gap exact lookup keeps newer direction and falls back to range',
      () async {
    const groupConv = '@TGS#_gap-group';
    sdk.exactSeqFailuresRemaining = 1;
    sdk.rows = <V2TimMessage>[groupRow(102)];

    global.setMessageList(
      groupConv,
      <V2TimMessage>[groupRow(103), groupRow(101)],
      replace: true,
    );
    await global.reconcileConversationCloud(
      groupConv,
      reason: 'seq_gap_101_103',
    );

    expect(sdk.requests, hasLength(2));
    expect(
      sdk.requests.first.getType,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
    );
    expect(sdk.requests.first.messageSeqList, <int>[102]);
    expect(sdk.requests.last.messageSeqList, isNull);
    expect(sdk.requests.last.lastMsgSeq, 101);
    expect(
      sdk.requests.last.getType,
      HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
    );
    expect(
      global.rawMessageList(groupConv)!.map((message) => message.seq),
      contains('102'),
    );
  });
}
