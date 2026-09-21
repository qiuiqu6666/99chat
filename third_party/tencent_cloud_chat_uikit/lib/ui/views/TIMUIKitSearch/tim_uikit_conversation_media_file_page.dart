import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_callback.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_state.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_search_view_model.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_uikit/theme/tui_theme.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_hook.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/desktop_media_preview_payload.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_edit/image_preview_editor.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/image_mem_cache_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/time_ago.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_asset_utils.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/conversation_image_save.dart';
import 'package:tencent_cloud_chat_uikit/ui/views/TIMUIKitSearch/tim_uikit_search_not_support.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/tim_uikit_back_button.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';

class _ConversationMediaFileHeaderStyle {
  const _ConversationMediaFileHeaderStyle({
    required this.appBarBackground,
    required this.backIconColor,
    required this.segmentTrack,
    required this.segmentSelected,
    required this.segmentSelectedText,
    required this.segmentUnselectedText,
  });

  final Color appBarBackground;
  final Color backIconColor;
  final Color segmentTrack;
  final Color segmentSelected;
  final Color segmentSelectedText;
  final Color segmentUnselectedText;
}

class TIMUIKitConversationMediaFilePage extends StatefulWidget {
  const TIMUIKitConversationMediaFilePage({
    super.key,
    required this.conversation,
    required this.onTapMessage,
    this.initialTab = ConversationAssetTab.media,
    this.embedded = false,
  });

  final V2TimConversation conversation;
  final ConversationAssetTab initialTab;
  final void Function(V2TimConversation conversation, V2TimMessage message)
      onTapMessage;

  /// 嵌在桌面右栏时隐藏自带返回，避免与外层标题栏叠两层。
  final bool embedded;

  @override
  State<TIMUIKitConversationMediaFilePage> createState() =>
      _TIMUIKitConversationMediaFilePageState();
}

