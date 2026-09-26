import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tencent_cloud_chat_demo/src/models/sticker_models.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/app_network_image.dart';
import 'package:tencent_cloud_chat_demo/utils/sticker_media.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 磁盘缓存 key（与聊天图片缩略图区分；同一 sticker 的 GIF/缩略图分别缓存）。
String stickerNetworkImageCacheKey(String stickerId, String url) {
  final id = stickerId.trim();
  final normalized = url.trim();
  if (id.isNotEmpty && normalized.isNotEmpty) {
    return 'sticker:$id:${normalized.hashCode}';
  }
  if (id.isNotEmpty) {
    return 'sticker:$id';
  }
  if (normalized.isNotEmpty) {
    return 'sticker:url:${normalized.hashCode}';
  }
  return 'sticker:unknown';
}

/// 表情缩略图/动图展示；GIF 使用 [originUrl] 以保证动画播放。
class StickerImage extends StatelessWidget {
  const StickerImage({
    super.key,
    required this.item,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.preferAnimated = true,
    this.pauseWhenOffscreen = false,
  });

  StickerImage.url({
    super.key,
    required String url,
    String fallbackUrl = '',
    String mediaType = StickerMediaType.image,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.preferAnimated = true,
    this.pauseWhenOffscreen = false,
  }) : item = _UrlOnlyStickerItem(
          url: url,
          fallbackUrl: fallbackUrl,
          mediaType: mediaType,
        );

  final StickerItem item;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// true：优先 [originUrl] 播放 GIF；false：优先 [thumbUrl] 静态缩略图。
  final bool preferAnimated;

  /// 聊天列表等场景：滚出视口后改用静态缩略图，停止 GIF 解码。
  final bool pauseWhenOffscreen;

  @override
  Widget build(BuildContext context) {
    if (StickerMediaType.isVideoUrl(item.originUrl) ||
        (item.mediaType == StickerMediaType.video &&
            !StickerMediaType.isGifUrl(item.originUrl))) {
      if (!preferAnimated) {
        final thumb = item.thumbUrl.trim();
        if (thumb.isEmpty || StickerMediaType.isVideoUrl(thumb)) {
          return _stickerImagePlaceholder(width: width, height: height);
        }
        return _StickerImageContent(
          item: StickerItem(
            stickerId: item.stickerId,
            thumbUrl: thumb,
            originUrl: thumb,
          ),
          fit: fit,
          width: width,
          height: height,
          preferAnimated: false,
        );
      }
      return _StickerVideoContent(
        item: item,
        fit: fit,
        width: width,
        height: height,
        pauseWhenOffscreen: pauseWhenOffscreen,
      );
    }
    if (pauseWhenOffscreen && item.isAnimated) {
      return _StickerImageVisibilityGate(
        item: item,
        fit: fit,
        width: width,
        height: height,
        preferAnimated: preferAnimated,
      );
    }
    return _StickerImageContent(
      item: item,
      fit: fit,
      width: width,
      height: height,
      preferAnimated: preferAnimated,
    );
  }
}

/// Keep the already cached thumbnail visible while the video opens and decodes.
class _StickerVideoContent extends StatefulWidget {
  const _StickerVideoContent({
    required this.item,
    required this.fit,
    required this.width,
    required this.height,
    required this.pauseWhenOffscreen,
  });

  final StickerItem item;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool pauseWhenOffscreen;

  @override
  State<_StickerVideoContent> createState() => _StickerVideoContentState();
}

