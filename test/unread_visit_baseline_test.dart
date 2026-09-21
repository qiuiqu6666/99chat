import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/tim_uikit_chat_config.dart';

class _Store extends HistoryWindowStore {
  _Store(String path) : super(debugDatabasePath: path);
  Future<void> Function()? beforeState;
  Future<void> Function()? afterAppend;
  @override
  Future<HistoryWindowDeferredState> deferredState(
      HistoryWindowScope scope) async {
    await beforeState?.call();
    return super.deferredState(scope);
  }

  @override
  Future<HistoryWindowDeferredReceipt> appendDeferred({
    required HistoryWindowScope scope,
    required String eventID,
    required int ingressSequence,
    bool hasStableIngressSequence = true,
    required V2TimMessage message,
  }) async {
    final receipt = await super.appendDeferred(
        scope: scope,
        eventID: eventID,
        ingressSequence: ingressSequence,
        hasStableIngressSequence: hasStableIngressSequence,
        message: message);
    await afterAppend?.call();
    return receipt;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Store store;
  late TUIChatGlobalModel global;
  final models = <TUIChatGlobalModel>[];
  const conv = 'c2c_visit-peer';
  TUIChatGlobalModel newGlobal() {
    final model = TUIChatGlobalModel();
    models.add(model);
    model.configureMessageWriterScope(
        ownerUserID: 'visit-reader', accountGeneration: 1, domainGeneration: 1);
    model.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    model.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    return model;
  }

  V2TimMessage message(int id) => V2TimMessage.fromJson({
        'message_msg_id': 'visit-$id',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..userID = 'visit-peer'
        ..isSelf = false;
  Future<void> receive(int id) => global.applyAppRealtimeMessage(message(id),
      ingressEventID: 'visit-event-$id', ingressSequence: id);
  Future<int> total() async =>
      (await store.deferredState(global.historyWindowScopeFor(conv)!))
          .receivedCount;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('unread-visit-');
    store = _Store('${directory.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    global = newGlobal();
  });
  tearDown(() async {
    store.beforeState = null;
    store.afterAppend = null;
    for (final model in models) {
      model.clearCurrentConversation();
      model.invalidateBoundedHistorySessions();
      model.dispose();
    }
    models.clear();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  test('same database, new global: old 213 plus 3 live displays only 3',
      () async {
    for (var i = 1; i <= 213; i++) {
      await receive(i);
    }
    global.invalidateBoundedHistorySessions();
    await store.closeIfOpen();
    global = newGlobal();
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 287, notify: false);
    await global.beginHistoryUnreadVisit(conv);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    for (var i = 214; i <= 216; i++) {
      await receive(i);
    }
    expect(await total(), 216);
    expect(global.receivedNewMessageCountFor(conv), 3);
    expect(global.unreadCountForTongueFor(conv), 290);
    global.releaseEntryUnreadReminder(conv);
    expect(global.unreadCountForTongueFor(conv), 3);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    await receive(217);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    expect(await total(), 1);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test(
      'old in-flight admission belongs to baseline, new queued arrival stays live',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    store.afterAppend = () async {
      store.afterAppend = null;
      entered.complete();
      await release.future;
    };
    final old = receive(1);
    await entered.future;
    final visit = global.beginHistoryUnreadVisit(conv);
    final fresh = receive(2);
    expect(global.receivedNewMessageCountFor(conv), 0);
    release.complete();
    await Future.wait([old, visit, fresh]);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test('partial old ACK reduces baseline without swallowing live rows',
      () async {
    await receive(1);
    final oldWatermark = await global.beginHistoryWindowReturnToLatest(conv);
    await receive(2);
    await global.beginHistoryUnreadVisit(conv);
    await receive(3);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, oldWatermark);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 1);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    await receive(4);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    expect(await total(), 1);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test(
      'baseline read failure retries before next append and never treats old count as live',
      () async {
    await receive(1);
    store.beforeState = () async {
      throw StateError('disk unavailable');
    };
    await expectLater(global.beginHistoryUnreadVisit(conv), throwsStateError);
    expect(global.receivedNewMessageCountFor(conv), 0);
    store.beforeState = null;
    await receive(2);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test(
      'LRU and latest cache reset retain visit; explicit reentry starts a new one',
      () async {
    await global.beginHistoryUnreadVisit(conv);
    await receive(1);
    global.invalidateBoundedHistorySessions();
    await receive(2);
    expect(global.receivedNewMessageCountFor(conv), 2);
    global.clearCurrentConversation();
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    await global.beginHistoryUnreadVisit(conv);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(await total(), 2);
    await receive(3);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test('legacy rows flushed during baseline SQL read remain new to this visit',
      () async {
    global.chatConfig =
        const TIMUIKitChatConfig(inboundChunkRevealEnabled: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await receive(1); // The coalescer has accepted this, but not committed it.
    final entered = Completer<void>();
    final release = Completer<void>();
    store.beforeState = () async {
      store.beforeState = null;
      entered.complete();
      await release.future;
    };
    final visit = global.beginHistoryUnreadVisit(conv);
    await entered.future;
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(global.receivedNewMessageCountFor(conv), 1);
    release.complete();
    await visit;
    expect(global.receivedNewMessageCountFor(conv), 1);
    await receive(2);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 2);
  });
  test(
      'old queued admission cannot absorb new legacy into the next visit baseline',
      () async {
    global.chatConfig =
        const TIMUIKitChatConfig(inboundChunkRevealEnabled: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await receive(50);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    final entered = Completer<void>();
    final release = Completer<void>();
    store.afterAppend = () async {
      store.afterAppend = null;
      entered.complete();
      await release.future;
    };
    final firstOld = receive(1);
    await entered.future;
    final secondOld = receive(2);
    final visit = global.beginHistoryUnreadVisit(conv);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(global.receivedNewMessageCountFor(conv), 1);
    release.complete();
    await Future.wait([firstOld, secondOld, visit]);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 1);
    await receive(3);
    expect(await total(), 4);
    expect(global.receivedNewMessageCountFor(conv), 2);
  });
  test('cold baseline failure survives ordinary cleanup before retry',
      () async {
    await receive(1);
    global.invalidateBoundedHistorySessions();
    global = newGlobal();
    store.beforeState = () async {
      throw StateError('cold disk unavailable');
    };
    await expectLater(global.beginHistoryUnreadVisit(conv), throwsStateError);
    global.unlockEntryUnreadForTongue(conversationID: conv, notify: false);
    global.clearReceivedUnreadState(conversationID: conv, notify: false);
    global.clearReceivedNewMessageCount(conversationID: conv);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(global.receivedNewMessageCountFor(conv), 0);
    store.beforeState = null;
    await receive(2);
    expect(await total(), 2);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });
  test('entry lock and dismissal exclude old legacy while baseline is pending',
      () async {
    global.chatConfig =
        const TIMUIKitChatConfig(inboundChunkRevealEnabled: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await receive(1);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final entered = Completer<void>();
    final release = Completer<void>();
    store.afterAppend = () async {
      store.afterAppend = null;
      entered.complete();
      await release.future;
    };
    final visit = global.beginHistoryUnreadVisit(conv);
    await entered.future;
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 287, notify: false);
    expect(global.unreadCountForTongueFor(conv), 287);
    global.releaseEntryUnreadReminder(conv);
    expect(global.unreadCountForTongueFor(conv), 0);
    release.complete();
    await visit;
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(await total(), 1);
  });
}