class _TIMUIKitConversationMediaFilePageState
    extends TIMUIKitState<TIMUIKitConversationMediaFilePage> {
  final TUISearchViewModel _model = serviceLocator<TUISearchViewModel>();
  final TUIChatGlobalModel _chatModel = serviceLocator<TUIChatGlobalModel>();
  late ConversationAssetTab _tab;
  String? _busyFileId;
  final ScrollController _scrollController = ScrollController();
  bool _ensureCurrentTabDataScheduled = false;
  // 当前 Tab 可能需要连续翻过多页历史才能找到第一条匹配消息。在确认
  // 已找到足够数据或彻底没有更多历史前，保持加载态，避免页间短暂显示空态。
  bool _isFillingCurrentTab = true;
  bool _paginationLoadScheduled = false;
  String _lastAssetUiSignature = '';
  double? _pendingGridScrollOffset;
  bool _isRestoringGridScroll = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _lastAssetUiSignature = _assetUiSignature();
    _model.addListener(_onModelChanged);
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (!mounted) {
      return;
    }
    final signature = _assetUiSignature();
    if (signature != _lastAssetUiSignature) {
      _lastAssetUiSignature = signature;
      final fillingDone =
          _currentTabHasEnoughData || !_model.conversationAssetHasMore;
      setState(() {
        if (fillingDone) {
          _isFillingCurrentTab = false;
        }
      });
    }
    _scheduleEnsureCurrentTabData();
  }

  String _assetUiSignature() {
    final media = _model.conversationMediaMessages;
    final files = _model.conversationFileMessages;
    final mediaTail = media.isEmpty ? '' : (media.last.msgID ?? media.last.id);
    final fileTail = files.isEmpty ? '' : (files.last.msgID ?? files.last.id);
    return '${media.length}|$mediaTail|${files.length}|$fileTail|'
        '${_model.conversationAssetLoading}|${_model.conversationAssetHasMore}';
  }

  void _onScroll() {
    if (_isRestoringGridScroll || !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    if (_model.conversationAssetLoading || !_model.conversationAssetHasMore) {
      return;
    }
    if (_paginationLoadScheduled) {
      return;
    }
    _paginationLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paginationLoadScheduled = false;
      if (!mounted ||
          _model.conversationAssetLoading ||
          !_model.conversationAssetHasMore) {
        return;
      }
      _load(reset: false);
    });
  }

  void _load({required bool reset}) {
    if (reset && mounted) {
      _isFillingCurrentTab = true;
    }
    final conversation = widget.conversation;
    _model.loadConversationAssets(
      conversation.conversationID,
      reset: reset,
      userID: conversation.userID,
      groupID: conversation.groupID,
    );
  }

  @override
  void didUpdateWidget(covariant TIMUIKitConversationMediaFilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.conversationID !=
        widget.conversation.conversationID) {
      _load(reset: true);
    }
  }

  static const int _minInitialTabItems = 32;

  int get _currentTabItemCount {
    return _tab == ConversationAssetTab.media
        ? _model.conversationMediaMessages.length
        : _model.conversationFileMessages.length;
  }

  bool get _currentTabHasEnoughData {
    return _currentTabItemCount >= _minInitialTabItems;
  }

  void _scheduleEnsureCurrentTabData() {
    if (_ensureCurrentTabDataScheduled) {
      return;
    }
    _ensureCurrentTabDataScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCurrentTabDataScheduled = false;
      if (!mounted) {
        return;
      }
      if (_currentTabHasEnoughData || !_model.conversationAssetHasMore) {
        if (_isFillingCurrentTab &&
            (_currentTabHasEnoughData || !_model.conversationAssetHasMore)) {
          setState(() => _isFillingCurrentTab = false);
        }
        return;
      }
      if (_model.conversationAssetLoading) {
        return;
      }
      _load(reset: false);
    });
  }

  void _switchTab(ConversationAssetTab tab) {
    if (_tab == tab) {
      return;
    }
    setState(() {
      _tab = tab;
      _isFillingCurrentTab =
          !_currentTabHasEnoughData && _model.conversationAssetHasMore;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _scheduleEnsureCurrentTabData();
  }

  String? _nonEmpty(String? raw) {
    final text = raw?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _localFilePath(V2TimMessage message) {
    final id = message.msgID;
    final candidates = <String?>[
      _nonEmpty(_chatModel.getFileMessageLocation(id)),
      _nonEmpty(message.fileElem?.localUrl),
      _nonEmpty(message.fileElem?.path),
    ];
    for (final path in candidates) {
      if (path != null && File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  Future<void> _openLocalFile(String path) async {
    try {
      if (PlatformUtils().isDesktop && !PlatformUtils().isWindows) {
        await launchUrl(Uri.file(path));
        return;
      }
      await OpenFile.open(path);
    } catch (_) {
      await OpenFile.open(path);
    }
  }

  Future<String?> _downloadRemoteFile(V2TimMessage message, String fileUrl) async {
    final response = await http.get(Uri.parse(fileUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final dir = await getTemporaryDirectory();
    final rawName = message.fileElem?.fileName?.trim();
    final fallback = Uri.parse(fileUrl).pathSegments.isEmpty
        ? 'file'
        : Uri.parse(fileUrl).pathSegments.last;
    final fileName = (rawName != null && rawName.isNotEmpty) ? rawName : fallback;
    final msgId = message.msgID ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final savePath = '${dir.path}/${msgId}_$fileName';
    await File(savePath).writeAsBytes(response.bodyBytes);
    if (message.msgID != null && message.msgID!.isNotEmpty) {
      _chatModel.setFileMessageLocation(message.msgID!, savePath);
      _chatModel.setMessageProgress(message.msgID!, 100);
    }
    return savePath;
  }

  Future<void> _openOrDownloadFile(V2TimMessage message) async {
    if (PlatformUtils().isWeb) {
      widget.onTapMessage(widget.conversation, message);
      return;
    }
    final fileId = message.msgID ?? message.id ?? message.fileElem?.fileName;
    if (fileId != null && fileId == _busyFileId) {
      onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('正在下载中'),
        infoCode: 6660416,
      ));
      return;
    }
    final existing = _localFilePath(message);
    if (existing != null) {
      await _openLocalFile(existing);
      return;
    }
    if (mounted) {
      setState(() => _busyFileId = fileId);
    }
    try {
      final remoteUrl = _nonEmpty(message.fileElem?.url);
      if (remoteUrl != null) {
        onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t('正在下载中'),
          infoCode: 6660416,
        ));
        final saved = await _downloadRemoteFile(message, remoteUrl);
        if (!mounted) {
          return;
        }
        if (saved != null) {
          await _openLocalFile(saved);
        } else {
          onTIMCallback(TIMCallback(
            type: TIMCallbackType.INFO,
            infoRecommendText: TIM_t('文件下载失败'),
            infoCode: 6660416,
          ));
        }
        return;
      }
      final msgID = message.msgID?.trim() ?? '';
      if (msgID.isNotEmpty) {
        _chatModel.addWaitingList(msgID);
        await _chatModel.downloadFile();
        onTIMCallback(TIMCallback(
          type: TIMCallbackType.INFO,
          infoRecommendText: TIM_t('正在下载中'),
          infoCode: 6660416,
        ));
        return;
      }
      onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('文件下载失败'),
        infoCode: 6660416,
      ));
    } catch (_) {
      onTIMCallback(TIMCallback(
        type: TIMCallbackType.INFO,
        infoRecommendText: TIM_t('文件下载失败'),
        infoCode: 6660416,
      ));
    } finally {
      if (mounted && _busyFileId == fileId) {
        setState(() => _busyFileId = null);
      }
    }
  }

  Widget _buildPaginationSpinner(TUITheme theme) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (theme.chatBgColor ?? Colors.white).withValues(alpha: 0.92),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _saveGridScrollBeforeMediaPreview() {
    if (_scrollController.hasClients && _scrollController.offset.isFinite) {
      _pendingGridScrollOffset = _scrollController.offset;
    }
  }

  void _restoreGridScrollAfterMediaPreview() {
    final offset = _pendingGridScrollOffset;
    if (offset == null) {
      return;
    }
    _pendingGridScrollOffset = null;
    _isRestoringGridScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isRestoringGridScroll = false;
        return;
      }
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final target = offset.clamp(0.0, maxExtent);
        if ((_scrollController.offset - target).abs() > 0.5) {
          _scrollController.jumpTo(target);
        }
      }
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          _isRestoringGridScroll = false;
        }
      });
    });
  }

  void _onMediaPreviewClosed(Object heroTag) {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      MediaPreviewHeroRegistry.instance.revealAll({heroTag});
      _restoreGridScrollAfterMediaPreview();
    });
  }

  /// 与网格缩略图同源，避免 resolve 失败时全屏无 provider。
  ImageProvider? _fallbackProviderFromGridUrl(V2TimMessage message) {
    final url = resolveConversationMediaPreviewUrl(message);
    if (url == null || url.isEmpty) {
      return null;
    }
    if (url.startsWith('http')) {
      return CachedNetworkImageProvider(url);
    }
    if (!PlatformUtils().isWeb) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          return FileImage(file);
        }
      } catch (_) {}
    }
    return null;
  }

  void _openMediaPreview(
    BuildContext context,
    TUITheme theme,
    V2TimMessage message,
    List<V2TimMessage> items,
  ) {
    unawaited(_openMediaPreviewImpl(context, theme, message, items));
  }

  Future<void> _openMediaPreviewImpl(
    BuildContext context,
    TUITheme theme,
    V2TimMessage message,
    List<V2TimMessage> items,
  ) async {
    final isImage =
        message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
    if (PlatformUtils().isWinMacDesktop) {
      final payload = DesktopMediaPreviewPayload.fromChat(
        originList: items,
        tappedMessage: message,
        types: isImage
            ? kChatMediaPreviewImageTypes
            : kChatMediaPreviewAllTypes,
        heroTagBuilder: conversationMediaHeroTag,
        conversationID: widget.conversation.conversationID,
        conversationType: widget.conversation.type == 2
            ? ConvType.group
            : ConvType.c2c,
      );
      final previewItems = payload['items'];
      if (previewItems is List && previewItems.isNotEmpty) {
        final opened = await DesktopMediaPreviewHook.tryOpen(payload);
        if (opened) {
          return;
        }
      }
    }
    if (!mounted) {
      return;
    }
    Future<void> downloadImage(V2TimMessage target) {
      return saveConversationImageToGallery(
        context: context,
        message: target,
        theme: theme,
      );
    }

    Future<void> editImage(
      V2TimMessage target,
      BuildContext previewContext,
    ) {
      return ImagePreviewEditor.editMessageImageAndSave(
        previewContext: previewContext,
        message: target,
      );
    }

    // 对齐聊天气泡：点图片只收图片走 ImageScreen；点视频再走视频/混滑。
    // 旧逻辑用 AllTypes，会话里一旦有视频就进 ChatMediaGalleryScreen，
    // 与聊天进全屏路径不一致，且网格无源 Hero 易出空罩。
    final preview = buildChatMediaPreviewItems(
      originList: items,
      tappedMessage: message,
      types: isImage
          ? kChatMediaPreviewImageTypes
          : kChatMediaPreviewAllTypes,
      heroTagBuilder: conversationMediaHeroTag,
      onDownload: downloadImage,
      onEdit: ImagePreviewEditor.isSupported ? editImage : null,
    );
    if (preview.items.isEmpty) {
      return;
    }

    final heroTag = conversationMediaHeroTag(message);
    _saveGridScrollBeforeMediaPreview();

    var closingHeroTag = heroTag.toString();
    void onPreviewClosing(String? messageID, String currentHeroTag) {
      closingHeroTag = currentHeroTag;
    }

    if (!isImage && preview.isMixed) {
      pushMediaPreview(
        context: context,
        enableGestureBack: false,
        requiresOpaquePlatformView: true,
        transitionDuration: Duration.zero,
        child: ChatMediaGalleryScreen(
          items: preview.items,
          initialIndex: preview.initialIndex,
          sourceMessage: message,
          enableHero: false,
          onClosing: onPreviewClosing,
        ),
      ).then((_) => _onMediaPreviewClosed(closingHeroTag));
      return;
    }

    if (!isImage && preview.hasVideo) {
      final videoItems = preview.items
          .where((item) => item.type == ChatMediaPreviewType.video)
          .toList();
      final current = preview.currentItem;
      final videoElem = current?.videoElement ?? message.videoElem;
      if (videoElem == null || current == null) {
        return;
      }
      pushMediaPreview(
        context: context,
        transitionDuration: Duration.zero,
        requiresOpaquePlatformView: true,
        child: VideoScreen(
          message: current.message,
          heroTag: current.heroTag,
          videoElement: videoElem,
          preferOnlinePlayback: true,
          galleryItems: videoItems.length > 1 ? videoItems : null,
          initialIndex: preview.initialIndex.clamp(
            0,
            videoItems.isEmpty ? 0 : videoItems.length - 1,
          ),
        ),
      ).then((_) => _onMediaPreviewClosed(closingHeroTag));
      return;
    }

    // —— 图片：与 tim_uikit_chat_image_elem._openMobileImagePreview 同构 ——
    final galleryItems = preview.items
        .where((item) => item.type == ChatMediaPreviewType.image)
        .map((item) => item.toImageGalleryItem())
        .toList();
    final currentItem = preview.currentItem;
    if (galleryItems.isEmpty || currentItem == null) {
      return;
    }

    final gridFallback = _fallbackProviderFromGridUrl(message);
    final imageProvider =
        currentItem.imageProvider ?? gridFallback;
    if (imageProvider == null) {
      return;
    }
    final placeholder = currentItem.placeholderImageProvider ??
        (identical(imageProvider, gridFallback) ? null : gridFallback);

    pushMediaPreview(
      context: context,
      enableGestureBack: false,
      // 与聊天一致：不要零时长 Hero 入场；网格无源 Hero，关 enableHero。
      // 媒体页下层是浅灰网格，必须不透明黑底，避免「全屏灰看不见图」。
      requiresOpaquePlatformView: true,
      transitionDuration: Duration.zero,
      child: ImageScreen(
        imageProvider: imageProvider,
        placeholderImageProvider: placeholder,
        heroTag: currentItem.heroTag.toString(),
        messageID: currentItem.messageID ?? message.msgID,
        sourceMessage: message,
        headerTitle: currentItem.headerTitle,
        headerSubtitle: currentItem.headerSubtitle,
        galleryItems: galleryItems,
        initialIndex: preview.initialIndex.clamp(
          0,
          galleryItems.isEmpty ? 0 : galleryItems.length - 1,
        ),
        forceGalleryMode: true,
        enableHero: false,
        onClosing: onPreviewClosing,
        downloadFn: () => downloadImage(message),
        editFn: ImagePreviewEditor.isSupported
            ? (previewContext) => editImage(message, previewContext)
            : null,
      ),
    ).then((_) => _onMediaPreviewClosed(closingHeroTag));
  }

  void _onMediaItemTap(
    BuildContext context,
    TUITheme theme,
    V2TimMessage message,
    List<V2TimMessage> items,
  ) {
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE ||
        message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO) {
      _openMediaPreview(context, theme, message, items);
    }
  }

  List<V2TimMessage> get _currentItems {
    return _tab == ConversationAssetTab.media
        ? _model.conversationMediaMessages
        : _model.conversationFileMessages;
  }

  _ConversationMediaFileHeaderStyle _headerPalette(TUITheme theme) {
    final appBarBackground = theme.chatHeaderBgColor ??
        theme.appbarBgColor ??
        theme.wideBackgroundColor ??
        Colors.white;
    final backIconColor = theme.primaryColor ??
        theme.lightPrimaryColor ??
        theme.chatHeaderBackTextColor ??
        const Color(0xFF1E90FF);
    final isDarkAppBar =
        ThemeData.estimateBrightnessForColor(appBarBackground) ==
            Brightness.dark;
    final segmentTrack = isDarkAppBar
        ? (theme.conversationItemPinedBgColor ??
            theme.inputFillColor ??
            const Color(0xFF252525))
        : (theme.inputFillColor ?? const Color(0xFFEDEDED));
    final segmentSelected = isDarkAppBar
        ? (theme.weakDividerColor ??
            theme.conversationItemActiveBgColor ??
            const Color(0xFF2C2C2C))
        : (theme.conversationItemBgColor ?? Colors.white);
    final segmentUnselectedText =
        theme.weakTextColor ?? const Color(0xFF888888);
    final isDarkSelectedChip =
        ThemeData.estimateBrightnessForColor(segmentSelected) ==
            Brightness.dark;
    final segmentSelectedText = isDarkSelectedChip
        ? (theme.chatHeaderTitleTextColor ??
            theme.appbarTextColor ??
            theme.darkTextColor ??
            Colors.white)
        : (theme.appbarTextColor ?? theme.darkTextColor ?? Colors.black);
    return _ConversationMediaFileHeaderStyle(
      appBarBackground: appBarBackground,
      backIconColor: backIconColor,
      segmentTrack: segmentTrack,
      segmentSelected: segmentSelected,
      segmentSelectedText: segmentSelectedText,
      segmentUnselectedText: segmentUnselectedText,
    );
  }

  Widget _buildSegment(
    _ConversationMediaFileHeaderStyle palette, {
    bool expand = false,
  }) {
    Widget buildChip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? palette.segmentSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? palette.segmentSelectedText
                    : palette.segmentUnselectedText,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: expand ? double.infinity : 220,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.segmentTrack,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          buildChip(
            label: TIM_t('媒体'),
            selected: _tab == ConversationAssetTab.media,
            onTap: () => _switchTab(ConversationAssetTab.media),
          ),
          buildChip(
            label: TIM_t('文件'),
            selected: _tab == ConversationAssetTab.file,
            onTap: () => _switchTab(ConversationAssetTab.file),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(TUITheme theme, List<V2TimMessage> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 480 ? 4 : 3;
        return GridView.builder(
      controller: _scrollController,
      cacheExtent: 640,
      clipBehavior: Clip.hardEdge,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final message = items[index];
        final previewUrl = resolveConversationMediaPreviewUrl(message);
        final isVideo =
            message.elemType == MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
        final messageKey = message.msgID ?? message.id ?? 'media_$index';
        return RepaintBoundary(
          key: ValueKey(messageKey),
          child: GestureDetector(
            onTap: () => _onMediaItemTap(context, theme, message, items),
            child: ClipRect(
              child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                ColoredBox(
                  color: theme.weakBackgroundColor ?? const Color(0xFFF3F3F4),
                  child: previewUrl == null
                      ? Icon(Icons.image_outlined, color: theme.weakTextColor)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final cacheSize = ImageMemCacheSize.forBox(
                              constraints,
                              context,
                            );
                            if (previewUrl.startsWith('http')) {
                              return CachedNetworkImage(
                                imageUrl: previewUrl,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                memCacheWidth: cacheSize,
                                memCacheHeight: cacheSize,
                                maxWidthDiskCache: cacheSize,
                                maxHeightDiskCache: cacheSize,
                              );
                            }
                            return Image.file(
                              File(previewUrl),
                              fit: BoxFit.cover,
                              cacheWidth: cacheSize,
                              cacheHeight: cacheSize,
                            );
                          },
                        ),
                ),
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 28,
                    ),
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
      },
    );
  }

  Widget _buildFileList(TUITheme theme, List<V2TimMessage> items) {
    return ListView.separated(
      controller: _scrollController,
      cacheExtent: 640,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.weakDividerColor ?? const Color(0xFFEDEDED),
      ),
      itemBuilder: (context, index) {
        final message = items[index];
        final fileName = message.fileElem?.fileName?.trim() ?? TIM_t('[文件]');
        final timeLabel = message.timestamp != null
            ? TimeAgo().getTimeForMessage(message.timestamp!)
            : '';
        final messageKey = message.msgID ?? message.id ?? 'file_$index';
        final downloaded = _localFilePath(message) != null;
        return RepaintBoundary(
          key: ValueKey(messageKey),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            onTap: () => unawaited(_openOrDownloadFile(message)),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.weakBackgroundColor ?? const Color(0xFFF3F3F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                downloaded
                    ? Icons.insert_drive_file_rounded
                    : Icons.file_download_outlined,
                color: downloaded
                    ? (theme.primaryColor ?? const Color(0xFF1E90FF))
                    : (theme.weakTextColor ?? const Color(0xFF8E8E93)),
              ),
            ),
            title: Text(
              fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                color: theme.darkTextColor ?? Colors.black,
              ),
            ),
            trailing: messageKey == _busyFileId
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primaryColor,
                    ),
                  )
                : null,
            subtitle: timeLabel.isEmpty
                ? null
                : Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.weakTextColor,
                    ),
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    if (PlatformUtils().isWeb) {
      return TIMUIKitSearchNotSupport();
    }

    final theme = value.theme;
    final header = _headerPalette(theme);
    final pageBg = theme.chatBgColor ??
        theme.wideBackgroundColor ??
        header.appBarBackground;
    final items = _currentItems;
    final loadingEmpty = items.isEmpty &&
        (_model.conversationAssetLoading || _isFillingCurrentTab);
    final loadingMore = items.isNotEmpty && _model.conversationAssetLoading;

    final content = loadingEmpty
        ? Center(
            child: CircularProgressIndicator(
              color: theme.primaryColor,
              strokeWidth: 2,
            ),
          )
        : items.isEmpty
            ? Center(
                child: Text(
                  TIM_t('暂无数据'),
                  style: TextStyle(
                    fontSize: 15,
                    color: theme.weakTextColor,
                  ),
                ),
              )
            : Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: _tab == ConversationAssetTab.media
                        ? _buildMediaGrid(theme, items)
                        : _buildFileList(theme, items),
                  ),
                  if (loadingMore) _buildPaginationSpinner(theme),
                ],
              );

    if (widget.embedded) {
      return ColoredBox(
        color: pageBg,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: header.appBarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: header.backIconColor),
        leading: TIMUIKitBackButton(
          color: header.backIconColor,
        ),
        title: _buildSegment(header),
      ),
      body: content,
    );
  }
}
