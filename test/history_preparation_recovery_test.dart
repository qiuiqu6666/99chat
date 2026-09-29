import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_persist_coordinator.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

const _scope = HistoryWindowScope(
    ownerUserID: 'owner',
    accountGeneration: 1,
    domainGeneration: 1,
    conversationID: 'group_g',
    clearEpoch: 0,
    sessionID: 's');
V2TimMessage _message() => V2TimMessage.fromJson({
      'message_msg_id': 'm1',
      'message_risk_type_identified': 0,
    })
      ..elemType = 1
      ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
      ..textElem = V2TimTextElem(text: 'before queue');

class _BrokenMessage extends V2TimMessage {
  _BrokenMessage()
      : super.fromJson(
            {'message_msg_id': 'broken', 'message_risk_type_identified': 0});
  @override
  Map<String, dynamic> toJson() => throw StateError('encoding failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final coordinator = MessagePersistCoordinator.instance;
  late Directory directory;
  late HistoryWindowStore store;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqfliteLifecycleGuard.instance.debugReset();
    coordinator.resetForTest();
    directory = await Directory.systemTemp.createTemp('history-preparation-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/history.db');
  });
  tearDown(() async {
    await store.closeIfOpen();
    await directory.delete(recursive: true);
  });

  Future<void> waitUntilQueued() async {
    final deadline = Stopwatch()..start();
    while (coordinator.userHistoryQueueDepth == 0) {
      if (deadline.elapsed > const Duration(seconds: 3)) {
        fail('Page was not queued');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
      'history freezes before writer admission and late revoke wins without mutating SDK object',
      () async {
    final hold = Completer<void>();
    final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () => hold.future);
    final original = _message();
    final saved = store.savePage(
        HistoryWindowPage(scope: _scope, pageKey: 'p', messages: [original]));
    try {
      await waitUntilQueued();
      original.textElem = V2TimTextElem(text: 'changed after queue');
      coordinator.rememberAuthority(
          conversationId: _scope.conversationID,
          messageId: 'm1',
          kind: MessagePersistAuthorityKind.revoke);
    } finally {
      hold.complete();
      await Future.wait([first, saved]);
    }
    final result = await store.readPage(scope: _scope, pageKey: 'p');
    expect(result.messages.single.textElem?.text, 'before queue');
    expect(result.messages.single.status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(original.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    expect(result.messages.single.msgID, 'm1');
  });

  test(
      'encoding failure completes while another writer is held and next save succeeds',
      () async {
    final hold = Completer<void>();
    final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () => hold.future);
    try {
      await expectLater(
          store
              .savePage(HistoryWindowPage(
                  scope: _scope,
                  pageKey: 'broken',
                  messages: [_BrokenMessage()]))
              .timeout(const Duration(seconds: 3)),
          throwsStateError);
      expect(coordinator.userHistoryQueueDepth, 0);
      expect(coordinator.txnInFlight, isTrue);
    } finally {
      hold.complete();
      await first;
    }
    await store.savePage(HistoryWindowPage(
        scope: _scope, pageKey: 'healthy', messages: [_message()]));
    expect((await store.readPage(scope: _scope, pageKey: 'healthy')).messages,
        hasLength(1));
  });

  test(
      'close invalidates already prepared queued pages without reopening database',
      () async {
    final hold = Completer<void>();
    final first = coordinator.enqueue<void>(
        priority: MessagePersistPriority.realtime,
        source: MessagePersistSource.realtime,
        run: () => hold.future);
    final page =
        HistoryWindowPage(scope: _scope, pageKey: 'p', messages: [_message()]);
    final saved = expectLater(
        store.savePage(page), throwsA(isA<SqfliteClosedForBackground>()));
    try {
      await waitUntilQueued();
      await store.closeIfOpen();
    } finally {
      hold.complete();
      await Future.wait([first, saved]);
    }
    expect(store.isOpenForTesting, isFalse);
    await store.savePage(page);
    expect((await store.readPage(scope: _scope, pageKey: 'p')).messages,
        hasLength(1));
  });
}
