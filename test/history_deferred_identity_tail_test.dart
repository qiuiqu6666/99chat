import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/history_window_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/sqflite_lifecycle_guard.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_window_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryWindowStore store;
  HistoryWindowScope scope(
          {String owner = 'owner',
          int epoch = 0,
          bool Function()? isCurrent}) =>
      HistoryWindowScope(
        ownerUserID: owner,
        accountGeneration: 1,
        domainGeneration: 1,
        conversationID: 'group_g',
        clearEpoch: epoch,
        sessionID: 'tail',
        isCurrent: isCurrent,
      );
  Future<void> append(int id, {HistoryWindowScope? into}) async {
    final row = V2TimMessage.fromJson({
      'message_msg_id': 'm$id',
      'message_server_time': id,
      'message_risk_type_identified': 0,
    })
      ..isSelf = false
      ..isRead = false
      ..groupID = 'g'
      ..seq = '$id';
    await store.appendDeferred(
        scope: into ?? scope(),
        eventID: 'e$id',
        ingressSequence: id,
        message: row);
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SqfliteLifecycleGuard.instance.debugReset();
    directory = await Directory.systemTemp.createTemp('identity-tail-');
    store = HistoryWindowStore(debugDatabasePath: '${directory.path}/tail.db');
  });
  tearDown(() async {
    await store.closeIfOpen();
    await directory.delete(recursive: true);
    SqfliteLifecycleGuard.instance.debugReset();
  });

  test('identity-only pending tail is exact, bounded, and does not acknowledge',
      () async {
    for (var id = 1; id <= 125; id++) {
      await append(id);
    }
    expect(await store.readDeferredMessageIDs(scope: scope(), limit: 2),
        {'m125', 'm124'});
    final capped =
        await store.readDeferredMessageIDs(scope: scope(), limit: 1000);
    expect(capped.length, 120);
    expect(capped.contains('m5'), isFalse);
    expect((await store.deferredState(scope())).receivedCount, 125);
    await store.acknowledgeVisibleDeferred(
        scope: scope(), messageIDs: ['m125'], afterIngressSequence: 0);
    expect(await store.readDeferredMessageIDs(scope: scope(), limit: 2),
        {'m124', 'm123'});
  });

  test('identity tail keeps owners and clear epochs separate', () async {
    await append(1);
    await append(2, into: scope(owner: 'other'));
    expect(await store.readDeferredMessageIDs(scope: scope()), {'m1'});
    expect(await store.readDeferredMessageIDs(scope: scope(owner: 'other')),
        {'m2'});
    await store.clearConversation(
        ownerUserID: 'owner', conversationID: 'group_g', clearEpoch: 1);
    await expectLater(store.readDeferredMessageIDs(scope: scope()),
        throwsA(isA<HistoryWindowStaleScope>()));
    expect(await store.readDeferredMessageIDs(scope: scope(epoch: 1)), isEmpty);
    expect(await store.readDeferredMessageIDs(scope: scope(owner: 'other')),
        {'m2'});
  });

  test('stale owner lease cannot read pending identities', () async {
    await append(1);
    await expectLater(
        store.readDeferredMessageIDs(scope: scope(isCurrent: () => false)),
        throwsA(isA<HistoryWindowStaleScope>()));
  });
}
