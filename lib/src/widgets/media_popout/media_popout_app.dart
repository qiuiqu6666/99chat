import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:tencent_chat_i18n_tool/tencent_chat_i18n_tool.dart';
import 'package:tencent_cloud_chat_demo/src/provider/local_setting.dart';
import 'package:tencent_cloud_chat_demo/src/provider/presence_provider.dart';
import 'package:tencent_cloud_chat_demo/src/provider/theme.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/media_popout/desktop_windows_image_clipboard.dart';
import 'package:tencent_cloud_chat_demo/utils/app_material_theme.dart';
import 'package:tencent_cloud_chat_demo/utils/media_url_resolver.dart';
import 'package:tencent_cloud_chat_demo/utils/theme.dart';
import 'package:tencent_cloud_chat_demo/utils/toast.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart'
    if (dart.library.html) 'package:tencent_cloud_chat_sdk/web/compatible_models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_img_trace.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_message_preview_image_resolver.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_gallery_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_gallery_item.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/image_screen.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_backdrop_scope.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/media_preview_save_notice.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/video_screen.dart';

class MediaPopoutApp extends StatelessWidget {
  const MediaPopoutApp({
    super.key,
    required this.windowId,
    required this.argumentJson,
  });

  final int windowId;
  final String argumentJson;

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DefaultThemeData()),
          ChangeNotifierProvider(create: (_) => LocalSetting(autoLoad: false)),
          ChangeNotifierProvider(create: (_) => PresenceProvider()),
        ],
        child: _MediaPopoutMaterialApp(
          windowId: windowId,
          argumentJson: argumentJson,
        ),
      ),
    );
  }
}

class _MediaPopoutMaterialApp extends StatefulWidget {
  const _MediaPopoutMaterialApp({
    required this.windowId,
    required this.argumentJson,
  });

  final int windowId;
  final String argumentJson;

  @override
  State<_MediaPopoutMaterialApp> createState() =>
      _MediaPopoutMaterialAppState();
}

class _MediaPopoutMaterialAppState extends State<_MediaPopoutMaterialApp> {
  late Map<String, dynamic> _payload;
  int _generation = 0;
  int _navEpoch = 0;
  bool _homeAlive = false;
  bool _closingWindow = false;

  @override
  void initState() {
    super.initState();
    _payload = _decode(widget.argumentJson);
    ChatImgTrace.log(
      '[ChatImg] event=popout_app_init items=${_itemCount(_payload)}',
    );
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'setPayload') {
        _applyPayload(call.arguments);
      } else if (call.method == 'windowShown') {
        _requestPresent();
      }
      return null;
    });
    unawaited(
      DesktopMultiWindow.invokeMethod(0, 'mediaPopoutReady', widget.windowId),
    );
  }

  @override
  void dispose() {
    DesktopMultiWindow.setMethodHandler(null);
    super.dispose();
  }

  void _applyPayload(dynamic raw) {
    if (!mounted) {
      return;
    }
    final next = _decode(raw);
    ChatImgTrace.log(
      '[ChatImg] event=popout_set_payload items=${_itemCount(next)} '
      'url0=${_firstUrl(next).isNotEmpty} orig0=${_firstOrig(next).isNotEmpty}',
    );
    setState(() {
      _payload = next;
      _generation++;
      if (!_homeAlive) {
        _navEpoch++;
      }
    });
    _requestPresent();
  }

  void _onHomeLifecycle(bool alive) {
    _homeAlive = alive;
  }

  void _requestPresent() {
    if (!mounted) {
      return;
    }
    final binding = WidgetsBinding.instance;
    binding.ensureVisualUpdate();
    binding.scheduleWarmUpFrame();
  }

  Map<String, dynamic> _decode(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  int _itemCount(Map<String, dynamic> payload) {
    final raw = payload['items'];
    return raw is List ? raw.length : 0;
  }

  String _firstUrl(Map<String, dynamic> payload) {
    final raw = payload['items'];
    if (raw is! List || raw.isEmpty || raw.first is! Map) {
      return '';
    }
    return '${(raw.first as Map)['url'] ?? ''}';
  }

  String _firstOrig(Map<String, dynamic> payload) {
    final raw = payload['items'];
    if (raw is! List || raw.isEmpty || raw.first is! Map) {
      return '';
    }
    return '${(raw.first as Map)['originalUrl'] ?? ''}';
  }

  Future<void> _closeWindow() async {
    if (_closingWindow) {
      return;
    }
    _closingWindow = true;
    try {
      await WindowController.fromWindowId(widget.windowId).hide();
    } catch (_) {}
    _closingWindow = false;
  }

  @override
  Widget build(BuildContext context) {
    final themeModel = context.watch<DefaultThemeData>();
    return MaterialApp(
      key: ValueKey(_navEpoch),
      debugShowCheckedModeBanner: false,
      color: MediaPreviewBackdropScope.desktopPopout,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: LocaleSettings.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: themeModel.materialThemeMode,
      theme: buildAppMaterialTheme(DefTheme.blueTheme, isDark: false),
      darkTheme: buildAppMaterialTheme(DefTheme.darkTheme, isDark: true),
      home: MediaPreviewBackdropScope(
        color: MediaPreviewBackdropScope.desktopPopout,
        desktopOverlayChrome: true,
        child: _MediaPopoutPage(
          key: ValueKey(_generation),
          payload: _payload,
          onRequestClose: _closeWindow,
          onLifecycle: _onHomeLifecycle,
        ),
      ),
    );
  }
}

