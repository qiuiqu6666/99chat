import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/group_local/muted_member_profile_resolver.dart';
import 'package:tencent_cloud_chat_demo/src/services/session_identity.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';

void main() {
  const identity = SessionIdentity(ownerUserId: 'owner', generation: 1);
  Future<Map<String, MutedProfileResult>> run(
          MutedMemberProfileResolver resolver,
          {List<String> ids = const ['alice'],
          bool force = false,
          bool Function()? current}) =>
      resolver.resolve(
          groupId: '@TGS#test',
          userIds: ids,
          identity: identity,
          isCurrent: current ?? () => true,
          force: force);
  V2TimValueCallback<List<V2TimGroupMemberFullInfo>> ok(List<String> ids) =>
      V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: ids
              .map((id) => V2TimGroupMemberFullInfo(
                  userID: id, nickName: '最新昵称', faceUrl: 'avatar'))
              .toList());

  test('resolves display fields, caches and allows explicit refresh', () async {
    var calls = 0;
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      calls++;
      return ok(ids);
    });
    expect((await run(r))['alice']!.nickname, '最新昵称');
    expect((await run(r))['alice']!.avatarUrl, 'avatar');
    expect(calls, 1);
    await run(r, force: true);
    expect(calls, 2);
  });
  test('normalizes IDs and batches 51 targets without a member-list scan',
      () async {
    final batches = <List<String>>[];
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      batches.add(ids);
      return ok(ids);
    });
    final result = await run(r,
        ids: [...List.generate(51, (i) => 'u$i'), '@u0', 'c2c_u1']);
    expect(result.length, 51);
    expect(batches.map((b) => b.length), [50, 1]);
  });
  test('coalesces identical in-flight requests', () async {
    final gate = Completer<void>();
    var calls = 0;
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      calls++;
      await gate.future;
      return ok(ids);
    });
    final a = run(r);
    final b = run(r);
    gate.complete();
    await a;
    await b;
    expect(calls, 1);
  });
  test('partial/empty/mismatched returns are not all reported resolved',
      () async {
    final r = MutedMemberProfileResolver(
        loader: (_, ids) async =>
            V2TimValueCallback(code: 0, desc: 'ok', data: [
              V2TimGroupMemberFullInfo(userID: 'alice', nickName: 'Alice'),
              V2TimGroupMemberFullInfo(
                  userID: 'bob', nickName: '', faceUrl: ''),
              V2TimGroupMemberFullInfo(userID: 'wrong', nickName: 'Wrong'),
            ]));
    final result = await run(r, ids: ['alice', 'bob', 'carol']);
    expect(result['alice']!.status, MutedProfileStatus.partial);
    expect(result['bob']!.status, MutedProfileStatus.resolvedEmpty);
    expect(result['carol']!.status, MutedProfileStatus.notFound);
    expect(result.containsKey('wrong'), isFalse);
  });
  test('permission denial stops remaining batches and is not retried',
      () async {
    var calls = 0;
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      calls++;
      return V2TimValueCallback(code: 10007, desc: 'denied');
    });
    final result = await run(r, ids: List.generate(51, (i) => 'u$i'));
    expect(calls, 1);
    expect(result.values.every((r) => r.status == MutedProfileStatus.forbidden),
        isTrue);
  });
  test('late result after account switch is discarded and not cached',
      () async {
    var current = true;
    var calls = 0;
    final gate = Completer<void>();
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      calls++;
      await gate.future;
      return ok(ids);
    });
    final result = run(r, current: () => current);
    current = false;
    gate.complete();
    expect(await result, isEmpty);
    current = true;
    await run(r);
    expect(calls, 2);
  });
  test('invalidation discards late permission or route results', () async {
    final gate = Completer<void>();
    final r = MutedMemberProfileResolver(loader: (_, ids) async {
      await gate.future;
      return ok(ids);
    });
    final result = run(r);
    r.invalidate();
    gate.complete();
    expect(await result, isEmpty);
  });
  test('timeout has one retry and cannot poison later successful cache',
      () async {
    var calls = 0;
    final late =
        Completer<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>();
    final r = MutedMemberProfileResolver(
        timeout: const Duration(milliseconds: 2),
        retryDelay: Duration.zero,
        loader: (_, ids) {
          calls++;
          return late.future;
        });
    final result = await run(r);
    expect(calls, 2);
    expect(result['alice']!.status, MutedProfileStatus.failed);
    late.complete(ok(['alice']));
    expect((await run(r))['alice']!.status, MutedProfileStatus.resolved);
    expect(calls, 3);
  });
  test('TTL expires even for nonempty stale names', () async {
    var now = DateTime(2026);
    var calls = 0;
    final r = MutedMemberProfileResolver(
        now: () => now,
        loader: (_, ids) async {
          calls++;
          return ok(ids);
        });
    await run(r);
    now = now.add(const Duration(seconds: 61));
    await run(r);
    expect(calls, 2);
  });
}
