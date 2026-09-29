import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_host.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'iOS pause closes the installed history database, resume reopens durable data',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final oldPath = await getDatabasesPath();
    final temp = await Directory.systemTemp.createTemp('history-lifecycle-');
    await databaseFactory.setDatabasesPath(temp.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    SqfliteLifecycleHost.debugReset();
    final store = HistoryWindowStore.instance;
    const scope = HistoryWindowScope(
        ownerUserID: 'owner',
        accountGeneration: 1,
        domainGeneration: 1,
        conversationID: 'c2c_peer',
        clearEpoch: 0,
        sessionID: 's');
    try {
      await store
          .savePage(HistoryWindowPage(scope: scope, pageKey: 'p', messages: [
        V2TimMessage.fromJson(
            {'message_msg_id': 'm', 'message_risk_type_identified': 0}),
      ]));
      expect(store.isOpenForTesting, isTrue);
      await SqfliteLifecycleHost.handle(AppLifecycleState.paused);
      expect(store.isOpenForTesting, isFalse);
      await expectLater(store.readPage(scope: scope, pageKey: 'p'),
          throwsA(isA<SqfliteClosedForBackground>()));
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
      final restored = await store.readPage(scope: scope, pageKey: 'p');
      expect(restored.messages.single.msgID, 'm');
      expect(store.isOpenForTesting, isTrue);
    } finally {
      SqfliteLifecycleGuard.instance.debugReset();
      SqfliteLifecycleHost.debugReset();
      await store.closeIfOpen();
      debugDefaultTargetPlatformOverride = null;
      await databaseFactory.setDatabasesPath(oldPath);
      await temp.delete(recursive: true);
    }
  });

  test(
      'an exact command completion waits through inactive and pause until resume',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    final oldPath = await getDatabasesPath();
    final temp =
        await Directory.systemTemp.createTemp('history-completion-lifecycle-');
    await databaseFactory.setDatabasesPath(temp.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    SqfliteLifecycleHost.debugReset();
    final store = HistoryWindowStore.instance;
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
        ownerUserID: 'owner', accountGeneration: 10, domainGeneration: 1);
    final scope = global.historyWindowScopeFor('c2c_peer')!;
    final message = V2TimMessage.fromJson(
        {'message_msg_id': 'm', 'message_risk_type_identified': 0});
    Future<String?>? completion;
    try {
      final token = await global.recordHistoryWindowMutation(
          conversationID: 'c2c_peer',
          msgID: 'm',
          kind: HistoryWindowMutationKind.delete,
          pending: true);
      expect(await store.applyMutations(scope: scope, messages: [message]),
          isEmpty);
      await SqfliteLifecycleHost.handle(AppLifecycleState.inactive);
      var finished = false;
      completion = global
          .recordHistoryWindowMutation(
              conversationID: 'c2c_peer',
              msgID: 'm',
              kind: HistoryWindowMutationKind.restore,
              restoreMutationToken: token,
              capturedScope: scope)
          .then((value) {
        finished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      await SqfliteLifecycleHost.handle(AppLifecycleState.paused);
      expect(finished, isFalse);
      expect(store.isOpenForTesting, isFalse);
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
      await completion.timeout(const Duration(seconds: 5));
      expect(await store.applyMutations(scope: scope, messages: [message]),
          hasLength(1));
    } finally {
      await SqfliteLifecycleHost.handle(AppLifecycleState.resumed);
      await completion;
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
      await store.closeIfOpen();
      SqfliteLifecycleGuard.instance.debugReset();
      SqfliteLifecycleHost.debugReset();
      debugDefaultTargetPlatformOverride = null;
      await databaseFactory.setDatabasesPath(oldPath);
      await temp.delete(recursive: true);
    }
  });
}