class _MediaPopoutPage extends StatefulWidget {
  const _MediaPopoutPage({
    super.key,
    required this.payload,
    required this.onRequestClose,
    required this.onLifecycle,
  });

  final Map<String, dynamic> payload;
  final Future<void> Function() onRequestClose;
  final void Function(bool alive) onLifecycle;

  @override
  State<_MediaPopoutPage> createState() => _MediaPopoutPageState();
}

class _MediaPopoutPageState extends State<_MediaPopoutPage> {
  @override
  void initState() {
    super.initState();
    widget.onLifecycle(true);
  }

  @override
  void dispose() {
    widget.onLifecycle(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MediaPreviewBackdropScope.desktopPopout,
      body: _MediaPopoutBody(
        payload: widget.payload,
        onRequestClose: widget.onRequestClose,
      ),
    );
  }
}

class _MediaPopoutBody extends StatelessWidget {
  const _MediaPopoutBody({
    super.key,
    required this.payload,
    required this.onRequestClose,
  });

  final Map<String, dynamic> payload;
  final Future<void> Function() onRequestClose;

  List<Map<String, dynamic>> get _items {
    final raw = payload['items'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  int get _initialIndex {
    final raw = payload['initialIndex'];
    final index = raw is int ? raw : int.tryParse('$raw') ?? 0;
    final last = _items.isEmpty ? 0 : _items.length - 1;
    return index.clamp(0, last);
  }

  bool get _downloadOnly => payload['downloadOnly'] == true;
  bool get _allowForward {
    if (_downloadOnly) {
      return false;
    }
    final raw = payload['allowForward'];
    if (raw == false || raw == 0 || raw == 'false') {
      return false;
    }
    return true;
  }
  String get _source => '${payload['source'] ?? ''}';

  ConvType get _conversationType {
    final raw = payload['conversationType'];
    final index = raw is int ? raw : int.tryParse('$raw') ?? ConvType.c2c.index;
    if (index < 0 || index >= ConvType.values.length) {
      return ConvType.c2c;
    }
    return ConvType.values[index];
  }

  String get _conversationID => '${payload['conversationID'] ?? ''}';

  bool get _canShowChatActions =>
      _source == 'chat' && _conversationID.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return const Center(
        child: Text('No media', style: TextStyle(color: Colors.white70)),
      );
    }
    final hasImage = items.any((item) => item['type'] != 'video');
    final hasVideo = items.any((item) => item['type'] == 'video');
    if (hasImage && hasVideo) {
      final gallery = _galleryItems(context, items);
      if (gallery.isEmpty) {
        return const Center(
          child: Text('No media', style: TextStyle(color: Colors.white70)),
        );
      }
      final initial = _initialIndex.clamp(0, gallery.length - 1);
      return ChatMediaGalleryScreen(
        items: gallery,
        initialIndex: initial,
        sourceMessage: gallery[initial].message,
        enableHero: false,
        onClosing: (_, __) => unawaited(onRequestClose()),
        onOpenMedia: _canShowChatActions ? _showAllImages : null,
        onGoToMessage: _canShowChatActions ? _goToMessage : null,
      );
    }
    if (hasVideo) {
      return _buildVideo(context, items);
    }
    return _buildImage(context, items);
  }

