import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _EpochStore extends HistoryWindowStore {
  _EpochStore({required super.debugDatabasePath});

  Completer<void>? readStarted;
  Completer<void>? releaseRead;

  @override
  Future<int> persistedClearEpoch({
    required String ownerUserID,
    required String conversationID,
  }) async {
    final value = await super.persistedClearEpoch(
      ownerUserID: ownerUserID,
      conversationID: conversationID,
    );
    final release = releaseRead;
    releaseRead = null;
    if (release != null) {
      readStarted!.complete();
      await release.future;
    }
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _EpochStore store;
  late TUIChatGlobalModel global;
  late String conversation;
  var generation = 0;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('history-epoch-retry-');
    store = _EpochStore(debugDatabasePath: '${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
      ownerUserID: 'epoch-reader',
      accountGeneration: ++generation,
      domainGeneration: 1,
    );
    conversation = 'c2c_epoch_retry_$generation';
    global.setCurrentConversation(
        CurrentConversation(conversation, ConvType.c2c));
  });

  tearDown(() async {
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
    global.clearData();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  Future<void> persistFloor(int epoch, {String owner = 'epoch-reader'}) =>
      store.clearConversation(
        ownerUserID: owner,
        conversationID:
            TUIChatGlobalModel.canonicalHistoryStorageKey(conversation),
        clearEpoch: epoch,
      );

  Future<void> expectReadableFloor(int epoch) async {
    expect(global.messageDeltaClearEpochFor(conversation), epoch);
    final scope = global.historyWindowScopeFor(conversation)!;
    expect(scope.clearEpoch, epoch);
    final page = await store.readAdjacent(
      scope: scope,
      boundary: const HistoryWindowBoundary(msgID: 'm1'),
      direction: HistoryWindowDirection.older,
    );
    expect(page.status, HistoryWindowReadStatus.miss);
  }

  test('first synchronization blocked in background retries after resume',
      () async {
    await global.ensureMessageHistoryCoverageLoaded(conversation);
    await persistFloor(5);
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.forbidOpen();
    await global.syncHistoryClearEpochFromWindowStore(conversation);
    expect(global.messageDeltaClearEpochFor(conversation), 0);

    SqfliteLifecycleGuard.instance.resume();
    await global.ensureMessageHistoryCoverageLoaded(conversation);
    await global.syncHistoryClearEpochFromWindowStore(conversation);
    await expectReadableFloor(5);
  });

  test('repository not attached yet does not consume synchronization',
      () async {
    await persistFloor(5);
    HistoryWindowRepositoryProvider.repository = null;
    await global.syncHistoryClearEpochFromWindowStore(conversation);
    expect(global.messageDeltaClearEpochFor(conversation), 0);

    HistoryWindowRepositoryProvider.repository = store;
    await global.syncHistoryClearEpochFromWindowStore(conversation);
    await expectReadableFloor(5);
  });

  test('an old account read cannot adopt its epoch or suppress the new read',
      () async {
    await persistFloor(5);
    await persistFloor(2, owner: 'next-reader');
    final started = Completer<void>();
    final release = Completer<void>();
    store.readStarted = started;
    store.releaseRead = release;
    final previous = global.syncHistoryClearEpochFromWindowStore(conversation);
    await started.future;
    global.clearData();
    global.configureMessageWriterScope(
      ownerUserID: 'next-reader',
      accountGeneration: ++generation,
      domainGeneration: 1,
    );
    global.setCurrentConversation(
        CurrentConversation(conversation, ConvType.c2c));
    release.complete();
    await previous;
    expect(global.messageDeltaClearEpochFor(conversation), 0);

    await global.syncHistoryClearEpochFromWindowStore(conversation);
    await expectReadableFloor(2);
  });
}
