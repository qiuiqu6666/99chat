import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_message_window_policy.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/life_cycle/chat_life_cycle.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late HistoryWindowStore store;
  late TUIChatGlobalModel global;
  var generation = 0;
  late String conv;
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    setupServiceLocator();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SqfliteLifecycleGuard.instance.debugReset();
    dir = await Directory.systemTemp.createTemp('bounded-history-model-');
    store = HistoryWindowStore(debugDatabasePath: '${dir.path}/history.db');
    HistoryWindowRepositoryProvider.repository = store;
    global = serviceLocator<TUIChatGlobalModel>();
    global.configureMessageWriterScope(
        ownerUserID: 'owner',
        accountGeneration: ++generation,
        domainGeneration: 1);
    conv = 'c2c_bounded_$generation';
    global.setCurrentConversation(CurrentConversation(conv, ConvType.c2c));
    global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
        notify: false);
  });
  tearDown(() async {
    global.lifeCycle = null;
    global.clearCurrentConversation();
    global.invalidateBoundedHistorySessions();
    HistoryWindowRepositoryProvider.repository = null;
    await store.closeIfOpen();
    SqfliteLifecycleGuard.instance.debugReset();
    await dir.delete(recursive: true);
  });

  V2TimMessage message(int id, {bool self = false, String? text}) =>
      V2TimMessage.fromJson({
        'message_msg_id': 'm$id',
        'message_server_time': id,
        'message_risk_type_identified': 0,
      })
        ..seq = '$id'
        ..userID = conv.substring(4)
        ..isSelf = self
        ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
        ..elemType = 1
        ..textElem = V2TimTextElem(text: text ?? 'text$id');

  void seed(int count, {bool recentSelf = false}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    global.setMessageList(
        conv,
        List.generate(count, (i) {
          final value = message(count - i, self: recentSelf && i < 60);
          if (recentSelf) value.timestamp = now - i;
          return value;
        }),
        replace: true,
        applyMemoryWindow: false);
    expect(global.rawMessageCount(conv), count);
  }

  test(
      'strict trim retains the configured budget of raw and Writer rows, including recent self compatibility',
      () async {
    seed(600, recentSelf: true);
    final scope = global.historyWindowScopeFor(conv)!;
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    expect(global.rawMessageCount(conv), 600);
    expect(global.commitHistoryWindowTrim(ticket), isTrue);
    expect(global.rawMessageList(conv)!.map((m) => m.msgID),
        ticket.after.map((m) => m.msgID));
    expect(global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize);
    expect(global.messageWriterRetainedCountForTesting(conv),
        ChatMessageWindowPolicy.targetSize);
    expect(global.memoryWindowMissingNewer(conv), isTrue);
    final boundary = global.rawMessageList(conv)!.first;
    final next = await store.readAdjacent(
        scope: scope,
        boundary:
            HistoryWindowBoundary(msgID: boundary.msgID!, seq: boundary.seq),
        direction: HistoryWindowDirection.newer);
    expect(next.status, HistoryWindowReadStatus.hit);
    expect(next.messages, hasLength(50));
    expect(
        next.messages
            .every((m) => int.parse(m.seq!) > int.parse(boundary.seq!)),
        isTrue);
    global.finishHistoryWindowTrim(ticket);
    expect(ticket.before, isEmpty);
    expect(ticket.after, isEmpty);
  });

  test(
      'two offset trims read across overlapping page edges without a cache miss',
      () async {
    global.setMessageList(conv, List.generate(600, (i) => message(1600 - i)),
        replace: true, applyMemoryWindow: false);
    final scope = global.historyWindowScopeFor(conv)!;
    final first = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm1050'))!;
    expect(global.commitHistoryWindowTrim(first), isTrue);
    global.finishHistoryWindowTrim(first);
    final retained = global.rawMessageList(conv)!;
    final oldest = int.parse(retained.last.seq!);
    global.setMessageList(
        conv,
        [
          ...retained,
          ...List.generate(50, (i) => message(oldest - i - 1)),
        ],
        replace: true,
        applyMemoryWindow: false,
        preserveInFlightOutgoing: false);
    final second = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm${oldest - 30}'))!;
    expect(global.commitHistoryWindowTrim(second), isTrue);
    global.finishHistoryWindowTrim(second);
    var boundary = global.rawMessageList(conv)!.first;
    final start = int.parse(boundary.seq!);
    final recovered = <int>[];
    while (int.parse(boundary.seq!) < 1600) {
      final page = await store.readAdjacent(
          scope: scope,
          boundary:
              HistoryWindowBoundary(msgID: boundary.msgID!, seq: boundary.seq),
          direction: HistoryWindowDirection.newer);
      expect(page.status, HistoryWindowReadStatus.hit);
      expect(page.messages, isNotEmpty);
      expect(page.scannedRows, lessThanOrEqualTo(200));
      expect(page.messages.length, lessThanOrEqualTo(50));
      recovered.addAll(page.messages.reversed.map((m) => int.parse(m.seq!)));
      boundary = page.messages.first;
    }
    expect(recovered, List.generate(1600 - start, (i) => start + i + 1));
    expect(global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize);
    expect(global.messageWriterRetainedCountForTesting(conv),
        ChatMessageWindowPolicy.targetSize);
  });

  test('pending revoke cannot spill before SQL and UI rollback both finish',
      () async {
    seed(260);
    final scope = global.historyWindowScopeFor(conv)!;
    final original = message(250);
    final revoked = message(250)
      ..status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
    final token = (await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.revoke,
        message: revoked,
        pending: true))!;
    global.setMessageList(
        conv,
        [
          for (final row in global.rawMessageList(conv)!)
            if (row.msgID == 'm250') revoked else row,
        ],
        replace: true,
        applyMemoryWindow: false);
    expect(
        await global.prepareHistoryWindowTrim(
            conversationID: conv, anchorMsgID: 'm50'),
        isNull);
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.restore,
        capturedScope: scope,
        restoreMutationToken: token);
    // SQL has restored the authority; the UI still holds the optimistic copy.
    expect(
        await global.prepareHistoryWindowTrim(
            conversationID: conv, anchorMsgID: 'm50'),
        isNull);
    final corrected =
        await global.applyHistoryWindowMutations(conv, [original]);
    global.restoreMessageDeltaAfterDeleteFailure(conv, corrected);
    global.finishHistoryWindowMutationProjection(scope: scope, token: token);
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    expect(global.commitHistoryWindowTrim(ticket), isTrue);
    global.finishHistoryWindowTrim(ticket);
    expect(global.rawMessageList(conv)!.any((m) => m.msgID == 'm250'), isFalse);
    final page = await store.readAdjacent(
        scope: scope,
        boundary: const HistoryWindowBoundary(msgID: 'm249', seq: '249'),
        direction: HistoryWindowDirection.newer);
    expect(page.messages.singleWhere((m) => m.msgID == 'm250').status,
        MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(page.messages.singleWhere((m) => m.msgID == 'm250').textElem?.text,
        original.textElem?.text);
  });

  test('failed optimistic revoke never supersedes a later confirmed revoke',
      () async {
    seed(260);
    final scope = global.historyWindowScopeFor(conv)!;
    final token = (await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.revoke,
        pending: true))!;
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.revoke,
        eventID: 'later-sdk-revoke');
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.restore,
        capturedScope: scope,
        restoreMutationToken: token);
    final corrected =
        await global.applyHistoryWindowMutations(conv, [message(250)]);
    expect(
        corrected.single.status, MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    global.restoreMessageDeltaAfterDeleteFailure(conv, corrected);
    global.finishHistoryWindowMutationProjection(scope: scope, token: token);
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    expect(global.commitHistoryWindowTrim(ticket), isTrue);
    global.finishHistoryWindowTrim(ticket);
    final page = await store.readAdjacent(
        scope: scope,
        boundary: const HistoryWindowBoundary(msgID: 'm249', seq: '249'),
        direction: HistoryWindowDirection.newer);
    expect(page.messages.singleWhere((m) => m.msgID == 'm250').status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
  });

  test('revision or account changes reject a prepared trim', () async {
    seed(600);
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    global.setMessageList(conv, [message(601), ...global.rawMessageList(conv)!],
        replace: true, applyMemoryWindow: false);
    expect(global.commitHistoryWindowTrim(ticket), isFalse);
    expect(global.rawMessageList(conv)!.first.msgID, 'm601');
    global.finishHistoryWindowTrim(ticket);
    final next = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    global.configureMessageWriterScope(
        ownerUserID: 'other',
        accountGeneration: ++generation,
        domainGeneration: 1);
    expect(global.commitHistoryWindowTrim(next), isFalse);
    expect(next.finished, isTrue);
  });

  test('rollback reapplies out-of-window edit and delete authority', () async {
    seed(260);
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    expect(global.commitHistoryWindowTrim(ticket), isTrue);
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm250',
        kind: HistoryWindowMutationKind.edit,
        message: message(250, text: 'edited outside'));
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm240',
        kind: HistoryWindowMutationKind.delete);
    expect(await global.rollbackHistoryWindowTrim(ticket), isTrue);
    final rows = global.rawMessageList(conv)!;
    expect(rows, hasLength(259));
    expect(rows.singleWhere((m) => m.msgID == 'm250').textElem!.text,
        'edited outside');
    expect(rows.any((m) => m.msgID == 'm240'), isFalse);
    expect(global.messageWriterRetainedCountForTesting(conv), rows.length);
    global.finishHistoryWindowTrim(ticket);
  });

  test('rollback never overwrites a new row or expands past its hard ceiling',
      () async {
    seed(600);
    final ticket = (await global.prepareHistoryWindowTrim(
        conversationID: conv, anchorMsgID: 'm50'))!;
    expect(global.commitHistoryWindowTrim(ticket), isTrue);
    global.setMessageList(conv, [message(601), ...global.rawMessageList(conv)!],
        replace: true, applyMemoryWindow: false);
    expect(await global.rollbackHistoryWindowTrim(ticket), isFalse);
    expect(
        global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize + 1);
    expect(global.rawMessageList(conv)!.first.msgID, 'm601');
    expect(global.memoryWindowMissingNewer(conv), isTrue);
    global.finishHistoryWindowTrim(ticket);
  });

  test(
      'first incoming row uses mounted C2C and group route geometry for bare SDK IDs',
      () async {
    for (final isGroup in [false, true]) {
      if (isGroup) {
        global.clearCurrentConversation();
        conv = 'group_@TGS#_@TGS#reviewGroup_$generation';
        global
            .setCurrentConversation(CurrentConversation(conv, ConvType.group));
        global.setMessageListPosition(
            conv, HistoryMessagePosition.notShowLatest,
            notify: false);
      }
      V2TimMessage row(int id) {
        final value = message(id);
        if (isGroup) {
          value.userID = null;
          value.groupID = conv.substring('group_'.length);
        }
        return value;
      }

      global.setMessageList(conv, List.generate(600, (i) => row(600 - i)),
          replace: true, applyMemoryWindow: false);
      global.setMessageListPosition(conv, HistoryMessagePosition.notShowLatest,
          notify: false);
      final scope = global.historyWindowScopeFor(conv)!;
      await global.applyAppRealtimeMessage(row(601),
          ingressEventID: 'first', ingressSequence: 1);
      // Check immediately: a timer/batch fallback must not accept this row only
      // in the legacy hot buffer while SQLite still has no durable admission.
      final deferred = await store.deferredState(scope);
      expect(deferred.receivedCount, 1, reason: isGroup ? 'group' : 'C2C');
      expect(deferred.firstIngressSequence, 1);
      expect(global.receivedNewMessageCount, 1);
      expect(global.deferredIncomingBufferedCount(conv), 1);
      expect(global.rawMessageCount(conv), 600);
      expect(global.messageWriterRetainedCountForTesting(conv), 600);
    }
  });

  test(
      '10000 real inbound admissions keep raw and hot buffers bounded; return watermark retains later arrivals',
      () async {
    seed(600);
    final scope = global.historyWindowScopeFor(conv)!;
    const total =
        int.fromEnvironment('BOUNDED_INBOUND_COUNT', defaultValue: 10000);
    for (var i = 1; i <= total; i++) {
      await global.applyAppRealtimeMessage(message(600 + i),
          ingressEventID: 'in$i', ingressSequence: i);
    }
    await global.applyAppRealtimeMessage(message(600 + total),
        ingressEventID: 'in$total', ingressSequence: total);
    expect(global.rawMessageCount(conv), 600);
    expect(global.messageWriterRetainedCountForTesting(conv), 600);
    expect(global.deferredIncomingBufferedCount(conv), 120);
    expect((await store.deferredState(scope)).receivedCount, total,
        reason: 'durable count');
    expect(global.receivedNewMessageCount, total, reason: 'UI count');

    // Durable deferred rows own identities/counts; SDK owns message bodies.
    // The independent in-memory body buffer above must still retain 120 rows.
    expect((await store.debugStatistics())['deferred_bodies'], 0);
    expect(await store.readDeferredTail(scope: scope), isEmpty);
    await store.closeIfOpen();
    expect((await store.deferredState(scope)).receivedCount, total,
        reason: 'all identities survive reopen without duplicate body storage');
    expect((await store.readDeferredMessageIDs(scope: scope)).length, 120);
    expect(global.flushDeferredIncomingMessages(conv, userInitiated: true),
        isFalse);
    final watermark = await global.beginHistoryWindowReturnToLatest(conv);
    await global.applyAppRealtimeMessage(message(601 + total),
        ingressEventID: 'in${total + 1}', ingressSequence: total + 1);
    global.setMessageList(
        conv, List.generate(50, (i) => message(600 + total - i)),
        replace: true, applyMemoryWindow: false);
    await global.acknowledgeHistoryWindowReturnToLatest(conv, watermark);
    expect(global.receivedNewMessageCount, 1);
    expect(global.deferredIncomingBufferedCount(conv), 1);
    expect((await store.deferredState(scope)).receivedCount, 1);
    await global.resetHistoryWindowAfterLatest(conv);
    expect(global.isHistoryWindowScopeCurrent(scope), isFalse);
    expect(global.hasDurableHistoryDeferred(conv), isTrue);
    expect(global.deferredIncomingBufferedCount(conv), 1);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('typing and lifecycle-rejected messages never enter durable history',
      () async {
    seed(600);
    final scope = global.historyWindowScopeFor(conv)!;
    final typing = message(601)
      ..sender = conv.substring(4)
      ..elemType = 2
      ..customElem = V2TimCustomElem(
          data: '{"businessID":"user_typing_status","typingStatus":1}');
    await global.applyAppRealtimeMessage(typing,
        ingressEventID: 'typing', ingressSequence: 1);
    global.lifeCycle = ChatLifeCycle(newMessageWillMount: (_) async => null);
    await global.applyAppRealtimeMessage(message(602),
        ingressEventID: 'filtered', ingressSequence: 2);
    expect((await store.deferredState(scope)).receivedCount, 0);
    expect(global.rawMessageCount(conv), 600);
    expect(global.deferredIncomingBufferedCount(conv), 0);
  });

  test(
      'account change while lifecycle awaits cannot admit old input into new owner',
      () async {
    seed(600);
    final blocked = Completer<V2TimMessage?>();
    final entered = Completer<void>();
    global.lifeCycle = ChatLifeCycle(newMessageWillMount: (_) {
      entered.complete();
      return blocked.future;
    });
    final incoming = global.applyAppRealtimeMessage(message(601),
        ingressEventID: 'late', ingressSequence: 1);
    await entered.future;
    global.configureMessageWriterScope(
        ownerUserID: 'other',
        accountGeneration: ++generation,
        domainGeneration: 1);
    blocked.complete(message(601));
    await incoming;
    expect((await store.debugStatistics())['deferred'], 0);
    expect(global.rawMessageCount(conv), 600);
  });

  test(
      'inactive raw-cache eviction releases Writer membership but leaves durable facts',
      () async {
    seed(600);
    final oldScope = global.historyWindowScopeFor(conv)!;
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm590',
        kind: HistoryWindowMutationKind.delete);
    global.setCurrentConversation(
        CurrentConversation('c2c_another', ConvType.c2c));
    try {
      global.removeMessageList(conv);
      expect(global.rawMessageCount(conv), 0);
      expect(global.messageWriterRetainedCountForTesting(conv), 0);
      expect(global.isHistoryWindowScopeCurrent(oldScope), isFalse);
      expect(await global.applyHistoryWindowMutations(conv, [message(590)]),
          isEmpty);
    } finally {
      global.clearCurrentConversation();
    }
  });

  for (final changeAccount in [true, false]) {
    test(
        'delayed SDK edit cannot cross ${changeAccount ? 'account' : 'clear'} scope',
        () async {
      seed(500);
      final entered = Completer<void>();
      final blocked = Completer<V2TimMessage?>();
      global.lifeCycle = ChatLifeCycle(modifiedMessageWillMount: (_) {
        entered.complete();
        return blocked.future;
      });
      final edit = global.applyAppMessageModified(
          message(100, text: 'late old edit'),
          conversationID: conv);
      await entered.future;
      if (changeAccount) {
        global.configureMessageWriterScope(
            ownerUserID: 'other',
            accountGeneration: ++generation,
            domainGeneration: 1);
      } else {
        await global.clearHistoryWindowData(conv, 1);
        await global.invalidateMessageHistoryCoverage(conv,
            isGroup: false, clearEpoch: 1);
      }
      blocked.complete(message(100, text: 'late old edit'));
      await edit;
      expect(
          global
              .rawMessageList(conv)!
              .singleWhere((m) => m.msgID == 'm100')
              .textElem!
              .text,
          'text100');
      expect(global.messageWriterRetainedCountForTesting(conv), 0);
    });
  }

  for (final self in [false, true]) {
    test(
        '1000 off-window SDK edits (self=$self) update facts without growing the window',
        () async {
      seed(ChatMessageWindowPolicy.targetSize);
      final revision = global.messageListRevisionFor(conv);
      for (var id = 501; id <= 1500; id++) {
        await global.applyAppMessageModified(
            message(id, text: 'updated$id', self: self),
            conversationID: conv,
            ingressEventID: 'edit$id',
            ingressSequence: id);
      }
      expect(global.rawMessageCount(conv), ChatMessageWindowPolicy.targetSize);
      expect(global.messageWriterRetainedCountForTesting(conv),
          ChatMessageWindowPolicy.targetSize);
      expect(global.messageListRevisionFor(conv), revision);
      final restored =
          await global.applyHistoryWindowMutations(conv, [message(1500)]);
      expect(restored.single.textElem!.text, 'updated1500');
    });
  }

  test(
      'failed command restores its exact old-account token after view and owner change',
      () async {
    seed(600);
    final oldScope = global.historyWindowScopeFor(conv)!;
    final token = await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm590',
        kind: HistoryWindowMutationKind.delete,
        pending: true);
    global.configureMessageWriterScope(
        ownerUserID: 'other',
        accountGeneration: ++generation,
        domainGeneration: 1);
    await global.recordHistoryWindowMutation(
        conversationID: conv,
        msgID: 'm590',
        kind: HistoryWindowMutationKind.restore,
        restoreMutationToken: token,
        capturedScope: oldScope);
    final readScope = HistoryWindowScope(
        ownerUserID: oldScope.ownerUserID,
        accountGeneration: oldScope.accountGeneration,
        domainGeneration: oldScope.domainGeneration,
        conversationID: oldScope.conversationID,
        clearEpoch: oldScope.clearEpoch,
        sessionID: 'reopen-old');
    expect(
        await store.applyMutations(scope: readScope, messages: [message(590)]),
        hasLength(1));
  });

  test('SDK self edit still adopts a matching in-window outgoing placeholder',
      () async {
    seed(10);
    final placeholder = message(11, self: true)
      ..msgID = ''
      ..id = 'pending-local-id'
      ..status = 1;
    global.setMessageList(conv, [placeholder, ...global.rawMessageList(conv)!],
        replace: true, applyMemoryWindow: false);
    final accepted = message(100, self: true)..id = 'pending-local-id';
    await global.applyAppMessageModified(accepted, conversationID: conv);
    final rows = global.rawMessageList(conv)!;
    expect(rows, hasLength(11));
    expect(rows.where((m) => m.id == 'pending-local-id'), hasLength(1));
    expect(rows.singleWhere((m) => m.id == 'pending-local-id').msgID, 'm100');
    expect(global.messageWriterRetainedCountForTesting(conv), rows.length);
  });
}
