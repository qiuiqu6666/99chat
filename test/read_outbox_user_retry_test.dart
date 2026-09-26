import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tencent_cloud_chat_demo/src/services/conversation_local/conversation_local_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/read_outbox_store.dart';

const _owner = 'read_user_retry_owner';
const _id = 'group_@TGS#_mc2SX4NMM62CZ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = ConversationReadOutboxStore.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ConversationLocalStore.instance.debugOwnerUserId = _owner;
    await store.clearOwner(_owner);
  });
  tearDown(() async {
    await store.clearOwner(_owner);
    ConversationLocalStore.instance.debugOwnerUserId = null;
  });
  Future<ConversationReadOutboxRecord> current() async =>
      (await store.find(ownerUserId: _owner, conversationId: _id))!;
  Future<void> seed(String reason) async {
    await store.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        lastReadMessageId: 'seen',
        cleanSequence: 2743454,
        lastReadAtMs: 100);
    await store.markRetry(await current(), reason: reason);
  }

  for (final reason in [
    'blocked:sdk_6017',
    'blocked:storage_6005',
    'reconnect:sdk_6014'
  ]) {
    for (final seq in [2743454, 2743458]) {
      test('fresh user read restarts $reason at sequence $seq', () async {
        await seed(reason);
        final old = await current();
        await store.enqueue(
            ownerUserId: _owner,
            conversationId: _id,
            lastReadMessageId: 'seen',
            cleanSequence: seq,
            lastReadAtMs: 200,
            retryPausedOnUserAction: true);
        final renewed = await current();
        expect(renewed.cleanSequence, seq);
        expect(renewed.cleanTimestamp, 0);
        expect(renewed.retryReason, isEmpty);
        expect(renewed.attemptCount, 0);
        expect(await store.listDue(ownerUserId: _owner), hasLength(1));
        // Late results from the old dispatch cannot erase or block the new read.
        await store.acknowledge(
            ownerUserId: _owner,
            conversationId: _id,
            lastReadAtMs: old.lastReadAtMs);
        await store.markRetry(old, reason: reason);
        expect((await current()).lastReadAtMs, renewed.lastReadAtMs);
        expect((await current()).retryReason, isEmpty);
      });
    }
  }

  test('passive newer snapshot retains SDK pause', () async {
    await seed('blocked:sdk_6017');
    await store.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        cleanSequence: 2743458,
        lastReadAtMs: 200);
    expect((await current()).nextRetryAtMs, -1);
  });
  test('missing watermark and older user action cannot restart work', () async {
    await seed('blocked:sdk_6017');
    await store.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        lastReadAtMs: 200,
        retryPausedOnUserAction: true);
    expect((await current()).nextRetryAtMs, -1);
    await store.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        cleanSequence: 2743458,
        lastReadAtMs: 99,
        retryPausedOnUserAction: true);
    expect((await current()).nextRetryAtMs, -1);
    expect((await current()).cleanSequence, 2743454);
  });
  test('user action preserves frequency cooldown', () async {
    await seed('transient:sdk_frequency_block');
    final before = await current();
    await store.enqueue(
        ownerUserId: _owner,
        conversationId: _id,
        cleanSequence: 2743458,
        lastReadAtMs: 200,
        retryPausedOnUserAction: true);
    expect((await current()).nextRetryAtMs, before.nextRetryAtMs);
    expect((await current()).attemptCount, before.attemptCount);
  });
}
