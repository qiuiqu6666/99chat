import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:extended_image/extended_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_preview_image_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_region_grid.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/tall_image_gallery_scroll_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tall_image_scroll_preview.dart';
import 'interactive_preview_fallback.dart';

class TiledImagePreview extends StatefulWidget {
  const TiledImagePreview({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    this.message,
    this.placeholder,
    this.onTap,
    this.inPageView = false,
    this.galleryScrollGate,
    this.onSlideDismiss,
    this.fitTallImagesToScreenWidth = true,
  });

  final int imageWidth;
  final int imageHeight;
  final V2TimMessage? message;
  final ImageProvider? placeholder;
  final VoidCallback? onTap;
  final bool inPageView;
  final ValueNotifier<TallImageGalleryScrollGate>? galleryScrollGate;
  final TallImageSlideDismissCallback? onSlideDismiss;
  final bool fitTallImagesToScreenWidth;

  @override
  State<TiledImagePreview> createState() => _TiledImagePreviewState();
}

class _TiledImagePreviewState extends State<TiledImagePreview> {
  final TransformationController _controller = TransformationController();
  final Map<int, ui.Image> _tiles = {};
  final Set<(int, int)> _inFlight = {};
  ImagePreviewRegionGrid? _grid;
  List<int> _wanted = [];
  String? _localPath;
  bool _resolvingOriginal = false;
  bool _unsupported = false;
  bool _loadFailed = false;
  int _loadGeneration = 0;
  int _epoch = 0;
  bool _pumpScheduled = false;
  Size _viewport = Size.zero;
  Size _display = Size.zero;
  bool _topAligned = true;
  Offset _doubleTap = Offset.zero;
  Offset _pointerDelta = Offset.zero;
  bool _dismissPending = false;
  final Set<int> _pointers = {};
  ExtendedImageGesturePageViewState? _pageView;
  Matrix4? _pageFrozen;
  VelocityTracker? _velocity;
  bool _routingPage = false;
  bool _startedAtLeft = true;
  bool _startedAtRight = true;

