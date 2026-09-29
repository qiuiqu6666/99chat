import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_preview_image_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_edit/image_preview_edit_store.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_preview_resolution_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/progressive_image_decode_budget.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/gestured_image.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_hero.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_preview_center_loading_indicator.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_backdrop_scope.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/tall_image_gallery_scroll_gate.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tall_image_scroll_preview.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tiled_image_preview.dart';

typedef DoubleClickAnimationListener = void Function();

/// 混滑画廊单页图片：缩略图落位后原位切换原图，并支持长图竖滑。
class ChatMediaGalleryImagePage extends StatefulWidget {
  const ChatMediaGalleryImagePage({
    super.key,
    required this.item,
    required this.inPageView,
    required this.isActive,
    required this.allowHero,
    required this.entranceSettled,
    required this.isGalleryScrolling,
    required this.slidePageKey,
    required this.slideMetrics,
    required this.onTap,
    this.onSlideDismiss,
    this.onDismissGestureStarted,
    this.galleryScrollGate,
  });

  final ChatMediaPreviewItem item;
  final bool inPageView;
  final bool isActive;
  final bool allowHero;
  final bool entranceSettled;
  final bool isGalleryScrolling;
  final GlobalKey<ExtendedImageSlidePageState> slidePageKey;
  final MediaPreviewSlideMetrics slideMetrics;
  final VoidCallback onTap;
  final TallImageSlideDismissCallback? onSlideDismiss;
  /// 长图进入竖向关闭手势时通知图集钉住当前页。
  final VoidCallback? onDismissGestureStarted;
  final ValueNotifier<TallImageGalleryScrollGate>? galleryScrollGate;

  @override
  State<ChatMediaGalleryImagePage> createState() =>
      _ChatMediaGalleryImagePageState();
}

