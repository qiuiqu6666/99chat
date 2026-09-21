/// Heartbeat is connection liveness only. The 5s period is unchanged.
///
/// A tick may inspect in-memory lease times. It may write the lease only when
/// expiry is close. It must not scan Inbox, conversations, or start repair.
class HeartbeatTickPolicy {
  static const int renewLeadMs = 20000;

  static bool shouldRenewLease({
    required int expiresAtMs,
    required int nowMs,
    int leadMs = renewLeadMs,
  }) {
    return expiresAtMs - nowMs <= leadMs;
  }
}

class HeartbeatTickMetrics {
  const HeartbeatTickMetrics({
    required this.tickCount,
    required this.cpuUs,
    required this.dbQueryCount,
    required this.uiNotifyCount,
    required this.triggeredTaskCount,
  });

  final int tickCount;
  final int cpuUs;
  final int dbQueryCount;
  final int uiNotifyCount;
  final int triggeredTaskCount;
}

/// Process-local heartbeat counters. Empty idle ticks should stay at
/// DB ≈ 0, UI notify = 0, business tasks = 0.
class HeartbeatTickRecorder {
  HeartbeatTickRecorder._();

  static final HeartbeatTickRecorder instance = HeartbeatTickRecorder._();

  int _tickCount = 0;
  int _cpuUs = 0;
  int _dbQueryCount = 0;
  int _uiNotifyCount = 0;
  int _triggeredTaskCount = 0;
  HeartbeatTickMetrics? _last;

  HeartbeatTickMetrics? get last => _last;
  int get tickCount => _tickCount;
  int get cpuUs => _cpuUs;
  int get dbQueryCount => _dbQueryCount;
  int get uiNotifyCount => _uiNotifyCount;
  int get triggeredTaskCount => _triggeredTaskCount;

  void record({
    required int cpuUs,
    required int dbQueryCount,
    required int uiNotifyCount,
    required int triggeredTaskCount,
  }) {
    _tickCount += 1;
    _cpuUs += cpuUs;
    _dbQueryCount += dbQueryCount;
    _uiNotifyCount += uiNotifyCount;
    _triggeredTaskCount += triggeredTaskCount;
    _last = HeartbeatTickMetrics(
      tickCount: _tickCount,
      cpuUs: cpuUs,
      dbQueryCount: dbQueryCount,
      uiNotifyCount: uiNotifyCount,
      triggeredTaskCount: triggeredTaskCount,
    );
  }

  void resetForTest() {
    _tickCount = 0;
    _cpuUs = 0;
    _dbQueryCount = 0;
    _uiNotifyCount = 0;
    _triggeredTaskCount = 0;
    _last = null;
  }
}
