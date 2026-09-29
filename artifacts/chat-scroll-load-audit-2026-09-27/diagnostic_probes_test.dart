import 'dart:async';
import 'dart:convert';
import 'package:tencent_cloud_chat_demo/src/utils/call_bubble_dedupe.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
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
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
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


  test('AUDIT newer local fallback must keep cloud continuation eligible', () async {
    HistoryWindowRepositoryProvider.repository = null;
    model.haveMoreLatestData = true;
    global.appMessageReconciliationNetworkStateProvider = () => MessageReconciliationNetworkState.online;
    global.markMemoryWindowMissingNewer(getConv());
    model.freezeVisibleHistoryWindowIfNeeded();
    _Sdk.history = () async {
      if (_Sdk.historyTypes.last == HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG) {
        throw StateError('simulated cloud read failure');
      }
      return V2TimMessageListResult(isFinished: true,
          messageList: [for (var seq = 101; seq <= 105; seq++) row(seq, getConv())]);
    };
    await model.loadChatRecord(count: 20, direction: LoadDirection.latest,
        lastMsgID: 'm100', lastMsgSeq: 100, lastMsg: row(100, getConv()));
    print('AUDIT_NEWER types=${_Sdk.historyTypes} ids=${currentIDs()} '
        'haveMoreLatest=${model.haveMoreLatestData} knownTipMissing=${model.hasHistoryKnownTipMissing} missingNewer=${global.memoryWindowMissingNewer(getConv())}');
    expect(currentIDs(), contains('m105'));
    expect(model.haveMoreLatestData, isTrue,
        reason: 'A failed cloud read followed by a short local cache page does not prove cloud EOF.');
  });

  test('AUDIT lifecycle filtered cached older pages must advance beyond hidden page', () async {
    V2TimMessage inviteRow(int seq) => row(seq, getConv())
      ..elemType = 2
      ..textElem = null
      ..customElem = V2TimCustomElem(data: jsonEncode({
        'businessID':'lk_call','action':'invite','callId':'audit-invite-$seq',
        'callerId':'self_a','calleeId':'peer_a','mediaType':'video'}));
    final s = getScope();
    await store.savePage(HistoryWindowPage(scope: s, pageKey: 'root',
        messages: [row(100, getConv()), row(99, getConv())], olderPageKey: 'older'));
    await store.savePage(HistoryWindowPage(scope: s, pageKey: 'older',
        newerPageKey: 'root', olderPageKey: 'next',
        messages: [for (var seq=98; seq>=79; seq--) inviteRow(seq)]));
    await store.savePage(HistoryWindowPage(scope: s, pageKey: 'next',
        newerPageKey: 'older', messages: [row(78,getConv())]));
    model.lifeCycle = ChatLifeCycle(didGetHistoricalMessageList: (messages) async =>
        TUIChatGlobalModel.dedupeMessages(CallBubbleDedupe.normalizeCallHistoryMessages(messages,preserveTipIdentity:true)));
    final returns=<bool>[];
    for(var i=0;i<3;i++) {
      returns.add(await model.loadChatRecord(count: 20, lastMsgID: 'm99', lastMsgSeq: 99, lastMsg: row(99,getConv())));
    }
    print('AUDIT_CACHE returns=$returns ids=${currentIDs()} sdkCalls=${_Sdk.historyCalls}');
    expect(currentIDs(), contains('m78'), reason: 'All filtered cached rows must not trap the same visible cursor forever.');
  });

  test('AUDIT unavailable local database prevents both paging directions before SDK', () async {
    // Establish the real scope on disk, then emulate a foreground request while
    // the database is unavailable due to an app-lifecycle close.
    await store.savePage(HistoryWindowPage(scope:getScope(),pageKey:'root',
        messages:[row(100,getConv()),row(99,getConv())]));
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.forbidOpen();
    model.haveMoreLatestData=true;
    _Sdk.history=() async => V2TimMessageListResult(isFinished:false,
        messageList:[row(98,getConv())]);
    for(final direction in LoadDirection.values) {
      await model.loadChatRecord(count:20,direction:direction,
          lastMsgID:direction==LoadDirection.previous?'m99':'m100',
          lastMsgSeq:direction==LoadDirection.previous?99:100);
    }
    print('AUDIT_DB ids=${currentIDs()} sdkCalls=${_Sdk.historyCalls} '
        'loading=${model.isLoadingChatHistory} notice=${model.historyLoadNotice}');
    expect(_Sdk.historyCalls,0);
    expect(currentIDs(),['m100','m99']);
    expect(model.isLoadingChatHistory,isFalse);
    expect(model.historyLoadNotice,isNull);
    SqfliteLifecycleGuard.instance.resume();
    await model.loadChatRecord(count:20,lastMsgID:'m99',lastMsgSeq:99,lastMsg:row(99,getConv()));
    print('AUDIT_DB_RECOVERED ids=${currentIDs()} sdkCalls=${_Sdk.historyCalls} loading=${model.isLoadingChatHistory}');
    expect(_Sdk.historyCalls,greaterThan(0));
    expect(currentIDs(),contains('m98'));
    expect(model.isLoadingChatHistory,isFalse);
  });
}
