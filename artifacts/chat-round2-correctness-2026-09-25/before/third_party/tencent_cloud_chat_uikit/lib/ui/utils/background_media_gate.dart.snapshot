import 'package:flutter/widgets.dart';

/// Shared admission for speculative media, restoration and optional idle work.
/// Visible loading, user pagination and accepted sends remain independent.
class BackgroundMediaGate with WidgetsBindingObserver {
  BackgroundMediaGate({
    bool Function()? platformBusy,
    bool Function()? isForeground,
    DateTime Function()? now,
    this.quietPeriod = const Duration(milliseconds: 200),
  })  : _platformBusy = platformBusy ?? _defaultPlatformBusy,
        _isForeground = isForeground ?? _appIsForeground,
        _now = now ?? DateTime.now;

  static final instance = BackgroundMediaGate();
  final bool Function() _platformBusy;
  final bool Function() _isForeground;
  final DateTime Function() _now;
  final Duration quietPeriod;
  final Set<Object> _busyOwners = {};
  static final Object _keyboardPauseOwner = Object();
  DateTime? _quietUntil;
  DateTime? _animationQuietUntil;
  bool _observing = false;

  static bool _appIsForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  static bool _defaultPlatformBusy() {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    return (state != null && state != AppLifecycleState.resumed) ||
        binding.transientCallbackCount > 0;
  }

  void observeMetrics() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void setBusy(Object owner, bool busy) {
    if (busy) {
      _busyOwners.add(owner);
    } else if (_busyOwners.remove(owner)) {
      defer();
    }
  }

  void defer() => _quietUntil = _now().add(quietPeriod);

  void pauseKeyboard() => setBusy(_keyboardPauseOwner, true);

  void resumeKeyboard() => setBusy(_keyboardPauseOwner, false);

  @override
  void didChangeMetrics() {}

  /// Restoration must not wait for an indeterminate loading spinner to stop.
  /// Explicit scroll/route/search owners and keyboard metrics still pause it.
  bool get canStartOptionalWork {
    if (_busyOwners.isNotEmpty || !_isForeground()) {
      defer();
      return false;
    }
    final until = _quietUntil;
    return until == null || !_now().isBefore(until);
  }

  bool get canStart {
    if (!canStartOptionalWork) return false;
    if (_platformBusy()) {
      // Keep animation quiet time separate: speculative media polling must
      // not prolong restoration's pause while its own spinner is running.
      _animationQuietUntil = _now().add(quietPeriod);
      return false;
    }
    final until = _animationQuietUntil;
    return until == null || !_now().isBefore(until);
  }
}
