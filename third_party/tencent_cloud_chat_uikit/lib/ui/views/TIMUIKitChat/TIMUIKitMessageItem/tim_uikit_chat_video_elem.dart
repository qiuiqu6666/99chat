import 'dart:async';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_cover_diag.dart';
import 'dart:io';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_video_card.dart';

import 'package:tencent_cloud_chat_demo/utils/navigation_routes.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/screen_utils.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_video_cover_provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:open_file/open_file.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/tencent_cloud_chat_uikit.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/message/message_services.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_jitter_diag.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/ticker_settled_task.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/tim_uikit_media_upload_overlay.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitChat/TIMUIKitMessageItem/TIMUIKitMessageReaction/tim_uikit_message_reaction_wrapper.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_gallery_session.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_send_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_payload.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_debug.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_media_navigation.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/forward_message_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/wide_popup.dart';
import 'package:url_launcher/url_launcher.dart';

class TIMUIKitVideoElem extends StatefulWidget {
  final V2TimMessage message;
  final bool isShowJump;
  final VoidCallback? clearJump;
  final String? isFrom;
  final TUIChatSeparateViewModel chatModel;
  final bool? isShowMessageReaction;

  const TIMUIKitVideoElem(this.message,
      {Key? key,
      this.isShowJump = false,
      this.clearJump,
      this.isFrom,
      this.isShowMessageReaction,
      required this.chatModel})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _TIMUIKitVideoElemState();
}

