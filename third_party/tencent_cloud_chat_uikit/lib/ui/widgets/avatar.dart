import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_status.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_user_status.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_self_info_view_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/common_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/avatar_image_provider.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_mem_cache_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_payload.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_web_image_lightbox.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';
import 'package:tencent_cloud_chat_uikit/data_services/core/core_services_implements.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';

typedef AvatarPreviewUrlResolver = Future<String?> Function();

/// 宿主可注入：将头像原始 URL 解析为可请求地址。未安装时保持原串。
String? Function(String url)? resolveAvatarNetworkUrl;

/// 宿主可注入：为解析后的头像 URL 附加鉴权头。
Map<String, String>? Function(String url)? avatarNetworkUrlHeaders;

String resolveAvatarDisplayUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return resolveAvatarNetworkUrl?.call(trimmed) ?? trimmed;
}

Map<String, String>? avatarNetworkHeaders(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return avatarNetworkUrlHeaders?.call(trimmed);
}

class Avatar extends TIMUIKitStatelessWidget {
  final String faceUrl;
  final String showName;
  final bool isFromLocalAsset;
  final CoreServicesImpl coreService = serviceLocator<CoreServicesImpl>();
  final BorderRadius? borderRadius;
  final V2TimUserStatus? onlineStatus;
  final int? type; // 1 c2c 2 group
  final bool isShowBigWhenClick;

  /// 普通展示始终使用 [faceUrl]（thumb）。该 URL 仅在点击后读取。
  final String? previewFaceUrl;

  /// 点击进入全屏后惰性获取 preview URL；普通页面不会触发。
  final AvatarPreviewUrlResolver? previewUrlResolver;
  final String? avatarCacheKey;
  final String? previewCacheKey;
  final TUISelfInfoViewModel selfInfoViewModel =
      serviceLocator<TUISelfInfoViewModel>();

  Avatar(
      {Key? key,
      required this.faceUrl,
      this.onlineStatus,
      required this.showName,
      this.isShowBigWhenClick = false,
      this.previewFaceUrl,
      this.previewUrlResolver,
      this.avatarCacheKey,
      this.previewCacheKey,
      this.isFromLocalAsset = false,
      this.borderRadius,
      this.type = 1})
      : super(key: key);

