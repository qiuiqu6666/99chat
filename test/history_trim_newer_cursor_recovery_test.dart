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
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/controllers/history_window_trim_ui_controller.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/history_window_trim_transaction.dart';
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
      ..textElem = V2TimTextElem(text: 'message $seq');

class _RecordingStore extends HistoryWindowStore {
  _RecordingStore({required super.debugDatabasePath});

  final newerBoundaries = <String>[];

  @override
  Future<HistoryWindowReadResult> readAdjacent({
    required HistoryWindowScope scope,
    required HistoryWindowBoundary boundary,
    required HistoryWindowDirection direction,
    int limit = 50,
  }) {
    if (direction == HistoryWindowDirection.newer) {
      newerBoundaries.add(boundary.msgID);
    }
    return super.readAdjacent(
        scope: scope, boundary: boundary, direction: direction, limit: limit);
  }
}

// The initial window already includes the server tip. Querying that stale tip
// after trimming it would return an empty finished SDK page and strand the gap.
class _ExhaustedSdk extends MessageService {
  int historyCalls = 0;

  V2TimMessageListResult _emptyPage() {
    historyCalls++;
    return V2TimMessageListResult(messageList: [], isFinished: true);
  }

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
  }) async =>
      MessageHistorySdkResult(
          code: 0, desc: 'tip exhausted', data: _emptyPage());

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
  }) async =>
      _emptyPage();

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
  late _RecordingStore store;
  late _ExhaustedSdk sdk;
  late TUIChatSeparateViewModel model;
  late TUIChatGlobalModel global;
  late HistoryWindowTrimUiController<HistoryWindowTrimTicket, String> trim;
  late List<String> events;
  HistoryWindowTrimTicket? lastTicket;

  List<String?> currentIDs() => global
      .canonicalMessageWindow(model.conversationID)
      .map((message) => message.msgID)
      .toList();

  void installWindow(int count) {
    final conv = model.conversationID;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    global.setMessageList(
        conv, [for (var seq = count; seq > 0; seq--) _row(seq, conv)],
        replace: true, applyMemoryWindow: false);
    model.freezeVisibleHistoryWindowIfNeeded();
    model.haveMoreLatestData = false;
    expect(model.historyNewerPageCursor?.msgID, 'm$count');
  }

  Future<HistoryWindowTrimUiOutcome> runTrim({
    required bool restoreSucceeds,
    bool rollbackOnRestoreFailure = true,
    bool throwOnSettled = false,
    Completer<void>? prepared,
    Future<void>? allowPrepare,
  }) =>
      trim.run(
        isCurrentAndIdle: () => true,
        capture: () => 'm1',
        prepare: (anchor) async {
          final ticket = await global.prepareHistoryWindowTrim(
              conversationID: model.conversationID, anchorMsgID: anchor);
          expect(ticket, isNotNull);
          lastTicket = ticket;
          prepared?.complete();
          if (allowPrepare != null) await allowPrepare;
          return ticket;
        },
        beginVisualUpdate: () {
          events.add('begin');
          return true;
        },
        commit: (ticket) {
          events.add('commit');
          return global.commitHistoryWindowTrim(ticket);
        },
        nextFrame: () async {},
        restore: (anchor, attempt) => restoreSucceeds,
        rollback: (ticket) async {
          events.add('rollback');
          return global.rollbackHistoryWindowTrim(ticket);
        },
        finish: (ticket) {
          global.finishHistoryWindowTrim(ticket);
          events.add('finish');
        },
        onWindowSettled: () {
          expect(lastTicket!.finished, isTrue);
          expect(events.last, 'finish');
          events.add('settled');
          model.rebaseHistoryReadingWindowAfterTrim();
          if (throwOnSettled) throw StateError('settled callback failed');
        },
        endVisualUpdate: () async {
          expect(events.last, 'settled');
          events.add('end');
        },
        maxRestoreFrames: 2,
        rollbackOnRestoreFailure: rollbackOnRestoreFailure,
      );

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory = await Directory.systemTemp.createTemp('trim-newer-cursor-');
    store = _RecordingStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    await serviceLocator.unregister<MessageService>();
    sdk = _ExhaustedSdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    await serviceLocator.unregister<TUIChatGlobalModel>();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(TUIChatGlobalModel());
    model = TUIChatSeparateViewModel()
      ..conversationID = '@TGS#${910000 + ++sequence}'
      ..conversationType = ConvType.group
      ..groupType = GroupReceiptAllowType.community
      ..chatConfig = TIMUIKitChatConfig(isShowReadingStatus: false)
      ..suppressReadReporting = true;
    model.groupInfo =
        V2TimGroupInfo(groupID: model.conversationID, groupType: 'Community');
    global = model.globalModel;
    global.configureMessageWriterScope(
        ownerUserID: 'trim-cursor-owner',
        accountGeneration: sequence,
        domainGeneration: 1);
    trim = HistoryWindowTrimUiController<HistoryWindowTrimTicket, String>();
    events = [];
    lastTicket = null;
  });

  tearDown(() async {
    trim.dispose();
    model.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  for (final mode in ['restored', 'rollbackFailed', 'keptCommitted']) {
    final restoreSucceeds = mode == 'restored';
    final rollbackOnRestoreFailure = mode != 'keptCommitted';
    test(
        '$mode trim replays evicted newer rows from the retained cursor',
        () async {
      // 300 exceeds the real rollback soft limit of 280. A failed visual
      // restore therefore keeps the 220 committed rows rather than rolling back.
      installWindow(300);
      final revision = model.historyReadingWindowRevision;

      expect(
          await runTrim(restoreSucceeds: restoreSucceeds,
              rollbackOnRestoreFailure: rollbackOnRestoreFailure),
          restoreSucceeds
              ? HistoryWindowTrimUiOutcome.restored
              : rollbackOnRestoreFailure
                  ? HistoryWindowTrimUiOutcome.rollbackFailed
                  : HistoryWindowTrimUiOutcome.keptCommitted);

      expect(currentIDs(), [for (var seq = 220; seq > 0; seq--) 'm$seq']);
      expect(events, [
        'begin',
        'commit',
        if (!restoreSucceeds && rollbackOnRestoreFailure) 'rollback',
        'finish',
        'settled',
        'end',
      ]);
      expect(model.historyNewerPageCursor?.msgID, 'm220');
      expect(model.historyReadingWindowRevision, revision + 1);
      expect(model.haveMoreLatestData, isTrue);
      expect(model.hasCaughtUpToLiveLatest, isFalse);

      // Passing the old UI cursor must not skip the evicted 221..300 segment.
      expect(
          await model.loadChatRecord(
              count: 30,
              direction: LoadDirection.latest,
              lastMsgID: 'm300',
              lastMsgSeq: 300),
          isTrue);
      expect(store.newerBoundaries, ['m220']);
      expect(currentIDs(), [for (var seq = 250; seq > 0; seq--) 'm$seq']);
      expect(model.historyNewerPageCursor?.msgID, 'm250');
      expect(model.haveMoreLatestData, isTrue);
      expect(model.hasCaughtUpToLiveLatest, isFalse);

      expect(
          await model.loadChatRecord(
              count: 50,
              direction: LoadDirection.latest,
              lastMsgID: 'm250',
              lastMsgSeq: 250),
          isTrue);
      expect(store.newerBoundaries, ['m220', 'm250']);
      expect(currentIDs(), [for (var seq = 300; seq > 0; seq--) 'm$seq']);
      expect(model.historyNewerPageCursor?.msgID, 'm300');
      expect(sdk.historyCalls, 0,
          reason: 'evicted pages were persisted before the trim committed');
    });
  }

  test('successful rollback preserves the original cursor and exhaustion',
      () async {
    installWindow(260);
    final cursor = model.historyNewerPageCursor;
    final revision = model.historyReadingWindowRevision;

    expect(await runTrim(restoreSucceeds: false),
        HistoryWindowTrimUiOutcome.rolledBack);

    expect(currentIDs(), [for (var seq = 260; seq > 0; seq--) 'm$seq']);
    expect(model.historyNewerPageCursor, same(cursor));
    expect(model.historyReadingWindowRevision, revision);
    expect(model.haveMoreLatestData, isFalse);
    expect(events, ['begin', 'commit', 'rollback', 'finish', 'settled', 'end']);
  });

  test('cancel during prepare releases the ticket without settling a window',
      () async {
    installWindow(300);
    final cursor = model.historyNewerPageCursor;
    final revision = model.historyReadingWindowRevision;
    final prepared = Completer<void>();
    final allowPrepare = Completer<void>();
    final result = runTrim(
        restoreSucceeds: true,
        prepared: prepared,
        allowPrepare: allowPrepare.future);
    await prepared.future;
    trim.cancel();
    allowPrepare.complete();

    expect(await result, HistoryWindowTrimUiOutcome.skipped);
    expect(currentIDs(), [for (var seq = 300; seq > 0; seq--) 'm$seq']);
    expect(model.historyNewerPageCursor, same(cursor));
    expect(model.historyReadingWindowRevision, revision);
    expect(model.haveMoreLatestData, isFalse);
    expect(lastTicket!.finished, isTrue);
    expect(events, ['finish']);
  });

  test(
      'settled callback failure still ends the visual update and releases busy',
      () async {
    installWindow(300);

    await expectLater(
        runTrim(restoreSucceeds: true, throwOnSettled: true), throwsStateError);

    expect(events, ['begin', 'commit', 'finish', 'settled', 'end']);
    expect(lastTicket!.finished, isTrue);
    expect(trim.isBusy, isFalse);
    expect(model.historyNewerPageCursor?.msgID, 'm220');
    expect(model.haveMoreLatestData, isTrue);
  });
}