  Widget _buildImage(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final galleryItems = <ImageGalleryItem>[];
    for (final item in items) {
      final message = _messageFrom(item);
      final preview = _previewForItem(item, message);
      final provider = preview.provider;
      if (provider == null) {
        continue;
      }
      galleryItems.add(
        ImageGalleryItem(
          imageProvider: provider,
          placeholderImageProvider: preview.placeholder,
          originalImageProvider: preview.original,
          heroTag: '${item['heroTag'] ?? ''}',
          messageID: '${item['messageID'] ?? ''}',
          headerTitle: '${item['headerTitle'] ?? ''}',
          headerSubtitle: '${item['headerSubtitle'] ?? ''}',
          sourceMessage: message,
          downloadFn: () => _saveItem(context, item),
          copyFn: () => _copyItem(context, item),
          forwardFn: _allowForward
              ? () => _forwardItem(context, item)
              : null,
          deleteFn: _canShowChatActions ? () => _deleteItem(item) : null,
        ),
      );
    }
    if (galleryItems.isEmpty) {
      final first = items[_initialIndex];
      if (_isSvg(first)) {
        return _svgPreview(first);
      }
      return const Center(
        child: Text('No image', style: TextStyle(color: Colors.white70)),
      );
    }
    final initial = _initialIndex.clamp(0, galleryItems.length - 1);
    final current = galleryItems[initial];
    return ImageScreen(
      imageProvider: current.imageProvider,
      heroTag: current.heroTag,
      headerTitle: current.headerTitle,
      headerSubtitle: current.headerSubtitle,
      messageID: current.messageID,
      sourceMessage: current.sourceMessage,
      galleryItems: galleryItems,
      initialIndex: initial,
      forceGalleryMode: true,
      enableHero: false,
      downloadOnly: _downloadOnly,
      fitTallImagesToScreenWidth: false,
      downloadFn: current.downloadFn,
      copyFn: current.copyFn,
      forwardFn: current.forwardFn,
      deleteFn: current.deleteFn,
      onOpenMedia: _canShowChatActions ? _showAllImages : null,
      onGoToMessage: _canShowChatActions ? _goToMessage : null,
      onClosing: (_, __) => unawaited(onRequestClose()),
    );
  }

  Widget _buildVideo(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final videoItems = <ChatMediaPreviewItem>[];
    for (final item in items) {
      if (item['type'] != 'video') {
        continue;
      }
      videoItems.add(_chatItem(context, item));
    }
    if (videoItems.isEmpty) {
      return const Center(
        child: Text('No video', style: TextStyle(color: Colors.white70)),
      );
    }
    final initial = _initialIndex.clamp(0, videoItems.length - 1);
    final current = videoItems[initial];
    final videoElem = current.videoElement;
    if (videoElem == null) {
      return const Center(
        child: Text('No video', style: TextStyle(color: Colors.white70)),
      );
    }
    return VideoScreen(
      message: current.message,
      heroTag: current.heroTag,
      videoElement: videoElem,
      preferOnlinePlayback: true,
      forwardFn: current.forwardFn,
      galleryItems: videoItems.length > 1 ? videoItems : null,
      initialIndex: initial,
      onClosed: () => unawaited(onRequestClose()),
    );
  }

