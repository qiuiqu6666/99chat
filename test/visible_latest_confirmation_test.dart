import 'dart:async';
import 'dart:io';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _Store extends HistoryWindowStore {
  _Store(String path) : super(debugDatabasePath: path);
  Future<void> Function()? afterTailRead;
  @override
  Future<List<V2TimMessage>> readDeferredTail(
      {required HistoryWindowScope scope, int limit = 120}) async {
    final rows = await super.readDeferredTail(scope: scope, limit: limit);
    await afterTailRead?.call();
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _Store store;
  late TUIChatGlobalModel global;
  late String conv;
  late TUIChatSeparateViewModel model;
  var generation = 0;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    dir = await Directory.systemTemp.createTemp('unread-state-');
    store = _Store('${dir.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
        ownerUserID: 'reader',
        accountGeneration: ++generation,
        domainGeneration: 1);
    conv = 'c2c_unread_$generation';
    model = TUIChatSeparateViewModel()
      ..conversationID = conv
      ..conversationType = ConvType.c2c;
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
  });
  tearDown(() async {
    store.afterTailRead = null;
    model.dispose();
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await dir.delete(recursive: true);
  });
  V2TimMessage message(int id) => V2TimMessage.fromJson({
        'message_msg_id': 'm$id',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..userID = conv.substring(4)
        ..isSelf = false;
  Future<void> receive(int id, {bool formal = true}) =>
      global.applyAppRealtimeMessage(message(id),
          ingressEventID: formal ? 'event$id' : null,
          ingressSequence: formal ? id : null);

  Future<bool> confirm(List<V2TimMessage> rows, {bool Function()? edge}) {
    model.haveMoreLatestData = false;
    return model.confirmVisibleLatestWindow(
        visibleMessages: rows, isStillAtLatestEdge: edge ?? () => true);
  }

  test('disconnected raw newest cannot acknowledge an older visible page',
      () async {
    await receive(10);
    global.setMessageList(conv, [message(20)],
        replace: true,
        needResetNewMessageCount: false,
        applyMemoryWindow: false);
    expect(await confirm([message(5)]), isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(await confirm([message(10)]), isTrue);
    expect(global.hasDurableHistoryDeferred(conv), isFalse);
  });

  test('leaving the bottom during snapshot preserves the pending message',
      () async {
    await receive(10);
    var atEdge = true;
    store.afterTailRead = () async {
      atEdge = false;
    };
    expect(await confirm([message(10)], edge: () => atEdge), isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
  });

  test('a captured watermark cannot acknowledge a later arrival', () async {
    await receive(10);
    final entered = Completer<void>();
    final release = Completer<void>();
    store.afterTailRead = () async {
      entered.complete();
      await release.future;
    };
    final confirming = confirm([message(10)]);
    await entered.future;
    final incoming = receive(11);
    store.afterTailRead = null;
    release.complete();
    await incoming;
    await confirming;
    final state =
        await store.deferredState(global.historyWindowScopeFor(conv)!);
    expect(state.receivedCount, 1);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
  });

  test('conversation switch during snapshot cannot consume old pending state',
      () async {
    await receive(10);
    store.afterTailRead = () async {
      model.conversationID = 'c2c_other';
    };
    expect(await confirm([message(10)]), isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
  });

  test('failed snapshot keeps the reminder retryable', () async {
    await receive(10);
    store.afterTailRead = () async {
      throw StateError('read failure');
    };
    expect(await confirm([message(10)]), isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    store.afterTailRead = null;
    expect(await confirm([message(10)]), isTrue);
  });
}
