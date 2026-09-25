import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_receipt_outbox_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ConversationLocalStore.instance.debugOwnerUserId = 'read_outbox_owner';
    await ConversationReadOutboxStore.instance.clearOwner('read_outbox_owner');
    await ReadReceiptOutboxStore.instance.clearOwner('read_outbox_owner');
  });

  tearDown(() async {
    await ConversationReadOutboxStore.instance.clearOwner('read_outbox_owner');
    await ReadReceiptOutboxStore.instance.clearOwner('read_outbox_owner');
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });

  test('older enqueue and acknowledgement cannot erase a newer read intent',
      () async {
    final store = ConversationReadOutboxStore.instance;
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'new-message',
      lastReadAtMs: 200,
    );
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'old-message',
      lastReadAtMs: 100,
    );

    var rows = await store.listDue(ownerUserId: 'read_outbox_owner');
    expect(rows, hasLength(1));
    expect(rows.single.lastReadAtMs, 200);
    expect(rows.single.lastReadMessageId, 'new-message');

    await store.acknowledge(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadAtMs: 100,
    );
    rows = await store.listDue(ownerUserId: 'read_outbox_owner');
    expect(rows, hasLength(1));

    await store.acknowledge(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadAtMs: 200,
    );
    expect(
      await store.listDue(ownerUserId: 'read_outbox_owner'),
      isEmpty,
    );
  });

  test('a valid new watermark wakes only watermark-blocked work', () async {
    final store = ConversationReadOutboxStore.instance;
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'w2',
      lastReadAtMs: 200,
    );
    final w2 = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    await store.markRetry(w2, reason: 'blocked:watermark_unavailable');
    expect(await store.listDue(ownerUserId: 'read_outbox_owner'), isEmpty);

    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'w3',
      cleanTimestamp: 123,
      lastReadAtMs: 300,
    );
    final w3 = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(w3.cleanTimestamp, 123);
    expect(w3.attemptCount, 1);
    expect(w3.createdAtMs, w2.createdAtMs);
    expect(await store.listDue(ownerUserId: 'read_outbox_owner'), hasLength(1));

    await store.markRetry(w2, reason: 'blocked:watermark_unavailable');
    expect(
        (await store.find(
          ownerUserId: 'read_outbox_owner',
          conversationId: 'c2c_bob',
        ))!
            .cleanTimestamp,
        123);
  });

  test('new watermark does not clear SDK block or reconnect retry history',
      () async {
    final store = ConversationReadOutboxStore.instance;
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'w2',
      lastReadAtMs: 200,
    );
    final blocked = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    await store.markRetry(blocked, reason: 'blocked:sdk_6017');
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      lastReadMessageId: 'w3',
      cleanTimestamp: 123,
      lastReadAtMs: 300,
    );
    expect(await store.listDue(ownerUserId: 'read_outbox_owner'), isEmpty);
    final w3 = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(w3.attemptCount, 1);
    await store.markRetry(w3, reason: 'reconnect:sdk_other');
    await store.resumeAfterReconnect('read_outbox_owner');
    final resumed = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(resumed.attemptCount, 2);
    expect(resumed.createdAtMs, w3.createdAtMs);
    await store.resumeAfterReconnect('read_outbox_owner');
    expect(
        (await store.find(
          ownerUserId: 'read_outbox_owner',
          conversationId: 'c2c_bob',
        ))!
            .attemptCount,
        2);
  });

  test(
      'frequency block keeps its cooldown and does not consume a skipped attempt',
      () async {
    final store = ConversationReadOutboxStore.instance;
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      cleanTimestamp: 100,
      lastReadAtMs: 100,
    );
    final w2 = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    final cooldown = DateTime.now().millisecondsSinceEpoch + 12000;
    await store.deferUntilIfCurrent(w2, cooldown);
    final deferred = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(deferred.nextRetryAtMs, cooldown);
    expect(deferred.attemptCount, 0);
    expect(await store.listDue(ownerUserId: 'read_outbox_owner'), isEmpty);

    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
      cleanTimestamp: 101,
      lastReadAtMs: 101,
    );
    await store.deferUntilIfCurrent(w2, cooldown + 1000);
    final w3 = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(w3.cleanTimestamp, 101);
    expect(w3.nextRetryAtMs, cooldown);

    await store.markRetry(w3, sdkCode: -10113, notBeforeAtMs: cooldown + 2000);
    final failed = (await store.find(
      ownerUserId: 'read_outbox_owner',
      conversationId: 'c2c_bob',
    ))!;
    expect(failed.retryReason, 'transient:sdk_frequency_block');
    expect(failed.nextRetryAtMs, greaterThanOrEqualTo(cooldown + 2000));
    expect(failed.attemptCount, 1);
  });

  test('due scan advances past a full page without revisiting its rows',
      () async {
    final store = ConversationReadOutboxStore.instance;
    for (final id in <String>['c2c_a', 'c2c_b', 'c2c_c']) {
      await store.enqueue(
        ownerUserId: 'read_outbox_owner',
        conversationId: id,
        cleanTimestamp: 100,
        lastReadAtMs: 100,
      );
    }
    final first = await store.listDue(
      ownerUserId: 'read_outbox_owner',
      afterConversationId: '',
      limit: 2,
    );
    final second = await store.listDue(
      ownerUserId: 'read_outbox_owner',
      afterConversationId: first.last.conversationId,
      limit: 2,
    );
    expect(first.map((row) => row.conversationId), <String>['c2c_a', 'c2c_b']);
    expect(second.map((row) => row.conversationId), <String>['c2c_c']);
  });

  test('read receipt row is removed only after explicit acknowledgement',
      () async {
    final store = ReadReceiptOutboxStore.instance;
    await store.enqueue(
      ownerUserId: 'read_outbox_owner',
      messageIds: const <String>['m1', 'm2', 'm1'],
    );

    expect(
      await store.listDue(ownerUserId: 'read_outbox_owner'),
      hasLength(2),
    );
    await store.acknowledge(
      ownerUserId: 'read_outbox_owner',
      messageIds: const <String>['m1'],
    );
    final rows = await store.listDue(ownerUserId: 'read_outbox_owner');
    expect(rows.map((row) => row.messageId), <String>['m2']);
  });
}
