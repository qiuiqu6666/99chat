import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 冷启动阶段性能日志。Profile 构建可在 Instruments/Dart Timeline 中对齐。
class StartupPerfLog {
  StartupPerfLog._();

  static final Stopwatch _watch = Stopwatch()..start();
  static int _lastMicros = 0;
  static String _lastEvent = 'process_start';
  static bool _homeFrameReady = false;
  static Timer? _idleSummaryTimer;

  static int homeBootstrapStartCount = 0;
  static int homeBootstrapJoinCount = 0;
  static int restoreProjectionEnterCount = 0;
  static int ensurePrimedJoinCount = 0;
  static int ensurePrimedRealCount = 0;
  static int ensurePrimedSkipCount = 0;
  static int tabConstructedBeforeFirstFrame = 0;
  static int tabConstructedAfterFirstFrame = 0;
  static int conversationInitCount = 0;
  static int contactInitCount = 0;

  static bool get homeFrameReady => _homeFrameReady;

  /// Profile builds are used for real-device performance diagnosis. Keep the
  /// same compact console line as Debug so Xcode/`flutter logs` can show the
  /// phase boundaries without enabling verbose business logging. Release
  /// builds remain silent and retain only their normal production telemetry.
  static bool get consoleLoggingEnabled => kDebugMode;

  static String get buildMode {
    if (kProfileMode) return 'profile';
    if (kDebugMode) return 'debug';
    return 'release';
  }

  static void mark(String event,
      [Map<String, Object> details = const <String, Object>{}]) {
    _markImpl(event, category: 'app', details: details);
  }

  static void markTagged(
    String event, {
    String category = 'app',
    Map<String, Object> details = const <String, Object>{},
  }) {
    _markImpl(event, category: category, details: details);
  }

  static void emitColdStartTraceSummary({required String phase}) {
    if (!consoleLoggingEnabled) return;
    markTagged(
      'cold_start_trace_summary',
      category: 'cold_start',
      details: <String, Object>{
        'phase': phase,
        'homeBootstrapStartCount': homeBootstrapStartCount,
        'homeBootstrapJoinCount': homeBootstrapJoinCount,
        'restoreProjectionEnterCount': restoreProjectionEnterCount,
        'ensurePrimedJoinCount': ensurePrimedJoinCount,
        'ensurePrimedRealCount': ensurePrimedRealCount,
        'ensurePrimedSkipCount': ensurePrimedSkipCount,
        'tabConstructedBeforeFirstFrame': tabConstructedBeforeFirstFrame,
        'tabConstructedAfterFirstFrame': tabConstructedAfterFirstFrame,
        'conversationInitCount': conversationInitCount,
        'contactInitCount': contactInitCount,
        'note': phase == 'idle12s' ? '12s 观察窗，不是冷启动完成态' : '冷启动计数快照',
      },
    );
  }

  static void _resetColdStartCounters() {
    homeBootstrapStartCount = 0;
    homeBootstrapJoinCount = 0;
    restoreProjectionEnterCount = 0;
    ensurePrimedJoinCount = 0;
    ensurePrimedRealCount = 0;
    ensurePrimedSkipCount = 0;
    tabConstructedBeforeFirstFrame = 0;
    tabConstructedAfterFirstFrame = 0;
    conversationInitCount = 0;
    contactInitCount = 0;
    _homeFrameReady = false;
    _idleSummaryTimer?.cancel();
    _idleSummaryTimer = null;
  }

  static void _tally(String event, Map<String, Object> details) {
    switch (event) {
      case 'home_bootstrap_start':
        _resetColdStartCounters();
        homeBootstrapStartCount = 1;
        break;
      case 'home_bootstrap_join':
        homeBootstrapJoinCount += 1;
        break;
      case 'restoreProjection_enter':
        restoreProjectionEnterCount += 1;
        break;
      case 'ensurePrimed_already':
        ensurePrimedSkipCount += 1;
        break;
      case 'ensurePrimed_join':
        ensurePrimedJoinCount += 1;
        break;
      case 'ensurePrimed_real_start':
        ensurePrimedRealCount += 1;
        break;
      case 'home_tab_constructed':
        final before = details['beforeFirstFrame'] == true;
        if (before) {
          tabConstructedBeforeFirstFrame += 1;
        } else {
          tabConstructedAfterFirstFrame += 1;
        }
        break;
      case 'conversation_init_start':
        conversationInitCount += 1;
        break;
      case 'contact_init_start':
        contactInitCount += 1;
        break;
      case 'home_first_frame_ready':
        _homeFrameReady = true;
        _idleSummaryTimer?.cancel();
        _idleSummaryTimer = Timer(const Duration(seconds: 12), () {
          _idleSummaryTimer = null;
          emitColdStartTraceSummary(phase: 'idle12s');
        });
        break;
    }
  }

  static void _markImpl(
    String event, {
    required String category,
    required Map<String, Object> details,
  }) {
    // Profile may share product-like compiler optimizations, but it must keep
    // diagnostics. Only a real Release build is silent.
    if (kReleaseMode && !kProfileMode) return;
    _tally(event, details);
    final elapsedMicros = _watch.elapsedMicroseconds;
    final deltaMicros = elapsedMicros - _lastMicros;
    _lastMicros = elapsedMicros;
    final buffer = StringBuffer('[StartupPerf] event=$event')
      ..write(' category=$category')
      ..write(' elapsedMs=${(elapsedMicros / 1000).toStringAsFixed(1)}')
      ..write(' deltaMs=${(deltaMicros / 1000).toStringAsFixed(1)}')
      ..write(' prev=$_lastEvent');
    for (final entry in details.entries) {
      buffer.write(' ${entry.key}=${entry.value}');
    }
    final message = buffer.toString();
    if (consoleLoggingEnabled) {
      // Use print directly so Profile output is visible in Xcode and
      // `flutter logs`, independent of debugPrint throttling configuration.
      // ignore: avoid_print
      print(message);
      developer.log(message, name: 'StartupPerf');
      developer.Timeline.instantSync(
        'StartupPerf:$category:$event',
        arguments: <String, Object>{
          'elapsedMs': elapsedMicros / 1000,
          'deltaMs': deltaMicros / 1000,
          'prev': _lastEvent,
          'category': category,
          ...details,
        },
      );
    }
    _lastEvent = event;
  }
}
