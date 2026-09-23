import 'dart:async';
import 'dart:io' show Platform;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_scroll_physics.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_debug.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_header_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_chat_videoplayer.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_hero.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_video_chrome.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_metrics.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_slide_shell.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({
    required this.message,
    required this.heroTag,
    required this.videoElement,
    this.preferOnlinePlayback = false,
    this.playbackHeaders,
    this.externalVideo = false,
    this.saveVideoFn,
    this.recoverVideoFn,
    this.forwardFn,
    this.deleteFn,
    this.onOpenMedia,
    this.onClosed,
    this.galleryItems,
    this.initialIndex = 0,
    this.onGalleryIndexChanged,
    Key? key,
  }) : super(key: key);

  final V2TimMessage message;
  final dynamic heroTag;
  final V2TimVideoElem videoElement;
  final bool preferOnlinePlayback;
  final Map<String, String>? playbackHeaders;
  final bool externalVideo;
  final Future<void> Function()? saveVideoFn;
  final Future<V2TimVideoElem?> Function()? recoverVideoFn;
  final Future<void> Function()? forwardFn;
  final Future<void> Function()? deleteFn;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onClosed;
  final List<ChatMediaPreviewItem>? galleryItems;
  final int initialIndex;
  final ValueChanged<int>? onGalleryIndexChanged;

  bool get _useGallery => (galleryItems?.length ?? 0) > 1;

  @override
  State<StatefulWidget> createState() => _VideoScreenState();
}

