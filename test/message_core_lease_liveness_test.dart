import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/im_ingress_store.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/writer_lease.dart';

void main() {
  test('healthy heartbeat during validation does not discard a realtime turn',
      () async {
    final service = ImWriterLeaseService(store: InMemoryImIngressStore());
    var now = 1000;
    ImWriterLease? current = await service.acquire(
        ownerUserId: 'alice', leaseOwnerId: 'core', nowMs: now, ttlMs: 60000);
    final validated = Completer<void>();
    final resume = Completer<void>();
    final check = isWriterLeaseCurrentAcrossAwait(
      currentLease: () => current,
      isOwnerCurrent: () => true,
      nowMs: () => now,
      validate: (lease) async {
        final result = await service.isCurrent(lease: lease, nowMs: now);
        validated.complete();
        await resume.future;
        return result;
      },
    );
    await validated.future;
    now = 45000;
    final previous = current!;
    current = await service.renew(lease: previous, nowMs: now, ttlMs: 60000);
    expect(identical(previous, current), isFalse);
    expect(current!.fencingToken, previous.fencingToken);
    resume.complete();
    expect(await check, isTrue);
  });

  for (final change in [
    'account',
    'owner',
    'token',
    'expired',
    'detached',
    'rejected'
  ]) {
    test('validation rejects $change after awaiting the store', () async {
      const original = ImWriterLease(
          ownerUserId: 'alice',
          leaseOwnerId: 'core',
          fencingToken: 1,
          acquiredAtMs: 0,
          expiresAtMs: 60000,
          heartbeatAtMs: 0);
      ImWriterLease? current = original;
      var ownerCurrent = true;
      var now = 1000;
      final result = Completer<bool>();
      final check = isWriterLeaseCurrentAcrossAwait(
        currentLease: () => current,
        isOwnerCurrent: () => ownerCurrent,
        nowMs: () => now,
        validate: (_) => result.future,
      );
      switch (change) {
        case 'account':
          ownerCurrent = false;
        case 'owner':
          current = const ImWriterLease(
              ownerUserId: 'bob',
              leaseOwnerId: 'other',
              fencingToken: 1,
              acquiredAtMs: 0,
              expiresAtMs: 60000,
              heartbeatAtMs: 0);
        case 'token':
          current = const ImWriterLease(
              ownerUserId: 'alice',
              leaseOwnerId: 'core',
              fencingToken: 2,
              acquiredAtMs: 0,
              expiresAtMs: 60000,
              heartbeatAtMs: 0);
        case 'expired':
          now = 60000;
        case 'detached':
          current = null;
      }
      result.complete(change != 'rejected');
      expect(await check, isFalse);
    });
  }
}