  Widget getImageWidget(BuildContext context, TUITheme theme) {
    Widget buildAssetAvatar(String path, {String? package}) {
      if (path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.asset(
          path,
          fit: BoxFit.cover,
          package: package,
        );
      }
      return Image.asset(
        path,
        fit: BoxFit.cover,
        package: package,
      );
    }

    Widget defaultAvatar() {
      if (type == 1) {
        return buildAssetAvatar(
          'images/default_c2c_head.png',
          package: 'tencent_cloud_chat_uikit',
        );
      } else {
        final assetPath = TencentUtils.checkString(
                selfInfoViewModel.globalConfig?.defaultAvatarAssetPath) ??
            'images/default_group_head.png';
        return buildAssetAvatar(
          assetPath,
          package:
              selfInfoViewModel.globalConfig?.defaultAvatarAssetPath != null
                  ? null
                  : 'tencent_cloud_chat_uikit',
        );
      }
    }

    // Keep the semantic placeholder visible while a real network avatar is
    // being decoded. A neutral grey block makes contact/group lists look
    // incomplete and also loses the distinction between a user and a group.
    // The cached image replaces this placeholder without changing layout.
    Widget placeholderForFaceUrl(String url) {
      if (url.trim().isEmpty || _isDefaultAvatarUrl(url)) {
        return defaultAvatar();
      }
      return defaultAvatar();
    }

    // final emptyAvatarBuilder = coreService.emptyAvatarBuilder;
    if (faceUrl != "") {
      if (isFromLocalAsset) {
        return buildAssetAvatar(faceUrl);
      }
      if (_isDefaultAvatarUrl(faceUrl)) {
        return defaultAvatar();
      }
      final displayUrl = resolveAvatarDisplayUrl(faceUrl);
      if (displayUrl.isEmpty) {
        return defaultAvatar();
      }
      final headers = avatarNetworkHeaders(displayUrl);
      final cacheIdentity = avatarCacheKey ?? faceUrl;
      if (kIsWeb && _isOssLikeNetworkUrl(displayUrl)) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return RepaintBoundary(
              child: Image.network(
                displayUrl,
                headers: headers,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return placeholderForFaceUrl(faceUrl);
                },
                errorBuilder: (_, __, ___) => defaultAvatar(),
              ),
            );
          },
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final cacheSize = ImageMemCacheSize.forBox(constraints, context);
          if (!kIsWeb) {
            // Resolve the warmed provider directly. Keep the Image mounted
            // while its URL changes, with the fallback underneath, so loading
            // never replaces an already decoded avatar with a placeholder.
            return RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  defaultAvatar(),
                  Image(
                    image: avatarImageProvider(
                      url: displayUrl,
                      cacheKey: cacheIdentity,
                      cacheSize: cacheSize,
                      headers: headers,
                    ),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          }
          return RepaintBoundary(
            child: CachedNetworkImage(
              imageUrl: displayUrl,
              cacheKey: cacheIdentity,
              httpHeaders: headers,
              useOldImageOnUrlChange: true,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: cacheSize,
              memCacheHeight: cacheSize,
              maxWidthDiskCache: cacheSize,
              maxHeightDiskCache: cacheSize,
              fadeInDuration: const Duration(milliseconds: 0),
              fadeOutDuration: Duration.zero,
              // Keep the user/group fallback while a web image loads.
              placeholder: (context, url) => placeholderForFaceUrl(url),
              imageBuilder: (context, imageProvider) => Image(
                image: imageProvider,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
              errorWidget: (BuildContext context, String c, dynamic s) {
                return defaultAvatar();
              },
            ),
          );
        },
      );
    } else {
      return defaultAvatar();
    }
  }

  Widget _clipAvatar(
      {required BorderRadius borderRadius, required Widget child}) {
    final radius = borderRadius.topLeft.x;
    if (radius >= 999) {
      return ClipOval(child: child);
    }
    return ClipRRect(borderRadius: borderRadius, child: child);
  }

  bool _isDefaultAvatarUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.contains('default_c2c_head') ||
        lower.contains('default_group_head');
  }

  bool _isOssLikeNetworkUrl(String url) {
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    return true;
  }

  ImageProvider getImageProvider({String? url, String? cacheKey}) {
    ImageProvider defaultAvatar() {
      if (type == 1) {
        return Image.asset('images/default_c2c_head.png',
                fit: BoxFit.cover, package: 'tencent_cloud_chat_uikit')
            .image;
      } else {
        return Image.asset(
                TencentUtils.checkString(selfInfoViewModel
                        .globalConfig?.defaultAvatarAssetPath) ??
                    'images/default_group_head.png',
                fit: BoxFit.cover,
                package:
                    selfInfoViewModel.globalConfig?.defaultAvatarAssetPath !=
                            null
                        ? null
                        : 'tencent_cloud_chat_uikit')
            .image;
      }
    }

    final source = (url ?? faceUrl).trim();
    if (source != "") {
      if (isFromLocalAsset) {
        return Image.asset(source).image;
      }
      if (_isDefaultAvatarUrl(source)) {
        return defaultAvatar();
      }
      final displayUrl = resolveAvatarDisplayUrl(source);
      if (displayUrl.isEmpty) {
        return defaultAvatar();
      }
      final headers = avatarNetworkHeaders(displayUrl);
      final cacheIdentity =
          cacheKey ?? (source == faceUrl ? avatarCacheKey : null) ?? source;
      if (kIsWeb && _isOssLikeNetworkUrl(displayUrl)) {
        return NetworkImage(
          displayUrl,
          headers: headers,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        );
      }
      return CachedNetworkImageProvider(
        displayUrl,
        cacheKey: cacheIdentity,
        headers: headers,
      );
    } else {
      return defaultAvatar();
    }
  }

  ({String path, String? package}) _resolveDefaultAvatarAsset() {
    if (type == 1) {
      return (
        path: 'images/default_c2c_head.png',
        package: 'tencent_cloud_chat_uikit'
      );
    }
    final custom = TencentUtils.checkString(
      selfInfoViewModel.globalConfig?.defaultAvatarAssetPath,
    );
    if (custom != null) {
      return (path: custom, package: null);
    }
    return (
      path: 'images/default_group_head.png',
      package: 'tencent_cloud_chat_uikit'
    );
  }

  Future<void> _openBigAvatar(BuildContext context) async {
    final trimmed = faceUrl.trim();
    final assetDownloadFn = _buildPreviewDownloadFn(context, faceUrl: trimmed);

    Future<bool> tryWindowsAsset() {
      final asset = _resolveDefaultAvatarAsset();
      return DesktopMediaPreviewHook.tryOpen(
        DesktopMediaPreviewPayload.image(
          source: 'avatar',
          assetPath: asset.path,
          assetPackage: asset.package,
          downloadOnly: true,
          fitTallImagesToScreenWidth: false,
        ),
      );
    }

    void openAssetPreview() {
      final asset = _resolveDefaultAvatarAsset();
      if (asset.path.toLowerCase().endsWith('.svg')) {
        pushMediaPreview(
          context: context,
          enableGestureBack: false,
          child: _AvatarAssetPreviewPage(
            assetPath: asset.path,
            package: asset.package,
            downloadFn: assetDownloadFn,
          ),
        );
        return;
      }
      pushMediaPreview(
        context: context,
        enableGestureBack: false,
        child: ImageScreen(
          imageProvider: getImageProvider(),
          heroTag: '',
          downloadFn: assetDownloadFn,
          downloadOnly: true,
          fitTallImagesToScreenWidth: false,
        ),
      );
    }

    if (trimmed.isEmpty ||
        isFromLocalAsset ||
        _isDefaultAvatarUrl(trimmed) ||
        (!trimmed.startsWith('http://') &&
            !trimmed.startsWith('https://') &&
            !trimmed.startsWith('data:'))) {
      if (PlatformUtils().isWindows && await tryWindowsAsset()) {
        return;
      }
      openAssetPreview();
      return;
    }

    // A network thumb is not a valid full-screen source.  Callers that want
    // the preview affordance must provide the explicit preview URL or lazy
    // resolver; silently opening the thumb here would violate the variant
    // boundary for legacy call sites.
    if ((previewFaceUrl?.trim().isEmpty ?? true) &&
        previewUrlResolver == null) {
      return;
    }

    if (PlatformUtils().isWinMacDesktop) {
      final previewUrl = await _resolvePreviewUrl();
      if (previewUrl != null && previewUrl.isNotEmpty) {
        final opened = await DesktopMediaPreviewHook.tryOpen(
          DesktopMediaPreviewPayload.image(
            source: 'avatar',
            url: previewUrl,
            downloadOnly: true,
            fitTallImagesToScreenWidth: false,
          ),
        );
        if (opened) {
          return;
        }
      }
    }

    // Web：禁止走 ImageScreen（会读像素触发 Same-Origin / CORS 红屏）。
    if (kIsWeb) {
      await ChatWebImageLightbox.show(
        context: context,
        imageUrl: trimmed,
        imageUrlResolver: () async {
          final resolved = await _resolvePreviewUrl();
          if (resolved == null) {
            return null;
          }
          final preparer =
              selfInfoViewModel.globalConfig?.prepareWebAvatarPreviewUrl;
          if (preparer == null) {
            return resolved;
          }
          try {
            return (await preparer(resolved))?.trim() ?? resolved;
          } catch (_) {
            return resolved;
          }
        },
        onDownloadUrl: _buildPreviewDownloadForUrl(context),
      );
      return;
    }

    pushMediaPreview(
      context: context,
      enableGestureBack: false,
      child: _AvatarNetworkPreviewPage(
        thumbUrl: trimmed,
        thumbProvider: getImageProvider(
          url: trimmed,
          cacheKey: avatarCacheKey,
        ),
        previewUrlResolver: _resolvePreviewUrl,
        previewProviderBuilder: (url) => getImageProvider(
          url: url,
          cacheKey: previewCacheKey,
        ),
        savePreviewUrl: _buildPreviewDownloadForUrl(context),
      ),
    );
  }

  /// Opens the same lazy full-screen preview used by the avatar tap handler.
  /// The resolver is not evaluated until this method is called.
  Future<void> openPreview(BuildContext context) => _openBigAvatar(context);

  Future<String?> _resolvePreviewUrl() async {
    final direct = previewFaceUrl?.trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final resolver = previewUrlResolver;
    if (resolver == null) {
      return null;
    }
    try {
      final resolved = (await resolver())?.trim() ?? '';
      return resolved.isEmpty ? null : resolved;
    } catch (_) {
      return null;
    }
  }

  Future<void> Function(String faceUrl)? _buildPreviewDownloadForUrl(
    BuildContext context,
  ) {
    final saver = selfInfoViewModel.globalConfig?.saveAvatarPreview;
    if (saver == null) {
      return null;
    }
    return (faceUrl) => saver(
          context,
          faceUrl: faceUrl,
          showName: showName,
          avatarType: type ?? 1,
        );
  }

  Future<void> Function()? _buildPreviewDownloadFn(
    BuildContext context, {
    required String faceUrl,
  }) {
    final saver = selfInfoViewModel.globalConfig?.saveAvatarPreview;
    if (saver == null) {
      return null;
    }
    final fallback =
        faceUrl.trim().isEmpty ? _resolveDefaultAvatarAsset() : null;
    return () => saver(
          context,
          faceUrl: faceUrl,
          showName: showName,
          avatarType: type ?? 1,
          fallbackAssetPath: fallback?.path,
          fallbackAssetPackage: fallback?.package,
        );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final TUITheme theme = value.theme;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (isShowBigWhenClick)
          GestureDetector(
            onTap: () {
              unawaited(_openBigAvatar(context));
            },
            child: ClipRRect(
              borderRadius: borderRadius ??
                  selfInfoViewModel.globalConfig?.defaultAvatarBorderRadius ??
                  BorderRadius.circular(4.8),
              child: getImageWidget(context, theme),
            ),
          ),
        if (!isShowBigWhenClick)
          _clipAvatar(
            borderRadius: borderRadius ??
                selfInfoViewModel.globalConfig?.defaultAvatarBorderRadius ??
                BorderRadius.circular(4.8),
            child: getImageWidget(context, theme),
          ),
        if (onlineStatus?.statusType == 1)
          Positioned(
            bottom: -1.5,
            right: -1.5,
            child: Container(
              width: 12,
              height: 12,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2.0,
                ),
                color:
                    theme.conversationItemOnlineStatusBgColor ?? Colors.green,
              ),
              child: null,
            ),
          ),
      ],
    );
  }
}

