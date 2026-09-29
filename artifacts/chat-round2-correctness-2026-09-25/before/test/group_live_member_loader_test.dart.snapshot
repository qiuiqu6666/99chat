import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/pages/group_live/group_live_member_loader.dart';
import 'package:tencent_cloud_chat_demo/src/pages/wallet/red_packet/red_packet_member.dart';

RedPacketMember member(String id) => RedPacketMember(userId: id, name: id);

void main() {
  test('loads beyond 100 and publishes each page, deduplicating IDs', () async {
    final cursors = <String>[];
    final sizes = <int>[];
    final loader = GroupLiveMemberLoader((cursor) async {
      cursors.add(cursor);
      if (cursor == '0') {
        return GroupLiveMemberPage(
            List.generate(100, (i) => member('$i')), '100');
      }
      return GroupLiveMemberPage(
          [member('99'), member('100'), member('')], '0');
    });
    loader.addListener(() => sizes.add(loader.members.length));
    await loader.load();
    expect(cursors, ['0', '100']);
    expect(sizes, contains(100));
    expect(loader.members.length, 101);
    expect(loader.complete, isTrue);
    expect(loader.failed, isFalse);
    loader.dispose();
  });

  test('a one-member first page is not mistaken for a complete group',
      () async {
    final loader = GroupLiveMemberLoader((cursor) async => cursor == '0'
        ? GroupLiveMemberPage([member('owner')], 'next')
        : GroupLiveMemberPage([member('anchor')], '0'));
    await loader.load();
    expect(loader.members.map((m) => m.userId), ['owner', 'anchor']);
    expect(loader.complete, isTrue);
    loader.dispose();
  });

  test('failed later page retains members and retries the same cursor',
      () async {
    var fail = true;
    final cursors = <String>[];
    final loader = GroupLiveMemberLoader((cursor) async {
      cursors.add(cursor);
      if (cursor == '0') return GroupLiveMemberPage([member('a')], 'next');
      if (fail) throw TimeoutException('offline');
      return GroupLiveMemberPage([member('b')], '0');
    });
    await loader.load();
    expect(loader.failed, isTrue);
    expect(loader.complete, isFalse);
    expect(loader.members.single.userId, 'a');
    fail = false;
    await loader.load();
    expect(cursors, ['0', 'next', 'next']);
    expect(loader.members.length, 2);
    expect(loader.failed, isFalse);
    expect(loader.complete, isTrue);
    loader.dispose();
  });

  test('repeating cursor stops with an error instead of looping', () async {
    var calls = 0;
    final loader = GroupLiveMemberLoader((cursor) async {
      calls++;
      return GroupLiveMemberPage([member('a')], 'next');
    });
    await loader.load();
    expect(calls, 2);
    expect(loader.failed, isTrue);
    expect(loader.complete, isFalse);
    loader.dispose();
  });

  test('concurrent loads do not duplicate requests; dispose stops pagination',
      () async {
    final pending = Completer<GroupLiveMemberPage>();
    var calls = 0;
    final loader = GroupLiveMemberLoader((_) {
      calls++;
      return pending.future;
    });
    final active = loader.load();
    await loader.load();
    expect(calls, 1);
    loader.dispose();
    pending.complete(GroupLiveMemberPage([member('a')], 'next'));
    await active;
    expect(calls, 1);
  });

  test('new picker visit fetches fresh membership', () async {
    var calls = 0;
    Future<GroupLiveMemberPage> fetch(String _) async =>
        GroupLiveMemberPage([member('${++calls}')], '0');
    final first = GroupLiveMemberLoader(fetch);
    await first.load();
    first.dispose();
    final second = GroupLiveMemberLoader(fetch);
    await second.load();
    expect(second.members.single.userId, '2');
    second.dispose();
  });
}