class _StickerVideoContentState extends State<_StickerVideoContent> {
  Player? _player;
  VideoController? _controller;
  bool _firstFrameReady = false;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible = !widget.pauseWhenOffscreen;
    if (_visible) _openAfterFirstPaint();
  }

  void _openAfterFirstPaint() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _player == null) unawaited(_openVideo());
    });
  }

  Future<void> _openVideo() async {
    final url = widget.item.originUrl.trim();
    if (url.isEmpty) return;
    Player? openingPlayer;
    try {
      MediaKit.ensureInitialized();
      final player = Player();
      openingPlayer = player;
      final controller = VideoController(player);
      _player = player;
      if (mounted) setState(() => _controller = controller);
      await player.setVolume(0);
      await player.setPlaylistMode(PlaylistMode.single);
      await player.open(Media(url), play: _visible);
      await controller.waitUntilFirstFrameRendered
          .timeout(const Duration(seconds: 30));
      if (!mounted || !identical(_player, player)) return;
      if (!_visible) unawaited(player.pause());
      setState(() => _firstFrameReady = true);
    } catch (_) {
      // A failed video must leave its thumbnail visible.
      if (identical(_player, openingPlayer)) {
        _player = null;
        if (mounted) {
          setState(() => _controller = null);
        } else {
          _controller = null;
        }
      }
      if (openingPlayer != null) unawaited(openingPlayer.dispose());
    }
  }

  @override
  void didUpdateWidget(_StickerVideoContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.originUrl != widget.item.originUrl) {
      final oldPlayer = _player;
      _player = null;
      _controller = null;
      _firstFrameReady = false;
      if (oldPlayer != null) unawaited(oldPlayer.dispose());
      if (_visible) _openAfterFirstPaint();
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = widget.item.thumbUrl.trim();
    final hasImageThumb = thumbUrl.isNotEmpty &&
        !StickerMediaType.isVideoUrl(thumbUrl);
    final thumbnail = hasImageThumb
        ? _StickerImageContent(
            item: StickerItem(
              stickerId: widget.item.stickerId,
              thumbUrl: thumbUrl,
              originUrl: thumbUrl,
            ),
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            preferAnimated: false,
          )
        : _stickerImagePlaceholder(width: widget.width, height: widget.height);
    final video = Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null)
          Video(
            controller: _controller!,
            fit: widget.fit,
            controls: NoVideoControls,
          ),
        if (!_firstFrameReady || _controller == null) thumbnail,
      ],
    );
    if (!widget.pauseWhenOffscreen) return video;
    return VisibilityDetector(
      key: ValueKey('sticker-video:${widget.item.stickerId}:${widget.item.originUrl}'),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.01;
        if (visible == _visible) return;
        _visible = visible;
        final player = _player;
        if (visible && player == null) {
          unawaited(_openVideo());
        } else if (player != null) {
          if (visible) {
            unawaited(player.play());
          } else {
            unawaited(player.pause());
          }
        }
      },
      child: video,
    );
  }
}

class _StickerImageVisibilityGate extends StatefulWidget {
  const _StickerImageVisibilityGate({
    required this.item,
    required this.fit,
    required this.width,
    required this.height,
    required this.preferAnimated,
  });

  final StickerItem item;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool preferAnimated;

  @override
  State<_StickerImageVisibilityGate> createState() =>
      _StickerImageVisibilityGateState();
}

class _StickerImageVisibilityGateState
    extends State<_StickerImageVisibilityGate> {
  static const _visibilityThreshold = 0.01;
  // VisibilityDetector keys are global, whereas the same sticker can occur
  // in several messages. Keep visibility independent from the media cache key.
  final _visibilityKey = UniqueKey();

  /// 乐观默认为可见，保证首屏 GIF 立即播放；屏外项在首次 visibility 回调后暂停。
  bool _isVisible = true;

  @override
  Widget build(BuildContext context) {
    final isCurrentRoute = ModalRoute.isCurrentOf(context) ?? true;
    return VisibilityDetector(
      key: _visibilityKey,
      // A covering preview is not a scroll out of the viewport. Disabling the
      // detector also forgets pending hide callbacks from the covered route.
      // Image retains its last frame while TickerMode pauses the GIF stream.
      onVisibilityChanged: !isCurrentRoute
          ? null
          : (info) {
              final visible = info.visibleFraction > _visibilityThreshold;
              if (visible != _isVisible && mounted) {
                setState(() => _isVisible = visible);
              }
            },
      // URL-only stickers, missing thumbnails and failed thumbnails may all
      // resolve back to the animated origin. Unmount the image while offscreen
      // so ImageState releases its stream listener instead of swapping URLs.
      child: TickerMode(
        enabled: isCurrentRoute,
        child: !_isVisible
            ? _stickerImagePlaceholder(
                width: widget.width, height: widget.height)
            : _StickerImageContent(
                item: widget.item,
                fit: widget.fit,
                width: widget.width,
                height: widget.height,
                preferAnimated: widget.preferAnimated && _isVisible,
              ),
      ),
    );
  }
}

