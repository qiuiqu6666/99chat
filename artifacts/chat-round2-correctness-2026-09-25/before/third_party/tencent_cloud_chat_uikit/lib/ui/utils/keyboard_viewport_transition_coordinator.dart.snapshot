import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/background_media_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_main_thread_perf.dart';

enum KeyboardTransitionPhase { idle, occupied }

enum KeyboardInsetSource {
  none,
  flutterInset,
  nativeIme,
  viewportShrink,
  cached,
  estimated,
}

/// Occupancy lock for the system IME. Does not interpolate animation.
/// Layout spacer reads [effectiveInset]. [inset] remains the raw Flutter
/// view inset and is not used to pad the input bar.
class KeyboardViewportTransitionCoordinator {
  KeyboardViewportTransitionCoordinator({
    this.onBegin,
    this.onEnd,
    this.pauseMedia,
    this.resumeMedia,
    this.persistTrustedHeight,
  });

  static KeyboardViewportTransitionCoordinator? active;
  static const double keyboardThreshold = 40.0;

  final VoidCallback? onBegin;
  final VoidCallback? onEnd;
  final VoidCallback? pauseMedia;
  final VoidCallback? resumeMedia;
  final ValueChanged<double>? persistTrustedHeight;

  final ValueNotifier<double> inset = ValueNotifier<double>(0);
  final ValueNotifier<double> effectiveInset = ValueNotifier<double>(0);
  final ValueNotifier<KeyboardInsetSource> effectiveSource =
      ValueNotifier<KeyboardInsetSource>(KeyboardInsetSource.none);
  final ValueNotifier<KeyboardTransitionPhase> phase =
      ValueNotifier<KeyboardTransitionPhase>(KeyboardTransitionPhase.idle);

  int metricsCount = 0;
  int beginCount = 0;
  int settleCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int jumpCountDuringTransition = 0;
  int correctionCount = 0;
  int chatBuildCount = 0;
  int historyBuildCount = 0;
  double lastViewHeight = 0;
  double lastPaddingTop = 0;
  double lastPaddingBottom = 0;
  double lastDisplayHeight = 0;
  double nativeImeHeight = 0;
  bool nativeImeVisible = false;
  bool inputHasFocus = false;
  double cachedTrustedHeight = 0;
  String debugDevice = '';

  double _lastOccupied = 0;
  double _lastRawInset = 0;
  bool _pausedMedia = false;
  Timer? _heightSaveTimer;
  double? _pendingHeight;
  double? _lastSavedHeight;

  bool get isOccupied =>
      phase.value == KeyboardTransitionPhase.occupied;

  /// Occupied lock. Kept as [isAnimating] so existing scroll guards apply
  /// for the whole time the keyboard owns the window, not a transition tail.
  bool get isAnimating => isOccupied;

  double get _viewportShrink =>
      (lastDisplayHeight - lastViewHeight).clamp(0.0, double.infinity);

  bool get keyboardOccupiedForFallback =>
      nativeImeVisible ||
      nativeImeHeight > keyboardThreshold ||
      _lastRawInset > keyboardThreshold ||
      _viewportShrink > keyboardThreshold;

  void resetCounters() {
    metricsCount = 0;
    beginCount = 0;
    settleCount = 0;
    pauseCount = 0;
    resumeCount = 0;
    jumpCountDuringTransition = 0;
    correctionCount = 0;
    chatBuildCount = 0;
    historyBuildCount = 0;
  }

  void reset() {
    _cancelHeightSave();
    _lastOccupied = 0;
    _lastRawInset = 0;
    nativeImeHeight = 0;
    nativeImeVisible = false;
    if (inset.value != 0) {
      inset.value = 0;
    }
    _setEffective(0, KeyboardInsetSource.none);
    if (phase.value != KeyboardTransitionPhase.idle) {
      phase.value = KeyboardTransitionPhase.idle;
    }
    _resumeMediaOnce();
  }

  /// Keyboard occupancy as a boolean source. Some OEMs may report
  /// inset=0 while the Flutter view height is shrinking.
  static double occupiedInset({
    required double rawInset,
    required double viewHeight,
    required double displayHeight,
  }) {
    final resizedBy = (displayHeight - viewHeight).clamp(0.0, double.infinity);
    return rawInset > resizedBy ? rawInset : resizedBy;
  }