class _AvatarNetworkPreviewPage extends StatefulWidget {
  const _AvatarNetworkPreviewPage({
    required this.thumbUrl,
    required this.thumbProvider,
    required this.previewUrlResolver,
    required this.previewProviderBuilder,
    this.savePreviewUrl,
  });

  final String thumbUrl;
  final ImageProvider thumbProvider;
  final Future<String?> Function() previewUrlResolver;
  final ImageProvider Function(String url) previewProviderBuilder;
  final Future<void> Function(String url)? savePreviewUrl;

  @override
  State<_AvatarNetworkPreviewPage> createState() =>
      _AvatarNetworkPreviewPageState();
}

class _AvatarNetworkPreviewPageState extends State<_AvatarNetworkPreviewPage> {
  late ImageProvider _imageProvider;
  String? _previewUrl;

  @override
  void initState() {
    super.initState();
    _imageProvider = widget.thumbProvider;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resolvePreview());
    });
  }

  Future<void> _resolvePreview() async {
    String url;
    try {
      url = (await widget.previewUrlResolver())?.trim() ?? '';
    } catch (_) {
      // A failed lazy preview request must leave the already visible thumb in
      // place.  This is deliberately not a fallback to another URL variant.
      return;
    }
    if (!mounted || url.isEmpty) {
      return;
    }
    setState(() {
      _previewUrl = url;
      _imageProvider = widget.previewProviderBuilder(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _previewUrl;
    return ImageScreen(
      key: ValueKey<String>(previewUrl ?? widget.thumbUrl),
      imageProvider: _imageProvider,
      placeholderImageProvider: widget.thumbProvider,
      heroTag: '',
      downloadFn: previewUrl == null || widget.savePreviewUrl == null
          ? null
          : () => widget.savePreviewUrl!(previewUrl),
      downloadOnly: true,
      fitTallImagesToScreenWidth: false,
    );
  }
}

class _AvatarAssetPreviewPage extends StatefulWidget {
  const _AvatarAssetPreviewPage({
    required this.assetPath,
    this.package,
    this.downloadFn,
  });

  final String assetPath;
  final String? package;
  final Future<void> Function()? downloadFn;

  @override
  State<_AvatarAssetPreviewPage> createState() =>
      _AvatarAssetPreviewPageState();
}

class _AvatarAssetPreviewPageState extends State<_AvatarAssetPreviewPage> {
  final MediaPreviewSlideMetrics _slideMetrics = MediaPreviewSlideMetrics();
  bool _isSaving = false;
  bool _isClosing = false;

  @override
  void dispose() {
    _slideMetrics.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_isClosing || !mounted) {
      return;
    }
    _isClosing = true;
    await Navigator.of(context).maybePop();
  }

  Future<void> _handleDownload() async {
    final downloadFn = widget.downloadFn;
    if (downloadFn == null || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await downloadFn();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _handleSlideEnd(Velocity velocity) {
    if (_isClosing) {
      return;
    }
    if (mediaPreviewShouldDismissForSlide(
      _slideMetrics.slideOffset,
      velocity.pixelsPerSecond.dy,
    )) {
      _close();
      return;
    }
    _slideMetrics.resetBackdrop();
  }

  @override
  Widget build(BuildContext context) {
    final isSvg = widget.assetPath.toLowerCase().endsWith('.svg');
    final chromeAnimation = mediaPreviewChromeAnimation(context);
    final screenSize = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _slideMetrics,
              builder: (context, _) {
                return ColoredBox(
                  color: Colors.black.withValues(
                    alpha: _slideMetrics.backdropOpacity,
                  ),
                );
              },
            ),
          ),
          MediaPreviewVerticalDismissLayer(
            metrics: _slideMetrics,
            onSlideEndWithVelocity: _handleSlideEnd,
            child: GestureDetector(
              onTap: _close,
              child: Center(
                child: ListenableBuilder(
                  listenable: _slideMetrics,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: _slideMetrics.slideOffset,
                      child: child,
                    );
                  },
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: SizedBox(
                      width: screenSize.width,
                      height: screenSize.height,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenSize.width * 0.08,
                          vertical: 24,
                        ),
                        child: isSvg
                            ? SvgPicture.asset(
                                widget.assetPath,
                                package: widget.package,
                                fit: BoxFit.contain,
                              )
                            : Image.asset(
                                widget.assetPath,
                                package: widget.package,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: chromeAnimation,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: _close,
                  ),
                  const Spacer(),
                  if (widget.downloadFn != null)
                    IconButton(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded,
                              color: Colors.white),
                      onPressed: _isSaving ? null : _handleDownload,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