class _ChatMediaGalleryImagePageState extends State<ChatMediaGalleryImagePage>
    with TickerProviderStateMixin {
  final GlobalKey<ExtendedImageGestureState> _gestureKey =
      GlobalKey<ExtendedImageGestureState>();
  Animation<double>? _doubleClickAnimation;
  late DoubleClickAnimationListener _doubleClickAnimationListener;
  late AnimationController _doubleClickAnimationController;
  List<double> _doubleTapScales = <double>[1.0, 2.0];

  ImageProvider? _refreshedProvider;
  late bool _previewImageReady;
  ImagePreviewDisplayConfig? _loadedDisplay;
  // Lock the Hero flight box size on first build so ORIGIN decode doesn't
  // shift the dismiss Hero landing rect (visible "jump" on close).
  Size? _heroLockedBoxSize;
  bool _originalUpgradeCompleted = false;
  bool _lowResolutionRefreshAttempted = false;
  bool _lowResolutionRefreshInFlight = false;
  bool _pendingOriginalRefresh = false;

  @override
  void initState() {
    super.initState();
    _previewImageReady = widget.entranceSettled;
    _doubleClickAnimationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(ChatMediaGalleryImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_previewImageReady && widget.entranceSettled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.entranceSettled) return;
        setState(() => _previewImageReady = true);
        _scheduleOriginalRefreshIfNeeded();
      });
    }
    final becameActive = !oldWidget.isActive && widget.isActive;
    final scrollSettled =
        oldWidget.isGalleryScrolling && !widget.isGalleryScrolling;
    if (widget.isActive &&
        !widget.isGalleryScrolling &&
        (becameActive || scrollSettled || _pendingOriginalRefresh)) {
      _scheduleOriginalRefreshIfNeeded();
    }
  }

  @override
  void dispose() {
    _doubleClickAnimationController.dispose();
    super.dispose();
  }

  void _completeOriginalUpgrade(ImageProvider originalProvider) {
    _originalUpgradeCompleted = true;
    _refreshedProvider = originalProvider;
  }

  /// Wraps the original image provider with a ResizeImage guard if the
  /// image dimensions exceed [ProgressiveImageDecodeBudget.maxDecodePx].
  /// This prevents OOM on low-end devices for 20MB+ images by capping
  /// the decoded pixel count — mirroring QQ's tile-loading strategy.
  ImageProvider _applyOomGuard(
    ImageProvider original,
    ImagePreviewDisplayConfig display,
  ) {
    // Check if we know the original dimensions.
    final msg = widget.item.message;
    final imageElem = msg.imageElem;
    V2TimImage? originalImage;
    for (final img in imageElem?.imageList ?? const <V2TimImage?>[]) {
      if (img?.type == 0 && img!.width != null && img.width! > 0) {
        originalImage = img;
        break;
      }
    }
    final origWidth = originalImage?.width;
    final origHeight = originalImage?.height;
    if (!ProgressiveImageDecodeBudget.needsProgressiveDecode(
        origWidth, origHeight)) {
      return original;
    }
    // Large image: wrap with ResizeImage to cap decode at maxDecodePx.
    final screenWidthPx = ProgressiveImageDecodeBudget.previewCacheWidth(
      MediaQuery.sizeOf(context).width,
      MediaQuery.devicePixelRatioOf(context),
    );
    final dims = ProgressiveImageDecodeBudget.safeDecodeDimensions(
      zoomLevel: 1.0,
      originalWidth: origWidth,
      originalHeight: origHeight,
      screenWidthPx: screenWidthPx,
    );
    if (dims.cacheWidth == null && dims.cacheHeight == null) {
      return original;
    }
    return ResizeImage(
      original,
      width: dims.cacheWidth,
      height: dims.cacheHeight,
    );
  }

  Future<void> _precachePreviewImage(ImageProvider provider) async {
    final config = createLocalImageConfiguration(context);
    final stream = provider.resolve(config);
    final completer = Completer<void>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, sync) {
        image.dispose();
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    await completer.future;
  }

  Future<ImageProvider?> _precacheOriginalOrDownload({
    required V2TimMessage message,
    required ImageProvider originalProvider,
    required ImagePreviewDisplayConfig display,
  }) async {
    var candidate = _applyOomGuard(originalProvider, display);
    try {
      await _precachePreviewImage(candidate);
      return candidate;
    } catch (_) {}
    if (!mounted) {
      return null;
    }
    final downloaded = await ChatMessagePreviewImageResolver.refreshOriginal(
      message,
      forceDownload: true,
    );
    if (downloaded == null ||
        ChatMessagePreviewImageResolver.isSameImageProvider(
          downloaded,
          originalProvider,
        )) {
      return null;
    }
    candidate = _applyOomGuard(downloaded, display);
    try {
      await _precachePreviewImage(candidate);
      return candidate;
    } catch (_) {
      return null;
    }
  }

  ImageProvider? _resolveImageProvider({bool preferFullResolution = false}) {
    final messageId = widget.item.messageID?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      final edited = ImagePreviewEditStore.instance.peek(messageId);
      if (edited != null && edited.existsSync()) {
        return FileImage(edited);
      }
    }
    if (!_previewImageReady) {
      final thumbnail = _placeholderForItem();
      if (thumbnail != null) return thumbnail;
    }
    final primary = _refreshedProvider ?? widget.item.imageProvider;
    if (primary == null) {
      return null;
    }
    final preferFull = preferFullResolution ||
        _originalUpgradeCompleted ||
        ChatMessagePreviewImageResolver.isOriginTierProvider(
          primary,
          widget.item.message,
        );
    // The full provider is resolved only after the thumbnail has landed.
    return ChatMessagePreviewImageResolver.wrapPreviewDecode(
      context: context,
      message: widget.item.message,
      provider: primary,
      preferFullResolution: preferFull,
    );
  }

  ImageProvider? _placeholderForItem() {
    final existing = widget.item.placeholderImageProvider;
    if (existing != null) {
      return existing;
    }
    if (widget.item.message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      return null;
    }
    return ChatMessagePreviewImageResolver.resolvePlaceholder(
      widget.item.message,
    );
  }

  Future<void> _replaceWithDecodedOriginal({
    required ImageProvider originalProvider,
    required ImagePreviewDisplayConfig display,
  }) async {
    if (!mounted || !widget.isActive) {
      return;
    }
    if (widget.isGalleryScrolling) {
      _pendingOriginalRefresh = true;
      return;
    }
    final decoded = await _precacheOriginalOrDownload(
      message: widget.item.message,
      originalProvider: originalProvider,
      display: display,
    );
    if (decoded == null) {
      // 原图预解码失败时保留当前已显示的大图，避免换成坏 provider 导致全屏灰。
      if (mounted) {
        _lowResolutionRefreshAttempted = true;
      }
      return;
    }

    if (!mounted ||
        _originalUpgradeCompleted ||
        !widget.isActive ||
        widget.isGalleryScrolling) {
      if (widget.isGalleryScrolling || !widget.isActive) {
        _pendingOriginalRefresh = true;
      }
      return;
    }

    setState(() => _completeOriginalUpgrade(decoded));
  }

  void _scheduleOriginalRefreshIfNeeded({
    int? loadedImageWidth,
    int? loadedImageHeight,
  }) {
    if (imagePreviewRequiresTileRendererForMessage(widget.item.message)) {
      return;
    }
    if (!_previewImageReady || !widget.isActive) {
      return;
    }
    if (widget.isGalleryScrolling) {
      _pendingOriginalRefresh = true;
      return;
    }
    if (_lowResolutionRefreshAttempted ||
        _lowResolutionRefreshInFlight ||
        _originalUpgradeCompleted) {
      return;
    }
    final message = widget.item.message;
    if (message.elemType != MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
      return;
    }
    final currentProvider = _refreshedProvider ?? widget.item.imageProvider;
    var needsUpgrade = ChatMessagePreviewImageResolver.shouldUpgradeToOriginal(
      message,
      currentProvider,
    );
    if (!needsUpgrade &&
        loadedImageWidth != null &&
        loadedImageHeight != null &&
        loadedImageWidth > 0 &&
        loadedImageHeight > 0) {
      needsUpgrade = isImagePreviewResolutionTooLow(
        imageWidth: loadedImageWidth,
        imageHeight: loadedImageHeight,
        context: context,
      );
    }
    if (!needsUpgrade) {
      _lowResolutionRefreshAttempted = true;
      _pendingOriginalRefresh = false;
      return;
    }

    Future<void> runRefresh() async {
      if (!mounted ||
          !widget.isActive ||
          _lowResolutionRefreshAttempted ||
          _lowResolutionRefreshInFlight ||
          _originalUpgradeCompleted) {
        return;
      }
      _lowResolutionRefreshInFlight = true;
      _pendingOriginalRefresh = false;
      try {
        final originalProvider =
            await ChatMessagePreviewImageResolver.refreshOriginal(message);
        if (!mounted || originalProvider == null) {
          if (mounted) {
            _lowResolutionRefreshAttempted = true;
          }
          return;
        }
        if (ChatMessagePreviewImageResolver.isSameImageProvider(
          originalProvider,
          currentProvider,
        )) {
          _lowResolutionRefreshAttempted = true;
          return;
        }
        _lowResolutionRefreshAttempted = true;
        // OOM guard: if the original image is very large (>40MP), wrap it
        // with ResizeImage to cap the decoded pixel count. This mirrors
        // QQ's tile-loading approach — never decode the full bitmap.
        final display = _loadedDisplay ??
            imagePreviewDisplayConfigForItem(
              sourceMessage: message,
              screenWidth: MediaQuery.sizeOf(context).width,
              screenHeight: MediaQuery.sizeOf(context).height,
            );
        if (display.verticallyScrollable) {
          if (!mounted || !widget.isActive || widget.isGalleryScrolling) {
            _pendingOriginalRefresh = true;
            return;
          }
          final decoded = await _precacheOriginalOrDownload(
            message: message,
            originalProvider: originalProvider,
            display: display,
          );
          if (decoded == null) {
            if (mounted) {
              _lowResolutionRefreshAttempted = true;
            }
            return;
          }
          if (!mounted || !widget.isActive) {
            return;
          }
          setState(() => _completeOriginalUpgrade(decoded));
          return;
        }
        await _replaceWithDecodedOriginal(
          originalProvider: originalProvider,
          display: display,
        );
      } finally {
        if (mounted) {
          _lowResolutionRefreshInFlight = false;
        }
      }
    }

    if (widget.entranceSettled) {
      unawaited(runRefresh());
      return;
    }
    Future<void>.delayed(mediaPreviewBackdropDuration, () {
      if (mounted) {
        unawaited(runRefresh());
      }
    });
  }

  void _onDoubleTap(ExtendedImageGestureState state) {
    final pointerDownPosition = state.pointerDownPosition;
    final begin = state.gestureDetails!.totalScale;
    final end = begin == _doubleTapScales[0]
        ? _doubleTapScales[1]
        : _doubleTapScales[0];

    _doubleClickAnimation?.removeListener(_doubleClickAnimationListener);
    _doubleClickAnimationController
      ..stop()
      ..reset();

    _doubleClickAnimationListener = () {
      state.handleDoubleTap(
        scale: _doubleClickAnimation!.value,
        doubleTapPosition: pointerDownPosition,
      );
    };
    _doubleClickAnimation = _doubleClickAnimationController.drive(
      Tween<double>(begin: begin, end: end),
    );
    _doubleClickAnimation!.addListener(_doubleClickAnimationListener);
    _doubleClickAnimationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ImagePreviewEditStore.instance.revision,
      builder: (context, revision, _) {
        return _buildBody(context, revision);
      },
    );
  }

  Widget _buildBody(BuildContext context, int revision) {
    final screenSize = MediaQuery.sizeOf(context);
    final display = _loadedDisplay ??
        imagePreviewDisplayConfigResolved(
          sourceMessage: widget.item.message,
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
        );
    if (imagePreviewRequiresTileRendererForMessage(widget.item.message) &&
        display.imageWidth > 0 &&
        display.imageHeight > 0) {
      return TiledImagePreview(
        imageWidth: display.imageWidth,
        imageHeight: display.imageHeight,
        message: widget.item.message,
        placeholder: _placeholderForItem(),
        onTap: widget.onTap,
        inPageView: widget.inPageView,
        galleryScrollGate: widget.galleryScrollGate,
        onSlideDismiss: widget.onSlideDismiss,
      );
    }
    final imageProvider = _resolveImageProvider();
    if (imageProvider == null) {
      return ColoredBox(
        color: MediaPreviewBackdropScope.of(context),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
        ),
      );
    }
    final trustDecodedSize = _previewImageReady &&
        (_originalUpgradeCompleted ||
            ChatMessagePreviewImageResolver.isOriginTierProvider(
              _refreshedProvider ?? widget.item.imageProvider,
              widget.item.message,
            ));

    final boxSize = imagePreviewBoxSizeFor(
      display: display,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
    );
    final heroBoxSize = _heroLockedBoxSize ??= boxSize;
    final imageFit = imagePreviewPaintFit(display);

    Widget image = ExtendedImage(
      key: ValueKey<String>(
        'mixed_preview_${widget.item.messageID ?? widget.item.heroTag}_$revision',
      ),
      image: imageProvider,
      // Zoom painting is clipped to this canvas, so it must span the viewport.
      // The initial image rectangle is retained separately for Hero flights.
      width: screenSize.width,
      height: screenSize.height,
      fit: imageFit,
      alignment: display.alignment,
      gaplessPlayback: true,
      filterQuality: PlatformUtils().isWinMacDesktop
          ? FilterQuality.medium
          : FilterQuality.low,
      enableLoadState: true,
      extendedImageGestureKey: _gestureKey,
      enableSlideOutPage: true,
      mode: ExtendedImageMode.gesture,
      initGestureConfigHandler: (state) {
        final info = state.extendedImageInfo;
        final resolved = imagePreviewDisplayConfigResolved(
          sourceMessage: widget.item.message,
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
          decodedWidth: info?.image.width ?? 0,
          decodedHeight: info?.image.height ?? 0,
          trustDecodedSize: trustDecodedSize,
        );
        final maxScale = imagePreviewMaxScale(
          imageWidth: resolved.imageWidth,
          imageHeight: resolved.imageHeight,
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
          fit: resolved.fit,
        );
        return buildImagePreviewGestureConfig(
          inPageView: widget.inPageView,
          display: resolved,
          maxScale: maxScale,
        );
      },
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return ImagePreviewLoadingLayer(
              placeholder: _placeholderForItem(),
              fit: imagePreviewPaintFit(display),
              alignment: display.alignment,
              showSpinner: widget.entranceSettled,
            );
          case LoadState.completed:
            final imgHeight = state.extendedImageInfo?.image.height ?? 1;
            final imgWidth = state.extendedImageInfo?.image.width ?? 1;
            final builtDisplay = _loadedDisplay ??
                imagePreviewDisplayConfigResolved(
                  sourceMessage: widget.item.message,
                  screenWidth: screenSize.width,
                  screenHeight: screenSize.height,
                );
            final resolved = imagePreviewDisplayConfigResolved(
              sourceMessage: widget.item.message,
              screenWidth: screenSize.width,
              screenHeight: screenSize.height,
              decodedWidth: imgWidth,
              decodedHeight: imgHeight,
              trustDecodedSize: trustDecodedSize,
            );
            final doubleTapTarget = imagePreviewDoubleTapScale(
              imageWidth: resolved.imageWidth,
              imageHeight: resolved.imageHeight,
              screenWidth: screenSize.width,
              screenHeight: screenSize.height,
              display: resolved,
            );
            final panScale = imagePreviewInitialScale(
              verticallyScrollable: resolved.verticallyScrollable,
            );
            _doubleTapScales = [panScale, doubleTapTarget];
            _loadedDisplay = resolved;
            if (!builtDisplay.layoutEquals(resolved)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                setState(() {});
              });
            }
            _scheduleOriginalRefreshIfNeeded(
              loadedImageWidth: imgWidth,
              loadedImageHeight: imgHeight,
            );
            // extended_image 在约 1x 时无法可靠纵滑长图，可纵滑内容仍走专用组件。
            if (resolved.verticallyScrollable) {
              final maxScale = imagePreviewMaxScale(
                imageWidth: resolved.imageWidth,
                imageHeight: resolved.imageHeight,
                screenWidth: screenSize.width,
                screenHeight: screenSize.height,
                fit: resolved.fit,
              );
              return SizedBox.expand(
                child: TallImageScrollPreview(
                  extendedImageState: state,
                  maxScale: maxScale,
                  doubleTapTarget: doubleTapTarget,
                  slidePageKey: widget.slidePageKey,
                  slideMetrics: widget.slideMetrics,
                  displayMode: resolved.mode,
                  sourcePixelSize: Size(resolved.imageWidth.toDouble(), resolved.imageHeight.toDouble()),
                  inPageView: widget.inPageView,
                  galleryScrollGate: widget.galleryScrollGate,
                  onTap: widget.onTap,
                  onDismissGestureStarted: widget.onDismissGestureStarted,
                  onSlideDismiss: widget.onSlideDismiss,
                ),
              );
            }
            return GesturedImage(state, key: _gestureKey);
          case LoadState.failed:
            if (_placeholderForItem() != null) {
              return ImagePreviewLoadingLayer(
                placeholder: _placeholderForItem(),
                fit: imagePreviewPaintFit(display),
                alignment: display.alignment,
                showSpinner: false,
                interactive: true,
              );
            }
            return const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            );
        }
      },
      onDoubleTap: _onDoubleTap,
    );

    if (widget.allowHero && widget.item.heroTag.toString().isNotEmpty) {
      image = HeroWidget(
        tag: widget.item.heroTag,
        slidePagekey: widget.slidePageKey,
        animateCornerRadius: true,
        cornerRadius: 10,
        child: image,
      );
    }

    image = MediaPreviewHeroLayout(
      displaySize: heroBoxSize,
      alignment: display.alignment,
      child: SizedBox.expand(child: image),
    );

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.deferToChild,
      child: SizedBox.expand(child: image),
    );
  }
}
