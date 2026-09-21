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
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
  });
  tearDown(() async {
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
  void evictScope() {
    global
        .setCurrentConversation(CurrentConversation('c2c_other', ConvType.c2c));
    for (var i = 0; i < 5; i++) {
      global.historyWindowScopeFor('c2c_other$i');
    }
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
  }

  test(
      'entry reminder survives live admission and release keeps all 150 live messages',
      () async {
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 1000, notify: false);
    for (var i = 1; i <= 150; i++) {
      await receive(i);
    }
    expect(global.lockedEntryUnreadCountFor(conv), 1000);
    expect(global.receivedNewMessageCountFor(conv), 150);
    expect(global.unreadCountForTongueFor(conv), 1150);
    global.releaseEntryUnreadReminder(conv);
    expect(global.unreadCountForTongueFor(conv), 150);
    expect(global.deferredIncomingBufferedCount(conv), 120);
  });

  test('durable gap and counters survive LRU after hot bodies are released',
      () async {
    await receive(1);
    final previous = global.historyWindowScopeFor(conv)!;
    evictScope();
    expect(global.isHistoryWindowScopeCurrent(previous), isFalse);
    expect(global.deferredIncomingBufferedCount(conv), 0);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    global.unlockEntryUnreadForTongue(conversationID: conv, notify: false);
    global.clearReceivedUnreadState(conversationID: conv, notify: false);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isFalse);
  });

  test('a bodyless durable bucket still needs its real latest identity',
      () async {
    await receive(2);
    await store.closeIfOpen();
    final db = await openDatabase('${dir.path}/history.db');
    // State left by payload eviction: counters and IDs survive without bodies.
    await db.update('hw_deferred', {'payload': null});
    await db.close();
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    global.setMessageList(conv, [message(1)],
        replace: true, applyMemoryWindow: false);
    expect(global.historyWindowReturnCoversDeferred(conv, watermark), isFalse);
    global.setMessageList(conv, [message(2)],
        replace: true, applyMemoryWindow: false);
    expect(global.historyWindowReturnCoversDeferred(conv, watermark), isTrue);
    global.setMessageList(conv, [message(3)],
        replace: true, applyMemoryWindow: false);
    expect(global.historyWindowReturnCoversDeferred(conv, watermark), isTrue);
  });

  test('C2C sequence is not proof that the pending boundary was passed',
      () async {
    await global.applyAppRealtimeMessage(message(2)..seq = '2',
        ingressEventID: 'event2', ingressSequence: 2);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    global.setMessageList(conv, [message(1)..seq = '999'],
        replace: true, applyMemoryWindow: false);
    expect(global.historyWindowReturnCoversDeferred(conv, watermark), isFalse);
    global.setMessageList(conv, [message(3)..seq = '1'],
        replace: true, applyMemoryWindow: false);
    expect(global.historyWindowReturnCoversDeferred(conv, watermark), isTrue);
  });

  test(
      'only committed deletion of every captured delivery can replace the content proof',
      () async {
    await receive(2);
    await receive(3);
    final scope = global.historyWindowScopeFor(conv)!;
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    global.setMessageList(conv, [message(1)],
        replace: true, applyMemoryWindow: false);
    Future<void> remove(String id, {bool pending = false}) =>
        store.recordMutation(HistoryWindowMutation(
            ownerUserID: scope.ownerUserID,
            conversationID: scope.conversationID,
            clearEpoch: scope.clearEpoch,
            msgID: id,
            eventID: '$id-$pending',
            kind: HistoryWindowMutationKind.delete,
            pending: pending));
    await remove('m3');
    expect(
        await global.confirmHistoryWindowReturnCoversDeferred(conv, watermark),
        isFalse);
    await remove('m2', pending: true);
    expect(
        await global.confirmHistoryWindowReturnCoversDeferred(conv, watermark),
        isFalse);
    await remove('m2');
    expect(
        await global.confirmHistoryWindowReturnCoversDeferred(conv, watermark),
        isTrue);
  });

  test('closing and reopening the actual route retains a durable gap',
      () async {
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 100, notify: false);
    await receive(1);
    global.clearCurrentConversation();
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    global.clearReceivedNewMessageCount(conversationID: conv);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(global.lockedEntryUnreadCountFor(conv), 0);
    expect(
        (await store.deferredState(global.historyWindowScopeFor(conv)!))
            .receivedCount,
        1);
  });

  test('clear history retires the durable counter together with its SQL bucket',
      () async {
    await receive(1);
    await global.clearHistoryWindowData(conv, 1);
    await global.invalidateMessageHistoryCoverage(conv,
        isGroup: false, clearEpoch: 1);
    expect(global.hasDurableHistoryDeferred(conv), isFalse);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(
        (await store.deferredState(global.historyWindowScopeFor(conv)!))
            .receivedCount,
        0);
  });

  test('a new visit can load latest without reviving the old durable reading lock',
      () async {
    await receive(1);
    expect(global.historyProjectionDiagnostics(conv)['deferredUntilBottom'],
        isTrue);
    global.clearCurrentConversation();
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    // UIKit starts the new visit synchronously, then removes a retained older
    // window and chooses latest. Its async SQL baseline must not undo that.
    final baseline = global.beginHistoryUnreadVisit(conv);
    global.removeMessageList(conv);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await baseline;
    expect(global.getMessageListPosition(conv), HistoryMessagePosition.bottom);
    expect(global.historyProjectionDiagnostics(conv)['deferredUntilBottom'],
        isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect((await store.deferredState(global.historyWindowScopeFor(conv)!))
        .receivedCount, 1);
    // Later deliveries still remain unread; opening a new page is no ACK.
    await receive(2);
    expect(global.getMessageListPosition(conv), HistoryMessagePosition.bottom);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect((await store.deferredState(global.historyWindowScopeFor(conv)!))
        .receivedCount, 2);
  });

  test('durable publication still protects a live history reader', () async {
    await receive(1);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    expect(global.getMessageListPosition(conv),
        HistoryMessagePosition.notShowLatest);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
  });

  test('starting a visit does not release an explicit search window', () async {
    await receive(1);
    final search = global.beginSearchJump(conv);
    await global.beginHistoryUnreadVisit(conv);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    expect(global.isCurrentSearchJumpRequest(conv, search), isTrue);
    expect(global.getMessageListPosition(conv),
        HistoryMessagePosition.notShowLatest);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect((await store.deferredState(global.historyWindowScopeFor(conv)!))
        .receivedCount, 1);
    global.clearSearchJumpStatus(conv, notify: false);
  });

  test(
      'a batch admitted at bottom then deferred by scroll joins durable counts',
      () async {
    global.chatConfig =
        const TIMUIKitChatConfig(inboundChunkRevealEnabled: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await receive(1);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(global.receivedNewMessageCountFor(conv), 1);
    await receive(2);
    expect(global.receivedNewMessageCountFor(conv), 2);
    final scope = global.historyWindowScopeFor(conv)!;
    expect((await store.deferredState(scope)).receivedCount, 2);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    expect(global.receivedNewMessageCountFor(conv), 0);
  });

  test('a lone coalesced deferred batch is persisted before return watermark',
      () async {
    global.chatConfig =
        const TIMUIKitChatConfig(inboundChunkRevealEnabled: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.bottom,
        notify: false);
    await receive(1);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    expect(watermark, isNotNull);
    expect(
        (await store.deferredState(global.historyWindowScopeFor(conv)!))
            .receivedCount,
        1);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    expect(global.receivedNewMessageCountFor(conv), 0);
  });

  test('switching owner cannot reuse the previous owners durable counter',
      () async {
    await receive(1);
    global.configureMessageWriterScope(
        ownerUserID: 'another-reader',
        accountGeneration: ++generation,
        domainGeneration: 1);
    expect(global.hasDurableHistoryDeferred(conv), isFalse);
    expect(global.receivedNewMessageCountFor(conv), 0);
    expect(
        (await store.deferredState(global.historyWindowScopeFor(conv)!))
            .receivedCount,
        0);
  });

  test('ACK cannot overwrite a newer admission after its count and tail reads',
      () async {
    await receive(1);
    final scope = global.historyWindowScopeFor(conv)!;
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    final tailRead = Completer<void>();
    final release = Completer<void>();
    store.afterTailRead = () {
      tailRead.complete();
      return release.future;
    };
    final ack = global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    await tailRead.future;
    final incoming = receive(2);
    // Give the incoming operation an opportunity to race the old tail snapshot.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    release.complete();
    await Future.wait([ack, incoming]);
    store.afterTailRead = null;
    expect((await store.deferredState(scope)).receivedCount, 1);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 1);
  });

  test(
      'clear fences queued admission and ACK without poisoning the next arrival',
      () async {
    await receive(1);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    final tailRead = Completer<void>();
    final release = Completer<void>();
    store.afterTailRead = () {
      tailRead.complete();
      return release.future;
    };
    final ack = global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    final ackExpectation =
        expectLater(ack, throwsA(isA<HistoryWindowStaleScope>()));
    await tailRead.future;
    final incoming = receive(2);
    final incomingExpectation =
        expectLater(incoming, throwsA(isA<HistoryWindowStaleScope>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await global.clearHistoryWindowData(conv, 1);
    await global.invalidateMessageHistoryCoverage(conv,
        isGroup: false, clearEpoch: 1);
    release.complete();
    await Future.wait([ackExpectation, incomingExpectation]);
    store.afterTailRead = null;
    expect(global.receivedNewMessageCountFor(conv), 0);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    await receive(3);
    expect(global.receivedNewMessageCountFor(conv), 1);
  });

  test(
      'fallback ingress identity does not restart below an acknowledged watermark after LRU',
      () async {
    await receive(1, formal: false);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    await global.resetHistoryWindowAfterLatest(conv);
    global.clearReceivedUnreadState(conversationID: conv, notify: false);
    evictScope();
    await receive(2, formal: false);
    expect(global.receivedNewMessageCountFor(conv), 1);
    expect(
        (await store.deferredState(global.historyWindowScopeFor(conv)!))
            .receivedCount,
        1);
  });

  test('late entry sequence lookup cannot re-lock a dismissed or newer entry',
      () {
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 100, notify: false);
    final oldUpdate = global.captureEntryUnreadSequenceUpdate(conv);
    global.releaseEntryUnreadReminder(conv);
    oldUpdate(501);
    expect(global.lockedEntryUnreadCountFor(conv), 0);
    expect(global.lockedFirstUnreadSeqFor(conv), 0);
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 200, notify: false);
    oldUpdate(501);
    expect(global.lockedFirstUnreadSeqFor(conv), 0);
    final currentUpdate = global.captureEntryUnreadSequenceUpdate(conv);
    currentUpdate(901);
    expect(global.lockedFirstUnreadSeqFor(conv), 901);
    expect(global.lockedEntryUnreadCountFor(conv), 200);
  });
  test('late entry sequence is fenced across owner and clear changes',
      () async {
    global.lockEntryUnreadForTongue(
        conversationID: conv, unreadCount: 100, notify: false);
    final beforeOwner = global.captureEntryUnreadSequenceUpdate(conv);
    global.configureMessageWriterScope(
        ownerUserID: 'new-reader',
        accountGeneration: ++generation,
        domainGeneration: 1);
    beforeOwner(101);
    expect(global.lockedFirstUnreadSeqFor(conv), 0);
    final beforeClear = global.captureEntryUnreadSequenceUpdate(conv);
    await global.clearHistoryWindowData(conv, 1);
    await global.invalidateMessageHistoryCoverage(conv,
        isGroup: false, clearEpoch: 1);
    beforeClear(102);
    expect(global.lockedFirstUnreadSeqFor(conv), 0);
    expect(global.lockedEntryUnreadCountFor(conv), 0);
  });
}
