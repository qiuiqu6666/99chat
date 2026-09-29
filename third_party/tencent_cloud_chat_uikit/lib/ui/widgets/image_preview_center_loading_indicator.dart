import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'interactive_preview_fallback.dart';

/// Returns real download progress when the response includes a total size.
double? imagePreviewDownloadProgress(ImageChunkEvent? event) {
  final total = event?.expectedTotalBytes;
  if (event == null || total == null || total <= 0) return null;
  return (event.cumulativeBytesLoaded / total).clamp(0.0, 1.0);
}

/// 全屏预览：轻量白环和真实下载扇形，短暂加载不闪现指示器。
class ImagePreviewCenterLoadingIndicator extends StatefulWidget {
  const ImagePreviewCenterLoadingIndicator({
    super.key,
    this.size = 40,
    this.strokeWidth = 1.5,
    this.progress,
  });

  final double size;
  final double strokeWidth;

  /// `0..1` 为实际已下载字节 / 总字节；`null` 保持上次进度或静止空环。
  final double? progress;

  @override
  State<ImagePreviewCenterLoadingIndicator> createState() =>
      _ImagePreviewCenterLoadingIndicatorState();
}

class _ImagePreviewCenterLoadingIndicatorState
    extends State<ImagePreviewCenterLoadingIndicator>
    with TickerProviderStateMixin {
  static const _progressDuration = Duration(milliseconds: 100);
  late final AnimationController _progress;
  late final AnimationController _appearance;
  Timer? _showDelay;
  bool _reduceMotion = false;
  double? _lastKnownProgress;

  @override
  void initState() {
    super.initState();
    _lastKnownProgress = _measured(widget.progress);
    _progress = AnimationController(
      vsync: this,
      value: _lastKnownProgress ?? 0,
      duration: _progressDuration,
    );
    _appearance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _showDelay = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _appearance.forward();
    });
  }

  double? _measured(double? value) =>
      value != null && value.isFinite ? value.clamp(0.0, 1.0) : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _showDelay?.cancel();
      _appearance.value = 1;
      _progress.value = _lastKnownProgress ?? 0;
    }
  }

  @override
  void didUpdateWidget(ImagePreviewCenterLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chunk events may omit total size while decoding or switching providers.
    // Keep the last measured value until a new measured value arrives. A new
    // image/loading widget gets its own state; no invented progress is added.
    final measured = _measured(widget.progress);
    if (measured != null && measured != _lastKnownProgress) {
      _lastKnownProgress = measured;
      if (_reduceMotion || measured < _progress.value) {
        _progress.value = measured;
      } else {
        // Ease only towards an already measured byte count, never past it.
        // New chunks continue from the visible angle; no restart from zero.
        _progress.animateTo(measured,
            duration: _progressDuration, curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _showDelay?.cancel();
    _appearance.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _appearance,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) => CustomPaint(
              painter: _ImagePreviewLoadingPainter(
                progress: _progress.value,
                strokeWidth: widget.strokeWidth,
                determinate: _lastKnownProgress != null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewLoadingPainter extends CustomPainter {
  const _ImagePreviewLoadingPainter({
    required this.progress,
    required this.strokeWidth,
    this.determinate = true,
  });

  final double progress;
  final double strokeWidth;
  final bool determinate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final radius = (size.width * 0.5) - strokeWidth;
    canvas.drawCircle(
      center,
      radius + strokeWidth,
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Unknown byte counts never produce a rotating or fabricated sector.
    if (!determinate) return;

    final clamped = progress.clamp(0.0, 1.0);
    const startAngle = -math.pi / 2;
    final sweepAngle = math.pi * 2 * clamped;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final fillRadius = radius - strokeWidth - 1.5;
    // A closed Path.arcTo at exactly 2π can collapse to its start point.
    // Keep the completed download visibly full while the image is decoding.
    if (clamped == 1) {
      canvas.drawCircle(center, fillRadius, fillPaint);
      return;
    }
    final fillPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: fillRadius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();
    if (clamped > 0) canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _ImagePreviewLoadingPainter oldDelegate) {
    return oldDelegate.determinate != determinate ||
        oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// 全屏预览加载层：先铺底图（气泡缩略图），再叠居中扇形指示器。
class ImagePreviewLoadingLayer extends StatelessWidget {
  const ImagePreviewLoadingLayer({
    super.key,
    this.placeholder,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.progress,
    this.showSpinner = true,
    this.interactive = false,
  });

  final ImageProvider? placeholder;
  final BoxFit fit;
  final Alignment alignment;
  final double? progress;
  final bool showSpinner;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (interactive && placeholder != null) {
      return InteractivePreviewFallback(image: placeholder!);
    }
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (placeholder != null)
          Image(
            image: placeholder!,
            fit: fit,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            // 内存命中时首帧即显示，避免底图未就绪时先黑一拍。
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return const SizedBox.expand();
            },
          ),
        if (showSpinner)
          Center(
            child: ImagePreviewCenterLoadingIndicator(progress: progress),
          ),
      ],
    );
  }
}
