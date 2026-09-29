import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';

/// Coalesces optional work, including callbacks posted to Flutter's idle queue.
/// Running work checks ownership between steps with a cooperative checkpoint.
class InteractionIdleScheduler {
  InteractionIdleScheduler({
    bool Function()? canStart,
    void Function(void Function())? postIdle,
    this.spacing = const Duration(milliseconds: 32),
    this.retryDelay = const Duration(milliseconds: 100),
  })  : _canStart = canStart ?? _interactionIsIdle,
        _postIdle = postIdle ?? _scheduleFlutterIdle;

  static final instance = InteractionIdleScheduler();
  final bool Function() _canStart;
  final void Function(void Function()) _postIdle;
  final Duration spacing;
  final Duration retryDelay;
  final Map<String, _IdleJob> _jobs = {};
  Timer? _pumpTimer;
  bool _posted = false;
  bool _running = false;

  static bool _interactionIsIdle() {
    BackgroundMediaGate.instance.observeMetrics();
    return BackgroundMediaGate.instance.canStartOptionalWork;
  }

  static void _scheduleFlutterIdle(void Function() callback) {
    unawaited(SchedulerBinding.instance.scheduleTask<void>(
      callback,
      Priority.idle,
      debugLabel: 'interaction_idle',
    ));
  }

  void schedule(
    String key, {
    required Duration delay,
    required FutureOr<void> Function() task,
    bool Function()? isCurrent,
  }) =>
      scheduleCooperative(key,
          delay: delay, isCurrent: isCurrent, task: (_) => task());

  void scheduleCooperative(
    String key, {
    required Duration delay,
    required FutureOr<void> Function(InteractionIdleTask) task,
    bool Function()? isCurrent,
  }) {
    cancel(key);
    final job = _IdleJob(task);
    job.context = InteractionIdleTask(
      () => identical(_jobs[key], job) && (isCurrent?.call() ?? true),
      _canStart,
      retryDelay,
      spacing,
    );
    _jobs[key] = job;
    job.timer = Timer(delay, () {
      job.ready = true;
      _pump();
    });
  }

  void cancel(String key) {
    _jobs.remove(key)?.timer?.cancel();
  }

  void cancelAll() {
    for (final job in _jobs.values) {
      job.timer?.cancel();
    }
    _jobs.clear();
    _pumpTimer?.cancel();
    _pumpTimer = null;
  }

  void _pump() {
    if (_running || _posted || _pumpTimer != null) return;
    _jobs.removeWhere((_, job) => !job.context.isCurrent);
    if (!_jobs.values.any((job) => job.ready)) return;
    if (!_canStart()) {
      _resumeAfter(retryDelay);
      return;
    }
    _posted = true;
    _postIdle(() {
      _posted = false;
      // Interaction/account/cancellation may change while Flutter holds us.
      if (!_canStart()) {
        _resumeAfter(retryDelay);
        return;
      }
      for (final entry in _jobs.entries) {
        if (entry.value.ready && entry.value.context.isCurrent) {
          unawaited(_run(entry.key, entry.value));
          return;
        }
      }
      _pump();
    });
  }

  Future<void> _run(String key, _IdleJob job) async {
    _running = true;
    try {
      await job.task(job.context);
    } finally {
      if (identical(_jobs[key], job)) _jobs.remove(key);
      _running = false;
      _resumeAfter(spacing);
    }
  }

  void _resumeAfter(Duration delay) {
    _pumpTimer ??= Timer(delay, () {
      _pumpTimer = null;
      _pump();
    });
  }
}

class InteractionIdleTask {
  InteractionIdleTask(
      this._isCurrent, this._canStart, this._retry, this._spacing);
  final bool Function() _isCurrent;
  final bool Function() _canStart;
  final Duration _retry;
  final Duration _spacing;
  bool get isCurrent => _isCurrent();

  /// Call outside transactions, before the next network/page/decode operation.
  Future<bool> checkpoint() async {
    if (!isCurrent) return false;
    await Future<void>.delayed(_spacing);
    while (isCurrent) {
      if (_canStart()) return true;
      await Future<void>.delayed(_retry);
    }
    return false;
  }
}

class _IdleJob {
  _IdleJob(this.task);
  final FutureOr<void> Function(InteractionIdleTask) task;
  late final InteractionIdleTask context;
  Timer? timer;
  bool ready = false;
}
