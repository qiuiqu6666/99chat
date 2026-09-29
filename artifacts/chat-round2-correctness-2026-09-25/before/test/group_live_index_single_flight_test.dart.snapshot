import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_live_models.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_live/group_live_index_sync_service.dart';
import 'package:tencent_cloud_chat_demo/src/services/friend_realtime/friend_realtime_event.dart';

void main() {
  final pending = <Completer<GroupLiveIndexFetchResult>>[];
  late GroupLiveIndexSyncService service;
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  GroupLiveIndexFetchResult snapshot(int revision) =>
      GroupLiveIndexFetchResult.updated(
          snapshot: GroupLiveIndexSnapshot(revision: revision, items: const []),
          etag: '$revision');
  setUp(() {
    pending.clear();
    service = GroupLiveIndexSyncService.forTest(fetch: ({String? ifNoneMatch}) {
      final result = Completer<GroupLiveIndexFetchResult>();
      pending.add(result);
      return result.future;
    });
    service.reset();
  });
  tearDown(() => service.reset());

  test('ordinary refresh bursts share one actual request', () async {
    final first = service.fetchIndex();
    for (var i = 0; i < 20; i++) {
      expect(identical(first, service.fetchIndex(reason: 'poll')), isTrue);
    }
    await flush();
    expect(pending.length, 1);
    pending.single.complete(snapshot(1));
    await first;
    expect(service.store.revision, 1);
  });

  test(
      'invalidation bursts produce one trailing request and discard stale snapshot',
      () async {
    final first = service.fetchIndex();
    await flush();
    for (var i = 0; i < 20; i++) {
      await service.applyGroupLiveChanged(FriendRealtimeEvent(
          event: 'group_changed',
          action: 'group_live_changed',
          groupId: 'g1',
          fromUserId: 'a',
          toUserId: 'b'));
    }
    pending.first.complete(snapshot(1));
    await flush();
    expect(service.store.revision, 0);
    expect(pending.length, 2);
    pending.last.complete(snapshot(2));
    await first;
    expect(pending.length, 2);
    expect(service.store.revision, 2);
  });

  test('account reset rejects old response and serializes new account fetch',
      () async {
    final old = service.fetchIndex();
    await flush();
    service.reset();
    final current = service.fetchIndex();
    await flush();
    expect(pending.length, 1);
    pending.first.complete(snapshot(9));
    await flush();
    expect(service.store.revision, 0);
    expect(pending.length, 2);
    pending.last.complete(snapshot(2));
    await Future.wait([old, current]);
    expect(service.store.revision, 2);
  });

  test('reset before dispatch cancels the queued refresh', () async {
    final task = service.fetchIndex();
    service.reset();
    await task;
    expect(pending, isEmpty);
  });

  test('failure allows the next refresh', () async {
    final first = service.fetchIndex();
    await flush();
    pending.first.completeError(StateError('offline'));
    await first;
    final next = service.fetchIndex();
    await flush();
    expect(pending.length, 2);
    pending.last.complete(snapshot(3));
    await next;
    expect(service.store.revision, 3);
  });
}