  ChatMediaPreviewItem _chatItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final isVideo = item['type'] == 'video';
    final parsed = _messageFrom(item);
    final message = parsed ?? _syntheticMessage(item);
    final preview = isVideo ? null : _previewForItem(item, parsed);
    return ChatMediaPreviewItem(
      message: message,
      type: isVideo ? ChatMediaPreviewType.video : ChatMediaPreviewType.image,
      heroTag: '${item['heroTag'] ?? ''}',
      messageID: '${item['messageID'] ?? ''}',
      headerTitle: '${item['headerTitle'] ?? ''}',
      headerSubtitle: '${item['headerSubtitle'] ?? ''}',
      imageProvider: isVideo ? null : preview?.provider,
      placeholderImageProvider: isVideo ? null : preview?.placeholder,
      videoElement: isVideo ? _videoElem(item, message) : null,
      downloadFn: () => _saveItem(context, item),
      copyFn: () => _copyItem(context, item),
      forwardFn: _allowForward ? () => _forwardItem(context, item) : null,
      deleteFn: _canShowChatActions ? () => _deleteItem(item) : null,
    );
  }

  List<ChatMediaPreviewItem> _galleryItems(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    return [for (final item in items) _chatItem(context, item)];
  }

  bool _isSvg(Map<String, dynamic> item) {
    final asset = '${item['assetPath'] ?? ''}'.toLowerCase();
    return asset.endsWith('.svg');
  }

  Widget _svgPreview(Map<String, dynamic> item) {
    final asset = '${item['assetPath'] ?? ''}';
    final package = '${item['assetPackage'] ?? ''}';
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SvgPicture.asset(
            asset,
            package: package.isEmpty ? null : package,
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            onPressed: () => unawaited(onRequestClose()),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }

  ({
    ImageProvider? provider,
    ImageProvider? placeholder,
    ImageProvider? original,
  }) _previewForItem(
    Map<String, dynamic> item,
    V2TimMessage? message,
  ) {
    try {
      if (message != null &&
          message.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
        final original = _imageProvider(item, preferOriginal: true) ??
            ChatMessagePreviewImageResolver.resolveOriginal(message);
        final preview = ChatMessagePreviewImageResolver.resolve(message);
        final placeholder =
            ChatMessagePreviewImageResolver.resolvePlaceholder(message);
        final first = placeholder ?? preview;
        ChatImgTrace.log(
          '[ChatImg] event=preview_popout_tier '
          'origin=${original != null} big=${preview != null} '
          'small=${placeholder != null} '
          'using=${placeholder != null ? 'small' : preview != null ? 'big' : 'none'} '
          'originQueued=${original != null}',
        );
        if (first != null || original != null) {
          return (
            provider: first ?? original,
            placeholder: ChatMessagePreviewImageResolver.isSameImageProvider(
              placeholder,
              first ?? original,
            )
                ? null
                : placeholder,
            original: original,
          );
        }
      }
    } catch (error) {
      ChatImgTrace.log(
        '[ChatImg] event=preview_popout_tier_error error=$error',
      );
    }
    ChatImgTrace.log(
      '[ChatImg] event=preview_popout_fallback '
      'msg=${message != null} elem=${message?.elemType} '
      'origUrl=${'${item['originalUrl'] ?? ''}'.isNotEmpty} '
      'originLocal=${'${item['originalLocalPath'] ?? ''}'.isNotEmpty} '
      'previewLocal=${'${item['previewLocalPath'] ?? ''}'.isNotEmpty} '
      'local=${'${item['localPath'] ?? ''}'.isNotEmpty}',
    );
    final first = _imageProvider(item, preferOriginal: false);
    final original = _imageProvider(item, preferOriginal: true);
    return (
      provider: first ?? original,
      placeholder: first,
      original: original,
    );
  }

  ImageProvider? _imageProvider(
    Map<String, dynamic> item, {
    bool preferOriginal = false,
  }) {
    final asset = '${item['assetPath'] ?? ''}';
    if (asset.isNotEmpty && !_isSvg(item)) {
      final package = '${item['assetPackage'] ?? ''}';
      return AssetImage(asset, package: package.isEmpty ? null : package);
    }
    if (preferOriginal) {
      final originLocal = '${item['originalLocalPath'] ?? ''}';
      if (originLocal.isNotEmpty && File(originLocal).existsSync()) {
        return FileImage(File(originLocal));
      }
      final original = '${item['originalUrl'] ?? ''}';
      if (original.isNotEmpty) {
        return _networkImage(original);
      }
    }
    final previewLocal = '${item['previewLocalPath'] ?? ''}';
    if (previewLocal.isNotEmpty && File(previewLocal).existsSync()) {
      return FileImage(File(previewLocal));
    }
    final small = '${item['smallUrl'] ?? ''}';
    if (small.isNotEmpty) {
      return _networkImage(small);
    }
    final big = '${item['bigUrl'] ?? ''}';
    if (big.isNotEmpty) {
      return _networkImage(big);
    }
    final local = '${item['localPath'] ?? ''}';
    if (local.isNotEmpty && File(local).existsSync()) {
      return FileImage(File(local));
    }
    final original = '${item['originalUrl'] ?? ''}';
    if (original.isNotEmpty) {
      return _networkImage(original);
    }
    final url = '${item['url'] ?? ''}';
    if (url.isNotEmpty) {
      return _networkImage(url);
    }
    return null;
  }

  ImageProvider? _networkImage(String url) {
    if (url.isEmpty) {
      return null;
    }
    final resolved = MediaUrlResolver.resolve(url) ?? url;
    return NetworkImage(
      resolved,
      headers: MediaUrlResolver.authHeadersFor(resolved),
    );
  }

  V2TimMessage? _messageFrom(Map<String, dynamic> item) {
    final raw = item['message'];
    if (raw is Map) {
      try {
        return V2TimMessage.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }
    return null;
  }

  V2TimMessage _syntheticMessage(Map<String, dynamic> item) {
    if (item['type'] == 'video') {
      return V2TimMessage(
        elemType: MessageElemType.V2TIM_ELEM_TYPE_VIDEO,
        videoElem: _videoElem(item, null),
      );
    }
    return V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE);
  }

  V2TimVideoElem _videoElem(
    Map<String, dynamic> item,
    V2TimMessage? message,
  ) {
    final existing = message?.videoElem;
    final videoUrl = '${item['videoUrl'] ?? existing?.videoUrl ?? ''}';
    final localVideoUrl =
        '${item['localVideoUrl'] ?? existing?.localVideoUrl ?? ''}';
    final videoPath = '${item['videoPath'] ?? existing?.videoPath ?? ''}';
    return V2TimVideoElem(
      videoUrl: videoUrl.isEmpty ? existing?.videoUrl : videoUrl,
      localVideoUrl:
          localVideoUrl.isEmpty ? existing?.localVideoUrl : localVideoUrl,
      videoPath: videoPath.isEmpty ? existing?.videoPath : videoPath,
      snapshotUrl: '${item['snapshotUrl'] ?? existing?.snapshotUrl ?? ''}'
              .isEmpty
          ? existing?.snapshotUrl
          : '${item['snapshotUrl']}',
      snapshotPath: '${item['snapshotPath'] ?? existing?.snapshotPath ?? ''}'
              .isEmpty
          ? existing?.snapshotPath
          : '${item['snapshotPath']}',
    );
  }

  Future<void> _saveItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final saved = await _saveAs(item);
    if (context.mounted) {
      MediaPreviewSaveNotice.show(context, success: saved);
    }
  }

  Future<bool> _saveAs(Map<String, dynamic> item) async {
    final name = _fileNameFor(item);
    final local = _bestLocalPath(item);
    try {
      if (local.isNotEmpty) {
        final dest = await FilePicker.platform.saveFile(
          dialogTitle: TIM_t('另存为'),
          fileName: name,
        );
        if (dest == null || dest.trim().isEmpty) {
          return false;
        }
        await File(local).copy(dest);
        return true;
      }
      final bytes = await _itemBytes(item);
      if (bytes == null || bytes.isEmpty) {
        return false;
      }
      final dest = await FilePicker.platform.saveFile(
        dialogTitle: TIM_t('另存为'),
        fileName: name,
        bytes: bytes,
      );
      return dest != null && dest.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    var copied = false;
    try {
      final bytes = await _itemBytes(item);
      if (bytes != null && bytes.isNotEmpty) {
        copied = await copyBytesToWindowsImageClipboard(bytes);
        if (copied) {
          ChatImgTrace.log('[ChatImg] event=popout_copy local=true');
        }
      }
      if (!copied) {
        copied = await _notifyHost('copy', {
          'localPath': _bestLocalPath(item),
          'url':
              '${item['originalUrl'] ?? item['url'] ?? item['originalPath'] ?? ''}',
        });
        ChatImgTrace.log('[ChatImg] event=popout_copy host=$copied');
      }
    } catch (error) {
      ChatImgTrace.log('[ChatImg] event=popout_copy_error error=$error');
    }
    if (!context.mounted) {
      return;
    }
    MediaPreviewSaveNotice.show(
      context,
      success: copied,
      message: copied ? '复制成功' : '复制失败',
    );
  }

  Future<void> _goToMessage(String? messageID, V2TimMessage? message) async {
    await _notifyHost('goToMessage', {
      'messageID': messageID ?? message?.msgID ?? '',
      'localID': message?.id ?? '',
      'seq': message?.seq ?? '',
      'timestamp': message?.timestamp,
      'sender': message?.sender ?? message?.userID ?? '',
      'elemType': message?.elemType,
    });
    await onRequestClose();
  }

  Future<void> _showAllImages() async {
    await _notifyHost('showAllImages', {});
    await onRequestClose();
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final message = _messageFrom(item);
    await _notifyHost('delete', {
      'messageID': message?.msgID ?? '${item['messageID'] ?? ''}',
      'localID': message?.id ?? '',
      'seq': message?.seq ?? '',
    });
  }

  Future<bool> _notifyHost(
    String action,
    Map<String, dynamic> extra,
  ) async {
    try {
      ChatImgTrace.log('[ChatImg] event=popout_notify_host action=$action');
      final result = await DesktopMultiWindow.invokeMethod(
        0,
        'mediaPopoutHostAction',
        jsonEncode(<String, dynamic>{
          'action': action,
          'conversationID': _conversationID,
          'conversationType': _conversationType.index,
          ...extra,
        }),
      );
      return result == true || result == 1 || result == 'true';
    } catch (error) {
      ChatImgTrace.log(
        '[ChatImg] event=popout_notify_host_error action=$action error=$error',
      );
      return false;
    }
  }

  String _fileNameFor(Map<String, dynamic> item) {
    final id = '${item['messageID'] ?? ''}'.trim();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (item['type'] == 'video') {
      return 'video_${id.isEmpty ? stamp : id}.mp4';
    }
    return 'image_${id.isEmpty ? stamp : id}.jpg';
  }

  String _bestLocalPath(Map<String, dynamic> item) {
    for (final key in [
      'originalLocalPath',
      'localPath',
      'previewLocalPath',
      'videoPath',
      'localVideoUrl',
    ]) {
      final path = '${item[key] ?? ''}'.trim();
      if (path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    }
    return '';
  }

  Future<Uint8List?> _itemBytes(Map<String, dynamic> item) async {
    final local = _bestLocalPath(item);
    if (local.isNotEmpty) {
      return Uint8List.fromList(await File(local).readAsBytes());
    }
    return _bytesFromUrlOrPath(
      '${item['originalUrl'] ?? item['url'] ?? item['originalPath'] ?? ''}',
    );
  }

  Future<void> _forwardItem(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    await onRequestClose();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final message = _messageFrom(item);
    final ok = await _notifyHost('forward', {
      'messageID': message?.msgID ?? '${item['messageID'] ?? ''}',
      'localPath': _bestLocalPath(item),
      'url':
          '${item['originalUrl'] ?? item['url'] ?? item['originalPath'] ?? ''}',
    });
    if (!ok) {
      ToastUtils.toast(TIM_t('转发失败'));
    }
  }

  Future<Uint8List?> _bytesFromUrlOrPath(String raw) async {
    final path = raw.trim();
    if (path.isEmpty) {
      return null;
    }
    try {
      if (path.startsWith('assets/')) {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List();
      }
      final resolved = MediaUrlResolver.resolve(path) ?? path;
      if (resolved.startsWith('http')) {
        final response = await Dio().get<List<int>>(
          resolved,
          options: Options(
            responseType: ResponseType.bytes,
            headers: MediaUrlResolver.authHeadersFor(resolved),
          ),
        );
        final data = response.data;
        return data == null ? null : Uint8List.fromList(data);
      }
      final file = File(resolved);
      if (!file.existsSync()) {
        return null;
      }
      return Uint8List.fromList(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }
}
