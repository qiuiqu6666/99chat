import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/api/me_group_api.dart';
import 'package:tencent_cloud_chat_demo/src/models/group_member_change.dart';
import 'package:tencent_cloud_chat_demo/src/models/me_group_record.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/group_member_incremental_sync_service.dart';

GroupMemberChangeEvent _upsert(int seq, {String groupId = 'g'}) =>
    GroupMemberChangeEvent(
      seq: seq,
      type: 'MEMBER_UPSERTED',
      groupId: groupId,
      userId: 'u$seq',
      nickName: 'User $seq',
    );

GroupMemberChangeEvent _remove(int seq, String userId) =>
    GroupMemberChangeEvent(
      seq: seq,
      type: 'MEMBER_REMOVED',
      groupId: 'g',
      userId: userId,
    );

GroupMemberRecord _record(String userId) => GroupMemberRecord(
      userId: userId,
      nickname: userId,
      avatarUrl: '',
      friendRemark: '',
      nameCard: '',
      role: 0,
      joinedAt: 0,
      isSelf: false,
    );

class _Harness {
  int cursor;
  _Harness({this.cursor = 0});

  final applied = <int>[];
  final removedUsers = <String>[];
  final calls = <int>[];
  List<GroupMemberRecord>? replacedWith;
  List<GroupMemberChangeEvent>? eventOverride;
  Completer<GroupMemberChangesPage>? firstPageGate;

  late final service = GroupMemberIncrementalSyncService.forTesting(
    ownerUserId: 'owner',
    readCursor: (_, __) async => cursor,
    writeCursor: (seq, _, __) async => cursor = seq,
    clearCursor: (_, __) async => cursor = 0,
    fetchChanges: (group, since, limit) async {
      calls.add(since);
      final gate = firstPageGate;
      if (gate != null && calls.length == 1) return gate.future;
      final events = eventOverride == null
          ? <GroupMemberChangeEvent>[
              for (var seq = since + 1; seq <= 10; seq++) _upsert(seq),
            ]
          : eventOverride!.where((event) => event.seq > since).toList();
      return GroupMemberChangesPage(
        nextSeq: events.isEmpty ? since : events.last.seq,
        hasMore: false,
        events: events,
      );
    },
    fetchSnapshot: (_, limit, offset) async {
      final all = <GroupMemberRecord>[_record('one'), _record('two')];
      final end = (offset + limit).clamp(0, all.length);
      return GroupMembersPage(
        groupId: 'g',
        items: all.sublist(offset.clamp(0, all.length), end),
        total: all.length,
        limit: limit,
        offset: offset,
        hasMore: end < all.length,
      );
    },
    applyEvent: (_, __, event) async {
      applied.add(event.seq);
      if (event.isRemoved) removedUsers.add(event.userId);
      cursor = event.seq;
    },
    replaceSnapshot: (_, __, records) async {
      replacedWith = List<GroupMemberRecord>.of(records);
    },
  );
}

void main() {
  test('a realtime hole replays every missing member event in order', () async {
    final h = _Harness(cursor: 2);
    await h.service.noteRealtimeSeq(groupId: 'g', seq: 5);
    expect(h.calls, [2]);
    expect(h.applied, [3, 4, 5]);
    expect(h.cursor, 5);
    expect(h.replacedWith, isNull);
  });

  test('first event after an empty baseline is replayed from sequence one',
      () async {
    final h = _Harness();
    await h.service.noteRealtimeSeq(groupId: 'g', seq: 4);
    expect(h.applied, [1, 2, 3, 4]);
    expect(h.cursor, 4);
  });

  test('gap replay restores a deletion that the realtime stream skipped',
      () async {
    final h = _Harness(cursor: 3)
      ..eventOverride = [_upsert(4), _remove(5, 'departed-user')];
    await h.service.noteRealtimeSeq(groupId: 'g', seq: 5);
    expect(h.applied, [4, 5]);
    expect(h.removedUsers, ['departed-user']);
    expect(h.cursor, 5);
  });

  test('expired cursor takes a complete snapshot before advancing baseline',
      () async {
    var cursor = 0;
    List<GroupMemberRecord>? replaced;
    var fetchCount = 0;
    final service = GroupMemberIncrementalSyncService.forTesting(
      ownerUserId: 'owner',
      readCursor: (_, __) async => cursor,
      writeCursor: (seq, _, __) async => cursor = seq,
      clearCursor: (_, __) async => cursor = 0,
      fetchChanges: (_, __, ___) async {
        throw GroupMemberCursorExpiredException();
      },
      fetchSnapshot: (_, limit, offset) async {
        fetchCount++;
        final items = offset == 0 ? [_record('first')] : [_record('second')];
        return GroupMembersPage(
          groupId: 'g',
          items: items,
          total: 2,
          limit: 1,
          offset: offset,
          hasMore: offset == 0,
        );
      },
      applyEvent: (_, __, ___) async => fail('expired cursor must snapshot'),
      replaceSnapshot: (_, __, records) async {
        replaced = List<GroupMemberRecord>.of(records);
      },
    );

    await service.noteRealtimeSeq(groupId: 'g', seq: 40);
    expect(fetchCount, 2);
    expect(replaced?.map((e) => e.userId).toList(), ['first', 'second']);
    expect(cursor, 40);
  });

  test('a higher realtime target arriving during repair is not dropped',
      () async {
    final h = _Harness()..firstPageGate = Completer<GroupMemberChangesPage>();
    final first = h.service.noteRealtimeSeq(groupId: 'g', seq: 3);
    while (h.calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = h.service.noteRealtimeSeq(groupId: 'g', seq: 5);
    h.firstPageGate!.complete(GroupMemberChangesPage(
      nextSeq: 10,
      hasMore: false,
      events: [_upsert(1), _upsert(2), _upsert(3), _upsert(4), _upsert(5)],
    ));
    await Future.wait<void>([first, second]);
    expect(h.cursor, 5);
    expect(h.applied, [1, 2, 3, 4, 5]);
  });

  test('out-of-order or malformed history repairs from a full snapshot',
      () async {
    var cursor = 1;
    List<GroupMemberRecord>? replaced;
    final service = GroupMemberIncrementalSyncService.forTesting(
      ownerUserId: 'owner',
      readCursor: (_, __) async => cursor,
      writeCursor: (seq, _, __) async => cursor = seq,
      clearCursor: (_, __) async => cursor = 0,
      fetchChanges: (_, __, ___) async => GroupMemberChangesPage(
        nextSeq: 4,
        hasMore: false,
        events: [_upsert(4)],
      ),
      fetchSnapshot: (_, limit, offset) async => GroupMembersPage(
        groupId: 'g',
        items: offset == 0 ? [_record('snapshot')] : const [],
        total: 1,
        limit: limit,
        offset: offset,
        hasMore: false,
      ),
      applyEvent: (_, __, ___) async => fail('gap must not be skipped'),
      replaceSnapshot: (_, __, records) async {
        replaced = List<GroupMemberRecord>.of(records);
      },
    );
    await service.noteRealtimeSeq(groupId: 'g', seq: 4);
    expect(replaced?.single.userId, 'snapshot');
    expect(cursor, 4);
  });
}
