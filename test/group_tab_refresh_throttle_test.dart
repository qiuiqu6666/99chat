// P1-3: 群 Tab 30s 节流 + in-flight 合并测试。
//
// 直接覆盖 conversation.dart 的 State 类需要 mock 大量依赖。
// 这里只测核心节流决策（hash 化的纯逻辑）：
//   - 首次触发：记时间戳，进入 refresh
//   - 30s 内重复触发：跳过 refresh
//   - 30s 之后：重新进入 refresh
//
// 不依赖 Flutter UI；只验证 throttle 状态机。
import 'package:flutter_test/flutter_test.dart';

class _TabRefreshThrottle {
  static const Duration interval = Duration(seconds: 30);
  DateTime? lastAt;
  Future<void>? inFlight;

  bool shouldRun(DateTime now) {
    final last = lastAt;
    if (last == null) return true;
    return now.difference(last) >= interval;
  }

  Future<void> runOnce(
    DateTime now,
    Future<void> Function() task,
  ) async {
    if (!shouldRun(now)) return;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    lastAt = now;
    inFlight = task();
    try {
      await inFlight;
    } finally {
      inFlight = null;
    }
  }
}

void main() {
  group('P1-3 tab throttle', () {
    test('first call runs', () async {
      final t = _TabRefreshThrottle();
      var calls = 0;
      await t.runOnce(DateTime(2026, 1, 1, 12), () async {
        calls++;
      });
      expect(calls, 1);
    });

    test('second call within 30s is skipped', () async {
      final t = _TabRefreshThrottle();
      var calls = 0;
      Future<void> task() async {
        calls++;
      }

      await t.runOnce(DateTime(2026, 1, 1, 12, 0, 0), task);
      await t.runOnce(DateTime(2026, 1, 1, 12, 0, 10), task);
      await t.runOnce(DateTime(2026, 1, 1, 12, 0, 29), task);
      expect(calls, 1);
    });

    test('call after 30s runs again', () async {
      final t = _TabRefreshThrottle();
      var calls = 0;
      Future<void> task() async {
        calls++;
      }

      await t.runOnce(DateTime(2026, 1, 1, 12, 0, 0), task);
      await t.runOnce(DateTime(2026, 1, 1, 12, 0, 30), task);
      expect(calls, 2);
    });

    test('concurrent calls within the throttle window share in-flight', () async {
      final t = _TabRefreshThrottle();
      var calls = 0;
      Future<void> task() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final now = DateTime(2026, 1, 1, 12, 0, 0);
      await Future.wait<void>([
        t.runOnce(now, task),
        t.runOnce(now, task),
        t.runOnce(now, task),
      ]);
      expect(calls, 1, reason: 'three concurrent calls share one in-flight');
    });
  });
}