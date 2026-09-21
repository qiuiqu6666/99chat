import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_demo/src/services/history_empty_retry_backoff.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/message_core_owner_io.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

void main() {
  test('empty reads back off, changed messages and reconnect invalidate', () {
    var now = DateTime(2026);
    final backoff = HistoryEmptyRetryBackoff(now: () => now);
    for (final delay in [15, 60, 300, 300]) {
      backoff.recordEmpty('alice@1|c2c_bob', 'revision1');
      now = now.add(Duration(seconds: delay - 1));
      expect(backoff.isDeferred('alice@1|c2c_bob', 'revision1'), isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(backoff.isDeferred('alice@1|c2c_bob', 'revision1'), isFalse);
    }
    backoff.recordEmpty('alice@1|c2c_bob', 'revision1');
    expect(backoff.isDeferred('alice@2|c2c_bob', 'revision1'), isFalse);
    expect(backoff.isDeferred('alice@1|c2c_bob', 'revision2'), isFalse);
    backoff.recordEmpty('alice@1|c2c_bob', 'revision2');
    backoff.invalidate('alice@1|c2c_bob');
    expect(backoff.isDeferred('alice@1|c2c_bob', 'revision2'), isFalse);
    backoff.recordEmpty('alice@1|c2c_bob', 'revision2');
    backoff.clear();
    expect(backoff.isDeferred('alice@1|c2c_bob', 'revision2'), isFalse);
  });

  test('an alive owner cannot be stolen; proven exit advances fencing',
      () async {
    final store = InMemoryImIngressStore();
    var dead = false;
    final service = ImWriterLeaseService(
      store: store,
      isOwnerAbandoned: (owner) async => owner == 'old' && dead,
    );
    final old = (await service.acquire(
        ownerUserId: 'alice', leaseOwnerId: 'old', nowMs: 1000, ttlMs: 60000))!;
    expect(
        await service.acquire(
            ownerUserId: 'alice', leaseOwnerId: 'new', nowMs: 1001),
        isNull);
    dead = true;
    final next = (await service.acquire(
        ownerUserId: 'alice', leaseOwnerId: 'new', nowMs: 1002))!;
    expect(next.fencingToken, greaterThan(old.fencingToken));
    expect(await service.isCurrent(lease: old, nowMs: 1003), isFalse);
    expect(await service.renew(lease: old, nowMs: 1003), isNull);
    expect(await service.release(old), isFalse);
    expect(await service.isCurrent(lease: next, nowMs: 1003), isTrue);
  });

  test('without abandonment evidence the original lease TTL is respected',
      () async {
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    await service.acquire(
        ownerUserId: 'alice', leaseOwnerId: 'legacy', nowMs: 0, ttlMs: 60000);
    expect(
        await service.acquire(
            ownerUserId: 'alice', leaseOwnerId: 'next', nowMs: 59999),
        isNull);
    expect(
        await service.acquire(
            ownerUserId: 'alice', leaseOwnerId: 'next', nowMs: 60000),
        isNotNull);
  });

  test('same-process sibling with fresh heartbeat stays other_owner_active',
      () async {
    const holder =
        'flutter-message-core-v2:19269:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const requester =
        'flutter-message-core-v2:19269:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final reasons = <String>[];
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: holder,
      nowMs: 1000,
      ttlMs: 60000,
    );
    final stolen = await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: requester,
      nowMs: 6000,
      ttlMs: 60000,
      onBlocked: (_, reason) => reasons.add(reason),
    );
    expect(stolen, isNull);
    expect(reasons, <String>['other_owner_active']);
  });

  test('same-process stale heartbeat allows CAS takeover before TTL', () async {
    const holder =
        'flutter-message-core-v2:19269:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const requester =
        'flutter-message-core-v2:19269:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final reasons = <String>[];
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    final old = (await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: holder,
      nowMs: 1000,
      ttlMs: 60000,
    ))!;
    final takeover = await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: requester,
      nowMs: 17001,
      ttlMs: 60000,
      onBlocked: (_, reason) => reasons.add(reason),
    );
    expect(takeover, isNotNull);
    expect(takeover!.fencingToken, greaterThan(old.fencingToken));
    expect(reasons, <String>['abandoned_same_process_isolate']);
  });

  test('old owner cannot renew or reacquire after same-process takeover',
      () async {
    const holder =
        'flutter-message-core-v2:19269:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const requester =
        'flutter-message-core-v2:19269:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    final old = (await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: holder,
      nowMs: 1000,
      ttlMs: 60000,
    ))!;
    await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: requester,
      nowMs: 17001,
      ttlMs: 60000,
    );
    expect(await service.renew(lease: old, nowMs: 17001, ttlMs: 60000), isNull);
    expect(
      await service.acquire(
        ownerUserId: 'alice',
        leaseOwnerId: holder,
        nowMs: 17001,
        ttlMs: 60000,
      ),
      isNull,
    );
  });

  test('second same-process claimant loses after the first CAS takeover',
      () async {
    const holder =
        'flutter-message-core-v2:19269:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const first =
        'flutter-message-core-v2:19269:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    const second =
        'flutter-message-core-v2:19269:cccccccc-cccc-cccc-cccc-cccccccccccc';
    final reasons = <String>[];
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    await service.acquire(
      ownerUserId: 'alice',
      leaseOwnerId: holder,
      nowMs: 1000,
      ttlMs: 60000,
    );
    expect(
      await service.acquire(
        ownerUserId: 'alice',
        leaseOwnerId: first,
        nowMs: 17001,
        ttlMs: 60000,
      ),
      isNotNull,
    );
    expect(
      await service.acquire(
        ownerUserId: 'alice',
        leaseOwnerId: second,
        nowMs: 17001,
        ttlMs: 60000,
        onBlocked: (_, reason) => reasons.add(reason),
      ),
      isNull,
    );
    expect(reasons, <String>['other_owner_active']);
  });

  test(
      'OS lock detects process exit, while alive and unknown owners stay protected',
      () async {
    final dir = await Directory.systemTemp.createTemp('im-owner-test-');
    final owner = MessageCoreOwner(directory: dir.path);
    await owner.ensureReady();
    expect(await owner.isAbandoned(owner.id), isFalse);
    expect(await owner.isAbandoned('flutter-message-core:legacy'), isFalse);
    final script = File(p.join(dir.path, 'lock.dart'));
    await script.writeAsString(r'''
import 'dart:io';
Future<void> main(List<String> args) async {
  final id = 'flutter-message-core-v2:$pid:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final file = await File('${args[0]}/message_core_owner_${id.split(':').skip(1).join('_')}.lock').open(mode: FileMode.append);
  await file.lock(FileLock.exclusive, 0, 1);
  stdout.writeln(id);
  await stdin.first;
  await file.close();
}
''');
    var parent = File(Platform.resolvedExecutable).parent;
    File? dart;
    while (parent.parent.path != parent.path) {
      final candidate = File(p.join(parent.path, 'dart-sdk', 'bin',
          Platform.isWindows ? 'dart.exe' : 'dart'));
      if (candidate.existsSync()) {
        dart = candidate;
        break;
      }
      parent = parent.parent;
    }
    expect(dart, isNotNull,
        reason: 'Flutter cache must contain the Dart runtime');
    final child = await Process.start(dart!.path, [script.path, dir.path]);
    try {
      final id = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      expect(await owner.isAbandoned(id), isFalse);
      Process.killPid(int.parse(id.split(':')[1]));
      await child.exitCode;
      expect(await owner.isAbandoned(id), isTrue);
    } finally {
      child.kill();
      await child.exitCode;
      // The current owner's guard intentionally stays open for the process.
      await script.delete();
    }
  });
}