class _VideoScreenState extends TIMUIKitState<VideoScreen>
    with TickerProviderStateMixin {
  final TUIChatGlobalModel model = serviceLocator<TUIChatGlobalModel>();
  final GlobalKey<ExtendedImageSlidePageState> _slidePageKey =
      GlobalKey<ExtendedImageSlidePageState>();
  GlobalKey<TIMUIKitVideoPlayerState> _playerKey =
      GlobalKey<TIMUIKitVideoPlayerState>();
  final MediaPreviewSlideMetrics _slideMetrics = MediaPreviewSlideMetrics();
  bool _closing = false;
  bool _recoveryAttempted = false;
  bool _recoveringVideo = false;
  bool _heroOverlayVisible = true;
  double _heroOverlayOpacity = 1.0;
  static const Duration _heroOverlayFadeDuration = Duration(milliseconds: 220);

  /// 首次进场等开播再掀封面；图集翻页落地为 false。
  bool _holdHeroUntilPlayback = true;
  final _videoChromeKey = GlobalKey<MediaPreviewVideoChromeState>();
  final ValueNotifier<int> _attachmentChanges = ValueNotifier<int>(0);
  final ValueNotifier<int> _chromeTick = ValueNotifier<int>(0);
  bool _slidePausedForDrag = false;
  bool _pausedByUser = false;
  bool _isPlaybackActive = false;
  bool _playbackRequested = false;
  final Set<Object> _hiddenHeroTags = <Object>{};
  bool _closeHeroRevealScheduled = false;
  final MediaPreviewSlideDismissController _slideDismissController =
      MediaPreviewSlideDismissController();
  final ValueNotifier<bool> _heroModeEnabled = ValueNotifier<bool>(true);
  late final MediaPreviewEntranceLatch _entranceLatch;
  late PageController _galleryPageController;
  late int _currentIndex;
  int _pageControllerEpoch = 0;

  /// 播放器所在页：翻页 ballistic 结束再切换，避免中途 setState 卡顿。
  late int _playerPageIndex;
  Widget? _cachedPlayerArea;

  List<ChatMediaPreviewItem> get _items {
    if (widget.galleryItems?.isNotEmpty == true) {
      return widget.galleryItems!;
    }
    return [
      ChatMediaPreviewItem(
        message: widget.message,
        type: ChatMediaPreviewType.video,
        heroTag: widget.heroTag,
        messageID: widget.message.msgID ?? widget.message.id?.toString(),
        videoElement: widget.videoElement,
        forwardFn: widget.forwardFn,
        deleteFn: widget.deleteFn,
      ),
    ];
  }

  ChatMediaPreviewItem get _currentItem => _items[_currentIndex];
  ChatMediaPreviewItem get _playerItem => _items[_playerPageIndex];
  V2TimMessage get _currentMessage => _currentItem.message;
  V2TimMessage get _playerMessage => _playerItem.message;
  V2TimVideoElem get _currentVideoElement =>
      _currentItem.videoElement ?? widget.videoElement;
  V2TimVideoElem get _playerVideoElement =>
      _playerItem.videoElement ?? widget.videoElement;
  Object get _currentHeroTag => _currentItem.heroTag;
  bool get _shouldBuildPlayer => widget._useGallery || _playbackRequested;

  void _markPlaybackActive() {
    if (!mounted || _closing) {
      return;
    }
    setState(() {
      _isPlaybackActive = true;
      _pausedByUser = false;
    });
  }

  void _markPlaybackPaused() {
    if (!mounted || _closing) {
      return;
    }
    setState(() {
      _isPlaybackActive = false;
      _pausedByUser = true;
    });
  }

  void _showHero(Object tag) {
    if (_hiddenHeroTags.remove(tag)) {
      MediaPreviewHeroRegistry.instance.show(tag);
    } else {
      MediaPreviewHeroRegistry.instance.revealAll({tag});
    }
  }

  void _revealHiddenHeroes() {
    if (_hiddenHeroTags.isEmpty) {
      return;
    }
    final tags = Set<Object>.from(_hiddenHeroTags);
    _hiddenHeroTags.clear();
    MediaPreviewHeroRegistry.instance.revealAll(tags);
  }

  void _scheduleCurrentHeroReveal() {
    if (_closeHeroRevealScheduled) {
      return;
    }
    _closeHeroRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeHeroRevealScheduled = false;
      if (!_closing) {
        return;
      }
      _showHero(_currentHeroTag);
    });
  }

  void _onSlidingPage(ExtendedImageSlidePageState state) {
    if (state.isSliding && !_slidePausedForDrag) {
      _slidePausedForDrag = true;
      if (_heroOverlayVisible) {
        _heroOverlayVisible = false;
      }
      unawaited(_playerKey.currentState?.pausePlayback());
      if (mounted) {
        setState(() {});
      }
    }
    if (_slidePausedForDrag &&
        !state.isSliding &&
        state.offset == Offset.zero &&
        !_closing) {
      _slidePausedForDrag = false;
      if (!_pausedByUser) {
        _playerKey.currentState?.resumePlayback();
        if (mounted) {
          setState(() => _isPlaybackActive = true);
        }
      }
      if (mounted) {
        setState(() {});
      }
    }
    _slideMetrics.updateFromSlide(state, MediaQuery.sizeOf(context));
  }

  @override
  initState() {
    super.initState();
    _currentIndex = widget._useGallery
        ? widget.initialIndex.clamp(0, widget.galleryItems!.length - 1)
        : 0;
    _playerPageIndex = _currentIndex;
    _playbackRequested = true;
    MediaPreviewDebug.log('video_screen_open', {
      'useGallery': widget._useGallery,
      'count': _items.length,
      'initial': _currentIndex,
      'items': MediaPreviewDebug.itemsSummary(_items),
      'holdHero': _holdHeroUntilPlayback,
    });
    _galleryPageController = PageController(initialPage: _currentIndex);
    _entranceLatch = MediaPreviewEntranceLatch(
      onSettled: () {
        if (!mounted || _closing) {
          return;
        }
        MediaPreviewDebug.log('video_screen_entrance_settled', {
          'playerPage': _playerPageIndex,
          'heroVisible': _heroOverlayVisible,
          'holdHero': _holdHeroUntilPlayback,
        });
        _onPreviewTransitionEnd();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) {
        return;
      }
      _bindVisibleEntrance();
      applyVideoPlaybackOrientation(
        resolveVideoAspectRatio(_currentVideoElement),
      );
      if (_shouldBuildPlayer) {
        _playerKey.currentState?.preparePlaybackPipeline();
      }
    });
  }

  void _bindVisibleEntrance() {
    if (!mounted || _closing) return;
    final route = ModalRoute.of(context);
    if (route?.offstage == true) {
      // Hero measures offstage first. Retry on the next frame, once the route
      // exposes its real animation instead of the completed measurement proxy.
      WidgetsBinding.instance
          .scheduleFrameCallback((_) => _bindVisibleEntrance());
      return;
    }
    _entranceLatch.bind(
      mediaPreviewChromeAnimation(context),
      routeDuration: route?.transitionDuration,
    );
  }

  @override
  void didUpdateWidget(covariant VideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItems = oldWidget.galleryItems;
    final newItems = widget.galleryItems;
    if (identical(oldItems, newItems) ||
        oldItems == newItems ||
        newItems == null ||
        newItems.isEmpty) {
      return;
    }
    final nextIndex = retainChatMediaGalleryIndex(
      currentIndex: _currentIndex,
      oldOldestFirst: [
        for (final item in oldItems ?? const <ChatMediaPreviewItem>[])
          item.message,
      ],
      newOldestFirst: [for (final item in newItems) item.message],
    );
    _currentIndex = nextIndex;
    _playerPageIndex = nextIndex;
    if (chatMediaGalleryShouldReplacePageController(
      oldItemCount: oldItems?.length ?? 0,
      newItemCount: newItems.length,
    )) {
      _replaceGalleryPageController(nextIndex);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) {
        return;
      }
      if (_galleryPageController.hasClients &&
          _galleryPageController.page?.round() != nextIndex) {
        _galleryPageController.jumpToPage(nextIndex);
      }
    });
  }

  void _replaceGalleryPageController(int initialPage) {
    final old = _galleryPageController;
    _pageControllerEpoch++;
    final count = _items.length;
    final page = count <= 0 ? 0 : initialPage.clamp(0, count - 1).toInt();
    _galleryPageController = PageController(initialPage: page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (!mounted || _closing) {
        return;
      }
      if (_galleryPageController.hasClients &&
          _galleryPageController.page?.round() != page) {
        _galleryPageController.jumpToPage(page);
      }
    });
  }

  void _onPreviewTransitionEnd() {
    if (_shouldBuildPlayer) {
      // 入场结束只触发播放；Hero 封面留到首帧/开播后再撤，避免灰屏。
      MediaPreviewDebug.log('video_screen_start_play', {
        'playerPage': _playerPageIndex,
        'hasPlayerState': _playerKey.currentState != null,
      });
      _playerKey.currentState?.startDeferredPlayback();
    }
  }

  void _dismissHeroOverlay({bool immediate = false}) {
    if (!mounted || _closing || !_heroOverlayVisible) {
      return;
    }
    MediaPreviewDebug.log('video_screen_hero_dismiss', {
      'playerPage': _playerPageIndex,
      'holdHero': _holdHeroUntilPlayback,
      'immediate': immediate,
    });
    if (immediate || _heroOverlayOpacity <= 0) {
      setState(() {
        _heroOverlayVisible = false;
        _heroOverlayOpacity = 0;
      });
      return;
    }
    setState(() => _heroOverlayOpacity = 0);
  }

  Future<void> _revealVideoAfterPlaybackStarted() async {
    final ready =
        await _playerKey.currentState?.waitUntilFirstFramePresentable() ??
            false;
    if (!mounted || _closing) {
      return;
    }
    if (!ready) {
      return;
    }
    _dismissHeroOverlay();
    _markPlaybackActive();
  }

  Widget _buildHeroSnapshot() =>
      buildMediaPreviewVideoSnapshot(context, _playerVideoElement);

  void _resetPlayerForCurrentItem({bool holdHeroUntilPlayback = true}) {
    _playerKey = GlobalKey<TIMUIKitVideoPlayerState>();
    _cachedPlayerArea = null;
    _heroOverlayVisible = true;
    _heroOverlayOpacity = 1.0;
    _holdHeroUntilPlayback = holdHeroUntilPlayback;
    _slidePausedForDrag = false;
    _pausedByUser = false;
    _isPlaybackActive = false;
    _playbackRequested = true;
  }

  Timer? _playerCommitDebounce;
  static const Duration _playerCommitDebounceDelay = Duration(milliseconds: 50);

  void _notifyChromeChanged() {
    if (!mounted) {
      return;
    }
    _chromeTick.value++;
  }

  void _onGalleryPageChanged(int index) {
    if (_closing) {
      return;
    }
    final next = index.clamp(0, _items.length - 1);
    if (next == _currentIndex) {
      return;
    }
    final previous = _currentIndex;
    // 先只更新逻辑页与顶栏，播放器等滚动停稳再切，避免翻页中途重建卡顿。
    _currentIndex = next;
    _videoChromeKey.currentState?.showControls();
    _notifyChromeChanged();
    widget.onGalleryIndexChanged?.call(next);
    final scrolling = _galleryPageController.hasClients &&
        _galleryPageController.position.isScrollingNotifier.value;
    MediaPreviewDebug.log('video_screen_page_changed', {
      'from': previous,
      'to': next,
      'fromItem': MediaPreviewDebug.itemSummary(_items[previous]),
      'toItem': MediaPreviewDebug.itemSummary(_items[next]),
      'playerPage': _playerPageIndex,
      'scrolling': scrolling,
    });
    if (!scrolling) {
      _scheduleCommitPlayerPage();
    }
  }

  void _onGalleryScrollEnd() {
    if (_closing) {
      return;
    }
    MediaPreviewDebug.log('video_screen_scroll_end', {
      'current': _currentIndex,
      'playerPage': _playerPageIndex,
    });
    _scheduleCommitPlayerPage();
  }

  void _scheduleCommitPlayerPage() {
    _playerCommitDebounce?.cancel();
    MediaPreviewDebug.log('video_screen_commit_schedule', {
      'current': _currentIndex,
      'playerPage': _playerPageIndex,
    });
    _playerCommitDebounce = Timer(_playerCommitDebounceDelay, () {
      if (!mounted || _closing) {
        return;
      }
      if (_galleryPageController.hasClients &&
          _galleryPageController.position.isScrollingNotifier.value) {
        MediaPreviewDebug.log('video_screen_commit_skip', {
          'reason': 'still_scrolling',
        });
        return;
      }
      _commitPlayerPage();
    });
  }

  void _commitPlayerPage() {
    if (_closing || !mounted) {
      return;
    }
    if (_playerPageIndex == _currentIndex) {
      MediaPreviewDebug.log('video_screen_commit_noop', {
        'playerPage': _playerPageIndex,
        'current': _currentIndex,
      });
      return;
    }
    final previousPlayer = _playerPageIndex;
    _playerKey.currentState?.prepareForRouteClose();
    setState(() {
      _playerPageIndex = _currentIndex;
      // 封面留到真正开播，避免 initialized 时掀开露出黑屏/上一页。
      _resetPlayerForCurrentItem(holdHeroUntilPlayback: true);
    });
    MediaPreviewDebug.log('video_screen_commit_player', {
      'from': previousPlayer,
      'to': _playerPageIndex,
      'toItem': MediaPreviewDebug.itemSummary(_items[_playerPageIndex]),
      'holdHero': _holdHeroUntilPlayback,
    });
    // 普通 PageView 也会因平台视图拆卸漂移，停稳后钉回逻辑页。
    void stabilize(String reason) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _closing ||
            !_galleryPageController.hasClients ||
            _galleryPageController.position.isScrollingNotifier.value) {
          return;
        }
        final page = _galleryPageController.page;
        if (page == null || (page - _currentIndex).abs() < 0.08) {
          return;
        }
        MediaPreviewDebug.log('video_screen_page_stabilize', {
          'reason': reason,
          'from': page.toStringAsFixed(3),
          'to': _currentIndex,
        });
        _galleryPageController.jumpToPage(_currentIndex);
      });
    }

    stabilize('commit_f1');
    stabilize('commit_f2');
    applyVideoPlaybackOrientation(resolveVideoAspectRatio(_playerVideoElement));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) {
        return;
      }
      MediaPreviewDebug.log('video_screen_commit_start_play', {
        'hasPlayerState': _playerKey.currentState != null,
        'playerPage': _playerPageIndex,
      });
      _playerKey.currentState?.preparePlaybackPipeline();
      _playerKey.currentState?.startDeferredPlayback();
      stabilize('after_start_play');
    });
  }

  Future<void> _recoverExternalVideo() async {
    if (_recoveryAttempted || !mounted || _closing) return;
    _recoveryAttempted = true;
    setState(() => _recoveringVideo = true);
    try {
      final recovered = await widget.recoverVideoFn!();
      if (!mounted || _closing) return;
      if (recovered == null) {
        _dismissHeroOverlay();
        return;
      }
      setState(() {
        _playerMessage.videoElem = recovered;
        _cachedPlayerArea = null;
        _playerKey = GlobalKey<TIMUIKitVideoPlayerState>();
        _holdHeroUntilPlayback = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing) return;
        _playerKey.currentState?.preparePlaybackPipeline();
        _playerKey.currentState?.startDeferredPlayback();
      });
    } catch (_) {
      if (mounted && !_closing) _dismissHeroOverlay();
    } finally {
      if (mounted && !_closing) setState(() => _recoveringVideo = false);
    }
  }

  Widget _buildSlideBody(Orientation orientation) {
    if (_recoveringVideo) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_shouldBuildPlayer) {
      final attachmentPlayerKey = _playerKey;
      _cachedPlayerArea ??= TIMUIKitVideoPlayer(
        key: _playerKey,
        message: _playerMessage,
        playbackHeaders: widget._useGallery ? null : widget.playbackHeaders,
        externalVideo: widget._useGallery
            ? _playerItem.resolveVideo != null
            : widget.externalVideo,
        resolveVideo: _playerItem.resolveVideo,
        deferInitialization: true,
        preferOnlinePlayback: true,
        isSending:
            _playerMessage.status == MessageStatus.V2TIM_MSG_STATUS_SENDING,
        onAspectRatioResolved: _onAspectRatioResolved,
        onPlayerInitialized: () {
          if (mounted && identical(attachmentPlayerKey, _playerKey)) {
            _attachmentChanges.value++;
          }
          MediaPreviewDebug.log('video_screen_player_initialized', {
            'playerPage': _playerPageIndex,
            'holdHero': _holdHeroUntilPlayback,
            'heroVisible': _heroOverlayVisible,
            'item': MediaPreviewDebug.itemSummary(_playerItem),
          });
          // 翻页落地：解码就绪即可掀封面。
          if (!_holdHeroUntilPlayback) {
            _dismissHeroOverlay();
          }
        },
        onInitFailed: () {
          if (mounted && identical(attachmentPlayerKey, _playerKey)) {
            _attachmentChanges.value++;
          }
          MediaPreviewDebug.log('video_screen_player_init_failed', {
            'playerPage': _playerPageIndex,
            'item': MediaPreviewDebug.itemSummary(_playerItem),
          });
          if (!widget._useGallery &&
              widget.recoverVideoFn != null &&
              !_recoveryAttempted) {
            unawaited(_recoverExternalVideo());
          } else {
            _dismissHeroOverlay(immediate: true);
          }
        },
        onPlaybackStarted: () {
          MediaPreviewDebug.log('video_screen_playback_started', {
            'playerPage': _playerPageIndex,
            'heroVisible': _heroOverlayVisible,
            'item': MediaPreviewDebug.itemSummary(_playerItem),
          });
          unawaited(_revealVideoAfterPlaybackStarted());
        },
        onPlaybackFinished: () {
          MediaPreviewDebug.log('video_screen_playback_finished', {
            'playerPage': _playerPageIndex,
            'item': MediaPreviewDebug.itemSummary(_playerItem),
          });
          _dismissHeroOverlay();
          _markPlaybackPaused();
        },
      );
    }

    return ExtendedImageSlidePageHandler(
      heroBuilderForSlidingPage: (result) => Material(
        color: Colors.transparent,
        child: result,
      ),
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            const ColoredBox(color: Colors.black),
            if (_cachedPlayerArea != null)
              Positioned.fill(child: _cachedPlayerArea!),
            if (_heroOverlayVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _heroOverlayOpacity,
                    duration: _heroOverlayFadeDuration,
                    curve: Curves.easeOut,
                    onEnd: () {
                      if (!mounted ||
                          _closing ||
                          _heroOverlayOpacity > 0 ||
                          !_heroOverlayVisible) {
                        return;
                      }
                      setState(() => _heroOverlayVisible = false);
                    },
                    child: HeroMode(
                      enabled: true,
                      child: HeroWidget(
                        tag: _currentHeroTag,
                        slidePagekey: _slidePageKey,
                        slideType: SlideType.wholePage,
                        child: Material(
                          color: Colors.transparent,
                          child: _buildHeroSnapshot(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!_shouldBuildPlayer)
              Center(
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              ),
            if (!_heroOverlayVisible && _shouldBuildPlayer)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _handlePreviewTap,
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryBody(Orientation orientation) {
    if (!widget._useGallery) {
      return _buildSlideBody(orientation);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification && notification.depth == 0) {
          _onGalleryScrollEnd();
        }
        return false;
      },
      child: PageView.builder(
        key: ValueKey<int>(_pageControllerEpoch),
        controller: _galleryPageController,
        itemCount: _items.length,
        physics: ChatMediaGalleryScrollPhysics.of(context),
        allowImplicitScrolling: true,
        onPageChanged: _onGalleryPageChanged,
        itemBuilder: (context, index) {
          // 普通 PageView 无 pageSpacing：左右各半缝，滑到一半中间露出黑间隔。
          final page = Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kChatMediaGalleryPageSpacing / 2,
            ),
            child: index == _playerPageIndex
                ? _buildSlideBody(orientation)
                : ColoredBox(
                    color: Colors.black,
                    child: buildMediaPreviewVideoSnapshot(
                      context,
                      _items[index].videoElement ?? widget.videoElement,
                    ),
                  ),
          );
          return RepaintBoundary(child: page);
        },
      ),
    );
  }

  void _onAspectRatioResolved(double aspectRatio) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) {
        applyVideoPlaybackOrientation(aspectRatio);
      }
    });
  }

  bool _prepareForClose({bool preserveSlideBackdrop = false}) {
    if (_closing) {
      return false;
    }
    if (!mounted) {
      return false;
    }
    _closing = true;
    _heroModeEnabled.value = false;
    _slidePausedForDrag = false;
    _playerKey.currentState?.prepareForRouteClose();
    if (!preserveSlideBackdrop) {
      _slideMetrics.resetBackdrop();
    } else {
      _scheduleCurrentHeroReveal();
    }
    return true;
  }

  void _close() {
    _slideDismissController.startMomentumDismiss(
      vsync: this,
      context: context,
      slidePageKey: _slidePageKey,
      metrics: _slideMetrics,
      isMounted: () => mounted,
      isClosing: () => _closing,
      prepareForClose: () => _prepareForClose(preserveSlideBackdrop: true),
      popRoute: _popSlideDismissRoute,
      releaseOffset: _slideMetrics.slideOffset,
    );
  }

  void _popSlideDismissRoute() {
    if (!_closing) {
      return;
    }
    _showHero(_currentHeroTag);
    widget.onClosed?.call();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _scheduleSlideDismissMomentumPop(
    ExtendedImageSlidePageState? state,
    ScaleEndDetails? details,
    Offset releaseOffset,
  ) {
    _slideDismissController.startMomentumDismiss(
      vsync: this,
      context: context,
      slidePageKey: _slidePageKey,
      metrics: _slideMetrics,
      isMounted: () => mounted,
      isClosing: () => _closing,
      prepareForClose: () => _prepareForClose(preserveSlideBackdrop: true),
      popRoute: _popSlideDismissRoute,
      details: details,
      releaseOffset: releaseOffset,
    );
  }

  bool _closeFromSlideDismiss(
    ExtendedImageSlidePageState? state,
    ScaleEndDetails? details,
    Offset releaseOffset,
  ) {
    _scheduleSlideDismissMomentumPop(state, details, releaseOffset);
    return false;
  }

  void _handlePreviewTap() {
    if (_closing) {
      return;
    }
    _videoChromeKey.currentState?.toggleControls();
  }

  Future<void> _togglePlayback() async {
    if (_closing) {
      return;
    }
    if (!_shouldBuildPlayer) {
      setState(() {
        _playbackRequested = true;
        _cachedPlayerArea = null;
        _pausedByUser = false;
        _isPlaybackActive = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing) {
          return;
        }
        _playerKey.currentState?.preparePlaybackPipeline();
        _playerKey.currentState?.startDeferredPlayback();
      });
      return;
    }
    final player = _playerKey.currentState;
    if (player == null || !player.isPlaybackPipelineReady) {
      return;
    }
    final playing = await player.togglePlayback();
    if (!mounted || _closing || playing == null) {
      return;
    }
    if (playing) {
      _markPlaybackActive();
    } else {
      _markPlaybackPaused();
    }
  }

  Future<void> _showVideoActionMenu() async {
    if (_closing) return;
    final player = _playerKey.currentState;
    await showMediaPreviewVideoActions(
      context: context,
      onDownload: _saveVideo,
      onForward: _currentItem.forwardFn ?? widget.forwardFn,
      onDelete: (_currentItem.deleteFn ?? widget.deleteFn) == null
          ? null
          : _handleDelete,
      onOpenMedia: null,
      onPictureInPicture: Platform.isAndroid
          ? () async {
              final ok = await player?.enablePictureInPicture();
              if (ok == true && mounted && !_closing) _close();
            }
          : null,
    );
  }

  Future<void> _saveResolvedGalleryVideo(ChatMediaPreviewItem item) async {
    final video = await item.resolveVideo!();
    if (!mounted || _closing) return;
    await saveChatVideoMessage(
        context: context,
        message: item.message,
        videoElement: video,
        model: model);
  }

  Future<void> _saveVideo() {
    if (widget._useGallery && _currentItem.resolveVideo != null) {
      return _saveResolvedGalleryVideo(_currentItem);
    }
    if (!widget._useGallery && widget.saveVideoFn != null) {
      return widget.saveVideoFn!();
    }
    return saveChatVideoMessage(
      context: context,
      message: _currentMessage,
      videoElement: _currentVideoElement,
      model: model,
    );
  }

  @override
  void dispose() {
    _closing = true;
    _playerCommitDebounce?.cancel();
    _slideDismissController.dispose();
    _heroModeEnabled.dispose();
    _slideMetrics.dispose();
    _entranceLatch.dispose();
    _revealHiddenHeroes();
    _galleryPageController.dispose();
    _attachmentChanges.dispose();
    _chromeTick.dispose();
    super.dispose();
  }

  Widget _buildPreviewChrome(Animation<double> routeAnimation) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([_slideMetrics, _chromeTick, routeAnimation]),
      builder: (context, _) {
        if (!(PlatformUtils().isMobile ||
            PlatformUtils().isWindows ||
            PlatformUtils().isMacOS)) {
          return const SizedBox.shrink();
        }
        return MediaPreviewVideoChrome(
          key: _videoChromeKey,
          playerKey: _playerKey,
          attachmentChanges: _attachmentChanges,
          title: MediaPreviewHeaderUtils.titleForMessage(_currentMessage),
          subtitle: MediaPreviewHeaderUtils.subtitleForMessage(
            _currentMessage.timestamp,
          ),
          galleryIndicator: _items.length > 1
              ? chatMediaGalleryPageLabel(
                  indexOldestFirst: _currentIndex, count: _items.length)
              : null,
          isPlaying: _isPlaybackActive,
          isReady: _shouldBuildPlayer &&
              !_heroOverlayVisible &&
              (_playerKey.currentState?.isPlaybackPipelineReady ?? false),
          active: !_closing &&
              !_slidePausedForDrag &&
              _playerPageIndex == _currentIndex,
          opacity: _slideMetrics.chromeOpacity * routeAnimation.value,
          onBack: _close,
          onTogglePlayback: _togglePlayback,
          onMore: _showVideoActionMenu,
          onForward: _currentItem.forwardFn ?? widget.forwardFn,
          onSave: _saveVideo,
          onOpenMedia: widget.onOpenMedia == null
              ? null
              : () {
                  if (_closing) return;
                  final openMedia = widget.onOpenMedia!;
                  _close();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    openMedia();
                  });
                },
          onDelete: (_currentItem.deleteFn ?? widget.deleteFn) == null
              ? null
              : _handleDelete,
        );
      },
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    return HeroMode(
      enabled: false,
      child: MediaPreviewSlideShell(
        slidePageKey: _slidePageKey,
        slideMetrics: _slideMetrics,
        entranceLatch: _entranceLatch,
        opaquePlatformBackdrop: true,
        slideType: SlideType.wholePage,
        onSlidingPage: _onSlidingPage,
        slideEndHandler: (
          Offset offset, {
          ExtendedImageSlidePageState? state,
          ScaleEndDetails? details,
        }) {
          final vy = details?.velocity.pixelsPerSecond.dy ?? 0;
          if (mediaPreviewShouldDismissForSlide(offset, vy)) {
            return _closeFromSlideDismiss(state, details, offset);
          }
          return null;
        },
        onClose: () {
          if (_closing) {
            return;
          }
          _close();
        },
        bodyBuilder: (context, orientation) => GestureDetector(
          onTap: _handlePreviewTap,
          onLongPress: () => _videoChromeKey.currentState?.showActions(),
          behavior: HitTestBehavior.translucent,
          child: _buildGalleryBody(orientation),
        ),
        chromeBuilder: _buildPreviewChrome,
      ),
    );
  }

  Future<void> _handleDelete() async {
    final deleteFn = _currentItem.deleteFn ?? widget.deleteFn;
    if (deleteFn == null) {
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(TIM_t('删除')),
        content: Text(TIM_t('确定删除这条消息吗？')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(TIM_t('取消')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(TIM_t('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await deleteFn();
    if (mounted) {
      _close();
    }
  }
}
