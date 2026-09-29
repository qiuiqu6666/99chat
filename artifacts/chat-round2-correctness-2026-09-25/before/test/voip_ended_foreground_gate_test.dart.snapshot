import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_session.dart';
import 'package:tencent_cloud_chat_demo/src/services/livekit_call_types.dart';

void main() {
  test('shouldReconcileStaleRinging only after ringing deadline', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1786752000000);
    final deadline = now.subtract(const Duration(seconds: 1));
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.ringingIn,
        ringDeadline: deadline,
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.ringingOut,
        ringDeadline: deadline,
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.ringingIn,
        ringDeadline: now.add(const Duration(seconds: 30)),
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.ringingIn,
        ringDeadline: null,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.connected,
        ringDeadline: deadline,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldReconcileStaleRinging(
        phase: LiveKitCallPhase.idle,
        ringDeadline: deadline,
        now: now,
      ),
      isFalse,
    );
  });
}
