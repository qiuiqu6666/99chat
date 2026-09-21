import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/keyboard_viewport_transition_coordinator.dart';

class ImeInsetsBridge {
  static const MethodChannel _method = MethodChannel('ninechat/ime_insets');
  static const EventChannel _events =
      EventChannel('ninechat/ime_insets_events');
  // One native subscription shared by all mounted chat routes. Cancelling a
  // covered route must not cancel another route's native event handler.
  static final Stream<dynamic> _sharedEvents = _events.receiveBroadcastStream();

  StreamSubscription<dynamic>? _subscription;
  KeyboardViewportTransitionCoordinator? _coordinator;
  bool _started = false;
  int _generation = 0;
  int _eventRevision = 0;

  Future<void> start(KeyboardViewportTransitionCoordinator coordinator) async {
    if (_started) {
      return;
    }
    _started = true;
    _coordinator = coordinator;
    final generation = ++_generation;
    final revision = _eventRevision;
    _subscription = _sharedEvents.listen(
      _onEvent,
      onError: (Object error) {
        if (kDebugMode) debugPrint('[KeyboardDiag] IME stream: $error');
      },
    );
    try {
      final data = await _method.invokeMethod<dynamic>('get');
      // A snapshot may finish after a newer keyboard event or route disposal.
      if (_started && generation == _generation && revision == _eventRevision) {
        _onEvent(data);
      }
    } on MissingPluginException {
      return;
    } catch (error) {
      if (kDebugMode) debugPrint('[KeyboardDiag] IME snapshot: $error');
    }
  }

  void stop() {
    _started = false;
    _generation++;
    _coordinator = null;
    _subscription?.cancel();
    _subscription = null;
  }

  void _onEvent(dynamic data) {
    if (!_started || data is! Map) {
      return;
    }
    _eventRevision++;
    final visible = data['visible'] == true;
    final imeHeight = (data['imeHeight'] as num?)?.toDouble() ?? 0;
    final device = data['device'] as String? ?? '';
    _coordinator?.applyNativeIme(
      visible: visible,
      imeHeight: imeHeight,
      device: device,
    );
  }
}