  static double _displayHeight(FlutterView view, double dpr) {
    try {
      final height = view.display.size.height / dpr;
      if (height > 0) {
        return height;
      }
    } catch (_) {}
    return view.physicalSize.height / dpr;
  }

  void seedCachedHeight(double height) {
    if (height > keyboardThreshold) {
      cachedTrustedHeight = height;
    }
  }

  void setInputHasFocus(bool hasFocus) {
    if (inputHasFocus == hasFocus) {
      return;
    }
    inputHasFocus = hasFocus;
    recomputeEffective();
  }

  void applyNativeIme({
    required bool visible,
    required double imeHeight,
    String? device,
  }) {
    if (device != null && device.isNotEmpty) {
      debugDevice = device;
    }
    nativeImeVisible = visible;
    nativeImeHeight = imeHeight;
    _refreshOccupied();
    recomputeEffective();
  }

  void applyFromView(FlutterView view) {
    final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final viewHeight = view.physicalSize.height / dpr;
    final displayHeight = _displayHeight(view, dpr);
    final rawInset = view.viewInsets.bottom / dpr;
    lastPaddingTop = view.padding.top / dpr;
    lastPaddingBottom = view.padding.bottom / dpr;
    applyLogicalInset(
      rawInset,
      viewHeight: viewHeight,
      displayHeight: displayHeight,
    );
  }

  void applyLogicalInset(
    double rawInset, {
    required double viewHeight,
    required double displayHeight,
  }) {
    lastViewHeight = viewHeight;
    lastDisplayHeight = displayHeight;
    _lastRawInset = rawInset;
    metricsCount++;
    ChatMainThreadPerf.increment('keyboard_metrics_count');
    if ((rawInset - inset.value).abs() > 0.5) {
      inset.value = rawInset;
    }
    _refreshOccupied();
    recomputeEffective();
  }

  void recomputeEffective() {
    final shrink = _viewportShrink;
    KeyboardInsetSource source;
    double height;
    if (_lastRawInset > keyboardThreshold) {
      height = _lastRawInset;
      source = KeyboardInsetSource.flutterInset;
    } else if (nativeImeHeight > keyboardThreshold) {
      height = nativeImeHeight;
      source = KeyboardInsetSource.nativeIme;
    } else if (shrink > keyboardThreshold) {
      height = shrink;
      source = KeyboardInsetSource.viewportShrink;
    } else if (keyboardOccupiedForFallback &&
        inputHasFocus &&
        cachedTrustedHeight > keyboardThreshold) {
      height = cachedTrustedHeight;
      source = KeyboardInsetSource.cached;
    } else if (keyboardOccupiedForFallback && inputHasFocus) {
      height = _estimatedHeight();
      source = KeyboardInsetSource.estimated;
    } else {
      height = 0;
      source = KeyboardInsetSource.none;
    }
    if (source == KeyboardInsetSource.flutterInset ||
        source == KeyboardInsetSource.nativeIme) {
      if (height > keyboardThreshold && cachedTrustedHeight != height) {
        cachedTrustedHeight = height;
      }
    }
    _scheduleHeightSave(height, source);
    _setEffective(height, source);
  }

  void _cancelHeightSave() {
    _heightSaveTimer?.cancel();
    _heightSaveTimer = null;
    _pendingHeight = null;
  }

  void _scheduleHeightSave(double height, KeyboardInsetSource source) {
    if (persistTrustedHeight == null || height <= keyboardThreshold ||
        (source != KeyboardInsetSource.flutterInset &&
            source != KeyboardInsetSource.nativeIme)) {
      _cancelHeightSave();
      return;
    }
    if (_pendingHeight == height) return;
    _cancelHeightSave();
    if (_lastSavedHeight == height) return;
    _pendingHeight = height;
    _heightSaveTimer = Timer(const Duration(milliseconds: 250), () {
      _heightSaveTimer = null;
      _pendingHeight = null;
      _lastSavedHeight = height;
      persistTrustedHeight?.call(height);
    });
  }