  bool get _desktop => PlatformUtils().isWinMacDesktop;
  int get _tileLimit => _desktop ? 96 : 48;
  double get _scale => _controller.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _ensureLocalOriginal();
  }

  @override
  void didUpdateWidget(covariant TiledImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _epoch++;
      for (final image in _tiles.values) {
        image.dispose();
      }
      _tiles.clear();
      _wanted = [];
      _grid = null;
      _localPath = null;
      _unsupported = false;
      _loadFailed = false;
      _loadGeneration++;
      _resolvingOriginal = false;
      _viewport = Size.zero;
      _display = Size.zero;
      _controller.value = Matrix4.identity();
      _ensureLocalOriginal();
    }
  }

  @override
  void dispose() {
    if (_routingPage) _pageView?.onDragCancel();
    _epoch++;
    _loadGeneration++;
    _controller.dispose();
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
    super.dispose();
  }

  Future<void> _ensureLocalOriginal() async {
    final message = widget.message;
    if (message == null) {
      _loadFailed = true;
      return;
    }
    final existing = ChatMessagePreviewImageResolver.localOriginalFilePath(
      message,
    );
    if (existing != null) {
      setState(() => _localPath = existing);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestVisibleTiles(settled: true);
        }
      });
      return;
    }
    if (_resolvingOriginal) {
      return;
    }
    _resolvingOriginal = true;
    final generation = ++_loadGeneration;
    try {
      // Region decoding needs a local file, not merely a resolvable URL.
      final refreshed = await ChatMessagePreviewImageResolver.refreshOriginal(
        message,
        forceDownload: true,
      ).timeout(const Duration(seconds: 60));
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      final path = ChatMessagePreviewImageResolver.localOriginalFilePath(
        message,
      );
      if (path != null) {
        setState(() => _localPath = path);
        _requestVisibleTiles(settled: true);
        return;
      }
      if (refreshed is FileImage && File(refreshed.file.path).existsSync()) {
        setState(() => _localPath = refreshed.file.path);
        _requestVisibleTiles(settled: true);
      } else {
        setState(() => _loadFailed = true);
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (generation == _loadGeneration) _resolvingOriginal = false;
    }
  }

  void _retry() {
    setState(() {
      _epoch++;
      _loadFailed = false;
      _unsupported = false;
    });
    _ensureLocalOriginal();
  }

  // Original resolution becomes available asynchronously. Rendering schedules
  // work after layout, so notifications never call setState during a build.
  Future<void> _requestVisibleTiles({required bool settled}) async {
    if (mounted) setState(() {});
  }

  void _scheduleDecode() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pumpScheduled = false;
      if (mounted) _drain();
    });
  }

  void _drain() {
    final grid = _grid;
    final decode = ImageRegionDecodeHook.decode;
    final path = _localPath;
    if (grid == null || path == null || _unsupported) return;
    if (decode == null) {
      setState(() => _unsupported = true);
      return;
    }
    // Two requests globally per viewer, including stale requests. Each output
    // is <=512x512, and only the bounded current visible set is retained.
    for (final index in _wanted) {
      if (_inFlight.length >= 2) break;
      final ticket = (_epoch, index);
      if (_tiles.containsKey(index) || _inFlight.contains(ticket)) continue;
      _inFlight.add(ticket);
      unawaited(_decodeRegion(ticket, grid, decode, path));
    }
  }

  Future<void> _decodeRegion((int, int) ticket, ImagePreviewRegionGrid grid,
      ImageRegionDecodeFn decode, String path) async {
    final src = grid.sourceRect(ticket.$2);
    final dst = grid.decodeSize(ticket.$2);
    ui.Image? result;
    var timedOut = false;
    try {
      final pending = decode(ImageRegionDecodeRequest(
          path: path,
          srcLeft: src.left.toInt(),
          srcTop: src.top.toInt(),
          srcWidth: src.width.toInt(),
          srcHeight: src.height.toInt(),
          dstWidth: dst.width.toInt(),
          dstHeight: dst.height.toInt()));
      result = await pending.then((image) {
        // A timed-out native decode can still finish; do not leak its image.
        if (timedOut) {
          image?.dispose();
          return null;
        }
        return image;
      }).timeout(const Duration(seconds: 20), onTimeout: () {
        timedOut = true;
        throw TimeoutException('Image region decode timed out');
      });
      if (!mounted || ticket.$1 != _epoch || !_wanted.contains(ticket.$2)) {
        result?.dispose();
      } else if (result == null) {
        setState(() => _unsupported = true);
      } else if (result.width * result.height >
          ImagePreviewRegionGrid.tileSide * ImagePreviewRegionGrid.tileSide) {
        result.dispose();
        setState(() => _unsupported = true);
      } else {
        final image = result;
        setState(() {
          _tiles.remove(ticket.$2)?.dispose();
          _tiles[ticket.$2] = image;
        });
      }
    } catch (_) {
      if (mounted && ticket.$1 == _epoch) {
        setState(() => _unsupported = true);
      }
    } finally {
      _inFlight.remove(ticket);
      if (mounted) _drain();
    }
  }

  void _setTransform(double scale, Offset translation) {
    double clampAxis(double value, double content, double viewport, bool top) {
      final extent = content * scale;
      if (extent <= viewport) return top ? 0 : (viewport - extent) / 2;
      return value.clamp(viewport - extent, 0.0);
    }

    _controller.value = Matrix4.identity()
      ..translateByDouble(
          clampAxis(translation.dx, _display.width, _viewport.width, false),
          clampAxis(
              translation.dy, _display.height, _viewport.height, _topAligned),
          0,
          1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _syncLayout(Size viewport, Size display, bool topAligned) {
    if (viewport == _viewport &&
        display == _display &&
        topAligned == _topAligned) {
      return;
    }
    final oldDisplay = _display;
    final scale = _scale;
    final oldCenter =
        _controller.toScene(Offset(_viewport.width / 2, _viewport.height / 2));
    final wasAtTop = _controller.value.getTranslation().y >= -0.5;
    _viewport = viewport;
    _display = display;
    _topAligned = topAligned;
    final center = oldDisplay.isEmpty
        ? Offset(display.width / 2, viewport.height / 2)
        : Offset(oldCenter.dx / oldDisplay.width * display.width,
            oldCenter.dy / oldDisplay.height * display.height);
    _setTransform(
        scale,
        Offset(
            viewport.width / 2 - center.dx * scale,
            wasAtTop && topAligned
                ? 0
                : viewport.height / 2 - center.dy * scale));
  }

  void _updateGate() {
    final tx = _controller.value.getTranslation().x;
    final width = _display.width * _scale;
    widget.galleryScrollGate?.value = TallImageGalleryScrollGate(
        scale: _scale,
        atLeftEdge: tx <= math.min(0.0, _viewport.width - width) + 1,
        atRightEdge: tx >= -1,
        hasHorizontalScroll: width > _viewport.width + 1);
  }

  void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointers.add(event.pointer);
      _pointerDelta = Offset.zero;
      _dismissPending = false;
      if (_pointers.length > 1 && _routingPage) {
        _pageView?.onDragCancel();
        setState(() => _routingPage = false);
      }
      if (_pointers.length == 1) {
        _pageFrozen = null;
        _velocity = VelocityTracker.withKind(event.kind);
        _updateGate();
        final tx = _controller.value.getTranslation().x;
        _startedAtLeft =
            tx <= math.min(0.0, _viewport.width - _display.width * _scale) + 1;
        _startedAtRight = tx >= -1;
      }
    } else if (event is PointerMoveEvent && _pointers.length == 1) {
      _pointerDelta += event.delta;
      _velocity?.addPosition(event.timeStamp, event.position);
      if (widget.inPageView &&
          !_routingPage &&
          _pointerDelta.dx.abs() > 20 &&
          _pointerDelta.dx.abs() > _pointerDelta.dy.abs() * 1.5 &&
          (_pointerDelta.dx < 0 ? _startedAtLeft : _startedAtRight)) {
        _pageView = context
            .findAncestorStateOfType<ExtendedImageGesturePageViewState>();
        if (_pageView != null) {
          _pageFrozen = Matrix4.copy(_controller.value);
          setState(() => _routingPage = true);
          _pageView!
              .onDragDown(DragDownDetails(globalPosition: event.position));
          _pageView!
              .onDragStart(DragStartDetails(globalPosition: event.position));
        }
      }
      if (_routingPage) {
        _controller.value = _pageFrozen!;
        _pageView!.onDragUpdate(DragUpdateDetails(
            globalPosition: event.position,
            delta: Offset(event.delta.dx, 0),
            primaryDelta: event.delta.dx));
        return;
      }
      _dismissPending = _scale <= 1.05 &&
          _controller.value.getTranslation().y >= -0.5 &&
          _pointerDelta.dy > 60 &&
          _pointerDelta.dy > _pointerDelta.dx.abs() * 1.5;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      if (_routingPage) {
        if (event is PointerCancelEvent) {
          _pageView?.onDragCancel();
        } else {
          final velocity = _velocity?.getVelocity() ?? Velocity.zero;
          _pageView?.onDragEnd(DragEndDetails(
              velocity: velocity,
              primaryVelocity: velocity.pixelsPerSecond.dx));
        }
        setState(() => _routingPage = false);
        _dismissPending = false;
        return;
      }
      if (event is PointerUpEvent && _pointers.isEmpty && _dismissPending) {
        widget.onSlideDismiss?.call(_pointerDelta);
      }
      _dismissPending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      _buildPreview(context),
      if (_loadFailed || _unsupported)
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Material(
              color: Colors.black87,
              child: TextButton(
                onPressed: _retry,
                child: const Text('原图加载失败，点击重试',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        )
      else if (_tiles.isEmpty)
        const IgnorePointer(
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
    ]);
  }

  Widget _buildPreview(BuildContext context) {
    if (_unsupported) {
      return ColoredBox(
          color: Colors.black,
          child: widget.placeholder == null
              ? const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54))
              : InteractivePreviewFallback(
                  image: widget.placeholder!,
                  onTap: widget.onTap,
                  sourcePixelSize: Size(widget.imageWidth.toDouble(),
                      widget.imageHeight.toDouble()),
                  fitTallImagesToScreenWidth:
                      widget.fitTallImagesToScreenWidth));
    }
    return LayoutBuilder(builder: (context, bounds) {
      final viewport = bounds.biggest;
      final config = imagePreviewDisplayConfig(
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          screenWidth: viewport.width,
          screenHeight: viewport.height,
          fitTallImagesToScreenWidth: widget.fitTallImagesToScreenWidth);
      final display = imagePreviewInitialDisplaySize(
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          screenWidth: viewport.width,
          screenHeight: viewport.height,
          fit: config.fit);
      _syncLayout(viewport, display, config.verticallyScrollable);
      return ColoredBox(
          color: Colors.black,
          child: Listener(
            onPointerDown: _handlePointer,
            onPointerMove: _handlePointer,
            onPointerUp: _handlePointer,
            onPointerCancel: _handlePointer,
            child: GestureDetector(
              onTap: widget.onTap,
              onDoubleTapDown: (d) => _doubleTap = d.localPosition,
              onDoubleTap: () {
                final next = _scale > 1.05
                    ? 1.0
                    : imagePreviewDoubleTapScale(
                        imageWidth: widget.imageWidth,
                        imageHeight: widget.imageHeight,
                        screenWidth: viewport.width,
                        screenHeight: viewport.height,
                        display: config);
                final point = _controller.toScene(_doubleTap);
                _setTransform(next, _doubleTap - point * next);
                _updateGate();
              },
              child: InteractiveViewer.builder(
                transformationController: _controller,
                alignment: Alignment.topLeft,
                boundaryMargin: EdgeInsets.zero,
                panEnabled: !_routingPage,
                scaleEnabled: !_routingPage,
                minScale: 1,
                maxScale: imagePreviewMaxScale(
                    imageWidth: widget.imageWidth,
                    imageHeight: widget.imageHeight,
                    screenWidth: viewport.width,
                    screenHeight: viewport.height,
                    fit: config.fit),
                onInteractionUpdate: (_) {
                  if (_routingPage && _pageFrozen != null) {
                    _controller.value = _pageFrozen!;
                  }
                  _updateGate();
                },
                onInteractionEnd: (_) => _updateGate(),
                builder: (context, quad) {
                  final grid = ImagePreviewRegionGrid(
                      source: Size(widget.imageWidth.toDouble(),
                          widget.imageHeight.toDouble()),
                      display: display,
                      pixelRatio: MediaQuery.devicePixelRatioOf(context),
                      zoom: _scale);
                  if (grid.signature != _grid?.signature) {
                    _epoch++;
                    for (final image in _tiles.values) {
                      image.dispose();
                    }
                    _tiles.clear();
                  }
                  _grid = grid;
                  final points = [
                    quad.point0,
                    quad.point1,
                    quad.point2,
                    quad.point3
                  ];
                  final visible = Rect.fromLTRB(
                      points.map((p) => p.x).reduce(math.min),
                      points.map((p) => p.y).reduce(math.min),
                      points.map((p) => p.x).reduce(math.max),
                      points.map((p) => p.y).reduce(math.max));
                  _wanted = grid.visible(visible, limit: _tileLimit);
                  for (final index in _tiles.keys.toList()) {
                    if (!_wanted.contains(index)) {
                      _tiles.remove(index)?.dispose();
                    }
                  }
                  _scheduleDecode();
                  return SizedBox(
                      width: display.width,
                      height: display.height,
                      child: Stack(children: [
                        if (widget.placeholder != null)
                          Positioned.fill(
                              child: Image(
                                  image: widget.placeholder!,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                  fit: BoxFit.fill)),
                        for (final index in _wanted)
                          if (_tiles[index] case final ui.Image image)
                            Positioned.fromRect(
                                rect: grid.displayRect(index),
                                child: RawImage(
                                    image: image,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.low)),
                      ]));
                },
              ),
            ),
          ));
    });
  }
}
