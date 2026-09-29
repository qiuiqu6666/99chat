import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/history_read_admission_gate.dart';

void main() {
  test('physical reads are bounded and a released permit wakes one waiter',
      () async {
    final gate = HistoryReadAdmissionGate(maxConcurrent: 2, maxQueued: 2);
    final first = await gate.acquire(timeout: const Duration(seconds: 1));
    final second = await gate.acquire(timeout: const Duration(seconds: 1));
    final thirdFuture = gate.acquire(timeout: const Duration(seconds: 1));

    expect(gate.activeCount, 2);
    expect(gate.queuedCount, 1);
    first.release();
    final third = await thirdFuture;
    expect(gate.activeCount, 2);
    expect(gate.queuedCount, 0);

    second.release();
    third.release();
    expect(gate.activeCount, 0);
  });

  test('timed out queued read is removed and cannot steal a later permit',
      () async {
    final gate = HistoryReadAdmissionGate(maxConcurrent: 1, maxQueued: 1);
    final active = await gate.acquire(timeout: const Duration(seconds: 1));
    await expectLater(
      gate.acquire(timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(gate.queuedCount, 0);

    active.release();
    expect(gate.activeCount, 0);
    final next = await gate.acquire(timeout: const Duration(seconds: 1));
    next.release();
    expect(gate.activeCount, 0);
  });

  test('queue saturation fails immediately instead of growing without bound',
      () async {
    final gate = HistoryReadAdmissionGate(maxConcurrent: 1, maxQueued: 1);
    final active = await gate.acquire(timeout: const Duration(seconds: 1));
    final queued = gate.acquire(timeout: const Duration(seconds: 1));
    await expectLater(
      gate.acquire(timeout: const Duration(seconds: 1)),
      throwsA(isA<HistoryReadCapacityException>()),
    );
    expect(gate.queuedCount, 1);
    active.release();
    final second = await queued;
    second.release();
    expect(gate.activeCount, 0);
  });

  test('release is idempotent', () async {
    final gate = HistoryReadAdmissionGate(maxConcurrent: 1, maxQueued: 0);
    final permit = await gate.acquire(timeout: const Duration(seconds: 1));
    permit
      ..release()
      ..release();
    expect(gate.activeCount, 0);
  });
}
