import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';

/// A retained handle to decoded pixels and their last painted geometry. Keeping
/// this outside Hero's placeholder preserves zoom/scroll when its child unmounts.
class MediaPreviewImageFrameController {
  _ImageFrame? _frame;
  _ImageSurface? _surface;

  void capture() {
    final surface = _surface;
    if (surface != null && surface.attached && surface.hasSize) {
      _capture(surface);
    }
  }

  void _capture(_ImageSurface surface) {
    final frame = _readFrame(surface);
    if (frame == null) return;
    final oldImage = _frame?.image;
    final image = oldImage != null && oldImage.isCloneOf(frame.image)
        ? oldImage
        : frame.image.clone();
    if (!identical(image, oldImage)) oldImage?.dispose();
    _frame = _ImageFrame(image, frame.imageRect, frame.clipRect,
        frame.colorFilter, frame.invertColors, frame.flipHorizontally);
  }

  void dispose() {
    _frame?.image.dispose();
    _frame = null;
    _surface = null;
  }
}

class MediaPreviewImageFrameScope extends InheritedWidget {
  const MediaPreviewImageFrameScope(
      {super.key, required this.controller, required super.child});
  final MediaPreviewImageFrameController controller;

  static MediaPreviewImageFrameController? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<MediaPreviewImageFrameScope>()
      ?.controller;

  @override
  bool updateShouldNotify(MediaPreviewImageFrameScope oldWidget) =>
      controller != oldWidget.controller;
}

class MediaPreviewImageSurface extends SingleChildRenderObjectWidget {
  const MediaPreviewImageSurface(
      {super.key, required this.controller, required super.child});
  final MediaPreviewImageFrameController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ImageSurface(controller);

  @override
  void updateRenderObject(
      BuildContext context, covariant _ImageSurface renderObject) {
    renderObject.controller = controller;
    controller._surface = renderObject;
  }
}

class _ImageSurface extends RenderProxyBox {
  _ImageSurface(this.controller) {
    controller._surface = this;
  }
  MediaPreviewImageFrameController controller;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    controller._capture(this);
  }

  @override
  void dispose() {
    if (identical(controller._surface, this)) controller._surface = null;
    super.dispose();
  }
}

class _ImageFrame {
  const _ImageFrame(this.image, this.imageRect, this.clipRect, this.colorFilter,
      this.invertColors, this.flipHorizontally);
  final ui.Image image;
  // Both rectangles are in the Hero's local coordinates. imageRect describes
  // the entire bitmap, including pixels outside the currently visible crop.
  final Rect imageRect;
  final Rect clipRect;
  final ColorFilter? colorFilter;
  final bool invertColors;
  final bool flipHorizontally;
}

_ImageFrame? _readFrame(RenderBox root) {
  _ImageFrame? result;
  void visit(RenderObject node) {
    if (node is RenderOffstage && node.offstage) return;
    if (node is RenderImage || node is ExtendedRenderImage) {
      final box = node as RenderBox;
      if (!box.hasSize || box.size.isEmpty) return;
      ui.Image? image;
      late double scale;
      BoxFit? fit;
      late Alignment alignment;
      Rect? source;
      GestureDetails? gesture;
      Color? color;
      BlendMode? blend;
      late bool inverted, flipped;
      var bounds = Offset.zero & box.size;
      if (node is ExtendedRenderImage) {
        image = node.image;
        scale = node.scale;
        fit = node.fit;
        alignment = node.alignment.resolve(node.textDirection);
        source = node.sourceRect;
        gesture = node.gestureDetails;
        color = node.color;
        blend = node.colorBlendMode;
        inverted = node.invertColors;
        flipped =
            node.matchTextDirection && node.textDirection == TextDirection.rtl;
        bounds = node.layoutInsets.deflateRect(bounds);
        if (node.centerSlice != null ||
            node.editActionDetails != null ||
            node.repeat != ImageRepeat.noRepeat) {
          return;
        }
      } else {
        final raw = node as RenderImage;
        image = raw.image;
        scale = raw.scale;
        fit = raw.fit;
        alignment = raw.alignment.resolve(raw.textDirection);
        color = raw.color;
        blend = raw.colorBlendMode;
        inverted = raw.invertColors;
        flipped =
            raw.matchTextDirection && raw.textDirection == TextDirection.rtl;
        if (raw.centerSlice != null || raw.repeat != ImageRepeat.noRepeat) {
          return;
        }
      }
      if (image == null || bounds.isEmpty) return;
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final fitted =
          applyBoxFit(fit ?? BoxFit.scaleDown, imageSize / scale, bounds.size);
      source ??=
          alignment.inscribe(fitted.source * scale, Offset.zero & imageSize);
      var destination = alignment.inscribe(fitted.destination, bounds);
      // The library records these in paint coordinates, not RenderBox local
      // coordinates. Subtract its layout origin; do not reset the gesture.
      if (gesture?.destinationRect != null && gesture?.layoutRect != null) {
        destination =
            gesture!.destinationRect!.shift(-gesture.layoutRect!.topLeft);
      }
      if (source.isEmpty || destination.isEmpty) return;
      final sx = destination.width / source.width;
      final sy = destination.height / source.height;
      final fullImage = Rect.fromLTWH(
          destination.left - source.left * sx,
          destination.top - source.top * sy,
          imageSize.width * sx,
          imageSize.height * sy);
      final transform = box.getTransformTo(root);
      // Rotated/editor content keeps the existing widget fallback.
      if (transform.entry(0, 1).abs() > .0001 ||
          transform.entry(1, 0).abs() > .0001 ||
          transform.entry(0, 0) <= 0 ||
          transform.entry(1, 1) <= 0) {
        return;
      }
      var clip = Offset.zero & root.size;
      if (gesture != null) {
        clip = clip.intersect(
            MatrixUtils.transformRect(transform, Offset.zero & box.size));
      }
      RenderObject child = box;
      while (!identical(child, root)) {
        final parent = child.parent;
        if (parent is! RenderObject) return;
        final parentClip = parent.describeApproximatePaintClip(child);
        if (parentClip != null) {
          clip = clip.intersect(MatrixUtils.transformRect(
              parent.getTransformTo(root), parentClip));
        }
        child = parent;
      }
      final imageRect = MatrixUtils.transformRect(transform, fullImage);
      final visible = clip.intersect(imageRect);
      if (visible.isEmpty) return;
      final candidate = _ImageFrame(
          image,
          imageRect,
          clip,
          color == null
              ? null
              : ColorFilter.mode(color, blend ?? BlendMode.srcIn),
          inverted,
          flipped);
      final previous = result;
      if (previous == null ||
          visible.size.width * visible.size.height >
              previous.clipRect.intersect(previous.imageRect).size.width *
                  previous.clipRect.intersect(previous.imageRect).size.height) {
        result = candidate;
      }
      return;
    }
    node.visitChildren(visit);
  }

  root.visitChildren(visit);
  return result;
}