  void noteSuppressedJump() {
    if (isAnimating) {
      jumpCountDuringTransition++;
      ChatMainThreadPerf.increment('scroll_jump_count_during_keyboard');
    }
  }

  void noteChatBuild() {
    if (!isAnimating) {
      return;
    }
    chatBuildCount++;
    ChatMainThreadPerf.increment('chat_build_count_during_keyboard');
  }

  void noteHistoryBuild() {
    if (!isAnimating) {
      return;
    }
    historyBuildCount++;
    ChatMainThreadPerf.increment('history_list_build_count_during_keyboard');
  }

  void dispose() {
    _cancelHeightSave();
    inset.dispose();
    effectiveInset.dispose();
    effectiveSource.dispose();
    phase.dispose();
    if (identical(active, this)) {
      active = null;
    }
  }

  void _refreshOccupied() {
    final flutterOccupied = occupiedInset(
      rawInset: _lastRawInset,
      viewHeight: lastViewHeight,
      displayHeight: lastDisplayHeight,
    );
    final occupied = flutterOccupied > 0.5 ||
        nativeImeVisible ||
        nativeImeHeight > keyboardThreshold;
    final wasZero = _lastOccupied <= 0.5;
    final isZero = !occupied;
    _lastOccupied = occupied
        ? (flutterOccupied > 0.5 ? flutterOccupied : 1.0)
        : 0;
    if (wasZero && !isZero) {
      _setOccupied(true);
      return;
    }
    if (!wasZero && isZero) {
      _setOccupied(false);
    }
  }

  void _setEffective(double height, KeyboardInsetSource source) {
    final heightChanged = (height - effectiveInset.value).abs() > 0.5;
    final sourceChanged = source != effectiveSource.value;
    if (!heightChanged && !sourceChanged) {
      return;
    }
    if (heightChanged) {
      effectiveInset.value = height;
    }
    if (sourceChanged) {
      effectiveSource.value = source;
    }
    _logDiag();
  }

  double _estimatedHeight() {
    if (lastViewHeight == 0) {
      return 280.0;
    }
    final estimated = lastViewHeight * 0.36;
    if (estimated < 240.0) {
      return 240.0;
    }
    if (estimated > 360.0) {
      return 360.0;
    }
    return estimated;
  }

  void _logDiag() {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[KeyboardDiag] device=$debugDevice focus=$inputHasFocus '
      'flutterInset=$_lastRawInset nativeVisible=$nativeImeVisible '
      'nativeImeHeight=$nativeImeHeight viewportShrink=$_viewportShrink '
      'cachedHeight=$cachedTrustedHeight effectiveHeight=${effectiveInset.value} '
      'source=${effectiveSource.value.name}',
    );
  }

  void _setOccupied(bool occupied) {
    if (occupied) {
      resetCounters();
      metricsCount = 1;
      phase.value = KeyboardTransitionPhase.occupied;
      beginCount++;
      ChatMainThreadPerf.increment('keyboard_transition_begin_count');
      _pauseMediaOnce();
      onBegin?.call();
      return;
    }
    phase.value = KeyboardTransitionPhase.idle;
    settleCount++;
    ChatMainThreadPerf.increment('keyboard_settle_count');
    _resumeMediaOnce();
    onEnd?.call();
  }

  void _pauseMediaOnce() {
    if (_pausedMedia) return;
    _pausedMedia = true;
    pauseCount++;
    ChatMainThreadPerf.increment('background_media_defer_count');
    (pauseMedia ?? BackgroundMediaGate.instance.pauseKeyboard)();
  }

  void _resumeMediaOnce() {
    if (!_pausedMedia) return;
    _pausedMedia = false;
    resumeCount++;
    (resumeMedia ?? BackgroundMediaGate.instance.resumeKeyboard)();
  }
}

class KeyboardTransitionScope extends InheritedWidget {
  const KeyboardTransitionScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final KeyboardViewportTransitionCoordinator coordinator;

  static KeyboardViewportTransitionCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<KeyboardTransitionScope>()
        ?.coordinator;
  }

  @override
  bool updateShouldNotify(KeyboardTransitionScope oldWidget) {
    return oldWidget.coordinator != coordinator;
  }
}
