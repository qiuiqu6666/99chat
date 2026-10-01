import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_recovery_trace.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';

/// Low-rate process evidence. No business recovery, queue mutation or I/O on
/// the synchronous event path. Up to five seconds may be lost on process kill.
class ChatLivenessDiagnostics with WidgetsBindingObserver {
  ChatLivenessDiagnostics._();
  static final instance = ChatLivenessDiagnostics._();
  static const lastRunKey = 'chat_trace_last_run_v1';
  static const previousRunKey = 'chat_trace_previous_run_v1';
  final Map<Object, String> _routes = {};
  Timer? _timer;
  Future<void>? _initializing;
  bool _writing = false;
  int _frames = 0, _touches = 0, _heartbeat = 0;
  bool _framePending = false;
  String _lifecycle = 'unknown';
  List<String> previousRunEvents = const [];

  void attach(Object route, String conversation) {
    final first = _routes.isEmpty;
    _routes[route] = '$conversation:visible';
    if (first) {
      WidgetsBinding.instance.addObserver(this);
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
      SchedulerBinding.instance.addTimingsCallback(_timings);
      _initializing ??= _restorePrevious();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => sample());
    }
    routeState(route, conversation, 'visible');
  }

  void routeState(Object route, String conversation, String state) {
    if (!_routes.containsKey(route)) return;
    _routes[route] = '$conversation:$state';
    ChatRecoveryTrace.log('route_state',
        conversationID: conversation, fields: {'route': state});
  }

  void detach(Object route) {
    _routes.remove(route);
    if (_routes.isNotEmpty) return;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    unawaited(flush());
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerUpEvent) _touches++;
  }

  void _timings(List<FrameTiming> timings) {
    _frames += timings.length;
  }

  @override
  void didHaveMemoryPressure() {
    ChatRecoveryTrace.log('memory_pressure',
        conversationID: '',
        fields: {'routes': _routes.values.join(','), 'frames': _frames});
    unawaited(flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state.name;
    ChatRecoveryTrace.log('app_lifecycle',
        conversationID: '', fields: {'state': state.name});
    unawaited(flush());
  }

  void sample() {
    final tick = ++_heartbeat;
    bool mediaOverlay = false;
    try {
      mediaOverlay = serviceLocator<TUIChatGlobalModel>()
          .shouldLockChatScrollForMediaPreview;
    } catch (_) {
      // Diagnostics may run before the chat service locator is configured.
    }
    ChatRecoveryTrace.log('ui_heartbeat', conversationID: '', fields: {
      'tick': tick,
      'frames': _frames,
      'touches': _touches,
      'framePending': _framePending,
      'route': _routes.values.join(','),
      'mediaOverlay': mediaOverlay,
      'lifecycle': _lifecycle,
    });
    // At most one outstanding probe. A quiet screen is not a hung renderer.
    if (!_framePending && _routes.isNotEmpty) {
      _framePending = true;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _framePending = false;
        ChatRecoveryTrace.log('frame_heartbeat',
            conversationID: '', fields: {'tick': tick});
      });
    }
    unawaited(flush());
  }

  Future<void> _restorePrevious() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(lastRunKey);
      if (last != null) {
        final rows =
            (jsonDecode(last) as List).whereType<String>().take(80).toList();
        previousRunEvents = List.unmodifiable(rows);
        await prefs.setString(previousRunKey, jsonEncode(rows));
      }
    } catch (_) {/* Diagnostics never block chat. */}
  }

  Future<void> flush() async {
    if (_writing) return;
    _writing = true;
    try {
      await (_initializing ??= _restorePrevious());
      final events = ChatRecoveryTrace.recentEvents;
      final tail =
          events.skip(events.length > 80 ? events.length - 80 : 0).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastRunKey, jsonEncode(tail));
    } catch (_) {
      /* Disk/platform failures cannot affect business work. */
    } finally {
      _writing = false;
    }
  }
}
