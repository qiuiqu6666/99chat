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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  final scope = HistoryWindowScope(
      ownerUserID: 'owner',
      accountGeneration: 1,
      domainGeneration: 1,
      conversationID: 'group_g',
      clearEpoch: 0,
      sessionID: 's');
  V2TimMessage row(String id, {String? text}) => V2TimMessage.fromJson({
        'message_msg_id': id,
        'message_server_time': 10,
        'message_risk_type_identified': 0
      })
        ..elemType = 1
        ..status = 2
        ..textElem = V2TimTextElem(text: text ?? id);
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqfliteLifecycleGuard.instance.debugReset();
    MessagePersistCoordinator.instance.resetForTest();
    directory =
        await Directory.systemTemp.createTemp('mobile-history-eviction-');
    store =
        HistoryWindowStore(debugDatabasePath: '${directory.path}/window.db');
  });
  tearDown(() async {
    await store.closeIfOpen();
    await directory.delete(recursive: true);
  });

  test(
      'evicted revoke edit and delete facts survive stale page save and reopen',
      () async {
    for (final entry in {
      'revoked': HistoryWindowMutationKind.revoke,
      'edited': HistoryWindowMutationKind.edit,
      'deleted': HistoryWindowMutationKind.delete
    }.entries) {
      await store.recordMutation(HistoryWindowMutation(
          ownerUserID: 'owner',
          conversationID: 'group_g',
          clearEpoch: 0,
          eventID: entry.key,
          msgID: entry.key,
          kind: entry.value,
          message: entry.value == HistoryWindowMutationKind.edit
              ? row('edited', text: 'latest text')
              : null));
    }
    final coordinator = MessagePersistCoordinator.instance;
    for (var i = 0; i < 5000; i++) {
      coordinator.rememberAuthority(
          conversationId: 'group_g',
          messageId: 'other$i',
          kind: MessagePersistAuthorityKind.edit);
    }
    expect(
        coordinator.authorityFor(
            conversationId: 'group_g', messageId: 'revoked'),
        isNull);
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'root',
        messages: [row('revoked'), row('edited'), row('deleted')],
        isReplayRoot: true));
    await store.closeIfOpen();
    final result = await store.readReplayRoot(scope);
    expect(result.messages.map((m) => m.msgID), ['revoked', 'edited']);
    expect(result.messages.first.status,
        MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED);
    expect(result.messages.last.textElem!.text, 'latest text');
  });

  test('worker round-trip preserves long text IDs and UI-only fields',
      () async {
    final longText = List.filled(6000, '中文😀').join();
    final messages = List.generate(
        40,
        (i) => row('m$i', text: longText)
          ..id = 'local$i'
          ..groupID = 'g'
          ..seq = '$i'
          ..nickName = '昵称$i');
    await store.savePage(HistoryWindowPage(
        scope: scope,
        pageKey: 'large',
        messages: messages,
        isReplayRoot: true));
    final result = await store.readReplayRoot(scope);
    expect(result.messages, hasLength(40));
    for (var i = 0; i < 40; i++) {
      expect(result.messages[i].msgID, 'm$i');
      expect(result.messages[i].id, 'local$i');
      expect(result.messages[i].seq, '$i');
      expect(result.messages[i].nickName, '昵称$i');
      expect(result.messages[i].textElem!.text, longText);
    }
  });
}
