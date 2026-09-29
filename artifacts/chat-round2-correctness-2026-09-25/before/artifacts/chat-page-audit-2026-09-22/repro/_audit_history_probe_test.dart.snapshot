import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/archive_history_provider.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

V2TimMessage row(int seq, String conv, {String? text}) =>
    V2TimMessage.fromJson({
      'message_msg_id': 'm$seq',
      'message_seq': '$seq',
      'message_conv_id': conv,
      'message_conv_type': 2,
      'message_server_time': seq,
      'message_risk_type_identified': 0,
    })
      ..groupID = conv
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: text ?? 'text$seq');

class _RollbackPauseStore extends HistoryWindowStore {
  _RollbackPauseStore({required super.debugDatabasePath});
  bool interruptRollbackRead = false;
  bool _closeNextRead = false;
  bool _holdResumedRead = false;
  void Function()? invalidateNextRollbackScope;
  bool _invalidateNextRead = false;
  final pausedAfterRestore = Completer<void>();
  final resumedRead = Completer<void>();
  final allowResumedRead = Completer<void>();

  @override
  Future<void> recordMutation(HistoryWindowMutation mutation) async {
    await super.recordMutation(mutation);
    if (mutation.kind == HistoryWindowMutationKind.restore &&
        invalidateNextRollbackScope != null) {
      _invalidateNextRead = true;
    }
    if (interruptRollbackRead &&
        mutation.kind == HistoryWindowMutationKind.restore) {
      interruptRollbackRead = false;
      _closeNextRead = true;
    }
  }

  @override
  Future<List<V2TimMessage>> applyMutations(
      {required HistoryWindowScope scope,
      required List<V2TimMessage> messages}) async {
    if (_invalidateNextRead) {
      _invalidateNextRead = false;
      final invalidate = invalidateNextRollbackScope;
      invalidateNextRollbackScope = null;
      invalidate!();
    }
    if (_closeNextRead) {
      _closeNextRead = false;
      _holdResumedRead = true;
      await SqfliteLifecycleHost.handle(AppLifecycleState.inactive);
      await closeIfOpen();
      SqfliteLifecycleGuard.instance.forbidOpen();
      // The real Store now raises SqfliteClosedForBackground on this read.
      try {
        return await super.applyMutations(scope: scope, messages: messages);
      } on SqfliteClosedForBackground {
        pausedAfterRestore.complete();
        rethrow;
      }
    }
    if (_holdResumedRead) {
      _holdResumedRead = false;
      resumedRead.complete();
      await allowResumedRead.future;
    }
    return super.applyMutations(scope: scope, messages: messages);
  }
}