class _StickerImageContent extends StatelessWidget {
  const _StickerImageContent({
    required this.item,
    required this.fit,
    required this.width,
    required this.height,
    required this.preferAnimated,
  });

  final StickerItem item;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool preferAnimated;

  @override
  Widget build(BuildContext context) {
    final url = item.displayUrl(preferAnimated: preferAnimated);
    if (url.isEmpty) {
      return _stickerImagePlaceholder(width: width, height: height);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final decodeWidth =
            stickerDecodePixels(width ?? constraints.maxWidth, dpr);
        final decodeHeight =
            stickerDecodePixels(height ?? constraints.maxHeight, dpr);
        final thumbUrl = item.thumbUrl.trim();
        if (!kIsWeb &&
            preferAnimated &&
            item.isAnimated &&
            thumbUrl.isNotEmpty &&
            thumbUrl != url) {
          return _buildCachedImage(
            url: url,
            fallbackUrl: thumbUrl,
            decodeWidth: decodeWidth,
            decodeHeight: decodeHeight,
            loadingWidget: _buildCachedImage(
              url: thumbUrl,
              fallbackUrl: '',
              decodeWidth: decodeWidth,
              decodeHeight: decodeHeight,
            ),
          );
        }
        return _buildCachedImage(
          url: url,
          fallbackUrl: preferAnimated ? item.thumbUrl : item.originUrl,
          decodeWidth: decodeWidth,
          decodeHeight: decodeHeight,
        );
      },
    );
  }

  Widget _buildCachedImage({
    required String url,
    required String fallbackUrl,
    required int decodeWidth,
    required int decodeHeight,
    Widget? loadingWidget,
  }) {
    if (kIsWeb) {
      return AppNetworkImage(
        url: url,
        cacheKey: stickerNetworkImageCacheKey(item.stickerId, url),
        fit: fit,
        width: width,
        height: height,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (_, __, ___) {
          if (fallbackUrl.isNotEmpty && fallbackUrl != url) {
            return _buildCachedImage(
                url: fallbackUrl,
                fallbackUrl: '',
                decodeWidth: decodeWidth,
                decodeHeight: decodeHeight);
          }
          return _stickerImagePlaceholder(width: width, height: height);
        },
      );
    }
    return Image(
      image: ResizeImage(
          CachedNetworkImageProvider(
            url,
            cacheKey: stickerNetworkImageCacheKey(item.stickerId, url),
          ),
          width: decodeWidth,
          height: decodeHeight,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: loadingWidget != null
          ? (_, child, frame, __) => frame == null ? loadingWidget : child
          : null,
      errorBuilder: (_, __, ___) {
        if (fallbackUrl.isNotEmpty && fallbackUrl != url) {
          return _buildCachedImage(
              url: fallbackUrl,
              fallbackUrl: '',
              decodeWidth: decodeWidth,
              decodeHeight: decodeHeight);
        }
        return _stickerImagePlaceholder(width: width, height: height);
      },
    );
  }
}

Widget _stickerImagePlaceholder({double? width, double? height}) {
  return SizedBox(
    width: width ?? 40,
    height: height ?? 40,
    child: const Icon(Icons.emoji_emotions_outlined),
  );
}

class _UrlOnlyStickerItem extends StickerItem {
  _UrlOnlyStickerItem({
    required String url,
    required String fallbackUrl,
    required String mediaType,
  }) : super(
          stickerId: '',
          thumbUrl: fallbackUrl.isNotEmpty ? fallbackUrl : url,
          originUrl: url,
          mediaType: mediaType,
        );
}

/// Bucket nearby layout sizes to share decodes and bound large GIF frames.
int stickerDecodePixels(double logicalPixels, double devicePixelRatio) {
  final logical =
      logicalPixels.isFinite && logicalPixels > 0 ? logicalPixels : 256.0;
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  return (((logical * ratio).clamp(1.0, 1024.0) / 64).ceil() * 64)
      .clamp(64, 1024);
}
