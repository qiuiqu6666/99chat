import 'package:tencent_cloud_chat_demo/src/platform/attachment_video_gallery_io.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/chat_media_preview_builder.dart';
import 'package:tencent_cloud_chat_uikit/ui/widgets/chat_media_preview_item.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/separate_models/tui_chat_separate_view_model.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_presenter.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/media_preview_video_utils.dart';
import 'package:tencent_cloud_chat_uikit/business_logic/view_models/tui_chat_global_model.dart';
import 'package:tencent_cloud_chat_uikit/data_services/services_locatar.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_preview.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_file/open_file.dart';
import 'package:tencent_cloud_chat_demo/src/api/api_client.dart';
import 'package:tencent_cloud_chat_demo/src/models/chat_attachment.dart';
import 'package:tencent_cloud_chat_demo/src/services/chat_attachment_service_io.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_file_card.dart';
import 'package:tencent_cloud_chat_demo/src/widgets/chat_attachment_video_card.dart';

class ChatAttachmentMessageCard extends StatefulWidget {
  const ChatAttachmentMessageCard(
      {super.key,
      required this.attachment,
      this.isSelf = false,
      this.message,
      this.conversationID,
      this.chatModel});
  final ChatAttachment attachment;
  final bool isSelf;
  final V2TimMessage? message;
  final String? conversationID;
  final TUIChatSeparateViewModel? chatModel;
  @override
  State<ChatAttachmentMessageCard> createState() =>
      _ChatAttachmentMessageCardState();
}

