import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/chat_ui_state_store.dart';

/// 宽屏鼠标长按后上下拖动：按行命中勾选气泡，靠近顶/底时自动翻页。
class DesktopMessageDragSelect {
  DesktopMessageDragSelect._();

  static final Map<String, DesktopMessageDragSelect> _byConv = {};

  static DesktopMessageDragSelect of(String conversationID) {
    return _byConv.putIfAbsent(conversationID, DesktopMessageDragSelect._);
  }

  static const double _edgeZone = 56;
  static const double _minSpeed = 260;
  static const double _maxSpeed = 1400;
  static const Duration _tick = Duration(milliseconds: 16);

  final Map<String, _DesktopMessageDragRow> _rows = {};
  bool _active = false;
  String? _anchorKey;
  TUIChatSeparateViewModel? _model;
  Offset? _pointer;
  ScrollPosition? _position;
  Timer? _autoScrollTimer;
  final Set<String> _sessionKeys = {};

  void register({
    required V2TimMessage message,
    required GlobalKey rowKey,
  }) {
    final key = ChatUiStateStore.messageKeyOf(message);
    if (key.isEmpty) {
      return;
    }
    _rows[key] = _DesktopMessageDragRow(message: message, rowKey: rowKey);
  }

  void unregister(V2TimMessage message) {
    final key = ChatUiStateStore.messageKeyOf(message);
    if (key.isEmpty) {
      return;
    }
    _rows.remove(key);
  }

  void begin({
    required TUIChatSeparateViewModel model,
    required V2TimMessage anchor,
    required Offset global,
    required BuildContext context,
  }) {
    _active = true;
    _model = model;
    _pointer = global;
    _anchorKey = ChatUiStateStore.messageKeyOf(anchor);
    _sessionKeys.clear();
    _position = Scrollable.maybeOf(context)?.position;
    if (!model.isMultiSelect) {
      model.updateMultiSelectStatus(true);
    }
    _paintSelection();
    _syncAutoScroll();
  }

  void update({
    required TUIChatSeparateViewModel model,
    required Offset global,
    required BuildContext context,
  }) {
    if (!_active) {
      return;
    }
    _model = model;
    _pointer = global;
    _position = Scrollable.maybeOf(context)?.position ?? _position;
    _paintSelection();
    _syncAutoScroll();
  }

  void end() {
    _stopAutoScroll();
    _active = false;
    _anchorKey = null;
    _model = null;
    _pointer = null;
    _position = null;
    _sessionKeys.clear();
  }

  void _paintSelection() {
    final model = _model;
    final pointer = _pointer;
    if (model == null || pointer == null) {
      return;
    }
    final loHi = _selectionBand(pointer);
    if (loHi == null) {
      return;
    }
    final inRange = <String>{};
    for (final entry in _rows.entries) {
      final box = _rowBox(entry.value);
      if (box == null) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom >= loHi.$1 && top <= loHi.$2) {
        inRange.add(entry.key);
      }
    }
    for (final key in inRange) {
      if (_sessionKeys.contains(key)) {
        continue;
      }
      final message = _rows[key]?.message;
      if (message != null) {
        model.setMessageItemChecked(message, true);
      }
    }
    for (final key in _sessionKeys.difference(inRange)) {
      final message = _rows[key]?.message;
      if (message != null) {
        model.setMessageItemChecked(message, false);
      }
    }
    _sessionKeys
      ..clear()
      ..addAll(inRange);
  }

  (double, double)? _selectionBand(Offset pointer) {
    final anchorBox = _anchorKey == null ? null : _rowBox(_rows[_anchorKey!]);
    final startY = anchorBox == null
        ? pointer.dy
        : anchorBox.localToGlobal(Offset.zero).dy + anchorBox.size.height / 2;
    return (min(startY, pointer.dy), max(startY, pointer.dy));
  }

  RenderBox? _rowBox(_DesktopMessageDragRow? row) {
    final box = row?.rowKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      return null;
    }
    return box;
  }

  void _syncAutoScroll() {
    final pointer = _pointer;
    final position = _position;
    if (pointer == null ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      _stopAutoScroll();
      return;
    }
    final context = position.context.notificationContext ??
        position.context.storageContext;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      _stopAutoScroll();
      return;
    }
    final viewport = box.localToGlobal(Offset.zero) & box.size;
    final velocity = _edgeVelocity(pointer, viewport);
    if (velocity == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(_tick, _autoScrollTick);
  }

  double _edgeVelocity(Offset pointer, Rect viewport) {
    if (pointer.dy <= viewport.top + _edgeZone) {
      final t = ((viewport.top + _edgeZone) - pointer.dy) / _edgeZone;
      return _speedFor(t);
    }
    if (pointer.dy >= viewport.bottom - _edgeZone) {
      final t = (pointer.dy - (viewport.bottom - _edgeZone)) / _edgeZone;
      return -_speedFor(t);
    }
    return 0;
  }

  double _speedFor(double t) {
    return (_minSpeed + (_maxSpeed - _minSpeed) * t.clamp(0.0, 1.6))
        .clamp(_minSpeed, _maxSpeed);
  }

  void _autoScrollTick(Timer timer) {
    if (!_active) {
      _stopAutoScroll();
      return;
    }
    final pointer = _pointer;
    final position = _position;
    if (pointer == null ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      _stopAutoScroll();
      return;
    }
    final context = position.context.notificationContext ??
        position.context.storageContext;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      _stopAutoScroll();
      return;
    }
    final viewport = box.localToGlobal(Offset.zero) & box.size;
    final velocity = _edgeVelocity(pointer, viewport);
    if (velocity == 0) {
      _stopAutoScroll();
      return;
    }
    final next = (position.pixels + velocity * _tick.inMilliseconds / 1000)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) {
      position.jumpTo(next);
    }
    _paintSelection();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }
}

class _DesktopMessageDragRow {
  const _DesktopMessageDragRow({
    required this.message,
    required this.rowKey,
  });

  final V2TimMessage message;
  final GlobalKey rowKey;
}