class _TIMUIKitVideoElemState extends TIMUIKitState<TIMUIKitVideoElem>
    with TickerSettledTaskMixin<TIMUIKitVideoElem> {
  static const BorderRadius _videoBorderRadius =
      TIMUIKitVideoCard.borderRadius;

  final MessageService _messageService = serviceLocator<MessageService>();
  final TUIChatGlobalModel globalModel = serviceLocator<TUIChatGlobalModel>();
  late V2TimVideoElem stateElement = widget.message.videoElem!;
  late final Set<String> _coverDiagStages = {};
  late final Stopwatch _coverDiagClock = Stopwatch()..start();

  void _coverDiag(String stage, String details) {
    if (!ChatCoverDiag.canLog || !_coverDiagStages.add(stage)) return;
    ChatCoverDiag.log(stage, widget.message.msgID ?? widget.message.id ?? '-',
        'conv=${widget.chatModel.conversationID} ageMs=${_coverDiagClock.elapsedMilliseconds} $details');
  }

  int get _uploadProgress => TimUIKitMediaUploadOverlay.resolveUploadProgress(
      globalModel, widget.message);

  bool get _showUploadOverlay =>
      TimUIKitMediaUploadOverlay.shouldShowUploadOverlay(
        widget.message,
        _uploadProgress,
      );

  @override
  void didUpdateWidget(covariant TIMUIKitVideoElem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.status != widget.message.status ||
        oldWidget.message.msgID != widget.message.msgID) {
      setState(() {});
    }
    final nextElem = widget.message.videoElem;
    if (nextElem != null && !identical(nextElem, stateElement)) {
      stateElement = nextElem;
    }
  }

  Widget errorDisplay(TUITheme? theme) {
    return Container(
      decoration: BoxDecoration(
          border: Border.all(
        width: 1,
        color: Colors.black12,
      )),
      height: 100,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: theme?.cautionColor,
              size: 16,
            ),
            Text(
              TIM_t("视频加载失败"),
              style: TextStyle(color: theme?.cautionColor),
            ),
          ],
        ),
      ),
    );
  }

  int _videoSnapshotDecodeWidth() {
    final deferHeavy = () {
      try {
        return serviceLocator<TUIChatGlobalModel>()
            .shouldSkipHeavyChatListPresentation;
      } catch (_) {
        return false;
      }
    }();
    final full = chatVideoBubbleSnapshotDecodeWidth(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    if (!deferHeavy) {
      return full;
    }
    return (full / 2).round().clamp(64, full);
  }

  Widget generateSnapshot(TUITheme theme, int height) {
    final cover = chatVideoCoverProvider(stateElement);
    if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
      _coverDiag('video_source', 'provider=${cover?.runtimeType} keyHash=${cover?.hashCode} localField=${stateElement.localSnapshotUrl?.isNotEmpty == true || stateElement.snapshotPath?.isNotEmpty == true} remoteField=${stateElement.snapshotUrl?.isNotEmpty == true}');
    }
    if (cover != null) {
      return Image(
        image: cover,
        frameBuilder: (_, child, frame, synchronous) {
          if (ChatCoverDiag.enabled && ChatCoverDiag.canLog) {
            _coverDiag(frame != null || synchronous ? 'video_frame' : 'video_wait_frame',
                'sync=$synchronous frame=$frame');
          }
          return child;
        },
        fit: BoxFit.fitWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            _videoSnapshotPlaceholder(theme, height, animated: false),
      );
    }
    final decodeWidth = _videoSnapshotDecodeWidth();
    final localSnapshot = existingLocalMediaPath(stateElement.snapshotPath) ??
        existingLocalMediaPath(stateElement.localSnapshotUrl);
    if (localSnapshot != null) {
      if (!isUsableVideoSnapshotFile(localSnapshot)) {
        return _videoSnapshotPlaceholder(theme, height);
      }
      return Image.file(
        File(localSnapshot),
        fit: BoxFit.fitWidth,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    final snapshotUrl = TencentUtils.checkString(stateElement.snapshotUrl);
    if (snapshotUrl == null) {
      return _videoSnapshotPlaceholder(theme, height);
    }
    if (!TickerMode.of(context)) {
      return _videoSnapshotPlaceholder(theme, height, animated: false);
    }
    return Image.network(
      snapshotUrl,
      fit: BoxFit.fitWidth,
      cacheWidth: decodeWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _videoSnapshotPlaceholder(TUITheme theme, int height,
      {bool animated = true}) {
    return Container(
      decoration: BoxDecoration(
          borderRadius: _videoBorderRadius,
          border: Border.all(
            width: 1,
            color: Colors.black12,
          )),
      height: double.parse(height.toString()),
      child: animated
          ? Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LoadingAnimationWidget.staggeredDotsWave(
                    color: theme.weakTextColor ?? Colors.grey,
                    size: 28,
                  )
                ],
              ),
            )
          : null,
    );
  }

  downloadMessageDetailAndSave() async {
    final msgID = TencentUtils.checkString(widget.message.msgID);
    if (msgID == null) {
      return;
    }
    ChatJitterDiag.log(
      'video_hydrate_start',
      msgId: msgID,
      extras: <String, Object?>{
        'hasVideoUrl': TencentUtils.checkString(stateElement.videoUrl) != null,
        'hasSnapshotUrl':
            TencentUtils.checkString(stateElement.snapshotUrl) != null,
        'snapW': stateElement.snapshotWidth,
        'snapH': stateElement.snapshotHeight,
      },
    );
    if (TencentUtils.checkString(widget.message.videoElem!.videoUrl) == null) {
      final response = await _messageService.getMessageOnlineUrl(msgID: msgID);
      if (response.data?.videoElem != null) {
        final merged = mergeVideoElemKeepingLocalPreview(
          stateElement,
          response.data!.videoElem!,
        );
        widget.message.videoElem = merged;
        if (mounted) {
          final visualChanged =
              stateElement.snapshotUrl != merged.snapshotUrl ||
                  stateElement.localSnapshotUrl != merged.localSnapshotUrl ||
                  stateElement.snapshotPath != merged.snapshotPath ||
                  stateElement.snapshotWidth != merged.snapshotWidth ||
                  stateElement.snapshotHeight != merged.snapshotHeight ||
                  stateElement.videoUrl != merged.videoUrl;
          if (visualChanged) {
            ChatJitterDiag.logSetState(
              widget: 'TIMUIKitVideoElem',
              reason: 'getMessageOnlineUrl_merge',
              msgId: msgID,
              extras: <String, Object?>{
                'snapW':
                    '${stateElement.snapshotWidth}->${merged.snapshotWidth}',
                'snapH':
                    '${stateElement.snapshotHeight}->${merged.snapshotHeight}',
              },
            );
            setState(() => stateElement = merged);
          } else {
            stateElement = merged;
          }
        }
      }
    }
    if (!PlatformUtils().isWeb) {
      final elem = widget.message.videoElem!;
      final localVideo = TencentUtils.checkString(elem.localVideoUrl);
      final needsVideoDownload =
          localVideo == null || !File(localVideo).existsSync();
      final hasVideoRemote = TencentUtils.checkString(elem.videoUrl) != null;
      if (needsVideoDownload && hasVideoRemote) {
        unawaited(_messageService.downloadMessage(
          msgID: msgID,
          messageType: 5,
          imageType: 0,
          isSnapshot: false,
        ));
      } else if (needsVideoDownload) {
        ChatJitterDiag.log(
          'video_download_skip',
          msgId: msgID,
          extras: const <String, Object?>{
            'kind': 'video',
            'reason': 'no_remote_url'
          },
        );
      }
      final localSnapshot = TencentUtils.checkString(elem.localSnapshotUrl);
      final needsSnapshotDownload =
          localSnapshot == null || !File(localSnapshot).existsSync();
      final hasSnapshotRemote =
          TencentUtils.checkString(elem.snapshotUrl) != null;
      if (needsSnapshotDownload && hasSnapshotRemote) {
        unawaited(_messageService.downloadMessage(
          msgID: msgID,
          messageType: 5,
          imageType: 0,
          isSnapshot: true,
        ));
      } else if (needsSnapshotDownload) {
        ChatJitterDiag.log(
          'video_download_skip',
          msgId: msgID,
          extras: const <String, Object?>{
            'kind': 'snapshot',
            'reason': 'no_remote_url',
          },
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 进场转场期间不发起在线信息回填/封面下载：转场中 setState 会让
      // 气泡尺寸/内容中途变化（进入聊天页视频气泡抖动的来源），等
      // TickerMode 打开（转场结束）后再执行。
      runWhenTickerEnabled(
        downloadMessageDetailAndSave,
        debugLabel: 'TIMUIKitVideoElem',
      );
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void launchDesktopFile(String path) {
    if (PlatformUtils().isWindows) {
      OpenFile.open(path);
    } else {
      launchUrl(Uri.file(path));
    }
  }

  Future<void> _openDesktopVideoPreview() async {
    final videoElem = widget.message.videoElem;
    if (videoElem == null) {
      return;
    }
    final videoUrl = TencentUtils.checkString(videoElem.videoUrl);
    final localVideoUrl = TencentUtils.checkString(videoElem.localVideoUrl);
    final videoPath = TencentUtils.checkString(videoElem.videoPath);
    final hasLocal = (localVideoUrl != null && File(localVideoUrl).existsSync()) ||
        (videoPath != null && File(videoPath).existsSync());
    if (videoUrl == null && !hasLocal) {
      onTIMCallback(TIMCallback(
          infoCode: 6660414,
          infoRecommendText: TIM_t("正在下载中"),
          type: TIMCallbackType.INFO));
      return;
    }
    var payload = DesktopMediaPreviewPayload.fromChat(
      originList: widget.chatModel.getGalleryOriginMessageList(),
      tappedMessage: widget.message,
      types: kChatMediaPreviewAllTypes,
      heroTagBuilder: _heroTagForMessage,
      conversationID: widget.chatModel.conversationID,
      conversationType: widget.chatModel.conversationType,
    );
    final items = payload['items'];
    if (items is! List || items.isEmpty) {
      payload = DesktopMediaPreviewPayload.video(
        source: 'chat',
        videoUrl: videoUrl,
        localPath: localVideoUrl ?? videoPath,
        allowForward: true,
      );
    }
    final opened = await DesktopMediaPreviewHook.tryOpen(payload);
    if (opened || DesktopMediaPreviewHook.openOrFocus != null) {
      return;
    }
    if (localVideoUrl != null) {
      launchDesktopFile(localVideoUrl);
    } else if (videoPath != null && File(videoPath).existsSync()) {
      launchDesktopFile(videoPath);
    } else {
      onTIMCallback(TIMCallback(
          infoCode: 6660414,
          infoRecommendText: TIM_t("正在下载中"),
          type: TIMCallbackType.INFO));
    }
  }

  Future<void> _forwardPreviewMessage(V2TimMessage message) async {
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t("发送失败消息不支持转发！"),
      ));
      return;
    }
    widget.chatModel.updateMultiSelectStatus(false);
    widget.chatModel.setMessageItemChecked(message, true);
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      TUIKitScreenUtils.getFormFactor(context) == DeviceType.Desktop
          ? MaterialPageRoute(
              builder: (context) => ForwardMessageScreen(
                conversationType: widget.chatModel.conversationType ?? ConvType.c2c,
                model: widget.chatModel,
              ),
            )
          : NavigationRoutes.cupertino(
              fullscreenDialog: true,
              builder: (context) => ForwardMessageScreen(
                conversationType: widget.chatModel.conversationType ?? ConvType.c2c,
                model: widget.chatModel,
              ),
            ),
    );
  }

  Future<void> _deletePreviewMessage(V2TimMessage message) async {
    final msgID = message.msgID;
    if (msgID == null || msgID.isEmpty) {
      return;
    }
    if (message.isSelf == true) {
      await widget.chatModel.revokeMsg(msgID, false);
    } else {
      await widget.chatModel.deleteMsg(msgID);
    }
  }

  void _openConversationMediaPageFromPreview() {
    openChatConversationMediaPage(
      context: context,
      chatModel: widget.chatModel,
    );
  }

  String _heroTagForMessage(V2TimMessage message) {
    return "${message.msgID ?? message.id ?? message.timestamp ?? DateTime.now().millisecondsSinceEpoch}${widget.isFrom}";
  }

  ChatMediaPreviewBuildResult _buildVideoPreviewItems(
    List<V2TimMessage> originList,
  ) {
    return buildChatMediaPreviewItems(
      originList: originList,
      tappedMessage: widget.message,
      types: kChatMediaPreviewAllTypes,
      heroTagBuilder: _heroTagForMessage,
      onForward: _forwardPreviewMessage,
      onDelete: _deletePreviewMessage,
    );
  }

  Future<void> _openMobileMediaPreview(String heroTag) async {
    // 长按出菜单后，子级 Tap 仍会在抬手时完成（自定义长按 450ms < Flutter tap
    // 拒绝阈值 500ms）。与图片气泡一致：菜单打开期间禁止进全屏。
    if (globalModel.isMessageContextMenuOverlayOpen) {
      return;
    }
    final convId = widget.chatModel.conversationID;
    final session = ChatMediaGalleryLiveSession(
      chatModel: widget.chatModel,
      tappedMessage: widget.message,
      types: kChatMediaPreviewAllTypes,
      initialPreview: _buildVideoPreviewItems(
        widget.chatModel.getGalleryOriginMessageList(),
      ),
      rebuildPreview: _buildVideoPreviewItems,
      isMounted: () => mounted,
    );
    MediaPreviewDebug.log('open_from_video_elem', {
      'mixed': session.preview.isMixed,
      'count': session.preview.items.length,
      'initial': session.preview.initialIndex,
      'tapped': chatMediaPreviewMessageID(widget.message) ?? '-',
      'items': MediaPreviewDebug.itemsSummary(session.preview.items),
    });
    globalModel.saveScrollBeforeMediaPreview(
      convId,
      anchorMessageID: chatMediaPreviewMessageID(widget.message),
    );

    var didPushPreview = false;
    try {
      if (!mounted) {
        return;
      }
      final videoItems = session.preview.items
          .where((item) => item.type == ChatMediaPreviewType.video)
          .toList();
      final tappedVideoIndex = videoItems.indexWhere(
        (item) => isSameChatMediaMessage(item.message, widget.message),
      );
      if (videoItems.isEmpty || tappedVideoIndex < 0) {
        return;
      }
      final tappedVideo = videoItems[tappedVideoIndex];
      MediaPreviewDebug.log('push_video_screen', {
        'mixed': session.preview.isMixed,
        'videoCount': videoItems.length,
        'initial': tappedVideoIndex,
      });
      didPushPreview = true;
      await pushMediaPreview(
        context: context,
        requiresOpaquePlatformView: true,
        restoreChatScrollConversationID: convId,
        child: StatefulBuilder(
          builder: (context, setPreviewState) {
            session.ensureStarted(() => setPreviewState(() {}));
            return VideoScreen(
              message: tappedVideo.message,
              heroTag: tappedVideo.heroTag,
              videoElement: tappedVideo.videoElement ?? stateElement,
              preferOnlinePlayback: true,
              forwardFn: () => _forwardPreviewMessage(widget.message),
              deleteFn: () => _deletePreviewMessage(widget.message),
              onOpenMedia: _openConversationMediaPageFromPreview,
              galleryItems: videoItems.length > 1 ? videoItems : null,
              initialIndex: tappedVideoIndex,
            );
          },
        ),
      );
    } finally {
      session.dispose();
      // 未真正 push 时仍须解锁；已 push 则由 pushMediaPreview finally 负责。
      if (!didPushPreview) {
        globalModel.restoreScrollAfterMediaPreview(convId);
      }
      MediaPreviewHeroRegistry.instance.revealAll({heroTag});
    }
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final convId = widget.chatModel.conversationID;
    final theme = value.theme;
    final heroTag =
        "${widget.message.msgID ?? widget.message.id ?? widget.message.timestamp ?? DateTime.now().millisecondsSinceEpoch}${widget.isFrom}";
    final hasSnapshot = videoElemHasSnapshotSource(stateElement);
    final hasVideoSource =
        TencentUtils.checkString(stateElement.videoPath) != null ||
            TencentUtils.checkString(stateElement.localVideoUrl) != null ||
            TencentUtils.checkString(stateElement.videoUrl) != null;
    final shouldShowPlayButton =
        hasSnapshot && hasVideoSource && !_showUploadOverlay;

    return GestureDetector(
      onTap: () {
        if (!PlatformUtils().isDesktop &&
            globalModel.isMessageContextMenuOverlayOpen) {
          return;
        }
        if (PlatformUtils().isWeb) {
          final url = widget.message.videoElem?.videoUrl ??
              widget.message.videoElem?.videoPath ??
              "";
          TUIKitWidePopup.showMedia(
              context: context,
              mediaURL: url,
              onClickOrigin: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ));
          return;
        }
        if (PlatformUtils().isDesktop) {
          if (PlatformUtils().isWinMacDesktop) {
            unawaited(_openDesktopVideoPreview());
            return;
          }
          final videoElem = widget.message.videoElem;
          if (videoElem != null) {
            final localVideoUrl =
                TencentUtils.checkString(videoElem.localVideoUrl);
            final videoPath = TencentUtils.checkString(videoElem.videoPath);
            final videoUrl = videoElem.videoUrl;
            if (localVideoUrl != null) {
              launchDesktopFile(localVideoUrl);
              // todo
              // TUIKitWidePopup.showMedia(
              //     context: context,
              //     mediaPath: localVideoUrl,
              //     onClickOrigin: () => launchDesktopFile(localVideoUrl));
            } else if (videoPath != null && File(videoPath).existsSync()) {
              launchDesktopFile(videoPath);
              // todo
              // TUIKitWidePopup.showMedia(
              //     context: context,
              //     mediaPath: videoPath,
              //     onClickOrigin: () => launchDesktopFile(videoPath));
            } else if (TencentUtils.isTextNotEmpty(videoUrl)) {
              onTIMCallback(TIMCallback(
                  infoCode: 6660414,
                  infoRecommendText: TIM_t("正在下载中"),
                  type: TIMCallbackType.INFO));
            }
          }
        } else {
          _openMobileMediaPreview(heroTag);
        }
      },
      child: PreviewHero(
          tag: heroTag,
          placeholderBuilder: (context, size, child) {
            return ClipRRect(
              borderRadius: _videoBorderRadius,
              child: SizedBox(
                width: size.width,
                height: size.height,
              ),
            );
          },
          child: TIMUIKitMessageReactionWrapper(
              chatModel: widget.chatModel,
              message: widget.message,
              isShowJump: widget.isShowJump,
              isShowMessageReaction: widget.isShowMessageReaction ?? true,
              clearJump: widget.clearJump,
              isFromSelf: widget.message.isSelf ?? true,
              child: TIMUIKitVideoCard(
                aspectRatio: resolveVideoAspectRatio(stateElement),
                cover: generateSnapshot(theme, stateElement.snapshotHeight ?? 100),
                durationMs: stateElement.duration == null ? null : stateElement.duration! * 1000,
                showPlayButton: shouldShowPlayButton,
                overlay: TimUIKitMessageUploadOverlayLayer(
                  message: widget.message,
                  conversationID: convId,
                  globalModel: globalModel,
                ),
              ))),
    );
  }
}
