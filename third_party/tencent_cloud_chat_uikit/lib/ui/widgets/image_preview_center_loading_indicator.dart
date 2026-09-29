import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'interactive_preview_fallback.dart';

/// Returns real download progress when the response includes a total size.
double? imagePreviewDownloadProgress(ImageChunkEvent? event) {
  final total = event?.expectedTotalBytes;
  if (event == null || total == null || total <= 0) return null;
  return (event.cumulativeBytesLoaded / total).clamp(0.0, 1.0);
}

/// 全屏图片预览居中加载：白环 + 扇形填充，对齐 iOS 相册式加载反馈。
class ImagePreviewCenterLoadingIndicator extends StatefulWidget {
  const ImagePreviewCenterLoadingIndicator({
    super.key,
    this.size = 52,
    this.strokeWidth = 2.4,
    this.progress,
  });

  final double size;
  final double strokeWidth;

  /// `null` 为不确定进度动画；`0..1` 为确定进度。
  final double? progress;

  @override
  State<ImagePreviewCenterLoadingIndicator> createState() =>
      _ImagePreviewCenterLoadingIndicatorState();
}

class _ImagePreviewCenterLoadingIndicatorState
    extends State<ImagePreviewCenterLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _lastKnownProgress;

  @override
  void initState() {
    super.initState();
    _lastKnownProgress = widget.progress;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (_lastKnownProgress == null) _controller.repeat();
  }

  @override
  void didUpdateWidget(ImagePreviewCenterLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chunk events may omit total size while decoding or switching providers.
    // Keep the last measured value until a new measured value arrives. A new
    // image/loading widget gets its own state; no invented progress is added.
    if (widget.progress != null) {
      _lastKnownProgress = widget.progress;
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ImagePreviewLoadingPainter(
              progress: (_lastKnownProgress ?? 0).clamp(0.0, 1.0),
              rotation: _lastKnownProgress == null ? _controller.value : 0,
              strokeWidth: widget.strokeWidth,
              determinate: _lastKnownProgress != null,
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
    required this.rotation,
    required this.strokeWidth,
    this.determinate = true,
  });

  final double progress;
  final double rotation;
  final double strokeWidth;
  final bool determinate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final radius = (size.width * 0.5) - strokeWidth;
    canvas.drawCircle(
      center, radius + strokeWidth,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (!determinate) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 + rotation * math.pi * 2,
        math.pi * 0.45,
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final clamped = progress.clamp(0.0, 1.0);
    const startAngle = -math.pi / 2;
    final sweepAngle = math.pi * 2 * clamped;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    final fillPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius - strokeWidth - 2),
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
        oldDelegate.rotation != rotation ||
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