class _ChatAttachmentMessageCardState extends State<ChatAttachmentMessageCard> {
  final service = ChatAttachmentService.instance;
  String? _local, _thumbnail;
  String _error = '';
  bool _busy = false;
  double _progress = 0;
  CancelToken? _downloadToken;
  String _owner = '';
  int _credentialGeneration = -1;
  int _probeVersion = 0;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelf && !oldWidget.isSelf) {
      unawaited(service.observeSent(widget.attachment).catchError((_) {}));
    }
    if (oldWidget.attachment.attachmentId != widget.attachment.attachmentId ||
        oldWidget.attachment.thumbnailAttachmentId !=
            widget.attachment.thumbnailAttachmentId ||
        _owner != ApiClient.instance.authenticatedUserId ||
        _credentialGeneration != ApiClient.instance.credentialGeneration) {
      _downloadToken?.cancel();
      _local = null;
      _thumbnail = null;
      _error = '';
      _busy = false;
      _progress = 0;
      _probe();
    }
  }

  bool _current(String owner, String id) =>
      mounted &&
      owner == ApiClient.instance.authenticatedUserId &&
      _credentialGeneration == ApiClient.instance.credentialGeneration &&
      id == widget.attachment.attachmentId;
  Future<void> _probe() async {
    final a = widget.attachment;
    final owner = _owner = ApiClient.instance.authenticatedUserId;
    _credentialGeneration = ApiClient.instance.credentialGeneration;
    final version = ++_probeVersion;
    try {
      final local = await service.localPath(a);
      if (!_current(owner, a.attachmentId) || version != _probeVersion) return;
      setState(() => _local = local);
      if (widget.isSelf) unawaited(service.observeSent(a).catchError((_) {}));
      if (a.kind == 'video') {
        final thumb = await service.videoThumbnail(a);
        if (_current(owner, a.attachmentId) && version == _probeVersion) {
          setState(() => _thumbnail = thumb);
        }
      }
    } catch (_) {/* Cloud cover failure must not hide a local original. */}
  }

  String get _heroTag =>
      'attachment-video:${widget.attachment.attachmentId}:${widget.attachment.referenceId}';

  Future<void> _open({bool download = false}) async {
    if (_busy) return;
    final globalModel = serviceLocator<TUIChatGlobalModel>();
    if (widget.attachment.kind == 'video' &&
        globalModel.isMessageContextMenuOverlayOpen) {
      return;
    }
    final owner = ApiClient.instance.authenticatedUserId;
    final a = widget.attachment;
    setState(() {
      _busy = true;
      _error = '';
    });
    final token = _downloadToken = CancelToken();
    try {
      if (!download && (a.kind == 'video' || a.kind == 'audio')) {
        // Legacy videos with no recoverable poster need the original once to
        // repair their local cover. Do this only on explicit playback, not while
        // paging history, and feed the complete file to the native player.
        final playback = a.kind == 'video' && _thumbnail == null
            ? ChatAttachmentPlayback(
                await service.resolveFile(a, cancelToken: token),
                local: true)
            : await service.playback(a, cancelToken: token);
        if (!mounted || !_current(owner, a.attachmentId)) return;
        if (playback.local) {
          setState(() => _local = playback.location);
          if (a.kind == 'video') unawaited(_probe());
        }
        if (a.kind == 'video') {
          final preview = attachmentVideoPreviewMessage(
              attachment: a,
              source: playback,
              original: widget.message,
              thumbnail: _thumbnail);
          installAttachmentVideoGallery();
          final gallery = buildChatMediaPreviewItems(
              originList:
                  widget.chatModel?.getGalleryOriginMessageList() ?? [preview],
              tappedMessage: widget.message ?? preview,
              types: const {ChatMediaPreviewType.video},
              heroTagBuilder: (message) =>
                  '${message.msgID ?? message.id ?? message.timestamp}');
          final convId = widget.conversationID;
          if (convId != null && convId.isNotEmpty) {
            globalModel.saveScrollBeforeMediaPreview(convId,
                anchorMessageID: widget.message?.msgID);
          }
          await pushMediaPreview(
            context: context,
            requiresOpaquePlatformView: true,
            restoreChatScrollConversationID: convId,
            child: attachmentVideoScreen(
                message: preview,
                source: playback,
                heroTag: _heroTag,
                galleryItems: gallery.items.length > 1 ? gallery.items : null,
                initialIndex: gallery.initialIndex,
                onRecover: () async {
                  final path = await service.resolveFile(a, cancelToken: token);
                  if (!mounted || !_current(owner, a.attachmentId)) return null;
                  setState(() => _local = path);
                  unawaited(_probe());
                  return attachmentVideoPreviewMessage(
                          attachment: a,
                          source: ChatAttachmentPlayback(path, local: true),
                          original: widget.message,
                          thumbnail: _thumbnail)
                      .videoElem;
                },
                onSave: () async {
                  final path = await service.resolveFile(a);
                  if (!mounted || !_current(owner, a.attachmentId)) return;
                  final localPreview = attachmentVideoPreviewMessage(
                      attachment: a,
                      source: ChatAttachmentPlayback(path, local: true),
                      original: widget.message,
                      thumbnail: _thumbnail);
                  await saveChatVideoMessage(
                      context: context,
                      message: localPreview,
                      videoElement: localPreview.videoElem!,
                      model: globalModel);
                }),
          );
          return;
        }

        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                _AttachmentPreview(attachment: a, source: playback)));
        return;
      }
      // resolveFile always rechecks the local file, including after OS cleanup.
      final path =
          await service.resolveFile(a, cancelToken: token, onProgress: (n) {
        if (_current(owner, a.attachmentId)) setState(() => _progress = n);
      });
      if (!mounted || !_current(owner, a.attachmentId)) return;
      setState(() => _local = path);
      if (a.kind == 'video') unawaited(_probe());
      if (a.kind == 'file') {
        final result = await OpenFile.open(path);
        if (result.type != ResultType.done && mounted) {
          setState(() => _error = '无法打开此类型文件');
        }
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _AttachmentPreview(
                attachment: a,
                source: ChatAttachmentPlayback(path, local: true))));
      }
    } catch (error) {
      if (_current(owner, a.attachmentId)) {
        setState(() => _error = error is ChatAttachmentException
            ? error.userMessage
            : '附件无法打开，请重试');
        if (mounted && a.kind == 'video') {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_error)));
        }
      }
    } finally {
      if (_current(owner, a.attachmentId)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _downloadToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    if (a.kind == 'video') {
      return PreviewHero(
          tag: _heroTag,
          child: ChatAttachmentVideoCard(
            thumbnail: _thumbnail == null ? null : FileImage(File(_thumbnail!)),
            sizeBytes: a.sizeBytes,
            durationMs: a.durationMs,
            videoWidth: a.width,
            videoHeight: a.height,
            busy: _busy,
            progress: _progress,
            error: _error,
            onOpen: _open,
            onPause: () => _downloadToken?.cancel(),
          ));
    }
    if (a.kind == 'file') {
      return ChatAttachmentFileCard(
        name: a.name.isEmpty ? a.label : a.name,
        sizeBytes: a.sizeBytes,
        isSelf: widget.isSelf,
        isLocal: _local != null,
        busy: _busy,
        progress: _progress,
        error: _error,
        onOpen: _open,
        onPause: () => _downloadToken?.cancel(),
      );
    }
    final imagePath = a.kind == 'image' ? _local : _thumbnail;
    return Semantics(
        label: a.preview,
        button: true,
        child: InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: widget.isSelf
                      ? const Color(0xffd9f5c5)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imagePath != null)
                      ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(imagePath),
                              height: 150,
                              width: 236,
                              fit: BoxFit.cover,
                              cacheWidth: 512,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  size: 40)))
                    else
                      Icon(
                          switch (a.kind) {
                            'video' => Icons.video_file_outlined,
                            'audio' => Icons.audio_file_outlined,
                            'image' => Icons.image_outlined,
                            _ => Icons.insert_drive_file_outlined
                          },
                          size: 36),
                    const SizedBox(height: 8),
                    Text(a.name.isEmpty ? a.label : a.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                        '${attachmentSizeLabel(a.sizeBytes)} · ${_local != null ? "已下载" : (a.kind == "audio" || a.kind == "video") ? "点击播放" : "点击下载打开"}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (_local == null &&
                        !_busy &&
                        (a.kind == 'video' || a.kind == 'audio'))
                      TextButton(
                          onPressed: () => _open(download: true),
                          child: const Text('下载后播放')),
                    if (_busy) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null),
                      TextButton(
                          onPressed: () => _downloadToken?.cancel(),
                          child: const Text('暂停下载'))
                    ],
                    if (_error.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12))),
                  ]),
            )));
  }
}

