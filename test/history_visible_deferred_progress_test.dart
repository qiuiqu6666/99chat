import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

class _AfterVisibleCommitStore extends HistoryWindowStore {
  _AfterVisibleCommitStore({required super.debugDatabasePath});

  void Function()? afterVisibleCommit;
  Completer<void>? appended;
  Completer<void>? publishGate;

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
    final gate = publishGate;
    if (gate != null) {
      appended?.complete();
      await gate.future;
    }
    return receipt;
  }

  @override
  Future<HistoryWindowVisibleReceipt> acknowledgeVisibleDeferred({
    required HistoryWindowScope scope,
    required List<String> messageIDs,
    required int afterIngressSequence,
    bool Function()? isCurrent,
  }) async {
    final receipt = await super.acknowledgeVisibleDeferred(
        scope: scope,
        messageIDs: messageIDs,
        afterIngressSequence: afterIngressSequence,
        isCurrent: isCurrent);
    afterVisibleCommit?.call();
    return receipt;
  }
}

V2TimMessage _message(String id, int groupSequence) => V2TimMessage.fromJson({
      'message_msg_id': id,
      'message_seq': '$groupSequence',
      'message_server_time': groupSequence,
      'message_risk_type_identified': 0,
    })
      ..groupID = 'progress'
      ..seq = '$groupSequence'
      ..status = 2
      ..isSelf = false
      ..isRead = false
      ..elemType = 1
      ..textElem = V2TimTextElem(text: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  const owner = 'visible-progress-reader';
  const conversation = 'group_progress';
  late HistoryWindowScope scope;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory = await Directory.systemTemp.createTemp('visible-deferred-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
    scope = const HistoryWindowScope(
        ownerUserID: owner,
        accountGeneration: 1,
        domainGeneration: 1,
        conversationID: conversation,
        clearEpoch: 0,
        sessionID: 'visible-progress-session');
  });

  tearDown(() async {
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await directory.delete(recursive: true);
  });

  Future<HistoryWindowDeferredReceipt> append(String id, int sourceSequence,
          {bool formal = true, int? groupSequence, String? eventID}) =>
      store.appendDeferred(
          scope: scope,
          eventID: eventID ?? 'event-$id',
          ingressSequence: sourceSequence,
          hasStableIngressSequence: formal,
          message: _message(id, groupSequence ?? sourceSequence));

  Future<HistoryWindowVisibleReceipt> see(List<String> ids,
          {int after = -1, bool Function()? isCurrent}) =>
      store.acknowledgeVisibleDeferred(
          scope: scope,
          messageIDs: ids,
          afterIngressSequence: after,
          isCurrent: isCurrent);

  Future<Set<String>> persistedIDs({required bool acknowledged}) async {
    // Deferred storage intentionally keeps metadata only. Inspect its durable
    // identity rows instead of expecting payloads from readDeferredTail().
    final audit = await databaseFactoryFfi.openDatabase(
        '${directory.path}/history.db',
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      final rows = await audit.query('hw_deferred',
          columns: ['msg_id'],
          where: 'acknowledged = ?',
          whereArgs: [acknowledged ? 1 : 0]);
      return rows.map((row) => row['msg_id']! as String).toSet();
    } finally {
      await audit.close();
    }
  }

  Future<void> expectPending(Set<String> expected) async {
    final state = await store.deferredState(scope);
    expect(state.receivedCount, expected.length);
    expect(state.unreadCount, expected.length);
    expect(await persistedIDs(acknowledged: false), expected);
  }

  test('one visible identity consumes one delivery exactly once', () async {
    await append('first', 101);
    await append('second', 102);
    await append('third', 103);
    final before = await store.deferredState(scope);

    final seen = await see(['second', 'second', 'not-delivered']);
    expect(seen.acknowledgedMessageIDs, {'second'});
    expect(seen.state.receivedCount, 2);
    expect(seen.state.acknowledgedThroughSequence,
        before.acknowledgedThroughSequence,
        reason:
            'an exact-ID acknowledgement must not advance the prefix fence');
    await expectPending({'first', 'third'});

    final duplicate = await see(['second']);
    expect(duplicate.acknowledgedMessageIDs, isEmpty);
    expect(duplicate.state.receivedCount, 2);
    await expectPending({'first', 'third'});
  });

  test('out-of-order delivery and equal group sequences still use exact IDs',
      () async {
    await append('newer-group-seq', 300, groupSequence: 30);
    await append('same-seq-a', 100, groupSequence: 10);
    await append('same-seq-b', 200, groupSequence: 10);
    final before = await store.deferredState(scope);

    final seen = await see(['same-seq-b']);
    expect(seen.acknowledgedMessageIDs, {'same-seq-b'});
    expect(seen.state.receivedCount, 2);
    expect(seen.state.acknowledgedThroughSequence,
        before.acknowledgedThroughSequence);
    await expectPending({'newer-group-seq', 'same-seq-a'});

    // Reading source 200 must not make a later delivery with source 150 stale.
    final lowerSource = await append('later-arriving-source-150', 150);
    expect(lowerSource.inserted, isTrue);
    await expectPending(
        {'newer-group-seq', 'same-seq-a', 'later-arriving-source-150'});
  });

  test('a reading baseline excludes older pending deliveries from seen IDs',
      () async {
    await append('baseline-old-a', 1);
    final old = await append('baseline-old-b', 2);
    final baseline = old.state.lastIngressSequence!;
    await append('new-a', 3);
    await append('new-b', 4);
    await append('new-c', 5);

    final seen = await see(['baseline-old-a', 'baseline-old-b', 'new-a'],
        after: baseline);
    expect(seen.acknowledgedMessageIDs, {'new-a'});
    expect(seen.state.receivedCount, 4,
        reason: 'the two baseline rows and two unseen arrivals remain pending');
    await expectPending({'baseline-old-a', 'baseline-old-b', 'new-b', 'new-c'});
  });

  for (final formal in [true, false]) {
    test(
        'arrival ordinal stays monotonic after seeing its maximum (formal=$formal)',
        () async {
      await append('one', 10, formal: formal);
      await append('two', 20, formal: formal);
      final newest = await append('three', 30, formal: formal);
      final highestArrival = newest.state.lastIngressSequence!;

      final seen = await see(['three']);
      expect(seen.acknowledgedMessageIDs, {'three'});
      expect(seen.state.lastIngressSequence, lessThan(highestArrival));
      final appended = await append('four', 40, formal: formal);
      expect(appended.inserted, isTrue);
      expect(appended.state.lastIngressSequence, greaterThan(highestArrival),
          reason:
              'acknowledged identity rows still reserve their arrival ordinals');
      await expectPending({'one', 'two', 'four'});
    });
  }

  test(
      'partial then full ACK survives reopen and rejects formal and fallback replay',
      () async {
    await append('formal-low', 100);
    await append('formal-high', 900);
    final fallback = await append('fallback', 99999, formal: false);
    final snapshot = fallback.state.lastIngressSequence!;

    final seen = await see(['formal-high', 'fallback']);
    expect(seen.acknowledgedMessageIDs, {'formal-high', 'fallback'});
    expect(await persistedIDs(acknowledged: true), {'formal-high', 'fallback'});
    await expectPending({'formal-low'});
    await store.acknowledgeDeferred(
        scope: scope, throughIngressSequence: snapshot);
    await expectPending({});
    await store.closeIfOpen();

    expect((await store.deferredState(scope)).receivedCount, 0);
    final formalReplay =
        await append('formal-high', 900, eventID: 'replayed-formal-event');
    expect(formalReplay.inserted, isFalse);
    final fallbackReplay = await append('fallback', 88888,
        formal: false, eventID: 'replayed-fallback-event');
    expect(fallbackReplay.inserted, isFalse);
    // The full ACK must include the already-exact-ACKed source 900 when
    // advancing its formal fence, not only the still-pending source 100.
    final sourceAliasReplay =
        await append('replayed-source-with-another-id', 900);
    expect(sourceAliasReplay.inserted, isFalse);
    await expectPending({});

    final fresh = await append('fresh', 901);
    expect(fresh.inserted, isTrue);
    expect(fresh.state.lastIngressSequence, greaterThan(snapshot));
    await expectPending({'fresh'});
  });

  test(
      'an invalidated visible request rejects acknowledgement without consuming data',
      () async {
    await append('first', 1);
    await append('second', 2);
    var current = true;
    final pending = see(['first'], isCurrent: () => current);
    current = false;

    await expectLater(pending, throwsA(isA<HistoryWindowStaleScope>()));
    await expectPending({'first', 'second'});
    final retry = await see(['first'], isCurrent: () => true);
    expect(retry.acknowledgedMessageIDs, {'first'});
    await expectPending({'second'});
  });

  test('one visible request consumes all 220 candidates across SQL batches',
      () async {
    final ids = [for (var index = 1; index <= 220; index++) 'candidate-$index'];
    for (var index = 0; index < ids.length; index++) {
      await append(ids[index], index + 1);
    }
    final before = await store.deferredState(scope);

    final seen = await see(ids);
    expect(seen.acknowledgedMessageIDs, ids.toSet());
    expect(seen.state.receivedCount, 0,
        reason:
            'the 120-row SQL batch size must not truncate caller candidates');
    expect(seen.state.acknowledgedThroughSequence,
        before.acknowledgedThroughSequence);
    await expectPending({});
    expect(await persistedIDs(acknowledged: true), ids.toSet());

    final duplicate = await see(ids);
    expect(duplicate.acknowledgedMessageIDs, isEmpty);
    expect(duplicate.state.receivedCount, 0);
    await expectPending({});
  });

  test('reading during local-to-durable migration never revives an unread ID',
      () async {
    final observed = _AfterVisibleCommitStore(
        debugDatabasePath: '${directory.path}/history.db');
    store = observed;
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#local_promotion_race';
    global.configureMessageWriterScope(
        ownerUserID: owner, accountGeneration: 44, domainGeneration: 1);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    final old = _message('race-old', 100)..groupID = conv;
    final incoming = _message('race-new', 101)..groupID = conv;
    global.setMessageList(conv, [old]);
    await global.beginHistoryUnreadVisit(conv);
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.awayTwoScreen,
        notify: false);
    try {
      await global.applyAppRealtimeMessage(incoming);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      global.commitBufferedIncomingReveal(
          conv, global.copyBufferedIncomingPage(conv, limit: 1));
      expect(global.receivedNewMessageCountFor(conv), 1);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
          notify: false);
      observed.appended = Completer<void>();
      observed.publishGate = Completer<void>();
      final promotion = global.applyAppRealtimeMessage(incoming,
          ingressEventID: 'promote-race-new', ingressSequence: 101);
      await observed.appended!.future;
      final visible = global.acknowledgeVisibleHistoryMessages(conv, [incoming],
          isCurrent: () => true);
      expect(global.receivedNewMessageCountFor(conv), 1,
          reason: 'wait for the ordered migration before consuming the ID');
      observed.publishGate!.complete();
      await promotion;
      expect(await visible, isTrue);
      scope = global.historyWindowScopeFor(conv)!;
      expect(global.receivedNewMessageCountFor(conv), 1,
          reason: 'tongue N must not fall while the reader is still away');
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect((await store.deferredState(scope)).receivedCount, 0);
      global.settleAtTrueLatestEnd(conv);
      expect(global.receivedNewMessageCountFor(conv), 0);
    } finally {
      if (observed.publishGate?.isCompleted == false)
        observed.publishGate!.complete();
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
    }
  });

  test(
      'local unread identities survive durable transition without double count',
      () async {
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#mixed_visible_progress';
    global.configureMessageWriterScope(
        ownerUserID: owner, accountGeneration: 43, domainGeneration: 1);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    final rows = [
      for (var seq = 100; seq <= 104; seq++)
        _message('mixed-$seq', seq)..groupID = conv
    ];
    global.setMessageList(conv, [rows.first]);
    await global.beginHistoryUnreadVisit(conv);
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.awayTwoScreen,
        notify: false);
    try {
      for (final message in rows.sublist(1, 4)) {
        await global.applyAppRealtimeMessage(message);
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.receivedNewMessageCountFor(conv), 3);
      global.commitBufferedIncomingReveal(
          conv, global.copyBufferedIncomingPage(conv, limit: 1));
      expect(global.deferredIncomingBufferedCount(conv), 2);
      expect(global.receivedNewMessageCountFor(conv), 3);

      global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
          notify: false);
      await global.applyAppRealtimeMessage(rows[4],
          ingressEventID: 'durable-104', ingressSequence: 104);
      scope = global.historyWindowScopeFor(conv)!;
      expect((await store.deferredState(scope)).receivedCount, 1);
      expect(global.receivedNewMessageCountFor(conv), 4,
          reason:
              'SQL publication must retain both attached and buffered hot IDs');

      await global.applyAppRealtimeMessage(rows[1],
          ingressEventID: 'replayed-local-101', ingressSequence: 105);
      expect(global.receivedNewMessageCountFor(conv), 4,
          reason: 'the same ID moves to SQL instead of counting twice');
      expect((await store.deferredState(scope)).receivedCount, 2);
      for (var index = 1; index <= 4; index++) {
        expect(
            await global.acknowledgeVisibleHistoryMessages(conv, [rows[index]],
                isCurrent: () => true),
            isTrue);
        expect(global.receivedNewMessageCountFor(conv), 4,
            reason: 'tongue N does not decrement per crossed row');
        expect(
            await global.acknowledgeVisibleHistoryMessages(conv, [rows[index]],
                isCurrent: () => true),
            isFalse);
      }
      expect(global.deferredIncomingBufferedCount(conv), 0);
      expect((await store.deferredState(scope)).receivedCount, 0);
      global.settleAtTrueLatestEnd(conv);
      expect(global.receivedNewMessageCountFor(conv), 0);
    } finally {
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
    }
  });

  test(
      'committed visible ACK publishes counts and removes hot rows after viewport invalidation',
      () async {
    final observedStore = _AfterVisibleCommitStore(
        debugDatabasePath: '${directory.path}/history.db');
    store = observedStore;
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#visible_progress_global';
    global.configureMessageWriterScope(
        ownerUserID: owner, accountGeneration: 42, domainGeneration: 1);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    try {
      await global.beginHistoryUnreadVisit(conv);
      final first = _message('first', 101)..groupID = conv;
      final second = _message('second', 102)..groupID = conv;
      await global.applyAppRealtimeMessage(first,
          ingressEventID: 'first-arrival', ingressSequence: 101);
      await global.applyAppRealtimeMessage(second,
          ingressEventID: 'second-arrival', ingressSequence: 102);
      scope = global.historyWindowScopeFor(conv)!;
      expect(global.receivedNewMessageCountFor(conv), 2);
      expect(global.deferredIncomingBufferedCount(conv), 2);
      await expectPending({'first', 'second'});

      var current = true;
      observedStore.afterVisibleCommit = () => current = false;
      expect(
          await global.acknowledgeVisibleHistoryMessages(conv, [first],
              isCurrent: () => current),
          isTrue);
      expect(current, isFalse,
          reason: 'the viewport became stale only after SQLite committed');
      expect(global.receivedNewMessageCountFor(conv), 2,
          reason: 'tongue N stays until true latest end, even after a durable ACK');
      expect(global.deferredIncomingBufferedCount(conv), 1);
      await expectPending({'second'});

      observedStore.afterVisibleCommit = null;
      expect(
          await global.acknowledgeVisibleHistoryMessages(conv, [second],
              isCurrent: () => true),
          isTrue);
      expect(global.receivedNewMessageCountFor(conv), 2);
      expect(global.deferredIncomingBufferedCount(conv), 0,
          reason: 'only the second identity remained in the hot buffer');
      await expectPending({});
      global.settleAtTrueLatestEnd(conv);
      expect(global.receivedNewMessageCountFor(conv), 0);
    } finally {
      observedStore.afterVisibleCommit = null;
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
    }
  });

  test(
      'settle at true latest end absorbs later SQL publish without reviving N',
      () async {
    HistoryWindowRepositoryProvider.repository = store;
    final global = serviceLocator<TUIChatGlobalModel>();
    const conv = '@TGS#settle_absorb_sql';
    global.configureMessageWriterScope(
        ownerUserID: owner, accountGeneration: 45, domainGeneration: 1);
    global.setCurrentConversation(CurrentConversation(conv, ConvType.group));
    final old = _message('absorb-old', 100)..groupID = conv;
    final incoming = _message('absorb-new', 101)..groupID = conv;
    final next = _message('absorb-next', 102)..groupID = conv;
    global.setMessageList(conv, [old]);
    await global.beginHistoryUnreadVisit(conv);
    global.setFollowingLatest(conv, false, notify: false);
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
    try {
      await global.applyAppRealtimeMessage(incoming,
          ingressEventID: 'absorb-new', ingressSequence: 101);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(global.receivedNewMessageCountFor(conv), 1);
      global.settleAtTrueLatestEnd(conv);
      expect(global.receivedNewMessageCountFor(conv), 0);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(global.receivedNewMessageCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      await global.applyAppRealtimeMessage(next,
          ingressEventID: 'absorb-next', ingressSequence: 102);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(global.receivedNewMessageCountFor(conv), 0);
      expect(global.hasDurableHistoryDeferred(conv), isFalse);
      expect(global.isFollowingLatest(conv), isTrue);
      expect(global.rawMessageList(conv)!.first.msgID, 'absorb-next');
    } finally {
      global.clearCurrentConversation();
      global.invalidateBoundedHistorySessions();
      HistoryWindowRepositoryProvider.repository = null;
    }
  });
}