class _Sdk extends MessageService {
  static Future<V2TimMessageListResult> Function()? history;
  static int historyCalls = 0;
  static final cursorCalls = <int>[];
  static Future<V2TimMessageListResult> Function(int cursor)? cursorHistory;
  static final historyTypes = <HistoryMsgGetTypeEnum>[];
  final completion = Completer<int>();
  int calls = 0;
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
    historyCalls++;
    historyTypes.add(getType);
    if (cursorHistory != null) {
      final cursor = lastMsgSeq > 0 ? lastMsgSeq : int.tryParse((lastMsgID ?? lastMsg?.msgID ?? '').replaceFirst('m', '')) ?? -1;
      cursorCalls.add(cursor);
      return MessageHistorySdkResult(code: 0, desc: 'audit cursor page', data: await cursorHistory!(cursor));
    }
    if (history == null) throw StateError('Unexpected SDK history call');
    return MessageHistorySdkResult(
        code: 0, desc: 'fake page', data: await history!());
  }

  @override
  Future<V2TimMessageListResult?> getHistoryMessageListWithComplete({
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
    historyCalls++;
    historyTypes.add(getType);
    if (history == null)
      throw StateError('Unexpected SDK complete history call');
    if (cursorHistory != null) {
      final cursor = lastMsgSeq > 0 ? lastMsgSeq : int.tryParse((lastMsgID ?? lastMsg?.msgID ?? '').replaceFirst('m', '')) ?? -1;
      cursorCalls.add(cursor);
      return cursorHistory!(cursor);
    }
    return history!();
  }

  @override
  Future<V2TimCallback> deleteMessages(
      {required List<String> msgIDs,
      List<dynamic>? webMessageInstanceList}) async {
    calls++;
    return V2TimCallback(code: await completion.future, desc: 'fake delete');
  }

  V2TimMessage? lastRevokeMessage;

  @override
  Future<V2TimCallback> revokeMessage(
      {required String msgID,
      Object? webMessageInstance,
      V2TimMessage? message}) async {
    calls++;
    lastRevokeMessage = message;
    return V2TimCallback(code: await completion.future, desc: 'fake revoke');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SDK call ${invocation.memberName}');
}

class _LatestModel extends TUIChatSeparateViewModel {
  bool succeed = true;
  Future<void> Function()? duringReload;
  @override
  Future<bool> loadChatRecord(
      {HistoryMsgGetTypeEnum? getType,
      int lastMsgSeq = -1,
      required int count,
      String? lastMsgID,
      V2TimMessage? lastMsg,
      LoadDirection direction = LoadDirection.previous,
      bool forceReloadNewest = false}) async {
    expect(forceReloadNewest, isTrue);
    await duringReload?.call();
    if (succeed)
      globalModel.setMessageList(conversationID, [row(999, conversationID)],
          replace: true);
    return succeed;
  }
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
  late _RollbackPauseStore store;
  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late _Sdk sdk;
  String getConv() => model.conversationID;
  HistoryWindowScope getScope() => global.historyWindowScopeFor(getConv())!;
  List<String?> currentIDs() =>
      global.messageListMap[getConv()]!.map((m) => m.msgID).toList();
  Future<void> settle() async {
    for (var n = 0; n < 15; n++)
      await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  setUp(() async {
    _Sdk.history = null;
    _Sdk.historyCalls = 0;
    _Sdk.historyTypes.clear();
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    SqfliteLifecycleHost.debugReset();
    directory = await Directory.systemTemp.createTemp('pagination-real-db-');
    store =
        _RollbackPauseStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _Sdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    // Global captures MessageService at construction, so inject before making
    // the real coordinator rather than leaving its original native service.
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(TUIChatGlobalModel());
    model = TUIChatSeparateViewModel()
      // Numeric group IDs exercise both public and Community SDK routing with
      // the same real model; neither group type uses a separate history store.
      ..conversationID = '@TGS#${800000 + ++sequence}'
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    model.groupInfo =
        V2TimGroupInfo(groupID: getConv(), groupType: 'Community');
    global = model.globalModel;
    global.configureMessageWriterScope(
        ownerUserID: 'pagination-owner',
        accountGeneration: 100 + sequence,
        domainGeneration: 1);
    global.setMessageList(getConv(), [row(100, getConv()), row(99, getConv())],
        applyMemoryWindow: false);
  });
  tearDown(() async {
    if (!store.allowResumedRead.isCompleted) store.allowResumedRead.complete();
    await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
    if (!sdk.completion.isCompleted) sdk.completion.complete(0);
    await settle();
    model.dispose();
    ArchiveHistoryProvider.register(null);
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });
  test('AUDIT a fully tombstoned SDK page must not hide valid older history', () async {
    model.groupType = GroupReceiptAllowType.public;
    _Sdk.cursorCalls.clear();
    _Sdk.history = () async => V2TimMessageListResult(messageList: [], isFinished: true);
    _Sdk.cursorHistory = (cursor) async => V2TimMessageListResult(
      messageList: cursor == 99
          ? [row(98, getConv()), row(97, getConv()), row(96, getConv())]
          : cursor == 96 ? [row(95, getConv())] : [],
      isFinished: false,
    );
    for (final seq in [98, 97, 96]) {
      await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm$seq',
        kind: HistoryWindowMutationKind.delete,
      );
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      await model.loadChatRecord(
        count: 3,
        lastMsgID: 'm99',
        lastMsgSeq: 99,
        lastMsg: global.messageListMap[getConv()]!.last,
      );
    }
    print('AUDIT SDK cursors=${_Sdk.cursorCalls} visible=${currentIDs()} availability=${model.historyAvailability}');
    expect(currentIDs(), contains('m95'),
      reason: 'The raw SDK page 98..96 is intentionally deleted; its older cursor must advance to retrieve visible m95.');
  });
}
