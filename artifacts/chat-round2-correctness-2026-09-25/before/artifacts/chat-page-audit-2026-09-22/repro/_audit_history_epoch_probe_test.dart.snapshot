import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late HistoryWindowStore store;
  late TUIChatGlobalModel global;
  late String conv;
  var generation = 0;
  const owner = 'reader';

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    dir = await Directory.systemTemp.createTemp('clear-epoch-sync-');
    store = HistoryWindowStore(debugDatabasePath: '${dir.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
      ownerUserID: owner,
      accountGeneration: ++generation,
      domainGeneration: 1,
    );
    conv = 'c2c_clear_epoch_$generation';
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
  });

  tearDown(() async {
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
    global.clearData();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await dir.delete(recursive: true);
  });

  Future<HistoryWindowReadStatus> readOlder(HistoryWindowScope scope) async {
    final result = await store.readAdjacent(
      scope: scope,
      boundary: const HistoryWindowBoundary(msgID: 'm1'),
      direction: HistoryWindowDirection.older,
    );
    return result.status;
  }

  test('persistedClearEpoch returns 0 then the max recorded epoch', () async {
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conv);
    expect(
      await store.persistedClearEpoch(ownerUserID: owner, conversationID: key),
      0,
    );
    await store.clearConversation(
      ownerUserID: owner,
      conversationID: key,
      clearEpoch: 5,
    );
    expect(
      await store.persistedClearEpoch(ownerUserID: owner, conversationID: key),
      5,
    );
    await store.clearConversation(
      ownerUserID: owner,
      conversationID: key,
      clearEpoch: 3,
    );
    expect(
      await store.persistedClearEpoch(ownerUserID: owner, conversationID: key),
      5,
    );
  });

  test('sync adopts the window store clear epoch and unblocks readAdjacent',
      () async {
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conv);
    // 该设备曾清空过记录，但 coverage 行丢失：内存 epoch 仍是 0。
    await store.clearConversation(
      ownerUserID: owner,
      conversationID: key,
      clearEpoch: 5,
    );
    final staleScope = global.historyWindowScopeFor(conv);
    expect(staleScope, isNotNull);
    expect(staleScope!.clearEpoch, 0);
    expect(await readOlder(staleScope), HistoryWindowReadStatus.stale);

    await global.syncHistoryClearEpochFromWindowStore(conv);
    expect(global.messageDeltaClearEpochFor(conv), 5);
    final healedScope = global.historyWindowScopeFor(conv);
    expect(healedScope, isNotNull);
    expect(healedScope!.clearEpoch, 5);
    expect(await readOlder(healedScope), HistoryWindowReadStatus.miss);

    // 每会话只对一次；重复调用无副作用。
    await global.syncHistoryClearEpochFromWindowStore(conv);
    expect(global.messageDeltaClearEpochFor(conv), 5);
  });

  test('loadChatRecord syncs the clear epoch before capturing fences', () {
    final source = File(
      'third_party/tencent_cloud_chat_uikit/lib/business_logic/'
      'separate_models/tui_chat_history_pagination_load.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final loadStart = source.indexOf('Future<bool> loadChatRecord({');
    final syncIndex = source.indexOf(
      'syncHistoryClearEpochFromWindowStore(model.conversationID)',
      loadStart,
    );
    final fenceIndex = source.indexOf(
      'final publicationIsCurrent = model._historyPublicationFence();',
      loadStart,
    );
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(syncIndex, greaterThan(loadStart));
    expect(fenceIndex, greaterThan(syncIndex));
  });
  test('AUDIT first epoch read blocked by lock screen must retry after resume', () async {
    final key = TUIChatGlobalModel.canonicalHistoryStorageKey(conv);
    await global.ensureMessageHistoryCoverageLoaded(conv);
    await store.clearConversation(
      ownerUserID: owner,
      conversationID: key,
      clearEpoch: 5,
    );
    expect(global.messageDeltaClearEpochFor(conv), 0);
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.forbidOpen();
    await global.syncHistoryClearEpochFromWindowStore(conv);
    expect(global.messageDeltaClearEpochFor(conv), 0);
    SqfliteLifecycleGuard.instance.resume();
    await global.ensureMessageHistoryCoverageLoaded(conv);
    await global.syncHistoryClearEpochFromWindowStore(conv);
    final actualStatus = await readOlder(global.historyWindowScopeFor(conv)!);
    print('AUDIT after resume epoch=${global.messageDeltaClearEpochFor(conv)} adjacent=$actualStatus');
    expect(global.messageDeltaClearEpochFor(conv), 5,
      reason: 'A background-closed read is not a successful synchronization; resume must retry it.');
    expect(actualStatus, HistoryWindowReadStatus.miss);
  });
}


