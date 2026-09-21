import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_preview_image_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_tile_geometry.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_region_decode_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/tall_image_gallery_scroll_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tall_image_scroll_preview.dart';

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
  });

  final int imageWidth;
  final int imageHeight;
  final V2TimMessage? message;
  final ImageProvider? placeholder;
  final VoidCallback? onTap;
  final bool inPageView;
  final ValueNotifier<TallImageGalleryScrollGate>? galleryScrollGate;
  final TallImageSlideDismissCallback? onSlideDismiss;

  @override
  State<TiledImagePreview> createState() => _TiledImagePreviewState();
}

class _TiledImagePreviewState extends State<TiledImagePreview> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, ui.Image> _tiles = <int, ui.Image>{};
  final Map<int, int> _generation = <int, int>{};
  String? _localPath;
  bool _resolvingOriginal = false;
  bool _unsupported = false;
  double _scale = 1.0;
  double _scaleBase = 1.0;
  int _decodeGeneration = 0;
  Timer? _settleTimer;
  Offset _pointerDelta = Offset.zero;
  TallImageGestureAxis _axis = TallImageGestureAxis.undecided;

  bool get _desktop => PlatformUtils().isWinMacDesktop;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _ensureLocalOriginal();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _decodeGeneration++;
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
    super.dispose();
  }

  ImagePreviewTileGeometry _geometryOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ImagePreviewTileGeometry.from(
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      screenWidth: mq.size.width,
      screenHeight: mq.size.height,
      devicePixelRatio: mq.devicePixelRatio,
      scale: _scale,
    );
  }

  Future<void> _ensureLocalOriginal() async {
    final message = widget.message;
    if (message == null) {
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
    try {
      final refreshed =
          await ChatMessagePreviewImageResolver.refreshOriginal(message);
      if (!mounted) {
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
      }
    } finally {
      _resolvingOriginal = false;
    }
  }

  void _onScroll() {
    widget.galleryScrollGate?.value = TallImageGalleryScrollGate(
      scale: _scale,
      atLeftEdge: true,
      atRightEdge: true,
      hasHorizontalScroll: false,
    );
    _requestVisibleTiles(settled: false);
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        _requestVisibleTiles(settled: true);
      }
    });
  }

  int _budgetPixels() => _desktop ? 24 * 1000 * 1000 : 12 * 1000 * 1000;

  Future<void> _requestVisibleTiles({required bool settled}) async {
    final path = _localPath;
    final decode = ImageRegionDecodeHook.decode;
    if (path == null || decode == null || !mounted) {
      if (decode == null && path != null && mounted) {
        setState(() => _unsupported = true);
      }
      return;
    }
    final geometry = _geometryOf(context);
    final center = geometry.visibleTileIndex(_scrollController.hasClients
        ? _scrollController.offset
        : 0);
    final radius = settled
        ? geometry.prefetchRadius(desktop: _desktop)
        : 0;
    final wanted = <int>{};
    for (var i = center - radius; i <= center + radius; i++) {
      if (i >= 0 && i < geometry.tileCount) {
        wanted.add(i);
      }
    }
    _evictFarTiles(center, geometry);
    for (final index in wanted) {
      unawaited(_decodeTile(index, geometry, decode, path));
    }
  }

  void _evictFarTiles(int center, ImagePreviewTileGeometry geometry) {
    final maxTiles = geometry.maxCachedTiles(desktop: _desktop);
    final keep = geometry.prefetchRadius(desktop: _desktop);
    final stale = _tiles.keys
        .where((index) => (index - center).abs() > keep)
        .toList()
      ..sort(
        (a, b) => (b - center).abs().compareTo((a - center).abs()),
      );
    var pixels = 0;
    for (final image in _tiles.values) {
      pixels += image.width * image.height;
    }
    while ((_tiles.length > maxTiles || pixels > _budgetPixels()) &&
        stale.isNotEmpty) {
      final index = stale.removeLast();
      final image = _tiles.remove(index);
      if (image != null) {
        pixels -= image.width * image.height;
        image.dispose();
      }
    }
  }

  Future<void> _decodeTile(
    int index,
    ImagePreviewTileGeometry geometry,
    ImageRegionDecodeFn decode,
    String path,
  ) async {
    if (_tiles.containsKey(index)) {
      return;
    }
    final generation = ++_decodeGeneration;
    _generation[index] = generation;
    final src = geometry.srcRectFor(index);
    final request = ImageRegionDecodeRequest(
      path: path,
      srcLeft: src.left.round(),
      srcTop: src.top.round(),
      srcWidth: src.width.round(),
      srcHeight: src.height.round(),
      dstWidth: geometry.dstWidth,
      dstHeight: geometry.dstHeightFor(index),
    );
    try {
      final image = await decode(request);
      if (!mounted || _generation[index] != generation) {
        image?.dispose();
        return;
      }
      if (image == null) {
        setState(() => _unsupported = true);
        return;
      }
      setState(() => _tiles[index] = image);
    } catch (_) {
      if (mounted) {
        setState(() => _unsupported = true);
      }
    }
  }

  void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointerDelta = Offset.zero;
      _axis = TallImageGestureAxis.undecided;
      return;
    }
    if (event is! PointerMoveEvent) {
      return;
    }
    _pointerDelta += event.delta;
    _axis = resolveTallImageScrollAxis(totalDelta: _pointerDelta);
    final gate = widget.galleryScrollGate;
    if (gate != null) {
      final horizontal = widget.inPageView &&
          tallImageShouldRouteGalleryPage(
            totalDelta: _pointerDelta,
            atHorizontalEdge: true,
            zoomed: _scale > 1.05,
          );
      gate.value = TallImageGalleryScrollGate(
        scale: _scale,
        atLeftEdge: horizontal && _pointerDelta.dx > 0,
        atRightEdge: horizontal && _pointerDelta.dx < 0,
        hasHorizontalScroll: horizontal,
      );
    }
    final atEdge = !_scrollController.hasClients
        ? true
        : (_scrollController.offset <= 0 && event.delta.dy > 0);
    if (atEdge &&
        _axis == TallImageGestureAxis.vertical &&
        _pointerDelta.dy > 24 &&
        _scale <= 1.05) {
      widget.onSlideDismiss?.call(_pointerDelta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometryOf(context);
    final screen = MediaQuery.sizeOf(context);
    Widget body;
    if (_unsupported) {
      body = _placeholderLayer(screen);
    } else {
      body = Listener(
        onPointerDown: _handlePointer,
        onPointerMove: _handlePointer,
        child: GestureDetector(
          onTap: widget.onTap,
          onScaleStart: (_) => _scaleBase = _scale,
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) {
              return;
            }
            final maxScale = imagePreviewMaxScale(
              imageWidth: widget.imageWidth,
              imageHeight: widget.imageHeight,
              screenWidth: screen.width,
              screenHeight: screen.height,
            );
            final next = (_scaleBase * details.scale).clamp(1.0, maxScale);
            if ((next - _scale).abs() < 0.01) {
              return;
            }
            for (final image in _tiles.values) {
              image.dispose();
            }
            _tiles.clear();
            setState(() => _scale = next);
            _requestVisibleTiles(settled: true);
          },
          child: SizedBox(
            width: screen.width,
            height: screen.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _placeholderLayer(screen),
                ListView.builder(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  itemCount: geometry.tileCount,
                  itemBuilder: (context, index) {
                    final tile = _tiles[index];
                    final height = geometry.tileLogicalHeight(index);
                    if (tile == null) {
                      return SizedBox(
                        width: screen.width,
                        height: height,
                      );
                    }
                    return RawImage(
                      image: tile,
                      width: screen.width,
                      height: height,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.low,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ColoredBox(color: Colors.black, child: body);
  }

  Widget _placeholderLayer(Size screen) {
    if (widget.placeholder != null) {
      return Image(
        image: widget.placeholder!,
        width: screen.width,
        height: screen.height,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}
