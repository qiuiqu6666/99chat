import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/im/heartbeat_tick.dart';

void main() {
  setUp(HeartbeatTickRecorder.instance.resetForTest);

  test('idle tick skips lease write when expiry is far away', () {
    expect(
      HeartbeatTickPolicy.shouldRenewLease(
        expiresAtMs: 60000,
        nowMs: 5000,
      ),
      isFalse,
    );
  });

  test('tick writes only when remaining ttl is inside the lead window', () {
    expect(
      HeartbeatTickPolicy.shouldRenewLease(
        expiresAtMs: 25000,
        nowMs: 10000,
      ),
      isTrue,
    );
  });

  test('idle recorder stays at db 0 ui 0 tasks 0', () {
    HeartbeatTickRecorder.instance.record(
      cpuUs: 12,
      dbQueryCount: 0,
      uiNotifyCount: 0,
      triggeredTaskCount: 0,
    );
    final last = HeartbeatTickRecorder.instance.last!;
    expect(last.tickCount, 1);
    expect(last.dbQueryCount, 0);
    expect(last.uiNotifyCount, 0);
    expect(last.triggeredTaskCount, 0);
  });
}