class _AttachmentPreview extends StatefulWidget {
  const _AttachmentPreview({required this.attachment, required this.source});
  final ChatAttachment attachment;
  final ChatAttachmentPlayback source;
  @override
  State<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<_AttachmentPreview> {
  Player? _player;
  VideoController? _video;
  StreamSubscription<String>? _errors;
  Timer? _sessionWatch;
  bool _refreshed = false;
  bool _refreshing = false;
  late ChatAttachmentPlayback _source;
  String _error = '';
  @override
  void initState() {
    super.initState();
    _source = widget.source;
    final owner = ApiClient.instance.authenticatedUserId;
    final generation = ApiClient.instance.credentialGeneration;
    _sessionWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (owner != ApiClient.instance.authenticatedUserId ||
          generation != ApiClient.instance.credentialGeneration) {
        _sessionWatch?.cancel();
        unawaited(_player?.stop());
        if (mounted) Navigator.of(context).pop();
      }
    });
    if (widget.attachment.kind != 'image') {
      MediaKit.ensureInitialized();
      final player = _player = Player();
      _video = VideoController(player);
      _errors = player.stream.error.listen((_) => unawaited(_playbackError()));
      unawaited(player
          .open(Media(_source.location, httpHeaders: _source.headers))
          .catchError((_) => _playbackError()));
    }
  }

  Future<void> _playbackError() async {
    if (!mounted || _refreshing) return;
    if (!_source.local && !_refreshed) {
      _refreshed = true;
      _refreshing = true;
      try {
        final position = _player!.state.position;
        final source =
            await ChatAttachmentService.instance.playback(widget.attachment);
        if (!mounted) return;
        _source = source;
        await _player!
            .open(Media(source.location, httpHeaders: source.headers));
        await _player!.seek(position);
        return;
      } catch (_) {
        // One fresh grant per playback failure; avoid an unbounded retry loop.
      } finally {
        _refreshing = false;
      }
    }
    if (mounted) setState(() => _error = '播放失败，请返回重试或下载后打开');
  }

  @override
  void dispose() {
    _sessionWatch?.cancel();
    unawaited(_errors?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.attachment.name), actions: [
          if (_source.local)
            IconButton(
                tooltip: '其他应用打开',
                onPressed: () => OpenFile.open(_source.location),
                icon: const Icon(Icons.open_in_new))
        ]),
        body: widget.attachment.kind == 'image'
            ? Center(
                child: InteractiveViewer(
                    maxScale: 8,
                    child:
                        Image.file(File(_source.location), cacheWidth: 2048)))
            : _error.isNotEmpty
                ? Center(child: Text(_error))
                : Center(
                    child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Video(controller: _video!))),
      );
}
