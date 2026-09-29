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

  test(
      'cache hit applies durable edit/delete and commits through live Writer without SDK',
      () async {
    final s = getScope();
    await store.savePage(HistoryWindowPage(
        scope: s,
        pageKey: 'current',
        messages: [row(100, getConv()), row(99, getConv())],
        olderPageKey: 'older',
        snapshotMaxSeq: 100));
    await store.savePage(HistoryWindowPage(
        scope: s,
        pageKey: 'older',
        newerPageKey: 'current',
        messages: [row(98, getConv()), row(97, getConv()), row(96, getConv())],
        snapshotMaxSeq: 100));
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm98',
        kind: HistoryWindowMutationKind.delete);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm97',
        kind: HistoryWindowMutationKind.edit,
        message: row(97, getConv(), text: 'edited'));
    expect(
        await model.loadChatRecord(count: 50, lastMsgID: 'm99', lastMsgSeq: 99),
        isTrue);
    expect(currentIDs(), ['m100', 'm99', 'm97', 'm96']);
    expect(global.getMessageList(getConv())![2].textElem!.text, 'edited');
    expect(sdk.calls, 0);
    expect(global.hasActiveHistoryReconciliation(getConv()), isFalse);
  });

  test('ordinary SDK page applies persistent facts before reconciliation',
      () async {
    model.groupType = GroupReceiptAllowType.public;
    final originalPage = [
      row(98, getConv()),
      row(97, getConv()),
      row(96, getConv())
    ];
    _Sdk.history = () async =>
        V2TimMessageListResult(messageList: originalPage, isFinished: false);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm98',
        kind: HistoryWindowMutationKind.delete);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm97',
        kind: HistoryWindowMutationKind.edit,
        message: row(97, getConv(), text: 'durable-sdk-edit'));
    expect(
        await model.loadChatRecord(
            count: 50,
            lastMsgID: 'm99',
            lastMsgSeq: 99,
            lastMsg: global.messageListMap[getConv()]!.last),
        isTrue);
    expect(_Sdk.historyCalls, greaterThan(0));
    expect(currentIDs(), ['m100', 'm99', 'm97', 'm96']);
    expect(global.messageListMap[getConv()]![2].textElem!.text,
        'durable-sdk-edit');
  });

  for (final official in [true, false]) {
    test(
        'peek uses SDK cloud history for every group type and applies durable facts',
        () async {
      model.groupType = official
          ? GroupReceiptAllowType.public
          : GroupReceiptAllowType.community;
      final raw = [row(98, getConv()), row(97, getConv()), row(96, getConv())];
      _Sdk.history = () async =>
          V2TimMessageListResult(messageList: raw, isFinished: true);
      await global.recordHistoryWindowMutation(
          conversationID: getConv(),
          msgID: 'm98',
          kind: HistoryWindowMutationKind.delete);
      await global.recordHistoryWindowMutation(
          conversationID: getConv(),
          msgID: 'm97',
          kind: HistoryWindowMutationKind.edit,
          message: row(97, getConv(), text: 'peek durable edit'));
      model.lifeCycle =
          ChatLifeCycle(didGetHistoricalMessageList: (messages) async {
        expect(messages.map((m) => m.msgID), isNot(contains('m98')));
        // A lifecycle extension may replay a stale raw row. Publication must
        // reapply facts to its output as well as the transport response.
        return [...messages, row(98, getConv())];
      });
      final page = await model.loadHistoryPeekStyle(
          count: 3, scheduleWindowReconcile: false);
      expect(page.map((m) => m.msgID).toSet(), {'m97', 'm96'});
      expect(page.firstWhere((m) => m.msgID == 'm97').textElem!.text,
          'peek durable edit');
      expect(raw.map((m) => m.msgID), ['m98', 'm97', 'm96']);
      // Community and ordinary groups share the SDK history lane.  The group
      // receipt type still changes message semantics, but it must not select a
      // second local-then-cloud history pipeline.
      expect(_Sdk.historyTypes,
          contains(HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG));
      expect(_Sdk.historyTypes,
          isNot(contains(HistoryMsgGetTypeEnum.V2TIM_GET_LOCAL_OLDER_MSG)));
    });
  }

  test('hydrate after empty Writer window cannot revive durable deletion',
      () async {
    model.groupType = GroupReceiptAllowType.public;
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm98',
        kind: HistoryWindowMutationKind.delete);
    global.setMessageList(getConv(), [],
        replace: true, applyMemoryWindow: false);
    _Sdk.history = () async => V2TimMessageListResult(messageList: [
          row(98, getConv()),
          row(97, getConv()),
          row(96, getConv())
        ], isFinished: true);
    expect(
        await model.hydrateInitialHistoryPeekStyle(
            count: 3, retryDelays: [Duration.zero]),
        isTrue);
    expect(currentIDs(), ['m97', 'm96']);
    expect(_Sdk.historyCalls, greaterThan(0));
  });

  test('warm hydrate early return refreshes facts without SDK refetch',
      () async {
    model.groupType = GroupReceiptAllowType.public;
    global.setMessageList(getConv(),
        [row(100, getConv()), row(99, getConv()), row(98, getConv())],
        replace: true);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm100',
        kind: HistoryWindowMutationKind.delete);
    expect(
        await model.hydrateInitialHistoryPeekStyle(count: 1, plainOpen: true),
        isTrue);
    expect(currentIDs(), ['m99', 'm98']);
    expect(_Sdk.historyCalls, 0);
  });

  test(
      'search around applies durable delete edit and rejects stale lifecycle rows',
      () async {
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm98',
        kind: HistoryWindowMutationKind.delete);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm97',
        kind: HistoryWindowMutationKind.edit,
        message: row(97, getConv(), text: 'search durable edit'));
    _Sdk.history = () async => V2TimMessageListResult(messageList: [
          row(98, getConv()),
          row(97, getConv()),
          row(96, getConv())
        ], isFinished: true);
    model.lifeCycle = ChatLifeCycle(
        didGetHistoricalMessageList: (messages) async =>
            [...messages, row(98, getConv())]);
    expect(
        await model.loadListForSpecificMessage(
            seq: 97, targetMessage: row(97, getConv())),
        isTrue);
    expect(currentIDs(), ['m97', 'm96']);
    expect(global.messageListMap[getConv()]!.first.textElem!.text,
        'search durable edit');
    expect(
        _Sdk.historyTypes,
        containsAll([
          HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
          HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG
        ]));
    expect(
        await model.loadListForSpecificMessage(
            seq: 98, targetMessage: row(98, getConv())),
        isFalse);
    expect(currentIDs(), ['m97', 'm96']);
  });

  for (final search in [false, true]) {
    test(
        '${search ? "search" : "hydrate"} cannot publish after lifecycle changes owner scope',
        () async {
      _Sdk.history = () async => V2TimMessageListResult(
          messageList: [row(98, getConv()), row(97, getConv())],
          isFinished: true);
      model.lifeCycle =
          ChatLifeCycle(didGetHistoricalMessageList: (messages) async {
        global.configureMessageWriterScope(
            ownerUserID: 'next-owner',
            accountGeneration: 9000 + sequence,
            domainGeneration: 1);
        global.setMessageList(getConv(), [row(777, getConv())], replace: true);
        return messages;
      });
      final accepted = search
          ? await model.loadListForSpecificMessage(
              seq: 97, targetMessage: row(97, getConv()))
          : await model.hydrateInitialHistoryPeekStyle(
              count: 3, retryDelays: [Duration.zero]);
      expect(accepted, isFalse);
      expect(currentIDs(), ['m777']);
    });
  }

  test('cache page rechecks capacity after asynchronous lifecycle work',
      () async {
    final s = getScope();
    await store.savePages([
      HistoryWindowPage(
          scope: s,
          pageKey: 'cap-head',
          messages: [row(100, getConv()), row(99, getConv())],
          olderPageKey: 'cap-older',
          snapshotMaxSeq: 100),
      HistoryWindowPage(
          scope: s,
          pageKey: 'cap-older',
          messages: [row(98, getConv())],
          newerPageKey: 'cap-head',
          snapshotMaxSeq: 100),
    ]);
    model.lifeCycle =
        ChatLifeCycle(didGetHistoricalMessageList: (messages) async {
      global.setMessageList(getConv(),
          [for (var seq = 1000; seq > 450; seq--) row(seq, getConv())],
          replace: true, applyMemoryWindow: false);
      return messages;
    });
    expect(
        await model.loadChatRecord(count: 50, lastMsgID: 'm99', lastMsgSeq: 99),
        isFalse);
    expect(global.rawMessageCount(getConv()), 550);
    expect(currentIDs().first, 'm1000');
    expect(global.hasActiveHistoryReconciliation(getConv()), isFalse);
  });

  test('empty SDK newest response cannot acknowledge or replace the old window',
      () async {
    model.groupType = GroupReceiptAllowType.public;
    _Sdk.history =
        () async => V2TimMessageListResult(messageList: [], isFinished: true);
    final oldScope = getScope();
    await store.appendDeferred(
        scope: oldScope,
        eventID: 'unacknowledged',
        ingressSequence: 1,
        message: row(101, getConv()));
    expect(
        await model.reloadNewestMessageWindow(allowWhileReadingHistory: true),
        isFalse);
    expect(_Sdk.historyCalls, greaterThan(0));
    expect(currentIDs(), ['m100', 'm99']);
    expect((await store.deferredState(oldScope)).receivedCount, 1);
    expect(getScope().sessionID, oldScope.sessionID);
  });

  test(
      'deleted cache pages advance bounded raw continuation before visible rows resume',
      () async {
    global.setMessageList(getConv(), [row(1000, getConv())],
        replace: true, applyMemoryWindow: false);
    final s = getScope();
    await store.savePage(HistoryWindowPage(
        scope: s,
        pageKey: 'head',
        messages: [row(1000, getConv())],
        olderPageKey: 'p0',
        snapshotMaxSeq: 1000));
    for (var index = 0; index < 5; index++) {
      final end = 999 - 50 * index;
      await store.savePage(HistoryWindowPage(
          scope: s,
          pageKey: 'p$index',
          messages: [
            for (var seq = end; seq > end - 50; seq--) row(seq, getConv())
          ],
          newerPageKey: index == 0 ? 'head' : 'p${index - 1}',
          olderPageKey: index == 4 ? null : 'p${index + 1}',
          snapshotMaxSeq: 1000));
    }
    for (var seq = 999; seq >= 800; seq--) {
      await global.recordHistoryWindowMutation(
          conversationID: getConv(),
          msgID: 'm$seq',
          kind: HistoryWindowMutationKind.delete);
    }
    expect(
        await model.loadChatRecord(
            count: 50, lastMsgID: 'm1000', lastMsgSeq: 1000),
        isFalse);
    expect(currentIDs(), ['m1000']);
    expect(
        await model.loadChatRecord(
            count: 50, lastMsgID: 'm1000', lastMsgSeq: 1000),
        isTrue);
    expect(
        currentIDs().skip(1), [for (var seq = 799; seq >= 750; seq--) 'm$seq']);
    expect(sdk.calls, 0);
  });

  test('local injected tips cannot replace the concrete cache boundary',
      () async {
    final tip = row(10000, getConv())
      ..msgID = 'ce_local_tip'
      ..seq = null
      ..elemType = 11;
    global.setMessageList(
        getConv(), [tip, row(100, getConv()), row(99, getConv())],
        replace: true, applyMemoryWindow: false);
    model.haveMoreLatestData = true;
    final s = getScope();
    await store.savePages([
      HistoryWindowPage(
          scope: s,
          pageKey: 'tip-current',
          messages: [row(100, getConv()), row(99, getConv())],
          newerPageKey: 'tip-newer',
          snapshotMaxSeq: 102),
      HistoryWindowPage(
          scope: s,
          pageKey: 'tip-newer',
          messages: [row(102, getConv()), row(101, getConv())],
          olderPageKey: 'tip-current',
          snapshotMaxSeq: 102),
    ]);
    expect(
        await model.loadChatRecord(
            count: 50,
            lastMsgID: 'm100',
            lastMsgSeq: 100,
            direction: LoadDirection.latest),
        isTrue);
    expect(currentIDs(), containsAll(['m102', 'm101', 'm100', 'm99']));
    expect(sdk.calls, 0);
  });

  for (final laterDelete in [false, true]) {
    test('delete failure restores only its token (later delete=$laterDelete)',
        () async {
      final original = row(100, getConv());
      await model.deleteMsg('m100');
      expect(currentIDs(), ['m99']);
      expect(
          await store.applyMutations(scope: getScope(), messages: [original]),
          isEmpty);
      if (laterDelete)
        await global.recordHistoryWindowMutation(
            conversationID: getConv(),
            msgID: 'm100',
            kind: HistoryWindowMutationKind.delete,
            eventID: 'later-delete');
      sdk.completion.complete(1);
      await settle();
      final restored =
          await store.applyMutations(scope: getScope(), messages: [original]);
      expect(restored.isEmpty, laterDelete);
      expect(currentIDs().contains('m100'), !laterDelete);
    });
  }

  test(
      'selected delete persists independent tokens and rolls back both on SDK failure',
      () async {
    for (final message in global.getMessageList(getConv())!)
      model.setMessageItemChecked(message, true);
    await model.deleteSelectedMsg();
    expect(currentIDs(), isEmpty);
    sdk.completion.complete(1);
    await settle();
    expect(currentIDs(), ['m100', 'm99']);
    expect(
        (await store.applyMutations(
            scope: getScope(),
            messages: [row(100, getConv()), row(99, getConv())])),
        hasLength(2));
  });

  test('failed revoke cannot restore a message deleted after optimistic revoke',
      () async {
    await model.revokeMsg('m100', false);
    await global.recordHistoryWindowMutation(
        conversationID: getConv(),
        msgID: 'm100',
        kind: HistoryWindowMutationKind.delete,
        eventID: 'later-delete');
    sdk.completion.complete(1);
    await settle();
    expect(
        await store
            .applyMutations(scope: getScope(), messages: [row(100, getConv())]),
        isEmpty);
    expect(global.getMessageList(getConv())!.first.status, isNot(2));
  });

  for (final revoke in [false, true]) {
    test(
        'SDK failure reverses durable ${revoke ? 'revoke' : 'delete'} after route and session eviction',
        () async {
      final oldConv = getConv();
      final oldScope = getScope();
      if (revoke)
        await model.revokeMsg('m100', false);
      else
        await model.deleteMsg('m100');
      model.conversationID = '@TGS#another-route';
      for (var index = 0; index < 5; index++)
        global.historyWindowScopeFor('@TGS#evict-$index');
      expect(global.isHistoryWindowScopeCurrent(oldScope), isFalse);
      sdk.completion.complete(1);
      await settle();
      final reopened = global.historyWindowScopeFor(oldConv)!;
      final restored = await store
          .applyMutations(scope: reopened, messages: [row(100, oldConv)]);
      expect(restored, hasLength(1));
      expect(restored.single.status, 2);
      // The inactive raw window is reused on a later open. Undo must repair
      // its own optimistic publication as well as the durable token.
      final warm = global.canonicalMessageWindow(oldConv);
      expect(warm.map((m) => m.msgID), contains('m100'));
      expect(warm.firstWhere((m) => m.msgID == 'm100').status, 2);
    });
  }

  for (final revoke in [false, true]) {
    test(
        'late failed ${revoke ? "revoke" : "delete"} does not append into a replacement window',
        () async {
      final oldConv = getConv();
      if (revoke) {
        await model.revokeMsg('m100', false);
      } else {
        await model.deleteMsg('m100');
      }
      global.setMessageList(oldConv, [row(50, oldConv)], replace: true);
      model.conversationID = '@TGS#another-route';
      for (var index = 0; index < 5; index++) {
        global.historyWindowScopeFor('@TGS#new-window-evict-$index');
      }
      sdk.completion.complete(1);
      await settle();
      expect(
          global.canonicalMessageWindow(oldConv).map((m) => m.msgID), ['m50']);
      final restored = await store.applyMutations(
          scope: global.historyWindowScopeFor(oldConv)!,
          messages: [row(100, oldConv)]);
      expect(restored.single.status, 2);
    });
  }

  test('late failed revoke cannot overwrite a newer same-ID message object',
      () async {
    final oldConv = getConv();
    await model.revokeMsg('m100', false);
    final newVersion = row(100, oldConv, text: 'new authoritative row');
    global.releaseMessageDeltaTombstones(oldConv, ['m100']);
    global.restoreMessageDeltaAfterDeleteFailure(oldConv, [newVersion]);
    model.conversationID = '@TGS#another-route';
    sdk.completion.complete(1);
    await settle();
    final current = global
        .canonicalMessageWindow(oldConv)
        .firstWhere((m) => m.msgID == 'm100');
    expect(current.textElem!.text, 'new authoritative row');
    expect(identical(current, newVersion), isTrue);
  });

  for (final revoke in [false, true]) {
    test(
        'failed ${revoke ? "revoke" : "delete"} retains trim guard across rollback read background close',
        () async {
      final conv = getConv();
      global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
      global.setMessageList(
          conv, [for (var seq = 260; seq > 0; seq--) row(seq, conv)],
          replace: true, applyMemoryWindow: false);
      store.interruptRollbackRead = true;
      if (revoke) {
        await model.revokeMsg('m250', false);
      } else {
        await model.deleteMsg('m250');
      }
      sdk.completion.complete(1);
      await store.pausedAfterRestore.future.timeout(const Duration(seconds: 3));
      expect(store.isOpenForTesting, isFalse);
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
      await store.resumedRead.future.timeout(const Duration(seconds: 3));
      expect(
          await global.prepareHistoryWindowTrim(
              conversationID: conv, anchorMsgID: 'm50'),
          isNull);
      if (revoke) {
        expect(
            global
                .canonicalMessageWindow(conv)
                .firstWhere((m) => m.msgID == 'm250')
                .status,
            isNot(2));
      } else {
        expect(global.canonicalMessageWindow(conv).map((m) => m.msgID),
            isNot(contains('m250')));
      }
      store.allowResumedRead.complete();
      await settle();
      expect(
          global
              .canonicalMessageWindow(conv)
              .firstWhere((m) => m.msgID == 'm250')
              .status,
          2);
      final ticket = await global.prepareHistoryWindowTrim(
          conversationID: conv, anchorMsgID: 'm50');
      expect(ticket, isNotNull);
      expect(global.commitHistoryWindowTrim(ticket!), isTrue);
      global.finishHistoryWindowTrim(ticket);
      final page = await store.readAdjacent(
          scope: getScope(),
          boundary: const HistoryWindowBoundary(msgID: 'm249', seq: '249'),
          direction: HistoryWindowDirection.newer);
      expect(page.messages.firstWhere((m) => m.msgID == 'm250').status, 2);
    });
  }

  for (final revoke in [false, true]) {
    test(
        'failed ${revoke ? "revoke" : "delete"} retries facts after same-owner LRU scope eviction',
        () async {
      final oldScope = getScope();
      var evictions = 0;
      store.invalidateNextRollbackScope = () {
        evictions++;
        for (var index = 0; index < 5; index++) {
          global.historyWindowScopeFor('@TGS#rollback-read-evict-$index');
        }
        expect(global.isHistoryWindowScopeCurrent(oldScope), isFalse);
      };
      if (revoke) {
        await model.revokeMsg('m100', false);
      } else {
        await model.deleteMsg('m100');
      }
      sdk.completion.complete(1);
      // SQLite rollback is asynchronous and competes with real inbound stress
      // tests. Wait for the observable restoration, rather than assuming 30 ms.
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while ((evictions != 1 ||
              global.canonicalMessageWindow(getConv()).length != 2 ||
              global.canonicalMessageWindow(getConv()).first.status != 2) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(evictions, 1);
      expect(currentIDs(), ['m100', 'm99']);
      expect(global.canonicalMessageWindow(getConv()).first.status, 2);
    });
  }

  for (final success in [false, true]) {
    test(
        'return latest success=$success controls watermark ack and snapshot session renewal',
        () async {
      final conv = getConv();
      model.dispose();
      final latest = _LatestModel()
        ..conversationID = conv
        ..conversationType = ConvType.group
        ..suppressReadReporting = true
        ..succeed = success;
      model = latest;
      final oldScope = getScope();
      global.noteHistoryWindowSnapshot(conv, 100);
      await store.appendDeferred(
          scope: oldScope,
          eventID: 'incoming-1',
          ingressSequence: 1,
          message: row(101, conv));
      latest.duringReload = () async {
        await store.appendDeferred(
            scope: oldScope,
            eventID: 'incoming-2',
            ingressSequence: 2,
            message: row(102, conv));
      };
      expect(
          await model.reloadNewestMessageWindow(allowWhileReadingHistory: true),
          success);
      final now = getScope();
      expect(now.sessionID == oldScope.sessionID, !success);
      final remaining = await store.deferredState(now);
      expect(remaining.receivedCount, success ? 1 : 2);
      if (success) {
        expect(
            () => global.noteHistoryWindowSnapshot(conv, 999), returnsNormally);
        expect(currentIDs(), ['m999']);
      } else {
        expect(currentIDs(), ['m100', 'm99']);
      }
    });
  }
}