/// The same bitmap/geometry interpolation is used in both directions. Only an
/// image handle is retained: no screenshot, extra decode or GPU readback.
Widget? buildMediaPreviewImageFlight({
  required BuildContext fromContext,
  required BuildContext toContext,
  required Animation<double> animation,
  required HeroFlightDirection direction,
  required double cornerRadius,
}) {
  final from = MediaPreviewImageFrameScope.of(fromContext)?._frame;
  final to = MediaPreviewImageFrameScope.of(toContext)?._frame;
  if (from == null || to == null) return null;
  return _ImageFlight(
      from: from,
      to: to,
      animation: animation,
      direction: direction,
      cornerRadius: cornerRadius,
      fromOpacity: fromContext
              .getInheritedWidgetOfExactType<MediaPreviewSlideVisualScope>()
              ?.notifier
              ?.contentOpacity ??
          1,
      toOpacity: toContext
              .getInheritedWidgetOfExactType<MediaPreviewSlideVisualScope>()
              ?.notifier
              ?.contentOpacity ??
          1);
}

class _ImageFlight extends StatefulWidget {
  const _ImageFlight(
      {required this.from,
      required this.to,
      required this.animation,
      required this.direction,
      required this.cornerRadius,
      required this.fromOpacity,
      required this.toOpacity});
  final _ImageFrame from, to;
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final double cornerRadius;
  final double fromOpacity, toOpacity;
  @override
  State<_ImageFlight> createState() => _ImageFlightState();
}

class _ImageFlightState extends State<_ImageFlight> {
  late final ui.Image image = widget.from.image.clone();
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _ImageFlightPainter(
          image,
          widget.from,
          widget.to,
          widget.animation,
          widget.direction,
          widget.cornerRadius,
          widget.fromOpacity,
          widget.toOpacity),
      child: const SizedBox.expand());
  @override
  void dispose() {
    image.dispose();
    super.dispose();
  }
}

class _ImageFlightPainter extends CustomPainter {
  _ImageFlightPainter(this.image, this.from, this.to, this.animation,
      this.direction, this.cornerRadius, this.fromOpacity, this.toOpacity)
      : super(repaint: animation);
  final ui.Image image;
  final _ImageFrame from, to;
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final double cornerRadius;
  final double fromOpacity, toOpacity;
  @override
  void paint(Canvas canvas, Size size) {
    final t = direction == HeroFlightDirection.push
        ? animation.value
        : 1 - animation.value;
    final rect = Rect.lerp(from.imageRect, to.imageRect, t)!;
    final clip = Rect.lerp(from.clipRect, to.clipRect, t)!.intersect(rect);
    if (clip.isEmpty) return;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        clip, Radius.circular(cornerRadius * (1 - animation.value))));
    if (from.flipHorizontally) {
      canvas.translate(rect.left + rect.right, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()
          ..color = Color.fromRGBO(
              255, 255, 255, fromOpacity + (toOpacity - fromOpacity) * t)
          ..filterQuality = FilterQuality.low
          ..colorFilter = from.colorFilter
          ..invertColors = from.invertColors);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImageFlightPainter oldDelegate) => true;
}
