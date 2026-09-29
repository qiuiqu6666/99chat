import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_local/friend_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/factory.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_list_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/message_reconciliation_coordinator.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _PendingNativeDatabase implements Database {
  final closeStarted = Completer<void>();
  final releaseClose = Completer<void>();
  bool _open = true;
  @override
  bool get isOpen => _open;
  @override
  String get path => 'w7-controlled-native-database';
  @override
  Future<void> close() async {
    if (!closeStarted.isCompleted) closeStarted.complete();
    await releaseClose.future;
    _open = false;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async =>
      [];
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DatabaseFactory implements SqfliteDatabaseFactory {
  _DatabaseFactory(this.db);
  final _PendingNativeDatabase db;
  @override
  Future<String> getDatabasesPath() async => 'w7-does-not-touch-disk';
  @override
  Future<Database> openDatabase(String path,
          {OpenDatabaseOptions? options}) async =>
      db;
  @override
  Future<bool> databaseExists(String path) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Global extends TUIChatGlobalModel {
  Future<void> Function()? preflight;
  List<V2TimMessage>? aliasWindow;
  @override
  int rawMessageCount(String conversationID) => aliasWindow != null
      ? (conversationID.startsWith('c2c_') ? aliasWindow!.length : 0)
      : super.rawMessageCount(conversationID);
  @override
  List<V2TimMessage>? rawMessageList(String conversationID) =>
      aliasWindow != null && conversationID.startsWith('c2c_')
          ? aliasWindow
          : super.rawMessageList(conversationID);
  @override
  Future<void> syncHistoryClearEpochFromWindowStore(
      String conversationID) async {
    await preflight?.call();
  }
}

class _Sdk extends MessageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int historyCalls = 0;
  final deleted = <List<String>>[];
  final deleteReplies = <Completer<V2TimCallback>>[];
  @override
  Future<V2TimCallback> deleteMessages(
      {required List<String> msgIDs, List<dynamic>? webMessageInstanceList}) {
    deleted.add(msgIDs);
    final response = Completer<V2TimCallback>();
    deleteReplies.add(response);
    return response.future;
  }

  final revoked = <String>[];
  final revokeReplies = <Completer<V2TimCallback>>[];
  List<V2TimMessage> page = [];
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
    return MessageHistorySdkResult(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(isFinished: true, messageList: page));
  }

  @override
  Future<V2TimCallback> revokeMessage(
      {required String msgID,
      Object? webMessageInstance,
      V2TimMessage? message}) {
    revoked.add(msgID);
    final response = Completer<V2TimCallback>();
    revokeReplies.add(response);
    return response.future;
  }
}

class _Repository implements HistoryWindowRepository {
  Future<void> Function(HistoryWindowMutation)? write;
  Future<List<V2TimMessage>> Function(List<V2TimMessage>)? read;
  final mutations = <HistoryWindowMutation>[];
  @override
  Future<void> recordMutation(HistoryWindowMutation mutation) async {
    mutations.add(mutation);
    await write?.call(mutation);
  }

  @override
  Future<List<V2TimMessage>> applyMutations(
          {required HistoryWindowScope scope,
          required List<V2TimMessage> messages}) async =>
      await read?.call(messages) ?? messages;
  @override
  Future<void> closeSession(HistoryWindowScope scope) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

V2TimMessage _row(String conv, int n) => V2TimMessage.fromJson({
      'message_msg_id': 'm$n',
      'message_server_time': n,
      'message_risk_type_identified': 0,
    })
      ..userID = conv
      ..id = 'local$n'
      ..isSelf = true
      ..status = 2
      ..elemType = 1
      ..textElem = V2TimTextElem(text: 'row$n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
  });
  late _Global global;
  late TUIChatSeparateViewModel model;
  late _Sdk sdk;
  late _Repository repository;
  late _PendingNativeDatabase db;
  DatabaseFactory? oldFactory;
  var serial = 0;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      oldFactory = databaseFactory;
    } catch (_) {}
    db = _PendingNativeDatabase();
    databaseFactory = _DatabaseFactory(db);
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    await FriendLocalStore.instance.readAll(ownerUserId: 'w7-test');
    await serviceLocator.unregister<TUIChatGlobalModel>();
    await serviceLocator.unregister<MessageService>();
    sdk = _Sdk();
    serviceLocator.registerSingleton<MessageService>(sdk);
    global = _Global();
    serviceLocator.registerSingleton<TUIChatGlobalModel>(global);
    model = TUIChatSeparateViewModel()
      ..conversationID = 'close_recovery_${++serial}'
      ..conversationType = ConvType.c2c
      ..suppressReadReporting = true
      ..chatConfig = const TIMUIKitChatConfig(isShowReadingStatus: false);
    global.configureMessageWriterScope(
        ownerUserID: 'owner', accountGeneration: serial, domainGeneration: 1);
    global.appMessageReconciliationNetworkStateProvider =
        () => MessageReconciliationNetworkState.online;
    global.setMessageList(
        model.conversationID, [_row(model.conversationID, 100)],
        applyMemoryWindow: false);
    repository = _Repository();
    HistoryWindowRepositoryProvider.repository = repository;
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    if (!db.releaseClose.isCompleted) db.releaseClose.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    model.dispose();
    HistoryWindowRepositoryProvider.repository = null;
    SqfliteLifecycleGuard.instance.debugReset();
    SqfliteLifecycleHost.debugReset();
    await FriendLocalStore.instance.closeIfOpen();
    databaseFactory = oldFactory ?? databaseFactoryFfi;
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> releaseClose(WidgetTester tester) async {
    if (!db.releaseClose.isCompleted) db.releaseClose.complete();
    // Store opening/closing crosses the fake widget clock and real async setup.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (SqfliteLifecycleHost.status.value == SqfliteLifecycleStatus.ready)
        break;
    }
  }

  void recoveryTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(tester);
      } finally {
        await releaseClose(tester);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> stallClose(WidgetTester tester) async {
    // Host stores are process singletons. Their serial Futures must be born in
    // real async, not a widget clock that is discarded at the end of one test.
    await tester.runAsync(() async {
      await SqfliteLifecycleHost.handle(AppLifecycleState.paused,
          waitBudget: Duration.zero);
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed,
          waitBudget: Duration.zero);
    });
    await tester.pump();
    expect(db.closeStarted.isCompleted, isTrue);
    expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
  }

  bool finished() => ChatRecoveryTrace.recentEvents.any((e) =>
      e.contains('revoke_finished') &&
      e.contains('conv=${model.conversationID} '));
  int status() => global.rawMessageList(model.conversationID)!.first.status!;

  recoveryTest(
      'exact completion releases UI while actual native close remains pending',
      (tester) async {
    final scope = global.historyWindowScopeFor(model.conversationID)!;
    final token = await global.recordHistoryWindowMutation(
        conversationID: model.conversationID,
        msgID: 'm100',
        kind: HistoryWindowMutationKind.delete,
        pending: true);
    await stallClose(tester);
    var done = false;
    unawaited(global
        .recordHistoryWindowMutation(
            msgID: 'm100',
            kind: HistoryWindowMutationKind.restore,
            capturedScope: scope,
            restoreMutationToken: token)
        .then((_) => done = true));
    await tester.pump(const Duration(seconds: 3));
    expect(done, isTrue);
    expect(repository.mutations.length, 1);
    expect(SqfliteLifecycleGuard.instance.canOpenDatabase, isFalse);
    await releaseClose(tester);
    expect(repository.mutations.length, 2);
    expect(repository.mutations.last.restoreMutationToken, token);
  });

  recoveryTest(
      'timed out SQL completion keeps one physical slot until real completion',
      (tester) async {
    final scope = global.historyWindowScopeFor(model.conversationID)!;
    final token = await global.recordHistoryWindowMutation(
        conversationID: model.conversationID,
        msgID: 'm100',
        kind: HistoryWindowMutationKind.delete,
        pending: true);
    final blocked = Completer<void>();
    repository.write = (_) => blocked.future;
    Future<String?> complete() => global.recordHistoryWindowMutation(
        msgID: 'm100',
        kind: HistoryWindowMutationKind.restore,
        capturedScope: scope,
        restoreMutationToken: token);
    var done = false;
    unawaited(complete().then((_) => done = true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(done, isTrue);
    final duplicates = List.generate(5, (_) => complete());
    await tester.pump(const Duration(seconds: 3));
    await Future.wait(duplicates);
    expect(repository.mutations.length, 2);
    blocked.complete();
    await tester.pump();
    expect(repository.mutations.length, 2);
  });

  recoveryTest(
      'accepted revoke finishes UI without undo while late close settles exact token',
      (tester) async {
    await model.revokeMsg('m100', false);
    final pending = repository.mutations.single;
    await stallClose(tester);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 0, desc: 'ok'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(finished(), isTrue);
    expect(status(), 6);
    expect(repository.mutations.length, 1);
    await releaseClose(tester);
    expect(
        repository.mutations.any((m) =>
            m.kind == HistoryWindowMutationKind.settle &&
            m.restoreMutationToken == pending.eventID),
        isTrue);
    expect(status(), 6);
    expect(sdk.revoked, ['m100']);
  });

  recoveryTest(
      'failed revoke compensates only after late native close really completes',
      (tester) async {
    await model.revokeMsg('m100', false);
    await stallClose(tester);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 1, desc: 'failed'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(finished(), isTrue);
    expect(status(), 6);
    await releaseClose(tester);
    expect(status(), 2);
    expect(sdk.revoked, ['m100']);
  });

  for (final replacement in ['account', 'window']) {
    recoveryTest('late restore cannot publish into a replacement $replacement',
        (tester) async {
      await model.revokeMsg('m100', false);
      await stallClose(tester);
      sdk.revokeReplies.single.complete(V2TimCallback(code: 1, desc: 'failed'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      if (replacement == 'account') {
        global.configureMessageWriterScope(
            ownerUserID: 'another-owner',
            accountGeneration: 999,
            domainGeneration: 1);
      }
      final fresh = _row(model.conversationID, 200)
        ..textElem = V2TimTextElem(text: 'new window');
      global.setMessageList(model.conversationID, [fresh],
          replace: true,
          applyMemoryWindow: false,
          preserveInFlightOutgoing: false);
      await releaseClose(tester);
      expect(global.rawMessageList(model.conversationID)!.single, same(fresh));
      expect(repository.mutations.last.kind, HistoryWindowMutationKind.restore);
      expect(sdk.revoked, ['m100']);
    });
  }

  recoveryTest(
      'hung rollback read is not duplicated and late facts restore once',
      (tester) async {
    final read = Completer<List<V2TimMessage>>();
    var reads = 0;
    List<V2TimMessage>? originals;
    repository.read = (messages) {
      reads++;
      originals = messages;
      return read.future;
    };
    await model.revokeMsg('m100', false);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 1, desc: 'failed'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(finished(), isTrue);
    for (var i = 0; i < 5; i++) {
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
    }
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 1);
    expect(status(), 6);
    read.complete(originals!);
    await tester.pump();
    expect(status(), 2);
    expect(reads, 1);
  });

  recoveryTest(
      'permanent settlement fault has two actual attempts and no remote resend',
      (tester) async {
    var settlements = 0;
    repository.write = (mutation) async {
      if (mutation.kind == HistoryWindowMutationKind.settle) {
        settlements++;
        throw StateError('disk remains broken');
      }
    };
    await model.revokeMsg('m100', false);
    sdk.revokeReplies.single.complete(V2TimCallback(code: 0, desc: 'ok'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(settlements, 2);
    for (var i = 0; i < 5; i++) {
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 6));
    }
    expect(settlements, 2);
    expect(status(), 6);
    expect(sdk.revoked, ['m100']);
  });

  recoveryTest(
      'delete preparation has a deadline before optimistic removal and SDK',
      (tester) async {
    final pending = Completer<void>();
    repository.write = (m) => m.pending ? pending.future : Future.value();
    var done = false;
    unawaited(model.deleteMsg('m100').then((_) => done = true));
    await tester.pump(const Duration(seconds: 3));
    expect(done, isTrue);
    expect(status(), 2);
    expect(sdk.deleted, isEmpty);
    pending.complete();
    await tester.pump();
    expect(repository.mutations.last.kind, HistoryWindowMutationKind.restore);
  });

  recoveryTest(
      'failed delete restores only after exact completion following native close',
      (tester) async {
    await model.deleteMsg('m100');
    expect(global.rawMessageList(model.conversationID), isEmpty);
    await stallClose(tester);
    sdk.deleteReplies.single.complete(V2TimCallback(code: 1, desc: 'failed'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(global.rawMessageList(model.conversationID), isEmpty);
    await releaseClose(tester);
    expect(status(), 2);
    expect(sdk.deleted.length, 1);
  });
}
