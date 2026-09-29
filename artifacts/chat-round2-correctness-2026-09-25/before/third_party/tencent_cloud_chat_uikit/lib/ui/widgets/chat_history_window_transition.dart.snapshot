import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Retain one viewport while a disjoint SDK window is laid out and positioned.
/// Also covers idle trims whose lazy rows need multiple layouts to remount.
/// Never blend two sets of message text.
class ChatHistoryWindowTransition extends StatefulWidget {
  const ChatHistoryWindowTransition({super.key, required this.child});
  final Widget child;

  @override
  State<ChatHistoryWindowTransition> createState() =>
      ChatHistoryWindowTransitionState();
}

class ChatHistoryWindowTransitionState
    extends State<ChatHistoryWindowTransition> {
  final _boundaryKey = GlobalKey();
  ui.Image? _image;
  bool _busy = false;
  bool _showSpinner = false;
  bool _showProgress = true;
  Future<void>? _finishing;
  Timer? _deferredProgressTimer;
  Timer? _retentionDeadline;
  VoidCallback? _onInterrupted;
  int _generation = 0;

  bool get isRetainingViewport => _image != null;
  int get generation => _generation;

  bool begin({
    bool retainViewport = true,
    bool showSpinner = false,
    bool showProgress = true,
    bool requireSnapshot = false,
    Duration? showProgressAfter,
    Duration? maxRetention,
    VoidCallback? onInterrupted,
  }) {
    if (!mounted || _busy) return false;
    _deferredProgressTimer?.cancel();
    _deferredProgressTimer = null;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    var needsPaint = false;
    assert(() {
      // Flutter's debugNeedsPaint getter throws with assertions disabled.
      needsPaint =
          boundary is RenderRepaintBoundary && boundary.debugNeedsPaint;
      return true;
    }());
    ui.Image? image;
    if (retainViewport &&
        boundary is RenderRepaintBoundary &&
        boundary.attached &&
        boundary.hasSize &&
        !needsPaint &&
        !boundary.size.isEmpty) {
      try {
        // Logical-resolution snapshots visibly blur text on high-DPI phones.
        image =
            boundary.toImageSync(pixelRatio: View.of(context).devicePixelRatio);
      } catch (_) {
        // Unsupported surfaces keep rendering the live list.
      }
    }
    // An optional background trim must not expose its intermediate layouts or
    // acquire the transition lane when a painted snapshot is unavailable.
    if (requireSnapshot && image == null) return false;
    final generation = ++_generation;
    _onInterrupted = onInterrupted;
    setState(() {
      _busy = true;
      _showSpinner = showSpinner || !retainViewport;
      _showProgress = showProgress;
      _image = image;
    });
    if (maxRetention != null) {
      _retentionDeadline = Timer(maxRetention, () {
        if (mounted && _busy && generation == _generation) _interrupt();
      });
    }
    if (showProgressAfter != null && image != null) {
      _deferredProgressTimer = Timer(showProgressAfter, () {
        _deferredProgressTimer = null;
        if (mounted && _busy) {
          setState(() => _showProgress = true);
        }
      });
    }
    return image != null;
  }

  Future<void> finish() {
    if (!mounted || !_busy) return Future<void>.value();
    return _finishing ??= _finishAfterLayout();
  }

  Future<void> _finishAfterLayout() async {
    final generation = _generation;
    // Complete target layout, then replace the retained frame atomically.
    // Fading the old text over the new text causes double-image ghosting.
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _generation) return;
    release();
  }

  void _interrupt() {
    if (!_busy) return;
    final callback = _onInterrupted;
    // Invalidate the owner's restore work before the same pointer reaches it.
    try {
      callback?.call();
    } finally {
      release();
    }
  }

  /// Reveal the last laid-out window without awaiting IO or another frame.
  void release({int? expectedGeneration}) {
    if (!mounted ||
        !_busy ||
        (expectedGeneration != null && expectedGeneration != _generation))
      return;
    _generation++;
    _retentionDeadline?.cancel();
    _retentionDeadline = null;
    _onInterrupted = null;
    _deferredProgressTimer?.cancel();
    _deferredProgressTimer = null;
    final oldImage = _image;
    setState(() {
      _image = null;
      _busy = false;
      _showSpinner = false;
      _showProgress = true;
    });
    _finishing = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => oldImage?.dispose());
  }

  @override
  void dispose() {
    _retentionDeadline?.cancel();
    _deferredProgressTimer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: _onInterrupted == null ? null : (_) => _interrupt(),
      onPointerSignal: _onInterrupted == null ? null : (_) => _interrupt(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          AbsorbPointer(
            // An interruptible trim must let this very gesture reach the live
            // Scrollable, rather than swallowing its initial pointer-down.
            absorbing: _busy && _onInterrupted == null,
            // Chat backgrounds live outside this boundary. The snapshot can
            // have transparent gaps: keep target layout alive but do not paint
            // new rows through those gaps, even before finish() is called.
            child: Opacity(
              // If capture is unavailable, keep the live messages visible.
              // Loading must never turn an existing conversation into a blank.
              opacity: isRetainingViewport ? 0 : 1,
              child: RepaintBoundary(key: _boundaryKey, child: widget.child),
            ),
          ),
          if (_image != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RawImage(image: _image, fit: BoxFit.fill),
              ),
            ),
          if (_busy && _showSpinner)
            Positioned.fill(
              child: Center(
                child: Semantics(
                  label: '正在定位消息',
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
          if (_busy && !_showSpinner && _showProgress)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child:
                  IgnorePointer(child: LinearProgressIndicator(minHeight: 2)),
            ),
        ],
      ));
}
