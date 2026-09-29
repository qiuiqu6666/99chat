// P1-1: cloud verify 软 TTL 测试。
//
// 验证 20 秒软 TTL 的状态机：同会话 N 秒内已 verify → 直接 skip。
import 'package:flutter_test/flutter_test.dart';

class _VerifySoftTtl {
  static const int ttlMs = 20000;
  final Map<String, int> lastAt = <String, int>{};

  bool shouldRun(String key, int nowMs) {
    final last = lastAt[key];
    if (last == null) return true;
    // TTL 是开区间：lastAt 时刻起 ttlMs 之内的所有时刻都要 skip。
    return nowMs - last > ttlMs;
  }

  void record(String key, int nowMs) {
    lastAt[key] = nowMs;
  }

  void reset() => lastAt.clear();
}

void main() {
  group('P1-1 cloud verify soft TTL', () {
    test('first call within window runs', () {
      final t = _VerifySoftTtl();
      expect(t.shouldRun('g1', 1000), isTrue);
    });

    test('second call within 20s is skipped', () {
      final t = _VerifySoftTtl();
      t.record('g1', 1000);
      // 20s open interval: shouldRun returns true only when (nowMs - lastAt) > 20000.
      // Diff = 1ms..20000ms → still skipped.
      expect(t.shouldRun('g1', 1001), isFalse);
      expect(t.shouldRun('g1', 21000), isFalse,
          reason: '10s after record is well within 20s TTL');
    });

    test('call exactly at 20s boundary is still within TTL — skipped', () {
      final t = _VerifySoftTtl();
      t.record('g1', 0);
      // TTL is an open interval (nowMs - lastAt > ttlMs means re-run);
      // boundary 20000ms - 0ms = 20000 is NOT greater than 20000 → skip.
      expect(t.shouldRun('g1', 20000), isFalse,
          reason: 'TTL is open interval — at boundary still skip');
    });

    test('call after 20s runs again', () {
      final t = _VerifySoftTtl();
      t.record('g1', 0);
      expect(t.shouldRun('g1', 20001), isTrue);
    });

    test('different keys are tracked independently', () {
      final t = _VerifySoftTtl();
      t.record('g1', 1000);
      expect(t.shouldRun('g2', 1001), isTrue,
          reason: 'g2 has no prior record → run');
      expect(t.shouldRun('g1', 1001), isFalse);
    });

    test('reset clears state — useful on dispose / clearSession', () {
      final t = _VerifySoftTtl();
      t.record('g1', 1000);
      t.reset();
      expect(t.shouldRun('g1', 1001), isTrue);
    });
  });
}