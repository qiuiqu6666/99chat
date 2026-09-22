import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';

/// A decoded thumbnail remains usable when the full-resolution path fails.
/// Its natural height is laid out outside the viewport, rather than cropped
/// inside a screen-sized Image before gesture handling is attached.
class InteractivePreviewFallback extends StatefulWidget {
  const InteractivePreviewFallback(
      {super.key, required this.image, this.onTap, this.sourcePixelSize,
      this.fitTallImagesToScreenWidth = true});

  final ImageProvider image;
  final VoidCallback? onTap;
  final Size? sourcePixelSize;
  final bool fitTallImagesToScreenWidth;

  @override
  State<InteractivePreviewFallback> createState() =>
      _InteractivePreviewFallbackState();
}

class _InteractivePreviewFallbackState
    extends State<InteractivePreviewFallback> {
  final _controller = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final source = widget.sourcePixelSize;
        final config = source == null ? null : imagePreviewDisplayConfig(
            imageWidth: source.width.round(), imageHeight: source.height.round(),
            screenWidth: bounds.maxWidth, screenHeight: bounds.maxHeight,
            fitTallImagesToScreenWidth: widget.fitTallImagesToScreenWidth);
        final display = source == null ? null : imagePreviewInitialDisplaySize(
            imageWidth: source.width.round(), imageHeight: source.height.round(),
            screenWidth: bounds.maxWidth, screenHeight: bounds.maxHeight,
            fit: config!.fit);
        return GestureDetector(
          onTap: widget.onTap,
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: () {
            if (_controller.value.getMaxScaleOnAxis() > 1.01) {
              _controller.value = Matrix4.identity();
            } else {
              final scene = _controller.toScene(_doubleTapPosition);
              _controller.value = Matrix4.identity()
                ..translateByDouble(_doubleTapPosition.dx - scene.dx * 2,
                    _doubleTapPosition.dy - scene.dy * 2, 0, 1)
                ..scaleByDouble(2, 2, 1, 1);
            }
          },
          child: InteractiveViewer(
            transformationController: _controller,
            constrained: false,
            alignment: Alignment.topLeft,
            minScale: 1,
            maxScale: 8,
            child: SizedBox(
              width: bounds.maxWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: bounds.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image(
                      image: widget.image,
                      width: display?.width ?? bounds.maxWidth,
                      height: display?.height,
                      fit: display == null ? BoxFit.fitWidth : BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      });
}
