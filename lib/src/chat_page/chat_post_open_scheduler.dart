import 'dart:async';

import '../services/chat_thermal_perf.dart';

typedef ChatPostOpenCanRun = bool Function();
typedef ChatPostOpenTask = FutureOr<void> Function();

enum ChatActivityState { active, interacting, covered, background, disposed }

enum ChatTaskPriority { essential, background }

class _ScheduledChatOpenTask {
  const _ScheduledChatOpenTask({
    required this.generation,
    required this.key,
    required this.canRun,
    required this.task,
    required this.timeout,
    required this.priority,
  });

  final int generation;
  final String key;
  final ChatPostOpenCanRun canRun;
  final ChatPostOpenTask task;
  final Duration timeout;
  final ChatTaskPriority priority;
}

/// Owns delayed post-open chat work so first-frame scheduling is visible in one
/// place instead of being scattered across `Future.delayed` calls.
class ChatPostOpenScheduler {
  static const Duration routeFallbackDelay = Duration(milliseconds: 1000);
  static const Duration p1Delay = Duration(milliseconds: 80);
  static const Duration p2Delay = Duration(milliseconds: 220);
  static const Duration idleDelay = Duration(milliseconds: 380);
  static const Duration muteNetworkDelay = Duration(milliseconds: 450);
  static const Duration defaultTaskTimeout = Duration(seconds: 8);

  ChatPostOpenScheduler({this.maxConcurrent = 2}) : assert(maxConcurrent > 0);

  final int maxConcurrent;

  final Set<Timer> _timers = <Timer>{};
  final List<_ScheduledChatOpenTask> _ready = <_ScheduledChatOpenTask>[];
  final Set<String> _taskKeys = <String>{};
  int _generation = 0;
  // A new route generation cannot cancel work already running in the SDK.
  int _running = 0;
  ChatActivityState _activity = ChatActivityState.active;

  ChatActivityState get activity => _activity;

  void setActivity(ChatActivityState state) {
    if (_activity == state || _activity == ChatActivityState.disposed) return;
    _activity = state;
    if (state == ChatActivityState.disposed) {
      ChatThermalPerf.increment('activity_disposed');
      cancelPending();
    } else {
      ChatThermalPerf.increment('activity_transition');
      _drain();
    }
  }

  int beginRun() {
    _cancelTimers();
    _generation++;
    return _generation;
  }

  void schedule({
    required int generation,
    required Duration delay,
    required ChatPostOpenCanRun canRun,
    required ChatPostOpenTask task,
    String key = '',
    Duration timeout = defaultTaskTimeout,
    ChatTaskPriority priority = ChatTaskPriority.essential,
  }) {
    if (_activity == ChatActivityState.disposed || generation != _generation) {
      return;
    }
    final normalizedKey = key.trim();
    final taskKey = normalizedKey.isEmpty ? '' : '$generation:$normalizedKey';
    if (taskKey.isNotEmpty && !_taskKeys.add(taskKey)) {
      ChatThermalPerf.increment('task_duplicate_suppressed');
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (generation != _generation || !canRun()) {
        ChatThermalPerf.increment('task_cancelled_before_ready');
        _taskKeys.remove(taskKey);
        return;
      }
      _ready.add(_ScheduledChatOpenTask(
        generation: generation,
        key: taskKey,
        canRun: canRun,
        task: task,
        timeout: timeout,
        priority: priority,
      ));
      _drain();
    });
    _timers.add(timer);
  }

  void cancelPending() {
    _cancelTimers();
    _generation++;
  }

  void dispose() {
    setActivity(ChatActivityState.disposed);
  }

  void _cancelTimers() {
    for (final timer in _timers.toList(growable: false)) {
      timer.cancel();
    }
    _timers.clear();
    _ready.clear();
    _taskKeys.clear();
  }

  void _drain() {
    while (_running < maxConcurrent && _ready.isNotEmpty) {
      final index = _ready.indexWhere((task) => _allows(task.priority));
      if (index < 0) {
        ChatThermalPerf.increment('task_held_by_activity');
        return;
      }
      final pending = _ready.removeAt(index);
      if (pending.generation != _generation || !pending.canRun()) {
        ChatThermalPerf.increment('task_dropped_before_start');
        _taskKeys.remove(pending.key);
        continue;
      }
      _running++;
      ChatThermalPerf.increment('task_started');
      // Timeout is diagnostic: Future.timeout does not cancel the actual task.
      final watchdog = Timer(pending.timeout, () {
        ChatThermalPerf.increment('task_timeout');
      });
      Future<void>.sync(pending.task)
          .catchError((Object _) {})
          .whenComplete(() {
        watchdog.cancel();
        _running--;
        _taskKeys.remove(pending.key);
        ChatThermalPerf.increment('task_completed');
        _drain();
      });
    }
  }

  bool _allows(ChatTaskPriority priority) {
    if (priority == ChatTaskPriority.essential) {
      return _activity != ChatActivityState.disposed;
    }
    return _activity == ChatActivityState.active ||
        _activity == ChatActivityState.interacting;
  }
}
